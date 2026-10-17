-- 013_規格別ロット.sql
-- 目的：胡瓜のように、1つのロット（1パレット）に複数の規格（AL・BL・丸・B・Aなど）を入れて管理できるようにする。
--   ・品目ごとに「規格別ロット」をオン／オフし、規格の候補を登録する（管理者・青果社員）。最初は胡瓜だけオン。
--   ・入庫時に規格ごとのケース数を登録する。ロット全体の数量は規格の合計になる。
--   ・出庫・廃棄・実数調整・取消・月末棚卸しは、規格ごとの数量も一緒に増減する。
--   ・規格ごとの増減は、在庫履歴の operation_meta（grades）とメモに残す。
--   ・規格の合計とロット全体の数量がずれる処理は、保存せずにエラーにする（古い画面からの操作を防ぐ）。
--   ・製造日報の使用原料に、規格を記録できるようにする。
-- 前提：001〜012 を実行済みであること。
-- 何度実行しても同じ結果になります。既存のロット・履歴は変更しません。
begin;

-- 1) 品目ごとの規格設定
create table if not exists public.qr_item_grade_settings_v1300(
  item_name text primary key check (btrim(item_name) <> ''),
  enabled boolean not null default true,
  grades text[] not null default '{}',
  updated_by text not null default '',
  updated_by_name text not null default '',
  updated_at timestamptz not null default now()
);
alter table public.qr_item_grade_settings_v1300 enable row level security;
revoke all on public.qr_item_grade_settings_v1300 from public, anon, authenticated;
grant select on public.qr_item_grade_settings_v1300 to authenticated;
grant all on public.qr_item_grade_settings_v1300 to service_role;
drop policy if exists qr_item_grade_settings_v1300_read on public.qr_item_grade_settings_v1300;
create policy qr_item_grade_settings_v1300_read on public.qr_item_grade_settings_v1300 for select to authenticated using (true);
insert into public.qr_item_grade_settings_v1300(item_name, enabled, grades)
values ('胡瓜', true, array['AL','BL','丸','B','A'])
on conflict (item_name) do nothing;

-- 2) ロットごとの規格別数量
create table if not exists public.qr_lot_grades_v1300(
  lot_id uuid not null references public.qr_lots(id) on delete cascade,
  qr_key text not null,
  grade text not null check (btrim(grade) <> '' and char_length(grade) <= 20),
  sort_order integer not null default 0,
  received_qty numeric not null check (received_qty >= 0),
  current_qty numeric not null check (current_qty >= 0),
  updated_at timestamptz not null default now(),
  primary key (lot_id, grade)
);
create index if not exists qr_lot_grades_v1300_qr_key_idx on public.qr_lot_grades_v1300(qr_key);
alter table public.qr_lot_grades_v1300 enable row level security;
revoke all on public.qr_lot_grades_v1300 from public, anon, authenticated;
grant select on public.qr_lot_grades_v1300 to authenticated;
grant all on public.qr_lot_grades_v1300 to service_role;
drop policy if exists qr_lot_grades_v1300_read on public.qr_lot_grades_v1300;
create policy qr_lot_grades_v1300_read on public.qr_lot_grades_v1300 for select to authenticated using (true);

-- 3) 製造日報の使用原料に規格を記録する列
alter table public.trimming_job_lots add column if not exists grade text;

-- 4) 規格の入力チェック（[{grade, qty}] → 正しい形に整える）
create or replace function public.seika_grade_rows_v1300(p_grades jsonb, p_allow_zero boolean)
returns table(grade text, qty numeric, ord integer)
language plpgsql
immutable
set search_path to 'pg_catalog'
as $f$
declare
  r record;
  v_seen text[] := '{}';
  v_g text;
  v_q numeric;
  v_i integer := 0;
