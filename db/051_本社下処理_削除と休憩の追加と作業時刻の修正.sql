/*
051_本社下処理_削除と休憩の追加と作業時刻の修正.sql（v1.199-c124）

前提：019〜050を番号順に実行済みであること。
SQL適用だけでは、既存の作業・在庫・履歴を変更しません。
*/
begin;

do $block$
begin
  if to_regclass('public.hq_works_v1500') is null
     or to_regclass('public.hq_work_members_v1500') is null
     or to_regclass('public.hq_work_pauses_v1199c116') is null
     or to_regclass('public.hq_prep_operations_v1199c116') is null
     or to_regprocedure('public.hq_actor_v1400(text[])') is null
     or to_regprocedure('public.hq_prep_unapply_v1500(uuid,public.profiles)') is null then
    raise exception '先に db/019〜050 を番号順に実行してください';
  end if;
end $block$;

-- c120は社員確認済み(review_status=confirmed)だけを確定後と扱う。
-- submitted / returned は confirm_status が過去の確定のままでも、再確認前なので確定前である。
create or replace function public.hq_c124_is_final(p_work public.hq_works_v1500)
returns boolean language sql stable security definer set search_path to ''
as $f$
  select p_work.confirm_status='確定'
     and (not coalesce(p_work.c120_flow,false) or p_work.review_status='confirmed')
$f$;

-- 045の削除処理を一箇所にし、公開RPCごとの差は認可だけにする。
create or replace function public.hq_c124_delete_work_core(p_work_id uuid, p_actor public.profiles)
returns jsonb language plpgsql security definer set search_path to ''
as $f$
declare w public.hq_works_v1500%rowtype; restored boolean:=false;
begin
  select * into w from public.hq_works_v1500 where id=p_work_id for update;
  if not found then raise exception '作業が見つかりません（すでに削除されています）'; end if;
  if w.stock_applied then perform public.hq_prep_unapply_v1500(w.id,p_actor); restored:=true; end if;
  insert into public.hq_deleted_works_v1500(work_id,work,materials,members,deleted_by_name)
  values(w.id,to_jsonb(w),
    coalesce((select jsonb_agg(to_jsonb(m)) from public.hq_work_materials_v1500 m where m.work_id=w.id),'[]'::jsonb),
    coalesce((select jsonb_agg(to_jsonb(m)) from public.hq_work_members_v1500 m where m.work_id=w.id),'[]'::jsonb),p_actor.display_name);
  delete from public.hq_lot_movements_v1400 where work_id=w.id and (cancelled_at is not null or movement_type='下処理取消');
  delete from public.hq_waste_v1500 where work_id=w.id and kind='下処理ロス';
  delete from public.hq_work_materials_v1500 where work_id=w.id;
  delete from public.hq_work_members_v1500 where work_id=w.id;
  delete from public.hq_works_v1500 where id=w.id;
  return jsonb_build_object('ok',true,'restored',restored);
end $f$;

create or replace function public.hq_work_delete_v1199c124(p_work_id uuid)
returns jsonb language plpgsql security definer set search_path to ''
as $f$
declare v public.profiles; w public.hq_works_v1500%rowtype;
begin
  v:=public.hq_actor_v1400(array['admin','hq_worker','hq_prep']);
  select * into w from public.hq_works_v1500 where id=p_work_id for update;
  if not found then raise exception '作業が見つかりません（すでに削除されています）'; end if;
  if v.role='hq_prep' and (w.kind<>'下処理' or public.hq_c124_is_final(w) or w.stock_applied) then
    raise exception '確定したあとの削除は、本社社員に頼んでください' using errcode='42501';
  end if;
  return public.hq_c124_delete_work_core(p_work_id,v);
end $f$;

create or replace function public.hq_work_pause_add_v1199c124(
  p_work_id uuid,p_operation_id uuid,p_staff_ids uuid[],p_at timestamptz default null
) returns jsonb language plpgsql security definer set search_path to ''
as $f$
declare v public.profiles; w public.hq_works_v1500%rowtype; old public.hq_work_pauses_v1199c116%rowtype;
  ids uuid[]; bad uuid[]; bad_name text; at_time timestamptz:=coalesce(p_at,clock_timestamp());
