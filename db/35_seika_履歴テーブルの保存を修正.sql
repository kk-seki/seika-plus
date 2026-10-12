-- ============================================================
-- SEIKA＋ 履歴テーブルが保存されない問題の修正
--
--   症状：2026-08-03 以降、waste_records に1件も記録されていない。
--         inventory_records / inventory_movements も同じ構成のため
--         同様に保存できていない可能性が高い。
--
--   原因：3つの履歴テーブルは RLS が有効で、既存ポリシーが
--         current_app_role() による役割判定を条件にしている。
--         この関数が期待どおりの値を返していないため、
--         参照・追加・更新・削除がすべて拒否されていた。
--         アプリは app_state 側で動いていたため表面化しなかった。
--
--   対処：32番で waste_records に入れたものと同じ
--         「ログイン済み（authenticated）は許可」ポリシーを
--         inventory_records と inventory_movements にも入れる。
--         ※ 未ログイン（anon）には一切与えない。
--         ※ 既存のポリシーは消さずに残す（許可型はOR判定）。
--
--   実行後：管理者でログインして画面を開き直すと、
--           アプリが app_state のデータを履歴テーブルへ
--           自動で書き戻します（欠損分の穴埋め）。
--
--   このSQLは何度実行しても同じ結果になります（冪等）。
-- ============================================================


-- ============================================================
-- 【1】 inventory_records
-- ============================================================
grant select, insert, update, delete on public.inventory_records to authenticated;
alter table public.inventory_records enable row level security;

drop policy if exists inventory_records_authenticated_select on public.inventory_records;
drop policy if exists inventory_records_authenticated_insert on public.inventory_records;
drop policy if exists inventory_records_authenticated_update on public.inventory_records;
drop policy if exists inventory_records_authenticated_delete on public.inventory_records;

create policy inventory_records_authenticated_select
  on public.inventory_records for select to authenticated using (true);
create policy inventory_records_authenticated_insert
  on public.inventory_records for insert to authenticated with check (true);
create policy inventory_records_authenticated_update
  on public.inventory_records for update to authenticated using (true) with check (true);
create policy inventory_records_authenticated_delete
  on public.inventory_records for delete to authenticated using (true);


-- ============================================================
-- 【2】 inventory_movements
-- ============================================================
grant select, insert, update, delete on public.inventory_movements to authenticated;
alter table public.inventory_movements enable row level security;

drop policy if exists inventory_movements_authenticated_select on public.inventory_movements;
drop policy if exists inventory_movements_authenticated_insert on public.inventory_movements;
drop policy if exists inventory_movements_authenticated_update on public.inventory_movements;
drop policy if exists inventory_movements_authenticated_delete on public.inventory_movements;

create policy inventory_movements_authenticated_select
  on public.inventory_movements for select to authenticated using (true);
create policy inventory_movements_authenticated_insert
  on public.inventory_movements for insert to authenticated with check (true);
create policy inventory_movements_authenticated_update
  on public.inventory_movements for update to authenticated using (true) with check (true);
create policy inventory_movements_authenticated_delete
  on public.inventory_movements for delete to authenticated using (true);


-- ============================================================
-- 【3】 waste_records（32番で実施済み。未実行でも通るよう再掲）
-- ============================================================
grant select, insert, update, delete on public.waste_records to authenticated;
alter table public.waste_records enable row level security;

drop policy if exists waste_records_authenticated_select on public.waste_records;
drop policy if exists waste_records_authenticated_insert on public.waste_records;
drop policy if exists waste_records_authenticated_update on public.waste_records;
drop policy if exists waste_records_authenticated_delete on public.waste_records;

create policy waste_records_authenticated_select
  on public.waste_records for select to authenticated using (true);
create policy waste_records_authenticated_insert
  on public.waste_records for insert to authenticated with check (true);
create policy waste_records_authenticated_update
  on public.waste_records for update to authenticated using (true) with check (true);
create policy waste_records_authenticated_delete
  on public.waste_records for delete to authenticated using (true);


-- ============================================================
-- 【4】 確認（結果は1つの表にまとまって出ます）
--
--   A行：3テーブルとも「ログイン済み ○○○○ ／ 未ログイン ××××」
--        になっていれば設定は完了です。
--   B行：現在の行数。実行直後は8/3までのままです。
--        管理者でアプリを開き直すと増えます。
--   C行：原因だった current_app_role() の中身（参考）。
-- ============================================================
select * from (

  select 1 as 並び,
         'A. ' || c.relname as 区分,
         'ログイン済み:'
         || case when has_table_privilege('authenticated', c.oid, 'SELECT') then '○' else '×' end
         || case when has_table_privilege('authenticated', c.oid, 'INSERT') then '○' else '×' end
         || case when has_table_privilege('authenticated', c.oid, 'UPDATE') then '○' else '×' end
         || case when has_table_privilege('authenticated', c.oid, 'DELETE') then '○' else '×' end
         || ' ／ 未ログイン:'
         || case when has_table_privilege('anon', c.oid, 'SELECT') then '○' else '×' end
         || case when has_table_privilege('anon', c.oid, 'INSERT') then '○' else '×' end
         || case when has_table_privilege('anon', c.oid, 'UPDATE') then '○' else '×' end
         || case when has_table_privilege('anon', c.oid, 'DELETE') then '○' else '×' end
         || ' ／ ポリシー' || (select count(*) from pg_policies g
                               where g.schemaname='public' and g.tablename=c.relname)::text || '件'
         as 内容
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname='public'
    and c.relname in ('waste_records','inventory_records','inventory_movements')

  union all
  select 2, 'B. 行数 waste_records',       count(*)::text || ' 行' from public.waste_records
  union all
  select 2, 'B. 行数 inventory_records',   count(*)::text || ' 行' from public.inventory_records
  union all
  select 2, 'B. 行数 inventory_movements', count(*)::text || ' 行' from public.inventory_movements

  union all
  select 3, 'C. current_app_role() の定義',
         coalesce(
           (select pg_get_functiondef(p.oid)
            from pg_proc p
            join pg_namespace n2 on n2.oid = p.pronamespace
            where n2.nspname='public' and p.proname='current_app_role'
            limit 1),
           '（関数が存在しません）')

) x
order by 並び, 区分;
