-- ============================================================
-- SEIKA＋ ①人参が未計算になる問題の修正 ②既存日報の作業日の直し方
--   ①原因: ロットの入荷日(received_date)が取れないと、価格解決関数が
--           入口で「品目または入庫日がありません」を返し未計算になる。
--           入荷日が無い場合は日報の作業日で代用するよう修正する。
--   ※ 在庫・QR履歴には触れません。価格列のみ更新します。
-- ============================================================

create or replace function public.recalc_trimming_job_price_v1195(p_job_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $fn$
declare
  r        record;
  v        jsonb;
  v_price  numeric;
  v_cost   numeric := 0;
  v_all    boolean := true;
  v_types  text[]  := array[]::text[];
  v_input  numeric;
  v_work   date;
begin
  select work_date, input_weight_kg into v_work, v_input
  from public.trimming_jobs where id = p_job_id;

  for r in
    select l.qr_key, btrim(coalesce(l.item_name,'')) as item_name,
           l.origin, l.supplier, l.used_weight_kg,
           coalesce(q.received_date, v_work) as ref_date
    from public.trimming_job_lots l
    left join public.qr_lots q on q.qr_key = l.qr_key
    where l.trimming_job_id = p_job_id
  loop
    v := public.resolve_trimming_purchase_price_v1117(
           r.item_name, r.origin, r.supplier, r.ref_date);
    v_price := nullif(v->>'price_yen_per_kg','')::numeric;

    if coalesce((v->>'found')::boolean, false) and coalesce(v_price,0) > 0 then
      v_cost := v_cost + coalesce(r.used_weight_kg,0) * v_price;
    else
      v_all   := false;
      v_price := null;
    end if;

    update public.trimming_job_lots
       set purchase_price_yen_per_kg = v_price,
           purchase_price_week_start = nullif(v->>'source_week_start','')::date,
           price_match_type          = coalesce(v->>'match_type','未計算'),
           price_match_reason        = coalesce(v->>'match_reason',''),
           price_source_supplier     = coalesce(v->>'source_supplier',''),
           price_average_count       = coalesce(nullif(v->>'average_count','')::integer,0)
     where trimming_job_id = p_job_id and qr_key = r.qr_key;

    v_types := v_types || coalesce(v->>'match_type','未計算');
  end loop;

  update public.trimming_jobs
     set purchase_price_yen_per_kg =
           case when v_all and coalesce(v_input,0) > 0 then round(v_cost / v_input, 2) end,
         input_cost_yen =
           case when v_all then round(v_cost, 0) end,
         price_match_summary =
           (select string_agg(distinct t, ' / ') from unnest(v_types) t),
         updated_at = pg_catalog.now()
   where id = p_job_id;
end;
$fn$;

-- 既存の日報をすべて再計算する
set local session_replication_role = replica;
do $$
declare r record;
begin
  for r in select id from public.trimming_jobs loop
    perform public.recalc_trimming_job_price_v1195(r.id);
  end loop;
end $$;
set local session_replication_role = origin;


-- ============================================================
-- ② 作業日の直し方
--    アプリ側は v1.196 で「選んだ作業日が保持される」よう修正済みです。
--    すでに 9/4 で登録されてしまった分は、下の④で ID を確認し、
--    次の2行を1件ずつ実行して直してください（日付とIDは書き換える）。
--
--    update public.trimming_jobs set work_date='2026-09-01' where id='ここにID';
--    select public.recalc_trimming_job_price_v1195('ここにID');
--
--    ※ 作業日を変えると入荷日が無いロットの価格基準週も変わるため、
--      必ず2行目の再計算をセットで実行してください。
-- ============================================================


-- ============================================================
-- 確認（1つの表にまとめて表示）
-- ============================================================
select '③ まだ未計算のロット' as 区分,
       coalesce(l.item_name,'') || ' / ' || coalesce(l.qr_key,'') ||
       ' / 産地' || coalesce(nullif(l.origin,''),'-') ||
       ' / 仕入先' || coalesce(nullif(l.supplier,''),'-') ||
       ' / 入荷日' || coalesce(q.received_date::text,'なし') ||
       ' / 理由:' || coalesce(l.price_match_reason,'') as 内容
from public.trimming_job_lots l
left join public.qr_lots q on q.qr_key = l.qr_key
where l.purchase_price_yen_per_kg is null

union all

select '④ 日報一覧（作業日の修正用ID）',
       j.work_date::text || ' / ' || coalesce(j.source_item_name,'') ||
       ' / 単価' || coalesce(j.purchase_price_yen_per_kg::text,'未計算') ||
       ' / 原料費' || coalesce(j.input_cost_yen::text,'未計算') ||
       ' / id=' || j.id::text
from public.trimming_jobs j
order by 1, 2;
