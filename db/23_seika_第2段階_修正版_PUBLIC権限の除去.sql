-- ============================================================
-- SEIKA＋ 認証改修 第2段階（修正版）
--
--   前回の 22_ では anon から revoke したが、実際には塞がっていなかった。
--   Postgres は関数作成時に自動で PUBLIC へ EXECUTE を与えるため、
--   anon は PUBLIC 経由で権限を継承したままだった。
--   （検証結果で ① と ② に同じ関数が並んでいたのはこのため）
--
--   ここでは PUBLIC から EXECUTE を外し、
--   authenticated と service_role にだけ明示的に与え直す。
--
--   ※ ログイン済みの利用者と、サーバー側処理の権限は維持されます。
--   ※ 問題があれば末尾のロールバックで戻せます。
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
    select p.oid, p.proname, pg_get_function_identity_arguments(p.oid) as args,
           p.prosrc, p.prorettype
    from pg_proc p
    join pg_namespace ns on ns.oid = p.pronamespace
    where ns.nspname = 'public'
  loop
    -- トリガー関数は外部から呼べないので対象外
    if r.prorettype = 'trigger'::regtype then
      continue;
    end if;

    if has_function_privilege('anon', r.oid, 'execute')
       and r.prosrc ~* '(insert\s+into|update\s+public\.|update\s+[a-z_]+\s+set|delete\s+from|truncate|alter\s+table|drop\s+)' then

      execute format('revoke execute on function public.%I(%s) from public',        r.proname, r.args);
      execute format('revoke execute on function public.%I(%s) from anon',          r.proname, r.args);
      execute format('grant  execute on function public.%I(%s) to authenticated',   r.proname, r.args);
      execute format('grant  execute on function public.%I(%s) to service_role',    r.proname, r.args);

      insert into public.seika_auth_migration_log_v1200(phase, func_name, func_args)
      values ('phase2b', r.proname, r.args);
      n := n + 1;
    end if;
  end loop;
  raise notice '書き込み系 %件 を未ログインから遮断しました', n;
end $$;


-- ============================================================
-- 確認
--   ② が0件になっていれば、未ログインからの書き込みは塞がれています
-- ============================================================
with fn as (
  select p.oid, p.proname, p.prosrc, p.prorettype
  from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
  where ns.nspname = 'public'
  offset 0
)
select '① 今回遮断した関数' as 区分, func_name as 内容
from public.seika_auth_migration_log_v1200 where phase='phase2b'

union all
select '② anonがまだ呼べる書き込み関数（0件であること）', proname
from fn
where prorettype <> 'trigger'::regtype
  and has_function_privilege('anon', oid, 'execute')
  and prosrc ~* '(insert\s+into|update\s+public\.|update\s+[a-z_]+\s+set|delete\s+from|truncate|alter\s+table|drop\s+)'

union all
select '③ authenticatedが実行できる数（110件のままであること）', count(*)::text || '件'
from fn where has_function_privilege('authenticated', oid, 'execute')

order by 1, 2;


-- ============================================================
-- 戻したい場合
-- ============================================================
/*
do $$
declare r record;
begin
  for r in select func_name, func_args from public.seika_auth_migration_log_v1200 where phase='phase2b' loop
    execute format('grant execute on function public.%I(%s) to public', r.func_name, r.func_args);
  end loop;
  delete from public.seika_auth_migration_log_v1200 where phase='phase2b';
  raise notice '第2段階を元に戻しました';
end $$;
*/
