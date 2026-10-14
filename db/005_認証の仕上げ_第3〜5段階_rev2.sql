-- 005_認証の仕上げ_第3〜5段階.sql
-- 認証改修の残り（第3・第4・第5段階）をまとめて仕上げます。
--  第3段階：棚卸しの「確定した人」「取り消した人」も、ログインしている本人で記録する。
--  第4段階：ログインしていない状態で実行できる関数・表を無くす（今後追加する関数も同じ扱いにする）。
--  第5段階：権限チェックが無かった書き込み処理に、サーバー側の権限チェックを追加する。
--            QR入庫・QR取消・棚卸し取消・日報の作業日修正 … 管理者・青果社員のみ
--            日報の単価再計算 … 閲覧専用以外
--            日報の行削除（内部用の部品） … アプリから直接は呼べないようにする
-- ・アプリの差し替えは不要です。今のアプリの動きは変わりません。
-- ・SQLエディタでの手作業（ログインしていない操作）は今までどおり実行できます。
-- ・変更前の関数定義は seika_function_backup_v1240 に保存します。末尾に切り戻し手順があります。
-- ・何度実行しても同じ結果になります。
-- ・rev2：ログイン画面の名前一覧（006 の list_login_users_v1241）だけは、ログイン前に必要なので対象外にしています。

begin;

-- ===== 変更前の定義の控え
create table if not exists public.seika_function_backup_v1240(
  function_name text primary key,
  definition text not null,
  saved_at timestamptz not null default now()
);
alter table public.seika_function_backup_v1240 enable row level security;
revoke all on public.seika_function_backup_v1240 from public, anon, authenticated;

-- ===== 第5段階：共通の権限チェック
create or replace function public.seika_require_role_v1240(p_roles text[])
returns void
language plpgsql
stable
security definer
set search_path to 'pg_catalog','public'
as $f$
declare
  v_role text;
begin
  if auth.uid() is null then
    if coalesce(auth.role(), '') in ('anon','authenticated') then
      raise exception 'ログインが必要です' using errcode = '42501';
    end if;
    return;
  end if;
  select p.role into v_role from public.profiles p where p.id = auth.uid() and p.active limit 1;
  if v_role is null or not (v_role = any(p_roles)) then
    raise exception 'この操作を行う権限がありません' using errcode = '42501';
  end if;
end
$f$;
revoke all on function public.seika_require_role_v1240(text[]) from public, anon;
grant execute on function public.seika_require_role_v1240(text[]) to authenticated, service_role;

-- ===== 第5段階：権限チェックを各処理の先頭に追加（本番の現在の定義をもとに書き換え）
do $do$
declare
  r record;
  v_oid oid;
  v_def text;
  v_pos int;
  v_new text;
  v_cnt int;
begin
  for r in
    select * from (values
      ('cancel_qr_lot_operation',            array['admin','worker']),
      ('cancel_qr_inventory_session',        array['admin','worker']),
      ('create_qr_lot_v185',                 array['admin','worker']),
      ('update_trimming_job_work_date_v1197',array['admin','worker']),
      ('recalc_trimming_job_price_v1195',    array['admin','worker','buyer','sales','clerk'])
    ) t(fn, roles)
  loop
    select count(*), min(p.oid) into v_cnt, v_oid
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = r.fn;
    if v_cnt <> 1 then
      raise exception '関数 % が % 件あります。作業を中止しました', r.fn, v_cnt;
    end if;
    v_def := pg_get_functiondef(v_oid);
    if position('seika_require_role_v1240' in v_def) > 0 then
      continue;
    end if;
    insert into public.seika_function_backup_v1240(function_name, definition)
    values (r.fn, v_def) on conflict (function_name) do nothing;
    v_pos := position('$function$' in v_def);
    v_new := left(v_def, v_pos - 1)
          || regexp_replace(substr(v_def, v_pos), '\mbegin\M',
               'begin' || E'\n  perform public.seika_require_role_v1240(' || quote_literal(r.roles::text) || '::text[]);', 'i');
    execute v_new;
  end loop;
end
$do$;

-- 日報の行削除は「日報の修正・削除」処理の内部部品。アプリから直接は呼べないようにする
revoke execute on function public.seika_delete_trimming_job_rows_v1203(text) from public, anon, authenticated;
grant execute on function public.seika_delete_trimming_job_rows_v1203(text) to service_role;

-- ===== 第3段階：確定した人・取り消した人をログイン本人で記録
create or replace function public.seika_stamp_operator_change_v1240()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','public'
as $f$
declare
  v_id text;
