-- ============================================================
-- SEIKA＋ 人参が「同一品目の登録価格がありません」で未計算になる問題
--   原因: 人参の仕入価格は契約2026-08-10・市場2026-08-31が最古で、
--         ロットの入荷日2026-08-01より後。価格解決関数は
--         「week_start <= 入荷日の週」しか見ないため0件になる。
--   対応: トリミングの再計算関数にだけ最終フォールバックを追加する。
--         該当週以前に価格が無い場合は、同一品目の最も古い登録価格を使う。
--         ※ 廃棄単価の計算（resolve_trimming_purchase_price_v1117 本体）は
--           変更しないため、廃棄側の挙動は一切変わりません。
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
  v_type   text;
  v_reason text;
  v_src    text;
  v_week   date;
  v_cnt    integer;
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
    v_price  := nullif(v->>'price_yen_per_kg','')::numeric;
    v_type   := coalesce(v->>'match_type','未計算');
    v_reason := coalesce(v->>'match_reason','');
    v_src    := coalesce(v->>'source_supplier','');
    v_week   := nullif(v->>'source_week_start','')::date;
    v_cnt    := coalesce(nullif(v->>'average_count','')::integer,0);

    -- 最終フォールバック：入荷日の週以前に価格が無い場合は最古の登録価格を使う
    if coalesce(v_price,0) <= 0 then
      with latest as (
        select distinct on (pp.price_type, pp.origin,
                            public.trimming_normalize_supplier_v1117(pp.supplier))
               pp.price_yen_per_kg, pp.week_start
        from public.purchase_prices pp
        where btrim(pp.item_name) = r.item_name
        order by pp.price_type, pp.origin,
                 public.trimming_normalize_supplier_v1117(pp.supplier),
                 pp.week_start asc, pp.updated_at desc
      )
      select round(avg(price_yen_per_kg),0), count(*), min(week_start)
        into v_price, v_cnt, v_week
      from latest;

      if coalesce(v_price,0) > 0 then
        v_type   := '同一品目平均（登録前の入荷）';
        v_reason := concat('入荷日', r.ref_date::text,
                           'の週以前に登録価格が無いため、最も古い登録価格',
                           v_cnt, '件を平均して四捨五入');
        v_src    := '同一品目平均';
      else
        v_price := null;
      end if;
    end if;

    if coalesce(v_price,0) > 0 then
      v_cost := v_cost + coalesce(r.used_weight_kg,0) * v_price;
    else
      v_all   := false;
      v_price := null;
    end if;

    update public.trimming_job_lots
       set purchase_price_yen_per_kg = v_price,
           purchase_price_week_start = v_week,
           price_match_type          = v_type,
           price_match_reason        = v_reason,
           price_source_supplier     = v_src,
           price_average_count       = v_cnt
     where trimming_job_id = p_job_id and qr_key = r.qr_key;

    v_types := v_types || v_type;
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
-- 作業日の修正（9/4で登録された9件）
--   下の update をまとめて実行できます。日付だけ実際の作業日に書き換えてください。
--   いまは全て '2026-09-04' のままなので、そのまま実行しても値は変わりません。
--   ※ 実行したら、その下の再計算ブロックも必ず一緒に実行してください。
-- ============================================================
/*
update public.trimming_jobs set work_date='2026-09-04' where id='631bc0e7-ff1c-4b25-9451-508381ff1080'; -- カット大根
update public.trimming_jobs set work_date='2026-09-04' where id='a4c2a76c-88d1-410b-9ab9-e858ee0e50da'; -- カット大根
update public.trimming_jobs set work_date='2026-09-04' where id='cfa1a119-dc21-46b8-965c-2b94d02877df'; -- キャベツ
update public.trimming_jobs set work_date='2026-09-04' where id='13fe85da-e412-4f49-b6c2-c9dbba41d1fa'; -- キャベツ
update public.trimming_jobs set work_date='2026-09-04' where id='f98c77f3-b7c8-4f9e-8f48-d6213fee77d7'; -- 人参
update public.trimming_jobs set work_date='2026-09-04' where id='0797f063-5960-4e24-8dc4-a91c36bbdc39'; -- 小葱
update public.trimming_jobs set work_date='2026-09-04' where id='efd2bf3a-ce69-4a49-941d-1cb739b38a5e'; -- 小葱
update public.trimming_jobs set work_date='2026-09-04' where id='d0ad5c59-dba8-4539-8fbc-fea425bcd0a6'; -- 葉付き大根
update public.trimming_jobs set work_date='2026-09-04' where id='fdcc24be-d802-4029-bc50-ccff52ac566e'; -- 葉付き大根

set local session_replication_role = replica;
do $$
declare r record;
begin
  for r in select id from public.trimming_jobs loop
    perform public.recalc_trimming_job_price_v1195(r.id);
  end loop;
end $$;
set local session_replication_role = origin;
*/


-- ============================================================
-- 確認
-- ============================================================
select '① まだ未計算のロット' as 区分,
       coalesce(l.item_name,'') || ' / ' || coalesce(l.qr_key,'') ||
       ' / 理由:' || coalesce(l.price_match_reason,'') as 内容
from public.trimming_job_lots l
where l.purchase_price_yen_per_kg is null

union all

select '② 日報一覧',
       j.work_date::text || ' / ' || coalesce(j.source_item_name,'') ||
       ' / 単価' || coalesce(j.purchase_price_yen_per_kg::text,'未計算') ||
       ' / 原料費' || coalesce(j.input_cost_yen::text,'未計算') ||
       ' / ' || coalesce(j.price_match_summary,'')
from public.trimming_jobs j
order by 1, 2;
