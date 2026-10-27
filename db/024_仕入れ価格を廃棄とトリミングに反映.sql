/*
024_仕入れ価格を廃棄とトリミングに反映.sql（v1.199-c62）
1. 価格の決め方を「その週の価格」に合わせます。
   市場から仕入れた原料は、その週の市場価格を使います。その週が未入力なら「未入力」として金額を出しません
   （前の週の価格は使いません）。廃棄は廃棄した日の週、トリミング日報は原料ロットの入荷日の週です。
   契約価格はこれまでどおり、次の改定まで同じ価格を使います。
   仕入先が空欄などで「同一品目平均」になる行は、その週に使える価格（その週の市場価格と、その週に有効な契約価格）だけで平均します。
2. 仕入れ価格表で価格を保存・修正・持ち越ししたとき、その価格を使う廃棄（QR廃棄・通常廃棄）とトリミング日報を計算し直します。
   手で単価を直した行も、Excel出力済みの行も計算し直します。
3. このSQLを実行したときに、2026年9月1日以降の分を一度まとめて計算し直します。
前提：000〜023を実行済みであること。何度実行しても同じ結果になります。
説明は行頭のハイフン2つを使わない書き方にしています（スマホから貼り付けても壊れないようにするため）。
*/
begin;

create or replace function public.resolve_trimming_purchase_price_v1117(p_item_name text, p_origin text, p_supplier text, p_received_date date)
returns jsonb language plpgsql stable security definer set search_path to ''
as $function$
declare
  v_names text[]; v_week date; v_row public.purchase_prices%rowtype; v_price numeric; v_count integer := 0;
  v_market boolean; v_supplier text; v_origin text;
  v_market_names constant text[] := array['水戸大同','大同','水戸中央','中央','東一','シティ'];
begin
  if p_received_date is null or btrim(coalesce(p_item_name,'')) = '' then
    return jsonb_build_object('found',false,'match_type','未計算','match_reason','品目または日付がありません','average_count',0);
  end if;
  v_week := public.trimming_week_start(p_received_date);
  v_origin := coalesce(p_origin,'');
  v_supplier := public.trimming_normalize_supplier_v1117(p_supplier);
  v_market := v_supplier = any(v_market_names);
  v_names := public.seika_item_name_group_v1200(p_item_name);

  if v_market then
    select pp.* into v_row from public.purchase_prices pp
    where pp.week_start = v_week and pp.item_name = any(v_names) and pp.price_type = 'market'
      and public.trimming_normalize_supplier_v1117(pp.supplier) = '市場'
    order by pp.updated_at desc limit 1;
    if found then
      return jsonb_build_object('found',true,'price_yen_per_kg',v_row.price_yen_per_kg,'match_type','市場価格',
        'match_reason',concat(coalesce(p_supplier,''),'を仕入価格表の「市場」へ対応（',to_char(v_week,'YYYY/MM/DD'),'の週）'),
        'source_supplier',v_row.supplier,'source_week_start',v_row.week_start,'average_count',0);
    end if;
    return jsonb_build_object('found',false,'match_type','未入力',
      'match_reason',concat(to_char(v_week,'YYYY/MM/DD'),'の週の市場価格が未入力です'),'source_week_start',v_week,'average_count',0);
  end if;

  if v_supplier <> '' then
    select pp.* into v_row from public.purchase_prices pp
    where pp.week_start <= v_week and pp.item_name = any(v_names) and pp.origin = v_origin and pp.price_type = 'contract'
      and public.trimming_normalize_supplier_v1117(pp.supplier) = v_supplier
    order by pp.week_start desc, pp.updated_at desc limit 1;
    if found then
      return jsonb_build_object('found',true,'price_yen_per_kg',v_row.price_yen_per_kg,'match_type','契約価格',
        'match_reason',concat('仕入先「',coalesce(p_supplier,''),'」の最新契約価格'),'source_supplier',v_row.supplier,
        'source_week_start',v_row.week_start,'average_count',0);
    end if;
    select pp.* into v_row from public.purchase_prices pp
    where pp.week_start <= v_week and pp.item_name = any(v_names) and pp.price_type = 'contract'
      and public.trimming_normalize_supplier_v1117(pp.supplier) = v_supplier
    order by pp.week_start desc, pp.updated_at desc limit 1;
    if found then
      return jsonb_build_object('found',true,'price_yen_per_kg',v_row.price_yen_per_kg,'match_type','契約価格',
        'match_reason',concat('仕入先「',coalesce(p_supplier,''),'」の最新契約価格（産地不問）'),'source_supplier',v_row.supplier,
        'source_week_start',v_row.week_start,'average_count',0);
    end if;
  end if;

  with valid as (
    select x.price_yen_per_kg from (
      select pp.price_yen_per_kg from public.purchase_prices pp
      where pp.week_start = v_week and pp.item_name = any(v_names) and pp.price_type = 'market'
        and public.trimming_normalize_supplier_v1117(pp.supplier) = '市場'
      order by pp.updated_at desc limit 1
    ) x
    union all
    select y.price_yen_per_kg from (
      select distinct on (pp.origin, public.trimming_normalize_supplier_v1117(pp.supplier)) pp.price_yen_per_kg
      from public.purchase_prices pp
      where pp.week_start <= v_week and pp.item_name = any(v_names) and pp.price_type = 'contract'
      order by pp.origin, public.trimming_normalize_supplier_v1117(pp.supplier), pp.week_start desc, pp.updated_at desc
    ) y
  )
  select round(avg(price_yen_per_kg),0), count(*) into v_price, v_count from valid;
  if v_count > 0 then
    return jsonb_build_object('found',true,'price_yen_per_kg',v_price,'match_type','同一品目平均',
      'match_reason',concat('市場・契約価格に該当なし。',to_char(v_week,'YYYY/MM/DD'),'の週に使える価格',v_count,'件を平均して四捨五入'),
      'source_supplier','同一品目平均','source_week_start',v_week,'average_count',v_count);
  end if;
  return jsonb_build_object('found',false,'match_type','未入力',
    'match_reason',concat(to_char(v_week,'YYYY/MM/DD'),'の週の価格が未入力です'),'source_week_start',v_week,'average_count',0);
