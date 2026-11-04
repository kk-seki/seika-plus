-- 調査用（読み取りだけ）：仕入れ担当者ごとの担当品目と適正在庫の設定状況
-- データは一切変更しません。結果をCSVでダウンロードして送ってください。
with s as (
  select data from public.app_state where id = 'ishioka_inventory_production_v2'
), it as (
  select x->>'id' as item_id, x->>'name' as 品目, coalesce((x->>'sort')::numeric,0) as 並び,
         coalesce(x->>'active','true') as 使用中, coalesce(x->>'deleted','false') as 削除
  from s, jsonb_array_elements(coalesce(s.data->'items','[]'::jsonb)) x
), ba as (
  select b.key as 担当id, v #>> '{}' as item_id
  from s, jsonb_each(coalesce(s.data->'buyerAssignments','{}'::jsonb)) b,
       jsonb_array_elements(case when jsonb_typeof(b.value)='array' then b.value else '[]'::jsonb end) v
)
select it.品目, it.item_id, it.使用中, it.削除,
       coalesce((select string_agg(ba.担当id, '、' order by ba.担当id) from ba where ba.item_id = it.item_id), '（割り当てなし）') as 担当の割り当て,
       s.data->'settings'->it.item_id as 適正在庫,
       s.data->'optimalStockMeta'->it.item_id->>'updatedAt' as 見直し日時,
       (select count(*) from jsonb_object_keys(coalesce(s.data->'optimalStockMeta','{}'::jsonb))) as 見直し記録の件数
from it, s
order by it.並び, it.品目;
