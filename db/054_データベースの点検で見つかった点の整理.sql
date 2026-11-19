/*
054_データベースの点検で見つかった点の整理.sql（v1.199-c132）

目的（Supabase の点検（Advisors）で見つかった点の整理。アプリの動きとデータの中身は変わりません）：
  1. 入出庫の記録（qr_lot_movements）の、同じ索引の重複3組を1つずつ消す（保存が少し速くなる）。
  2. 更新日時を入れる関数 set_updated_at に search_path を固定する。
  3. トリガー用の関数を、ログインしていない人（anon）が呼べないようにする。
  4. アプリのコードから呼んでいない古い関数・内部用の関数（下の一覧）を、ログインした人が直接呼べないようにする。
     ほかの関数の中から呼ばれる分は、そのまま動きます（中で呼ぶときは関数の持ち主の権限で動くため）。
  5. 7月などに作った一時的なバックアップの表を、アプリから見えない archive スキーマへ移す（消さない）。

元に戻すとき：
  1. create index idx_qr_movements_excel_exported on public.qr_lot_movements(excel_exported); など（消した索引は下に記載）
  4. grant execute on function public.<名前>(<引数>) to authenticated;
  5. alter table archive.<表> set schema public;
何度実行しても同じ結果になります。
*/
begin;

-- 1. 重複している索引（同じ中身のもう一方は残す）
drop index if exists public.idx_qr_movements_excel_exported;   -- 残す：idx_qr_lot_movements_excel_exported
drop index if exists public.idx_qr_movements_occurred_at;      -- 残す：idx_qr_lot_movements_occurred_at
drop index if exists public.qr_lot_movements_operation_id_uidx; -- 残す：qr_lot_movements_operation_id_uq（同じ一意の索引）

-- 2. search_path の固定
alter function public.set_updated_at() set search_path to 'pg_catalog','public';

-- 3. トリガー用の関数は直接呼べないようにする（トリガーとしては今までどおり動く）
do $b$
declare r record;
begin
  for r in select p.oid::regprocedure fn from pg_proc p join pg_namespace n on n.oid=p.pronamespace
           where n.nspname='public' and p.prorettype='trigger'::regtype loop
    execute format('revoke execute on function %s from public, anon, authenticated', r.fn);
  end loop;
end $b$;

-- 4. アプリが直接呼んでいない関数（2026-11-19 時点の js/ を全文検索して、どこにも名前が出てこないもの）
do $b$
declare r record;
begin
  for r in select p.oid::regprocedure fn from pg_proc p join pg_namespace n on n.oid=p.pronamespace
           where n.nspname='public' and p.prokind='f' and p.proname in ('can_modify_app_state','cancel_trimming_job','cancel_trimming_job_legacy_v1144','create_manual_app_state_backup_v1167','finalize_monthly_quality_purge_v1102','hq_actor_v1400','hq_item_canon_v1600','hq_new_lot_no_v1400','hq_prep_confirm_v1199c116','hq_prep_confirm_v1500','hq_setting_on_v1500','hq_work_delete_v1500','hq_work_leave_v1500','hq_work_pallet_use_v1199c122','hq_work_resume_v1199c116','hq_work_start_v1199c116','list_monthly_quality_archives_v1102','prepare_monthly_quality_purge_v1102','replace_trimming_job_outputs','resolve_trimming_purchase_price_v1117','seika_item_name_group_v1200','seika_permission_diagnostics_v1145','seika_quality_can_operate_v1102','seika_quality_monthly_storage_delete_allowed_v1102','seika_require_role_v1240','trimming_lock_inventory_state','v177_delete_legacy_inventory_count_sessions') loop
    execute format('revoke execute on function %s from public, anon, authenticated', r.fn);
    execute format('grant execute on function %s to service_role', r.fn);
  end loop;
end $b$;

-- 5. 一時的なバックアップの表をアプリから見えない場所へ移す（消さない）
create schema if not exists archive;
revoke all on schema archive from public, anon, authenticated;
do $b$
declare t text;
begin
  foreach t in array array['app_state_backup_20260710','app_state_backup_20260721','qr_lots_backup_20260721','qr_lot_movements_backup_20260721',
                           'seika_policy_backup_v1203','seika_function_backup_v1240','seika_rpc_test_result','app_state_backup_migration_audit_v1167'] loop
    if to_regclass('public.'||t) is not null and to_regclass('archive.'||t) is null then
      execute format('alter table public.%I set schema archive', t);
    end if;
  end loop;
end $b$;

commit;

-- 確認：4行とも「OK」なら成功です
select '重複した索引' as 確認項目, case when to_regclass('public.idx_qr_movements_excel_exported') is null and to_regclass('public.idx_qr_movements_occurred_at') is null and to_regclass('public.qr_lot_movements_operation_id_uidx') is null and to_regclass('public.qr_lot_movements_operation_id_uq') is not null then 'OK' else '要確認' end as 判定
union all select 'search_path', case when exists(select 1 from pg_proc where oid='public.set_updated_at()'::regprocedure and proconfig is not null) then 'OK' else '要確認' end
union all select '直接呼べない関数', case when not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('can_modify_app_state','cancel_trimming_job','cancel_trimming_job_legacy_v1144','create_manual_app_state_backup_v1167','finalize_monthly_quality_purge_v1102','hq_actor_v1400','hq_item_canon_v1600','hq_new_lot_no_v1400','hq_prep_confirm_v1199c116','hq_prep_confirm_v1500','hq_setting_on_v1500','hq_work_delete_v1500','hq_work_leave_v1500','hq_work_pallet_use_v1199c122','hq_work_resume_v1199c116','hq_work_start_v1199c116','list_monthly_quality_archives_v1102','prepare_monthly_quality_purge_v1102','replace_trimming_job_outputs','resolve_trimming_purchase_price_v1117','seika_item_name_group_v1200','seika_permission_diagnostics_v1145','seika_quality_can_operate_v1102','seika_quality_monthly_storage_delete_allowed_v1102','seika_require_role_v1240','trimming_lock_inventory_state','v177_delete_legacy_inventory_count_sessions') and has_function_privilege('authenticated',p.oid,'EXECUTE')) then 'OK' else '要確認' end
union all select 'バックアップの表', case when to_regclass('public.app_state_backup_20260721') is null and to_regclass('archive.app_state_backup_20260721') is not null then 'OK' else '要確認' end;
