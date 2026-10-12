-- SEIKA＋ v1.192
-- 出庫履歴が開けない不具合の修正
--
-- 原因: 元の定義では with base/filtered/resolved ... を宣言した直後の
--       「select count(*) into v_count from filtered;」だけに with が掛かっており、
--       続く集計用 select（from resolved）と明細用 select（from filtered）からは
--       これらの一時表が見えないため、実行時に
--       relation "resolved" does not exist で失敗していた。
-- 対応: 3本に分かれていた select を 1 本の with 文にまとめ、
--       同じ戻り値（ok / work_date / total_count / offset / limit /
--       rows / summary_rows / destinations）をそのまま返す。
--       絞り込み条件・kg 換算・並び順など既存の挙動は変更していない。

CREATE OR REPLACE FUNCTION public.list_qr_outbound_history_v1144(
  p_destination text,
  p_work_date date,
  p_include_cancelled boolean DEFAULT false,
  p_limit integer DEFAULT 500,
  p_offset integer DEFAULT 0
)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_profile public.profiles%rowtype;
  v_limit int := greatest(1, least(coalesce(p_limit, 500), 500));
  v_offset int := greatest(coalesce(p_offset, 0), 0);
  v_date date := coalesce(p_work_date, (now() at time zone 'Asia/Tokyo')::date);
  v_result jsonb;
begin
  v_profile := public.seika_v1144_require_active_profile();

  with base as (
    select
      q.*,
      coalesce(q.occurred_at, q.created_at) as event_at,
      (q.cancelled_at is not null
        or q.reversed_operation_id is not null
        or public.seika_v1144_qr_operation_cancelled(q.operation_id)) as is_cancelled,
      coalesce(q.container_type, l.container_type) as resolved_container_type,
      l.pack_weight as resolved_pack_weight,
      coalesce(q.lot_no, l.lot_no) as resolved_lot_no,
      coalesce(q.qr_key, l.qr_key) as resolved_qr_key
    from public.qr_lot_movements q
    left join lateral (
      select
        l1.container_type,
        l1.pack_weight,
        l1.lot_no,
        l1.qr_key
      from public.qr_lots l1
      where (
        q.lot_id is not null
        and l1.id::text = q.lot_id::text
      ) or (
        q.lot_id is null
        and l1.qr_key = q.qr_key
      )
      order by l1.id::text
      limit 1
    ) l on true
    where q.movement_type = '出庫'
  ), filtered as (
    select * from base
    where (event_at at time zone 'Asia/Tokyo')::date = v_date
      and (nullif(btrim(coalesce(p_destination, '')), '') is null or destination = p_destination)
      and (p_include_cancelled or not is_cancelled)
  ), resolved as (
    select
      *,
      case
        when weight is not null then weight
        when resolved_container_type in ('網コンテナ', '鉄コンテナ', 'パレテーナ') then null
        when unit ~* '(^|\s)(kg|㎏|キロ)(\s|$)' then qty
        when nullif(regexp_replace(coalesce(resolved_pack_weight::text, ''), '[^0-9.]', '', 'g'), '') is not null
          then qty * nullif(regexp_replace(coalesce(resolved_pack_weight::text, ''), '[^0-9.]', '', 'g'), '')::numeric
        else null
      end as kg,
      resolved_container_type in ('網コンテナ', '鉄コンテナ', 'パレテーナ') as is_large
    from filtered
  ), counted as (
    select count(*)::bigint as total_count from filtered
  ), summary_src as (
    select
      item_name,
      unit,
      sum(qty) as qty,
      sum(kg) as weight_kg,
      count(*) filter (where kg is null and is_large) as unconfirmed_large_count,
      count(*) filter (where kg is null and not is_large) as unconvertible_normal_count
    from resolved
    group by item_name, unit
  ), summary_json as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'item_name', item_name,
      'unit', unit,
      'qty', qty,
      'weight_kg', weight_kg,
      'unconfirmed_large_count', unconfirmed_large_count,
      'unconvertible_normal_count', unconvertible_normal_count
    ) order by item_name, unit), '[]'::jsonb) as summary_rows
    from summary_src
  ), page as (
    select * from filtered
    order by event_at, id
    limit v_limit offset v_offset
  ), rows_json as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', id,
      'operation_id', operation_id,
      'occurred_at', event_at,
      'destination', destination,
      'item_name', item_name,
      'qty', qty,
      'unit', unit,
      'weight', weight,
      'lot_no', resolved_lot_no,
      'qr_key', resolved_qr_key,
      'container_type', resolved_container_type,
      'pack_weight', resolved_pack_weight,
      'user_name', user_name,
      'memo', memo,
      'is_cancelled', is_cancelled
    ) order by event_at, id), '[]'::jsonb) as rows
    from page
  ), dest_src as (
    select distinct destination
    from public.qr_lot_movements
    where movement_type = '出庫'
      and nullif(btrim(coalesce(destination, '')), '') is not null
  ), dest_json as (
    select coalesce(jsonb_agg(destination order by destination), '[]'::jsonb) as destinations
    from dest_src
  )
  select jsonb_build_object(
    'ok', true,
    'work_date', v_date,
    'total_count', counted.total_count,
    'offset', v_offset,
    'limit', v_limit,
    'rows', rows_json.rows,
    'summary_rows', summary_json.summary_rows,
    'destinations', dest_json.destinations
  )
  into v_result
  from counted, rows_json, summary_json, dest_json;

  return v_result;
end;
$function$;
