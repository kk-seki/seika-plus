/*
067_返品_仕入先へと石岡への戻し.sql（v1.199-c163）

目的：
 ② 入庫したQRロットを仕入先・産地へ返すとき、QR出庫の出庫先に「返品」を選べるようにする（納品先マスタに「返品」を足す）。
    出庫の記録は今までと同じ（区分＝出庫、出庫先＝返品）。日量・分析・出荷予定との比べ・伝票には入れない（アプリ側）。
 ③ 本社・埼玉・深谷などから返ってきた分を、元の石岡のロットに戻す（石岡の入荷日はそのまま）。
    ・どの出庫の分が返ってきたかを選び、返品日・数量（規格別ロットは規格ごと）・メモを入れる。戻せるのは出した数まで。
    ・石岡の在庫履歴の区分は「返品入庫」（出庫先の欄に返ってきた元の出庫先、メモに返品日）。
    ・本社から返ってきたときは、本社の在庫も同時に減らす。本社で受け入れ済みなら本社の履歴に「出庫（出庫先：石岡へ返品）」、
      まだ入荷待ちなら入荷予定の数を減らす（全部戻したら入荷待ちを取消）。下処理で使う予定の分は返品できない。
    ・QRで探すときは、石岡のQR・ロット番号のほか、本社で貼ったQR・ロット番号でも探せる。
    ・登録した返品は取り消せる（石岡の在庫に返品分が残っているときだけ。本社の分も元に戻す）。
    返品を登録・取り消しできるのは管理者・青果社員。見るのはログインしている人。

前提：001〜066 を実行済みであること（066 がなくても動きますが、出庫先の「返品」は納品先マスタで手で足してください）。
何度実行しても同じ結果になります。今までの在庫・ロット・履歴は変わりません。

元に戻すとき：
  drop function if exists public.list_qr_returnable_v1199c163(text, date, date, text);
  drop function if exists public.return_qr_to_ishioka_v1199c163(uuid, uuid, numeric, date, text, jsonb);
  drop function if exists public.cancel_qr_return_v1199c163(uuid, uuid, text);
  drop function if exists public.list_qr_returns_v1199c163(integer);
  drop function if exists public.qr_return_done_v1199c163(uuid);
  drop function if exists public.qr_return_grade_left_v1199c163(uuid);
  drop table if exists public.qr_returns_v1199c163;
  delete from public.dest_master_v1199c160 where name = '返品';
*/
begin;

-- 1) 在庫履歴の区分に「返品入庫」を足す（今ある区分はそのまま残す）
do $do$
declare v_def text; v_vals text[];
begin
  select pg_get_constraintdef(c.oid) into v_def from pg_constraint c
   where c.conrelid = 'public.qr_lot_movements'::regclass and c.conname = 'qr_lot_movements_movement_type_check';
  if v_def is null or position('返品入庫' in v_def) > 0 then return; end if;
  select array_agg(m[1]) into v_vals from regexp_matches(v_def, '''([^'']+)''', 'g') as m;
  v_vals := v_vals || array['返品入庫'];
  execute 'alter table public.qr_lot_movements drop constraint qr_lot_movements_movement_type_check';
  execute format('alter table public.qr_lot_movements add constraint qr_lot_movements_movement_type_check check (movement_type = any (%L::text[]))', v_vals);
end
$do$;

-- 2) 出庫先「返品」（仕入先・産地へ返す）
do $do$
begin
  if to_regclass('public.dest_master_v1199c160') is not null then
    insert into public.dest_master_v1199c160(name, formal, kind, group_name, outbound, weight, sort_order)
    values ('返品', '仕入先・産地への返品', '内', '社内', true, false, 10)
    on conflict (name) do nothing;
  end if;
end
$do$;

