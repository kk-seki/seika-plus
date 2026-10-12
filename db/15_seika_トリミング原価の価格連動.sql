-- ============================================================
-- SEIKA＋ トリミング日報に仕入価格を連動させる
--   症状: 品目別歩留まり表の「採用単価/原料費/歩留まり原価」が全て未計算
--   原因: create_trimming_job が purchase_price_yen_per_kg / input_cost_yen を
--         明示的に null で保存しており、価格解決関数を呼んでいない
--   対応: ①再計算関数を新設 ②create_trimming_job から呼ぶ ③既存分を遡って計算
--   ※ 在庫・QR履歴には触れません。価格列のみ更新します。
-- ============================================================

-- ① 再計算関数（市場価格→契約価格→同一品目平均 の既存ロジックを流用）
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
begin
  for r in
    select l.qr_key, l.item_name, l.origin, l.supplier, l.used_weight_kg, q.received_date
    from public.trimming_job_lots l
    left join public.qr_lots q on q.qr_key = l.qr_key
    where l.trimming_job_id = p_job_id
  loop
    v := public.resolve_trimming_purchase_price_v1117(
           r.item_name, r.origin, r.supplier, r.received_date);
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

  select input_weight_kg into v_input from public.trimming_jobs where id = p_job_id;

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

-- ② create_trimming_job の末尾から呼ぶ（該当が1件でなければ例外で中断）
do $$
declare
  v_def text;
  v_old text := 'return jsonb_build_object(''ok'',true,''idempotent'',false,''job'',to_jsonb(v_job));';
  v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'create_trimming_job';

  if v_def is null then
    raise exception 'public.create_trimming_job が見つかりません';
  end if;

  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then
    raise exception '差し込み位置が1件ではありません（変更していません）';
  end if;

  if position('recalc_trimming_job_price_v1195' in v_def) > 0 then
    raise notice '既に連動済みのためスキップします';
  else
    v_new := replace(v_def, v_old,
      'perform public.recalc_trimming_job_price_v1195(v_job_id);' || E'\n  ' ||
      'select * into v_job from public.trimming_jobs where id=v_job_id;' || E'\n  ' || v_old);
    execute v_new;
    raise notice 'create_trimming_job に価格連動を追加しました';
  end if;
end $$;

-- ③ 既存のトリミング日報を遡って計算する
set local session_replication_role = replica;

do $$
declare r record; n integer := 0;
begin
  for r in select id from public.trimming_jobs order by work_date loop
    perform public.recalc_trimming_job_price_v1195(r.id);
    n := n + 1;
  end loop;
  raise notice '% 件を再計算しました', n;
end $$;

set local session_replication_role = origin;

-- ④ 確認（直近の登録分）
select work_date        as 作業日,
       source_item_name as 品目,
       input_weight_kg  as 使用kg,
       purchase_price_yen_per_kg as 採用単価,
       input_cost_yen   as 原料費,
       price_match_summary       as 採用区分
from public.trimming_jobs
order by work_date desc, created_at desc
limit 20;
