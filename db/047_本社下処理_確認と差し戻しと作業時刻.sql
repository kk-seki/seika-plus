/*
047_本社下処理_確認と差し戻しと作業時刻.sql（v1.199-c120）

前提：019、022、023、042、045、046 を実行済みであること。
047 は新規c120作業と、利用者が保存・提出・差戻しを行った既存下処理だけを
c120へ採用します。SQL適用だけで既存の作業・在庫・履歴は変更しません。
*/
begin;

do $block$
begin
  if to_regclass('public.hq_works_v1500') is null
     or to_regclass('public.hq_work_materials_v1500') is null
     or to_regclass('public.hq_work_members_v1500') is null
     or to_regclass('public.hq_lots_v1400') is null
     or to_regprocedure('public.hq_actor_v1400(text[])') is null
     or to_regprocedure('public.hq_c117_guard_reservations(uuid)') is null then
    raise exception '先に db/019、022、023、042、045、046 を番号順に実行してください';
  end if;
end $block$;

-- NULL は047前のまま。既存行をSQL適用時に採用・書換えしない。
alter table public.hq_works_v1500 add column if not exists c120_flow boolean not null default false;
alter table public.hq_works_v1500 add column if not exists review_status text;
alter table public.hq_works_v1500 add column if not exists review_reason text;
alter table public.hq_works_v1500 add column if not exists reviewed_at timestamptz;
alter table public.hq_works_v1500 add column if not exists reviewed_by_name text;
alter table public.hq_works_v1500 add column if not exists c120_adopted_at timestamptz;
alter table public.hq_works_v1500 add column if not exists c120_adopted_by_id uuid;
alter table public.hq_works_v1500 add column if not exists c120_applied_snapshot jsonb;
alter table public.hq_works_v1500 drop constraint if exists hq_works_v1500_c120_review_status_check;
alter table public.hq_works_v1500 add constraint hq_works_v1500_c120_review_status_check
  check (review_status is null or review_status in ('draft','submitted','returned','confirmed'));
alter table public.hq_works_v1500 drop constraint if exists hq_works_v1500_c120_review_required_check;
alter table public.hq_works_v1500 add constraint hq_works_v1500_c120_review_required_check
  check ((not c120_flow and review_status is null) or (c120_flow and review_status is not null));
alter table public.hq_works_v1500 drop constraint if exists hq_works_v1500_c120_applied_snapshot_check;
alter table public.hq_works_v1500 add constraint hq_works_v1500_c120_applied_snapshot_check
  check (c120_applied_snapshot is null or jsonb_typeof(c120_applied_snapshot)='object');

-- 採用前の旧作業（清掃を含む）の表示用履歴をそのまま凍結する。
create table if not exists public.hq_prep_legacy_archives_v1199c120 (
  id uuid primary key default gen_random_uuid(),
  work_id uuid not null references public.hq_works_v1500(id) on delete cascade,
  action text not null,
  snapshot jsonb not null,
  archived_by uuid references public.profiles(id),
  archived_by_name text,
  archived_at timestamptz not null default now(),
  unique(work_id)
);
alter table public.hq_prep_legacy_archives_v1199c120 enable row level security;
revoke all on public.hq_prep_legacy_archives_v1199c120 from public, anon, authenticated;
grant all on public.hq_prep_legacy_archives_v1199c120 to service_role;

-- NULL work_id は「日報後入力の新規作成」の操作台帳として意図的に許可する。
create table if not exists public.hq_prep_operations_v1199c120 (
  operation_id uuid primary key,
  work_id uuid references public.hq_works_v1500(id) on delete set null,
  action text not null,
  payload jsonb not null,
  result jsonb,
  created_by uuid references public.profiles(id),
  created_by_name text,
  created_at timestamptz not null default now(),
  completed_at timestamptz
);
alter table public.hq_prep_operations_v1199c120 drop constraint if exists hq_prep_operations_v1199c120_work_id_fkey;
alter table public.hq_prep_operations_v1199c120 add constraint hq_prep_operations_v1199c120_work_id_fkey
  foreign key(work_id) references public.hq_works_v1500(id) on delete set null;
alter table public.hq_prep_operations_v1199c120 enable row level security;
revoke all on public.hq_prep_operations_v1199c120 from public, anon, authenticated;
grant all on public.hq_prep_operations_v1199c120 to service_role;

-- 新規c120だけは期限2日。旧作業の採用時は後段の helper が既存snapshotを戻す。
create or replace function public.hq_c120_outputs(p_raw_item text, p_outputs jsonb, p_need_yield boolean)
returns jsonb language plpgsql security definer set search_path to ''
as $f$
declare r jsonb; v_id uuid; m public.hq_prep_masters_v1500%rowtype; v_name text; v_yield numeric; v_result jsonb:='[]'::jsonb;
begin
  if jsonb_typeof(coalesce(p_outputs,'null'::jsonb))<>'array' or jsonb_array_length(p_outputs)<1 then
    raise exception '仕掛品を1つ以上指定してください';
  end if;
  for r in select value from jsonb_array_elements(p_outputs) loop
    if jsonb_typeof(r)<>'object' then raise exception '仕掛品の形が正しくありません'; end if;
    if p_need_yield then
      v_yield:=public.hq_c117_number(r->>'yield_kg','出来高（kg）');
      if v_yield<0 then raise exception '出来高（kg）は0以上で入れてください'; end if;
    else
      v_yield:=0;
    end if;
    begin v_id:=(r->>'master_id')::uuid; exception when others then raise exception '仕掛品IDを正しく指定してください'; end;
    if v_id is null then raise exception '仕掛品IDを正しく指定してください'; end if;
    if coalesce((r->>'custom')::boolean,false) then
      v_name:=nullif(btrim(coalesce(r->>'name','')),'');
      if v_name is null then raise exception '手入力仕掛品の名前を入れてください'; end if;
      if nullif(btrim(coalesce(r->>'item_name',p_raw_item)), '') is distinct from p_raw_item then
        raise exception '手入力仕掛品の原料品目が一致しません';
      end if;
      v_result:=v_result||jsonb_build_array(jsonb_build_object(
        'master_id',v_id,'custom',true,'name',v_name,'item_name',p_raw_item,
        'expiry_days',2,'yield_kg',v_yield));
    else
      select * into m from public.hq_prep_masters_v1500 where id=v_id;
      if not found or m.item_name<>p_raw_item then raise exception '仕掛品と原料の品目が一致しません'; end if;
      v_result:=v_result||jsonb_build_array(jsonb_build_object(
        'master_id',m.id,'name',m.name,'item_name',m.item_name,'expiry_days',2,
        'yield_kg',v_yield));
    end if;
  end loop;
  if (select count(*) from jsonb_array_elements(v_result))<>(select count(distinct value->>'master_id') from jsonb_array_elements(v_result)) then
    raise exception '同じ仕掛品を重複して指定できません';
  end if;
  return v_result;
end $f$;

-- 旧作業は既存の名前・期限snapshotを優先する。新規作成だけが上の2日を採用する。
create or replace function public.hq_c120_outputs_for_work(
  p_raw_item text,p_outputs jsonb,p_need_yield boolean,p_old_outputs jsonb,p_old_expiry integer,p_new boolean
) returns jsonb language plpgsql security definer set search_path to ''
as $f$
declare base jsonb; r jsonb; old jsonb; out jsonb:='[]'::jsonb; fallback integer;
begin
  base:=public.hq_c120_outputs(p_raw_item,p_outputs,p_need_yield);
  if p_new then return base; end if;
  fallback:=coalesce(p_old_expiry,2);
  for r in select value from jsonb_array_elements(base) loop
    select x.value into old from jsonb_array_elements(coalesce(p_old_outputs,'[]'::jsonb)) with ordinality x(value,n)
      where x.value->>'master_id'=r->>'master_id' order by x.n limit 1;
    if found then
      r:=jsonb_set(r,'{expiry_days}',to_jsonb(coalesce((old->>'expiry_days')::integer,fallback)),true);
      if not coalesce((r->>'custom')::boolean,false) then
        if nullif(old->>'name','') is not null then r:=jsonb_set(r,'{name}',old->'name',true); end if;
        if nullif(old->>'item_name','') is not null then r:=jsonb_set(r,'{item_name}',old->'item_name',true); end if;
      end if;
    else
      r:=jsonb_set(r,'{expiry_days}',to_jsonb(fallback),true);
    end if;
    out:=out||jsonb_build_array(r);
  end loop;
  return out;
end $f$;

