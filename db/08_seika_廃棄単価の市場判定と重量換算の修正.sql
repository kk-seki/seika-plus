-- ============================================================
-- SEIKA＋ 廃棄単価の修正
--   (1) 市場4社を完全一致リスト方式に。市場価格は産地を見ない
--   (2) 契約価格は産地一致を優先し、無ければ産地不問で採用
--   (3) 廃棄一覧の「重量未確定」を量目×ケース数で解消
--   (4) 既存のQR廃棄を新ルールで再計算
-- Supabase SQL Editor で上から順に実行してください
-- ============================================================
BEGIN;

-- ------------------------------------------------------------
-- (1)(2) 価格判定の本体
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.resolve_trimming_purchase_price_v1117(p_item_name text, p_origin text, p_supplier text, p_received_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
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

  if v_market then
    -- 市場価格：産地は一切見ない。当週が未登録なら直近の登録週を使う
    select pp.* into v_row
    from public.purchase_prices pp
    where pp.week_start<=v_week
      and pp.item_name=p_item_name
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
      and pp.item_name=p_item_name
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
      and pp.item_name=p_item_name
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
    where pp.item_name=p_item_name and pp.week_start<=v_week
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
$function$;

-- ------------------------------------------------------------
-- (3) 廃棄一覧の重量換算
--     量目が「5kg」のように単位付きでも読めるよう、価格計算側と同じ
--     public.seika_parse_kg_v1162() を使う
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.list_unified_waste_records_v1144(p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile public.profiles%rowtype;
  v_from date:=least(coalesce(p_from,(now() at time zone 'Asia/Tokyo')::date),coalesce(p_to,(now() at time zone 'Asia/Tokyo')::date));
  v_to date:=greatest(coalesce(p_from,(now() at time zone 'Asia/Tokyo')::date),coalesce(p_to,(now() at time zone 'Asia/Tokyo')::date));
  v_rows jsonb;
begin
  v_profile:=public.seika_v1144_require_active_profile();
  with qr_base as (
    select q.*,l.pack_weight,pw.pack_weight_numeric,
      case when q.weight is not null and q.weight>0 then q.weight
           when q.before_weight is not null and q.after_weight is not null and abs(q.before_weight-q.after_weight)>0 then abs(q.before_weight-q.after_weight)
           when pw.pack_weight_numeric is not null and pw.pack_weight_numeric>0 and q.qty>0 then round(pw.pack_weight_numeric*q.qty,3)
           else null end resolved_weight,
      case when q.weight is not null and q.weight>0 then '確定'
           when q.before_weight is not null and q.after_weight is not null and abs(q.before_weight-q.after_weight)>0 then '重量差分換算'
           when pw.pack_weight_numeric is not null and pw.pack_weight_numeric>0 and q.qty>0 then '量目換算'
           else '未確定' end resolved_weight_status
    from public.qr_lot_movements q
    left join public.qr_lots l on l.id=q.lot_id
    cross join lateral (
      select public.seika_parse_kg_v1162(l.pack_weight) as pack_weight_numeric
    ) pw
    where q.movement_type='廃棄'
      and (coalesce(q.occurred_at,q.created_at) at time zone 'Asia/Tokyo')::date between v_from and v_to
      and q.cancelled_at is null and q.reversed_operation_id is null
      and not public.seika_v1144_qr_operation_cancelled(q.operation_id)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'source','qr','source_id',q.id::text,'operation_id',q.operation_id,'occurred_at',coalesce(q.occurred_at,q.created_at),
      'date',(coalesce(q.occurred_at,q.created_at) at time zone 'Asia/Tokyo')::date,
      'item_name',q.item_name,'item_id',q.item_id,'lot_no',q.lot_no,'qr_key',q.qr_key,'origin',q.origin,'supplier',q.supplier,'cooperative_name',q.cooperative_name,
      'qty',q.qty,'unit',q.unit,'weight',q.resolved_weight,'weight_status',q.resolved_weight_status,
      'reason',q.reason,'memo',q.memo,'user_name',q.user_name,
      'purchase_price_yen_per_kg',q.purchase_price_yen_per_kg,'waste_amount_yen',q.waste_amount_yen,
      'price_match_type',coalesce(q.price_match_type,'未計算'),'price_match_reason',coalesce(q.price_match_reason,case when q.resolved_weight is null then '廃棄重量が確定していないため金額未計算' else '' end),
      'price_source_supplier',q.price_source_supplier,'price_average_count',coalesce(q.price_average_count,0),'price_reference_date',q.price_reference_date,'price_calculated_at',q.price_calculated_at
    ) order by coalesce(q.occurred_at,q.created_at) desc),'[]'::jsonb) into v_rows
  from qr_base q;
  return jsonb_build_object('ok',true,'from',v_from,'to',v_to,'rows',v_rows);
end;
$function$;

COMMIT;

-- ------------------------------------------------------------
-- (4) 既存のQR廃棄を新ルールで再計算
--     「手動修正」した行は上書きしません
-- ------------------------------------------------------------
BEGIN;

with target as (
  select q.id,
         q.item_name,
         coalesce(l.origin,'')   as origin,
         coalesce(l.supplier,'') as supplier,
         coalesce((coalesce(q.occurred_at,q.created_at) at time zone 'Asia/Tokyo')::date,l.received_date,current_date) as ref_date,
         coalesce(
           nullif(q.weight,0),
           case when q.before_weight is not null and q.after_weight is not null and abs(q.before_weight-q.after_weight)>0
                then abs(q.before_weight-q.after_weight) end,
           case when public.seika_parse_kg_v1162(l.pack_weight)>0 and q.qty>0
                then round(public.seika_parse_kg_v1162(l.pack_weight)*q.qty,3) end
         ) as w
  from public.qr_lot_movements q
  join public.qr_lots l on l.id=q.lot_id
  where q.movement_type='廃棄'
    and q.cancelled_at is null
    and q.reversed_operation_id is null
    and not public.seika_v1144_qr_operation_cancelled(q.operation_id)
    and coalesce(q.price_match_type,'') <> '手動修正'
),
calc as (
  select t.*, public.resolve_trimming_purchase_price_v1117(t.item_name,t.origin,t.supplier,t.ref_date) as p
  from target t
  where t.w is not null and t.w > 0
)
update public.qr_lot_movements m
   set purchase_price_yen_per_kg = (c.p->>'price_yen_per_kg')::numeric,
       waste_amount_yen          = round((c.p->>'price_yen_per_kg')::numeric * c.w, 2),
       price_match_type          = c.p->>'match_type',
       price_match_reason        = c.p->>'match_reason',
       price_source_supplier     = nullif(c.p->>'source_supplier',''),
       price_average_count       = coalesce((c.p->>'average_count')::integer,0),
       price_reference_date      = c.ref_date,
       price_calculated_at       = now()
  from calc c
 where m.id = c.id
   and (c.p->>'found')::boolean;

COMMIT;

-- ------------------------------------------------------------
-- 確認：採用区分の内訳（市場価格が増えていればOK）
-- ------------------------------------------------------------
SELECT price_match_type, count(*)
FROM public.qr_lot_movements
WHERE movement_type='廃棄' AND cancelled_at IS NULL
GROUP BY 1 ORDER BY 2 DESC;
