-- 55_seika_本番DBの書き出し_一括.sql
-- 53番と54番を1本にまとめた、読み取り専用の書き出しです。データも定義も変更しません。
-- （この接続の間だけ使う一時的な関数 pg_temp.seika_dump を作り、接続を閉じると自動で消えます）
-- 途中で1つの項目が失敗しても全体は止まらず、その項目だけ section='ERROR' の行として出ます。
--
-- 使い方：SQLエディタで「New query」を開く（または中身を全部消す）→ このファイルの中身を全部貼る → Run
--        → 結果を Export → Download CSV で保存して送る

create or replace function pg_temp.seika_dump()
returns table(ord int, section text, name text, def text)
language plpgsql as $f$
declare
  r record;
  v_ns oid;
begin
  select oid into v_ns from pg_namespace where nspname='public';

  for r in
    select p.oid, p.proname||'('||pg_get_function_identity_arguments(p.oid)||')' as nm, p.proacl
    from pg_proc p
    where p.pronamespace=v_ns and p.prokind in ('f','p')
      and not exists(select 1 from pg_depend d where d.objid=p.oid and d.deptype='e')
  loop
    begin
      ord:=1; section:='function'; name:=r.nm; def:=pg_get_functiondef(r.oid)||';'; return next;
      ord:=2; section:='function_grant'; def:=coalesce(array_to_string(r.proacl::text[],', '),'(既定：PUBLICに実行権あり)'); return next;
    exception when others then
      ord:=0; section:='ERROR'; name:='function '||r.nm; def:=sqlstate||' '||sqlerrm; return next;
    end;
  end loop;

  for r in select c.oid, c.relname, c.relkind, c.relrowsecurity from pg_class c
           where c.relnamespace=v_ns and c.relkind in ('r','p') loop
    begin
      ord:=3; section:='table'; name:=r.relname;
      select 'create table if not exists public.'||quote_ident(r.relname)||E' (\n  '||
             string_agg(quote_ident(a.attname)||' '||format_type(a.atttypid,a.atttypmod)
               ||case when a.attnotnull then ' not null' else '' end
               ||coalesce(' default '||pg_get_expr(ad.adbin,ad.adrelid),''),
               E',\n  ' order by a.attnum)||E'\n);'
        into def
      from pg_attribute a left join pg_attrdef ad on ad.adrelid=a.attrelid and ad.adnum=a.attnum
      where a.attrelid=r.oid and a.attnum>0 and not a.attisdropped;
      return next;
      ord:=7; section:='rls';
      def:='alter table public.'||quote_ident(r.relname)||case when r.relrowsecurity then ' enable' else ' disable' end||' row level security;';
      return next;
    exception when others then
      ord:=0; section:='ERROR'; name:='table '||r.relname; def:=sqlstate||' '||sqlerrm; return next;
    end;
  end loop;

  begin
    for r in select table_name::text as t, string_agg(grantee||':'||privilege_type,', ' order by grantee,privilege_type) as g
             from information_schema.role_table_grants where table_schema='public' group by table_name loop
      ord:=4; section:='table_grant'; name:=r.t; def:=r.g; return next;
    end loop;
  exception when others then
    ord:=0; section:='ERROR'; name:='table_grant'; def:=sqlstate||' '||sqlerrm; return next;
  end;

  for r in select k.oid, k.conname, c.relname from pg_constraint k join pg_class c on c.oid=k.conrelid
           where c.relnamespace=v_ns and k.contype in ('p','u','c','f','x') loop
    begin
      ord:=5; section:='constraint'; name:=r.relname||'.'||r.conname;
      def:='alter table public.'||quote_ident(r.relname)||' add constraint '||quote_ident(r.conname)||' '||pg_get_constraintdef(r.oid)||';';
      return next;
    exception when others then
      ord:=0; section:='ERROR'; name:='constraint '||r.relname||'.'||r.conname; def:=sqlstate||' '||sqlerrm; return next;
    end;
  end loop;

  begin
    for r in select indexname::text as n, indexdef from pg_indexes where schemaname='public' loop
      ord:=6; section:='index'; name:=r.n; def:=r.indexdef||';'; return next;
    end loop;
  exception when others then
    ord:=0; section:='ERROR'; name:='index'; def:=sqlstate||' '||sqlerrm; return next;
  end;

  begin
    for r in select tablename::text as t, policyname::text as p, permissive, cmd, roles, qual, with_check
             from pg_policies where schemaname='public' loop
      ord:=8; section:='policy'; name:=r.t||'.'||r.p;
      def:=format('create policy %I on public.%I as %s for %s to %s%s%s;', r.p, r.t, r.permissive, r.cmd,
             array_to_string(r.roles,', '), coalesce(' using ('||r.qual||')',''), coalesce(' with check ('||r.with_check||')',''));
      return next;
    end loop;
  exception when others then
    ord:=0; section:='ERROR'; name:='policy'; def:=sqlstate||' '||sqlerrm; return next;
  end;

  for r in select t.oid, t.tgname, t.tgenabled, c.relname from pg_trigger t join pg_class c on c.oid=t.tgrelid
           where c.relnamespace=v_ns and not t.tgisinternal loop
    begin
      ord:=9; section:='trigger'; name:=r.relname||'.'||r.tgname;
      def:=pg_get_triggerdef(r.oid)||';'||case r.tgenabled when 'D' then E'\n-- 無効化中' else '' end;
      return next;
    exception when others then
      ord:=0; section:='ERROR'; name:='trigger '||r.relname||'.'||r.tgname; def:=sqlstate||' '||sqlerrm; return next;
    end;
  end loop;

  for r in select c.oid, c.relname from pg_class c where c.relnamespace=v_ns and c.relkind in ('v','m') loop
    begin
      ord:=10; section:='view'; name:=r.relname;
      def:='create or replace view public.'||quote_ident(r.relname)||E' as\n'||pg_get_viewdef(r.oid,true);
      return next;
    exception when others then
      ord:=0; section:='ERROR'; name:='view '||r.relname; def:=sqlstate||' '||sqlerrm; return next;
    end;
  end loop;

  begin
    for r in execute $q$
      select s.id::text as id, e.key as k, jsonb_typeof(e.value) as t,
             case jsonb_typeof(e.value) when 'array' then jsonb_array_length(e.value)
                  when 'object' then (select count(*) from jsonb_object_keys(e.value))::int end as n,
             pg_column_size(e.value) as b
      from public.app_state s cross join lateral jsonb_each(s.data::jsonb) e
      order by s.id, pg_column_size(e.value) desc $q$
    loop
      ord:=11; section:='app_state'; name:=r.id||'.'||r.k;
      def:=format('型=%s 件数=%s バイト=%s', r.t, coalesce(r.n::text,'-'), r.b); return next;
    end loop;
  exception when others then
    ord:=0; section:='ERROR'; name:='app_state'; def:=sqlstate||' '||sqlerrm; return next;
  end;

  for r in select c.oid, c.relname from pg_class c where c.relnamespace=v_ns and c.relkind in ('r','p') loop
    begin
      ord:=12; section:='row_count'; name:=r.relname;
      execute format('select count(*)::text from public.%I', r.relname) into def;
      def:=def||' 行 / '||pg_size_pretty(pg_total_relation_size(r.oid));
      return next;
    exception when others then
      ord:=0; section:='ERROR'; name:='row_count '||r.relname; def:=sqlstate||' '||sqlerrm; return next;
    end;
  end loop;
end
$f$;

select section, name, def from pg_temp.seika_dump() order by ord, name;
