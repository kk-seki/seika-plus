/*
058_本社下処理_休憩中の人がいても作業終了.sql（v1.199-c137）

困っていたこと（2026-11-20 本社）：
  何人かが休憩に入り、残った人だけで作業が終わったとき、
  ・休憩中の人がいると「作業終了」を押せない
  ・休憩から戻す操作をすると、戻った人の時刻が作業終了より後になり登録できない
直したこと（hq_prep_end_v1199c120 を置き換え）：
  休憩（中断ではない）の途中でも作業終了できる。
  まだ戻っていない人は「休憩に入った時刻で作業を抜けた」扱いにする（end_reason を「途中で抜けた」に変更）。
  休憩の記録からはその人を外し、誰も戻っていない休憩は記録ごと消す。
  一部の人が戻っていた休憩は、最後の人が戻った時刻で休憩を終える。
  中断（全員止める）のときは、今までどおり再開してから終了する。
何度実行しても同じ結果になります。
*/
begin;

create or replace function public.hq_prep_end_v1199c120(p_work_id uuid, p_operation_id uuid, p_expected_updated_at timestamptz, p_ended_at timestamptz)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare v public.profiles; w public.hq_works_v1500%rowtype; r jsonb; payload jsonb; updated timestamptz;
  p public.hq_work_pauses_v1199c116%rowtype; left_ids uuid[]; kept uuid[]; last_back timestamptz; left_names text;
begin
  v:=public.hq_actor_v1400(array['admin','hq_worker','hq_prep']); payload:=jsonb_build_object('work_id',p_work_id,'expected_updated_at',p_expected_updated_at,'ended_at',p_ended_at);
  r:=public.hq_c120_record_operation(p_operation_id,p_work_id,'終了',payload,v); if r is not null then return r; end if;
  select * into w from public.hq_works_v1500 where id=p_work_id for update;
  if not found or not w.c120_flow or w.kind<>'下処理' then raise exception 'c120の下処理が見つかりません'; end if;
  if w.updated_at is distinct from p_expected_updated_at then return public.hq_c120_finish_operation(p_operation_id,jsonb_build_object('ok',false,'conflict',true,'current_updated_at',w.updated_at,'message','他の操作で内容が変わりました。画面を開き直してください')); end if;
  if w.status<>'作業中' then raise exception 'この作業はすでに終了しています'; end if;
  if p_ended_at is null or not isfinite(p_ended_at) or p_ended_at<=w.started_at or p_ended_at>clock_timestamp() then raise exception '終了時刻を正しく入れてください'; end if;
  if w.pause_kind='中断' or exists(select 1 from public.hq_work_pauses_v1199c116 where work_id=w.id and end_at is null and kind<>'休憩') then
    raise exception '中断中の作業は、先に再開してから終了してください';
  end if;

  -- c137：休憩から戻っていない人は、休憩に入った時刻で作業を抜けた扱いにする
  for p in select * from public.hq_work_pauses_v1199c116 where work_id=w.id and kind='休憩' and end_at is null order by start_at,id for update loop
    if p_ended_at<p.start_at then raise exception '終了時刻は、休憩に入った時刻（%）より後にしてください',to_char(p.start_at at time zone 'Asia/Tokyo','HH24:MI'); end if;
    left_ids:=array(select x from unnest(p.staff_ids) x where not x=any(coalesce(p.resumed_staff_ids,'{}'::uuid[])) order by x);
    kept:=array(select x from unnest(p.staff_ids) x where x=any(coalesce(p.resumed_staff_ids,'{}'::uuid[])) order by x);
    if coalesce(array_length(left_ids,1),0)>0 then
      update public.hq_work_members_v1500 set end_reason='途中で抜けた',fixed_by_name=v.display_name,fixed_at=now()
       where work_id=w.id and phase='作業' and staff_id=any(left_ids) and end_at=p.start_at and end_reason='休憩';
      select string_agg(m.staff_name,'・' order by m.staff_name) into left_names from public.hq_work_members_v1500 m
       where m.work_id=w.id and m.staff_id=any(left_ids) and m.end_at=p.start_at;
    end if;
    if coalesce(array_length(kept,1),0)=0 then
      delete from public.hq_work_pauses_v1199c116 where id=p.id;
    else
      select max(m.start_at) into last_back from public.hq_work_members_v1500 m
       where m.work_id=w.id and m.staff_id=any(kept) and m.start_at>=p.start_at and m.start_at<=p_ended_at;
      update public.hq_work_pauses_v1199c116 set staff_ids=kept,end_at=coalesce(last_back,p_ended_at) where id=p.id;
    end if;
    update public.hq_works_v1500 set history=history||jsonb_build_array(jsonb_build_object('at',now(),'by',v.display_name,'actor_id',v.id,
      'action','休憩のまま作業終了','pause_start_at',p.start_at,'left_staff_ids',to_jsonb(left_ids),'left_names',left_names)) where id=w.id;
  end loop;
  update public.hq_works_v1500 set pause_kind='' where id=w.id and pause_kind='休憩';

  if not exists(select 1 from public.hq_work_members_v1500 where work_id=w.id and phase='作業') then raise exception '作業者がいません'; end if;
  if exists(select 1 from public.hq_work_members_v1500 where work_id=w.id and (phase<>'作業' or start_at is null or start_at<w.started_at or start_at>=p_ended_at or (end_at is not null and (end_at<=start_at or end_at>p_ended_at)))) then raise exception '作業者の開始・終了時刻を確認してください'; end if;
  update public.hq_work_members_v1500 set end_at=p_ended_at,end_reason='作業終了',fixed_by_name=v.display_name,fixed_at=now() where work_id=w.id and end_at is null and phase='作業';
  if exists(select 1 from public.hq_work_members_v1500 where work_id=w.id and (end_at is null or end_at<=start_at)) then raise exception '作業者の終了時刻を確認してください'; end if;
  update public.hq_works_v1500 set status='入力待ち',ended_at=p_ended_at,history=history||jsonb_build_array(jsonb_build_object('at',now(),'by',v.display_name,'actor_id',v.id,'action','作業終了','ended_at',p_ended_at)),updated_at=now() where id=w.id returning updated_at into updated;
  return public.hq_c120_finish_operation(p_operation_id,jsonb_build_object('ok',true,'id',w.id,'updated_at',updated));
end $function$;

commit;
notify pgrst, 'reload schema';

-- 確認：「OK」なら成功です
select '休憩中でも作業終了できる関数' as 確認項目,
  case when (select prosrc from pg_proc where proname='hq_prep_end_v1199c120') like '%休憩のまま作業終了%' then 'OK' else '要確認' end as 判定;
