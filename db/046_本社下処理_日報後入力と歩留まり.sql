/*
046_本社下処理_日報後入力と歩留まり.sql（v1.199-c117）

前提：019、022、023、042、045 を実行済みであること。
本社下処理の日報後入力、未確定日報の編集、使用数予約、廃棄自動記録、歩留まり標準を追加します。
既存の作業・在庫・履歴は、このSQLの適用だけでは変更しません。
*/
begin;

do $block$
begin
  if to_regclass('public.hq_works_v1500') is null
     or to_regclass('public.hq_work_materials_v1500') is null
     or to_regclass('public.hq_work_members_v1500') is null
     or to_regclass('public.hq_lots_v1400') is null
     or to_regprocedure('public.hq_actor_v1400(text[])') is null
     or to_regprocedure('public.hq_c116_validate_master_set(uuid[])') is null
     or to_regprocedure('public.hq_prep_confirm_v1199c116(uuid,jsonb,numeric,jsonb,text)') is null then
    raise exception '先に db/019、022、023、042、045 を番号順に実行してください';
  end if;
end $block$;

-- 既存行を更新しない追加列。標準値は保存時点の値だけを日報へ残す。
alter table public.hq_works_v1500 add column if not exists standard_rate numeric;
alter table public.hq_works_v1500 add column if not exists tolerance_points numeric;
-- report_entered_at がある日報は、後入力画面で原料重量・廃棄を自動計算した記録として扱う。
-- 既存行は NULL のままなので、従来画面の手入力互換を変えない。
alter table public.hq_works_v1500 add column if not exists report_entered_at timestamptz;
alter table public.hq_works_v1500 add column if not exists report_raw_kg numeric;
alter table public.hq_works_v1500 add column if not exists report_waste_kg numeric;
alter table public.hq_works_v1500 add column if not exists report_breaks jsonb not null default '[]'::jsonb;
alter table public.hq_works_v1500 drop constraint if exists hq_works_v1500_report_breaks_array_check;
alter table public.hq_works_v1500 add constraint hq_works_v1500_report_breaks_array_check
  check (jsonb_typeof(report_breaks) = 'array');

create table if not exists public.hq_prep_standards_v1199c117 (
  master_ids uuid[] primary key,
  standard_rate numeric,
  tolerance_points numeric not null default 5,
  updated_at timestamptz not null default now(),
  updated_by_name text
);
alter table public.hq_prep_standards_v1199c117 drop constraint if exists hq_prep_standards_v1199c117_rate_check;
alter table public.hq_prep_standards_v1199c117 add constraint hq_prep_standards_v1199c117_rate_check
  check (standard_rate is null or (standard_rate >= 0 and standard_rate <= 100 and standard_rate::text not in ('NaN','Infinity','-Infinity')));
alter table public.hq_prep_standards_v1199c117 drop constraint if exists hq_prep_standards_v1199c117_tolerance_check;
alter table public.hq_prep_standards_v1199c117 add constraint hq_prep_standards_v1199c117_tolerance_check
  check (tolerance_points >= 0 and tolerance_points <= 100 and tolerance_points::text not in ('NaN','Infinity','-Infinity'));

-- 成功した日報保存だけを再送可能にする台帳。payload が異なる同一 operation_id は拒否する。
create table if not exists public.hq_prep_report_operations_v1199c117 (
  operation_id uuid primary key,
  work_id uuid references public.hq_works_v1500(id) on delete set null,
  payload jsonb not null,
  result jsonb,
  created_by uuid references public.profiles(id),
  created_by_name text,
  created_at timestamptz not null default now(),
  completed_at timestamptz
);
alter table public.hq_prep_report_operations_v1199c117
  add column if not exists created_by uuid references public.profiles(id);

-- 標準は有効な本社の対象者だけが読める。再送台帳は、payload・結果を含むため直接読取を許可しない。
-- 書込みと再送結果の取得は SECURITY DEFINER RPC 内だけに限定する。
do $block$
begin
  alter table public.hq_prep_standards_v1199c117 enable row level security;
  drop policy if exists hq_prep_standards_v1199c117_read on public.hq_prep_standards_v1199c117;
  create policy hq_prep_standards_v1199c117_read on public.hq_prep_standards_v1199c117
    for select to authenticated
    using (exists (
      select 1 from public.profiles p
      where p.id=auth.uid() and p.active=true and p.role in ('admin','hq_worker','hq_prep')
    ));
  revoke all on public.hq_prep_standards_v1199c117 from public, anon;
  grant select on public.hq_prep_standards_v1199c117 to authenticated;
  grant all on public.hq_prep_standards_v1199c117 to service_role;

  alter table public.hq_prep_report_operations_v1199c117 enable row level security;
  drop policy if exists hq_prep_report_operations_v1199c117_read on public.hq_prep_report_operations_v1199c117;
  revoke all on public.hq_prep_report_operations_v1199c117 from public, anon, authenticated;
  grant all on public.hq_prep_report_operations_v1199c117 to service_role;
end $block$;

create or replace function public.hq_c117_number(p_value text, p_label text)
returns numeric language plpgsql immutable security definer set search_path to ''
as $f$
declare v numeric;
begin
  if nullif(btrim(coalesce(p_value,'')),'') is null then raise exception '%を入れてください', p_label; end if;
  begin v := p_value::numeric; exception when others then raise exception '%は数字で入れてください', p_label; end;
  if v::text in ('NaN','Infinity','-Infinity') then raise exception '%は有限の数字で入れてください', p_label; end if;
  return v;
end $f$;

create or replace function public.hq_c117_master_ids(p_master_ids uuid[])
returns uuid[] language plpgsql immutable security definer set search_path to ''
as $f$
declare v_ids uuid[];
begin
  if p_master_ids is null or array_position(p_master_ids,null) is not null then raise exception '仕掛品を正しく選んでください'; end if;
  select array_agg(x order by x) into v_ids from unnest(p_master_ids) x;
  if coalesce(array_length(v_ids,1),0) <> coalesce(array_length(p_master_ids,1),0) then raise exception '仕掛品を正しく選んでください'; end if;
  perform public.hq_c116_validate_master_set(v_ids);
  return v_ids;
end $f$;