begin
  if p_grades is null or jsonb_typeof(p_grades) <> 'array' or jsonb_array_length(p_grades) = 0 then
    raise exception '規格ごとの数量を入力してください' using errcode = '22023';
  end if;
  for r in select value from jsonb_array_elements(p_grades) loop
    v_i := v_i + 1;
    v_g := btrim(coalesce(r.value->>'grade', ''));
    if v_g = '' or char_length(v_g) > 20 then
      raise exception '規格名を確認してください' using errcode = '22023';
    end if;
    if v_g = any(v_seen) then
      raise exception '規格「%」が重複しています', v_g using errcode = '22023';
    end if;
    v_seen := v_seen || v_g;
    begin
      v_q := (r.value->>'qty')::numeric;
    exception when others then
      raise exception '規格「%」の数量を確認してください', v_g using errcode = '22023';
    end;
    if v_q is null or v_q < 0 or (not p_allow_zero and v_q = 0) then
      raise exception '規格「%」の数量を確認してください', v_g using errcode = '22023';
    end if;
    grade := v_g; qty := v_q; ord := v_i * 10;
    return next;
  end loop;
end
$f$;

create or replace function public.seika_grade_memo_v1300(p_deltas jsonb)
returns text
language sql
immutable
set search_path to 'pg_catalog'
as $f$
  select '［規格 ' || string_agg((d->>'grade') || ' ' ||
           case when (d->>'delta')::numeric > 0 then '+' else '' end || trim(to_char((d->>'delta')::numeric, 'FM999999990.####'), '.'), '・') || '］'
    from jsonb_array_elements(coalesce(p_deltas, '[]'::jsonb)) d
   where (d->>'delta')::numeric <> 0
$f$;

-- 5) 規格の合計とロット全体の数量がずれていないか、処理の最後に確認する
create or replace function public.seika_check_lot_grades_v1300()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','public'
as $f$
declare
  v_lot public.qr_lots%rowtype;
  v_sum numeric;
  v_cnt integer;
begin
  select * into v_lot from public.qr_lots where id = new.id;
  if not found or coalesce(v_lot.active, true) = false or coalesce(v_lot.status, '') = '削除' then
    return null;
  end if;
  select count(*), coalesce(sum(current_qty), 0) into v_cnt, v_sum
    from public.qr_lot_grades_v1300 where lot_id = new.id;
  if v_cnt > 0 and v_sum <> coalesce(v_lot.current_qty, 0) then
    raise exception '規格別ロット（%）は、規格ごとの数量で操作してください。画面を再読み込みしてからやり直してください。（規格の合計 % ／ ロット全体 %）',
      v_lot.item_name, v_sum, coalesce(v_lot.current_qty, 0) using errcode = '23514';
  end if;
  return null;
end
$f$;
drop trigger if exists seika_check_lot_grades_v1300 on public.qr_lots;
create constraint trigger seika_check_lot_grades_v1300
  after insert or update on public.qr_lots
  deferrable initially deferred
  for each row execute function public.seika_check_lot_grades_v1300();

-- 6) 取消（cancel_qr_lot_operation）のとき、元の操作の規格増減を自動で戻す
create or replace function public.seika_cancel_lot_grades_v1300()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','public'
as $f$
declare
  v_orig jsonb;
  v_rev jsonb;
  d jsonb;
begin
  if new.reversed_operation_id is null or new.movement_type <> '取消' then
    return new;
  end if;
  select m.operation_meta->'grades' into v_orig
    from public.qr_lot_movements m
   where m.operation_id = new.reversed_operation_id
     and m.movement_type <> '取消'
   limit 1;
  if v_orig is null or jsonb_typeof(v_orig) <> 'array' or jsonb_array_length(v_orig) = 0 then
    return new;
  end if;
  select jsonb_agg(jsonb_build_object('grade', x->>'grade', 'delta', -((x->>'delta')::numeric)))
    into v_rev from jsonb_array_elements(v_orig) x;
  for d in select value from jsonb_array_elements(v_rev) loop
    update public.qr_lot_grades_v1300
       set current_qty = current_qty + (d->>'delta')::numeric, updated_at = now()
     where lot_id = new.lot_id and grade = d->>'grade';
  end loop;
  new.operation_meta := coalesce(new.operation_meta, '{}'::jsonb) || jsonb_build_object('grades', v_rev);
  return new;
