-- ============================================================
-- SEIKA＋ 市場価格が廃棄単価に反映されない原因調査
-- Supabase SQL Editor で上から順に実行してください
-- ============================================================

-- ① 価格解決RPCの中身（市場4社の判定条件を確認する）
SELECT p.proname, pg_get_functiondef(p.oid) AS definition
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
    'resolve_waste_purchase_price_v1118',
    'calculate_waste_price_v1118',
    'recalculate_qr_waste_price_v1162'
  );

-- ② 廃棄側に実際に入っている「仕入先」の表記一覧
--    「大同 / 中央 / 東一 / シティ」と一字一句同じか、
--    前後の空白・全角スペース・別名（水戸大同 / 東京シティ青果 など）が無いかを見る
SELECT DISTINCT
  supplier                              AS 仕入先そのまま,
  '['|| supplier ||']'                  AS 前後空白チェック,
  length(supplier)                      AS 文字数,
  count(*) OVER (PARTITION BY supplier) AS 件数
FROM public.qr_lots
WHERE supplier IS NOT NULL AND supplier <> ''
ORDER BY 1;

-- ③ 登録済みの市場価格（仕入先は必ず「市場」・産地は空欄が正）
SELECT week_start, item_name, origin, supplier, price_yen_per_kg, price_type
FROM public.purchase_prices
WHERE COALESCE(price_type,'') = 'market'
   OR replace(replace(COALESCE(supplier,''),' ',''),'　','') = '市場'
ORDER BY week_start DESC, item_name
LIMIT 100;

-- ④ 品目名の表記ゆれチェック（廃棄側 vs 価格表側）
--    ここに出た品目は「価格表に無い品目」＝③同一品目平均に落ちる
SELECT DISTINCT l.item_name AS 廃棄側の品目
FROM public.qr_lots l
WHERE NOT EXISTS (
  SELECT 1 FROM public.purchase_prices p
  WHERE replace(replace(p.item_name,' ',''),'　','')
      = replace(replace(l.item_name,' ',''),'　','')
)
ORDER BY 1;
