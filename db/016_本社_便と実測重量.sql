-- 016_本社_便と実測重量.sql（v1.199-c50）
-- 目的：
--   ① 石岡から本社へ出庫したときの「便（配送便・原料便・市場便など）」「当日便／翌日便」
--      「発注分（当日分／翌日分先送り＝画面では当日発注分／翌日発注分）」「出庫日」を
--      本社の入荷待ち原料（hq_lots_v1400）に残す。翌日便なら本社入荷日（予定）を出庫日の翌日にする。
--   ② 大型容器の実測合計kgと基数を入れたら、本社の入荷待ち原料の数量・基数・1基あたりkgを実測に合わせる。
--      石岡のQR在庫は、今までどおり出庫した数で減らす（このSQLでは石岡の在庫は変えません）。
-- 前提：本社 第1段階（hq_*_v1400）を実行済みであること。
-- 何度実行しても同じ結果になります。既存の原料・履歴の数量は変更しません。
begin;

-- 1) 本社の原料に列を追加
alter table public.hq_lots_v1400
  add column if not exists shipped_date date,
  add column if not exists order_timing text,
  add column if not exists ship_run text,
  add column if not exists ship_run_time text,
  add column if not exists ship_day text,
  add column if not exists measured_total_kg numeric,
  add column if not exists measured_count numeric;

-- 2) 石岡の出庫から本社の入荷待ちを作る処理（便・発注分・出庫日を追加）
create or replace function public.hq_capture_ishioka_transfer_v1400()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare l public.qr_lots%rowtype; v_unit text; v_qty numeric; v_per numeric;
  v_ship jsonb; v_day text; v_shipped date; v_timing text;
begin
 begin
  if tg_op = 'INSERT' and new.reversed_operation_id is not null then
    update public.hq_lots_v1400 h set status = '取消', updated_at = now()
    from public.qr_lot_movements m
    where m.operation_id = new.reversed_operation_id and h.source_movement_id = m.id and h.status = '入荷待ち';
    update public.hq_lots_v1400 h set memo = concat_ws(' / ', h.memo, '石岡で出庫が取り消されました（本社は確定済み）'), updated_at = now()
    from public.qr_lot_movements m
    where m.operation_id = new.reversed_operation_id and h.source_movement_id = m.id and h.status in ('在庫あり','在庫なし')
      and coalesce(h.memo,'') not like '%石岡で出庫が取り消されました%';
    return new;
  end if;
  if tg_op = 'INSERT' then
    if new.movement_type <> '出庫' or btrim(coalesce(new.destination,'')) <> '本社' or new.cancelled_at is not null then
      return new;
    end if;
    select * into l from public.qr_lots where id = new.lot_id;
    v_unit := public.hq_unit_for_v1400(coalesce(new.container_type, l.container_type));
    v_per := case when coalesce(l.total_weight,0) > 0 and coalesce(l.received_qty,0) > 0 then round(l.total_weight / l.received_qty, 1) end;
    v_qty := case when v_unit = 'kg' then coalesce(case when v_per is not null then round(new.qty * v_per, 1) end, nullif(new.weight,0), new.qty) else new.qty end;
    v_ship := case when jsonb_typeof(new.operation_meta->'hqShip') = 'object' then new.operation_meta->'hqShip' else '{}'::jsonb end;
    v_day := nullif(btrim(coalesce(v_ship->>'day','')), '');
    v_shipped := (new.occurred_at at time zone 'Asia/Tokyo')::date;
    v_timing := substring(coalesce(new.memo,'') from '^(当日分|翌日分先送り)');
    insert into public.hq_lots_v1400(lot_no, qr_key, source_kind, source_movement_id, source_lot_id, source_lot_no,
      ishioka_received_date, item_name, origin, supplier, cooperative_name, container_type, pack_weight, unit,
      planned_qty, planned_count, unit_weight_kg, planned_date, status, created_by_name,
      shipped_date, order_timing, ship_run, ship_run_time, ship_day)
    values (public.hq_new_lot_no_v1400(), 'HQ-' || replace(gen_random_uuid()::text,'-',''), '石岡から', new.id, new.lot_id,
      coalesce(new.lot_no, l.lot_no), l.received_date, new.item_name, coalesce(new.origin, l.origin),
      coalesce(new.supplier, l.supplier), coalesce(new.cooperative_name, l.cooperative_name),
      coalesce(new.container_type, l.container_type), l.pack_weight, v_unit, coalesce(v_qty,0),
      new.qty, case when v_unit = 'kg' then v_per end,
      v_shipped + case when v_day = '翌日便' then 1 else 0 end, '入荷待ち', new.user_name,
      v_shipped, v_timing, nullif(btrim(coalesce(v_ship->>'run','')), ''), nullif(btrim(coalesce(v_ship->>'time','')), ''), v_day)
    on conflict (source_movement_id) do nothing;
  elsif tg_op = 'UPDATE' then
    if new.cancelled_at is not null and old.cancelled_at is null then
      update public.hq_lots_v1400 set status = '取消', updated_at = now()
      where source_movement_id = new.id and status = '入荷待ち';
    end if;
  end if;
 exception when others then
  raise warning '本社の入荷待ちを作れませんでした（石岡の出庫はそのまま保存します）：%', sqlerrm;
 end;
  return new;
end $function$;

-- 3) 大型容器の実測合計kgと基数を、本社の入荷待ち原料に反映する
create or replace function public.hq_set_measured_v1420(p_lot_id uuid, p_total_kg numeric, p_count numeric)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v public.profiles;
begin
  v := public.hq_actor_v1400(array['admin','worker','hq_worker','hq_receiver']);
  if p_total_kg is null or p_total_kg <= 0 then raise exception '実測合計kgを入れてください'; end if;
  if p_count is null or p_count < 1 or p_count <> trunc(p_count) then raise exception '基数を入れてください'; end if;
  update public.hq_lots_v1400
     set planned_qty = round(p_total_kg, 1), planned_count = p_count,
         unit_weight_kg = round(p_total_kg / p_count, 1),
         measured_total_kg = round(p_total_kg, 1), measured_count = p_count, updated_at = now()
   where id = p_lot_id and status = '入荷待ち' and unit = 'kg';
  if not found then raise exception '入荷待ちの大型容器の原料が見つかりません'; end if;
  return jsonb_build_object('ok', true, 'per', round(p_total_kg / p_count, 1));
end $function$;

revoke all on function public.hq_set_measured_v1420(uuid, numeric, numeric) from public, anon;
grant execute on function public.hq_set_measured_v1420(uuid, numeric, numeric) to authenticated, service_role;

commit;
notify pgrst, 'reload schema';

-- 成功の確かめ方（実行後に別で実行）：
-- select column_name from information_schema.columns
--  where table_schema='public' and table_name='hq_lots_v1400'
--    and column_name in ('shipped_date','order_timing','ship_run','ship_run_time','ship_day','measured_total_kg','measured_count');
-- → 7行出れば成功
-- select proname from pg_proc where proname = 'hq_set_measured_v1420';
-- → 1行出れば成功
