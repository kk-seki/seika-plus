-- ============================================================
-- SEIKA＋ 品目別歩留まり表の「未計算（価格未登録）」原因調査
--   参照のみ・変更なし。結果は1つの表にまとめて表示されます。
-- ============================================================

select '① trimming_jobs の価格列' as 区分,
       column_name || ' : ' || data_type as 内容
from information_schema.columns
where table_schema='public' and table_name='trimming_jobs'
  and (column_name ilike '%price%' or column_name ilike '%cost%')

union all
select '② trimming_job_lots の価格列',
       column_name || ' : ' || data_type
from information_schema.columns
where table_schema='public' and table_name='trimming_job_lots'
  and (column_name ilike '%price%' or column_name ilike '%match%' or column_name ilike '%average%')

union all
select '③ qr_lots の日付列',
       column_name || ' : ' || data_type
from information_schema.columns
where table_schema='public' and table_name='qr_lots'
  and (column_name ilike '%date%' or column_name ilike '%received%' or column_name ilike '%arriv%')

union all
select '④ トリミング関連の関数',
       p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')'
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname ilike '%trimming%'

union all
select '⑤ 仕入価格の登録状況',
       coalesce(pp.item_name,'(なし)') || ' / ' || coalesce(pp.price_type,'-')
         || ' / 最新週 ' || coalesce(max(pp.week_start)::text,'-')
         || ' / ' || count(*)::text || '件'
from public.purchase_prices pp
group by pp.item_name, pp.price_type

order by 1,2;
