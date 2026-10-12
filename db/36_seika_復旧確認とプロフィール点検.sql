-- ============================================================
-- SEIKA＋ 書き戻しの確認 ＋ プロフィール設定の点検
--
--   使い方：管理者でログインし直し、アプリの画面を開いたあとに実行。
--   参照のみで、変更は一切しません。
--
--   A行：履歴テーブルの行数と最終日。
--        日付が今日に近づいていれば書き戻し成功。
--   B行：current_app_role() が正しく動く状態かどうかの点検。
--        将来この関数で役割制限に戻すための材料です。
-- ============================================================

select * from (

  -- ---------- A. 書き戻しの確認 ----------
  select 1 as 並び, 'A. waste_records' as 区分,
         count(*)::text || ' 行 ／ 最終 '
         || coalesce(max(created_at)::date::text, 'なし') as 内容
  from public.waste_records
  union all
  select 1, 'A. inventory_records',
         count(*)::text || ' 行 ／ 最終 '
         || coalesce(max(created_at)::date::text, 'なし')
  from public.inventory_records
  union all
  select 1, 'A. inventory_movements',
         count(*)::text || ' 行 ／ 最終 '
         || coalesce(max(created_at)::date::text, 'なし')
  from public.inventory_movements

  -- ---------- B. プロフィールの点検 ----------
  union all
  select 2, 'B-1. ログイン利用者の数',
         (select count(*)::text from auth.users) || ' 人'
  union all
  select 2, 'B-2. profiles の行数',
         (select count(*)::text from public.profiles) || ' 行'
  union all
  select 2, 'B-3. auth.uid と profiles が一致する人',
         (select count(*)::text
          from auth.users u
          join public.profiles p on p.id = u.id) || ' 人'
  union all
  select 2, 'B-4. うち active = true',
         (select count(*)::text
          from auth.users u
          join public.profiles p on p.id = u.id
          where p.active = true) || ' 人'
  union all
  select 2, 'B-5. profiles に無い利用者',
         coalesce((select string_agg(u.email, ' , ')
                   from auth.users u
                   left join public.profiles p on p.id = u.id
                   where p.id is null), '（なし）')
  union all
  select 2, 'B-6. 登録されている役割',
         coalesce((select string_agg(x.role || ':' || x.c::text, ' , ')
                   from (select coalesce(role,'(未設定)') as role, count(*) as c
                         from public.profiles group by 1) x), '（なし）')

) y
order by 並び, 区分;
