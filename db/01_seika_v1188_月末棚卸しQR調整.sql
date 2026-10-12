-- SEIKA＋ v1.188 月末棚卸しQR差異調整

create or replace function public.v188_apply_month_end_qr_adjustment(
  p_qr_key text,
  p_operation_id text,
  p_target_month text,
  p_as_of_date text,
  p_book_qty numeric,
  p_actual_qty numeric,
  p_reason text,
  p_memo text,
  p_session_id text,
  p_count_no text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_profile public.profiles%rowtype;
  v_lot public.qr_lots%rowtype;
  v_diff numeric;
  v_current_qty numeric;
  v_after_qty numeric;
  v_stored_after_qty numeric;
  v_movement_type text;
  v_occurred_at timestamptz;
  v_memo text;
  v_payload jsonb;
  v_cols text;
  v_has_current_weight boolean;
  v_is_large_container boolean;
  v_per_unit_weight numeric;
  v_current_weight numeric;
  v_after_weight numeric;
begin
  if pg_catalog.nullif(pg_catalog.btrim(p_qr_key), '') is null
     or pg_catalog.nullif(pg_catalog.btrim(p_operation_id), '') is null
     or pg_catalog.nullif(pg_catalog.btrim(p_target_month), '') is null
     or pg_catalog.nullif(pg_catalog.btrim(p_as_of_date), '') is null
     or p_book_qty is null
     or p_actual_qty is null
     or pg_catalog.nullif(pg_catalog.btrim(p_session_id), '') is null
     or pg_catalog.nullif(pg_catalog.btrim(p_count_no), '') is null
     or p_target_month !~ '^[0-9]{4}-[0-9]{2}$'
     or p_as_of_date !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
     or pg_catalog.left(p_as_of_date, 7) <> p_target_month then
    raise exception '月末棚卸しQR調整データが不正です' using errcode = '22023';
  end if;

  select * into v_profile from public.seika_inventory_count_profile_v123();
  if not found or v_profile.role not in ('admin', 'worker') then
    raise exception '棚卸しを操作できるのは管理者・青果社員のみです' using errcode = '42501';
  end if;

  if exists (
    select 1
      from public.qr_lot_movements
     where operation_id = p_operation_id
  ) then
    return pg_catalog.jsonb_build_object('ok', true, 'idempotent', true);
  end if;

  select * into v_lot
    from public.qr_lots
   where qr_key = p_qr_key
   for update;
  if not found then
    raise exception 'QRロットが見つかりません' using errcode = 'P0002';
  end if;

  v_diff := p_actual_qty - p_book_qty;
  if v_diff = 0 then
    return pg_catalog.jsonb_build_object('ok', true, 'skipped', true);
  end if;

  v_current_qty := pg_catalog.coalesce((pg_catalog.to_jsonb(v_lot)->>'current_qty')::numeric, 0);
  v_after_qty := v_current_qty + v_diff;
  v_stored_after_qty := pg_catalog.greatest(0::numeric, v_after_qty);
  v_movement_type := case when v_diff > 0 then '棚卸し調整増' else '棚卸し調整減' end;
  v_occurred_at := (p_as_of_date || ' 23:59:59')::timestamp at time zone 'Asia/Tokyo';
  v_memo := '対象月' || p_target_month || ' 月末棚卸し（基準日' || p_as_of_date || '）/ 棚卸し番号 ' || p_count_no
    || ' / 帳簿' || p_book_qty::text || '→実数' || p_actual_qty::text
    || case when pg_catalog.nullif(pg_catalog.btrim(p_memo), '') is null then '' else ' / ' || p_memo end;

  v_has_current_weight := exists (
    select 1
      from information_schema.columns
     where table_schema = 'public'
       and table_name = 'qr_lots'
       and column_name = 'current_weight'
  );
  v_is_large_container := pg_catalog.coalesce(pg_catalog.to_jsonb(v_lot)->>'container_type', '')
    in ('網コンテナ', '鉄コンテナ', 'パレテーナ');
  v_per_unit_weight := case
    when v_is_large_container
     and pg_catalog.nullif(pg_catalog.to_jsonb(v_lot)->>'total_weight', '') is not null
     and pg_catalog.coalesce(
           pg_catalog.nullif(pg_catalog.to_jsonb(v_lot)->>'received_qty', ''),
           pg_catalog.nullif(pg_catalog.to_jsonb(v_lot)->>'initial_quantity', '')
         ) is not null
     and pg_catalog.coalesce(
           pg_catalog.nullif(pg_catalog.to_jsonb(v_lot)->>'received_qty', ''),
           pg_catalog.nullif(pg_catalog.to_jsonb(v_lot)->>'initial_quantity', '')
         )::numeric > 0
    then (pg_catalog.to_jsonb(v_lot)->>'total_weight')::numeric
       / pg_catalog.coalesce(
           pg_catalog.nullif(pg_catalog.to_jsonb(v_lot)->>'received_qty', ''),
           pg_catalog.nullif(pg_catalog.to_jsonb(v_lot)->>'initial_quantity', '')
         )::numeric
    else null
  end;
  v_current_weight := case
    when v_has_current_weight then (pg_catalog.to_jsonb(v_lot)->>'current_weight')::numeric
    else null
  end;
  v_after_weight := case
    when v_has_current_weight and v_per_unit_weight is not null
    then pg_catalog.greatest(0::numeric, pg_catalog.coalesce(v_current_weight, 0) + v_diff * v_per_unit_weight)
    else null
  end;

  v_payload := pg_catalog.jsonb_build_object(
    'qr_key', p_qr_key,
    'lot_id', pg_catalog.to_jsonb(v_lot)->'id',
    'lot_no', pg_catalog.to_jsonb(v_lot)->>'lot_no',
    'item_name', pg_catalog.to_jsonb(v_lot)->>'item_name',
    'unit', pg_catalog.to_jsonb(v_lot)->>'unit',
    'movement_type', v_movement_type,
    'qty', pg_catalog.abs(v_diff),
    'quantity', pg_catalog.abs(v_diff),
    'before_quantity', v_current_qty,
    'after_quantity', v_after_qty,
    'weight', case when v_per_unit_weight is null then null else pg_catalog.abs(v_diff) * v_per_unit_weight end,
    'before_weight', v_current_weight,
    'after_weight', v_after_weight,
    'storage_location', pg_catalog.to_jsonb(v_lot)->>'storage_location',
    'origin', pg_catalog.to_jsonb(v_lot)->>'origin',
    'supplier', pg_catalog.to_jsonb(v_lot)->>'supplier',
    'cooperative_name', pg_catalog.to_jsonb(v_lot)->>'cooperative_name',
    'user_id', v_profile.id,
    'user_name', pg_catalog.coalesce(v_profile.display_name, ''),
    'reason', p_reason,
    'memo', v_memo,
    'operation_id', p_operation_id,
    'created_at', v_occurred_at,
    'occurred_at', v_occurred_at
  );

  select pg_catalog.string_agg(pg_catalog.quote_ident(column_name), ', ' order by ordinal_position)
    into v_cols
    from information_schema.columns
   where table_schema = 'public'
     and table_name = 'qr_lot_movements'
     and column_name = any (pg_catalog.array[
       'qr_key', 'lot_id', 'lot_no', 'item_name', 'unit', 'movement_type', 'qty', 'quantity',
       'before_quantity', 'after_quantity', 'weight', 'before_weight', 'after_weight',
       'storage_location', 'origin', 'supplier', 'cooperative_name',
       'user_id', 'user_name', 'reason', 'memo', 'operation_id', 'created_at', 'occurred_at'
     ]);
  if v_cols is null then
    raise exception 'QR在庫履歴の挿入可能列が見つかりません' using errcode = 'P0002';
  end if;

  execute pg_catalog.format(
    'insert into public.qr_lot_movements (%s) select %s from pg_catalog.jsonb_populate_record(null::public.qr_lot_movements, $1)',
    v_cols,
    v_cols
  ) using v_payload;

  if v_has_current_weight and v_per_unit_weight is not null then
    execute 'update public.qr_lots set current_qty = $1, current_weight = $2, updated_at = pg_catalog.now() where qr_key = $3'
      using v_stored_after_qty, v_after_weight, p_qr_key;
  else
    update public.qr_lots
       set current_qty = v_stored_after_qty,
           updated_at = pg_catalog.now()
     where qr_key = p_qr_key;
  end if;

  return pg_catalog.jsonb_build_object(
    'ok', true,
    'diff', v_diff,
    'after_qty', v_stored_after_qty,
    'movement_type', v_movement_type
  );
end;
$function$;

revoke all on function public.v188_apply_month_end_qr_adjustment(text, text, text, text, numeric, numeric, text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.v188_apply_month_end_qr_adjustment(text, text, text, text, numeric, numeric, text, text, text, text)
  to authenticated;
