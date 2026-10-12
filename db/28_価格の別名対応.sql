/* SEIKA+ 仕入価格の品目名を別名込みで判定する。ロメインレタス等の未計算を解消する。 */

create or replace function public.seika_item_name_group_v1200(p_name text)
returns text[]
language sql
immutable
security definer
set search_path to ''
as $function$
  with g(names) as (
    values
    (array['人参','人参（国産）','国産人参']),
    (array['葉付き大根','葉付大根']),
    (array['玉葱','玉ねぎ']),
    (array['グリーンリーフ','グリーンカール','リーフレタス','リーフ']),
    (array['サニーレタス','サニー']),
    (array['ロメインレタス','ロメイン'])
  ),
  hit as (
    select names from g where btrim(coalesce(p_name,'')) = any(names) limit 1
  )
  select coalesce(
    (select names from hit),
    array[btrim(coalesce(p_name,''))]
  );
$function$;

CREATE OR REPLACE FUNCTION public.resolve_trimming_purchase_price_v1117(p_item_name text, p_origin text, p_supplier text, p_received_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_names text[];
  v_week date;
  v_row public.purchase_prices%rowtype;
  v_price numeric;
  v_count integer:=0;
  v_market boolean;
  v_supplier text;
  v_origin text;
  -- 市場4社（別名を明示登録した完全一致リスト）
  -- 中央園芸／茨城中央園芸／飯山中央市場／中央VFS／市場商事 は契約産地のため含めない
  v_market_names constant text[]:=array['水戸大同','大同','水戸中央','中央','東一','シティ'];
begin
  if p_received_date is null or btrim(coalesce(p_item_name,''))='' then
    return jsonb_build_object('found',false,'match_type','未計算','match_reason','品目または入庫日がありません','average_count',0);
  end if;
  v_week:=public.trimming_week_start(p_received_date);
  v_origin:=coalesce(p_origin,'');
  v_supplier:=public.trimming_normalize_supplier_v1117(p_supplier);
  v_market:=v_supplier = any(v_market_names);
  v_names:=public.seika_item_name_group_v1200(p_item_name);

  if v_market then
    -- 市場価格：産地は一切見ない。当週が未登録なら直近の登録週を使う
    select pp.* into v_row
    from public.purchase_prices pp
    where pp.week_start<=v_week
      and pp.item_name = any(v_names)
      and pp.price_type='market'
      and public.trimming_normalize_supplier_v1117(pp.supplier)='市場'
    order by pp.week_start desc,pp.updated_at desc limit 1;
    if found then
      return jsonb_build_object('found',true,'price_yen_per_kg',v_row.price_yen_per_kg,'match_type','市場価格',
        'match_reason',concat(coalesce(p_supplier,''),'を仕入価格表の「市場」へ対応（産地不問）'),'source_supplier',v_row.supplier,
        'source_week_start',v_row.week_start,'average_count',0);
    end if;
  else
    -- 契約価格①：産地が一致するものを優先
    select pp.* into v_row
    from public.purchase_prices pp
    where pp.week_start<=v_week
      and pp.item_name = any(v_names)
      and pp.origin=v_origin
      and pp.price_type='contract'
      and public.trimming_normalize_supplier_v1117(pp.supplier)=v_supplier
    order by pp.week_start desc,pp.updated_at desc limit 1;
    if found then
      return jsonb_build_object('found',true,'price_yen_per_kg',v_row.price_yen_per_kg,'match_type','契約価格',
        'match_reason',concat('仕入先「',coalesce(p_supplier,''),'」の最新契約価格'),'source_supplier',v_row.supplier,
        'source_week_start',v_row.week_start,'average_count',0);
    end if;
    -- 契約価格②：産地が違う／空欄でも、同一品目・同一仕入先なら採用
    select pp.* into v_row
    from public.purchase_prices pp
    where pp.week_start<=v_week
      and pp.item_name = any(v_names)
      and pp.price_type='contract'
      and public.trimming_normalize_supplier_v1117(pp.supplier)=v_supplier
    order by pp.week_start desc,pp.updated_at desc limit 1;
    if found then
      return jsonb_build_object('found',true,'price_yen_per_kg',v_row.price_yen_per_kg,'match_type','契約価格',
        'match_reason',concat('仕入先「',coalesce(p_supplier,''),'」の最新契約価格（産地不問）'),'source_supplier',v_row.supplier,
        'source_week_start',v_row.week_start,'average_count',0);
    end if;
  end if;

  with latest as (
    select distinct on (pp.price_type,pp.origin,public.trimming_normalize_supplier_v1117(pp.supplier))
      pp.price_yen_per_kg
    from public.purchase_prices pp
    where pp.item_name = any(v_names) and pp.week_start<=v_week
    order by pp.price_type,pp.origin,public.trimming_normalize_supplier_v1117(pp.supplier),pp.week_start desc,pp.updated_at desc
  )
  select round(avg(price_yen_per_kg),0),count(*) into v_price,v_count from latest;
  if v_count>0 then
    return jsonb_build_object('found',true,'price_yen_per_kg',v_price,'match_type','同一品目平均',
      'match_reason',concat('市場・契約価格に該当なし。同一品目の有効価格',v_count,'件を平均して四捨五入'),
      'source_supplier','同一品目平均','source_week_start',v_week,'average_count',v_count);
  end if;
  return jsonb_build_object('found',false,'match_type','未計算','match_reason','同一品目の登録価格がありません','average_count',0);
end;
$function$

;

CREATE OR REPLACE FUNCTION public.recalc_trimming_job_price_v1195(p_job_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
        where btrim(pp.item_name) = any(public.seika_item_name_group_v1200(r.item_name))
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
$function$

;

begin;
set local session_replication_role = replica;
do $$
declare j record;
begin
  for j in select id from public.trimming_jobs loop
    perform public.recalc_trimming_job_price_v1195(j.id);
  end loop;
end $$;
commit;

select 'A 別名グループの確認' as 区分,
       concat('ロメインレタス -> ', array_to_string(public.seika_item_name_group_v1200('ロメインレタス'), ', ')) as 内容
union all
select 'A 別名グループの確認',
       concat('リーフ -> ', array_to_string(public.seika_item_name_group_v1200('リーフ'), ', '))
union all
select 'A 別名グループの確認',
       concat('レタス -> ', array_to_string(public.seika_item_name_group_v1200('レタス'), ', '))
union all
select 'B 未計算がまだ残っている件数',
       count(*)::text
from public.trimming_jobs t
where t.purchase_price_yen_per_kg is null
union all
select 'C ロメインの結果',
       concat('採用単価', coalesce(l.purchase_price_yen_per_kg::text,'なし'),
              '円/kg / 判定', coalesce(l.price_match_type,''),
              ' / ', coalesce(l.price_match_reason,''))
from public.trimming_job_lots l
where l.item_name ilike '%ロメイン%'
order by 1, 2;