begin
  v:=public.hq_actor_v1400(array['admin','hq_worker','hq_prep']);
  if p_operation_id is null then raise exception 'operation_idが必要です'; end if;
  if coalesce(array_length(p_staff_ids,1),0)<1 or array_position(p_staff_ids,null) is not null then raise exception '休憩に入る人を選んでください'; end if;
  ids:=array(select distinct x from unnest(p_staff_ids) x order by x);
  if array_length(ids,1)<>array_length(p_staff_ids,1) then raise exception '休憩に入る人を重複して指定できません'; end if;
  select * into old from public.hq_work_pauses_v1199c116 where operation_id=p_operation_id for update;
  if found then
    if old.work_id=p_work_id and old.kind='休憩' and old.staff_ids=ids and (p_at is null or old.start_at=p_at) then
      return jsonb_build_object('ok',true,'already',true,'pause_id',old.id,'staff_ids',old.staff_ids,'start_at',old.start_at);
    end if;
    raise exception '同じoperation_idに異なる休憩は使えません';
  end if;
  select * into w from public.hq_works_v1500 where id=p_work_id for update;
  if not found or w.kind<>'下処理' or w.status<>'作業中' or w.confirm_status='取消' then raise exception '休憩を追加できる下処理が見つかりません'; end if;
  if w.pause_kind='中断' then raise exception '中断中は、休憩を追加できません。先に再開してください'; end if;
  if w.pause_kind not in ('','休憩') then raise exception '休憩を追加できる下処理が見つかりません'; end if;
  if at_time>clock_timestamp()+interval '60 seconds' then raise exception '未来の時刻は選べません'; end if;
  select array_agg(x order by x) into bad from unnest(ids) x
   where not exists(select 1 from public.hq_work_members_v1500 m where m.work_id=w.id and m.staff_id=x and m.phase='作業' and m.end_at is null);
  if bad is not null then raise exception 'いま作業中の人だけ選べます'; end if;
  select min(m.staff_name) into bad_name from public.hq_work_members_v1500 m
   where m.work_id=w.id and m.staff_id=any(ids) and m.phase='作業' and m.end_at is null and at_time<m.start_at;
  if bad_name is not null then raise exception '%さんの作業開始より前の時刻は選べません',bad_name; end if;
  insert into public.hq_work_pauses_v1199c116(operation_id,work_id,kind,start_at,staff_ids,by_name,excluded_staff_ids)
  values(p_operation_id,w.id,'休憩',at_time,ids,v.display_name,'{}'::uuid[]) returning * into old;
  update public.hq_work_members_v1500 set end_at=at_time,end_reason='休憩'
   where work_id=w.id and phase='作業' and end_at is null and staff_id=any(ids);
  update public.hq_works_v1500 set pause_kind='休憩',
    history=history||jsonb_build_array(jsonb_build_object('at',at_time,'by',v.display_name,'action','休憩に入る人を追加','staff_ids',ids)),updated_at=now() where id=w.id;
  return jsonb_build_object('ok',true,'pause_id',old.id,'staff_ids',ids,'start_at',at_time);
end $f$;

create or replace function public.hq_work_resume_v1199c124(
  p_work_id uuid,p_operation_id uuid,p_staff_ids uuid[],p_at timestamptz default null
) returns jsonb language plpgsql security definer set search_path to ''
as $f$
declare v public.profiles; w public.hq_works_v1500%rowtype; p public.hq_work_pauses_v1199c116%rowtype;
  staff public.hq_staff_v1500%rowtype; old public.hq_prep_operations_v1199c116%rowtype; ids uuid[]; matched uuid[];
  remaining uuid[]; all_remaining uuid[]; busy text; sid uuid; at_time timestamptz:=coalesce(p_at,clock_timestamp()); input jsonb;
  pause_rows jsonb:='[]'::jsonb; one_pause uuid:=null; n_pause integer:=0;
