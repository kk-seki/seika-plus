-- ============================================================
-- SEIKA＋ 履歴保存RPCの不具合調査
--   アプリの履歴保存は REST 直書きではなく
--   RPC save_history_records_v188 を通っている。
--   端末からの REST 直書きは HTTP 201 で成功するため、
--   原因はこの関数の中にある。
-- ============================================================

-- 1. 関数の存在・所有者・SECURITY DEFINER の別・実行権限
select p.proname                                   as 関数名,
       pg_get_userbyid(p.proowner)                 as 所有者,
       case when p.prosecdef then 'DEFINER' else 'INVOKER' end as 実行区分,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') as ログイン済み実行可,
       has_function_privilege('anon',          p.oid, 'EXECUTE') as 未ログイン実行可
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('save_history_records_v188','save_clerk_waste_history_v188');

-- 2. 関数の中身（ここに原因があるはず）
select pg_get_functiondef(p.oid) as 定義
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'save_history_records_v188';
