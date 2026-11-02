-- v1.199-c76 自動バックアップの保存期間
-- 自動バックアップ（アプリ全体のデータを丸ごと保存したもの）が消されずにたまり続け、容量の約半分を使っていたため、
-- 古いものを自動で消すようにします。
-- 残す期間：日ごと 14日分 / 週ごと 8週分 / 月ごと 12か月分。手動バックアップ（最大5件）は消しません。
-- 新しいバックアップが保存されるたびに、期間を過ぎたものと、どこからも使われなくなった本文を消します。
-- 何度実行しても同じ結果になります。このSQLの最後で、今たまっている古いものも1回消します。
begin;

create or replace function public.seika_prune_app_state_backups_v1199c76()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $f$
declare
  v_slots bigint;
  v_blobs bigint;
begin
  delete from public.app_state_backup_slots_v1167 x
   where (x.slot_kind = 'daily'   and x.captured_at < pg_catalog.now() - interval '14 days')
      or (x.slot_kind = 'weekly'  and x.captured_at < pg_catalog.now() - interval '56 days')
      or (x.slot_kind = 'monthly' and x.captured_at < pg_catalog.now() - interval '12 months');
  get diagnostics v_slots = row_count;
  delete from public.app_state_backup_blobs_v1167 b
   where not exists (select 1 from public.app_state_backup_slots_v1167 x where x.content_hash = b.content_hash);
  get diagnostics v_blobs = row_count;
  return pg_catalog.jsonb_build_object('deleted_slots', v_slots, 'deleted_blobs', v_blobs);
end
$f$;

revoke all on function public.seika_prune_app_state_backups_v1199c76() from public, anon, authenticated;
grant execute on function public.seika_prune_app_state_backups_v1199c76() to service_role;

create or replace function public.seika_prune_app_state_backups_trg_v1199c76()
returns trigger
language plpgsql
security definer
set search_path to ''
as $f$
begin
  perform public.seika_prune_app_state_backups_v1199c76();
  return null;
end
$f$;

revoke all on function public.seika_prune_app_state_backups_trg_v1199c76() from public, anon, authenticated;

drop trigger if exists seika_prune_app_state_backups_v1199c76 on public.app_state_backup_slots_v1167;
create trigger seika_prune_app_state_backups_v1199c76
  after insert on public.app_state_backup_slots_v1167
  for each statement execute function public.seika_prune_app_state_backups_trg_v1199c76();

select public.seika_prune_app_state_backups_v1199c76();

commit;

-- 確認：3行とも「OK」なら成功です
select '自動バックアップ：古いものを消す仕組み' as 確認項目,
       case when exists (select 1 from pg_trigger where tgname = 'seika_prune_app_state_backups_v1199c76' and not tgisinternal)
            then 'OK' else '要確認' end as 判定
union all
select '自動バックアップ：期間を過ぎたものが残っていない',
       case when not exists (select 1 from public.app_state_backup_slots_v1167
                              where (slot_kind = 'daily' and captured_at < now() - interval '14 days')
                                 or (slot_kind = 'weekly' and captured_at < now() - interval '56 days')
                                 or (slot_kind = 'monthly' and captured_at < now() - interval '12 months'))
            then 'OK' else '要確認' end
union all
select '自動バックアップ：残っている件数 ' || (select count(*) from public.app_state_backup_blobs_v1167)::text || '件',
       'OK';