begin
  v:=public.hq_actor_v1400(array['admin','hq_worker','hq_prep']);
  if p_operation_id is null then raise exception 'operation_idが必要です'; end if;
  if coalesce(array_length(p_staff_ids,1),0)<1 or array_position(p_staff_ids,null) is not null then raise exception '再開する人を選んでください'; end if;
  ids:=array(select distinct x from unnest(p_staff_ids) x order by x);
  if array_length(ids,1)<>array_length(p_staff_ids,1) then raise exception '再開する人を重複して指定できません'; end if;
  if at_time>clock_timestamp()+interval '60 seconds' then raise exception '未来の時刻は選べません'; end if;
  input:=jsonb_build_object('work_id',p_work_id,'staff_ids',ids,'at',p_at);
  insert into public.hq_prep_operations_v1199c116(operation_id,work_id,action,input,created_by_name)
  values(p_operation_id,p_work_id,'再開',input,v.display_name) on conflict(operation_id) do nothing;
  if not found then
    select * into old from public.hq_prep_operations_v1199c116 where operation_id=p_operation_id for update;
    if old.action<>'再開' or old.input is distinct from input then return jsonb_build_object('ok',false,'idempotency_conflict',true,'message','同じoperation_idに異なる内容は使えません'); end if;
    if old.result is null then raise exception '同じ再開が処理中です。しばらく待ってから再表示してください'; end if;
    return old.result||jsonb_build_object('idempotent',true,'already',true);
  end if;
  select * into w from public.hq_works_v1500 where id=p_work_id for update;
  if not found or w.kind<>'下処理' or w.status<>'作業中' or w.pause_kind='' then raise exception '再開できる休憩・中断中の作業が見つかりません'; end if;
  for staff in select * from public.hq_staff_v1500 where id=any(ids) order by id for update loop
    if staff.deleted_at is not null then raise exception '%さんは削除済みです',staff.name; end if;
    if not exists(select 1 from public.hq_work_pauses_v1199c116 q where q.work_id=w.id and q.kind in ('休憩','中断') and q.end_at is null and staff.id=any(q.staff_ids) and not staff.id=any(q.resumed_staff_ids)) then raise exception '休憩・中断に入っていた人だけを再開できます'; end if;
    if exists(select 1 from public.hq_work_pauses_v1199c116 q where q.work_id=w.id and q.kind in ('休憩','中断') and q.end_at is null and staff.id=any(q.staff_ids) and at_time<=q.start_at) then raise exception '休憩開始より後の時刻を選べません'; end if;
    select o.task_name||coalesce('（'||o.place||'）','') into busy from public.hq_work_members_v1500 m join public.hq_works_v1500 o on o.id=m.work_id where m.staff_id=staff.id and m.end_at is null and m.work_id<>w.id limit 1;
    if busy is not null then raise exception '%さんは、ほかの作業（%）に入っています',staff.name,busy; end if;
  end loop;
  insert into public.hq_work_members_v1500(work_id,staff_id,staff_name,team,phase,start_at)
    select w.id,s.id,s.name,s.team,'作業',at_time from public.hq_staff_v1500 s where s.id=any(ids);
  for p in select * from public.hq_work_pauses_v1199c116 where work_id=w.id and kind in ('休憩','中断') and end_at is null order by start_at,id for update loop
    matched:=array(select x from unnest(ids) x where x=any(p.staff_ids) and not x=any(p.resumed_staff_ids) order by x);
    if coalesce(array_length(matched,1),0)=0 then continue; end if;
    remaining:=array(select x from unnest(p.staff_ids) x where not x=any(array(select distinct y from unnest(p.resumed_staff_ids||matched) y)) order by x);
    update public.hq_work_pauses_v1199c116 set resumed_staff_ids=array(select distinct y from unnest(p.resumed_staff_ids||matched) y order by y),
      end_at=case when coalesce(array_length(remaining,1),0)=0 then at_time else null end,
      resume_operation_id=case when coalesce(array_length(remaining,1),0)=0 then p_operation_id else null end where id=p.id;
    n_pause:=n_pause+1; one_pause:=p.id;
    foreach sid in array matched loop
      pause_rows:=pause_rows||jsonb_build_array(jsonb_build_object('pause_id',p.id,'staff_id',sid,'resumed_at',at_time));
    end loop;
  end loop;
  select coalesce(array_agg(distinct x order by x),'{}'::uuid[]) into all_remaining from public.hq_work_pauses_v1199c116 q cross join lateral unnest(q.staff_ids) x where q.work_id=w.id and q.kind in ('休憩','中断') and q.end_at is null and not x=any(q.resumed_staff_ids);
  update public.hq_works_v1500 set pause_kind=case when coalesce(array_length(all_remaining,1),0)=0 then '' else w.pause_kind end,
    history=history||jsonb_build_array(jsonb_build_object('at',at_time,'by',v.display_name,'action','再開','staff_ids',ids)),updated_at=now() where id=w.id;
  update public.hq_prep_operations_v1199c116 set result=jsonb_build_object('ok',true,'work_id',w.id,'pause_id',case when n_pause=1 then one_pause else null end,'staff_ids',ids,'remaining_staff_ids',all_remaining,'resumed_at',at_time,'resumed_at_by_pause',pause_rows),completed_at=now() where operation_id=p_operation_id;
  return (select result from public.hq_prep_operations_v1199c116 where operation_id=p_operation_id);
