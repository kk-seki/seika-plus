-- 009_場所移動・品質確認・品質分析.sql
-- 目的：
--  ② QRロットの保管場所を移動できるようにする（移動は「場所移動」として履歴に残す）
--  ③ 品質評価（要確認・不良）の「確認済み」は担当の仕入れ担当者だけが付けられるようにする
--     ・管理者・青果社員はホームに通知が出て、「確認しました」で自分の通知だけ消せる
--     ・仕入れ担当者が決まっていないロットに限り、管理者が代わりに確認済みにできる
--     ・これまでに確認済みになっている評価はそのまま
--  ④ 仕入先品質分析（仕入先別・品目別・月別）の集計関数を追加する（ログインしている全員が閲覧可）
-- ・先に 007・008 を実行しておいてください。
-- ・何度実行しても同じ結果になります。
begin;

-- ② 履歴の種類に「場所移動」を追加（いまの種類はそのまま残す）
do $do$
declare v_def text; v_vals text[];
begin
  select pg_get_constraintdef(c.oid) into v_def
  from pg_constraint c
  where c.conrelid = 'public.qr_lot_movements'::regclass and c.conname = 'qr_lot_movements_movement_type_check';
  if v_def is null or position('場所移動' in v_def) > 0 then return; end if;
  select array_agg(m[1]) into v_vals from regexp_matches(v_def, '''([^'']+)''', 'g') as m;
  v_vals := v_vals || array['場所移動'];
  execute 'alter table public.qr_lot_movements drop constraint qr_lot_movements_movement_type_check';
  execute format('alter table public.qr_lot_movements add constraint qr_lot_movements_movement_type_check check (movement_type = any (%L::text[]))', v_vals);
end
$do$;

create or replace function public.move_qr_lot_location_v1260(p_lot_id uuid, p_to_location text, p_memo text default '')
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public'
as $f$
declare
  v_profile public.profiles%rowtype;
  v_lot public.qr_lots%rowtype;
  v_to text := btrim(coalesce(p_to_location, ''));
  v_from text;
  v_memo text := btrim(coalesce(p_memo, ''));
begin
  perform public.seika_require_role_v1240(array['admin','worker']);
  select * into v_profile from public.profiles where id = auth.uid() and active limit 1;
  if v_profile.id is null then
    raise exception 'ログインが必要です' using errcode = '42501';
  end if;
  if v_to = '' then
    return jsonb_build_object('ok', false, 'message', '移動先を選んでください');
  end if;
  if v_to not in ('第2冷蔵庫','第3冷蔵庫','片岡冷蔵庫','その他')
     and not exists (select 1 from public.qr_storage_locations s where s.name = v_to and s.active) then
    return jsonb_build_object('ok', false, 'message', '登録されていない保管場所です');
  end if;
  select * into v_lot from public.qr_lots where id = p_lot_id and active for update;
  if not found then
    return jsonb_build_object('ok', false, 'message', 'ロットが見つかりません');
  end if;
  v_from := btrim(coalesce(v_lot.storage_location, ''));
  if v_from = v_to then
    return jsonb_build_object('ok', false, 'message', 'すでに同じ保管場所です');
  end if;

  insert into public.qr_lot_movements(
    movement_type, lot_id, lot_no, qr_key, item_id, item_name, origin, supplier, cooperative_name,
    qty, unit, destination, storage_location, user_id, user_name, memo, container_type, lot_manage_type,
    weight, before_quantity, after_quantity, before_weight, after_weight, weight_status, reason,
    operation_id, operation_meta)
  values (
    '場所移動', v_lot.id, v_lot.lot_no, v_lot.qr_key, v_lot.item_id, v_lot.item_name, v_lot.origin, v_lot.supplier, v_lot.cooperative_name,
    0, v_lot.unit, null, v_to, v_profile.id::text, coalesce(v_profile.display_name, ''),
    '保管場所移動：' || coalesce(nullif(v_from, ''), '未設定') || ' → ' || v_to || case when v_memo <> '' then ' ／ ' || v_memo else '' end,
    v_lot.container_type, v_lot.lot_manage_type,
    null, v_lot.current_qty, v_lot.current_qty, v_lot.current_weight, v_lot.current_weight, v_lot.weight_status, '保管場所移動',
    gen_random_uuid(), jsonb_build_object('from_location', v_from, 'to_location', v_to));

  update public.qr_lots set storage_location = v_to where id = v_lot.id;
  return jsonb_build_object('ok', true, 'from_location', v_from, 'to_location', v_to);
