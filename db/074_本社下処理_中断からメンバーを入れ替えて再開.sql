/*
074_本社下処理_中断からメンバーを入れ替えて再開.sql（v1.199-c171）

困っていたこと（2026-11-26 本社・白菜）：
  中断から再開するとき、メンバーがまったく変わることがあるのに、再開で選べるのは中断前にいた人だけだった。
  中断中は「途中から入る人を追加」も押せなかった。
直したこと：
  「中断から再開する」を1回の操作で決められるようにする（hq_work_resume_swap_v1199c171）。
  ・戻る人：中断前のメンバーから選ぶ（0人でもよい）
  ・戻らない人：中断した時刻で抜けた扱い（end_reason＝途中で抜けた）。中断の記録からも外す
  ・新しく入る人：同じ操作で追加。再開した時刻から作業
  ・戻る人も新しい人もいないときは再開できない
  ・中断前のメンバーが1人も戻らないときは、中断の記録を消す（作業終了で抜けた扱いにするときと同じ）
  ・同じ操作を2回送っても1回分だけ（operation_id。操作の記録は「再開」、中身に swap:true）
  ・休憩のときは今までの「再開」を使う（休憩中の人がいるときは、この操作はできない）
前提：051・072 まで実行済みであること。今までのデータは変えません。何度実行しても同じ結果になります。
元に戻すとき：drop function if exists public.hq_work_resume_swap_v1199c171(uuid, uuid, uuid[], uuid[], timestamptz);
*/
begin;

create or replace function public.hq_work_resume_swap_v1199c171(
  p_work_id uuid, p_operation_id uuid, p_back_staff_ids uuid[], p_new_staff_ids uuid[], p_at timestamptz default null
) returns jsonb
language plpgsql
security definer
set search_path to ''
as $f$
declare v public.profiles; w public.hq_works_v1500%rowtype; p public.hq_work_pauses_v1199c116%rowtype; staff public.hq_staff_v1500%rowtype;
  old public.hq_prep_operations_v1199c116%rowtype; back uuid[]; news uuid[]; waiting uuid[]; left_ids uuid[]; kept uuid[]; busy text;
  at_time timestamptz := coalesce(p_at, clock_timestamp()); input jsonb; v_result jsonb; deleted_pauses integer := 0;