end
$f$;
drop trigger if exists seika_cancel_lot_grades_v1300 on public.qr_lot_movements;
create trigger seika_cancel_lot_grades_v1300
  before insert on public.qr_lot_movements
  for each row execute function public.seika_cancel_lot_grades_v1300();

-- 7) 規格設定の保存・削除（管理者・青果社員）
create or replace function public.save_qr_item_grade_setting_v1300(p_item_name text, p_enabled boolean, p_grades text[], p_old_name text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public'
as $f$
declare
  v_profile public.profiles%rowtype;
  v_name text := btrim(coalesce(p_item_name, ''));
  v_old text := nullif(btrim(coalesce(p_old_name, '')), '');
  v_grades text[];
begin
  perform public.seika_require_role_v1240(array['admin','worker']);
  select * into v_profile from public.profiles where id = auth.uid() and active limit 1;
  if v_profile.id is null then
    raise exception 'ログインが必要です' using errcode = '42501';
  end if;
  if v_name = '' then
    return jsonb_build_object('ok', false, 'message', '品目名を入力してください');
  end if;
  select coalesce(array_agg(g order by o), '{}') into v_grades
    from (select btrim(g) g, min(o) o from unnest(coalesce(p_grades, '{}')) with ordinality t(g, o)
           where btrim(g) <> '' group by btrim(g)) s;
  if coalesce(p_enabled, true) and cardinality(v_grades) < 2 then
    return jsonb_build_object('ok', false, 'message', '規格を2つ以上登録してください');
  end if;
  if exists (select 1 from unnest(v_grades) g where char_length(g) > 20) then
    return jsonb_build_object('ok', false, 'message', '規格名は20文字以内にしてください');
  end if;
  if v_old is not null and v_old <> v_name then
    if exists (select 1 from public.qr_item_grade_settings_v1300 where item_name = v_name) then
      return jsonb_build_object('ok', false, 'message', '同じ品目がすでに登録されています');
    end if;
    delete from public.qr_item_grade_settings_v1300 where item_name = v_old;
  end if;
  insert into public.qr_item_grade_settings_v1300(item_name, enabled, grades, updated_by, updated_by_name)
  values (v_name, coalesce(p_enabled, true), v_grades, coalesce(v_profile.legacy_user_id, ''), coalesce(v_profile.display_name, ''))
  on conflict (item_name) do update
    set enabled = excluded.enabled, grades = excluded.grades,
        updated_by = excluded.updated_by, updated_by_name = excluded.updated_by_name, updated_at = now();
  return jsonb_build_object('ok', true, 'item_name', v_name, 'grades', to_jsonb(v_grades));
end
$f$;

create or replace function public.delete_qr_item_grade_setting_v1300(p_item_name text)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public'
as $f$
begin
  perform public.seika_require_role_v1240(array['admin','worker']);
  if not exists (select 1 from public.profiles where id = auth.uid() and active) then
    raise exception 'ログインが必要です' using errcode = '42501';
  end if;
  delete from public.qr_item_grade_settings_v1300 where item_name = btrim(coalesce(p_item_name, ''));
  return jsonb_build_object('ok', found);
end
$f$;

-- 8) 規格別ロットの入庫（create_qr_lot_v185 を呼び、同じ処理の中で規格を登録）
create or replace function public.create_qr_lot_graded_v1300(p_lot jsonb, p_operation_id uuid, p_grades jsonb,
  p_device_meta jsonb default '{}'::jsonb, p_operation_meta jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public'
as $f$
declare
  v_total numeric := 0;
  v_deltas jsonb := '[]'::jsonb;
  v_ans jsonb;
  v_lot_id uuid;
  r record;
begin
  perform public.seika_require_role_v1240(array['admin','worker']);
  for r in select * from public.seika_grade_rows_v1300(p_grades, false) loop
    v_total := v_total + r.qty;
    v_deltas := v_deltas || jsonb_build_object('grade', r.grade, 'delta', r.qty);
  end loop;
  if v_total <> coalesce(nullif(p_lot->>'received_qty', '')::numeric, -1) then
    raise exception '規格ごとのケース数の合計（%）と入庫数量（%）が一致しません', v_total, p_lot->>'received_qty' using errcode = '22023';
  end if;
  v_ans := public.create_qr_lot_v185(p_lot, p_operation_id, coalesce(p_device_meta, '{}'::jsonb),
             coalesce(p_operation_meta, '{}'::jsonb) || jsonb_build_object('grades', v_deltas));
  if coalesce((v_ans->>'ok')::boolean, false) and not coalesce((v_ans->>'idempotent')::boolean, false) then
    v_lot_id := (v_ans->'lot'->>'id')::uuid;
    insert into public.qr_lot_grades_v1300(lot_id, qr_key, grade, sort_order, received_qty, current_qty)
    select v_lot_id, v_ans->'lot'->>'qr_key', g.grade, g.ord, g.qty, g.qty
      from public.seika_grade_rows_v1300(p_grades, false) g;
  end if;
  return v_ans;
end
$f$;

-- 9) 規格別ロットの出庫・廃棄・実数調整（apply_qr_lot_operation を呼び、同じ処理の中で規格も増減）
--    p_args：apply_qr_lot_operation と同じ引数（p_ を除いた名前）
--    p_grades：出庫・廃棄＝[{grade, qty（減らす数）}]、実数調整＝[{grade, qty（調整後の数）}]
create or replace function public.apply_qr_lot_grade_operation_v1300(p_args jsonb, p_grades jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public'
as $f$
declare
  v_lot public.qr_lots%rowtype;
  v_type text := p_args->>'movement_type';
  v_net numeric := 0;
  v_deltas jsonb := '[]'::jsonb;
  v_cur numeric;
  v_delta numeric;
  v_ans jsonb;
  v_memo text;
  v_cnt integer;
  r record;
begin
  perform public.seika_require_role_v1240(array['admin','worker']);
  -- 同じ操作の再送は、最初の結果をそのまま返す（二重に減らさない）
  select q.result_payload into v_ans
    from public.seika_qr_operation_requests_v1156 q
   where q.operation_id = nullif(p_args->>'operation_id', '')::uuid;
  if v_ans is not null then
    return v_ans || jsonb_build_object('idempotent', true);
  end if;
  select * into v_lot from public.qr_lots where qr_key = p_args->>'qr_key' and coalesce(active, true) for update;
  if not found then
    return jsonb_build_object('ok', false, 'not_found', true, 'message', '対象QRロットが見つかりません');
  end if;
  select count(*) into v_cnt from public.qr_lot_grades_v1300 where lot_id = v_lot.id;
  if v_cnt = 0 then
    raise exception 'このロットは規格別ロットではありません' using errcode = '22023';
  end if;
  for r in select * from public.seika_grade_rows_v1300(p_grades, true) loop
    select current_qty into v_cur from public.qr_lot_grades_v1300 where lot_id = v_lot.id and grade = r.grade;
    if not found then
      raise exception 'このロットに規格「%」はありません', r.grade using errcode = '22023';
    end if;
    if v_type in ('出庫','廃棄') then
      if r.qty > v_cur then
        raise exception '規格「%」の残りは % です', r.grade, v_cur using errcode = '22023';
      end if;
      v_delta := -r.qty;
    else
      v_delta := r.qty - v_cur;
    end if;
    if v_delta <> 0 then
      v_deltas := v_deltas || jsonb_build_object('grade', r.grade, 'delta', v_delta);
      v_net := v_net + v_delta;
    end if;
  end loop;
  if jsonb_array_length(v_deltas) = 0 then
    return jsonb_build_object('ok', false, 'message', '規格ごとの数量が変わっていません');
  end if;
  if v_type in ('出庫','廃棄') and v_net >= 0 then
    raise exception '出庫・廃棄する数量を入力してください' using errcode = '22023';
  end if;
  if v_type not in ('出庫','廃棄') then
    v_type := case when v_net < 0 then '出庫・調整減' when v_net > 0 then '入庫・調整増' else '差分なし' end;
  end if;
  if coalesce((p_args->>'after_quantity')::numeric, -1) <> coalesce(v_lot.current_qty, 0) + v_net
     or coalesce((p_args->>'qty')::numeric, -1) <> abs(v_net) then
    return jsonb_build_object('ok', false, 'conflict', true, 'current_quantity', v_lot.current_qty,
      'message', '規格ごとの数量と合計が一致しません。ロットを開き直して確認してください。');
  end if;
  v_memo := btrim(coalesce(p_args->>'memo', '') || ' ' || coalesce(public.seika_grade_memo_v1300(v_deltas), ''));
  v_ans := public.apply_qr_lot_operation(
    p_operation_id => (p_args->>'operation_id')::uuid,
    p_qr_key => v_lot.qr_key,
    p_movement_type => v_type,
    p_qty => abs(v_net),
    p_after_quantity => coalesce(v_lot.current_qty, 0) + v_net,
    p_weight => nullif(p_args->>'weight', '')::numeric,
    p_after_weight => nullif(p_args->>'after_weight', '')::numeric,
    p_destination => nullif(p_args->>'destination', ''),
    p_reason => nullif(p_args->>'reason', ''),
    p_memo => nullif(v_memo, ''),
    p_user_id => nullif(p_args->>'user_id', ''),
    p_user_name => nullif(p_args->>'user_name', ''),
    p_device_meta => coalesce(p_args->'device_meta', '{}'::jsonb),
    p_operation_meta => coalesce(p_args->'operation_meta', '{}'::jsonb) || jsonb_build_object('grades', v_deltas),
    p_expected_quantity => nullif(p_args->>'expected_quantity', '')::numeric
  );
  if coalesce((v_ans->>'ok')::boolean, false) and not coalesce((v_ans->>'idempotent')::boolean, false) then
    for r in select value as d from jsonb_array_elements(v_deltas) loop
      update public.qr_lot_grades_v1300
         set current_qty = current_qty + (r.d->>'delta')::numeric, updated_at = now()
       where lot_id = v_lot.id and grade = r.d->>'grade';
    end loop;
  end if;
  return v_ans || jsonb_build_object('grades', v_deltas);
end
$f$;

-- 10) 月末棚卸しの規格ごとの調整（v188_apply_month_end_qr_adjustment を呼び、規格も増減）
create or replace function public.apply_month_end_grade_adjustment_v1300(p_qr_key text, p_grade text, p_operation_id text,
  p_target_month text, p_as_of_date text, p_book_qty numeric, p_actual_qty numeric, p_reason text, p_memo text,
  p_session_id text, p_count_no text)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public'
