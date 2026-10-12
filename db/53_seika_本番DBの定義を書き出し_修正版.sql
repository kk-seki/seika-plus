-- 53_seika_本番DBの定義を書き出し_修正版.sql
-- 読み取り専用です。データも定義も一切変更しません。
-- 前回の 'public'::regnamespace / ::regclass の型変換をやめ、pg_namespace・pg_class との結合に置き換えました。
-- 実行後、結果の「Export → Download CSV」で保存して送ってください。

with
ns as (select oid from pg_namespace where nspname='public'),
fnl as (
  select p.oid, p.proname||'('||pg_get_function_identity_arguments(p.oid)||')' as nm, p.proacl
  from pg_proc p
  where p.pronamespace=(select oid from ns) and p.prokind in ('f','p')
    and not exists(select 1 from pg_depend d where d.objid=p.oid and d.deptype='e')
),
rels as (
  select c.oid, c.relname, c.relkind, c.relrowsecurity
  from pg_class c where c.relnamespace=(select oid from ns)
),
fn as (select 1 as ord,'function'::text as section,nm::text as name,pg_get_functiondef(oid)||';' as def from fnl),
fg as (select 2,'function_grant',nm::text,coalesce(array_to_string(proacl::text[],', '),'(既定：PUBLICに実行権あり)') from fnl),
tb as (
  select 3,'table',r.relname::text,
         'create table if not exists public.'||quote_ident(r.relname)||E' (\n  '||
         string_agg(quote_ident(a.attname)||' '||format_type(a.atttypid,a.atttypmod)
           ||case when a.attnotnull then ' not null' else '' end
           ||coalesce(' default '||pg_get_expr(ad.adbin,ad.adrelid),''),
           E',\n  ' order by a.attnum)||E'\n);'
  from rels r
  join pg_attribute a on a.attrelid=r.oid and a.attnum>0 and not a.attisdropped
  left join pg_attrdef ad on ad.adrelid=r.oid and ad.adnum=a.attnum
  where r.relkind in ('r','p')
  group by r.relname
),
tg as (
  select 4,'table_grant',table_name::text,
         string_agg(grantee||':'||privilege_type,', ' order by grantee,privilege_type)
  from information_schema.role_table_grants
  where table_schema='public'
  group by table_name
),
co as (
  select 5,'constraint',r.relname||'.'||k.conname,
         'alter table public.'||quote_ident(r.relname)||' add constraint '||quote_ident(k.conname)||' '||pg_get_constraintdef(k.oid)||';'
  from pg_constraint k join rels r on r.oid=k.conrelid
  where k.contype in ('p','u','c','f','x')
),
ix as (select 6,'index',indexname::text,indexdef||';' from pg_indexes where schemaname='public'),
rl as (
  select 7,'rls',relname::text,
         'alter table public.'||quote_ident(relname)||case when relrowsecurity then ' enable' else ' disable' end||' row level security;'
  from rels where relkind in ('r','p')
),
po as (
  select 8,'policy',tablename||'.'||policyname,
         format('create policy %I on public.%I as %s for %s to %s%s%s;',
           policyname,tablename,permissive,cmd,array_to_string(roles,', '),
           coalesce(' using ('||qual||')',''),coalesce(' with check ('||with_check||')',''))
  from pg_policies where schemaname='public'
),
tr as (
  select 9,'trigger',r.relname||'.'||t.tgname,
         pg_get_triggerdef(t.oid)||';'||case t.tgenabled when 'D' then E'\n-- 無効化中' else '' end
  from pg_trigger t join rels r on r.oid=t.tgrelid
  where not t.tgisinternal
),
vw as (
  select 10,'view',viewname::text,'create or replace view public.'||quote_ident(viewname)||E' as\n'||definition
  from pg_views where schemaname='public'
),
allrows as (
  select * from fn union all select * from fg union all select * from tb union all
  select * from tg union all select * from co union all select * from ix union all
  select * from rl union all select * from po union all select * from tr union all select * from vw
)
select section,name,def from allrows order by ord,name;