begin
  v := public.hq_actor_v1400(array['admin','hq_worker','hq_prep']);
  if p_operation_id is null then raise exception 'operation_idが必要です'; end if;
  if array_position(coalesce(p_back_staff_ids, '{}'), null) is not null or array_position(coalesce(p_new_staff_ids, '{}'), null) is not null then raise exception '人の指定が正しくありません'; end if;
  back := array(select distinct x from unnest(coalesce(p_back_staff_ids, '{}'::uuid[])) x order by x);
  news := array(select distinct x from unnest(coalesce(p_new_staff_ids, '{}'::uuid[])) x order by x);
  if coalesce(array_length(back, 1), 0) + coalesce(array_length(news, 1), 0) = 0 then raise exception '再開する人を選んでください（戻る人か、新しく入る人）'; end if;
  if back && news then raise exception '同じ人を「戻る人」と「新しく入る人」の両方に選べません'; end if;
  if at_time > clock_timestamp() + interval '60 seconds' then raise exception '未来の時刻は選べません'; end if;
  input := jsonb_build_object('swap', true, 'work_id', p_work_id, 'back', back, 'new', news, 'at', p_at);
  insert into public.hq_prep_operations_v1199c116(operation_id, work_id, action, input, created_by_name)
  values (p_operation_id, p_work_id, '再開', input, v.display_name) on conflict (operation_id) do nothing;
  if not found then
    select * into old from public.hq_prep_operations_v1199c116 where operation_id = p_operation_id for update;
    if old.action <> '再開' or old.input is distinct from input then
      return jsonb_build_object('ok', false, 'idempotency_conflict', true, 'message', '同じoperation_idに異なる内容は使えません');
    end if;
    if old.result is null then raise exception '同じ再開が処理中です。しばらく待ってから再表示してください'; end if;
    return old.result || jsonb_build_object('idempotent', true, 'already', true);
  end if;

  select * into w from public.hq_works_v1500 where id = p_work_id for update;
  if not found or w.kind <> '下処理' or w.status <> '作業中' or w.pause_kind <> '中断' then raise exception '中断中の作業が見つかりません'; end if;
  if exists (select 1 from public.hq_work_pauses_v1199c116 q where q.work_id = w.id and q.end_at is null and q.kind <> '中断') then
    raise exception '休憩中の人がいるため、入れ替えての再開はできません。いつもの「再開」を使ってください';
  end if;
  -- 中断から戻っていない人（中断前のメンバー）
  select coalesce(array_agg(distinct x order by x), '{}'::uuid[]) into waiting
    from public.hq_work_pauses_v1199c116 q cross join lateral unnest(q.staff_ids) x
   where q.work_id = w.id and q.kind = '中断' and q.end_at is null and not x = any(coalesce(q.resumed_staff_ids, '{}'::uuid[]));
  if not (back <@ waiting) then raise exception '「戻る人」は中断前のメンバーから選んでください'; end if;
  if news && waiting then raise exception '中断前のメンバーは「戻る人」で選んでください'; end if;
  if exists (select 1 from public.hq_work_pauses_v1199c116 q where q.work_id = w.id and q.kind = '中断' and q.end_at is null and at_time <= q.start_at) then
    raise exception '中断した時刻より後の時刻を選んでください';
  end if;
  for staff in select * from public.hq_staff_v1500 where id = any(back || news) order by id for update loop
    if staff.deleted_at is not null then raise exception '%さんは削除済みです', staff.name; end if;
    if exists (select 1 from public.hq_work_members_v1500 m where m.work_id = w.id and m.staff_id = staff.id and m.end_at is null) then
      raise exception '%さんは、もうこの作業に入っています', staff.name;
    end if;
    select o.task_name || coalesce('（' || o.place || '）', '') into busy from public.hq_work_members_v1500 m join public.hq_works_v1500 o on o.id = m.work_id
     where m.staff_id = staff.id and m.end_at is null and m.work_id <> w.id limit 1;
    if busy is not null then raise exception '%さんは、ほかの作業（%）に入っています。先にそちらを抜けてください', staff.name, busy; end if;
  end loop;
  if (select count(*) from public.hq_staff_v1500 where id = any(back || news)) <> coalesce(array_length(back, 1), 0) + coalesce(array_length(news, 1), 0) then
    raise exception '見つからない人が含まれています';
  end if;
  left_ids := array(select x from unnest(waiting) x where not x = any(back) order by x);

  -- 戻る人・新しく入る人は、再開した時刻から作業
  insert into public.hq_work_members_v1500(work_id, staff_id, staff_name, team, phase, start_at)
    select w.id, s.id, s.name, s.team, '作業', at_time from public.hq_staff_v1500 s where s.id = any(back || news);
  -- 戻らない人は、中断した時刻で抜けた扱い。中断の記録からも外す
  for p in select * from public.hq_work_pauses_v1199c116 where work_id = w.id and kind = '中断' and end_at is null order by start_at, id for update loop
    update public.hq_work_members_v1500 set end_reason = '途中で抜けた'
     where work_id = w.id and staff_id = any(left_ids) and staff_id = any(p.staff_ids) and end_at = p.start_at and end_reason = '中断';
    kept := array(select x from unnest(p.staff_ids) x where not x = any(left_ids) order by x);
    if coalesce(array_length(kept, 1), 0) = 0 then
      delete from public.hq_work_pauses_v1199c116 where id = p.id; deleted_pauses := deleted_pauses + 1;
    else
      update public.hq_work_pauses_v1199c116 set staff_ids = kept, resumed_staff_ids = kept, end_at = at_time, resume_operation_id = p_operation_id where id = p.id;
    end if;
  end loop;
  update public.hq_works_v1500 set pause_kind = '',
    history = history || jsonb_build_array(jsonb_build_object('at', at_time, 'by', v.display_name, 'actor_id', v.id, 'action', '再開（入れ替え）',
      'back_staff_ids', back, 'new_staff_ids', news, 'left_staff_ids', left_ids)),
    updated_at = now()
   where id = w.id;
  v_result := jsonb_build_object('ok', true, 'work_id', w.id, 'back_staff_ids', back, 'new_staff_ids', news, 'left_staff_ids', left_ids,
    'resumed_at', at_time, 'deleted_pauses', deleted_pauses);
  update public.hq_prep_operations_v1199c116 set result = v_result, completed_at = now() where operation_id = p_operation_id;
  return v_result;
end
$f$;
revoke all on function public.hq_work_resume_swap_v1199c171(uuid, uuid, uuid[], uuid[], timestamptz) from public, anon;
grant execute on function public.hq_work_resume_swap_v1199c171(uuid, uuid, uuid[], uuid[], timestamptz) to authenticated;

commit;
notify pgrst, 'reload schema';

-- ===== 確認（OK なら成功） =====
select case when to_regprocedure('public.hq_work_resume_swap_v1199c171(uuid,uuid,uuid[],uuid[],timestamptz)') is not null then 'OK' else 'NG' end as "中断から入れ替えて再開";
