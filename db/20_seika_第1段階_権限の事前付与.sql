-- ============================================================
-- SEIKA＋ 認証改修 第1段階：ログイン済みユーザーへの権限付与
--
--   これまで全ての通信が anon（未ログイン）権限で実行されていました。
--   v1.199 でユーザーのトークンを使うようになると、実行権限は
--   authenticated（ログイン済み）に変わります。
--   authenticated に権限が無いままアプリを差し替えると全機能が止まるため、
--   先にこのSQLで権限をそろえます。
--
--   ※ anon の権限は一切変更しません（剥がすのは第4段階です）。
--   ※ いま anon が持っている権限を超える権限は与えません。
--
--   （修正版）対象の絞り込みを確定させてから権限を判定します。
--             pg_class を直接条件に混ぜると、Postgres が評価順を入れ替え、
--             インデックスに対して権限判定を行って 42809 で失敗するため。
-- ============================================================

-- ① 関数の実行権限をそろえる
do $$
declare r record; n integer := 0;
begin
  for r in
    select p.oid, p.proname, pg_get_function_identity_arguments(p.oid) as args
    from pg_proc p
    join pg_namespace ns on ns.oid = p.pronamespace
    where ns.nspname = 'public'
  loop
    if has_function_privilege('anon', r.oid, 'execute')
       and not has_function_privilege('authenticated', r.oid, 'execute') then
      execute format('grant execute on function public.%I(%s) to authenticated', r.proname, r.args);
      n := n + 1;
    end if;
  end loop;
  raise notice '関数 %件 に実行権限を付与しました', n;
end $$;

-- ② テーブルの権限をそろえる
do $$
declare r record; v text; n integer := 0;
begin
  for r in
    select c.oid, c.relname
    from pg_class c
    join pg_namespace ns on ns.oid = c.relnamespace
    where ns.nspname = 'public' and c.relkind in ('r','p')
  loop
    foreach v in array array['SELECT','INSERT','UPDATE','DELETE'] loop
      if has_table_privilege('anon', r.oid, v)
         and not has_table_privilege('authenticated', r.oid, v) then
        execute format('grant %s on public.%I to authenticated', v, r.relname);
        n := n + 1;
      end if;
    end loop;
  end loop;
  raise notice 'テーブル権限 %件 を付与しました', n;
end $$;

-- ③ 連番（シーケンス）の権限をそろえる
do $$
declare r record; n integer := 0;
begin
  for r in
    select c.oid, c.relname
    from pg_class c
    join pg_namespace ns on ns.oid = c.relnamespace
    where ns.nspname = 'public' and c.relkind = 'S'
  loop
    if has_sequence_privilege('anon', r.oid, 'USAGE')
       and not has_sequence_privilege('authenticated', r.oid, 'USAGE') then
      execute format('grant usage, select on sequence public.%I to authenticated', r.relname);
      n := n + 1;
    end if;
  end loop;
  raise notice 'シーケンス %件 に権限を付与しました', n;
end $$;


-- ============================================================
-- 確認：「不足」が0件になっていれば、v1.199 を差し替えて安全です
-- ============================================================
with fn as (
  select p.oid, p.proname
  from pg_proc p
  join pg_namespace ns on ns.oid = p.pronamespace
  where ns.nspname = 'public'
  offset 0
),
tb as (
  select c.oid, c.relname
  from pg_class c
  join pg_namespace ns on ns.oid = c.relnamespace
  where ns.nspname = 'public' and c.relkind in ('r','p')
  offset 0
)
select '① 関数：anonが実行できる数' as 区分, count(*)::text || '件' as 内容
from fn where has_function_privilege('anon', oid, 'execute')

union all
select '② 関数：authenticatedが実行できる数', count(*)::text || '件'
from fn where has_function_privilege('authenticated', oid, 'execute')

union all
select '③ 関数の不足（0件であること）', proname
from fn
where has_function_privilege('anon', oid, 'execute')
  and not has_function_privilege('authenticated', oid, 'execute')

union all
select '④ テーブルの不足（0件であること）', relname || ' / ' || v.priv
from tb
cross join (values ('SELECT'),('INSERT'),('UPDATE'),('DELETE')) as v(priv)
where has_table_privilege('anon', tb.oid, v.priv)
  and not has_table_privilege('authenticated', tb.oid, v.priv)

order by 1, 2;
