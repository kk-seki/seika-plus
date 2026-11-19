/*
056_使われていない古い世代の関数を保管して削除.sql（v1.199-c135）

目的：
  新しい版に置き換わり、アプリ（js/）からも、ほかの関数・トリガー・行の決まり（RLS）からも呼ばれていない
  古い世代の関数15個を、定義を archive.function_backup_c135 に保管してから削除する。
  （2026-11-20 時点で本番の関数定義と js/ を全文検索して確認）

元に戻すとき：
  select definition from archive.function_backup_c135 where name = '関数名';
  → 出てきた定義をそのまま実行すると元に戻ります（権限は revoke/grant をやり直す）。
何度実行しても同じ結果になります。
*/
begin;

create schema if not exists archive;
revoke all on schema archive from public, anon, authenticated;
create table if not exists archive.function_backup_c135(
  name text not null,
  args text not null,
  definition text not null,
  saved_at timestamptz not null default now(),
  primary key (name, args)
);

do $b$
declare r record;
begin
  for r in
    select p.oid, p.proname, pg_get_function_identity_arguments(p.oid) args, pg_get_functiondef(p.oid) def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in (
      'hq_prep_confirm_v1500','hq_work_check_inputs_v1500','hq_work_delete_v1500','hq_work_leave_v1500',
      'hq_work_pallet_use_v1199c122','hq_work_resume_v1199c116','hq_work_start_v1199c116',
      'finalize_monthly_quality_purge_v1102','list_monthly_quality_archives_v1102','prepare_monthly_quality_purge_v1102',
      'seika_quality_monthly_storage_delete_allowed_v1102',
      'v123_create_inventory_count_session','v124_save_inventory_count_section','v177_delete_legacy_inventory_count_sessions',
      'replace_trimming_job_outputs')
  loop
    insert into archive.function_backup_c135(name, args, definition) values (r.proname, r.args, r.def)
      on conflict (name, args) do update set definition = excluded.definition, saved_at = now();
    execute format('drop function public.%I(%s)', r.proname, r.args);
  end loop;
end $b$;

commit;

-- 確認：「OK」なら成功です（15個とも保管され、public からなくなっている）
select '古い世代の関数' as 確認項目,
  case when (select count(*) from archive.function_backup_c135) >= 15
        and not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in (
          'hq_prep_confirm_v1500','hq_work_check_inputs_v1500','hq_work_delete_v1500','hq_work_leave_v1500','hq_work_pallet_use_v1199c122','hq_work_resume_v1199c116','hq_work_start_v1199c116',
          'finalize_monthly_quality_purge_v1102','list_monthly_quality_archives_v1102','prepare_monthly_quality_purge_v1102','seika_quality_monthly_storage_delete_allowed_v1102',
          'v123_create_inventory_count_session','v124_save_inventory_count_section','v177_delete_legacy_inventory_count_sessions','replace_trimming_job_outputs'))
  then 'OK' else '要確認' end as 判定;