begin
  if auth.uid() is null then
    return new;
  end if;
  select p.legacy_user_id into v_id from public.profiles p where p.id = auth.uid() and p.active limit 1;
  if v_id is null then
    return new;
  end if;
  if tg_table_name = 'qr_inventory_sessions' then
    if new.confirmed_by is not null and (tg_op = 'INSERT' or new.confirmed_by is distinct from old.confirmed_by) then
      new.confirmed_by := v_id;
    end if;
    if new.cancelled_by is not null and (tg_op = 'INSERT' or new.cancelled_by is distinct from old.cancelled_by) then
      new.cancelled_by := v_id;
    end if;
  elsif tg_table_name = 'qr_lot_movements' then
    if new.cancelled_by is not null and (tg_op = 'INSERT' or new.cancelled_by is distinct from old.cancelled_by) then
      new.cancelled_by := v_id;
    end if;
  end if;
  return new;
end
$f$;
revoke all on function public.seika_stamp_operator_change_v1240() from public, anon;

drop trigger if exists seika_stamp_operator_change_v1240 on public.qr_inventory_sessions;
create trigger seika_stamp_operator_change_v1240 before insert or update on public.qr_inventory_sessions
  for each row execute function public.seika_stamp_operator_change_v1240();
drop trigger if exists seika_stamp_operator_change_v1240 on public.qr_lot_movements;
create trigger seika_stamp_operator_change_v1240 before insert or update on public.qr_lot_movements
  for each row execute function public.seika_stamp_operator_change_v1240();

-- ===== 第4段階：ログインしていない状態で使えるものを無くす
do $do$
declare r record;
begin
  for r in
    select p.oid::regprocedure as f
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname <> 'list_login_users_v1241'
      and has_function_privilege('anon', p.oid, 'execute')
  loop
    execute format('revoke execute on function %s from public, anon', r.f);
    execute format('grant execute on function %s to authenticated, service_role', r.f);
  end loop;
  for r in
    select c.oid::regclass as t
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind in ('r','v','m','p')
      and (has_table_privilege('anon', c.oid, 'select') or has_table_privilege('anon', c.oid, 'insert')
        or has_table_privilege('anon', c.oid, 'update') or has_table_privilege('anon', c.oid, 'delete'))
  loop
    execute format('revoke all on table %s from anon', r.t);
  end loop;
end
$do$;

-- 今後新しく作る関数・表も、最初からログインしていない人には使えないようにする
alter default privileges in schema public revoke execute on functions from public;
alter default privileges in schema public revoke execute on functions from anon;
alter default privileges in schema public revoke all on tables from anon;

commit;

-- ===== 確認：4行とも「OK」なら成功です
select '未ログインで実行できる関数（ログイン画面の名前一覧を除く）' as 確認項目,
       count(*)::text || ' 件' as 結果,
       case when count(*) = 0 then 'OK' else '要確認' end as 判定
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname <> 'list_login_users_v1241'
  and has_function_privilege('anon', p.oid, 'execute')
union all
select '未ログインで読み書きできる表', count(*)::text || ' 件',
       case when count(*) = 0 then 'OK' else '要確認' end
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind in ('r','v','m','p')
  and (has_table_privilege('anon', c.oid, 'select') or has_table_privilege('anon', c.oid, 'insert')
    or has_table_privilege('anon', c.oid, 'update') or has_table_privilege('anon', c.oid, 'delete'))
union all
select '権限チェックを追加した処理', count(*)::text || ' / 5',
       case when count(*) = 5 then 'OK' else '要確認' end
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('cancel_qr_lot_operation','cancel_qr_inventory_session','create_qr_lot_v185',
                    'update_trimming_job_work_date_v1197','recalc_trimming_job_price_v1195')
  and pg_get_functiondef(p.oid) like '%seika_require_role_v1240%'
union all
select '確定・取消の本人記録', count(*)::text || ' / 2',
       case when count(*) = 2 then 'OK' else '要確認' end
from pg_trigger where tgname = 'seika_stamp_operator_change_v1240';

-- ===== 切り戻し（問題があったときだけ使います）
-- 下の「-- 」で始まる行の「-- 」をすべて消して実行すると、権限チェックの追加と本人記録を元に戻せます。
-- （第4段階の「未ログインで使えないようにする」は戻しません。戻す必要がある場合はご相談ください）
-- do $do$
-- declare r record;
-- begin
--   for r in select definition from public.seika_function_backup_v1240 loop
--     execute r.definition;
--   end loop;
-- end
-- $do$;
-- drop trigger if exists seika_stamp_operator_change_v1240 on public.qr_inventory_sessions;
-- drop trigger if exists seika_stamp_operator_change_v1240 on public.qr_lot_movements;
-- grant execute on function public.seika_delete_trimming_job_rows_v1203(text) to authenticated;
