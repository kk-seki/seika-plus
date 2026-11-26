/*
072_本社下処理_休憩からの再開を取り消す.sql（v1.199-c169）

困っていたこと（2026-11-26 本社・キャベツ）：
  休憩に入った4人が戻らないまま作業が終わったのに、12:31に「再開」が押されて4人が作業に戻ったことになった。
  そのため、本当の終了時刻（11:45）で作業終了できなかった。アプリには再開を取り消す操作がなかった。
直したこと：
  作業中の画面で、休憩・中断から「再開」した人の再開を、1人ずつ取り消せるようにする（hq_work_resume_undo_v1199c169）。
  ・再開で作った作業の記録（再開した時刻〜）を消し、その人を休憩・中断に戻す。
  ・休憩・中断がもう閉じていた（全員が戻っていた）ときは、開け直す。
  ・作業の履歴に「再開の取り消し」を残す。
  ・できるのは、再開してから「抜ける」などをしていない人（その人の記録が作業中のまま）だけ。作業終了後は日報で直す。
前提：051 まで実行済みであること。今までのデータは変えません。何度実行しても同じ結果になります。
元に戻すとき：drop function if exists public.hq_work_resume_undo_v1199c169(uuid, uuid, timestamptz);
*/
begin;

create or replace function public.hq_work_resume_undo_v1199c169(p_work_id uuid, p_member_id uuid, p_expected_updated_at timestamptz)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $f$
declare v public.profiles; w public.hq_works_v1500%rowtype; m public.hq_work_members_v1500%rowtype; p public.hq_work_pauses_v1199c116%rowtype;
  reopened boolean := false;
begin
  v := public.hq_actor_v1400(array['admin','hq_worker','hq_prep']);
  select * into w from public.hq_works_v1500 where id = p_work_id for update;
  if not found or w.kind <> '下処理' then raise exception '作業が見つかりません'; end if;
  if w.status <> '作業中' then raise exception '作業中のときだけ取り消せます。作業終了のあとは日報で直してください'; end if;
  if w.updated_at is distinct from p_expected_updated_at then
    return jsonb_build_object('ok', false, 'conflict', true, 'message', '他の操作で内容が変わりました。画面を開き直してください');
  end if;
  select * into m from public.hq_work_members_v1500 where id = p_member_id and work_id = w.id for update;
  if not found then raise exception '作業者の記録が見つかりません'; end if;
  if m.end_at is not null or m.phase <> '作業' then raise exception '%さんは、もう作業を抜けています。抜けたあとは取り消せません', m.staff_name; end if;
  -- この人が戻った休憩・中断（再開の時刻より前に始まった、いちばん新しいもの）
  select * into p from public.hq_work_pauses_v1199c116
   where work_id = w.id and kind in ('休憩','中断') and m.staff_id = any(staff_ids) and m.staff_id = any(coalesce(resumed_staff_ids, '{}'::uuid[]))
     and start_at < m.start_at
   order by start_at desc, id desc limit 1 for update;
  if not found then raise exception '%さんは、休憩・中断から戻った記録ではありません', m.staff_name; end if;
  -- 休憩・中断のあと、この記録より前にこの人の別の記録があるときは取り消さない（再開で作った記録ではない）
  if exists (select 1 from public.hq_work_members_v1500 x where x.work_id = w.id and x.staff_id = m.staff_id and x.id <> m.id
               and x.start_at >= p.start_at and x.start_at < m.start_at) then
    raise exception '%さんの記録が休憩のあとにほかにもあるため、取り消せません。日報で直してください', m.staff_name;
  end if;

  delete from public.hq_work_members_v1500 where id = m.id;
  if p.end_at is null then
    update public.hq_work_pauses_v1199c116 set resumed_staff_ids = array_remove(resumed_staff_ids, m.staff_id) where id = p.id;
  else
    update public.hq_work_pauses_v1199c116 set resumed_staff_ids = array_remove(resumed_staff_ids, m.staff_id), end_at = null, resume_operation_id = null where id = p.id;
    reopened := true;
  end if;
  update public.hq_works_v1500 set pause_kind = case when w.pause_kind = '' then p.kind else w.pause_kind end,
    history = history || jsonb_build_array(jsonb_build_object('at', now(), 'by', v.display_name, 'actor_id', v.id, 'action', '再開の取り消し',
      'staff_id', m.staff_id, 'staff', m.staff_name, 'pause_id', p.id, 'pause_kind', p.kind, 'resumed_at', m.start_at, 'reopened', reopened)),
    updated_at = now()
   where id = w.id;
  return jsonb_build_object('ok', true, 'work_id', w.id, 'staff', m.staff_name, 'pause_kind', p.kind, 'reopened', reopened,
    'updated_at', (select updated_at from public.hq_works_v1500 where id = w.id));
end
$f$;
revoke all on function public.hq_work_resume_undo_v1199c169(uuid, uuid, timestamptz) from public, anon;
grant execute on function public.hq_work_resume_undo_v1199c169(uuid, uuid, timestamptz) to authenticated;

commit;
notify pgrst, 'reload schema';

-- ===== 確認（OK なら成功） =====
select case when to_regprocedure('public.hq_work_resume_undo_v1199c169(uuid,uuid,timestamptz)') is not null then 'OK' else 'NG' end as "再開の取り消し";