-- 3) 石岡へ戻した返品の記録
create table if not exists public.qr_returns_v1199c163(
  id uuid primary key default gen_random_uuid(),
  operation_id uuid not null unique,
  source_movement_id uuid not null references public.qr_lot_movements(id),
  return_movement_id uuid references public.qr_lot_movements(id),
  lot_id uuid not null references public.qr_lots(id),
  qr_key text not null,
  lot_no text,
  item_name text not null,
  from_destination text not null,
  qty numeric not null check (qty > 0),
  unit text,
  weight numeric,
  grades jsonb not null default '[]'::jsonb,
  return_date date not null,
  memo text not null default '',
  hq_lot_id uuid,
  hq_qty numeric,
  hq_action text not null default '' check (hq_action in ('','在庫から減らす','入荷予定を減らす')),
  hq_movement_id uuid,
  created_by uuid,
  created_by_name text not null default '',
  created_at timestamptz not null default now(),
  cancelled_at timestamptz,
  cancelled_by_name text,
  cancel_reason text,
  cancel_operation_id uuid unique
);
create index if not exists qr_returns_v1199c163_source_idx on public.qr_returns_v1199c163(source_movement_id);
create index if not exists qr_returns_v1199c163_time_idx on public.qr_returns_v1199c163(created_at desc);
alter table public.qr_returns_v1199c163 enable row level security;
revoke all on public.qr_returns_v1199c163 from public, anon, authenticated;
grant all on public.qr_returns_v1199c163 to service_role;

-- 戻した数（取り消したものは数えない）
create or replace function public.qr_return_done_v1199c163(p_movement_id uuid)
returns numeric language sql stable security definer set search_path to 'pg_catalog','public'
as $f$
  select coalesce(sum(qty), 0) from public.qr_returns_v1199c163 where source_movement_id = p_movement_id and cancelled_at is null
$f$;

-- 規格ごとの出した数（出庫の operation_meta.grades はマイナスの増減）と戻した数
create or replace function public.qr_return_grade_left_v1199c163(p_movement_id uuid)
returns jsonb language sql stable security definer set search_path to 'pg_catalog','public'
as $f$
  with shipped as (
    select g->>'grade' as grade, sum(abs((g->>'delta')::numeric)) as qty
      from public.qr_lot_movements m,
           jsonb_array_elements(case when jsonb_typeof(m.operation_meta->'grades') = 'array' then m.operation_meta->'grades' else '[]'::jsonb end) g
     where m.id = p_movement_id
     group by 1
  ), done as (
    select g->>'grade' as grade, sum((g->>'qty')::numeric) as qty
      from public.qr_returns_v1199c163 r, jsonb_array_elements(r.grades) g
     where r.source_movement_id = p_movement_id and r.cancelled_at is null
     group by 1
  )
  select coalesce(jsonb_agg(jsonb_build_object('grade', s.grade, 'shipped', s.qty, 'left', s.qty - coalesce(d.qty, 0)) order by s.grade), '[]'::jsonb)
    from shipped s left join done d on d.grade = s.grade
$f$;

