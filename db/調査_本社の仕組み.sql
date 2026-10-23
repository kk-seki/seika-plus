-- 調査用SQL（読むだけ・データは一切変わりません）
-- 目的：本社機能（hq_）のテーブル・関数・トリガーの定義を確認し、
--       便の選択（①）と実測重量の反映（②）のSQLを正しく作るため。
-- 使い方：Supabase の SQL Editor に全文を貼って Run →
--         結果の右上「Export」→「Download CSV」で保存し、チャットに添付してください。
select 'columns' as kind, table_name::text as name,
       string_agg(column_name||' '||data_type, ', ' order by ordinal_position) as detail
  from information_schema.columns
 where table_schema='public' and (table_name like 'hq%' or table_name in ('qr_lots','qr_lot_movements'))
 group by table_name
union all
select 'function', p.proname||'('||pg_get_function_identity_arguments(p.oid)||')',
       pg_get_functiondef(p.oid)
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.prokind in ('f','p')
   and (p.proname like 'hq%' or (case when p.prokind in ('f','p') then pg_get_functiondef(p.oid) end) like '%本社%')
union all
select 'trigger', c.relname||'.'||t.tgname, pg_get_triggerdef(t.oid)
  from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
 where n.nspname='public' and not t.tgisinternal and (c.relname like 'hq%' or c.relname like 'qr%')
union all
select 'view', viewname::text, definition
  from pg_views where schemaname='public' and viewname like 'hq%'
order by 1,2;
