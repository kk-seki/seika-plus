-- SEIKA＋ パスワード変更を毎回求められる問題の修正
-- 症状: フレンキでログインするたびに「パスワード変更が必要です」が出る。
-- 原因: パスワード変更後もプロフィール側の must_change_password が true のまま残る。
--       アプリは画面上だけ false にしていたため、次回ログインで再び true を読み込む。
-- 対処: 本人が自分のフラグだけを解除できる RPC を作り、変更完了時に呼ぶ。
--
-- 対象テーブルは環境ごとに名前が違う可能性があるため、自動検出して作成する。
-- 実行後に最後の確認クエリの結果を確認すること。

-- 1) 対象テーブルの確認（参考表示）
select table_schema, table_name, column_name
  from information_schema.columns
 where column_name = 'must_change_password'
   and table_schema not in ('pg_catalog', 'information_schema')
 order by table_schema, table_name;

-- 2) RPC の作成
do $do$
declare
  v_schema text;
  v_table  text;
  v_uidcol text;
  v_haschanged boolean;
  v_sql    text;
begin
  select c.table_schema, c.table_name
    into v_schema, v_table
    from information_schema.columns c
   where c.column_name = 'must_change_password'
     and c.table_schema not in ('pg_catalog', 'information_schema')
   order by (c.table_schema = 'public') desc, c.table_name
   limit 1;

  if v_table is null then
    raise exception 'must_change_password 列を持つテーブルが見つかりません。';
  end if;

  -- auth.uid() と突き合わせる uuid 列を探す
  select c.column_name
    into v_uidcol
    from information_schema.columns c
   where c.table_schema = v_schema
     and c.table_name = v_table
     and c.data_type = 'uuid'
     and c.column_name in ('auth_user_id', 'user_id', 'uid', 'auth_uid', 'id')
   order by array_position(
              array['auth_user_id', 'user_id', 'uid', 'auth_uid', 'id'],
              c.column_name)
   limit 1;

  if v_uidcol is null then
    raise exception 'テーブル %.% に auth.uid() と対応する uuid 列が見つかりません。', v_schema, v_table;
  end if;

  select exists (
           select 1
             from information_schema.columns c
            where c.table_schema = v_schema
              and c.table_name = v_table
              and c.column_name = 'password_changed_at')
    into v_haschanged;

  raise notice '対象: %.% / 判定列: % / password_changed_at: %',
    v_schema, v_table, v_uidcol, v_haschanged;

  v_sql := format($f$
    create or replace function public.seika_mark_password_changed_v1202()
    returns jsonb
    language plpgsql
    security definer
    set search_path = public, pg_temp
    as $body$
    declare
      v_rows integer;
    begin
      if auth.uid() is null then
        return jsonb_build_object('ok', false, 'message', 'AUTH_REQUIRED');
      end if;

      update %I.%I
         set must_change_password = false%s
       where %I = auth.uid();

      get diagnostics v_rows = row_count;
      return jsonb_build_object('ok', v_rows > 0, 'updated', v_rows);
    end;
    $body$;
  $f$,
    v_schema, v_table,
    case when v_haschanged then ', password_changed_at = now()' else '' end,
    v_uidcol);

  execute v_sql;

  -- 3) 既にパスワードを変更済みの利用者のフラグを解除する
  if exists (select 1
               from information_schema.columns c
              where c.table_schema = v_schema
                and c.table_name = v_table
                and c.column_name = 'legacy_user_id') then
    execute format(
      'update %I.%I set must_change_password = false where legacy_user_id = %L',
      v_schema, v_table, 'furenki');
    raise notice 'furenki のフラグを解除しました。';
    for v_sql in execute format(
        'select legacy_user_id || '' : '' || coalesce(must_change_password::text, ''-'') from %I.%I order by 1',
        v_schema, v_table) loop
      raise notice '要変更フラグ % ', v_sql;
    end loop;
  else
    raise notice 'legacy_user_id 列がないため、個別解除はスキップしました。';
  end if;
end
$do$;

revoke execute on function public.seika_mark_password_changed_v1202() from public, anon;
grant  execute on function public.seika_mark_password_changed_v1202() to authenticated, service_role;

-- 4) 確認: 実行権限
select p.proname,
       has_function_privilege('anon',          'public.seika_mark_password_changed_v1202()', 'execute') as anon_can_run,
       has_function_privilege('authenticated', 'public.seika_mark_password_changed_v1202()', 'execute') as auth_can_run
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname = 'seika_mark_password_changed_v1202';

-- 5) 確認: 変更が必要なままの利用者が残っていないか
--    1) で表示されたテーブル名に置き換えて実行する。
--    （ヒェップは初回ログインで変更してもらうため true のままで正常）
-- select legacy_user_id, must_change_password from <1)で表示されたテーブル> order by 1;
