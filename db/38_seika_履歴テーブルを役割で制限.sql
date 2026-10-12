-- ============================================================
-- SEIKA＋ 履歴テーブルを「役割で制限」へ締め直す
--
--   前提：37番まで実行済みで、3テーブルの書き戻しが完了していること。
--         profiles は22人全員が auth.users と一致・active=true。
--         v1.199 以降アプリは本人のJWTを送るため
--         current_app_role() が正しく機能する状態。
--
--   方針：
--     ・参照（SELECT）は役割を見ません。ログイン済みなら全員可。
--       ここを役割依存にすると、判定が外れた瞬間に画面が
--       真っ白になるため、あえて緩くしています。
--     ・登録・更新・削除だけを役割で制限します。
--     ・役割はアプリ側の判定（canWasteInput / saveHistoryTablesNow）と
--       完全に一致させています。ここがずれると保存が黙って失敗します。
--     ・未ログイン（anon）には引き続き一切与えません。
--
--   安全策：
--     ・既存ポリシーは削除前に public.seika_policy_backup_v1203 へ
--       控えを取ります。元に戻すときはこの表を見れば復元できます。
--     ・問題が出た場合は 39番（切り戻し）を実行してください。
-- ============================================================


-- ============================================================
-- 【0】 既存ポリシーの控えを取る
-- ============================================================
create table if not exists public.seika_policy_backup_v1203(
  saved_at    timestamptz not null default now(),
  schemaname  text,
  tablename   text,
  policyname  text,
  permissive  text,
  roles       text,
  cmd         text,
  qual        text,
  with_check  text
);

insert into public.seika_policy_backup_v1203
  (schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check)
select schemaname, tablename, policyname, permissive,
       array_to_string(roles, ','), cmd, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename in ('waste_records','inventory_records','inventory_movements');


-- ============================================================
-- 【1】 3テーブルの既存ポリシーをすべて削除
--        （控えは【0】で取得済み）
-- ============================================================
do $$
declare
  p record;
begin
  for p in
    select tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename in ('waste_records','inventory_records','inventory_movements')
  loop
    execute format('drop policy if exists %I on public.%I', p.policyname, p.tablename);
  end loop;
end $$;


-- ============================================================
-- 【2-1】 waste_records
--         登録・更新：admin / worker / sales / clerk
--         削除      ：admin / worker / clerk
-- ============================================================
create policy waste_records_read
  on public.waste_records for select to authenticated
  using (true);

create policy waste_records_write
  on public.waste_records for insert to authenticated
  with check (public.current_app_role() = any (array['admin','worker','sales','clerk']));

create policy waste_records_modify
  on public.waste_records for update to authenticated
  using      (public.current_app_role() = any (array['admin','worker','sales','clerk']))
  with check (public.current_app_role() = any (array['admin','worker','sales','clerk']));

create policy waste_records_remove
  on public.waste_records for delete to authenticated
  using (public.current_app_role() = any (array['admin','worker','clerk']));


-- ============================================================
-- 【2-2】 inventory_records
--         登録・更新・削除：admin / worker
-- ============================================================
create policy inventory_records_read
  on public.inventory_records for select to authenticated
  using (true);

create policy inventory_records_write
  on public.inventory_records for insert to authenticated
  with check (public.current_app_role() = any (array['admin','worker']));

create policy inventory_records_modify
  on public.inventory_records for update to authenticated
  using      (public.current_app_role() = any (array['admin','worker']))
  with check (public.current_app_role() = any (array['admin','worker']));

create policy inventory_records_remove
  on public.inventory_records for delete to authenticated
  using (public.current_app_role() = any (array['admin','worker']));


-- ============================================================
-- 【2-3】 inventory_movements
--         登録・更新・削除：admin / worker
-- ============================================================
create policy inventory_movements_read
  on public.inventory_movements for select to authenticated
  using (true);

create policy inventory_movements_write
  on public.inventory_movements for insert to authenticated
  with check (public.current_app_role() = any (array['admin','worker']));

create policy inventory_movements_modify
  on public.inventory_movements for update to authenticated
  using      (public.current_app_role() = any (array['admin','worker']))
  with check (public.current_app_role() = any (array['admin','worker']));

create policy inventory_movements_remove
  on public.inventory_movements for delete to authenticated
  using (public.current_app_role() = any (array['admin','worker']));


-- ============================================================
-- 【3】 確認
--   ・各テーブル4件ずつ（参照／登録／更新／削除）になっていればOK
--   ・未ログインは ×××× のまま
-- ============================================================
select * from (

  select 1 as 並び, 'A. ' || c.relname as 区分,
         'ポリシー'
         || (select count(*) from pg_policies g
             where g.schemaname='public' and g.tablename=c.relname)::text || '件'
         || ' ／ 未ログイン:'
         || case when has_table_privilege('anon', c.oid, 'SELECT') then '○' else '×' end
         || case when has_table_privilege('anon', c.oid, 'INSERT') then '○' else '×' end
         || case when has_table_privilege('anon', c.oid, 'UPDATE') then '○' else '×' end
         || case when has_table_privilege('anon', c.oid, 'DELETE') then '○' else '×' end
         as 内容
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname='public'
    and c.relname in ('waste_records','inventory_records','inventory_movements')

  union all
  select 2, 'B. ' || tablename || ' / ' || cmd,
         policyname || ' ／ 条件:' || coalesce(qual, with_check, 'true')
  from pg_policies
  where schemaname='public'
    and tablename in ('waste_records','inventory_records','inventory_movements')

  union all
  select 3, 'C. 控えた旧ポリシー',
         count(*)::text || ' 件を public.seika_policy_backup_v1203 に保存'
  from public.seika_policy_backup_v1203

) x
order by 並び, 区分, 内容;
