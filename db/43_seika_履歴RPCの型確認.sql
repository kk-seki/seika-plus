-- ============================================================
-- SEIKA＋ 履歴保存RPCの型不一致（SQLSTATE 42883）の特定
--   エラー: operator does not exist: text = uuid
--   → id列の型と、seika_uuid_v188 の戻り値の型が食い違っている。
--   どちらがtextでどちらがuuidかを確定させる。読み取りのみ。
-- ============================================================

select 'id列の型' as 確認項目,
       c.table_name || '.' || c.column_name || ' : ' || c.data_type as 結果
from information_schema.columns c
where c.table_schema = 'public'
  and c.table_name in ('waste_records','inventory_records','inventory_movements')
  and c.column_name in ('id','record_id','user_id')

union all

select '関数の戻り値の型',
       p.proname || ' → ' || pg_catalog.format_type(p.prorettype, null)
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('seika_uuid_v188','current_app_role')

union all

select 'profilesの型',
       'profiles.' || c.column_name || ' : ' || c.data_type
from information_schema.columns c
where c.table_schema='public' and c.table_name='profiles'
  and c.column_name in ('id','legacy_user_id','role','display_name')

order by 1, 2;
