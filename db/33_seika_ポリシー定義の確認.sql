-- ============================================================
-- SEIKA＋ 廃棄記録の削除：既存ポリシーの中身を確認
--
--   32番を実行した結果、waste_records のポリシーが8件になりました。
--   32番が作るのは4件なので、元から4件あったことになります。
--   つまり「ポリシーが0件だった」という当初の見立ては誤りでした。
--
--   元からあった4件が何を許可／制限しているのかを確認します。
--   参照のみ・変更は一切しません。
-- ============================================================


-- ============================================================
-- 【A】 ポリシーの一覧と中身
--
--   見るポイント：
--     ・種別 が「制限(RESTRICTIVE)」の行があるか
--       → 制限型は AND で効くため、1件でも条件に合わないと削除できない
--     ・対象ロール に authenticated が含まれているか
--     ・コマンド が DELETE または ALL の行の 条件(USING)
-- ============================================================
select
  tablename                                   as テーブル,
  policyname                                  as ポリシー名,
  case when permissive = 'PERMISSIVE'
       then '許可(PERMISSIVE)'
       else '制限(RESTRICTIVE)' end            as 種別,
  array_to_string(roles, ', ')                as 対象ロール,
  cmd                                         as コマンド,
  coalesce(qual, '(なし)')                     as 条件_USING,
  coalesce(with_check, '(なし)')               as 条件_WITHCHECK
from pg_policies
where schemaname = 'public'
  and tablename in ('waste_records', 'inventory_records', 'inventory_movements')
order by tablename, cmd, policyname;


-- ============================================================
-- 【B】 削除に効くポリシーだけを抜き出す
--      （DELETE または ALL、かつ authenticated / public が対象）
-- ============================================================
select
  tablename                                   as テーブル,
  policyname                                  as ポリシー名,
  case when permissive = 'PERMISSIVE'
       then '許可'
       else '制限' end                         as 種別,
  array_to_string(roles, ', ')                as 対象ロール,
  cmd                                         as コマンド,
  coalesce(qual, '(なし)')                     as 条件_USING
from pg_policies
where schemaname = 'public'
  and tablename = 'waste_records'
  and cmd in ('DELETE', 'ALL')
order by permissive desc, policyname;


-- ============================================================
-- 【C】 テーブルにトリガーが仕掛かっていないかの確認
--      削除を止めるトリガーがある場合はここに出ます
-- ============================================================
select
  c.relname                                   as テーブル,
  t.tgname                                    as トリガー名,
  p.proname                                   as 実行される関数,
  case when t.tgenabled = 'D' then '無効' else '有効' end as 状態
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_namespace n on n.oid = c.relnamespace
join pg_proc p on p.oid = t.tgfoid
where n.nspname = 'public'
  and c.relname in ('waste_records', 'inventory_records', 'inventory_movements')
  and not t.tgisinternal
order by c.relname, t.tgname;
