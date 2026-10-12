-- 価格判定の本体（市場4社の判定条件はここにあります）
SELECT p.proname, pg_get_functiondef(p.oid) AS definition
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public'
  AND (p.proname LIKE '%purchase_price%' OR p.proname LIKE '%trimming_price%')
ORDER BY p.proname;