-- customを含む組合せには標準を付けない。登録済みの組合せだけ保存時点の標準を固定する。
create or replace function public.hq_c120_standard_snapshot(p_outputs jsonb)
returns jsonb language plpgsql security definer set search_path to ''
as $f$
declare ids uuid[]; r numeric; t numeric;
begin
  if exists(select 1 from jsonb_array_elements(coalesce(p_outputs,'[]'::jsonb)) x where coalesce((x.value->>'custom')::boolean,false)) then
    return jsonb_build_object('standard_rate',null,'tolerance_points',null);
  end if;
  begin
    select array_agg((value->>'master_id')::uuid order by (value->>'master_id')::uuid) into ids from jsonb_array_elements(p_outputs);
  exception when others then raise exception '仕掛品を正しく指定してください'; end;
  if ids is null or array_length(ids,1)<1 then return jsonb_build_object('standard_rate',null,'tolerance_points',null); end if;
  select standard_rate,tolerance_points into r,t from public.hq_prep_standards_v1199c117 where master_ids=ids;
  return jsonb_build_object('standard_rate',r,'tolerance_points',coalesce(t,5));
end $f$;

create or replace function public.hq_c120_work_snapshot(p_work_id uuid)
returns jsonb language sql stable security definer set search_path to ''
as $f$
  select jsonb_build_object(
    'work_date',w.work_date,'started_at',w.started_at,'ended_at',w.ended_at,'place',w.place,
    'status',w.status,'confirm_status',w.confirm_status,'review_status',w.review_status,
    'materials',coalesce((select jsonb_agg(jsonb_build_object('lot_id',m.lot_id,'lot_no',m.lot_no,'item_name',m.item_name,'unit',m.unit,'pack_kg',m.pack_kg,'qty',m.qty) order by m.lot_id) from public.hq_work_materials_v1500 m where m.work_id=w.id),'[]'::jsonb),
    'members',coalesce((select jsonb_agg(jsonb_build_object('staff_id',m.staff_id,'staff_name',m.staff_name,'team',m.team,'phase',m.phase,'start_at',m.start_at,'end_at',m.end_at,'end_reason',m.end_reason) order by m.staff_id,m.start_at,m.id) from public.hq_work_members_v1500 m where m.work_id=w.id),'[]'::jsonb),
    'breaks',coalesce(w.report_breaks,'[]'::jsonb), 'outputs',coalesce(w.outputs,'[]'::jsonb),
    'yield_kg',w.yield_kg,'waste_kg',w.waste_kg,'raw_kg',w.report_raw_kg,
    'standard_rate',w.standard_rate,'tolerance_points',w.tolerance_points,'expiry_days',w.expiry_days)
  from public.hq_works_v1500 w where w.id=p_work_id
$f$;

create or replace function public.hq_c120_record_operation(p_operation_id uuid,p_work_id uuid,p_action text,p_payload jsonb,p_by public.profiles)
returns jsonb language plpgsql security definer set search_path to ''
as $f$
declare x public.hq_prep_operations_v1199c120%rowtype;
begin
  if p_operation_id is null then raise exception 'operation_idが必要です'; end if;
  insert into public.hq_prep_operations_v1199c120(operation_id,work_id,action,payload,created_by,created_by_name)
  values(p_operation_id,p_work_id,p_action,p_payload,p_by.id,p_by.display_name) on conflict(operation_id) do nothing;
  if found then return null; end if;
  select * into x from public.hq_prep_operations_v1199c120 where operation_id=p_operation_id for update;
  if x.created_by is distinct from p_by.id then raise exception 'この操作は別の利用者のものです'; end if;
  if x.action<>p_action or x.payload is distinct from p_payload then
    return jsonb_build_object('ok',false,'idempotency_conflict',true,'message','同じoperation_idに異なる内容は使えません');
  end if;
  if x.result is null then raise exception '同じ操作が処理中です。しばらく待ってから再表示してください'; end if;
  return x.result||jsonb_build_object('already',true,'idempotent',true);
end $f$;

create or replace function public.hq_c120_finish_operation(p_operation_id uuid,p_result jsonb)
returns jsonb language plpgsql security definer set search_path to ''
as $f$
begin
  update public.hq_prep_operations_v1199c120 set result=p_result,completed_at=now() where operation_id=p_operation_id;
  return p_result;
end $f$;

-- 旧作業の採用は、この関数を呼ぶ明示的なユーザー操作でのみ行う。
create or replace function public.hq_c120_adopt_legacy(p_work_id uuid,p_action text,p_by public.profiles)
returns void language plpgsql security definer set search_path to ''
as $f$
declare w public.hq_works_v1500%rowtype; snap jsonb;
begin
  select * into w from public.hq_works_v1500 where id=p_work_id for update;
  if not found or w.kind<>'下処理' then raise exception '下処理が見つかりません'; end if;
  if w.c120_flow then return; end if;
  if w.status not in ('入力待ち','清掃中','完了') or w.ended_at is null then
    raise exception '終了済みの下処理だけを新しい確認フローへ採用できます';
  end if;
  snap:=public.hq_c120_work_snapshot(w.id);
  insert into public.hq_prep_legacy_archives_v1199c120(work_id,action,snapshot,archived_by,archived_by_name)
  values(w.id,p_action,snap,p_by.id,p_by.display_name) on conflict(work_id) do nothing;
  update public.hq_works_v1500 set c120_flow=true,
    review_status=case when confirm_status='確定' then 'confirmed' else 'draft' end,
    review_reason=null,reviewed_at=now(),reviewed_by_name=p_by.display_name,
    c120_adopted_at=now(),c120_adopted_by_id=p_by.id,
    c120_applied_snapshot=case when confirm_status='確定' then snap else null end,
    history=history||jsonb_build_array(jsonb_build_object('at',now(),'by',p_by.display_name,'actor_id',p_by.id,
      'action','c120採用','reason',p_action,'before',snap,'after',jsonb_build_object('c120_flow',true,'review_status',case when confirm_status='確定' then 'confirmed' else 'draft' end))),
    updated_at=now()
  where id=w.id;
end $f$;

-- 休憩を人ごとの作業区間へ一度だけ反映し、既存日報の分割済み区間を二重に引かない。
create or replace function public.hq_c120_normalize_intervals(
  p_work_id uuid,p_started timestamptz,p_ended timestamptz,p_members jsonb,p_breaks jsonb
) returns jsonb language plpgsql security definer set search_path to ''
as $f$
declare r jsonb; b jsonb; q jsonb; n integer; s public.hq_staff_v1500%rowtype; oldp public.hq_work_pauses_v1199c116%rowtype;
  ids uuid[]; excluded uuid[]; affected uuid[]; sid uuid; a timestamptz; z timestamptz; bs timestamptz; bz timestamptz; resume_at timestamptz;
  raw jsonb:='[]'::jsonb; effective jsonb:='[]'::jsonb; next_effective jsonb; breaks jsonb:='[]'::jsonb; pauses jsonb:='[]'::jsonb; known boolean;
