-- ============================================================
-- SEIKA＋ / app_state_backups 旧バックアップの整理
-- 目的: 旧世代バックアップ 516件・187MB を圧縮し、DB容量を解放する
--
-- 前提（2026-09-01 確認済み）
--   ・app_state_backups        : 516件 / 187MB / 生存行のみ（dead 0）
--   ・app_state_backup_blobs_v1167 : 6件 / 3.3MB（新・世代制。稼働中）
--   ・日時列は backed_up_at（created_at ではない）
--
-- 残す方針
--   ・最新 10 件（直近の復旧用）
--   ・各月の最終バックアップ 1 件（月次の復旧点）
--   ・上記以外を削除
--
-- 業務データ（qr_lots / qr_lot_movements / inventory_records /
-- qr_quality_evaluations / waste_records など）には一切触れません。
-- app_state 本体、新方式 blobs_v1167 にも触れません。
-- ============================================================


-- ============================================================
-- STEP 1: 読み取り専用の事前確認（必ず先に実行）
-- ============================================================

-- 1-1. 月ごとの件数と容量
select
  to_char(backed_up_at at time zone 'Asia/Tokyo', 'YYYY-MM') as month,
  count(*)                                                   as rows,
  pg_size_pretty(sum(pg_column_size(t))::bigint)             as approx_size,
  min(backed_up_at at time zone 'Asia/Tokyo')                as oldest_jst,
  max(backed_up_at at time zone 'Asia/Tokyo')                as newest_jst
from public.app_state_backups t
group by 1
order by 1;

-- 1-2. 残す件数 / 消す件数
with ranked as (
  select
    backup_id,
    row_number() over (order by backed_up_at desc, backup_id desc) as rn_new,
    row_number() over (
      partition by date_trunc('month', backed_up_at at time zone 'Asia/Tokyo')
      order by backed_up_at desc, backup_id desc
    ) as rn_month
  from public.app_state_backups
)
select
  count(*)                                                          as total_rows,
  count(*) filter (where rn_new <= 10 or rn_month = 1)              as keep_rows,
  count(*) filter (where not (rn_new <= 10 or rn_month = 1))         as delete_rows
from ranked;

-- 1-3. 残る行の一覧（内容確認用）
with ranked as (
  select
    backup_id, state_id, state_version, backed_up_at,
    row_number() over (order by backed_up_at desc, backup_id desc) as rn_new,
    row_number() over (
      partition by date_trunc('month', backed_up_at at time zone 'Asia/Tokyo')
      order by backed_up_at desc, backup_id desc
    ) as rn_month
  from public.app_state_backups
)
select backup_id, state_id, state_version,
       backed_up_at at time zone 'Asia/Tokyo' as backed_up_at_jst,
       case when rn_new <= 10 then '最新10件' else '月次' end as keep_reason
from ranked
where rn_new <= 10 or rn_month = 1
order by backed_up_at desc;


-- ============================================================
-- STEP 2: 削除（STEP 1 の結果を確認してから実行）
-- ============================================================

begin;

with ranked as (
  select
    backup_id,
    row_number() over (order by backed_up_at desc, backup_id desc) as rn_new,
    row_number() over (
      partition by date_trunc('month', backed_up_at at time zone 'Asia/Tokyo')
      order by backed_up_at desc, backup_id desc
    ) as rn_month
  from public.app_state_backups
),
keep as (
  select backup_id from ranked where rn_new <= 10 or rn_month = 1
)
delete from public.app_state_backups b
where not exists (select 1 from keep k where k.backup_id = b.backup_id);

-- 削除後の残り件数を確認
select count(*) as remaining_rows from public.app_state_backups;

commit;


-- ============================================================
-- STEP 3: 領域の解放
--   ※ 下の1行だけを単独で実行してください。
--     VACUUM はトランザクション内で実行できないため、
--     STEP 2 と同時に流すとエラーになります。
-- ============================================================

-- vacuum (full, analyze) public.app_state_backups;


-- ============================================================
-- STEP 4: 結果確認
-- ============================================================

-- select
--   pg_size_pretty(pg_total_relation_size('public.app_state_backups'))            as old_table,
--   pg_size_pretty(pg_total_relation_size('public.app_state_backup_blobs_v1167')) as new_table,
--   pg_size_pretty(pg_database_size(current_database()))                          as database_total;
