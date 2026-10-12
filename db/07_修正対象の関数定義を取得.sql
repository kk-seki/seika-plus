-- 修正に必要な2つの関数の定義を取得します
-- Supabase SQL Editor に貼り付けて実行し、結果をそのまま送ってください

SELECT p.proname, pg_get_functiondef(p.oid) AS definition
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
    'resolve_trimming_purchase_price_v1117',   -- 市場4社・産地の判定条件（要件1〜3）
    'list_unified_waste_records_v1144'         -- 廃棄一覧の重量返却（要件4〜5）
  )
ORDER BY p.proname;