end;
$function$;

create or replace function public.seika_reprice_trimming_job_v1620(p_job_id uuid)
returns void language plpgsql security definer set search_path to ''
as $function$
declare r record; v jsonb; v_price numeric; v_cost numeric := 0; v_all boolean := true; v_types text[] := array[]::text[];
  v_input numeric; v_work date;
begin
  select work_date, input_weight_kg into v_work, v_input from public.trimming_jobs where id = p_job_id;
  if not found then return; end if;
  for r in
    select l.qr_key, btrim(coalesce(l.item_name,'')) as item_name, l.origin, l.supplier, l.used_weight_kg,
           coalesce(q.received_date, v_work) as ref_date
    from public.trimming_job_lots l left join public.qr_lots q on q.qr_key = l.qr_key
    where l.trimming_job_id = p_job_id
  loop
    v := public.resolve_trimming_purchase_price_v1117(r.item_name, r.origin, r.supplier, r.ref_date);
    v_price := nullif(v->>'price_yen_per_kg','')::numeric;
    if coalesce(v_price,0) > 0 then v_cost := v_cost + coalesce(r.used_weight_kg,0) * v_price;
    else v_all := false; v_price := null; end if;
    update public.trimming_job_lots
       set purchase_price_yen_per_kg = v_price,
           purchase_price_week_start = nullif(v->>'source_week_start','')::date,
           price_match_type = coalesce(v->>'match_type','未計算'),
           price_match_reason = coalesce(v->>'match_reason',''),
           price_source_supplier = coalesce(v->>'source_supplier',''),
           price_average_count = coalesce(nullif(v->>'average_count','')::integer,0)
     where trimming_job_id = p_job_id and qr_key = r.qr_key;
    v_types := v_types || coalesce(v->>'match_type','未計算');
  end loop;
  update public.trimming_jobs
     set purchase_price_yen_per_kg = case when v_all and coalesce(v_input,0) > 0 then round(v_cost / v_input, 2) end,
         input_cost_yen = case when v_all then round(v_cost, 0) end,
         price_match_summary = (select string_agg(distinct t, ' / ') from unnest(v_types) t),
         updated_at = pg_catalog.now()
   where id = p_job_id;
end;
$function$;

create or replace function public.recalc_trimming_job_price_v1195(p_job_id uuid)
returns void language plpgsql security definer set search_path to ''
as $function$
begin
  perform public.seika_require_role_v1240('{admin,worker,buyer,sales,clerk}'::text[]);
  perform public.seika_reprice_trimming_job_v1620(p_job_id);
end;
$function$;

