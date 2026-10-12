-- ============================================================
-- SEIKA＋ 履歴テーブルへの書き戻し（app_state から直接復旧）
--
--   前提：35番を実行済みで、3テーブルとも
--         「ログイン済み ○○○○ ／ 未ログイン ××××」になっていること。
--
--   目的：2026-08-03 以降、履歴テーブルに保存されていない記録を
--         app_state（アプリ本体の保存領域）から直接書き戻します。
--         アプリ側の再ログインを待たずにサーバー側だけで完結します。
--
--   安全性：
--     ・既存の行には一切触れません（on conflict do nothing）。
--     ・足りない行を追加するだけです。
--     ・列の型変換は jsonb_populate_record に任せているので、
--       日付や数値の書式で失敗しません。
--     ・何度実行しても結果は同じです（冪等）。
-- ============================================================


-- ============================================================
-- 【1】 廃棄記録
-- ============================================================
insert into public.waste_records
  (id, waste_date, item_name, qty, unit_price, amount,
   user_name, user_id, created_at, updated_at,
   excel_exported_at, excel_exported_by, data)
select p.id, p.waste_date, p.item_name, p.qty, p.unit_price, p.amount,
       p.user_name, p.user_id, p.created_at, p.updated_at,
       p.excel_exported_at, p.excel_exported_by, p.data
from (
  select jsonb_build_object(
    'id',                r->>'id',
    'waste_date',        nullif(r->>'date',''),
    'item_name',         nullif(r->>'itemName',''),
    'qty',               coalesce(nullif(r->>'qty','')::numeric, 0),
    'unit_price',        coalesce(nullif(r->>'unitPrice','')::numeric, 0),
    'amount',            coalesce(nullif(r->>'amount','')::numeric, 0),
    'user_name',         nullif(r->>'user',''),
    'user_id',           nullif(r->>'userId',''),
    'created_at',        coalesce(nullif(r->>'createdAt',''), nullif(r->>'date',''), now()::text),
    'updated_at',        coalesce(nullif(r->>'updatedAt',''), nullif(r->>'createdAt',''), nullif(r->>'date',''), now()::text),
    'excel_exported_at', nullif(r->>'excelExportedAt',''),
    'excel_exported_by', nullif(r->>'excelExportedBy',''),
    'data',              r
  ) as obj
  from public.app_state s
  cross join lateral jsonb_array_elements(
         case when jsonb_typeof(s.data->'wasteRecords') = 'array'
              then s.data->'wasteRecords' else '[]'::jsonb end) r
  where s.id in ('ishioka_inventory_production_v2',
                 'ishioka_inventory_demo_v6_linecopy_weekly')
    and coalesce(r->>'id','') <> ''
) t
cross join lateral jsonb_populate_record(null::public.waste_records, t.obj) p
on conflict (id) do nothing;


-- ============================================================
-- 【2】 在庫記録
-- ============================================================
insert into public.inventory_records
  (id, item_id, item_name, kind, total, status,
   user_name, user_role, created_at, updated_at,
   excel_exported_at, excel_exported_by, data)
select p.id, p.item_id, p.item_name, p.kind, p.total, p.status,
       p.user_name, p.user_role, p.created_at, p.updated_at,
       p.excel_exported_at, p.excel_exported_by, p.data
from (
  select jsonb_build_object(
    'id',                r->>'id',
    'item_id',           nullif(r->>'itemId',''),
    'item_name',         nullif(r->>'itemName',''),
    'kind',              nullif(r->>'kind',''),
    'total',             coalesce(nullif(r->>'total','')::numeric, 0),
    'status',            nullif(r->>'status',''),
    'user_name',         nullif(r->>'user',''),
    'user_role',         nullif(r->>'role',''),
    'created_at',        coalesce(nullif(r->>'createdAt',''), now()::text),
    'updated_at',        coalesce(nullif(r->>'updatedAt',''), nullif(r->>'createdAt',''), now()::text),
    'excel_exported_at', nullif(r->>'excelExportedAt',''),
    'excel_exported_by', nullif(r->>'excelExportedBy',''),
    'data',              r
  ) as obj
  from public.app_state s
  cross join lateral jsonb_array_elements(
         case when jsonb_typeof(s.data->'records') = 'array'
              then s.data->'records' else '[]'::jsonb end) r
  where s.id in ('ishioka_inventory_production_v2',
                 'ishioka_inventory_demo_v6_linecopy_weekly')
    and coalesce(r->>'id','') <> ''
) t
cross join lateral jsonb_populate_record(null::public.inventory_records, t.obj) p
on conflict (id) do nothing;


-- ============================================================
-- 【3】 入出庫の動き
-- ============================================================
insert into public.inventory_movements
  (id, record_id, item_id, item_name, movement_type,
   before_total, after_total, diff_kg,
   user_name, user_role, created_at, data)
select p.id, p.record_id, p.item_id, p.item_name, p.movement_type,
       p.before_total, p.after_total, p.diff_kg,
       p.user_name, p.user_role, p.created_at, p.data
from (
  select jsonb_build_object(
    'id',            r->>'id',
    'record_id',     nullif(r->>'recordId',''),
    'item_id',       nullif(r->>'itemId',''),
    'item_name',     nullif(r->>'itemName',''),
    'movement_type', nullif(r->>'type',''),
    'before_total',  coalesce(nullif(r->>'beforeTotal','')::numeric, 0),
    'after_total',   coalesce(nullif(r->>'afterTotal','')::numeric, 0),
    'diff_kg',       coalesce(nullif(r->>'diffKg','')::numeric, 0),
    'user_name',     nullif(r->>'user',''),
    'user_role',     nullif(r->>'role',''),
    'created_at',    coalesce(nullif(r->>'createdAt',''), now()::text),
    'data',          r
  ) as obj
  from public.app_state s
  cross join lateral jsonb_array_elements(
         case when jsonb_typeof(s.data->'movements') = 'array'
              then s.data->'movements' else '[]'::jsonb end) r
  where s.id in ('ishioka_inventory_production_v2',
                 'ishioka_inventory_demo_v6_linecopy_weekly')
    and coalesce(r->>'id','') <> ''
) t
cross join lateral jsonb_populate_record(null::public.inventory_movements, t.obj) p
on conflict (id) do nothing;


-- ============================================================
-- 【4】 結果の確認
--   最終日が今日に近づいていれば復旧完了です。
-- ============================================================
select 'waste_records' as テーブル,
       count(*)::text || ' 行' as 行数,
       coalesce(max(created_at)::date::text,'なし') as 最終日
from public.waste_records
union all
select 'inventory_records', count(*)::text || ' 行',
       coalesce(max(created_at)::date::text,'なし')
from public.inventory_records
union all
select 'inventory_movements', count(*)::text || ' 行',
       coalesce(max(created_at)::date::text,'なし')
from public.inventory_movements
order by テーブル;
