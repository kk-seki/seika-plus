-- 調査_使用量と増え方.sql
-- 読み取り専用（データは一切変更しません）。何度実行しても大丈夫です。
-- 目的：本社でも使う場合に、無料の範囲（データベース 500MB・ファイル置き場 1GB）に収まるかを見積もるための数字を出します。
-- 結果は1つの表で出ます。「Download」→「CSV」で保存して渡してください。

with
t as (
  select c.oid, n.nspname as sch, c.relname as tbl,
         pg_total_relation_size(c.oid) as bytes,
         greatest(coalesce(s.n_live_tup,0),0) as live_est,
         coalesce(s.n_dead_tup,0) as dead_est
  from pg_class c
  join pg_namespace n on n.oid=c.relnamespace
  left join pg_stat_user_tables s on s.relid=c.oid
  where c.relkind in ('r','p') and n.nspname in ('public','storage','auth')
),
cr as (
  select t.*, exists(select 1 from information_schema.columns ic
                     where ic.table_schema=t.sch and ic.table_name=t.tbl and ic.column_name='created_at') as has_created
  from t where t.sch='public'
),
grow as (
  select cr.tbl, cr.bytes,
    (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from %I.%I', cr.sch, cr.tbl), false, true, '')))[1]::text::bigint as all_rows,
    (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from %I.%I where created_at >= now() - interval ''30 days''', cr.sch, cr.tbl), false, true, '')))[1]::text::bigint as rows_30d,
    (xpath('/row/c/text()', query_to_xml(format('select coalesce(to_char(min(created_at) at time zone ''Asia/Tokyo'',''YYYY-MM-DD''),''-'') as c from %I.%I', cr.sch, cr.tbl), false, true, '')))[1]::text as first_day
  from cr where cr.has_created
),
bk as (
  select coalesce(bucket_id,'(なし)') as bucket, count(*) as files,
         coalesce(sum(nullif(metadata->>'size','')::bigint),0) as bytes
  from storage.objects group by 1
)
select * from (
  select 1 as 並び, '① 全体' as 区分, 'データベース全体' as 名前,
         round(pg_database_size(current_database())/1048576.0,1)::text||' MB' as 値,
         '無料の上限 500MB' as 補足
  union all
  select 2, '① 全体', 'ファイル置き場（写真など）合計',
         round(coalesce((select sum(bytes) from bk),0)/1048576.0,1)::text||' MB',
         '無料の上限 1GB（1024MB）'
  union all
  select 3, '① 全体', 'ログインできる人の数',
         (select count(*) from auth.users)::text||' 人',
         '無料の上限 月5万人'
  union all
  select 10+row_number() over (order by bytes desc), '② 大きい表（上位15）', sch||'.'||tbl,
         round(bytes/1048576.0,2)::text||' MB',
         '行数(目安) '||live_est||' ／ 不要行(目安) '||dead_est
  from (select * from t order by bytes desc limit 15) x
  union all
  select 100+row_number() over (order by rows_30d desc, tbl), '③ 増え方（作成日がある表）', tbl,
         '直近30日 '||rows_30d||' 行',
         '全 '||all_rows||' 行 ／ '||round(bytes/1048576.0,2)||' MB ／ 1行あたり約 '||
         case when all_rows>0 then round(bytes::numeric/all_rows/1024,2)::text else '-' end||' KB ／ 最初の記録 '||first_day
  from grow
  union all
  select 300+row_number() over (order by bytes desc), '④ ファイル置き場（場所ごと）', bucket,
         round(bytes/1048576.0,2)::text||' MB',
         files||' ファイル ／ 1ファイル平均 '||case when files>0 then round(bytes::numeric/files/1024,1)::text else '-' end||' KB'
  from bk
) r
order by 並び;
