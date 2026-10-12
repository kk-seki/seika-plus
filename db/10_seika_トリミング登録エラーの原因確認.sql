-- ============================================================
-- SEIKA＋ トリミング日報 登録エラーの原因確認（参照のみ・変更なし）
--   エラー: {"code":"42703","message":"record \"v_lot\" has no field \"initial_quantity\""}
--   Supabase の SQL Editor に貼り付けて実行し、結果をそのまま返してください。
-- ============================================================

-- ① qr_lots の「数量」系の列名を確認する
select '① qr_lots の列' as section, column_name, data_type
from information_schema.columns
where table_schema = 'public'
  and table_name   = 'qr_lots'
  and (column_name ilike '%qty%' or column_name ilike '%quantit%' or column_name ilike '%weight%')
order by ordinal_position;

-- ② initial_quantity を参照している関数を洗い出す
select '② 該当する関数' as section,
       p.proname                                   as function_name,
       pg_get_function_identity_arguments(p.oid)   as arguments
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.prosrc ilike '%initial_quantity%'
order by p.proname;

-- ③ create_trimming_job の定義そのものを取得する
select '③ 関数定義' as section, pg_get_functiondef(p.oid) as definition
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'create_trimming_job';
