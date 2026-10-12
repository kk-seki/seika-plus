-- ============================================================
-- SEIKA＋ セキュリティ点検（参照のみ・変更なし）
--   会社に説明するうえで最重要の2点を確認します。
--   ① 公開キーで直接読み書きできるテーブルが無いか（RLS）
--   ② 誰でも呼べるRPCが、中で権限を確認しているか
-- ============================================================

select '① RLS未設定のテーブル（危険）' as 区分,
       c.relname || ' / ポリシー' || count(p.polname)::text || '件' as 内容
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
left join pg_policy p on p.polrelid = c.oid
where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity = false
group by c.relname

union all

select '② RLS有効だがポリシー0件',
       c.relname
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
left join pg_policy p on p.polrelid = c.oid
where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity = true
group by c.relname
having count(p.polname) = 0

union all

select '③ anonが実行でき権限確認が無いRPC',
       p.proname
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.prosecdef = true
  and has_function_privilege('anon', p.oid, 'execute')
  and p.prosrc !~* '(auth\.uid|auth\.jwt|current_setting|role|権限|AUTH_REQUIRED)'

union all

select '④ 参考：anonが実行できるRPCの総数',
       count(*)::text || '件'
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute')

order by 1, 2;
