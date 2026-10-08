-- 006_ログイン画面の名前一覧.sql
-- 目的：アプリでユーザーを追加・停止したとき、すべての端末のログイン画面に反映されるようにする。
--       これまでは名前の一覧を各端末が覚えているだけで、ユーザー管理を開いた端末でしか更新されなかった。
-- 内容：ログイン前でも、有効なユーザーの「ログインID・表示名・役割」だけを返す関数を作る。
--       パスワードやメールアドレスなど、それ以外の情報は返さない。
-- ・005 より先に実行しても後に実行しても大丈夫です。何度実行しても同じ結果になります。
begin;

create or replace function public.list_login_users_v1241()
returns table(legacy_user_id text, display_name text, role text)
language sql
stable
security definer
set search_path to 'pg_catalog','public'
as $f$
  select p.legacy_user_id, p.display_name, p.role
  from public.profiles p
  where p.active = true
  order by p.created_at, p.legacy_user_id
$f$;

revoke all on function public.list_login_users_v1241() from public;
grant execute on function public.list_login_users_v1241() to anon, authenticated, service_role;

commit;

-- 確認：有効なユーザーの一覧が出れば成功です（池田さんが含まれていることを確認してください）
select * from public.list_login_users_v1241();