-- hq_lots の total_weight は旧DBで存在しない場合があるため、行JSONから安全に参照する。
create or replace function public.hq_c117_lot_pack_kg(p_lot public.hq_lots_v1400)
returns numeric language plpgsql stable security definer set search_path to ''
as $f$
declare v_total numeric; v_pack numeric;
begin
  if p_lot.unit = 'kg' then return null; end if;
  v_pack := public.hq_pack_kg_v1500(p_lot.pack_weight);
  if v_pack is not null and v_pack > 0 then return v_pack; end if;
  begin v_total := nullif(to_jsonb(p_lot)->>'total_weight','')::numeric; exception when others then v_total := null; end;
  if v_total is not null and v_total > 0 and coalesce(p_lot.received_qty,0) > 0 then return v_total / p_lot.received_qty; end if;
  return null;
end $f$;

-- 同じロットを使う未確定作業を予約として差し引く。p_work_id 自身の予約は除外する。
create or replace function public.hq_c117_available_qty(p_lot_id uuid, p_work_id uuid default null)
returns numeric language sql stable security definer set search_path to ''
as $f$
  select l.current_qty - coalesce((
    select sum(coalesce(m.qty,0))
    from public.hq_work_materials_v1500 m
    join public.hq_works_v1500 w on w.id=m.work_id
    where m.lot_id=l.id
      and (p_work_id is null or w.id<>p_work_id)
      and w.kind='下処理' and w.confirm_status='未確定' and w.status<>'取消'
  ),0)
  from public.hq_lots_v1400 l where l.id=p_lot_id
$f$;

-- 全保存経路がこの関数を通る。ロットをUUID順でロックするため、同時保存で予約超過しない。
create or replace function public.hq_c117_guard_reservations(p_work_id uuid)
returns void language plpgsql security definer set search_path to ''
as $f$
declare l public.hq_lots_v1400%rowtype; v_mine numeric; v_available numeric;
begin
  for l in select lot.* from public.hq_lots_v1400 lot
    where lot.id=any(array(select distinct lot_id from public.hq_work_materials_v1500 where work_id=p_work_id))
    order by lot.id for update
  loop
    if l.status not in ('在庫あり','在庫なし') then raise exception '原料 % は受け入れ済みではありません',l.lot_no; end if;
    select coalesce(sum(qty),0) into v_mine from public.hq_work_materials_v1500 where work_id=p_work_id and lot_id=l.id;
    v_available := public.hq_c117_available_qty(l.id,p_work_id);
    if v_mine > v_available then raise exception '原料 % の予約可能数が不足しています',l.lot_no; end if;
  end loop;
end $f$;

-- 045の訂正を含め、未確定作業の全保存経路に予約検査を掛ける。
-- 遅延制約トリガーにより、同一保存で複数ロットの使用数を入れ替える途中値ではなく最終値を検査する。
create or replace function public.hq_c117_material_reservation_trigger()
returns trigger language plpgsql security definer set search_path to ''
as $f$
declare w public.hq_works_v1500%rowtype;
begin
  if tg_op='DELETE' then return old; end if;
  select * into w from public.hq_works_v1500 where id=new.work_id;
  if found and w.kind='下処理' and w.confirm_status='未確定' and w.status<>'取消' then
    perform public.hq_c117_guard_reservations(new.work_id);
  end if;
  return new;
end $f$;

drop trigger if exists hq_c117_material_reservation_guard on public.hq_work_materials_v1500;
create constraint trigger hq_c117_material_reservation_guard
  after insert or update of lot_id,qty on public.hq_work_materials_v1500
  deferrable initially deferred for each row
  execute function public.hq_c117_material_reservation_trigger();

create or replace function public.hq_prep_available_lots_v1199c117(p_work_id uuid default null)
returns jsonb language plpgsql security definer set search_path to ''
as $f$
declare v public.profiles; w public.hq_works_v1500%rowtype; result jsonb;
begin
  v := public.hq_actor_v1400(array['admin','hq_worker','hq_prep']);
  if p_work_id is not null then
    select * into w from public.hq_works_v1500 where id=p_work_id;
    if not found or w.kind<>'下処理' then raise exception '下処理が見つかりません'; end if;
  end if;
  select coalesce(jsonb_agg(to_jsonb(l) || jsonb_build_object('total_weight',to_jsonb(l)->'total_weight','available_qty',public.hq_c117_available_qty(l.id,p_work_id)) order by l.hq_received_date nulls last,l.lot_no),'[]'::jsonb)
    into result
  from public.hq_lots_v1400 l
  where l.status in ('在庫あり','在庫なし');
  return result;
end $f$;

create or replace function public.hq_prep_standard_save_v1199c117(
  p_master_ids uuid[], p_standard_rate numeric, p_tolerance_points numeric
) returns jsonb language plpgsql security definer set search_path to ''
as $f$
declare v public.profiles; v_ids uuid[]; v_tolerance numeric;
begin
  v := public.hq_actor_v1400(array['admin','hq_worker']);
  v_ids := public.hq_c117_master_ids(p_master_ids);
  if p_standard_rate is not null and (p_standard_rate < 0 or p_standard_rate > 100 or p_standard_rate::text in ('NaN','Infinity','-Infinity')) then
    raise exception '標準歩留まりは0から100で入れてください';
  end if;
  v_tolerance := coalesce(p_tolerance_points,5);
  if v_tolerance < 0 or v_tolerance > 100 or v_tolerance::text in ('NaN','Infinity','-Infinity') then
    raise exception '許容差は0から100で入れてください';
  end if;
  insert into public.hq_prep_standards_v1199c117(master_ids,standard_rate,tolerance_points,updated_at,updated_by_name)
  values(v_ids,p_standard_rate,v_tolerance,now(),v.display_name)
  on conflict(master_ids) do update set standard_rate=excluded.standard_rate,tolerance_points=excluded.tolerance_points,
    updated_at=excluded.updated_at,updated_by_name=excluded.updated_by_name;
  return jsonb_build_object('ok',true);
end $f$;

