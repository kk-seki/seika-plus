/*
028_作業名と作業場所の削除.sql（v1.199-c70）
1. 作業名（下処理・清掃以外）と作業場所を「削除」できるようにします（本社社員・管理者）。
   これまでの作業の記録に書かれた名前は、そのまま残ります。
2. 最初から登録されていた作業場所「手切場」を削除します（初回だけ。あとで同じ名前を登録しても、このSQLの再実行では消しません）。
前提：000〜027を実行済みであること。何度実行しても同じ結果になります。在庫は変わりません。
*/
begin;

create or replace function public.hq_delete_place_v1700(p_name text)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles;
begin
  v := public.hq_actor_v1400(array['admin','hq_worker']);
  delete from public.hq_places_v1500 where name = btrim(coalesce(p_name,''));
  if not found then raise exception '作業場所が見つかりません。画面を開き直してください'; end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.hq_delete_task_v1700(p_name text)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles;
begin
  v := public.hq_actor_v1400(array['admin','hq_worker']);
  if btrim(coalesce(p_name,'')) in ('下処理','清掃') then raise exception '「下処理」「清掃」は削除できません'; end if;
  delete from public.hq_tasks_v1500 where name = btrim(coalesce(p_name,'')) and kind = '作業';
  if not found then raise exception '作業名が見つかりません。画面を開き直してください'; end if;
  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.hq_delete_place_v1700(text) from public, anon;
grant execute on function public.hq_delete_place_v1700(text) to authenticated, service_role;
revoke all on function public.hq_delete_task_v1700(text) from public, anon;
grant execute on function public.hq_delete_task_v1700(text) to authenticated, service_role;

do $$
begin
  if not exists (select 1 from public.hq_settings_v1500 where key = 'c70_tegiri_removed') then
    delete from public.hq_places_v1500 where name = '手切場';
    insert into public.hq_settings_v1500(key, value, updated_by_name) values ('c70_tegiri_removed', 'true'::jsonb, '028');
  end if;
end $$;

commit;

notify pgrst, 'reload schema';

/* 成功の確かめ方：下のSELECTの3行がすべて「OK」なら成功です。 */
select '作業場所の削除' as 項目, case when to_regprocedure('public.hq_delete_place_v1700(text)') is not null then 'OK' else 'NG' end as 結果
union all select '作業名の削除', case when to_regprocedure('public.hq_delete_task_v1700(text)') is not null then 'OK' else 'NG' end
union all select '手切場', case when not exists (select 1 from public.hq_places_v1500 where name = '手切場') then 'OK（削除済み）' when exists (select 1 from public.hq_settings_v1500 where key='c70_tegiri_removed') then 'OK（あとで登録し直したもの）' else 'NG' end;
