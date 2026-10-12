-- ============================================================
-- SEIKA＋ 役割制限が効かない原因の特定（管理者になりきって実験）
--
--   廃棄を登録しても waste_records が 287 行から増えないため、
--   データベース側で「管理者としてログインした状態」を再現し、
--   どこで止まっているかを実際に試して確かめます。
--
--   ・current_app_role() が役割を返せるか
--   ・ポリシー評価に必要な実行権限があるか
--   ・実際に1行登録できるか（テスト行は自動で削除します）
--
--   参照と一時的なテストのみです。既存データは変更しません。
-- ============================================================

create temp table if not exists _seika_diag(step text, result text);
truncate _seika_diag;

do $$
declare
  uid   uuid;
  mail  text;
  r     text;
  err   text;
  okins boolean;
  testid text := '__diagtest__' || gen_random_uuid()::text;
begin
  -- 管理者を1人選ぶ
  select p.id into uid
  from public.profiles p
  where p.role = 'admin' and p.active = true
  limit 1;

  select u.email into mail from auth.users u where u.id = uid;

  insert into _seika_diag values ('1. 実験に使う管理者', coalesce(mail, uid::text));

  -- ---------- 実験A: current_app_role() ----------
  perform set_config('request.jwt.claims', json_build_object('sub', uid)::text, true);
  set local role authenticated;
  begin
    select public.current_app_role() into r;
    err := null;
  exception when others then
    r := null; err := SQLERRM;
  end;
  reset role;

  insert into _seika_diag values ('2. current_app_role() の戻り値', coalesce(r, 'NULL（役割を取れていない）'));
  insert into _seika_diag values ('3. 関数呼び出しのエラー', coalesce(err, 'なし'));

  -- ---------- 実験B: 実際に1行登録してみる ----------
  perform set_config('request.jwt.claims', json_build_object('sub', uid)::text, true);
  set local role authenticated;
  begin
    insert into public.waste_records
      (id, waste_date, item_name, qty, unit_price, amount, user_name, created_at, updated_at, data)
    values
      (testid, current_date, '診断用テスト', 0, 0, 0, '診断', now(), now(), '{}'::jsonb);
    okins := true; err := null;
  exception when others then
    okins := false; err := SQLERRM;
  end;
  reset role;

  insert into _seika_diag values ('4. 管理者として登録できたか', case when okins then '成功' else '失敗' end);
  insert into _seika_diag values ('5. 登録時のエラー', coalesce(err, 'なし'));

  -- テスト行を片付ける
  delete from public.waste_records where id like '__diagtest__%';
  insert into _seika_diag values ('6. テスト行の削除', '完了');
end $$;

-- ---------- 実行権限の確認 ----------
insert into _seika_diag
select '7. current_app_role() の実行権限',
       'ログイン済み:' || case when has_function_privilege('authenticated', p.oid, 'EXECUTE') then '○' else '×（これが原因）' end
       || ' ／ 未ログイン:' || case when has_function_privilege('anon', p.oid, 'EXECUTE') then '○' else '×' end
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'current_app_role';

insert into _seika_diag
select '8. 現在の行数', count(*)::text || ' 行' from public.waste_records;

select step as 確認項目, result as 結果 from _seika_diag order by step;