end $f$;

-- 既存の後入力休憩の重複検査も、c124で複数休憩をまたいだ部分再開を認識させる。
do $block$
declare d text; old_text text; new_text text;
begin
  d:=pg_get_functiondef('public.hq_work_break_add_v1199c116(uuid,uuid,timestamp with time zone,timestamp with time zone,uuid[])'::regprocedure);
  old_text:='o.result->>''pause_id''=p.id::text';
  new_text:='(o.result->>''pause_id''=p.id::text or exists(select 1 from jsonb_array_elements(coalesce(o.result->''resumed_at_by_pause'',''[]''::jsonb)) z where z->>''pause_id''=p.id::text and z->>''staff_id''=paused.staff_id::text))';
  if position(old_text in d)=0 then raise exception '後入力休憩の再開重複検査を確認してください'; end if;
  execute replace(d,old_text,new_text);
end $block$;

create or replace function public.hq_work_leave_v1199c124(p_work_id uuid,p_staff_id uuid,p_leave_at timestamptz default null)
returns jsonb language plpgsql security definer set search_path to ''
as $f$
declare v public.profiles; w public.hq_works_v1500%rowtype; m public.hq_work_members_v1500%rowtype; at_time timestamptz:=coalesce(p_leave_at,clock_timestamp());
begin
  v:=public.hq_actor_v1400(array['admin','hq_worker','hq_prep']);
  select * into w from public.hq_works_v1500 where id=p_work_id for update;
  if not found or w.status not in ('作業中','清掃中') then raise exception 'この人は、この作業に入っていません'; end if;
  select * into m from public.hq_work_members_v1500 where work_id=w.id and staff_id=p_staff_id and end_at is null for update;
  if not found then raise exception 'この人は、この作業に入っていません'; end if;
  if at_time<=m.start_at then raise exception '入った時刻より前には抜けられません'; end if;
  if at_time>clock_timestamp()+interval '60 seconds' then raise exception '未来の時刻は選べません'; end if;
  update public.hq_work_members_v1500 set end_at=at_time,end_reason='途中で抜けた',fixed_by_name=case when p_leave_at is null then fixed_by_name else v.display_name end,fixed_at=case when p_leave_at is null then fixed_at else now() end where id=m.id;
  update public.hq_works_v1500 set history=history||jsonb_build_array(jsonb_build_object('at',now(),'by',v.display_name,'action','途中で抜ける','staff_id',p_staff_id,'leave_at',at_time)),updated_at=now() where id=w.id;
  return jsonb_build_object('ok',true,'leave_at',at_time);
end $f$;