as $f$
declare
  v_lot public.qr_lots%rowtype;
  v_cur numeric;
  v_diff numeric;
  v_deltas jsonb;
  v_ans jsonb;
begin
  perform public.seika_require_role_v1240(array['admin','worker']);
  select * into v_lot from public.qr_lots where qr_key = p_qr_key for update;
  if not found then
    raise exception 'QRロットが見つかりません' using errcode = 'P0002';
  end if;
  select current_qty into v_cur from public.qr_lot_grades_v1300 where lot_id = v_lot.id and grade = btrim(coalesce(p_grade, '')) for update;
  if not found then
    raise exception 'このロットに規格「%」はありません', p_grade using errcode = '22023';
  end if;
  v_ans := public.v188_apply_month_end_qr_adjustment(p_qr_key, p_operation_id, p_target_month, p_as_of_date,
             p_book_qty, p_actual_qty, p_reason,
             btrim('規格 ' || btrim(p_grade) || coalesce(' / ' || nullif(btrim(coalesce(p_memo, '')), ''), '')),
             p_session_id, p_count_no);
  if coalesce((v_ans->>'ok')::boolean, false)
     and not coalesce((v_ans->>'idempotent')::boolean, false)
     and not coalesce((v_ans->>'skipped')::boolean, false) then
    v_diff := p_actual_qty - p_book_qty;
    if v_cur + v_diff < 0 then
      v_diff := -v_cur;
    end if;
    v_deltas := jsonb_build_array(jsonb_build_object('grade', btrim(p_grade), 'delta', v_diff));
    update public.qr_lot_grades_v1300
       set current_qty = current_qty + v_diff, updated_at = now()
     where lot_id = v_lot.id and grade = btrim(p_grade);
    update public.qr_lot_movements
       set operation_meta = coalesce(operation_meta, '{}'::jsonb) || jsonb_build_object('grades', v_deltas)
     where operation_id::text = p_operation_id;
  end if;
  return v_ans;
