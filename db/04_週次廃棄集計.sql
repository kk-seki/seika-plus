-- ============================================================
-- SEIKA＋ 週次廃棄集計（Supabase SQL Editor で実行）
--
-- 使い方
--   1. 下の「期首」と「対象週の最終日」だけを書き換える
--   2. 実行 → 右下の「Download CSV」でCSVを保存
--   3. そのCSVを渡せば、週次資料のPDFを作成できる
--
-- 通常廃棄とQR廃棄の両方を、アプリと同じ集計ロジックで取得する
-- （アプリの廃棄一覧が使っている関数をそのまま呼び出している）
-- ============================================================

with p as (
  select
    date '2026-09-01' as d_from,   -- 期首（今期の開始日）
    date '2026-09-07' as d_to      -- 対象週の最終日
),
src as (
  select jsonb_array_elements(
           to_jsonb(list_unified_waste_records_v1144(p.d_from::text, p.d_to::text)) -> 'rows'
         ) as r
  from p
)
select
  (r ->> 'date')::date                              as 日付,
  r ->> 'item_name'                                 as 品名,
  coalesce((r ->> 'qty')::numeric, 0)               as 数量kg,
  coalesce((r ->> 'purchase_price_yen_per_kg')::numeric, 0) as 単価円kg,
  coalesce((r ->> 'waste_amount_yen')::numeric, 0)  as 金額円,
  r ->> 'source'                                    as 区分,
  r ->> 'supplier'                                  as 仕入先,
  r ->> 'origin'                                    as 産地,
  r ->> 'memo'                                      as 備考,
  r ->> 'user_name'                                 as 入力者
from src
order by 1, 2;
