-- 調査_通信量の原因.sql
-- 読み取り専用（データは一切変更しません）。何度実行しても大丈夫です。
-- 目的：アプリがどのデータを、何回、どれだけ受け取っているかを調べ、通信量（Egress）の原因を確かめます。
-- 結果は1つの表で出ます。「Download」→「CSV」で保存して渡してください。

select * from (
  select 1 as 並び, '① データの大きさ' as 区分, 'app_state（アプリ全体のデータ） id='||id as 名前,
         round(octet_length(data::text)/1048576.0,2)::text||' MB' as 値,
         'アプリを開く・最新を読み込むたびに丸ごと受け取っている' as 補足
  from public.app_state
  union all
  select 2, '① データの大きさ', 'inventory_records（在庫入力の履歴）',
         round(coalesce(sum(octet_length(data::text)),0)/1048576.0,2)::text||' MB',
         count(*)||' 行 ／ 1行平均 '||round(coalesce(avg(octet_length(data::text)),0)/1024.0,2)||' KB'
  from public.inventory_records
  union all
  select 3, '① データの大きさ', 'waste_records（廃棄の履歴）',
         round(coalesce(sum(octet_length(data::text)),0)/1048576.0,2)::text||' MB',
         count(*)||' 行 ／ 1行平均 '||round(coalesce(avg(octet_length(data::text)),0)/1024.0,2)||' KB'
  from public.waste_records
  union all
  select 4, '① データの大きさ', 'inventory_movements（在庫修正の履歴）',
         round(coalesce(sum(octet_length(data::text)),0)/1048576.0,2)::text||' MB',
         count(*)||' 行 ／ 1行平均 '||round(coalesce(avg(octet_length(data::text)),0)/1024.0,2)||' KB'
  from public.inventory_movements
  union all
  select 5, '① データの大きさ', 'qr_lots（QRロット）1行の平均',
         round(coalesce(avg(octet_length(q::text)),0)/1024.0,2)::text||' KB',
         count(*)||' 行'
  from public.qr_lots q
  union all
  select 9, '② 集計の開始日', '回数を数え始めた日時',
         coalesce(to_char((select stats_reset from extensions.pg_stat_statements_info) at time zone 'Asia/Tokyo','YYYY-MM-DD HH24:MI'),'-'),
         'この日時からの合計回数です'
  union all
  select 10+row_number() over (order by s.rows desc), '③ 受け取った行数が多い処理（上位25）',
         left(regexp_replace(s.query,'\s+',' ','g'),160),
         s.calls::text||' 回',
         '合計 '||s.rows||' 行 ／ 1回あたり '||round(s.rows::numeric/greatest(s.calls,1),1)||' 行'
  from (select query,sum(calls) calls,sum(rows) rows from extensions.pg_stat_statements
        where query ~* '(app_state|inventory_records|waste_records|inventory_movements|qr_|trimming|purchase_prices|items|profiles|seika_)'
          and query !~* '^\s*(insert|update|delete|create|alter|drop|grant|revoke|vacuum|analyze|set|show|begin|commit)'
        group by query order by sum(rows) desc limit 25) s
  union all
  select 100+row_number() over (order by s.calls desc), '④ 呼ばれた回数が多い処理（上位15）',
         left(regexp_replace(s.query,'\s+',' ','g'),160),
         s.calls::text||' 回',
         '合計 '||s.rows||' 行'
  from (select query,sum(calls) calls,sum(rows) rows from extensions.pg_stat_statements
        where query ~* '(app_state|inventory_records|waste_records|inventory_movements|qr_|trimming|purchase_prices|items|profiles|seika_)'
        group by query order by sum(calls) desc limit 15) s
) r
order by 並び;
