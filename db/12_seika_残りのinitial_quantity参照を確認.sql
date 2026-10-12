-- ============================================================
-- SEIKA＋ 旧列名 initial_quantity が残っている関数の該当箇所を抽出
--   対象: purge_monthly_archive_v1101 / v188_apply_month_end_qr_adjustment
--   参照のみ・変更なし
-- ============================================================

with f as (
  select p.oid, p.proname, pg_get_functiondef(p.oid) as def
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.prosrc ilike '%initial_quantity%'
),
l as (
  select f.proname,
         t.ord  as 行番号,
         t.line as 該当行
  from f,
       lateral unnest(string_to_array(f.def, E'\n')) with ordinality as t(line, ord)
  where t.line ilike '%initial_quantity%'
)
select proname as 関数名, 行番号, btrim(該当行) as 該当行
from l
order by 関数名, 行番号;

-- 変数の宣言方法（%rowtype か record か）も確認する
select p.proname as 関数名,
       btrim(t.line) as 宣言行
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace,
     lateral unnest(string_to_array(pg_get_functiondef(p.oid), E'\n')) as t(line)
where n.nspname = 'public'
  and p.prosrc ilike '%initial_quantity%'
  and (t.line ilike '%qr_lots%' or t.line ilike '%rowtype%' or t.line ilike '%record%')
order by p.proname;