end
$f$;
revoke all on function public.move_qr_lot_location_v1260(uuid, text, text) from public, anon;
grant execute on function public.move_qr_lot_location_v1260(uuid, text, text) to authenticated, service_role;

-- ③ 管理者・青果社員の「確認しました」（自分の通知だけ消す）
create table if not exists public.qr_quality_alert_reads_v1260(
  evaluation_id uuid not null references public.qr_quality_evaluations(id) on delete cascade,
  profile_id uuid not null,
  read_by_name text not null default '',
  read_at timestamptz not null default now(),
  primary key (evaluation_id, profile_id)
);
alter table public.qr_quality_alert_reads_v1260 enable row level security;
revoke all on public.qr_quality_alert_reads_v1260 from public, anon, authenticated;
grant select on public.qr_quality_alert_reads_v1260 to authenticated;
grant all on public.qr_quality_alert_reads_v1260 to service_role;
drop policy if exists qr_quality_alert_reads_v1260_own on public.qr_quality_alert_reads_v1260;
create policy qr_quality_alert_reads_v1260_own on public.qr_quality_alert_reads_v1260
  for select to authenticated using (profile_id = auth.uid());

create or replace function public.mark_qr_quality_alert_read_v1260(p_evaluation_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public'
as $f$
declare v_profile public.profiles%rowtype;
begin
  perform public.seika_require_role_v1240(array['admin','worker']);
  select * into v_profile from public.profiles where id = auth.uid() and active limit 1;
  if v_profile.id is null then
    raise exception 'ログインが必要です' using errcode = '42501';
  end if;
  if not exists (select 1 from public.qr_quality_evaluations where id = p_evaluation_id) then
    return jsonb_build_object('ok', false, 'message', '品質評価が見つかりません');
  end if;
  insert into public.qr_quality_alert_reads_v1260(evaluation_id, profile_id, read_by_name)
  values (p_evaluation_id, v_profile.id, coalesce(v_profile.display_name, ''))
  on conflict (evaluation_id, profile_id) do nothing;
  return jsonb_build_object('ok', true);
end
$f$;
revoke all on function public.mark_qr_quality_alert_read_v1260(uuid) from public, anon;
grant execute on function public.mark_qr_quality_alert_read_v1260(uuid) to authenticated, service_role;

-- ③ 確認済み：担当の仕入れ担当者だけ（担当未設定のロットだけ管理者が代わりに確認できる）
create or replace function public.acknowledge_qr_quality_evaluation_v1103(p_evaluation_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_profile public.profiles%rowtype;
  v_evaluation public.qr_quality_evaluations%rowtype;
  v_lot_id uuid;
  v_context jsonb;
  v_already boolean;
begin
  select p.* into v_profile from public.profiles p where p.id=auth.uid() and p.active=true limit 1;
  if not found or v_profile.role not in ('admin','buyer') then raise exception '確認済みにできるのは担当の仕入れ担当者です' using errcode='42501'; end if;
  if p_evaluation_id is null then raise exception '品質評価IDが必要です' using errcode='22023'; end if;
  select * into v_evaluation from public.qr_quality_evaluations e
  where e.id=p_evaluation_id and coalesce(e.active,true)=true and to_jsonb(e)->>'invalidated_at' is null and coalesce((to_jsonb(e)->>'invalidated_by_lot_delete')::boolean,false)=false
  for update;
  if not found then raise exception '有効な品質評価が見つかりません' using errcode='P0002'; end if;
  if v_evaluation.grade not in ('review','bad') then raise exception '良好評価は確認済みにできません' using errcode='22023'; end if;
  if exists(select 1 from public.qr_quality_evaluations n where n.supersedes_id=v_evaluation.id and coalesce(n.active,true)=true and to_jsonb(n)->>'invalidated_at' is null and coalesce((to_jsonb(n)->>'invalidated_by_lot_delete')::boolean,false)=false) then raise exception '訂正前の評価は確認できません。最新評価を確認してください' using errcode='22023'; end if;

  select q.id into v_lot_id from public.qr_lots q
  where (v_evaluation.lot_id is not null and q.id::text=v_evaluation.lot_id::text) or q.qr_key=v_evaluation.qr_key
  order by case when v_evaluation.lot_id is not null and q.id::text=v_evaluation.lot_id::text then 0 else 1 end,coalesce(q.active,true) desc,q.created_at desc,q.id desc limit 1;
  if v_lot_id is null then raise exception '対象QRロットが見つかりません' using errcode='P0002'; end if;
  v_context:=public.seika_quality_buyer_context_for_lot_v1159(v_lot_id);

  if v_profile.role='buyer' then
    if not exists(select 1 from jsonb_array_elements(coalesce(v_context->'acknowledger_profile_ids','[]'::jsonb)) x where x#>>'{}'=v_profile.id::text) then raise exception 'この品質評価を確認する担当ではありません' using errcode='42501'; end if;
  else
    if jsonb_array_length(coalesce(v_context->'acknowledger_profile_ids','[]'::jsonb))>0 then raise exception '担当の仕入れ担当者が確認済みにします。管理者は「確認しました」で自分の通知だけ消せます' using errcode='42501'; end if;
  end if;

  v_already:=v_evaluation.acknowledged_at is not null;
  if not v_already then
    update public.qr_quality_evaluations set acknowledged_at=now(),acknowledged_by=v_profile.id,acknowledged_by_name=coalesce(v_profile.display_name,'（名称未設定）') where id=v_evaluation.id;
  end if;
  return jsonb_build_object('ok',true,'evaluation_id',v_evaluation.id,'already_acknowledged',v_already,
    'acknowledged_at',case when v_already then v_evaluation.acknowledged_at else now() end,
    'acknowledged_by',case when v_already then v_evaluation.acknowledged_by else v_profile.id end,
    'acknowledged_by_name',case when v_already then v_evaluation.acknowledged_by_name else coalesce(v_profile.display_name,'（名称未設定）') end);
end;
$function$;

-- ③ ホームの通知：仕入れ担当者＝担当分、管理者・青果社員＝「確認しました」を押していない分
create or replace function public.list_my_unacknowledged_low_quality_evaluations_v1103(p_limit integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_profile public.profiles%rowtype;
  v_limit integer:=greatest(1,least(coalesce(p_limit,100),500));
  v_rows jsonb;
begin
  select p.* into v_profile from public.profiles p where p.id=auth.uid() and p.active=true limit 1;
  if not found or v_profile.role not in ('admin','buyer','worker') then raise exception '低評価アラートを閲覧する権限がありません' using errcode='42501'; end if;
  with latest as (
    select e.*,q.id as current_lot_id,coalesce(q.item_name,e.item_name) as current_item_name,
      public.seika_quality_buyer_context_for_lot_v1159(q.id) as buyer_context
    from public.qr_quality_evaluations e
    join lateral (
      select lot.* from public.qr_lots lot
      where (e.lot_id is not null and lot.id::text=e.lot_id::text) or lot.qr_key=e.qr_key
      order by case when e.lot_id is not null and lot.id::text=e.lot_id::text then 0 else 1 end,coalesce(lot.active,true) desc,lot.created_at desc,lot.id desc
      limit 1
    ) q on true
    where e.grade in ('review','bad') and e.acknowledged_at is null and coalesce(e.active,true)=true
      and to_jsonb(e)->>'invalidated_at' is null
      and coalesce((to_jsonb(e)->>'invalidated_by_lot_delete')::boolean,false)=false
      and not exists(select 1 from public.qr_quality_evaluations n where n.supersedes_id=e.id and coalesce(n.active,true)=true and to_jsonb(n)->>'invalidated_at' is null and coalesce((to_jsonb(n)->>'invalidated_by_lot_delete')::boolean,false)=false)
  ), flagged as (
    select l.*,
      jsonb_array_length(coalesce(l.buyer_context->'acknowledger_profile_ids','[]'::jsonb)) as acknowledger_count,
      exists(select 1 from jsonb_array_elements(coalesce(l.buyer_context->'acknowledger_profile_ids','[]'::jsonb)) x where x#>>'{}'=v_profile.id::text) as is_my_buyer,
      exists(select 1 from public.qr_quality_alert_reads_v1260 r where r.evaluation_id=l.id and r.profile_id=v_profile.id) as read_by_me
    from latest l
  ), allowed as (
    select * from flagged f
    where (v_profile.role='buyer' and f.is_my_buyer)
       or (v_profile.role='admin' and (not f.read_by_me or f.acknowledger_count=0))
       or (v_profile.role='worker' and not f.read_by_me)
  )
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'qr_key',qr_key,'lot_id',lot_id,'lot_no',lot_no,'item_name',current_item_name,'grade',grade,'evaluated_at',evaluated_at,'buyers',buyer_context->'buyers','buyer_source',buyer_context->>'buyer_source',
           'can_acknowledge',(v_profile.role='buyer' and is_my_buyer) or (v_profile.role='admin' and acknowledger_count=0),
           'acknowledger_count',acknowledger_count,'read_by_me',read_by_me) order by case grade when 'bad' then 1 else 2 end,evaluated_at desc),'[]'::jsonb)
  into v_rows from (select * from allowed order by case grade when 'bad' then 1 else 2 end,evaluated_at desc limit v_limit) s;
  return jsonb_build_object('ok',true,'evaluations',v_rows);
end;
$function$;

-- ④ 仕入先品質分析（ロット1つにつき最新の評価1件、月は入荷日で分ける）
create or replace function public.get_quality_improvement_analysis_v1260(p_from date, p_to date)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','public'
as $f$
declare v_rows jsonb;
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and active) then
    raise exception 'ログインが必要です' using errcode = '42501';
  end if;
  if p_from is null or p_to is null or p_from > p_to or (p_to - p_from + 1) > 800 then
    raise exception '対象期間は800日以内で指定してください' using errcode = '22023';
  end if;
  with latest as (
    select distinct on (e.qr_key) e.qr_key, e.grade, e.evaluated_at
    from public.qr_quality_evaluations e
    where coalesce(e.active, true) and e.invalidated_at is null and coalesce(e.invalidated_by_lot_delete, false) = false
      and not exists (select 1 from public.qr_quality_evaluations n where n.supersedes_id = e.id and coalesce(n.active, true) and n.invalidated_at is null and coalesce(n.invalidated_by_lot_delete, false) = false)
    order by e.qr_key, e.evaluated_at desc, e.created_at desc, e.id desc
  ), base as (
    select coalesce(q.received_date, (l.evaluated_at at time zone 'Asia/Tokyo')::date) as base_date,
           coalesce(nullif(btrim(q.supplier), ''), '（仕入先未入力）') as supplier,
           coalesce(nullif(btrim(q.cooperative_name), ''), '（単協名なし）') as cooperative_name,
           coalesce(nullif(btrim(q.item_name), ''), '（品目なし）') as item_name,
           l.grade
    from latest l
    join lateral (select * from public.qr_lots x where x.qr_key = l.qr_key order by coalesce(x.active, true) desc, x.created_at desc limit 1) q on true
  ), agg as (
    select to_char(base_date, 'YYYY-MM') as month, supplier, cooperative_name, item_name,
           count(*) filter (where grade = 'good') as good,
           count(*) filter (where grade = 'review') as review,
           count(*) filter (where grade = 'bad') as bad
    from base
    where base_date between p_from and p_to
    group by 1, 2, 3, 4
  )
  select coalesce(jsonb_agg(to_jsonb(agg) order by month, supplier, cooperative_name, item_name), '[]'::jsonb) into v_rows from agg;
  return jsonb_build_object('ok', true, 'from', p_from, 'to', p_to, 'rows', v_rows);
end
$f$;
revoke all on function public.get_quality_improvement_analysis_v1260(date, date) from public, anon;
grant execute on function public.get_quality_improvement_analysis_v1260(date, date) to authenticated, service_role;

commit;

-- 確認：5行とも「OK」なら成功です
select '保管場所の移動' as 確認項目, case when exists (select 1 from pg_proc where proname = 'move_qr_lot_location_v1260') then 'OK' else '要確認' end as 判定
union all select '履歴の種類に「場所移動」', case when exists (select 1 from pg_constraint where conname = 'qr_lot_movements_movement_type_check' and position('場所移動' in pg_get_constraintdef(oid)) > 0) then 'OK' else '要確認' end
union all select '「確認しました」の記録表', case when to_regclass('public.qr_quality_alert_reads_v1260') is not null then 'OK' else '要確認' end
union all select '確認済みの権限変更', case when exists (select 1 from pg_proc where proname = 'acknowledge_qr_quality_evaluation_v1103' and position('担当の仕入れ担当者が確認済みにします' in prosrc) > 0) then 'OK' else '要確認' end
union all select '仕入先品質分析の集計', case when exists (select 1 from pg_proc where proname = 'get_quality_improvement_analysis_v1260') then 'OK' else '要確認' end;