create or replace function public.hq_work_member_time_fix_v1199c124(p_member_id uuid,p_start timestamptz,p_end timestamptz)
returns jsonb language plpgsql security definer set search_path to ''
as $f$
declare v public.profiles; m public.hq_work_members_v1500%rowtype; w public.hq_works_v1500%rowtype; other public.hq_work_members_v1500%rowtype; other_work public.hq_works_v1500%rowtype; before jsonb; after jsonb; range_end timestamptz;
begin
  v:=public.hq_actor_v1400(array['admin','hq_worker','hq_prep']);
  select * into m from public.hq_work_members_v1500 where id=p_member_id for update;
  if not found then raise exception '記録が見つかりません'; end if;
  select * into w from public.hq_works_v1500 where id=m.work_id for update;
  if w.status='取消' then raise exception '取消済みの作業時間は直せません'; end if;
  if public.hq_c124_is_final(w) then raise exception '確定したあとの作業時間は、日報（社員の訂正）から直してください'; end if;
  if m.end_reason in ('休憩','中断','休憩（後入力）') or (m.end_at is null and w.pause_kind<>'') then raise exception '休憩の時間は「休憩の追加」や「押し忘れた休憩」から直してください'; end if;
  if p_start is null then raise exception '開始の時刻を入れてください'; end if;
  if p_end is not null and p_end<=p_start then raise exception '終了が開始より前になっています'; end if;
  if p_start>clock_timestamp()+interval '60 seconds' or (p_end is not null and p_end>clock_timestamp()+interval '60 seconds') then raise exception '未来の時刻は選べません'; end if;
  if p_end is null and w.status not in ('作業中','清掃中') then raise exception '作業中でない記録は、作業中には戻せません'; end if;
  -- 同じ人の全行をUUID順に先にロックして、再開・別作業開始との競合を防ぐ。
  for other in select * from public.hq_work_members_v1500 where staff_id=m.staff_id order by id for update loop
    if other.id=m.id then continue; end if;
    range_end:=coalesce(p_end,'infinity'::timestamptz);
    if other.start_at<range_end and coalesce(other.end_at,'infinity'::timestamptz)>p_start then
      select * into other_work from public.hq_works_v1500 where id=other.work_id;
      raise exception '%さんは、その時間に別の作業（%）に入っています',m.staff_name,coalesce(other_work.task_name,'不明');
    end if;
  end loop;
  if p_start=m.start_at and p_end is not distinct from m.end_at then return jsonb_build_object('ok',true,'unchanged',true); end if;
  before:=to_jsonb(m);
  update public.hq_work_members_v1500 set start_at=p_start,end_at=p_end,end_reason=case when p_end is null then null else coalesce(end_reason,'修正') end,fixed_by_name=v.display_name,fixed_at=now() where id=m.id;
  select to_jsonb(x) into after from public.hq_work_members_v1500 x where x.id=m.id;
  update public.hq_works_v1500 set history=history||jsonb_build_array(jsonb_build_object('at',now(),'by',v.display_name,'action','作業時間の修正','member',m.id,'staff',m.staff_id,'before',before,'after',after)),updated_at=now() where id=w.id;
  return jsonb_build_object('ok',true,'member_id',m.id,'start_at',p_start,'end_at',p_end);
end $f$;

do $block$
declare f text;
begin
  foreach f in array array[
    'public.hq_work_delete_v1199c124(uuid)',
    'public.hq_work_pause_add_v1199c124(uuid,uuid,uuid[],timestamp with time zone)',
    'public.hq_work_resume_v1199c124(uuid,uuid,uuid[],timestamp with time zone)',
    'public.hq_work_leave_v1199c124(uuid,uuid,timestamp with time zone)',
    'public.hq_work_member_time_fix_v1199c124(uuid,timestamp with time zone,timestamp with time zone)'
  ] loop
    execute format('revoke all on function %s from public, anon',f);
    execute format('grant execute on function %s to authenticated, service_role',f);
  end loop;
  foreach f in array array[
    'public.hq_c124_is_final(public.hq_works_v1500)',
    'public.hq_c124_delete_work_core(uuid,public.profiles)'
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role',f);
  end loop;
end $block$;

commit;
notify pgrst,'reload schema';

/* 成功の確かめ方：下の6行がすべてOKなら成功です。 */
select 'c124削除RPC' as 確認,case when to_regprocedure('public.hq_work_delete_v1199c124(uuid)') is not null then 'OK' else 'NG' end as 結果
union all select 'c124休憩追加RPC',case when to_regprocedure('public.hq_work_pause_add_v1199c124(uuid,uuid,uuid[],timestamp with time zone)') is not null then 'OK' else 'NG' end
union all select 'c124再開RPC',case when to_regprocedure('public.hq_work_resume_v1199c124(uuid,uuid,uuid[],timestamp with time zone)') is not null then 'OK' else 'NG' end
union all select 'c124抜けるRPC',case when to_regprocedure('public.hq_work_leave_v1199c124(uuid,uuid,timestamp with time zone)') is not null then 'OK' else 'NG' end
union all select 'c124作業時間訂正RPC',case when to_regprocedure('public.hq_work_member_time_fix_v1199c124(uuid,timestamp with time zone,timestamp with time zone)') is not null then 'OK' else 'NG' end
union all select 'c124内部helper非公開',case when not has_function_privilege('authenticated','public.hq_c124_delete_work_core(uuid,public.profiles)','execute') then 'OK' else 'NG' end;