do $do$
declare v_def text; v_pos int;
begin
  v_def := pg_get_functiondef('public.guard_seika_qr_write_v187()'::regprocedure);
  if position('seika.reprice_v1620' in v_def) = 0 then
    v_pos := position('$function$' in v_def);
    execute left(v_def, v_pos - 1) || regexp_replace(substr(v_def, v_pos), '\mbegin\M',
      'begin' || E'\n  if tg_table_name = ''qr_lot_movements'' and tg_op = ''UPDATE'' and current_setting(''seika.reprice_v1620'', true) = ''on'' then return new; end if;', 'i');
  end if;
end
$do$;

create or replace function public.seika_reprice_v1620(p_item_name text, p_from date, p_to date)
returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare
  v_names text[] := case when btrim(coalesce(p_item_name,'')) = '' then null else public.seika_item_name_group_v1200(p_item_name) end;
  m record; w record; j record; v jsonb; v_found boolean; v_unit numeric; v_weight numeric; v_pack numeric; v_ref date;
  n_qr integer := 0; n_normal integer := 0; n_trim integer := 0; n_exported integer := 0; n_none integer := 0; v_now text := to_char(now() at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
begin
  perform set_config('seika.reprice_v1620','on',true);
  for m in
    select x.*, l.item_name lot_item, l.origin lot_origin, l.supplier lot_supplier, l.received_date lot_received, l.pack_weight lot_pack
    from public.qr_lot_movements x
    join public.qr_lots l on l.id = x.lot_id
    where x.movement_type = '廃棄' and x.cancelled_at is null and x.reversed_operation_id is null
      and (coalesce(x.occurred_at, x.created_at) at time zone 'Asia/Tokyo')::date between p_from and p_to
      and (v_names is null or btrim(l.item_name) = any(v_names))
    for update of x
  loop
    if public.seika_qr_operation_cancelled_v1162(m.operation_id::text) then continue; end if;
    v_pack := public.seika_parse_kg_v1162(m.lot_pack);
    v_weight := coalesce(nullif(m.weight,0),
      case when m.before_weight is not null and m.after_weight is not null and abs(m.before_weight-m.after_weight) > 0 then abs(m.before_weight-m.after_weight) end,
      case when v_pack > 0 and m.qty > 0 then round(v_pack*m.qty,3) end);
    v_ref := (coalesce(m.occurred_at, m.created_at) at time zone 'Asia/Tokyo')::date;
    v := public.resolve_trimming_purchase_price_v1117(m.lot_item, coalesce(m.lot_origin,''), coalesce(m.lot_supplier,''), v_ref);
    v_found := coalesce((v->>'found')::boolean,false);
    v_unit := case when v_found then (v->>'price_yen_per_kg')::numeric end;
    if not v_found then n_none := n_none + 1; end if;
    update public.qr_lot_movements
       set purchase_price_yen_per_kg = v_unit,
           waste_amount_yen = case when v_unit is not null and v_weight > 0 then round(v_unit*v_weight,2) end,
           price_match_type = coalesce(v->>'match_type','未計算'),
           price_match_reason = coalesce(v->>'match_reason',''),
           price_source_supplier = nullif(v->>'source_supplier',''),
           price_average_count = coalesce((v->>'average_count')::integer,0),
           price_reference_date = v_ref,
           price_calculated_at = now()
     where id = m.id;
    n_qr := n_qr + 1;
    if m.excel_exported_at is not null then n_exported := n_exported + 1; end if;
  end loop;

  perform set_config('seika.reprice_v1620','off',true);

  for w in
    select * from public.waste_records r
    where r.waste_date between p_from and p_to
      and (v_names is null or btrim(coalesce(r.item_name, r.data->>'itemName','')) = any(v_names))
    for update
  loop
    v := public.resolve_trimming_purchase_price_v1117(coalesce(w.item_name, w.data->>'itemName'), coalesce(w.data->>'origin',''), coalesce(w.data->>'supplier',''), w.waste_date);
    v_found := coalesce((v->>'found')::boolean,false);
    v_unit := case when v_found then round((v->>'price_yen_per_kg')::numeric,2) else 0 end;
    if not v_found then n_none := n_none + 1; end if;
    update public.waste_records
       set unit_price = v_unit,
           amount = round(coalesce(w.qty,0)*v_unit,2),
           updated_at = now(),
           data = coalesce(w.data,'{}'::jsonb) || jsonb_build_object(
             'unitPrice', v_unit, 'amount', round(coalesce(w.qty,0)*v_unit,2),
             'priceMatchType', coalesce(v->>'match_type','未計算'), 'priceMatchReason', coalesce(v->>'match_reason',''),
             'priceSourceSupplier', coalesce(v->>'source_supplier',''), 'priceAverageCount', coalesce((v->>'average_count')::integer,0),
             'priceUpdatedAt', v_now, 'updatedAt', v_now)
     where id = w.id;
    n_normal := n_normal + 1;
    if w.excel_exported_at is not null or coalesce(w.data->>'excelExportedAt','') <> '' then n_exported := n_exported + 1; end if;
  end loop;

  for j in
    select distinct t.id from public.trimming_jobs t
    join public.trimming_job_lots l on l.trimming_job_id = t.id
    left join public.qr_lots q on q.qr_key = l.qr_key
    where coalesce(q.received_date, t.work_date) between p_from and p_to
      and (v_names is null or btrim(coalesce(l.item_name,'')) = any(v_names))
  loop
    perform public.seika_reprice_trimming_job_v1620(j.id);
    n_trim := n_trim + 1;
  end loop;

  return jsonb_build_object('ok',true,'qr_waste',n_qr,'normal_waste',n_normal,'trimming',n_trim,'exported',n_exported,'no_price',n_none,'from',p_from,'to',p_to);
end;
$function$;

create or replace function public.reprice_purchase_v1620(p_item_name text, p_week date, p_price_type text default 'market')
returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare v_week date; v_to date;
begin
  perform public.trimming_require_role(array['admin','worker','buyer','clerk']);
  if p_week is null then raise exception '週を選んでください'; end if;
  v_week := public.trimming_week_start(p_week);
  v_to := case when p_price_type = 'contract' and btrim(coalesce(p_item_name,'')) <> '' then greatest(current_date, v_week) + 6 else v_week + 6 end;
  return public.seika_reprice_v1620(p_item_name, v_week, v_to);
end;
$function$;

revoke all on function public.seika_reprice_trimming_job_v1620(uuid) from public, anon, authenticated;
revoke all on function public.seika_reprice_v1620(text,date,date) from public, anon, authenticated;
grant execute on function public.seika_reprice_trimming_job_v1620(uuid) to service_role;
grant execute on function public.seika_reprice_v1620(text,date,date) to service_role;
revoke all on function public.reprice_purchase_v1620(text,date,text) from public, anon;
grant execute on function public.reprice_purchase_v1620(text,date,text) to authenticated, service_role;
revoke all on function public.recalc_trimming_job_price_v1195(uuid) from public, anon;
grant execute on function public.recalc_trimming_job_price_v1195(uuid) to authenticated, service_role;

create table if not exists public.seika_reprice_log_v1620 (
  id bigserial primary key, ran_at timestamptz not null default now(), note text, result jsonb
);
alter table public.seika_reprice_log_v1620 enable row level security;
revoke all on public.seika_reprice_log_v1620 from anon, public, authenticated;

insert into public.seika_reprice_log_v1620(note, result)
select '024実行時：2026年9月以降をまとめて計算し直し', public.seika_reprice_v1620(null, date '2026-09-01', current_date + 6);

commit;

/* 成功の確かめ方：下のSELECTを実行して、5行とも「OK」になれば成功です。
   「まとめて計算し直した件数」の行には、計算し直した件数が出ます。 */
select '価格の決め方（その週の価格）' as 項目, case when pg_get_functiondef('public.resolve_trimming_purchase_price_v1117(text,text,text,date)'::regprocedure) like '%未入力%' then 'OK' else 'NG' end as 結果
union all select 'QR廃棄の単価の書き換え許可', case when pg_get_functiondef('public.guard_seika_qr_write_v187()'::regprocedure) like '%seika.reprice_v1620%' then 'OK' else 'NG' end
union all select '価格を保存したときの計算し直し', case when to_regprocedure('public.reprice_purchase_v1620(text,date,text)') is not null then 'OK' else 'NG' end
union all select 'トリミング日報の権限チェック', case when pg_get_functiondef('public.recalc_trimming_job_price_v1195(uuid)'::regprocedure) like '%seika_require_role_v1240%' then 'OK' else 'NG' end
union all select 'まとめて計算し直した件数', (select 'OK（QR廃棄 ' || (result->>'qr_waste') || '件・通常廃棄 ' || (result->>'normal_waste') || '件・トリミング日報 ' || (result->>'trimming') || '件・価格未入力 ' || (result->>'no_price') || '件）' from public.seika_reprice_log_v1620 order by id desc limit 1);