-- 042の旧保存経路にも予約保護を追加する。既存の認可・状態条件は保持する。
create or replace function public.hq_work_save_material_qty_v1199c112(p_work_id uuid, p_material_id uuid, p_qty numeric)
returns jsonb language plpgsql security definer set search_path to ''
as $f$
declare v public.profiles; w public.hq_works_v1500%rowtype; mt public.hq_work_materials_v1500%rowtype;
begin
  v := public.hq_actor_v1400(array['admin','hq_worker','hq_prep']);
  if p_qty is null or p_qty<0 or p_qty::text in ('NaN','Infinity','-Infinity') then raise exception '使用原料の数は0以上の数で入れてください'; end if;
  select * into w from public.hq_works_v1500 where id=p_work_id for update;
  if not found then raise exception '下処理が見つかりません'; end if;
  if w.kind<>'下処理' or w.status<>'作業中' or w.confirm_status<>'未確定' then raise exception '使用原料の数は未確定の作業中の下処理だけ保存できます'; end if;
  select * into mt from public.hq_work_materials_v1500 where id=p_material_id and work_id=w.id for update;
  if not found then raise exception 'この下処理の使用原料が見つかりません'; end if;
  update public.hq_work_materials_v1500 set qty=p_qty where id=mt.id;
  perform public.hq_c117_guard_reservations(w.id);
  update public.hq_works_v1500 set history=history||jsonb_build_array(jsonb_build_object('at',now(),'by',v.display_name,'action','作業中に原料使用数を保存','lot_id',mt.lot_id,'material_id',mt.id,'qty',p_qty)),updated_at=now() where id=w.id;
  return jsonb_build_object('ok',true,'material_id',mt.id,'qty',p_qty);
end $f$;

-- 045/019の入力保存が通る共通関数へ予約検査を加える（確定時もこの経路を通る）。
create or replace function public.hq_c116_save_inputs(
  p_work_id uuid, p_materials jsonb, p_waste_kg numeric, p_outputs jsonb, p_by public.profiles
) returns jsonb language plpgsql security definer set search_path to ''
as $f$
declare w public.hq_works_v1500%rowtype; ids uuid[]; r jsonb; v_id uuid; v_qty numeric; v_outputs jsonb; v_yield numeric;
  v_raw_kg numeric:=0; v_auto_waste numeric; v_standard numeric; v_tolerance numeric; v_master_ids uuid[]; mt public.hq_work_materials_v1500%rowtype;
begin
  if jsonb_typeof(coalesce(p_materials,'[]'::jsonb))<>'array' then raise exception '使用原料の形が正しくありません'; end if;
  if p_waste_kg is null or p_waste_kg<0 or p_waste_kg::text in ('NaN','Infinity','-Infinity') then raise exception '廃棄（kg）は0以上の数字で入れてください'; end if;
  select * into w from public.hq_works_v1500 where id=p_work_id for update;
  if not found or w.kind<>'下処理' then raise exception '下処理が見つかりません'; end if;
  if w.status='作業中' then raise exception '先に「作業終了」をしてください'; end if;
  if w.status='取消' or w.confirm_status<>'未確定' then raise exception 'この下処理は確定済みか取消済みです。訂正画面から直してください'; end if;
  if w.pause_kind<>'' then raise exception '休憩・中断中の作業は、先に再開するか休憩を終えてください'; end if;
  ids:=array(select id from public.hq_work_materials_v1500 where work_id=w.id order by id);
  if jsonb_array_length(p_materials)<>coalesce(array_length(ids,1),0) then raise exception 'すべての原料の使用数を入れてください'; end if;
  if exists(select 1 from jsonb_array_elements(p_materials) x where jsonb_typeof(x.value)<>'object') or exists(select 1 from jsonb_array_elements(p_materials) x group by x.value->>'id' having count(*)>1) then raise exception '使用原料の形が正しくありません'; end if;
  for r in select value from jsonb_array_elements(p_materials) loop
    begin v_id:=(r->>'id')::uuid; exception when others then raise exception '使用原料が見つかりません'; end;
    if v_id is null or not(v_id=any(ids)) then raise exception '使用原料が見つかりません'; end if;
    v_qty:=public.hq_c116_nonnegative(r->>'qty','使用原料の数');
    update public.hq_work_materials_v1500 set qty=v_qty where id=v_id and work_id=w.id;
  end loop;
  perform public.hq_c117_guard_reservations(w.id);
  v_outputs:=public.hq_c116_work_outputs(w,p_outputs);
  select coalesce(sum((value->>'yield_kg')::numeric),0) into v_yield from jsonb_array_elements(v_outputs);
  -- c117日報は、原料重量−出来高だけを廃棄として保存する。旧日報は従来どおり手入力を許可する。
  if w.report_entered_at is not null then
    for mt in select * from public.hq_work_materials_v1500 where work_id=w.id order by lot_id loop
      if mt.unit='kg' then
        v_raw_kg:=v_raw_kg+coalesce(mt.qty,0);
      elsif mt.pack_kg is null or mt.pack_kg<=0 then
        raise exception '原料 % の量目が不明です',coalesce(mt.lot_no,mt.lot_id::text);
      else
        v_raw_kg:=v_raw_kg+coalesce(mt.qty,0)*mt.pack_kg;
      end if;
    end loop;
    if v_raw_kg<=0 then raise exception '使用重量の合計は0より大きくしてください'; end if;
    if v_yield>v_raw_kg then raise exception '出来高の合計は使用重量を超えられません'; end if;
    v_auto_waste:=v_raw_kg-v_yield;
    if p_waste_kg is distinct from v_auto_waste then raise exception '日報後入力の廃棄は、使用重量から出来高を引いた値と一致させてください'; end if;
  end if;
  -- 旧保存・旧確定経路も初回入力時だけ標準を固定する。後入力済みの日報は保存時の値を上書きしない。
  if w.standard_rate is null and w.tolerance_points is null and w.report_entered_at is null then
    v_master_ids:=public.hq_c116_work_master_ids(w);
    select standard_rate,tolerance_points into v_standard,v_tolerance
      from public.hq_prep_standards_v1199c117 where master_ids=v_master_ids;
    -- 標準未設定も初回状態として固定し、後から設定した標準を過去の初回保存へ混ぜない。
    v_tolerance:=coalesce(v_tolerance,5);
  end if;
  update public.hq_works_v1500 set waste_kg=p_waste_kg,yield_kg=v_yield,outputs=v_outputs,
    -- c117日報を旧保存・初回確定から更新しても、日報用の原料重量・廃棄snapshotを同じ確定値へそろえる。
    report_raw_kg=case when w.report_entered_at is not null then v_raw_kg else report_raw_kg end,
    report_waste_kg=case when w.report_entered_at is not null then v_auto_waste else report_waste_kg end,
    standard_rate=case when w.standard_rate is null and w.tolerance_points is null and w.report_entered_at is null then v_standard else standard_rate end,
    tolerance_points=case when w.standard_rate is null and w.tolerance_points is null and w.report_entered_at is null then v_tolerance else tolerance_points end,
    inputs_saved_at=now(),inputs_saved_by_name=p_by.display_name,updated_at=now() where id=w.id;
  return jsonb_build_object('ok',true,'yield_kg',v_yield,'outputs',v_outputs);
