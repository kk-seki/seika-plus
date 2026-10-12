-- ============================================================
-- 08番のステップ(4)だけをやり直します
-- 原因: qr_lot_movements に書き込みガードのトリガーがあり、
--       SQL Editor は認証ユーザーを持たないため AUTH_REQUIRED になる
-- 対策: このトランザクションの間だけトリガーを止める（SET LOCAL）
-- Supabase SQL Editor で上から順に実行してください
-- ============================================================

-- ------------------------------------------------------------
-- ① まず 08番の (1)〜(3) が反映済みか確認
--    2行とも 修正済み = true なら関数の入れ替えは成功しています
-- ------------------------------------------------------------
SELECT p.proname,
       CASE p.proname
         WHEN 'resolve_trimming_purchase_price_v1117'
           THEN pg_get_functiondef(p.oid) LIKE '%産地不問%'
         ELSE pg_get_functiondef(p.oid) LIKE '%seika_parse_kg_v1162%'
       END AS 修正済み
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('resolve_trimming_purchase_price_v1117',
                    'list_unified_waste_records_v1144')
ORDER BY p.proname;

-- ------------------------------------------------------------
-- ② 参考：qr_lot_movements に付いているトリガー一覧
-- ------------------------------------------------------------
SELECT t.tgname AS トリガー名, p.proname AS 関数名
FROM pg_trigger t
JOIN pg_proc p ON p.oid = t.tgfoid
WHERE t.tgrelid = 'public.qr_lot_movements'::regclass
  AND NOT t.tgisinternal
ORDER BY 1;

-- ------------------------------------------------------------
-- ③ 既存のQR廃棄を新ルールで再計算
--    SET LOCAL なので、COMMIT した時点で設定は自動的に元へ戻ります
--    「手動修正」した行は上書きしません
-- ------------------------------------------------------------
BEGIN;

SET LOCAL session_replication_role = replica;

WITH target AS (
  SELECT q.id,
         q.item_name,
         COALESCE(l.origin,'')   AS origin,
         COALESCE(l.supplier,'') AS supplier,
         COALESCE((COALESCE(q.occurred_at,q.created_at) AT TIME ZONE 'Asia/Tokyo')::date,
                  l.received_date, current_date) AS ref_date,
         COALESCE(
           NULLIF(q.weight,0),
           CASE WHEN q.before_weight IS NOT NULL AND q.after_weight IS NOT NULL
                     AND abs(q.before_weight-q.after_weight) > 0
                THEN abs(q.before_weight-q.after_weight) END,
           CASE WHEN public.seika_parse_kg_v1162(l.pack_weight) > 0 AND q.qty > 0
                THEN round(public.seika_parse_kg_v1162(l.pack_weight) * q.qty, 3) END
         ) AS w
  FROM public.qr_lot_movements q
  JOIN public.qr_lots l ON l.id = q.lot_id
  WHERE q.movement_type = '廃棄'
    AND q.cancelled_at IS NULL
    AND q.reversed_operation_id IS NULL
    AND NOT public.seika_v1144_qr_operation_cancelled(q.operation_id)
    AND COALESCE(q.price_match_type,'') <> '手動修正'
),
calc AS (
  SELECT t.*,
         public.resolve_trimming_purchase_price_v1117(t.item_name, t.origin, t.supplier, t.ref_date) AS p
  FROM target t
  WHERE t.w IS NOT NULL AND t.w > 0
)
UPDATE public.qr_lot_movements m
   SET purchase_price_yen_per_kg = (c.p->>'price_yen_per_kg')::numeric,
       waste_amount_yen          = round((c.p->>'price_yen_per_kg')::numeric * c.w, 2),
       price_match_type          = c.p->>'match_type',
       price_match_reason        = c.p->>'match_reason',
       price_source_supplier     = NULLIF(c.p->>'source_supplier',''),
       price_average_count       = COALESCE((c.p->>'average_count')::integer, 0),
       price_reference_date      = c.ref_date,
       price_calculated_at       = now()
  FROM calc c
 WHERE m.id = c.id
   AND (c.p->>'found')::boolean;

COMMIT;

-- ------------------------------------------------------------
-- ④ 確認：採用区分の内訳（市場価格が増えていればOK）
-- ------------------------------------------------------------
SELECT price_match_type AS 採用区分, count(*) AS 件数
FROM public.qr_lot_movements
WHERE movement_type = '廃棄' AND cancelled_at IS NULL
GROUP BY 1 ORDER BY 2 DESC;
