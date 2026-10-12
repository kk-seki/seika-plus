-- ============================================================
-- SEIKA＋ 役割制限の切り戻し（38番を元に戻す）
--
--   使う場面：38番を実行したあと、
--     ・廃棄や在庫の登録が保存されなくなった
--     ・削除できなくなった
--     ・画面に記録が出なくなった
--   などが起きた場合に実行してください。
--
--   内容：役割による制限を外し、
--         「ログイン済みなら参照・登録・更新・削除が可能」
--         （35番を実行した直後の状態）に戻します。
--         未ログイン（anon）には引き続き与えません。
--
--   データは一切削除しません。ポリシーだけを戻します。
--   何度実行しても同じ結果になります。
-- ============================================================

do $$
declare
  t text;
  p record;
begin
  foreach t in array array['waste_records','inventory_records','inventory_movements']
  loop
    -- 現在のポリシーをすべて削除
    for p in
      select policyname from pg_policies
      where schemaname='public' and tablename=t
    loop
      execute format('drop policy if exists %I on public.%I', p.policyname, t);
    end loop;

    -- ログイン済みなら全操作可に戻す
    execute format(
      'create policy %I on public.%I for select to authenticated using (true)',
      t||'_authenticated_select', t);
    execute format(
      'create policy %I on public.%I for insert to authenticated with check (true)',
      t||'_authenticated_insert', t);
    execute format(
      'create policy %I on public.%I for update to authenticated using (true) with check (true)',
      t||'_authenticated_update', t);
    execute format(
      'create policy %I on public.%I for delete to authenticated using (true)',
      t||'_authenticated_delete', t);

    execute format(
      'grant select, insert, update, delete on public.%I to authenticated', t);
  end loop;
end $$;


-- 確認
select tablename as テーブル,
       count(*)::text || ' 件' as ポリシー数,
       string_agg(cmd, ' , ' order by cmd) as 種別
from pg_policies
where schemaname='public'
  and tablename in ('waste_records','inventory_records','inventory_movements')
group by tablename
order by tablename;