end $f$;

create or replace function public.hq_prep_report_save_v1199c117(
  p_operation_id uuid, p_work_id uuid, p_expected_updated_at timestamptz, p_report jsonb
) returns jsonb language plpgsql security definer set search_path to ''
as $f$
declare
  v public.profiles; w public.hq_works_v1500%rowtype; l public.hq_lots_v1400%rowtype; s public.hq_staff_v1500%rowtype;
  r jsonb; b jsonb; m jsonb; other jsonb; v_existing public.hq_prep_report_operations_v1199c117%rowtype;
  v_payload jsonb; v_ids uuid[]; v_outputs jsonb; v_product text; v_expiry integer; v_raw text;
  v_work_date date; v_started timestamptz; v_ended timestamptz; v_status text; v_standard numeric; v_tolerance numeric;
  v_lot_id uuid; v_qty numeric; v_expected numeric; v_available numeric; v_pack numeric; v_raw_kg numeric:=0; v_yield numeric; v_waste numeric;
  v_materials jsonb:='[]'::jsonb; v_old_materials jsonb; v_old_members jsonb; v_old_breaks jsonb; v_before jsonb;
  v_members jsonb:='[]'::jsonb; v_effective jsonb:='[]'::jsonb; v_next jsonb; v_breaks jsonb:='[]'::jsonb; v_pause_rows jsonb:='[]'::jsonb;
  v_staff_id uuid; v_phase text; v_start timestamptz; v_end timestamptz; v_bstart timestamptz; v_bend timestamptz; v_staff_bend timestamptz;
  v_excluded uuid[]; v_member_staff_ids uuid[]; v_break_staff_ids uuid[]; v_affects boolean; v_known_break boolean;
  v_pause public.hq_work_pauses_v1199c116%rowtype; v_new_id uuid; v_updated timestamptz; v_updated_after timestamptz;