end
$f$;

-- 11) 入庫直後の打ち間違い用：規格の内訳を直す（合計は変えない・入庫以外の処理がないロットだけ）
create or replace function public.fix_qr_lot_grades_v1300(p_qr_key text, p_grades jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public'
as $f$
declare
  v_lot public.qr_lots%rowtype;
  v_total numeric := 0;
  r record;
begin
  perform public.seika_require_role_v1240(array['admin','worker']);
  select * into v_lot from public.qr_lots where qr_key = p_qr_key and coalesce(active, true) for update;
  if not found then
    return jsonb_build_object('ok', false, 'message', '対象QRロットが見つかりません');
  end if;
  if not exists (select 1 from public.qr_lot_grades_v1300 where lot_id = v_lot.id) then
    return jsonb_build_object('ok', false, 'message', 'このロットは規格別ロットではありません');
  end if;
  if exists (select 1 from public.qr_lot_movements m where m.lot_id = v_lot.id and m.movement_type <> '入庫' and m.reversed_operation_id is null and m.movement_type <> '取消') then
    return jsonb_build_object('ok', false, 'message', '出庫・廃棄・調整などの処理があるため、内訳は直せません。実数調整で直してください。');
  end if;
  for r in select * from public.seika_grade_rows_v1300(p_grades, true) loop
    v_total := v_total + r.qty;
  end loop;
  if v_total <> coalesce(v_lot.current_qty, 0) then
    return jsonb_build_object('ok', false, 'message', format('規格の合計（%s）をロット全体（%s）と同じにしてください', v_total, coalesce(v_lot.current_qty, 0)));
  end if;
  delete from public.qr_lot_grades_v1300 where lot_id = v_lot.id;
  insert into public.qr_lot_grades_v1300(lot_id, qr_key, grade, sort_order, received_qty, current_qty)
  select v_lot.id, v_lot.qr_key, g.grade, g.ord, g.qty, g.qty
    from public.seika_grade_rows_v1300(p_grades, true) g where g.qty > 0;
  update public.qr_lot_movements
     set operation_meta = coalesce(operation_meta, '{}'::jsonb) || jsonb_build_object('grades',
           (select jsonb_agg(jsonb_build_object('grade', g.grade, 'delta', g.qty)) from public.seika_grade_rows_v1300(p_grades, true) g where g.qty > 0))
   where lot_id = v_lot.id and movement_type = '入庫';
  return jsonb_build_object('ok', true);
end
$f$;

-- 12) 製造日報の使用原料に規格を記録
create or replace function public.set_trimming_job_lot_grades_v1300(p_job_id text, p_grades jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public'
as $f$
declare
  r record;
  v_n integer := 0;
begin
  perform public.seika_require_role_v1240(array['admin','worker']);
  if p_grades is null or jsonb_typeof(p_grades) <> 'array' then
    return jsonb_build_object('ok', true, 'updated', 0);
  end if;
  for r in select value as g from jsonb_array_elements(p_grades) loop
    update public.trimming_job_lots
       set grade = nullif(left(btrim(coalesce(r.g->>'grade', '')), 20), '')
     where trimming_job_id::text = p_job_id and qr_key = r.g->>'qr_key';
    v_n := v_n + (case when found then 1 else 0 end);
  end loop;
  return jsonb_build_object('ok', true, 'updated', v_n);
end
$f$;

revoke all on function public.seika_grade_rows_v1300(jsonb, boolean) from public, anon;
revoke all on function public.seika_grade_memo_v1300(jsonb) from public, anon;
revoke all on function public.seika_check_lot_grades_v1300() from public, anon, authenticated;
revoke all on function public.seika_cancel_lot_grades_v1300() from public, anon, authenticated;
revoke all on function public.save_qr_item_grade_setting_v1300(text, boolean, text[], text) from public, anon;
revoke all on function public.delete_qr_item_grade_setting_v1300(text) from public, anon;
revoke all on function public.create_qr_lot_graded_v1300(jsonb, uuid, jsonb, jsonb, jsonb) from public, anon;
revoke all on function public.apply_qr_lot_grade_operation_v1300(jsonb, jsonb) from public, anon;
revoke all on function public.apply_month_end_grade_adjustment_v1300(text, text, text, text, text, numeric, numeric, text, text, text, text) from public, anon;
revoke all on function public.fix_qr_lot_grades_v1300(text, jsonb) from public, anon;
revoke all on function public.set_trimming_job_lot_grades_v1300(text, jsonb) from public, anon;
grant execute on function public.seika_grade_rows_v1300(jsonb, boolean) to authenticated, service_role;
grant execute on function public.seika_grade_memo_v1300(jsonb) to authenticated, service_role;
grant execute on function public.save_qr_item_grade_setting_v1300(text, boolean, text[], text) to authenticated, service_role;
grant execute on function public.delete_qr_item_grade_setting_v1300(text) to authenticated, service_role;
grant execute on function public.create_qr_lot_graded_v1300(jsonb, uuid, jsonb, jsonb, jsonb) to authenticated, service_role;
grant execute on function public.apply_qr_lot_grade_operation_v1300(jsonb, jsonb) to authenticated, service_role;
grant execute on function public.apply_month_end_grade_adjustment_v1300(text, text, text, text, text, numeric, numeric, text, text, text, text) to authenticated, service_role;
grant execute on function public.fix_qr_lot_grades_v1300(text, jsonb) to authenticated, service_role;
grant execute on function public.set_trimming_job_lot_grades_v1300(text, jsonb) to authenticated, service_role;

commit;

-- 確認：6行とも「OK」なら成功です
select '規格設定の表（胡瓜を登録済み）' as 確認項目,
       case when exists (select 1 from public.qr_item_grade_settings_v1300 where item_name = '胡瓜') then 'OK' else '要確認' end as 判定
union all
select 'ロットの規格別数量の表',
       case when to_regclass('public.qr_lot_grades_v1300') is not null then 'OK' else '要確認' end
union all
select '規格の合計チェック',
       case when exists (select 1 from pg_trigger where tgname = 'seika_check_lot_grades_v1300') then 'OK' else '要確認' end
union all
select '取消時の規格戻し',
       case when exists (select 1 from pg_trigger where tgname = 'seika_cancel_lot_grades_v1300') then 'OK' else '要確認' end
union all
select '規格別の入庫・出庫・棚卸し・内訳修正・日報の関数',
       case when (select count(*) from pg_proc where proname in ('save_qr_item_grade_setting_v1300','delete_qr_item_grade_setting_v1300','create_qr_lot_graded_v1300','apply_qr_lot_grade_operation_v1300','apply_month_end_grade_adjustment_v1300','fix_qr_lot_grades_v1300','set_trimming_job_lot_grades_v1300')) = 7 then 'OK' else '要確認' end
union all
select '製造日報の規格の列',
       case when exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'trimming_job_lots' and column_name = 'grade') then 'OK' else '要確認' end;
