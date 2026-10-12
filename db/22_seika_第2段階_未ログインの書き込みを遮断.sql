-- ============================================================
-- SEIKA＋ 認証改修 第2段階：未ログインからの書き込みを遮断する
--
--   第1段階でアプリはログイン済みトークンで通信するようになった。
--   ここでは anon（未ログイン）から書き込み系RPCを呼べないようにする。
--   authenticated の権限は変更しないため、通常業務に影響はない。
--
--   関数本体は書き換えない。実行権限を外すだけなので、
--   問題があれば末尾のロールバックで即座に戻せる。
-- ============================================================

create table if not exists public.seika_auth_migration_log_v1200(
  id          bigserial primary key,
  phase       text not null,
  func_name   text not null,
  func_args   text not null,
  revoked_at  timestamptz not null default now()
);

do $$
declare r record; n integer := 0;
begin
  for r in
    select p.oid, p.proname, pg_get_function_identity_arguments(p.oid) as args, p.prosrc
    from pg_proc p
    join pg_namespace ns on ns.oid = p.pronamespace
    where ns.nspname = 'public'
  loop
    if has_function_privilege('anon', r.oid, 'execute')
       and r.prosrc ~* '(insert\s+into|update\s+public\.|update\s+[a-z_]+\s+set|delete\s+from|truncate|alter\s+table|drop\s+)' then
      execute format('revoke execute on function public.%I(%s) from anon', r.proname, r.args);
      insert into public.seika_auth_migration_log_v1200(phase, func_name, func_args)
      values ('phase2', r.proname, r.args);
      n := n + 1;
    end if;
  end loop;
  raise notice '書き込み系 %件 から anon の実行権限を外しました', n;
end $$;


-- ============================================================
-- 確認
-- ============================================================
with fn as (
  select p.oid, p.proname, p.prosrc
  from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
  where ns.nspname = 'public'
  offset 0
)
select '① 今回anonから外した関数' as 区分,
       func_name as 内容
from public.seika_auth_migration_log_v1200 where phase='phase2'

union all
select '② まだanonが呼べる関数（読み取り想定）', proname
from fn where has_function_privilege('anon', oid, 'execute')

union all
select '③ authenticatedが実行できる数（変わっていないこと）', count(*)::text || '件'
from fn where has_function_privilege('authenticated', oid, 'execute')

order by 1, 2;


-- ============================================================
-- 戻したい場合はこのブロックを実行する
-- ============================================================
/*
do $$
declare r record;
begin
  for r in select func_name, func_args from public.seika_auth_migration_log_v1200 where phase='phase2' loop
    execute format('grant execute on function public.%I(%s) to anon', r.func_name, r.func_args);
  end loop;
  delete from public.seika_auth_migration_log_v1200 where phase='phase2';
  raise notice '第2段階を元に戻しました';
end $$;
*/