begin
  v:=public.hq_actor_v1400(array['admin','hq_worker','hq_prep']);
  if p_operation_id is null then raise exception 'operation_idが必要です'; end if;
  if jsonb_typeof(coalesce(p_report,'null'::jsonb))<>'object' then raise exception '日報の形が正しくありません'; end if;
  v_payload:=jsonb_build_object('work_id',p_work_id,'report',p_report);
  insert into public.hq_prep_report_operations_v1199c117(operation_id,work_id,payload,created_by,created_by_name)
    values(p_operation_id,p_work_id,v_payload,v.id,v.display_name) on conflict(operation_id) do nothing;
  if not found then
    select * into v_existing from public.hq_prep_report_operations_v1199c117 where operation_id=p_operation_id for update;
    if v_existing.created_by is distinct from v.id then raise exception 'この日報保存操作は別の利用者のものです'; end if;
    if v_existing.payload is distinct from v_payload then raise exception '同じoperation_idに異なる内容は使えません'; end if;
    if v_existing.result is null then raise exception '同じ日報保存が処理中です。しばらく待ってから再表示してください'; end if;
    return v_existing.result || jsonb_build_object('already',true,'idempotent',true);
  end if;

  begin v_work_date:=(p_report->>'work_date')::date; exception when others then raise exception '作業日を正しく入れてください'; end;
  begin v_started:=(p_report->>'started_at')::timestamptz; v_ended:=(p_report->>'ended_at')::timestamptz; exception when others then raise exception '開始・終了時刻を正しく入れてください'; end;
  if v_work_date is null or v_started is null or v_ended is null or not isfinite(v_started) or not isfinite(v_ended)
     or v_ended<=v_started or v_work_date<>(v_started at time zone 'Asia/Tokyo')::date
     or v_work_date>(clock_timestamp() at time zone 'Asia/Tokyo')::date or v_started>clock_timestamp() or v_ended>clock_timestamp() then
    raise exception '作業日と開始・終了時刻を正しく入れてください';
  end if;
  if nullif(btrim(coalesce(p_report->>'place','')),'') is null then raise exception '作業場所を入れてください'; end if;
  if jsonb_typeof(coalesce(p_report->'master_ids','null'::jsonb))<>'array' or jsonb_array_length(p_report->'master_ids')<1 then raise exception '仕掛品を正しく選んでください'; end if;
  begin select array_agg((value #>> '{}')::uuid) into v_ids from jsonb_array_elements(p_report->'master_ids'); exception when others then raise exception '仕掛品を正しく選んでください'; end;
  v_ids:=public.hq_c117_master_ids(v_ids);
  select item_name into v_raw from public.hq_prep_masters_v1500 where id=v_ids[1];
  if not found then raise exception '仕掛品が見つかりません'; end if;
  select public.hq_c116_outputs(v_ids,p_report->'outputs') into v_outputs;
  select coalesce(sum((value->>'yield_kg')::numeric),0) into v_yield from jsonb_array_elements(v_outputs);
  select string_agg(name,'・' order by id),max(expiry_days) into v_product,v_expiry from public.hq_prep_masters_v1500 where id=any(v_ids);
  select standard_rate,tolerance_points into v_standard,v_tolerance from public.hq_prep_standards_v1199c117 where master_ids=v_ids;

  if p_work_id is null then
    if p_expected_updated_at is not null then raise exception '新規後入力には更新時刻を指定できません'; end if;
    -- 標準未設定も保存時点の状態として固定する。
    v_tolerance:=coalesce(v_tolerance,5);
    v_status:='完了';
  else
    if p_expected_updated_at is null then raise exception '編集には画面を開いた時刻が必要です'; end if;
    select * into w from public.hq_works_v1500 where id=p_work_id for update;
    if not found or w.kind<>'下処理' then raise exception '下処理が見つかりません'; end if;
    if w.confirm_status<>'未確定' or w.status not in ('入力待ち','清掃中','完了') then raise exception '作業終了後の未確定日報だけ編集できます'; end if;
    if w.updated_at is distinct from p_expected_updated_at then
      update public.hq_prep_report_operations_v1199c117 set result=jsonb_build_object('ok',false,'conflict',true,'current_updated_at',w.updated_at,'message','他の操作で内容が変わりました。画面を開き直してください'),completed_at=now() where operation_id=p_operation_id;
      return (select result from public.hq_prep_report_operations_v1199c117 where operation_id=p_operation_id);
    end if;
    v_status:=w.status;
    select coalesce(jsonb_agg(jsonb_build_object('lot_id',lot_id,'qty',qty,'pack_kg',pack_kg) order by lot_id),'[]'::jsonb) into v_old_materials from public.hq_work_materials_v1500 where work_id=w.id;
    select coalesce(jsonb_agg(jsonb_build_object('staff_id',staff_id,'phase',phase,'start_at',start_at,'end_at',end_at) order by staff_id,start_at),'[]'::jsonb) into v_old_members from public.hq_work_members_v1500 where work_id=w.id;
    -- 作業中の休憩操作で残った人別再開は member 区間が正本。日報編集で再度差し引かない。
    select coalesce(jsonb_agg(jsonb_build_object('kind',kind,'start_at',start_at,'end_at',end_at,'excluded_staff_ids',to_jsonb(excluded_staff_ids)) order by start_at,id),'[]'::jsonb)
      into v_old_breaks from public.hq_work_pauses_v1199c116
      where work_id=w.id and kind in ('休憩','中断') and end_at is not null;
    v_old_breaks:=coalesce(w.report_breaks,'[]'::jsonb)||coalesce(v_old_breaks,'[]'::jsonb);
    -- 後入力日報の再編集は保存済みの標準を固定する。
    if w.report_entered_at is not null and public.hq_c116_work_master_ids(w)=v_ids then v_standard:=w.standard_rate; v_tolerance:=w.tolerance_points; end if;
    v_tolerance:=coalesce(v_tolerance,5);
  end if;

  if jsonb_typeof(coalesce(p_report->'materials','null'::jsonb))<>'array' or jsonb_array_length(p_report->'materials')<1 then raise exception '原料を1件以上入れてください'; end if;
  if exists(select 1 from jsonb_array_elements(p_report->'materials') x where jsonb_typeof(x.value)<>'object') or exists(select 1 from jsonb_array_elements(p_report->'materials') x group by x.value->>'lot_id' having count(*)>1) then raise exception '原料ロットを重複なく指定してください'; end if;
  -- 指定ロットをUUID順でロックしてから snapshot/all と予約を検証する。
  for l in select lot.* from public.hq_lots_v1400 lot where lot.id=any(array(
    select distinct (value->>'lot_id')::uuid from jsonb_array_elements(p_report->'materials')
    union select distinct (value->>'lot_id')::uuid from jsonb_array_elements(coalesce(v_old_materials,'[]'::jsonb))
  )) order by lot.id for update loop
    if l.status not in ('在庫あり','在庫なし') then raise exception '原料 % は受け入れ済みではありません',l.lot_no; end if;
  end loop;
  if (select count(*) from public.hq_lots_v1400 lot join lateral (select distinct (value->>'lot_id')::uuid as lot_id from jsonb_array_elements(p_report->'materials')) x on x.lot_id=lot.id)<>jsonb_array_length(p_report->'materials') then raise exception '原料が見つかりません'; end if;
  for r in select value from jsonb_array_elements(p_report->'materials') loop
    begin v_lot_id:=(r->>'lot_id')::uuid; exception when others then raise exception '原料ロットを正しく指定してください'; end;
    select * into l from public.hq_lots_v1400 where id=v_lot_id;
    if l.item_name<>v_raw then raise exception '原料 %（%）は、仕掛品の原料（%）と違います',l.lot_no,l.item_name,v_raw; end if;
    if r->>'use_mode' not in ('all','partial') then raise exception '原料の使用方法を正しく選んでください'; end if;
    v_available:=public.hq_c117_available_qty(l.id,p_work_id);
    if r->>'use_mode'='all' then
      v_expected:=public.hq_c117_number(r->>'expected_available_qty','原料の残数snapshot');
      if v_expected<>v_available then raise exception '原料 % の残数が変わりました。再読み込みしてください',l.lot_no; end if;
      v_qty:=v_available;
    else
      v_qty:=public.hq_c117_number(r->>'qty','使用原料の数');
      if v_qty<0 then raise exception '使用原料の数は0以上で入れてください'; end if;
    end if;
    if v_qty<0 or v_qty>v_available then raise exception '原料 % の予約可能数が不足しています',l.lot_no; end if;
    select pack_kg into v_pack from public.hq_work_materials_v1500 where work_id=p_work_id and lot_id=l.id;
    if l.unit<>'kg' and (v_pack is null or v_pack<=0) then v_pack:=public.hq_c117_lot_pack_kg(l); end if;
    if l.unit<>'kg' and (v_pack is null or v_pack<=0) then raise exception '原料 % の量目が不明です',l.lot_no; end if;
    v_raw_kg:=v_raw_kg+case when l.unit='kg' then v_qty else v_qty*v_pack end;
    v_materials:=v_materials||jsonb_build_array(jsonb_build_object('lot_id',l.id,'lot_no',l.lot_no,'item_name',l.item_name,'unit',l.unit,'pack_kg',v_pack,'qty',v_qty));
  end loop;
  if v_raw_kg<=0 then raise exception '使用重量の合計は0より大きくしてください'; end if;
  if v_yield>v_raw_kg then raise exception '出来高の合計は使用重量を超えられません'; end if;
  v_waste:=v_raw_kg-v_yield;

  if jsonb_typeof(coalesce(p_report->'members','null'::jsonb))<>'array' or jsonb_array_length(p_report->'members')<1 then raise exception '参加スタッフを1人以上入れてください'; end if;
  begin
    select array_agg(distinct (value->>'staff_id')::uuid order by (value->>'staff_id')::uuid) into v_member_staff_ids
      from jsonb_array_elements(p_report->'members');
  exception when others then raise exception '参加スタッフを正しく指定してください'; end;
  if coalesce(array_length(v_member_staff_ids,1),0)<>(select count(*) from public.hq_staff_v1500 where id=any(v_member_staff_ids)) then raise exception 'スタッフが見つかりません'; end if;
  -- work→lot→staffの順で、スタッフはUUID順にロックする。
  perform 1 from public.hq_staff_v1500 where id=any(v_member_staff_ids) order by id for update;
  for r in select value from jsonb_array_elements(p_report->'members') loop
    if jsonb_typeof(r)<>'object' then raise exception '参加スタッフの形が正しくありません'; end if;
    begin v_staff_id:=(r->>'staff_id')::uuid; v_start:=(r->>'start_at')::timestamptz; if nullif(r->>'end_at','') is null then v_end:=null; else v_end:=(r->>'end_at')::timestamptz; end if; exception when others then raise exception '参加スタッフの時刻を正しく入れてください'; end;
    v_phase:=r->>'phase';
    if v_phase not in ('作業','清掃') or v_start is null or not isfinite(v_start) or v_start>clock_timestamp()
       or (v_end is not null and (not isfinite(v_end) or v_end<=v_start or v_end>clock_timestamp())) then
      raise exception '参加スタッフの時刻を正しく入れてください';
    end if;
    if v_phase='作業' and (v_start<v_started or v_end is null or v_end>v_ended) then
      raise exception '作業スタッフは作業時間内で終了させてください';
    end if;
    if v_phase='清掃' and v_start<v_ended then raise exception '清掃スタッフは作業終了後に開始してください'; end if;
    if v_end is null and not(p_work_id is not null and v_status='清掃中' and v_phase='清掃') then raise exception '終了なしで保存できるのは清掃中の清掃スタッフだけです'; end if;
    select * into s from public.hq_staff_v1500 where id=v_staff_id;
    if not found or s.deleted_at is not null then raise exception 'スタッフが見つかりません'; end if;
    v_members:=v_members||jsonb_build_array(jsonb_build_object('staff_id',s.id,'staff_name',s.name,'team',s.team,'phase',v_phase,'start_at',v_start,'end_at',v_end));
  end loop;
  if exists(select 1 from jsonb_array_elements(v_members) with ordinality a(value,n) cross join jsonb_array_elements(v_members) with ordinality z(value,n) where a.value->>'staff_id'=z.value->>'staff_id' and a.n<z.n and (a.value->>'start_at')::timestamptz<coalesce((z.value->>'end_at')::timestamptz,'infinity'::timestamptz) and (z.value->>'start_at')::timestamptz<coalesce((a.value->>'end_at')::timestamptz,'infinity'::timestamptz)) then raise exception '同じスタッフの作業時間が重なっています'; end if;

  v_effective:=v_members;
  if jsonb_typeof(coalesce(p_report->'breaks','[]'::jsonb))<>'array' then raise exception '休憩・中断の形が正しくありません'; end if;
  for b in select value from jsonb_array_elements(coalesce(p_report->'breaks','[]'::jsonb)) loop
    if jsonb_typeof(b)<>'object' or b->>'kind' not in ('休憩','中断') then raise exception '休憩・中断の形が正しくありません'; end if;
    begin v_bstart:=(b->>'start_at')::timestamptz; v_bend:=(b->>'end_at')::timestamptz; exception when others then raise exception '休憩・中断の時刻を正しく入れてください'; end;
    if v_bstart is null or v_bend is null or v_bend<=v_bstart or v_bstart<v_started or v_bend>v_ended or v_bend>clock_timestamp() then raise exception '休憩・中断は作業時間内の過去時刻で入れてください'; end if;
    begin select coalesce(array_agg((value #>> '{}')::uuid order by (value #>> '{}')::uuid),'{}'::uuid[]) into v_excluded from jsonb_array_elements(coalesce(b->'excluded_staff_ids','[]'::jsonb)); exception when others then raise exception '休憩の除外スタッフを正しく入れてください'; end;
    if b->>'kind'='中断' and coalesce(array_length(v_excluded,1),0)>0 then raise exception '中断では除外スタッフを指定できません'; end if;
    if coalesce(array_length(v_excluded,1),0)<>(select count(distinct x) from unnest(v_excluded) x) then raise exception '休憩の除外スタッフを重複して指定できません'; end if;
    if exists(select 1 from unnest(v_excluded) x where not exists(select 1 from jsonb_array_elements(v_effective) q where (q.value->>'staff_id')::uuid=x and q.value->>'phase'='作業')) then raise exception '休憩の除外スタッフは参加スタッフから選んでください'; end if;
    select * into v_pause from public.hq_work_pauses_v1199c116
      where work_id=coalesce(p_work_id,'00000000-0000-0000-0000-000000000000'::uuid)
        and kind=b->>'kind' and start_at=v_bstart and end_at=v_bend and excluded_staff_ids=v_excluded
      order by created_at,id limit 1;
    v_known_break:=found;
    v_affects:=false; v_break_staff_ids:='{}'::uuid[]; v_next:='[]'::jsonb;
    for m in select value from jsonb_array_elements(v_effective) loop
      v_staff_id:=(m->>'staff_id')::uuid; v_start:=(m->>'start_at')::timestamptz; v_end:=nullif(m->>'end_at','')::timestamptz;
      v_staff_bend:=v_bend;
      if v_known_break and v_staff_id=any(v_pause.resumed_staff_ids) then
        select least(v_bend,coalesce(min((value->>'start_at')::timestamptz),v_bend)) into v_staff_bend
        from jsonb_array_elements(v_old_members)
        where (value->>'staff_id')::uuid=v_staff_id and value->>'phase'='作業'
          and (value->>'start_at')::timestamptz>=v_bstart;
      end if;
      if m->>'phase'='作業' and not(v_staff_id=any(v_excluded)) and v_start<v_staff_bend and coalesce(v_end,'infinity'::timestamptz)>v_bstart then
        v_affects:=true;
        v_break_staff_ids:=array(select distinct x from unnest(v_break_staff_ids||array[v_staff_id]) x order by x);
        if v_start<v_bstart then v_next:=v_next||jsonb_build_array(m||jsonb_build_object('end_at',v_bstart)); end if;
        if coalesce(v_end,'infinity'::timestamptz)>v_staff_bend then v_next:=v_next||jsonb_build_array(m||jsonb_build_object('start_at',v_staff_bend)); end if;
      else v_next:=v_next||jsonb_build_array(m); end if;
    end loop;
    -- 既に休憩で分割済みなら既存 pause の人別記録を正本にし、二重に差し引かない。
    if not v_affects and not v_known_break then raise exception 'この時間に休憩・中断へ入れる作業スタッフがいません'; end if;
    if not v_affects then v_break_staff_ids:=v_pause.staff_ids; end if;
    v_effective:=v_next;
    v_breaks:=v_breaks||jsonb_build_array(jsonb_build_object('kind',b->>'kind','start_at',v_bstart,'end_at',v_bend,'excluded_staff_ids',to_jsonb(v_excluded)));
    v_pause_rows:=v_pause_rows||jsonb_build_array(jsonb_build_object('operation_id',case when v_known_break then v_pause.operation_id else gen_random_uuid() end,
      'kind',b->>'kind','start_at',v_bstart,'end_at',v_bend,'staff_ids',to_jsonb(v_break_staff_ids),
      'excluded_staff_ids',to_jsonb(v_excluded),'resumed_staff_ids',case when v_known_break then to_jsonb(v_pause.resumed_staff_ids) else '[]'::jsonb end,
      'resume_operation_id',case when v_known_break then to_jsonb(v_pause.resume_operation_id) else 'null'::jsonb end));
  end loop;
  -- 休憩で分割した実活動区間で、他作業との重なりを判定する。
  for m in select value from jsonb_array_elements(v_effective) loop
    v_staff_id:=(m->>'staff_id')::uuid; v_start:=(m->>'start_at')::timestamptz; v_end:=nullif(m->>'end_at','')::timestamptz;
    if exists(select 1 from public.hq_work_members_v1500 om join public.hq_works_v1500 ow on ow.id=om.work_id where om.staff_id=v_staff_id and (p_work_id is null or om.work_id<>p_work_id) and ow.status<>'取消' and om.start_at<coalesce(v_end,'infinity'::timestamptz) and coalesce(om.end_at,'infinity'::timestamptz)>v_start) then raise exception 'スタッフがほかの作業時間と重なっています'; end if;
  end loop;

  if p_work_id is null then
    insert into public.hq_works_v1500(kind,task_name,place,work_date,status,prep_master_id,raw_item_name,product_name,expiry_days,waste_kg,yield_kg,inputs_saved_at,inputs_saved_by_name,confirm_status,stock_applied,history,started_at,ended_at,created_by_name,standard_rate,tolerance_points,report_entered_at,report_raw_kg,report_waste_kg,report_breaks,outputs,updated_at)
    values('下処理','下処理',nullif(btrim(p_report->>'place'),''),v_work_date,'完了',v_ids[1],v_raw,v_product,v_expiry,v_waste,v_yield,now(),v.display_name,'未確定',false,
      jsonb_build_array(jsonb_build_object('at',now(),'by',v.display_name,'actor_id',v.id,'action','日報後入力','before',null,'after',jsonb_build_object('work_date',v_work_date,'started_at',v_started,'ended_at',v_ended,'place',nullif(btrim(p_report->>'place'),''),'materials',v_materials,'members',v_effective,'breaks',v_breaks,'outputs',v_outputs,'yield_kg',v_yield,'waste_kg',v_waste,'raw_kg',v_raw_kg,'standard_rate',v_standard,'tolerance_points',v_tolerance))),v_started,v_ended,v.display_name,v_standard,v_tolerance,now(),v_raw_kg,v_waste,v_breaks,v_outputs,now()) returning id,updated_at into v_new_id,v_updated;
    p_work_id:=v_new_id;
    update public.hq_prep_report_operations_v1199c117 set work_id=p_work_id where operation_id=p_operation_id;
  else
    v_before:=jsonb_build_object('work_date',w.work_date,'started_at',w.started_at,'ended_at',w.ended_at,'place',w.place,'materials',v_old_materials,'members',v_old_members,'breaks',v_old_breaks,'outputs',w.outputs,'yield_kg',w.yield_kg,'waste_kg',w.waste_kg,'raw_kg',w.report_raw_kg,'standard_rate',w.standard_rate,'tolerance_points',w.tolerance_points);
    delete from public.hq_work_materials_v1500 where work_id=p_work_id;
    delete from public.hq_work_members_v1500 where work_id=p_work_id;
    update public.hq_works_v1500 set place=nullif(btrim(p_report->>'place'),''),work_date=v_work_date,prep_master_id=v_ids[1],raw_item_name=v_raw,product_name=v_product,expiry_days=v_expiry,waste_kg=v_waste,yield_kg=v_yield,inputs_saved_at=now(),inputs_saved_by_name=v.display_name,started_at=v_started,ended_at=v_ended,outputs=v_outputs,standard_rate=v_standard,tolerance_points=v_tolerance,report_entered_at=coalesce(w.report_entered_at,now()),report_raw_kg=v_raw_kg,report_waste_kg=v_waste,report_breaks=v_breaks,
      history=history||jsonb_build_array(jsonb_build_object('at',now(),'by',v.display_name,'actor_id',v.id,'action','日報後入力を編集','before',v_before,'after',jsonb_build_object('work_date',v_work_date,'started_at',v_started,'ended_at',v_ended,'place',nullif(btrim(p_report->>'place'),''),'materials',v_materials,'members',v_effective,'breaks',v_breaks,'outputs',v_outputs,'yield_kg',v_yield,'waste_kg',v_waste,'raw_kg',v_raw_kg,'standard_rate',v_standard,'tolerance_points',v_tolerance))),updated_at=now() where id=p_work_id returning updated_at into v_updated;
  end if;
  insert into public.hq_work_materials_v1500(work_id,lot_id,lot_no,item_name,unit,pack_kg,qty)
  select p_work_id,(value->>'lot_id')::uuid,value->>'lot_no',value->>'item_name',value->>'unit',nullif(value->>'pack_kg','')::numeric,(value->>'qty')::numeric from jsonb_array_elements(v_materials);
  perform public.hq_c117_guard_reservations(p_work_id);
  insert into public.hq_work_members_v1500(work_id,staff_id,staff_name,team,phase,start_at,end_at,end_reason,fixed_by_name,fixed_at)
  select p_work_id,(value->>'staff_id')::uuid,value->>'staff_name',value->>'team',value->>'phase',(value->>'start_at')::timestamptz,nullif(value->>'end_at','')::timestamptz,null,v.display_name,now() from jsonb_array_elements(v_effective);
  -- UI が読む既存 pause 表を日報休憩へ同期する。既存の staff_ids / resumed_staff_ids は保持する。
  delete from public.hq_work_pauses_v1199c116 where work_id=p_work_id and kind in ('休憩','中断') and end_at is not null;
  insert into public.hq_work_pauses_v1199c116(operation_id,work_id,kind,start_at,end_at,staff_ids,resumed_staff_ids,by_name,excluded_staff_ids,resume_operation_id)
  select (value->>'operation_id')::uuid,p_work_id,value->>'kind',(value->>'start_at')::timestamptz,(value->>'end_at')::timestamptz,
    array(select (x #>> '{}')::uuid from jsonb_array_elements(value->'staff_ids') x order by (x #>> '{}')::uuid),
    array(select (x #>> '{}')::uuid from jsonb_array_elements(value->'resumed_staff_ids') x order by (x #>> '{}')::uuid),v.display_name,
    array(select (x #>> '{}')::uuid from jsonb_array_elements(value->'excluded_staff_ids') x order by (x #>> '{}')::uuid),
    nullif(value->>'resume_operation_id','')::uuid
  from jsonb_array_elements(v_pause_rows);
  -- 未確定の新規日報では廃棄一覧を作らない。社員の確定時に既存 confirm 経路が1件だけ作る。
  -- pause 同期も含めた最終更新時刻を返し、次の編集の楽観ロックに使う。
  update public.hq_works_v1500 set updated_at=now() where id=p_work_id returning updated_at into v_updated_after;
  -- 失敗を返す前に同一operation_idの台帳行を残さない。呼出し全体は例外時に原子的に巻き戻る。
  update public.hq_prep_report_operations_v1199c117 set result=jsonb_build_object('ok',true,'id',p_work_id,'updated_at',v_updated_after,'waste_kg',v_waste,'yield_kg',v_yield),completed_at=now() where operation_id=p_operation_id;
  return (select result from public.hq_prep_report_operations_v1199c117 where operation_id=p_operation_id);
end $f$;

-- c117日報は、確定後の旧訂正RPCを通っても原料重量・出来高・廃棄の整合を崩せない。
-- 遅延検査なので、日報編集の「古い原料行を消して新しい行を入れる」途中状態は拒否しない。
create or replace function public.hq_c117_report_integrity_trigger()
returns trigger language plpgsql security definer set search_path to ''
as $f$
declare v_raw numeric; v_bad boolean; w public.hq_works_v1500%rowtype;
begin
  select * into w from public.hq_works_v1500 where id=new.id;
  if not found or w.report_entered_at is null or w.status='取消' or w.confirm_status='取消' then return new; end if;
  select coalesce(sum(case when m.unit='kg' then coalesce(m.qty,0)
    when m.pack_kg is not null and m.pack_kg>0 then coalesce(m.qty,0)*m.pack_kg else null end),0),
    bool_or((m.unit<>'kg') and (m.pack_kg is null or m.pack_kg<=0))
    into v_raw,v_bad
  from public.hq_work_materials_v1500 m where m.work_id=new.id;
  if coalesce(v_bad,false) or v_raw<=0 then raise exception '日報後入力の原料重量を確認してください'; end if;
  if w.yield_kg is null or w.waste_kg is null or w.yield_kg::text in ('NaN','Infinity','-Infinity') or w.waste_kg::text in ('NaN','Infinity','-Infinity')
     or w.yield_kg>v_raw or w.waste_kg<>v_raw-w.yield_kg then
    raise exception '日報後入力の出来高・廃棄は使用重量と一致させてください';
  end if;
  -- 確定後訂正など045由来の経路はこの日報用snapshotを直接書かないため、
  -- 遅延検査の最終原料行から更新し、旧値だけが残らないようにする。
  if w.report_raw_kg is distinct from v_raw or w.report_waste_kg is distinct from w.waste_kg then
    update public.hq_works_v1500 set report_raw_kg=v_raw,report_waste_kg=w.waste_kg where id=w.id;
  end if;
  return new;
end $f$;
drop trigger if exists hq_c117_report_integrity_guard on public.hq_works_v1500;
create constraint trigger hq_c117_report_integrity_guard
  after insert or update on public.hq_works_v1500
  deferrable initially deferred for each row
  execute function public.hq_c117_report_integrity_trigger();

create or replace function public.hq_prep_confirm_v1199c117(
  p_work_id uuid, p_expected_updated_at timestamptz, p_materials jsonb,
  p_waste_kg numeric, p_outputs jsonb, p_reason text
) returns jsonb language plpgsql security definer set search_path to ''
as $f$
declare v public.profiles; w public.hq_works_v1500%rowtype;
begin
  v:=public.hq_actor_v1400(array['admin','hq_worker']);
  select * into w from public.hq_works_v1500 where id=p_work_id for update;
  if not found or w.kind<>'下処理' then raise exception '下処理が見つかりません'; end if;
  if w.confirm_status<>'確定' and (p_expected_updated_at is null or w.updated_at is distinct from p_expected_updated_at) then
    return jsonb_build_object('ok',false,'conflict',true,'message','他の操作で内容が変わりました。画面を開き直してください');
  end if;
  return public.hq_prep_confirm_v1199c116(p_work_id,p_materials,p_waste_kg,p_outputs,p_reason);
end $f$;

-- 公開RPCだけ authenticated。ヘルパーと再送台帳は直接実行させない。
do $block$
declare f text;
begin
  foreach f in array array[
    'public.hq_prep_available_lots_v1199c117(uuid)',
    'public.hq_prep_report_save_v1199c117(uuid,uuid,timestamptz,jsonb)',
    'public.hq_prep_standard_save_v1199c117(uuid[],numeric,numeric)',
    'public.hq_prep_confirm_v1199c117(uuid,timestamptz,jsonb,numeric,jsonb,text)',
    'public.hq_work_save_material_qty_v1199c112(uuid,uuid,numeric)'
  ] loop
    execute format('revoke all on function %s from public, anon',f);
    execute format('grant execute on function %s to authenticated, service_role',f);
  end loop;
  foreach f in array array[
    'public.hq_c117_number(text,text)',
    'public.hq_c117_master_ids(uuid[])',
    'public.hq_c117_lot_pack_kg(public.hq_lots_v1400)',
    'public.hq_c117_available_qty(uuid,uuid)',
    'public.hq_c117_guard_reservations(uuid)',
    'public.hq_c117_material_reservation_trigger()',
    'public.hq_c117_report_integrity_trigger()'
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role',f);
  end loop;
end $block$;

commit;
notify pgrst, 'reload schema';

/* 成功の確かめ方：下の5行がすべてOKなら成功です。 */
select '日報後入力RPC' as 確認,case when to_regprocedure('public.hq_prep_report_save_v1199c117(uuid,uuid,timestamp with time zone,jsonb)') is not null then 'OK' else 'NG' end as 結果
union all select '予約可能ロットRPC',case when to_regprocedure('public.hq_prep_available_lots_v1199c117(uuid)') is not null then 'OK' else 'NG' end
union all select '歩留まり標準RPC',case when to_regprocedure('public.hq_prep_standard_save_v1199c117(uuid[],numeric,numeric)') is not null then 'OK' else 'NG' end
union all select '社員確定RPC',case when to_regprocedure('public.hq_prep_confirm_v1199c117(uuid,timestamp with time zone,jsonb,numeric,jsonb,text)') is not null then 'OK' else 'NG' end
union all select '歩留まり標準表',case when to_regclass('public.hq_prep_standards_v1199c117') is not null then 'OK' else 'NG' end;