-- 4) 戻せる出庫の一覧（出庫先・期間・QRで絞る。廃棄・返品・取消済みは出さない）
create or replace function public.list_qr_returnable_v1199c163(p_destination text, p_from date, p_to date, p_qr_key text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','public'
as $f$
declare v_from date := coalesce(p_from, (now() at time zone 'Asia/Tokyo')::date - 14);
        v_to date := coalesce(p_to, (now() at time zone 'Asia/Tokyo')::date);
        v_key text := nullif(btrim(coalesce(p_qr_key, '')), '');
        v_dest text := nullif(btrim(coalesce(p_destination, '')), '');
begin
  perform public.seika_require_role_v1240(array['admin','worker','buyer','sales','clerk','viewer','office_viewer']);
  if v_to < v_from then raise exception '期間の始まりと終わりを確かめてください' using errcode = '22023'; end if;
  if v_to - v_from > 120 then raise exception '期間は120日までにしてください' using errcode = '22023'; end if;
  return coalesce((
    select jsonb_agg(x order by x->>'occurred_at' desc)
      from (
        select jsonb_build_object(
          'movement_id', m.id, 'operation_id', m.operation_id, 'occurred_at', m.occurred_at,
          'out_date', (m.occurred_at at time zone 'Asia/Tokyo')::date,
          'destination', m.destination, 'lot_id', m.lot_id, 'qr_key', m.qr_key, 'lot_no', coalesce(m.lot_no, l.lot_no),
          'item_name', coalesce(m.item_name, l.item_name), 'origin', coalesce(m.origin, l.origin), 'supplier', coalesce(m.supplier, l.supplier),
          'received_date', l.received_date, 'unit', coalesce(m.unit, l.unit), 'container_type', coalesce(m.container_type, l.container_type),
          'qty', m.qty, 'weight', m.weight, 'returned', public.qr_return_done_v1199c163(m.id),
          'left', m.qty - public.qr_return_done_v1199c163(m.id),
          'grades', public.qr_return_grade_left_v1199c163(m.id),
          'lot_current_qty', l.current_qty, 'lot_active', coalesce(l.active, true),
          'hq', (select jsonb_build_object('lot_id', h.id, 'lot_no', h.lot_no, 'status', h.status, 'unit', h.unit,
                        'current_qty', h.current_qty, 'planned_qty', h.planned_qty, 'planned_count', h.planned_count)
                   from public.hq_lots_v1400 h where h.source_movement_id = m.id)
        ) as x
          from public.qr_lot_movements m
          join public.qr_lots l on l.id = m.lot_id
         where m.movement_type = '出庫'
           and m.cancelled_at is null
           and btrim(coalesce(m.destination, '')) not in ('', '廃棄', '返品')
           and (v_dest is null or btrim(m.destination) = v_dest)
           and (v_key is not null or (m.occurred_at at time zone 'Asia/Tokyo')::date between v_from and v_to)
           and (v_key is null or m.qr_key = v_key or l.qr_key = v_key or l.lot_no = v_key
                or exists (select 1 from public.hq_lots_v1400 h where h.source_movement_id = m.id and (h.qr_key = v_key or h.lot_no = v_key)))
         order by m.occurred_at desc
         limit 500
      ) t
  ), '[]'::jsonb);
end
$f$;

-- 5) 返品を石岡の在庫に戻す
create or replace function public.return_qr_to_ishioka_v1199c163(
  p_operation_id uuid, p_movement_id uuid, p_qty numeric, p_return_date date, p_memo text default '', p_grades jsonb default '[]'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public'
as $f$
declare
  v_profile public.profiles%rowtype; v_src public.qr_lot_movements%rowtype; v_lot public.qr_lots%rowtype;
  v_mov public.qr_lot_movements%rowtype; v_ret public.qr_returns_v1199c163%rowtype; v_hq public.hq_lots_v1400%rowtype;
  v_today date := (now() at time zone 'Asia/Tokyo')::date; v_left numeric; v_before numeric; v_after numeric;
  v_before_w numeric; v_add_w numeric; v_after_w numeric; v_grades jsonb := '[]'::jsonb; v_grade_left jsonb; v_grade_sum numeric := 0;
  v_has_grades boolean; v_hq_qty numeric; v_hq_after numeric; v_hq_available numeric; v_hq_action text := ''; v_hq_mov uuid;
  v_memo text := btrim(coalesce(p_memo, '')); v_line text; r record;
begin
  v_profile := public.trimming_require_role(array['admin','worker']);
  if p_operation_id is null or p_movement_id is null then raise exception '返品する出庫を選んでください' using errcode = '22023'; end if;
  perform pg_advisory_xact_lock(hashtext('qr_return_v1199c163:' || p_operation_id::text));
  select * into v_ret from public.qr_returns_v1199c163 where operation_id = p_operation_id;
  if found then
    if v_ret.source_movement_id <> p_movement_id or v_ret.qty <> p_qty then
      return jsonb_build_object('ok', false, 'idempotency_conflict', true, 'message', '同じ操作IDで違う内容が送られました。画面を開き直してください。');
    end if;
    return jsonb_build_object('ok', true, 'idempotent', true, 'return_id', v_ret.id, 'movement_id', v_ret.return_movement_id);
  end if;
  if p_qty is null or p_qty <= 0 or p_qty::text in ('NaN','Infinity','-Infinity') then raise exception '戻す数量を入れてください' using errcode = '22023'; end if;
  if p_return_date is null then raise exception '返品日を入れてください' using errcode = '22023'; end if;
  if p_return_date > v_today then raise exception '返品日に先の日付は入れられません' using errcode = '22023'; end if;
  if char_length(v_memo) > 300 then raise exception 'メモは300文字までにしてください' using errcode = '22023'; end if;

  select * into v_src from public.qr_lot_movements where id = p_movement_id for update;
  if not found then raise exception '元の出庫が見つかりません' using errcode = 'P0002'; end if;
  if v_src.movement_type <> '出庫' or v_src.cancelled_at is not null then raise exception 'この出庫は取り消されているため、返品にできません' using errcode = '22023'; end if;
  if btrim(coalesce(v_src.destination, '')) in ('', '廃棄', '返品') then raise exception 'この出庫は返品の対象になりません（出庫先：%）', coalesce(v_src.destination, 'なし') using errcode = '22023'; end if;
  if p_return_date < (v_src.occurred_at at time zone 'Asia/Tokyo')::date then raise exception '返品日が出庫した日より前になっています' using errcode = '22023'; end if;
  v_left := v_src.qty - public.qr_return_done_v1199c163(v_src.id);
  if p_qty > v_left then raise exception '戻せるのは出した数までです（残り %）', v_left using errcode = '22023'; end if;

  select * into v_lot from public.qr_lots where id = v_src.lot_id for update;
  if not found or not coalesce(v_lot.active, true) then raise exception '元のロットが見つかりません（削除されています）' using errcode = 'P0002'; end if;

  -- 規格別ロット：規格ごとに戻す数を確かめる
  v_has_grades := exists (select 1 from public.qr_lot_grades_v1300 where lot_id = v_lot.id);
  if v_has_grades then
    if jsonb_typeof(coalesce(p_grades, '[]'::jsonb)) <> 'array' or jsonb_array_length(coalesce(p_grades, '[]'::jsonb)) = 0 then
      raise exception '規格ごとの数を入れてください' using errcode = '22023';
    end if;
    v_grade_left := public.qr_return_grade_left_v1199c163(v_src.id);
    for r in select g->>'grade' as grade, (g->>'qty')::numeric as qty from jsonb_array_elements(p_grades) g loop
      continue when coalesce(r.qty, 0) = 0;
      if r.qty < 0 then raise exception '規格「%」の数を確かめてください', r.grade using errcode = '22023'; end if;
      if not exists (select 1 from public.qr_lot_grades_v1300 where lot_id = v_lot.id and grade = r.grade) then
        raise exception 'このロットに規格「%」はありません', r.grade using errcode = '22023';
      end if;
      if jsonb_array_length(v_grade_left) > 0 and r.qty > coalesce((select (e->>'left')::numeric from jsonb_array_elements(v_grade_left) e where e->>'grade' = r.grade), 0) then
        raise exception '規格「%」は出した数より多く戻せません', r.grade using errcode = '22023';
      end if;
      v_grades := v_grades || jsonb_build_object('grade', r.grade, 'qty', r.qty);
      v_grade_sum := v_grade_sum + r.qty;
    end loop;
    if v_grade_sum <> p_qty then raise exception '規格ごとの数の合計（%）が戻す数量（%）と合いません', v_grade_sum, p_qty using errcode = '22023'; end if;
  end if;

  -- 本社から返ってきたとき：本社の在庫も同時に減らす
  if btrim(v_src.destination) = '本社' then
    select * into v_hq from public.hq_lots_v1400 where source_movement_id = v_src.id for update;
    if found and v_hq.status <> '取消' then
      v_hq_qty := case when v_hq.unit = 'kg' then
                    round(p_qty * coalesce(nullif(v_hq.unit_weight_kg, 0), case when coalesce(v_src.qty, 0) > 0 then v_hq.planned_qty / v_src.qty end, 1), 1)
                  else p_qty end;
      if v_hq.status = '入荷待ち' then
        update public.hq_lots_v1400
           set planned_qty = greatest(planned_qty - v_hq_qty, 0),
               planned_count = case when planned_count is null then null else greatest(planned_count - p_qty, 0) end,
               status = case when planned_qty - v_hq_qty <= 0 then '取消' else status end,
               memo = concat_ws(' / ', nullif(memo, ''), format('石岡へ返品 %s %s（返品日 %s）', p_qty, coalesce(v_src.unit, ''), to_char(p_return_date, 'MM/DD'))),
               updated_at = now()
         where id = v_hq.id;
        v_hq_action := '入荷予定を減らす';
      else
        v_hq_available := v_hq.current_qty;
        if to_regprocedure('public.hq_c117_available_qty(uuid,uuid)') is not null then
          execute 'select public.hq_c117_available_qty($1, null)' into v_hq_available using v_hq.id;
        end if;
        if v_hq_qty > coalesce(v_hq_available, 0) + 1e-9 then
          raise exception '本社の在庫が足りません（本社に残っている数：% %）。本社で使った分や下処理で使う予定の分は返品できません', coalesce(v_hq_available, 0), v_hq.unit using errcode = '22023';
        end if;
        v_hq_after := v_hq.current_qty - v_hq_qty;
        update public.hq_lots_v1400
           set current_qty = v_hq_after, status = case when v_hq_after > 0 then '在庫あり' else '在庫なし' end, updated_at = now()
         where id = v_hq.id;
        insert into public.hq_lot_movements_v1400(operation_id, lot_id, movement_type, qty, unit, before_qty, after_qty, destination, memo, item_name, lot_no, user_id, user_name)
        values (gen_random_uuid(), v_hq.id, '出庫', v_hq_qty, v_hq.unit, v_hq.current_qty, v_hq_after, '石岡へ返品',
                btrim(format('返品日 %s %s', to_char(p_return_date, 'MM/DD'), v_memo)), v_hq.item_name, v_hq.lot_no, v_profile.id, coalesce(v_profile.display_name, ''))
        returning id into v_hq_mov;
        v_hq_action := '在庫から減らす';
      end if;
    end if;
  end if;

  -- 石岡のロットに戻す（入荷日は変えない）
  v_before := coalesce(v_lot.current_qty, 0);
  v_after := v_before + p_qty;
  v_before_w := v_lot.current_weight;
  v_add_w := case when coalesce(v_src.weight, 0) > 0 and coalesce(v_src.qty, 0) > 0 then round(v_src.weight * p_qty / v_src.qty, 1) end;
  v_after_w := case when v_before_w is not null and v_add_w is not null then v_before_w + v_add_w else v_before_w end;
  update public.qr_lots set current_qty = v_after, current_weight = v_after_w, status = '在庫あり', updated_at = now()
   where id = v_lot.id returning * into v_lot;
  if v_has_grades then
    for r in select e->>'grade' as grade, (e->>'qty')::numeric as qty from jsonb_array_elements(v_grades) e loop
      update public.qr_lot_grades_v1300 set current_qty = current_qty + r.qty, updated_at = now() where lot_id = v_lot.id and grade = r.grade;
    end loop;
  end if;

  v_line := format('返品日 %s・%sから返品（%s出庫分）', to_char(p_return_date, 'YYYY-MM-DD'), btrim(v_src.destination),
                   to_char(v_src.occurred_at at time zone 'Asia/Tokyo', 'MM/DD'));
  insert into public.qr_lot_movements(
    movement_type, lot_id, lot_no, qr_key, item_id, item_name, origin, supplier, cooperative_name,
    qty, unit, destination, storage_location, user_id, user_name, memo,
    container_type, lot_manage_type, weight, before_quantity, after_quantity, before_weight, after_weight, weight_status, reason,
    operation_id, device_meta, operation_meta
  ) values (
    '返品入庫', v_lot.id, v_lot.lot_no, v_lot.qr_key, v_lot.item_id, v_lot.item_name, v_lot.origin, v_lot.supplier, v_lot.cooperative_name,
    p_qty, v_lot.unit, btrim(v_src.destination), v_lot.storage_location, v_profile.id::text, coalesce(v_profile.display_name, ''),
    btrim(v_line || case when v_memo <> '' then ' / ' || v_memo else '' end),
    v_lot.container_type, v_lot.lot_manage_type, v_add_w, v_before, v_after, v_before_w, v_after_w, v_lot.weight_status, '返品',
    p_operation_id, '{}'::jsonb,
    jsonb_build_object('c163_return', jsonb_build_object('source_movement_id', v_src.id, 'return_date', p_return_date, 'from', btrim(v_src.destination),
                                                         'hq_action', v_hq_action, 'hq_qty', v_hq_qty))
    || case when v_has_grades then jsonb_build_object('grades', (select jsonb_agg(jsonb_build_object('grade', e->>'grade', 'delta', (e->>'qty')::numeric)) from jsonb_array_elements(v_grades) e)) else '{}'::jsonb end
  ) returning * into v_mov;

  insert into public.qr_returns_v1199c163(operation_id, source_movement_id, return_movement_id, lot_id, qr_key, lot_no, item_name, from_destination,
    qty, unit, weight, grades, return_date, memo, hq_lot_id, hq_qty, hq_action, hq_movement_id, created_by, created_by_name)
  values (p_operation_id, v_src.id, v_mov.id, v_lot.id, v_lot.qr_key, v_lot.lot_no, v_lot.item_name, btrim(v_src.destination),
    p_qty, v_lot.unit, v_add_w, v_grades, p_return_date, v_memo, case when v_hq_action <> '' then v_hq.id end, v_hq_qty, v_hq_action, v_hq_mov,
    v_profile.id, coalesce(v_profile.display_name, ''))
  returning * into v_ret;

  return jsonb_build_object('ok', true, 'idempotent', false, 'return_id', v_ret.id, 'movement_id', v_mov.id, 'lot_id', v_lot.id,
    'before_quantity', v_before, 'after_quantity', v_after, 'received_date', v_lot.received_date,
    'hq_action', v_hq_action, 'hq_qty', v_hq_qty, 'hq_unit', case when v_hq_action <> '' then v_hq.unit end);
end
$f$;

-- 6) 返品の取り消し（石岡の在庫に返品分が残っているときだけ。本社の分も元に戻す）
create or replace function public.cancel_qr_return_v1199c163(p_operation_id uuid, p_return_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public'
as $f$
declare
  v_profile public.profiles%rowtype; v_ret public.qr_returns_v1199c163%rowtype; v_lot public.qr_lots%rowtype; v_hq public.hq_lots_v1400%rowtype;
  v_mov public.qr_lot_movements%rowtype; v_before numeric; v_after numeric; v_after_w numeric; v_reason text := btrim(coalesce(p_reason, '')); r record;
begin
  v_profile := public.trimming_require_role(array['admin','worker']);
  if p_operation_id is null or p_return_id is null then raise exception '取り消す返品を選んでください' using errcode = '22023'; end if;
  if v_reason = '' then raise exception '取り消す理由を入れてください' using errcode = '22023'; end if;
  select * into v_ret from public.qr_returns_v1199c163 where id = p_return_id for update;
  if not found then raise exception '返品の記録が見つかりません' using errcode = 'P0002'; end if;
  if v_ret.cancelled_at is not null then
    if v_ret.cancel_operation_id = p_operation_id then return jsonb_build_object('ok', true, 'idempotent', true); end if;
    raise exception 'この返品はすでに取り消されています' using errcode = '22023';
  end if;
  select * into v_lot from public.qr_lots where id = v_ret.lot_id for update;
  if not found then raise exception 'ロットが見つかりません' using errcode = 'P0002'; end if;
  v_before := coalesce(v_lot.current_qty, 0);
  if v_before < v_ret.qty then raise exception '石岡の在庫（%）が返品した数（%）より少ないため、取り消せません。先に出庫した分を確かめてください', v_before, v_ret.qty using errcode = '22023'; end if;
  for r in select e->>'grade' as grade, (e->>'qty')::numeric as qty from jsonb_array_elements(v_ret.grades) e loop
    if coalesce((select current_qty from public.qr_lot_grades_v1300 where lot_id = v_lot.id and grade = r.grade), 0) < r.qty then
      raise exception '規格「%」の在庫が返品した数より少ないため、取り消せません', r.grade using errcode = '22023';
    end if;
  end loop;

  -- 本社の分を元に戻す
  if v_ret.hq_lot_id is not null then
    select * into v_hq from public.hq_lots_v1400 where id = v_ret.hq_lot_id for update;
    if found then
      if v_ret.hq_action = '入荷予定を減らす' then
        if v_hq.status not in ('入荷待ち','取消') then
          raise exception '本社ですでに受け入れが済んでいるため、取り消せません。本社で数を確かめてください' using errcode = '22023';
        end if;
        update public.hq_lots_v1400
           set planned_qty = planned_qty + coalesce(v_ret.hq_qty, 0),
               planned_count = case when planned_count is null then null else planned_count + v_ret.qty end,
               status = '入荷待ち',
               memo = concat_ws(' / ', nullif(memo, ''), '石岡への返品を取り消し'), updated_at = now()
         where id = v_hq.id;
      elsif v_ret.hq_action = '在庫から減らす' then
        update public.hq_lots_v1400
           set current_qty = current_qty + coalesce(v_ret.hq_qty, 0), status = '在庫あり', updated_at = now()
         where id = v_hq.id;
        update public.hq_lot_movements_v1400 set cancelled_at = now(), cancelled_by_name = coalesce(v_profile.display_name, '')
         where id = v_ret.hq_movement_id and cancelled_at is null;
        insert into public.hq_lot_movements_v1400(operation_id, lot_id, movement_type, qty, unit, before_qty, after_qty, destination, memo, item_name, lot_no, user_id, user_name, reversed_movement_id)
        values (gen_random_uuid(), v_hq.id, '出庫取消', coalesce(v_ret.hq_qty, 0), v_hq.unit, v_hq.current_qty, v_hq.current_qty + coalesce(v_ret.hq_qty, 0), '石岡へ返品',
                '石岡への返品を取り消し：' || v_reason, v_hq.item_name, v_hq.lot_no, v_profile.id, coalesce(v_profile.display_name, ''), v_ret.hq_movement_id);
      end if;
    end if;
  end if;

  v_after := v_before - v_ret.qty;
  v_after_w := case when v_lot.current_weight is not null and v_ret.weight is not null then greatest(v_lot.current_weight - v_ret.weight, 0) else v_lot.current_weight end;
  update public.qr_lots set current_qty = v_after, current_weight = v_after_w, status = case when v_after > 0 then '在庫あり' else '在庫なし' end, updated_at = now()
   where id = v_lot.id returning * into v_lot;
  -- 規格ごとの数は、下の「取消」の履歴を入れたときに 013 の仕組み（seika_cancel_lot_grades_v1300）が元の増減を打ち消す（ここでは引かない）
  update public.qr_lot_movements set cancelled_at = now(), cancelled_by = coalesce(v_profile.display_name, '') where id = v_ret.return_movement_id and cancelled_at is null;
  insert into public.qr_lot_movements(
    movement_type, lot_id, lot_no, qr_key, item_id, item_name, origin, supplier, cooperative_name,
    qty, unit, destination, storage_location, user_id, user_name, memo,
    container_type, lot_manage_type, weight, before_quantity, after_quantity, before_weight, after_weight, weight_status, reason,
    operation_id, reversed_operation_id, device_meta, operation_meta
  ) select '取消', v_lot.id, v_lot.lot_no, v_lot.qr_key, v_lot.item_id, v_lot.item_name, v_lot.origin, v_lot.supplier, v_lot.cooperative_name,
    v_ret.qty, v_lot.unit, v_ret.from_destination, v_lot.storage_location, v_profile.id::text, coalesce(v_profile.display_name, ''),
    '返品入庫の取消：' || v_reason, v_lot.container_type, v_lot.lot_manage_type, v_ret.weight, v_before, v_after, null, v_after_w, v_lot.weight_status, '返品の取消',
    p_operation_id, m.operation_id, '{}'::jsonb, jsonb_build_object('c163_return_cancel', v_ret.id)
    from public.qr_lot_movements m where m.id = v_ret.return_movement_id
  returning * into v_mov;
  update public.qr_returns_v1199c163 set cancelled_at = now(), cancelled_by_name = coalesce(v_profile.display_name, ''), cancel_reason = v_reason,
         cancel_operation_id = p_operation_id where id = v_ret.id;
  return jsonb_build_object('ok', true, 'idempotent', false, 'after_quantity', v_after);
end
$f$;

-- 7) 登録した返品の一覧（新しい順）
create or replace function public.list_qr_returns_v1199c163(p_limit integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','public'
as $f$
begin
  perform public.seika_require_role_v1240(array['admin','worker','buyer','sales','clerk','viewer','office_viewer']);
  return coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'source_movement_id', r.source_movement_id, 'lot_no', r.lot_no, 'qr_key', r.qr_key,
      'item_name', r.item_name, 'from', r.from_destination, 'qty', r.qty, 'unit', r.unit, 'grades', r.grades, 'return_date', r.return_date,
      'memo', r.memo, 'hq_action', r.hq_action, 'hq_qty', r.hq_qty, 'created_by_name', r.created_by_name, 'created_at', r.created_at,
      'cancelled_at', r.cancelled_at, 'cancel_reason', r.cancel_reason, 'received_date', l.received_date,
      'out_date', (m.occurred_at at time zone 'Asia/Tokyo')::date) order by r.created_at desc)
    from (select * from public.qr_returns_v1199c163 order by created_at desc limit least(greatest(coalesce(p_limit, 50), 1), 300)) r
    left join public.qr_lots l on l.id = r.lot_id
    left join public.qr_lot_movements m on m.id = r.source_movement_id), '[]'::jsonb);