begin
  if jsonb_typeof(coalesce(p_members,'null'::jsonb))<>'array' or jsonb_array_length(p_members)<1 then raise exception '作業者を1人以上指定してください'; end if;
  if jsonb_typeof(coalesce(p_breaks,'[]'::jsonb))<>'array' then raise exception '休憩・中断の形が正しくありません'; end if;
  begin select array_agg(distinct (value->>'staff_id')::uuid order by (value->>'staff_id')::uuid) into ids from jsonb_array_elements(p_members); exception when others then raise exception '作業者を正しく指定してください'; end;
  if ids is null or array_length(ids,1)<1 or (select count(*) from public.hq_staff_v1500 where id=any(ids) and deleted_at is null)<>array_length(ids,1) then raise exception '作業者が見つかりません'; end if;
  perform 1 from public.hq_staff_v1500 where id=any(ids) order by id for update;
  for r in select value from jsonb_array_elements(p_members) loop
    if jsonb_typeof(r)<>'object' then raise exception '作業者区間の形が正しくありません'; end if;
    begin sid:=(r->>'staff_id')::uuid; a:=(r->>'start_at')::timestamptz; z:=(r->>'end_at')::timestamptz; exception when others then raise exception '作業者の開始・終了時刻を正しく入れてください'; end;
    if coalesce(r->>'phase','作業')<>'作業' then raise exception '清掃は日報に記録しません'; end if;
    if sid is null or a is null or z is null or not isfinite(a) or not isfinite(z) or z<=a or a<p_started or z>p_ended then raise exception '作業者の作業時間は作業時間内で入力してください'; end if;
    if exists(select 1 from jsonb_array_elements(raw) x where (x.value->>'staff_id')::uuid=sid and a<((x.value->>'end_at')::timestamptz) and ((x.value->>'start_at')::timestamptz)<z) then raise exception '同じ作業者の時間が重なっています'; end if;
    select * into s from public.hq_staff_v1500 where id=sid;
    raw:=raw||jsonb_build_array(jsonb_build_object('staff_id',s.id,'staff_name',s.name,'team',s.team,'phase','作業','start_at',a,'end_at',z));
  end loop;
  effective:=raw;
  for b in select value from jsonb_array_elements(p_breaks) loop
    if jsonb_typeof(b)<>'object' or b->>'kind' not in ('休憩','中断') then raise exception '休憩・中断の形が正しくありません'; end if;
    begin bs:=(b->>'start_at')::timestamptz; bz:=(b->>'end_at')::timestamptz; exception when others then raise exception '休憩・中断の時刻を正しく入れてください'; end;
    if bs is null or bz is null or not isfinite(bs) or not isfinite(bz) or bz<=bs or bs<p_started or bz>p_ended then raise exception '休憩・中断は作業時間内で入力してください'; end if;
    if exists(select 1 from jsonb_array_elements(breaks) x
      where (x.value->>'start_at')::timestamptz<bz and bs<(x.value->>'end_at')::timestamptz) then
      raise exception '休憩・中断の時間が重なっています';
    end if;
    if jsonb_typeof(coalesce(b->'excluded_staff_ids','[]'::jsonb))<>'array' then raise exception '休憩に入らない作業者を正しく指定してください'; end if;
    begin select coalesce(array_agg((value #>> '{}')::uuid order by (value #>> '{}')::uuid),'{}'::uuid[]) into excluded from jsonb_array_elements(coalesce(b->'excluded_staff_ids','[]'::jsonb)); exception when others then raise exception '休憩に入らない作業者を正しく指定してください'; end;
    if b->>'kind'='中断' and coalesce(array_length(excluded,1),0)>0 then raise exception '中断では除外作業者を指定できません'; end if;
    if coalesce(array_length(excluded,1),0)<>(select count(distinct x) from unnest(excluded) x) then raise exception '休憩に入らない作業者を重複して指定できません'; end if;
    if exists(select 1 from unnest(excluded) x where not x=any(ids)) then raise exception '休憩に入らない人は作業者から選んでください'; end if;
    if exists(select 1 from unnest(excluded) x where not exists(select 1 from jsonb_array_elements(effective) m where (m.value->>'staff_id')::uuid=x and (m.value->>'start_at')::timestamptz<bz and ((m.value->>'end_at')::timestamptz)>bs)) then raise exception '休憩に入らない人は、その時間に作業していた人だけ選べます'; end if;
    if exists(select 1 from jsonb_array_elements(breaks) x where x.value->>'kind'=b->>'kind' and (x.value->>'start_at')::timestamptz=bs and (x.value->>'end_at')::timestamptz=bz and coalesce(x.value->'excluded_staff_ids','[]'::jsonb)=to_jsonb(excluded)) then raise exception '同じ休憩・中断を重複して指定できません'; end if;
    known:=false;
    if p_work_id is not null then
      select * into oldp from public.hq_work_pauses_v1199c116 where work_id=p_work_id and kind=b->>'kind' and start_at=bs and end_at=bz and excluded_staff_ids=excluded order by created_at,id limit 1;
      known:=found;
    end if;
    affected:=case when known then oldp.staff_ids else '{}'::uuid[] end; next_effective:='[]'::jsonb;
    for q in select value from jsonb_array_elements(effective) loop
      sid:=(q->>'staff_id')::uuid; a:=(q->>'start_at')::timestamptz; z:=(q->>'end_at')::timestamptz;
      if not(sid=any(excluded)) and a<bz and z>bs then
        affected:=array(select distinct x from unnest(affected||array[sid]) x order by x);
        resume_at:=bz;
        if known and sid=any(oldp.resumed_staff_ids) then
          select min(m.start_at) into resume_at from public.hq_work_members_v1500 m
            where m.work_id=p_work_id and m.staff_id=sid and m.phase='作業' and m.start_at>bs and m.start_at<bz;
          resume_at:=coalesce(resume_at,bz);
        end if;
        if a<bs then next_effective:=next_effective||jsonb_build_array(q||jsonb_build_object('end_at',bs)); end if;
        if z>resume_at then next_effective:=next_effective||jsonb_build_array(q||jsonb_build_object('start_at',resume_at)); end if;
      else
        next_effective:=next_effective||jsonb_build_array(q);
      end if;
    end loop;
    if coalesce(array_length(affected,1),0)=0 and not known then raise exception 'この時間に休憩・中断へ入る作業者がいません'; end if;
    if coalesce(array_length(affected,1),0)=0 then affected:=oldp.staff_ids; end if;
    effective:=next_effective;
    breaks:=breaks||jsonb_build_array(jsonb_build_object('kind',b->>'kind','start_at',bs,'end_at',bz,'excluded_staff_ids',to_jsonb(excluded)));
    pauses:=pauses||jsonb_build_array(jsonb_build_object('operation_id',case when known then oldp.operation_id else gen_random_uuid() end,
      'kind',b->>'kind','start_at',bs,'end_at',bz,'staff_ids',to_jsonb(affected),'resumed_staff_ids',case when known then to_jsonb(oldp.resumed_staff_ids) else to_jsonb(affected) end,
      'excluded_staff_ids',to_jsonb(excluded),'resume_operation_id',case when known then to_jsonb(oldp.resume_operation_id) else 'null'::jsonb end));
  end loop;
  for q in select value from jsonb_array_elements(effective) loop
    sid:=(q->>'staff_id')::uuid; a:=(q->>'start_at')::timestamptz; z:=(q->>'end_at')::timestamptz;
    if exists(select 1 from public.hq_work_members_v1500 om join public.hq_works_v1500 ow on ow.id=om.work_id where om.staff_id=sid and (p_work_id is null or om.work_id<>p_work_id) and ow.status<>'取消' and om.start_at<z and coalesce(om.end_at,'infinity'::timestamptz)>a) then raise exception '作業者の時間がほかの作業と重なっています'; end if;
  end loop;
  return jsonb_build_object('members',effective,'breaks',breaks,'pauses',pauses);
end $f$;

create or replace function public.hq_c120_baseline_qty(p_snapshot jsonb,p_lot_id uuid)
returns numeric language sql stable security definer set search_path to ''
as $f$
  select coalesce(sum((value->>'qty')::numeric),0) from jsonb_array_elements(coalesce(p_snapshot->'materials','[]'::jsonb)) where (value->>'lot_id')::uuid=p_lot_id
$f$;

-- own confirmed baseline is usable only when it was actually deducted. Other unconfirmed works remain reservations.
create or replace function public.hq_c120_available_qty(p_lot_id uuid,p_work_id uuid,p_baseline jsonb,p_stock_applied boolean)
returns numeric language sql stable security definer set search_path to ''
as $f$
  select public.hq_c117_available_qty(p_lot_id,p_work_id)+case when p_stock_applied then public.hq_c120_baseline_qty(p_baseline,p_lot_id) else 0 end
$f$;

-- 入力済みの差分を、在庫を動かす必要がある時だけ一括・原子的に反映する。
create or replace function public.hq_c120_apply_stock_delta(
  p_work_id uuid,p_baseline jsonb,p_materials jsonb,p_stock_applied boolean,p_reason text,p_by public.profiles
) returns void language plpgsql security definer set search_path to ''
as $f$
declare lot public.hq_lots_v1400%rowtype; old_qty numeric; new_qty numeric; delta numeric; before_qty numeric; after_qty numeric;
begin
  if not p_stock_applied then return; end if;
  for lot in select * from public.hq_lots_v1400 where id=any(array(
    select distinct (value->>'lot_id')::uuid from jsonb_array_elements(coalesce(p_baseline->'materials','[]'::jsonb))
    union select distinct (value->>'lot_id')::uuid from jsonb_array_elements(coalesce(p_materials,'[]'::jsonb))
  )) order by id for update loop
    old_qty:=public.hq_c120_baseline_qty(p_baseline,lot.id);
    select coalesce(sum((value->>'qty')::numeric),0) into new_qty from jsonb_array_elements(p_materials) where (value->>'lot_id')::uuid=lot.id;
    delta:=old_qty-new_qty;
    if delta<0 and lot.current_qty< -delta then raise exception '原料 % の現在在庫が不足しています',lot.lot_no; end if;
  end loop;
  for lot in select * from public.hq_lots_v1400 where id=any(array(
    select distinct (value->>'lot_id')::uuid from jsonb_array_elements(coalesce(p_baseline->'materials','[]'::jsonb))
    union select distinct (value->>'lot_id')::uuid from jsonb_array_elements(coalesce(p_materials,'[]'::jsonb))
  )) order by id for update loop
    old_qty:=public.hq_c120_baseline_qty(p_baseline,lot.id);
    select coalesce(sum((value->>'qty')::numeric),0) into new_qty from jsonb_array_elements(p_materials) where (value->>'lot_id')::uuid=lot.id;
    delta:=old_qty-new_qty;
    if delta<>0 then
      before_qty:=lot.current_qty; after_qty:=before_qty+delta;
      update public.hq_lots_v1400 set current_qty=after_qty,status=case when after_qty>0 then '在庫あり' else '在庫なし' end,updated_at=now() where id=lot.id;
      insert into public.hq_lot_movements_v1400(operation_id,lot_id,movement_type,qty,unit,before_qty,after_qty,destination,reason,memo,item_name,lot_no,user_id,user_name,occurred_at,work_id)
      values(gen_random_uuid(),lot.id,case when old_qty=0 then '下処理使用' else '下処理訂正' end,case when old_qty=0 then -delta else delta end,lot.unit,before_qty,after_qty,'下処理',p_reason,null,lot.item_name,lot.lot_no,p_by.id,p_by.display_name,now(),p_work_id);
    end if;
  end loop;
end $f$;

create or replace function public.hq_c120_sync_waste(p_work_id uuid,p_waste numeric,p_by public.profiles)
returns void language plpgsql security definer set search_path to ''
as $f$
declare w public.hq_works_v1500%rowtype;
begin
  select * into w from public.hq_works_v1500 where id=p_work_id;
  update public.hq_waste_v1500 set cancelled_at=now(),cancelled_by_name=p_by.display_name where work_id=p_work_id and kind='下処理ロス' and cancelled_at is null;
  if coalesce(p_waste,0)>0 then insert into public.hq_waste_v1500(kind,waste_date,item_name,kg,work_id,memo,user_name)
    values('下処理ロス',w.work_date,w.raw_item_name,p_waste,w.id,w.product_name,p_by.display_name); end if;
end $f$;

-- c120開始。出力は同原料品目、全ての新規仕掛品期限は2日。
create or replace function public.hq_prep_start_v1199c120(
  p_operation_id uuid,p_place text,p_lot_ids uuid[],p_staff_ids uuid[],p_started_at timestamptz,p_outputs jsonb
) returns jsonb language plpgsql security definer set search_path to ''
as $f$
declare v public.profiles; l public.hq_lots_v1400%rowtype; s public.hq_staff_v1500%rowtype; w public.hq_works_v1500%rowtype; raw text; outs jsonb; payload jsonb; replay jsonb; ids uuid[];
begin
  v:=public.hq_actor_v1400(array['admin','hq_worker','hq_prep']);
  payload:=jsonb_build_object('place',p_place,'lot_ids',to_jsonb(p_lot_ids),'staff_ids',to_jsonb(p_staff_ids),'started_at',p_started_at,'outputs',p_outputs);
  replay:=public.hq_c120_record_operation(p_operation_id,null,'開始',payload,v); if replay is not null then return replay; end if;
  if nullif(btrim(coalesce(p_place,'')),'') is null then raise exception '作業場所を選んでください'; end if;
  if p_started_at is null or not isfinite(p_started_at) or p_started_at>clock_timestamp() then raise exception '開始時刻を正しく入れてください'; end if;
  if coalesce(array_length(p_lot_ids,1),0)<1 or array_position(p_lot_ids,null) is not null then raise exception '原料を1つ以上選んでください'; end if;
  if coalesce(array_length(p_staff_ids,1),0)<1 or array_position(p_staff_ids,null) is not null then raise exception '作業者を1人以上選んでください'; end if;
  ids:=array(select distinct x from unnest(p_lot_ids) x order by x); if array_length(ids,1)<>array_length(p_lot_ids,1) then raise exception '同じ原料ロットを重複して指定できません'; end if;
  for l in select * from public.hq_lots_v1400 where id=any(ids) order by id for update loop
    if l.status not in ('在庫あり','在庫なし') then raise exception '原料 % は受け入れ済みではありません',l.lot_no; end if;
    if raw is null then raw:=l.item_name; elsif raw<>l.item_name then raise exception '原料の品目をそろえてください'; end if;
  end loop;
  if (select count(*) from public.hq_lots_v1400 where id=any(ids))<>array_length(ids,1) then raise exception '原料が見つかりません'; end if;
  outs:=public.hq_c120_outputs(raw,p_outputs,false);
  for s in select * from public.hq_staff_v1500 where id=any(p_staff_ids) order by id for update loop
    if s.deleted_at is not null then raise exception '%さんは削除済みです',s.name; end if;
    if exists(select 1 from public.hq_work_members_v1500 m join public.hq_works_v1500 ow on ow.id=m.work_id where m.staff_id=s.id and ow.status<>'取消' and m.start_at<clock_timestamp() and coalesce(m.end_at,'infinity'::timestamptz)>p_started_at) then raise exception '%さんの作業時間がほかの作業と重なっています',s.name; end if;
  end loop;
  if (select count(*) from public.hq_staff_v1500 where id=any(p_staff_ids) and deleted_at is null)<>array_length(p_staff_ids,1) then raise exception '作業者が見つかりません'; end if;
  insert into public.hq_works_v1500(operation_id,kind,task_name,place,work_date,status,prep_master_id,raw_item_name,product_name,expiry_days,outputs,started_at,created_by_name,c120_flow,review_status,history)
  values(p_operation_id,'下処理','下処理',btrim(p_place),(p_started_at at time zone 'Asia/Tokyo')::date,'作業中',null,raw,
    (select string_agg(value->>'name','・' order by value->>'name') from jsonb_array_elements(outs)),2,outs,p_started_at,v.display_name,true,'draft',
    jsonb_build_array(jsonb_build_object('at',now(),'by',v.display_name,'actor_id',v.id,'action','下処理開始','started_at',p_started_at,'outputs',outs))) returning * into w;
  update public.hq_prep_operations_v1199c120 set work_id=w.id where operation_id=p_operation_id;
  insert into public.hq_work_materials_v1500(work_id,lot_id,lot_no,item_name,unit,pack_kg)
    select w.id,src.id,src.lot_no,src.item_name,src.unit,case when src.unit='kg' then null else public.hq_c117_lot_pack_kg(src) end from public.hq_lots_v1400 src where src.id=any(ids);
  insert into public.hq_work_members_v1500(work_id,staff_id,staff_name,team,phase,start_at)
    select w.id,src.id,src.name,src.team,'作業',p_started_at from public.hq_staff_v1500 src where src.id=any(p_staff_ids);
  return public.hq_c120_finish_operation(p_operation_id,jsonb_build_object('ok',true,'id',w.id,'updated_at',w.updated_at,'outputs',outs));
end $f$;

create or replace function public.hq_prep_end_v1199c120(p_work_id uuid,p_operation_id uuid,p_expected_updated_at timestamptz,p_ended_at timestamptz)
returns jsonb language plpgsql security definer set search_path to ''
as $f$
declare v public.profiles; w public.hq_works_v1500%rowtype; r jsonb; payload jsonb; updated timestamptz;
begin
  v:=public.hq_actor_v1400(array['admin','hq_worker','hq_prep']); payload:=jsonb_build_object('work_id',p_work_id,'expected_updated_at',p_expected_updated_at,'ended_at',p_ended_at);
  r:=public.hq_c120_record_operation(p_operation_id,p_work_id,'終了',payload,v); if r is not null then return r; end if;
  select * into w from public.hq_works_v1500 where id=p_work_id for update;
  if not found or not w.c120_flow or w.kind<>'下処理' then raise exception 'c120の下処理が見つかりません'; end if;
  if w.updated_at is distinct from p_expected_updated_at then return public.hq_c120_finish_operation(p_operation_id,jsonb_build_object('ok',false,'conflict',true,'current_updated_at',w.updated_at,'message','他の操作で内容が変わりました。画面を開き直してください')); end if;
  if w.status<>'作業中' then raise exception 'この作業はすでに終了しています'; end if;
  if p_ended_at is null or not isfinite(p_ended_at) or p_ended_at<=w.started_at or p_ended_at>clock_timestamp() then raise exception '終了時刻を正しく入れてください'; end if;
  if w.pause_kind<>'' or exists(select 1 from public.hq_work_pauses_v1199c116 where work_id=w.id and end_at is null) then raise exception '休憩・中断中の作業は、先に再開してから終了してください'; end if;
  if not exists(select 1 from public.hq_work_members_v1500 where work_id=w.id and phase='作業') then raise exception '作業者がいません'; end if;
  if exists(select 1 from public.hq_work_members_v1500 where work_id=w.id and (phase<>'作業' or start_at is null or start_at<w.started_at or start_at>=p_ended_at or (end_at is not null and (end_at<=start_at or end_at>p_ended_at)))) then raise exception '作業者の開始・終了時刻を確認してください'; end if;
  update public.hq_work_members_v1500 set end_at=p_ended_at,end_reason='作業終了',fixed_by_name=v.display_name,fixed_at=now() where work_id=w.id and end_at is null and phase='作業';
  if exists(select 1 from public.hq_work_members_v1500 where work_id=w.id and (end_at is null or end_at<=start_at)) then raise exception '作業者の終了時刻を確認してください'; end if;
  update public.hq_works_v1500 set status='入力待ち',ended_at=p_ended_at,history=history||jsonb_build_array(jsonb_build_object('at',now(),'by',v.display_name,'actor_id',v.id,'action','作業終了','ended_at',p_ended_at)),updated_at=now() where id=w.id returning updated_at into updated;
  return public.hq_c120_finish_operation(p_operation_id,jsonb_build_object('ok',true,'id',w.id,'updated_at',updated));
end $f$;

-- 新規日報、c120編集、旧終了作業の明示採用を同じ保存経路にする。
create or replace function public.hq_prep_report_save_v1199c120(
  p_work_id uuid,p_operation_id uuid,p_expected_updated_at timestamptz,p_report jsonb
) returns jsonb language plpgsql security definer set search_path to ''
as $f$
declare v public.profiles; w public.hq_works_v1500%rowtype; r jsonb; payload jsonb; l public.hq_lots_v1400%rowtype;
  v_work_date date; v_started timestamptz; v_ended timestamptz; raw text; outs jsonb; norm jsonb; mats jsonb:='[]'::jsonb; mt jsonb;
  lid uuid; qty numeric; expected numeric; available numeric; pack numeric; v_raw_kg numeric:=0; v_yield_kg numeric:=0; v_waste_kg numeric;
  old_snapshot jsonb; baseline jsonb; after_snapshot jsonb; std jsonb; v_standard numeric; v_tolerance numeric; updated timestamptz;
  ids uuid[]; old_ids uuid[]; is_new boolean:=false; direct_confirmed boolean:=false; next_review text; reason text;
begin
  v:=public.hq_actor_v1400(array['admin','hq_worker','hq_prep']);
  if jsonb_typeof(coalesce(p_report,'null'::jsonb))<>'object' then raise exception '日報の形が正しくありません'; end if;
  payload:=jsonb_build_object('work_id',p_work_id,'expected_updated_at',p_expected_updated_at,'report',p_report);
  r:=public.hq_c120_record_operation(p_operation_id,p_work_id,'日報保存',payload,v); if r is not null then return r; end if;
  begin v_work_date:=(p_report->>'work_date')::date; v_started:=(p_report->>'started_at')::timestamptz; v_ended:=(p_report->>'ended_at')::timestamptz; exception when others then raise exception '作業日・開始・終了時刻を正しく入れてください'; end;
  if v_work_date is null or v_started is null or v_ended is null or not isfinite(v_started) or not isfinite(v_ended) or v_ended<=v_started or v_started>clock_timestamp() or v_ended>clock_timestamp() or v_work_date<>(v_started at time zone 'Asia/Tokyo')::date then raise exception '作業日・開始・終了時刻を正しく入れてください'; end if;
  if nullif(btrim(coalesce(p_report->>'place','')),'') is null then raise exception '作業場所を入れてください'; end if;
  if p_work_id is null then
    if p_expected_updated_at is not null then raise exception '新規後入力には更新時刻を指定できません'; end if;
    is_new:=true;
    if jsonb_typeof(coalesce(p_report->'materials','null'::jsonb))<>'array' or jsonb_array_length(p_report->'materials')<1 then raise exception '原料を1つ以上指定してください'; end if;
    begin select array_agg(distinct (value->>'lot_id')::uuid order by (value->>'lot_id')::uuid) into ids from jsonb_array_elements(p_report->'materials'); exception when others then raise exception '原料を正しく指定してください'; end;
    if array_length(ids,1)<>jsonb_array_length(p_report->'materials') then raise exception '同じ原料ロットを重複して指定できません'; end if;
    for l in select * from public.hq_lots_v1400 where id=any(ids) order by id for update loop
      if l.status not in ('在庫あり','在庫なし') then raise exception '原料 % は受け入れ済みではありません',l.lot_no; end if;
      if raw is null then raw:=l.item_name; elsif raw<>l.item_name then raise exception '原料の品目をそろえてください'; end if;
    end loop;
    if (select count(*) from public.hq_lots_v1400 where id=any(ids))<>array_length(ids,1) then raise exception '原料が見つかりません'; end if;
    outs:=public.hq_c120_outputs_for_work(raw,p_report->'outputs',true,'[]'::jsonb,null,true);
    baseline:='{"materials":[]}'::jsonb;
  else
    if p_expected_updated_at is null then raise exception '編集には画面を開いた時刻が必要です'; end if;
    select * into w from public.hq_works_v1500 where id=p_work_id for update;
    if not found or w.kind<>'下処理' then raise exception '下処理が見つかりません'; end if;
    if w.updated_at is distinct from p_expected_updated_at then return public.hq_c120_finish_operation(p_operation_id,jsonb_build_object('ok',false,'conflict',true,'current_updated_at',w.updated_at,'message','他の操作で内容が変わりました。画面を開き直してください')); end if;
    if not w.c120_flow then perform public.hq_c120_adopt_legacy(w.id,'日報保存',v); select * into w from public.hq_works_v1500 where id=p_work_id for update; end if;
    if w.status not in ('入力待ち','清掃中','完了') then raise exception '作業終了後の日報だけ保存できます'; end if;
    if v.role='hq_prep' and w.review_status='confirmed' then raise exception '下処理班は社員確定後の日報を直接訂正できません。差し戻し後に編集してください'; end if;
    -- submitted は社員がまだ確定していないため、下処理班も保存すると draft に戻して再提出できる。
    if v.role='hq_prep' and w.review_status not in ('draft','submitted','returned') then raise exception 'この日報は編集できません'; end if;
    old_snapshot:=public.hq_c120_work_snapshot(w.id);
    raw:=w.raw_item_name;
    outs:=public.hq_c120_outputs_for_work(raw,p_report->'outputs',true,w.outputs,w.expiry_days,false);
    baseline:=coalesce(w.c120_applied_snapshot,'{"materials":[]}'::jsonb);
    direct_confirmed:=(w.confirm_status='確定' and w.review_status='confirmed');
  end if;
  if jsonb_typeof(coalesce(p_report->'materials','null'::jsonb))<>'array' or jsonb_array_length(p_report->'materials')<1 then raise exception '原料を1つ以上指定してください'; end if;
  begin select array_agg(distinct (value->>'lot_id')::uuid order by (value->>'lot_id')::uuid) into ids from jsonb_array_elements(p_report->'materials'); exception when others then raise exception '原料を正しく指定してください'; end;
  if array_length(ids,1)<>jsonb_array_length(p_report->'materials') then raise exception '同じ原料ロットを重複して指定できません'; end if;
  begin select array_agg(distinct (value->>'lot_id')::uuid order by (value->>'lot_id')::uuid) into old_ids from jsonb_array_elements(coalesce(baseline->'materials','[]'::jsonb)); exception when others then raise exception '保存済み原料を確認してください'; end;
  for l in select * from public.hq_lots_v1400 where id=any(coalesce(ids,'{}'::uuid[])||coalesce(old_ids,'{}'::uuid[])) order by id for update loop
    if l.status not in ('在庫あり','在庫なし') then raise exception '原料 % は受け入れ済みではありません',l.lot_no; end if;
    if l.item_name<>raw then raise exception '原料 % の品目が一致しません',l.lot_no; end if;
  end loop;
  if (select count(*) from public.hq_lots_v1400 where id=any(ids))<>array_length(ids,1) then raise exception '原料が見つかりません'; end if;
  for mt in select value from jsonb_array_elements(p_report->'materials') loop
    if jsonb_typeof(mt)<>'object' then raise exception '原料の形が正しくありません'; end if;
    begin lid:=(mt->>'lot_id')::uuid; exception when others then raise exception '原料を正しく指定してください'; end;
    select * into l from public.hq_lots_v1400 where id=lid;
    available:=public.hq_c120_available_qty(l.id,p_work_id,baseline,coalesce(w.stock_applied,false));
    -- c120の正規契約は全use_modeにsnapshot必須。移行中の旧画面のpartialだけは、
    -- 実数量をそのままexpectedとして扱い、意図せず既存画面を停止させない。
    if mt ? 'use_mode' then
      if mt->>'use_mode' not in ('all','partial') then raise exception '原料の使用方法を正しく選んでください'; end if;
      begin expected:=public.hq_c117_number(mt->>'expected_available_qty','原料の残数snapshot'); exception when others then raise exception '原料の残数snapshotを正しく入れてください'; end;
      if expected<>available then raise exception '原料 % の残数が変わりました。再読み込みしてください',l.lot_no; end if;
      if mt->>'use_mode'='all' then qty:=available; else qty:=public.hq_c117_number(mt->>'qty','使用原料の数'); end if;
    else
      qty:=public.hq_c117_number(mt->>'qty','使用原料の数');
    end if;
    if qty<0 or qty>available then raise exception '原料 % の予約可能数が不足しています',l.lot_no; end if;
    pack:=case when l.unit='kg' then 1 else public.hq_c117_lot_pack_kg(l) end;
    if pack is null or pack<=0 then raise exception '原料 % の量目が不明です',l.lot_no; end if;
    v_raw_kg:=v_raw_kg+qty*pack;
    mats:=mats||jsonb_build_array(jsonb_build_object('lot_id',l.id,'lot_no',l.lot_no,'item_name',l.item_name,'unit',l.unit,'pack_kg',case when l.unit='kg' then null else pack end,'qty',qty));
  end loop;
  select coalesce(sum((value->>'yield_kg')::numeric),0) into v_yield_kg from jsonb_array_elements(outs);
  if v_raw_kg<=0 or v_yield_kg>v_raw_kg then raise exception '出来高合計は使用合計を超えられません'; end if;
  v_waste_kg:=v_raw_kg-v_yield_kg;
  norm:=public.hq_c120_normalize_intervals(p_work_id,v_started,v_ended,p_report->'members',coalesce(p_report->'breaks','[]'::jsonb));
  std:=public.hq_c120_standard_snapshot(outs);
  if not is_new and not exists(
    (select value->>'master_id' from jsonb_array_elements(coalesce(w.outputs,'[]'::jsonb)))
    except
    (select value->>'master_id' from jsonb_array_elements(outs))
    union all
    (select value->>'master_id' from jsonb_array_elements(outs))
    except
    (select value->>'master_id' from jsonb_array_elements(coalesce(w.outputs,'[]'::jsonb)))
  ) then
    v_standard:=w.standard_rate; v_tolerance:=w.tolerance_points;
  else
    v_standard:=(std->>'standard_rate')::numeric; v_tolerance:=(std->>'tolerance_points')::numeric;
  end if;
  after_snapshot:=jsonb_build_object('work_date',v_work_date,'started_at',v_started,'ended_at',v_ended,'place',btrim(p_report->>'place'),'status','完了','confirm_status',case when is_new then '未確定' else w.confirm_status end,'review_status',case when is_new then 'draft' else w.review_status end,'materials',mats,'members',norm->'members','breaks',norm->'breaks','outputs',outs,'yield_kg',v_yield_kg,'waste_kg',v_waste_kg,'raw_kg',v_raw_kg,'standard_rate',v_standard,'tolerance_points',v_tolerance,'expiry_days',case when is_new then 2 else w.expiry_days end);
  if is_new then
    insert into public.hq_works_v1500(kind,task_name,place,work_date,status,prep_master_id,raw_item_name,product_name,expiry_days,waste_kg,yield_kg,inputs_saved_at,inputs_saved_by_name,confirm_status,stock_applied,history,started_at,ended_at,created_by_name,standard_rate,tolerance_points,report_entered_at,report_raw_kg,report_waste_kg,report_breaks,outputs,c120_flow,review_status,updated_at)
    values('下処理','下処理',btrim(p_report->>'place'),v_work_date,'完了',null,raw,(select string_agg(value->>'name','・' order by value->>'name') from jsonb_array_elements(outs)),2,v_waste_kg,v_yield_kg,now(),v.display_name,'未確定',false,
      jsonb_build_array(jsonb_build_object('at',now(),'by',v.display_name,'actor_id',v.id,'action','日報後入力','before',null,'after',after_snapshot)),v_started,v_ended,v.display_name,v_standard,v_tolerance,now(),v_raw_kg,v_waste_kg,norm->'breaks',outs,true,'draft',now()) returning * into w;
    p_work_id:=w.id; update public.hq_prep_operations_v1199c120 set work_id=w.id where operation_id=p_operation_id;
  else
    if direct_confirmed then
      reason:=nullif(btrim(coalesce(p_report->>'correction_reason','')),''); if reason is null then raise exception '確定後の訂正理由を入れてください'; end if;
      perform public.hq_c120_apply_stock_delta(w.id,baseline,mats,w.stock_applied,reason,v);
    end if;
    next_review:=case when w.review_status='submitted' then 'draft' else w.review_status end;
    update public.hq_works_v1500 set place=btrim(p_report->>'place'),work_date=v_work_date,product_name=(select string_agg(value->>'name','・' order by value->>'name') from jsonb_array_elements(outs)),
      outputs=outs,started_at=v_started,ended_at=v_ended,status='完了',pause_kind='',yield_kg=v_yield_kg,waste_kg=v_waste_kg,inputs_saved_at=now(),inputs_saved_by_name=v.display_name,report_entered_at=coalesce(report_entered_at,now()),report_raw_kg=v_raw_kg,report_waste_kg=v_waste_kg,report_breaks=norm->'breaks',standard_rate=v_standard,tolerance_points=v_tolerance,
      review_status=next_review,review_reason=case when next_review='draft' then null else review_reason end,
      c120_applied_snapshot=case when direct_confirmed then after_snapshot else c120_applied_snapshot end,
      history=history||jsonb_build_array(jsonb_build_object('at',now(),'by',v.display_name,'actor_id',v.id,'action',case when direct_confirmed then '確定後の社員訂正' else '日報保存' end,'reason',reason,'before',old_snapshot,'after',after_snapshot)),updated_at=now()
      where id=w.id returning updated_at into updated;
  end if;
  delete from public.hq_work_materials_v1500 where work_id=p_work_id;
  insert into public.hq_work_materials_v1500(work_id,lot_id,lot_no,item_name,unit,pack_kg,qty)
    select p_work_id,(value->>'lot_id')::uuid,value->>'lot_no',value->>'item_name',value->>'unit',nullif(value->>'pack_kg','')::numeric,(value->>'qty')::numeric from jsonb_array_elements(mats);
  if is_new or w.confirm_status='未確定' then perform public.hq_c117_guard_reservations(p_work_id); end if;
  delete from public.hq_work_members_v1500 where work_id=p_work_id;
  insert into public.hq_work_members_v1500(work_id,staff_id,staff_name,team,phase,start_at,end_at,end_reason,fixed_by_name,fixed_at)
    select p_work_id,(value->>'staff_id')::uuid,value->>'staff_name',value->>'team','作業',(value->>'start_at')::timestamptz,(value->>'end_at')::timestamptz,'日報保存',v.display_name,now() from jsonb_array_elements(norm->'members');
  delete from public.hq_work_pauses_v1199c116 where work_id=p_work_id and kind in ('休憩','中断') and end_at is not null;
  insert into public.hq_work_pauses_v1199c116(operation_id,work_id,kind,start_at,end_at,staff_ids,resumed_staff_ids,by_name,excluded_staff_ids,resume_operation_id)
    select (value->>'operation_id')::uuid,p_work_id,value->>'kind',(value->>'start_at')::timestamptz,(value->>'end_at')::timestamptz,
      array(select (x #>> '{}')::uuid from jsonb_array_elements(value->'staff_ids') x order by (x #>> '{}')::uuid),array(select (x #>> '{}')::uuid from jsonb_array_elements(value->'resumed_staff_ids') x order by (x #>> '{}')::uuid),v.display_name,
      array(select (x #>> '{}')::uuid from jsonb_array_elements(value->'excluded_staff_ids') x order by (x #>> '{}')::uuid),nullif(value->>'resume_operation_id','')::uuid from jsonb_array_elements(norm->'pauses');
  if is_new then update public.hq_works_v1500 set updated_at=now() where id=p_work_id returning updated_at into updated; end if;
  if direct_confirmed then perform public.hq_c120_sync_waste(p_work_id,v_waste_kg,v); end if;
  select * into w from public.hq_works_v1500 where id=p_work_id;
  return public.hq_c120_finish_operation(p_operation_id,jsonb_build_object('ok',true,'id',p_work_id,'updated_at',updated,'review_status',w.review_status,'stock_applied',w.stock_applied));
end $f$;

create or replace function public.hq_prep_submit_v1199c120(p_work_id uuid,p_operation_id uuid,p_expected_updated_at timestamptz)
returns jsonb language plpgsql security definer set search_path to ''
as $f$
declare v public.profiles; w public.hq_works_v1500%rowtype; r jsonb; payload jsonb; updated timestamptz; before jsonb;
begin
  v:=public.hq_actor_v1400(array['admin','hq_worker','hq_prep']); payload:=jsonb_build_object('work_id',p_work_id,'expected_updated_at',p_expected_updated_at);
  r:=public.hq_c120_record_operation(p_operation_id,p_work_id,'提出',payload,v); if r is not null then return r; end if;
  select * into w from public.hq_works_v1500 where id=p_work_id for update;
  if not found or w.kind<>'下処理' then raise exception '下処理が見つかりません'; end if;
  if w.updated_at is distinct from p_expected_updated_at then return public.hq_c120_finish_operation(p_operation_id,jsonb_build_object('ok',false,'conflict',true,'current_updated_at',w.updated_at,'message','他の操作で内容が変わりました。画面を開き直してください')); end if;
  if not w.c120_flow then perform public.hq_c120_adopt_legacy(w.id,'提出',v); select * into w from public.hq_works_v1500 where id=p_work_id for update; end if;
  if w.review_status not in ('draft','returned') or w.status<>'完了' or w.inputs_saved_at is null then raise exception '日報を保存してから内容確認をしてください'; end if;
  if not exists(select 1 from public.hq_work_materials_v1500 where work_id=w.id) or not exists(select 1 from public.hq_work_members_v1500 where work_id=w.id and phase='作業') then raise exception '原料と作業者を保存してください'; end if;
  before:=public.hq_c120_work_snapshot(w.id);
  update public.hq_works_v1500 set review_status='submitted',review_reason=null,reviewed_at=now(),reviewed_by_name=v.display_name,history=history||jsonb_build_array(jsonb_build_object('at',now(),'by',v.display_name,'actor_id',v.id,'action','入力者確認・社員確認待ち','before',before,'after',before||jsonb_build_object('review_status','submitted'))),updated_at=now() where id=w.id returning updated_at into updated;
  return public.hq_c120_finish_operation(p_operation_id,jsonb_build_object('ok',true,'id',w.id,'updated_at',updated,'review_status','submitted'));
end $f$;

create or replace function public.hq_prep_return_v1199c120(p_work_id uuid,p_operation_id uuid,p_expected_updated_at timestamptz,p_reason text)
returns jsonb language plpgsql security definer set search_path to ''
as $f$
declare v public.profiles; w public.hq_works_v1500%rowtype; r jsonb; payload jsonb; updated timestamptz; reason text; before jsonb;
begin
  v:=public.hq_actor_v1400(array['admin','hq_worker']); reason:=nullif(btrim(coalesce(p_reason,'')), ''); if reason is null then raise exception '差し戻し理由を入れてください'; end if;
  payload:=jsonb_build_object('work_id',p_work_id,'expected_updated_at',p_expected_updated_at,'reason',reason);
  r:=public.hq_c120_record_operation(p_operation_id,p_work_id,'差戻し',payload,v); if r is not null then return r; end if;
  select * into w from public.hq_works_v1500 where id=p_work_id for update;
  if not found or w.kind<>'下処理' then raise exception '下処理が見つかりません'; end if;
  if w.updated_at is distinct from p_expected_updated_at then return public.hq_c120_finish_operation(p_operation_id,jsonb_build_object('ok',false,'conflict',true,'current_updated_at',w.updated_at,'message','他の操作で内容が変わりました。画面を開き直してください')); end if;
  if not w.c120_flow then perform public.hq_c120_adopt_legacy(w.id,'差戻し',v); select * into w from public.hq_works_v1500 where id=p_work_id for update; end if;
  if w.review_status not in ('submitted','confirmed') then raise exception '社員確認待ちまたは確定済みの日報だけ差し戻せます'; end if;
  before:=public.hq_c120_work_snapshot(w.id);
  update public.hq_works_v1500 set review_status='returned',review_reason=reason,reviewed_at=now(),reviewed_by_name=v.display_name,history=history||jsonb_build_array(jsonb_build_object('at',now(),'by',v.display_name,'actor_id',v.id,'action','社員差戻し','reason',reason,'before',before,'after',before||jsonb_build_object('review_status','returned'))),updated_at=now() where id=w.id returning updated_at into updated;
  return public.hq_c120_finish_operation(p_operation_id,jsonb_build_object('ok',true,'id',w.id,'updated_at',updated,'review_status','returned','stock_applied',w.stock_applied));
end $f$;

create or replace function public.hq_prep_confirm_v1199c120(p_work_id uuid,p_operation_id uuid,p_expected_updated_at timestamptz,p_reason text)
returns jsonb language plpgsql security definer set search_path to ''
as $f$
declare v public.profiles; w public.hq_works_v1500%rowtype; r jsonb; payload jsonb; l public.hq_lots_v1400%rowtype; mats jsonb; before jsonb; after jsonb; baseline jsonb; updated timestamptz; apply_stock boolean; available numeric; qty numeric;
begin
  v:=public.hq_actor_v1400(array['admin','hq_worker']); payload:=jsonb_build_object('work_id',p_work_id,'expected_updated_at',p_expected_updated_at,'reason',nullif(btrim(coalesce(p_reason,'')),''));
  r:=public.hq_c120_record_operation(p_operation_id,p_work_id,'確定',payload,v); if r is not null then return r; end if;
  select * into w from public.hq_works_v1500 where id=p_work_id for update;
  if not found or not w.c120_flow or w.kind<>'下処理' then raise exception 'c120の下処理が見つかりません'; end if;
  if w.status='取消' or w.confirm_status='取消' then raise exception '取消済みの日報は確定できません'; end if;
  -- 先に楽観ロックを照合する。差戻し後の古い確定要求がreview_statusを戻すことはない。
  if w.updated_at is distinct from p_expected_updated_at then return public.hq_c120_finish_operation(p_operation_id,jsonb_build_object('ok',false,'conflict',true,'current_updated_at',w.updated_at,'message','他の操作で内容が変わりました。画面を開き直してください')); end if;
  if w.confirm_status='確定' and w.review_status='confirmed' then return public.hq_c120_finish_operation(p_operation_id,jsonb_build_object('ok',true,'already',true,'id',w.id,'updated_at',w.updated_at,'review_status','confirmed','stock_applied',w.stock_applied)); end if;
  if w.review_status<>'submitted' then raise exception '入力者が内容確認して社員確認待ちにした日報だけ確定できます'; end if;
  before:=public.hq_c120_work_snapshot(w.id);
  select coalesce(jsonb_agg(jsonb_build_object('lot_id',m.lot_id,'lot_no',m.lot_no,'item_name',m.item_name,'unit',m.unit,'pack_kg',m.pack_kg,'qty',m.qty) order by m.lot_id),'[]'::jsonb) into mats from public.hq_work_materials_v1500 m where m.work_id=w.id;
  baseline:=coalesce(w.c120_applied_snapshot,'{"materials":[]}'::jsonb);
  apply_stock:=case when w.confirm_status='確定' then w.stock_applied else public.hq_setting_on_v1500('stage2_stock') end;
  for l in select * from public.hq_lots_v1400 where id=any(array(select distinct (value->>'lot_id')::uuid from jsonb_array_elements(mats) union select distinct (value->>'lot_id')::uuid from jsonb_array_elements(coalesce(baseline->'materials','[]'::jsonb)))) order by id for update loop
    if l.status not in ('在庫あり','在庫なし') then raise exception '原料 % は受け入れ済みではありません',l.lot_no; end if;
    select coalesce(sum((value->>'qty')::numeric),0) into qty from jsonb_array_elements(mats) where (value->>'lot_id')::uuid=l.id;
    available:=public.hq_c120_available_qty(l.id,w.id,baseline,apply_stock);
    if qty>available then raise exception '原料 % の予約可能数が不足しています',l.lot_no; end if;
  end loop;
  perform public.hq_c120_apply_stock_delta(w.id,baseline,mats,apply_stock,coalesce(nullif(btrim(coalesce(p_reason,'')),''),'社員確定'),v);
  perform public.hq_c120_sync_waste(w.id,w.waste_kg,v);
  after:=before||jsonb_build_object('confirm_status','確定','review_status','confirmed');
  update public.hq_works_v1500 set confirm_status='確定',confirmed_at=now(),confirmed_by_name=v.display_name,stock_applied=apply_stock,review_status='confirmed',review_reason=null,reviewed_at=now(),reviewed_by_name=v.display_name,c120_applied_snapshot=after,
    history=history||jsonb_build_array(jsonb_build_object('at',now(),'by',v.display_name,'actor_id',v.id,'action',case when w.confirm_status='確定' then '差戻し後の社員再確定' else '社員確定' end,'reason',nullif(btrim(coalesce(p_reason,'')),''),'before',before,'after',after,'stock',apply_stock)),updated_at=now() where id=w.id returning updated_at into updated;
  return public.hq_c120_finish_operation(p_operation_id,jsonb_build_object('ok',true,'id',w.id,'updated_at',updated,'review_status','confirmed','stock_applied',apply_stock));
end $f$;

-- 作業中だけは、c120でも使用数保存を許可する。終了後の内容は日報確認RPCでのみ更新する。
create or replace function public.hq_work_save_material_qty_v1199c112(p_work_id uuid, p_material_id uuid, p_qty numeric)
returns jsonb language plpgsql security definer set search_path to ''
as $f$
declare v public.profiles; w public.hq_works_v1500%rowtype; mt public.hq_work_materials_v1500%rowtype;
begin
  v:=public.hq_actor_v1400(array['admin','hq_worker','hq_prep']);
  if p_qty is null or p_qty<0 or p_qty::text in ('NaN','Infinity','-Infinity') then raise exception '使用原料の数は0以上の数で入れてください'; end if;
  select * into w from public.hq_works_v1500 where id=p_work_id for update;
  if not found then raise exception '下処理が見つかりません'; end if;
  if w.kind<>'下処理' or w.status<>'作業中' or w.confirm_status<>'未確定' then raise exception '使用原料の数は未確定の作業中の下処理だけ保存できます'; end if;
  select * into mt from public.hq_work_materials_v1500 where id=p_material_id and work_id=w.id for update;
  if not found then raise exception 'この下処理の使用原料が見つかりません'; end if;
  update public.hq_work_materials_v1500 set qty=p_qty where id=mt.id;
  perform public.hq_c117_guard_reservations(w.id);
  update public.hq_works_v1500 set history=history||jsonb_build_array(jsonb_build_object('at',now(),'by',v.display_name,'action','作業中に原料使用数を保存','lot_id',mt.lot_id,'material_id',mt.id,'qty',p_qty)),updated_at=now() where id=w.id;
  return jsonb_build_object('ok',true,'material_id',mt.id,'qty',p_qty,'updated_at',(select updated_at from public.hq_works_v1500 where id=w.id));
end $f$;

-- c120日報編集時は、自身が確定済み在庫から既に使用した分を候補数に戻して表示する。
create or replace function public.hq_prep_available_lots_v1199c120(p_work_id uuid default null)
returns jsonb language plpgsql security definer set search_path to ''
as $f$
declare v public.profiles; w public.hq_works_v1500%rowtype; baseline jsonb:='{"materials":[]}'::jsonb; result jsonb;
begin
  v:=public.hq_actor_v1400(array['admin','hq_worker','hq_prep']);
  if p_work_id is not null then
    select * into w from public.hq_works_v1500 where id=p_work_id;
    if not found or w.kind<>'下処理' then raise exception '下処理が見つかりません'; end if;
    if w.stock_applied then
      baseline:=case when w.c120_flow then coalesce(w.c120_applied_snapshot,'{"materials":[]}'::jsonb)
        when w.confirm_status='確定' then public.hq_c120_work_snapshot(w.id)
        else '{"materials":[]}'::jsonb end;
    end if;
  end if;
  select coalesce(jsonb_agg(to_jsonb(l)||jsonb_build_object(
    'total_weight',to_jsonb(l)->'total_weight',
    'available_qty',public.hq_c120_available_qty(l.id,p_work_id,baseline,coalesce(w.stock_applied,false))
  ) order by l.hq_received_date nulls last,l.lot_no),'[]'::jsonb) into result
  from public.hq_lots_v1400 l where l.status in ('在庫あり','在庫なし');
  return result;
end $f$;

-- c120作業を旧入口から保存・確定・終了・清掃へ回して確認フローを迂回させない。
create or replace function public.hq_c120_reject_legacy_route(p_work_id uuid)
returns void language plpgsql security definer set search_path to ''
as $f$
declare w public.hq_works_v1500%rowtype;
begin
  if p_work_id is null then return; end if;
  select * into w from public.hq_works_v1500 where id=p_work_id for update;
  if found and w.c120_flow then raise exception 'c120の下処理は新しい確認フローから操作してください'; end if;
end $f$;

do $block$
declare f regprocedure; d text; p integer; needle text:=E'\nbegin\n'; injected text:=E'\nbegin\n  -- c120 legacy-route guard v1\n  perform public.hq_c120_reject_legacy_route(p_work_id);\n';
begin
  foreach f in array array[
    'public.hq_work_end_v1500(uuid)'::regprocedure,
    'public.hq_work_save_inputs_v1500(uuid,jsonb,numeric,numeric)'::regprocedure,
    'public.hq_prep_confirm_v1500(uuid,jsonb,numeric,numeric,text)'::regprocedure,
    'public.hq_work_save_inputs_v1199c116(uuid,jsonb,numeric,jsonb)'::regprocedure,
    'public.hq_prep_confirm_v1199c116(uuid,jsonb,numeric,jsonb,text)'::regprocedure,
    'public.hq_prep_correct_v1199c116(uuid,uuid,timestamp with time zone,jsonb,numeric,jsonb,text)'::regprocedure,
    'public.hq_prep_report_save_v1199c117(uuid,uuid,timestamp with time zone,jsonb)'::regprocedure,
    'public.hq_prep_confirm_v1199c117(uuid,timestamp with time zone,jsonb,numeric,jsonb,text)'::regprocedure,
    'public.hq_work_to_clean_v1500(uuid,boolean)'::regprocedure,
    'public.hq_member_fix_v1500(uuid,timestamp with time zone,timestamp with time zone,boolean)'::regprocedure,
    'public.hq_member_add_v1500(uuid,uuid,text,timestamp with time zone,timestamp with time zone)'::regprocedure
  ] loop
    d:=pg_get_functiondef(f);
    if position('-- c120 legacy-route guard v1' in d)>0 then continue; end if;
    if position('p_work_id uuid' in d)>0 then
      p:=position(needle in d);
      if p=0 then raise exception '旧入口の安全パッチ位置を確認できません: %',f; end if;
      d:=overlay(d placing injected from p for char_length(needle));
    elsif f='public.hq_member_fix_v1500(uuid,timestamp with time zone,timestamp with time zone,boolean)'::regprocedure then
      p:=position(needle in d);
      if p=0 then raise exception '旧入口の安全パッチ位置を確認できません: %',f; end if;
      d:=overlay(d placing E'\nbegin\n  -- c120 legacy-route guard v1\n  if exists(select 1 from public.hq_work_members_v1500 m join public.hq_works_v1500 w on w.id=m.work_id where m.id=p_member_id and w.c120_flow) then raise exception ''c120の下処理は新しい確認フローから操作してください''; end if;\n' from p for char_length(needle));
    else
      raise exception '旧入口の安全パッチ対象が変わりました: %',f;
    end if;
    execute d;
    if position('-- c120 legacy-route guard v1' in pg_get_functiondef(f))=0 then raise exception '旧入口の安全パッチに失敗しました: %',f; end if;
  end loop;
end $block$;

-- 公開RPCだけ authenticated。内部helper・台帳・archiveは直接実行不可。
do $block$
declare f text;
begin
  foreach f in array array[
    'public.hq_prep_start_v1199c120(uuid,text,uuid[],uuid[],timestamp with time zone,jsonb)',
    'public.hq_prep_end_v1199c120(uuid,uuid,timestamp with time zone,timestamp with time zone)',
    'public.hq_prep_report_save_v1199c120(uuid,uuid,timestamp with time zone,jsonb)',
    'public.hq_prep_submit_v1199c120(uuid,uuid,timestamp with time zone)',
    'public.hq_prep_return_v1199c120(uuid,uuid,timestamp with time zone,text)',
    'public.hq_prep_confirm_v1199c120(uuid,uuid,timestamp with time zone,text)',
    'public.hq_prep_available_lots_v1199c120(uuid)'
  ] loop
    execute format('revoke all on function %s from public, anon',f); execute format('grant execute on function %s to authenticated, service_role',f);
  end loop;
  foreach f in array array[
    'public.hq_c120_outputs(text,jsonb,boolean)','public.hq_c120_outputs_for_work(text,jsonb,boolean,jsonb,integer,boolean)',
    'public.hq_c120_standard_snapshot(jsonb)','public.hq_c120_work_snapshot(uuid)','public.hq_c120_record_operation(uuid,uuid,text,jsonb,public.profiles)',
    'public.hq_c120_finish_operation(uuid,jsonb)','public.hq_c120_adopt_legacy(uuid,text,public.profiles)',
    'public.hq_c120_normalize_intervals(uuid,timestamp with time zone,timestamp with time zone,jsonb,jsonb)','public.hq_c120_baseline_qty(jsonb,uuid)',
    'public.hq_c120_available_qty(uuid,uuid,jsonb,boolean)','public.hq_c120_apply_stock_delta(uuid,jsonb,jsonb,boolean,text,public.profiles)',
    'public.hq_c120_sync_waste(uuid,numeric,public.profiles)','public.hq_c120_reject_legacy_route(uuid)'
  ] loop execute format('revoke all on function %s from public, anon, authenticated, service_role',f); end loop;
end $block$;
commit;
notify pgrst,'reload schema';

/* 成功の確かめ方：下の10行がすべてOKなら成功です。 */
select 'c120列' as 確認,case when exists(select 1 from information_schema.columns where table_schema='public' and table_name='hq_works_v1500' and column_name='c120_applied_snapshot') then 'OK' else 'NG' end as 結果
union all select 'c120再送台帳',case when to_regclass('public.hq_prep_operations_v1199c120') is not null then 'OK' else 'NG' end
union all select '旧作業archive',case when to_regclass('public.hq_prep_legacy_archives_v1199c120') is not null then 'OK' else 'NG' end
union all select 'c120開始RPC',case when to_regprocedure('public.hq_prep_start_v1199c120(uuid,text,uuid[],uuid[],timestamp with time zone,jsonb)') is not null then 'OK' else 'NG' end
union all select 'c120終了RPC',case when to_regprocedure('public.hq_prep_end_v1199c120(uuid,uuid,timestamp with time zone,timestamp with time zone)') is not null then 'OK' else 'NG' end
union all select 'c120日報RPC',case when to_regprocedure('public.hq_prep_report_save_v1199c120(uuid,uuid,timestamp with time zone,jsonb)') is not null then 'OK' else 'NG' end
union all select 'c120確認待ちRPC',case when to_regprocedure('public.hq_prep_submit_v1199c120(uuid,uuid,timestamp with time zone)') is not null then 'OK' else 'NG' end
union all select 'c120差戻しRPC',case when to_regprocedure('public.hq_prep_return_v1199c120(uuid,uuid,timestamp with time zone,text)') is not null then 'OK' else 'NG' end
union all select 'c120確定RPC',case when to_regprocedure('public.hq_prep_confirm_v1199c120(uuid,uuid,timestamp with time zone,text)') is not null then 'OK' else 'NG' end
union all select 'c120原料候補RPC',case when to_regprocedure('public.hq_prep_available_lots_v1199c120(uuid)') is not null then 'OK' else 'NG' end;
