-- 49 棚卸しの状態確認（読み取り専用・データは変更しません）
-- サーバー上の棚卸し一覧と、開始を妨げている棚卸しを表示します。
with s as (
  select e
    from public.app_state a,
         jsonb_array_elements(coalesce(a.data->'inventoryCounts'->'sessions','[]'::jsonb)) e
   where a.id = 'ishioka_inventory_production_v2'
)
select
  e->>'countNo'                         as 棚卸し番号,
  e->>'room'                            as 冷蔵庫,
  e->>'targetMonth'                     as 対象月,
  e->>'status'                          as 状態,
  case when coalesce(e->>'status','') not in ('completed','confirmed','test_confirmed','reversed','cancelled')
       then '★開始を妨げている' else '' end as 判定,
  coalesce(e->>'monthEndMode', e->>'inventoryCountMode', '旧仕様') as 仕様,
  e->>'v188ConfirmedAt'                 as 確定日時,
  e->>'normalStatus'                    as 通常工程,
  e->>'qrCountStatus'                   as QR工程,
  e->>'kataokaStatus'                   as 片岡工程,
  e->>'countSchemaVersion'              as 旧形式印,
  case when jsonb_typeof(e->'lines')='array' then jsonb_array_length(e->'lines') end        as 通常明細数,
  case when jsonb_typeof(e->'kataokaLines')='array' then jsonb_array_length(e->'kataokaLines') end as 片岡明細数,
  case when jsonb_typeof(e->'qrLines')='array' then jsonb_array_length(e->'qrLines') end    as QR明細数,
  e->>'startedAt'                       as 開始日時,
  e->>'updatedAt'                       as 最終更新
from s
order by e->>'room', coalesce(e->>'startedAt', e->>'updatedAt') desc;
