-- ============================================================
-- SEIKA＋ 廃棄記録を削除できない問題の修正
--
--   症状：管理者で廃棄一覧の「削除」を押すと
--         「クラウド上の廃棄記録を削除できませんでした。権限を確認してください」
--
--   原因：public.waste_records は RLS（行レベルセキュリティ）が有効なのに
--         ポリシーが1件も無い。この状態では
--           ・SELECT は「0件」が返る（エラーにならない）
--           ・DELETE は「0行削除」で成功扱いになる（エラーにならない）
--         アプリは「1件も消えていない」ことを検知して上のメッセージを出している。
--
--   対処：ログイン済み（authenticated）に対して
--         テーブル権限とRLSポリシーを与える。
--         ※ 未ログイン（anon）には一切与えない。
--
--   このSQLは何度実行しても同じ結果になります（冪等）。
-- ============================================================


-- ============================================================
-- 【1】 実行前の状態を確認
-- ============================================================
select
  '実行前' as 時点,
  c.relname as テーブル,
  case when c.relrowsecurity then 'RLS有効' else 'RLS無効' end as RLS,
  count(p.polname)::text || '件' as ポリシー数,
  case when has_table_privilege('authenticated', c.oid, 'SELECT') then '○' else '×' end as 参照,
  case when has_table_privilege('authenticated', c.oid, 'INSERT') then '○' else '×' end as 追加,
  case when has_table_privilege('authenticated', c.oid, 'UPDATE') then '○' else '×' end as 更新,
  case when has_table_privilege('authenticated', c.oid, 'DELETE') then '○' else '×' end as 削除
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
left join pg_policy p on p.polrelid = c.oid
where n.nspname = 'public'
  and c.relname in ('waste_records', 'inventory_records', 'inventory_movements')
group by c.oid, c.relname, c.relrowsecurity
order by c.relname;


-- ============================================================
-- 【2】 修正：waste_records にテーブル権限とポリシーを付与
-- ============================================================

-- ① テーブル権限（ログイン済みのみ）
grant select, insert, update, delete on public.waste_records to authenticated;

-- ② RLS を有効化（すでに有効ならそのまま）
alter table public.waste_records enable row level security;

-- ③ ポリシーを作り直す
drop policy if exists waste_records_authenticated_select on public.waste_records;
drop policy if exists waste_records_authenticated_insert on public.waste_records;
drop policy if exists waste_records_authenticated_update on public.waste_records;
drop policy if exists waste_records_authenticated_delete on public.waste_records;

create policy waste_records_authenticated_select
  on public.waste_records for select to authenticated
  using (true);

create policy waste_records_authenticated_insert
  on public.waste_records for insert to authenticated
  with check (true);

create policy waste_records_authenticated_update
  on public.waste_records for update to authenticated
  using (true) with check (true);

create policy waste_records_authenticated_delete
  on public.waste_records for delete to authenticated
  using (true);


-- ============================================================
-- 【3】 実行後の確認
--      waste_records が「RLS有効 / ポリシー4件 / 参照○追加○更新○削除○」
--      になっていれば完了です。
-- ============================================================
select
  '実行後' as 時点,
  c.relname as テーブル,
  case when c.relrowsecurity then 'RLS有効' else 'RLS無効' end as RLS,
  count(p.polname)::text || '件' as ポリシー数,
  case when has_table_privilege('authenticated', c.oid, 'SELECT') then '○' else '×' end as 参照,
  case when has_table_privilege('authenticated', c.oid, 'INSERT') then '○' else '×' end as 追加,
  case when has_table_privilege('authenticated', c.oid, 'UPDATE') then '○' else '×' end as 更新,
  case when has_table_privilege('authenticated', c.oid, 'DELETE') then '○' else '×' end as 削除
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
left join pg_policy p on p.polrelid = c.oid
where n.nspname = 'public'
  and c.relname in ('waste_records', 'inventory_records', 'inventory_movements')
group by c.oid, c.relname, c.relrowsecurity
order by c.relname;


-- ============================================================
-- 【4】 未ログイン（anon）に権限が漏れていないことの確認
--      3件とも「×××× / ポリシー対象外」であること
-- ============================================================
select
  c.relname as テーブル,
  case when has_table_privilege('anon', c.oid, 'SELECT') then '○' else '×' end as anon参照,
  case when has_table_privilege('anon', c.oid, 'INSERT') then '○' else '×' end as anon追加,
  case when has_table_privilege('anon', c.oid, 'UPDATE') then '○' else '×' end as anon更新,
  case when has_table_privilege('anon', c.oid, 'DELETE') then '○' else '×' end as anon削除
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in ('waste_records', 'inventory_records', 'inventory_movements')
order by c.relname;
