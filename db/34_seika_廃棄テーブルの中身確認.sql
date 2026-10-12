-- ============================================================
-- SEIKA＋ 廃棄記録が削除できない原因の特定（参照のみ・変更なし）
--
--   32番でポリシーと権限を付与しても削除できなかったため、
--   「そもそも waste_records にその行が存在するのか」を確認します。
--
--   背景：v1.199 より前のアプリは、履歴テーブルへの通信に
--         未ログイン用のキー（anon）を使っていました。
--         anon は waste_records に一切権限がないため、
--         これまでの登録はすべて拒否されていた可能性があります。
--         その場合テーブルは空で、画面の廃棄一覧は
--         app_state（アプリ本体の保存領域）から表示されています。
--
--   結果はすべて1つの表にまとめて出ます。
--   Supabaseのエディタにそのまま貼って実行してください。
-- ============================================================

select * from (

  -- 【A】waste_records に何行入っているか
  select 1 as 並び, 'A. waste_records の行数' as 区分,
         count(*)::text || ' 行' as 内容
  from public.waste_records

  union all

  -- 【B】入っている場合、いつのデータか
  select 2, 'B. 登録日時の範囲',
         coalesce(min(created_at)::text, '（データなし）')
         || ' 〜 ' ||
         coalesce(max(created_at)::text, '（データなし）')
  from public.waste_records

  union all

  -- 【C】直近5件のID（画面の記録と突き合わせる用）
  select 3, 'C. 直近のID', coalesce(string_agg(t.id::text, ' , '), '（データなし）')
  from (
    select id from public.waste_records
    order by created_at desc nulls last
    limit 5
  ) t

  union all

  -- 【D】削除をブロックし得る制限型ポリシーの有無
  select 4, 'D. ポリシー（削除に関係するもの）',
         policyname || ' / ' || permissive || ' / ' || cmd
         || ' / 対象:' || array_to_string(roles, ',')
         || ' / 条件:' || coalesce(qual, 'なし')
  from pg_policies
  where schemaname = 'public'
    and tablename = 'waste_records'
    and cmd in ('DELETE', 'ALL')

  union all

  -- 【E】削除を止めるトリガーの有無
  select 5, 'E. トリガー',
         coalesce(
           string_agg(tg.tgname || ' / ' || p.proname, ' , '),
           '（なし）'
         )
  from pg_trigger tg
  join pg_class c on c.oid = tg.tgrelid
  join pg_namespace n on n.oid = c.relnamespace
  join pg_proc p on p.oid = tg.tgfoid
  where n.nspname = 'public'
    and c.relname = 'waste_records'
    and not tg.tgisinternal

) x
order by 並び, 内容;
