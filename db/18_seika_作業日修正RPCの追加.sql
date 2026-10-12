-- ============================================================
-- SEIKA＋ v1.197 アプリから作業日を修正するための関数
--   品目別歩留まり表の「作業日の修正」から呼ばれます。
--   作業日を更新し、その日報の単価を計算し直します。
--   在庫・QR履歴には触れません。
-- ============================================================

create or replace function public.update_trimming_job_work_date_v1197(
  p_job_id    uuid,
  p_work_date date
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $fn$
declare
  v_job public.trimming_jobs%rowtype;
begin
  if p_work_date is null then
    return jsonb_build_object('ok', false, 'message', '作業日を指定してください');
  end if;

  update public.trimming_jobs
     set work_date = p_work_date,
         updated_at = pg_catalog.now()
   where id = p_job_id
  returning * into v_job;

  if not found then
    return jsonb_build_object('ok', false, 'message', '対象の日報が見つかりません');
  end if;

  perform public.recalc_trimming_job_price_v1195(p_job_id);

  select * into v_job from public.trimming_jobs where id = p_job_id;
  return jsonb_build_object('ok', true, 'job', pg_catalog.to_jsonb(v_job));
end;
$fn$;

grant execute on function public.update_trimming_job_work_date_v1197(uuid, date)
  to anon, authenticated;

select 'update_trimming_job_work_date_v1197 を作成しました' as 結果;
