-- ============================================================
-- SEIKA＋ 履歴保存RPCが失敗する理由の特定
--
--   関数定義は取得できたが、どの行で落ちているかは定義からは
--   断定できない。管理者になりきって実際に呼び出し、
--   発生する例外コードとメッセージをそのまま取得する。
--
--   ・既存の廃棄記録1件をそのまま渡すため、新規行は増えない
--     （on conflict で同じ内容に更新されるだけ）
--   ・読み取りと1件の上書きのみ。削除は一切行わない
-- ============================================================

drop table if exists public.seika_rpc_test_result;
create table public.seika_rpc_test_result(
  項目 text,
  結果 text
);

do $$
declare
  v_uid   uuid;
  v_name  text;
  v_row   jsonb;
  v_res   jsonb;
begin
  -- 実験に使う管理者
  select p.id, p.display_name
    into v_uid, v_name
  from public.profiles p
  where p.role = 'admin' and p.active = true
  order by p.display_name
  limit 1;

  insert into public.seika_rpc_test_result
  values ('1. 実験に使う管理者', coalesce(v_name,'(見つからない)')||' / '||coalesce(v_uid::text,'-'));

  -- アプリが送るのと同じ形の廃棄1件
  select w.data into v_row
  from public.waste_records w
  where w.data is not null
  order by w.updated_at desc nulls last
  limit 1;

  insert into public.seika_rpc_test_result
  values ('2. 送信する廃棄記録のid', coalesce(v_row->>'id','(データなし)'));

  -- ログイン済み利用者になりきる
  perform set_config('request.jwt.claims',
                     json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);

  insert into public.seika_rpc_test_result
  values ('3. なりきり後の current_app_role()', coalesce(public.current_app_role(),'(null)'));

  -- 本番と同じ呼び出し（廃棄1件のみ）
  begin
    v_res := public.save_history_records_v188(
               p_records         => '[]'::jsonb,
               p_waste_records   => jsonb_build_array(v_row),
               p_movements       => '[]'::jsonb,
               p_delete_record_ids   => '{}'::text[],
               p_delete_waste_ids    => '{}'::text[],
               p_delete_movement_ids => '{}'::text[]);
    insert into public.seika_rpc_test_result values ('4. RPCの結果', '成功 / '||coalesce(v_res::text,'(null)'));
    insert into public.seika_rpc_test_result values ('5. エラー', 'なし');
  exception when others then
    insert into public.seika_rpc_test_result values ('4. RPCの結果', '失敗');
    insert into public.seika_rpc_test_result values ('5. エラー', 'SQLSTATE '||SQLSTATE||' / '||SQLERRM);
  end;

  perform set_config('role', 'none', true);
end $$;

-- 関数の実行区分と所有者、権限
insert into public.seika_rpc_test_result
select '6. 関数の状態',
       '所有者 '||pg_get_userbyid(p.proowner)
       ||' / '||case when p.prosecdef then 'DEFINER' else 'INVOKER' end
       ||' / ログイン済み実行 '||case when has_function_privilege('authenticated', p.oid, 'EXECUTE') then '○' else '×' end
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname='public' and p.proname='save_history_records_v188';

-- 対象テーブルのRLS状態（強制RLSだと DEFINER でも弾かれる）
insert into public.seika_rpc_test_result
select '7. '||c.relname||' のRLS',
       'RLS '||case when c.relrowsecurity then '有効' else '無効' end
       ||' / 強制 '||case when c.relforcerowsecurity then '有効' else '無効' end
       ||' / 所有者 '||pg_get_userbyid(c.relowner)
       ||' / ポリシー '||(select count(*) from pg_policies pol
                          where pol.schemaname='public' and pol.tablename=c.relname)||'件'
from pg_class c
join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public'
  and c.relname in ('waste_records','inventory_records','inventory_movements');

insert into public.seika_rpc_test_result
select '8. 現在の行数',
       'waste_records '||(select count(*) from public.waste_records)||' 行';

select * from public.seika_rpc_test_result order by 項目;