end
$f$;

do $block$
declare f text;
begin
  foreach f in array array['public.list_qr_returnable_v1199c163(text,date,date,text)',
                           'public.return_qr_to_ishioka_v1199c163(uuid,uuid,numeric,date,text,jsonb)',
                           'public.cancel_qr_return_v1199c163(uuid,uuid,text)',
                           'public.list_qr_returns_v1199c163(integer)'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
  foreach f in array array['public.qr_return_done_v1199c163(uuid)','public.qr_return_grade_left_v1199c163(uuid)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
end $block$;

commit;

-- ===== 確認（3つとも OK なら成功） =====
select
  (select case when position('返品入庫' in pg_get_constraintdef(oid)) > 0 then 'OK' else 'NG' end
     from pg_constraint where conname = 'qr_lot_movements_movement_type_check') as "在庫履歴の区分（返品入庫）",
  (select case when to_regclass('public.dest_master_v1199c160') is null then 'OK（066未実行のため出庫先は手で追加）'
               when exists (select 1 from public.dest_master_v1199c160 where name = '返品') then 'OK' else 'NG' end) as "出庫先（返品）",
  (select case when count(*) = 6 then 'OK' else 'NG' end from pg_proc
    where proname in ('list_qr_returnable_v1199c163','return_qr_to_ishioka_v1199c163','cancel_qr_return_v1199c163',
                      'list_qr_returns_v1199c163','qr_return_done_v1199c163','qr_return_grade_left_v1199c163')) as "返品の関数";
