-- 調査_アプリ全体データの内訳.sql
-- 読み取り専用（データは一切変更しません）。何度実行しても大丈夫です。
-- 目的：アプリを開くたびに受け取っている「アプリ全体のデータ（app_state）」の中で、何が大きいかを調べます。
-- 結果は1つの表で出ます。「Download」→「CSV」で保存して渡してください。

select k.key as 項目,
       round(octet_length(k.value::text)/1024.0,1) as 大きさ_KB,
       round(100.0*octet_length(k.value::text)/nullif(octet_length(s.data::text),0),1) as 全体に占める割合,
       jsonb_typeof(k.value) as 種類,
       case jsonb_typeof(k.value) when 'array' then jsonb_array_length(k.value)
                                  when 'object' then (select count(*) from jsonb_object_keys(k.value)) end as 件数,
       case when jsonb_typeof(k.value)='array' and jsonb_array_length(k.value)>0
            then (select coalesce(to_char(min(nullif(e->>'createdAt','')::timestamptz) at time zone 'Asia/Tokyo','YYYY-MM-DD'),'-')
                  from jsonb_array_elements(k.value) e where jsonb_typeof(e)='object' and (e->>'createdAt') ~ '^\d{4}-\d{2}-\d{2}')
       end as いちばん古い記録
from public.app_state s
cross join lateral jsonb_each(s.data::jsonb) k
where s.id='ishioka_inventory_production_v2'
order by octet_length(k.value::text) desc;
