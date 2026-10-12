-- ============================================================
-- SEIKA＋ 登録済み日報（トリミング）の修正・削除
--
--   目的：
--     入力済みの製造日報をあとから直せるようにする。
--     作業日だけでなく、使用原料・使用量・出来高・メモも修正できる。
--
--   方針：
--     既存の create_trimming_job をそのまま呼び出して新しい日報を作り、
--     成功したら古い日報を削除する（差し替え）。
--     計算ロジックを二重に持たないので、登録と修正の結果が必ず一致する。
--     途中で失敗した場合は関数全体が巻き戻り、元の日報は残る。
--
--   作るもの：
--     1) seika_delete_trimming_job_rows_v1203  … 子テーブルを自動判別して削除
--     2) delete_trimming_job_v1203             … 日報を削除
--     3) replace_trimming_job_v1203            … 日報を差し替え（修正）
--
--   実行は何度でも可（create or replace）。既存の関数・データは壊しません。
-- ============================================================

-- ------------------------------------------------------------
-- 1) 子テーブルの削除（内部用）
--    trimming_jobs を参照している外部キーを pg_constraint から
--    その場で調べて削除するので、テーブル名を決め打ちしません。
-- ------------------------------------------------------------
create or replace function public.seika_delete_trimming_job_rows_v1203(p_job_id text)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  r record;
  v_deleted integer := 0;
  v_n integer;
begin
  for r in
    select c.conrelid::regclass as child_table,
           a.attname            as child_column
      from pg_constraint c
      join pg_attribute a
        on a.attrelid = c.conrelid
       and a.attnum   = c.conkey[1]
     where c.contype = 'f'
       and c.confrelid = 'public.trimming_jobs'::regclass
       and array_length(c.conkey, 1) = 1
  loop
    execute format('delete from %s where %I::text = $1', r.child_table, r.child_column)
      using p_job_id;
    get diagnostics v_n = row_count;
    v_deleted := v_deleted + v_n;
  end loop;

  delete from public.trimming_jobs where id::text = p_job_id;
  get diagnostics v_n = row_count;
  v_deleted := v_deleted + v_n;

  return v_deleted;
end;
$$;

revoke all on function public.seika_delete_trimming_job_rows_v1203(text) from public;
revoke all on function public.seika_delete_trimming_job_rows_v1203(text) from anon;
grant execute on function public.seika_delete_trimming_job_rows_v1203(text) to service_role;


-- ------------------------------------------------------------
-- 2) 日報の削除
-- ------------------------------------------------------------
create or replace function public.delete_trimming_job_v1203(p_job_id text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_job      public.trimming_jobs;
  v_role     text;
  v_rows     integer;
begin
  begin
    v_role := public.current_app_role();
  exception when others then
    v_role := null;
  end;
  if v_role is not null and v_role not in ('admin','worker') then
    return jsonb_build_object('ok', false, 'message', '日報の削除は管理者・青果社員のみです。');
  end if;

  select * into v_job from public.trimming_jobs where id::text = p_job_id;
  if not found then
    return jsonb_build_object('ok', false, 'message', 'この日報は見つかりません。すでに削除された可能性があります。');
  end if;

  v_rows := public.seika_delete_trimming_job_rows_v1203(p_job_id);

  return jsonb_build_object(
    'ok', true,
    'deleted_rows', v_rows,
    'work_date', v_job.work_date,
    'item_name', v_job.source_item_name,
    'message', '日報を削除しました。'
  );
end;
$$;

revoke all on function public.delete_trimming_job_v1203(text) from public;
revoke all on function public.delete_trimming_job_v1203(text) from anon;
grant execute on function public.delete_trimming_job_v1203(text) to authenticated;
grant execute on function public.delete_trimming_job_v1203(text) to service_role;


-- ------------------------------------------------------------
-- 3) 日報の差し替え（修正）
--    新しい内容で登録 → 成功したら古い行を削除。
--    create_trimming_job は引数名つきで動的に呼ぶので、
--    引数の型（uuid か text かなど）が変わっても動きます。
-- ------------------------------------------------------------
create or replace function public.replace_trimming_job_v1203(
  p_job_id       text,
  p_operation_id text,
  p_work_date    text,
  p_lots         jsonb,
  p_outputs      jsonb,
  p_note         text        default '',
  p_user_name    text        default ''
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_old   public.trimming_jobs;
  v_role  text;
  v_ans   jsonb;
  v_rows  integer;
begin
  begin
    v_role := public.current_app_role();
  exception when others then
    v_role := null;
  end;
  if v_role is not null and v_role not in ('admin','worker') then
    return jsonb_build_object('ok', false, 'message', '日報の修正は管理者・青果社員のみです。');
  end if;

  select * into v_old from public.trimming_jobs where id::text = p_job_id;
  if not found then
    return jsonb_build_object('ok', false, 'message', 'もとの日報が見つかりません。画面を再読み込みしてください。');
  end if;

  -- 新しい内容で登録（既存の登録関数をそのまま使う）
  execute format(
    'select public.create_trimming_job('
    || 'p_operation_id := %L, p_work_date := %L, p_lots := %L, '
    || 'p_outputs := %L, p_note := %L, p_user_name := %L)',
    coalesce(nullif(p_operation_id,''), gen_random_uuid()::text),
    p_work_date,
    coalesce(p_lots, '[]'::jsonb)::text,
    coalesce(p_outputs, '[]'::jsonb)::text,
    coalesce(p_note, ''),
    coalesce(nullif(p_user_name,''), v_old.created_by_name, '')
  ) into v_ans;

  if v_ans is null or coalesce((v_ans->>'ok')::boolean, false) is not true then
    return jsonb_build_object(
      'ok', false,
      'message', coalesce(v_ans->>'message', '修正内容を登録できませんでした。もとの日報はそのまま残っています。')
    );
  end if;

  -- 登録できたので、もとの日報を削除
  v_rows := public.seika_delete_trimming_job_rows_v1203(p_job_id);
  if v_rows = 0 then
    raise exception 'もとの日報を削除できませんでした（job_id=%）', p_job_id;
  end if;

  return v_ans || jsonb_build_object(
    'ok', true,
    'replaced_job_id', p_job_id,
    'message', '日報を修正しました。'
  );
end;
$$;

revoke all on function public.replace_trimming_job_v1203(text,text,text,jsonb,jsonb,text,text) from public;
revoke all on function public.replace_trimming_job_v1203(text,text,text,jsonb,jsonb,text,text) from anon;
grant execute on function public.replace_trimming_job_v1203(text,text,text,jsonb,jsonb,text,text) to authenticated;
grant execute on function public.replace_trimming_job_v1203(text,text,text,jsonb,jsonb,text,text) to service_role;


-- ------------------------------------------------------------
-- 確認（作成できたかと、子テーブルの自動判別結果）
-- ------------------------------------------------------------
select '作成した関数' as 区分,
       string_agg(p.proname, ' / ' order by p.proname) as 内容
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('delete_trimming_job_v1203',
                     'replace_trimming_job_v1203',
                     'seika_delete_trimming_job_rows_v1203')
union all
select '削除対象の子テーブル' as 区分,
       coalesce(string_agg(c.conrelid::regclass::text, ' / '), '（なし）') as 内容
  from pg_constraint c
 where c.contype = 'f'
   and c.confrelid = 'public.trimming_jobs'::regclass
   and array_length(c.conkey, 1) = 1
union all
select '登録済み日報の件数' as 区分, count(*)::text as 内容 from public.trimming_jobs;
