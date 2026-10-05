-- 003 廃棄記録だけを取り消す（在庫数は変えない）
-- 目的：廃棄のあとに実数調整などで在庫を直したロットでも、誤った廃棄を廃棄一覧・週次レポートから外せるようにする。
-- 動き：対象の廃棄に「取消済み」の印を付け、履歴に「取消」を1行残す。ロットの在庫数・重量は変更しない。
-- 条件：管理者のみ。区分が「廃棄」で、まだ取り消されていないもの。
-- 前提：002（区分に「取消」を追加）を実行済みであること。
begin;

create or replace function public.cancel_qr_waste_record_only_v1232(
  p_cancel_operation_id uuid,
  p_original_operation_id uuid,
  p_user_id text default null,
  p_user_name text default null,
  p_device_meta jsonb default '{}'::jsonb,
  p_operation_meta jsonb default '{}'::jsonb,
  p_memo text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_original public.qr_lot_movements%rowtype;
  v_cancel public.qr_lot_movements%rowtype;
  v_lot public.qr_lots%rowtype;
begin
  if coalesce(public.current_app_role(), '') <> 'admin' then
    return jsonb_build_object('ok', false, 'forbidden', true, 'message', '廃棄記録だけの取消は管理者のみです');
  end if;
  if p_cancel_operation_id is null or p_original_operation_id is null
     or p_cancel_operation_id = p_original_operation_id then
    raise exception '取消operation_idと元operation_idを正しく指定してください';
  end if;

  select * into v_cancel from public.qr_lot_movements where operation_id = p_cancel_operation_id;
  if found then
    return jsonb_build_object('ok', true, 'idempotent', true, 'movement_id', v_cancel.id, 'lot_id', v_cancel.lot_id);
  end if;

  select * into v_original from public.qr_lot_movements
  where operation_id = p_original_operation_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'not_found', true, 'message', '取消対象の廃棄が見つかりません');
  end if;
  if v_original.movement_type <> '廃棄' then
    return jsonb_build_object('ok', false, 'message', '廃棄以外の操作には使えません');
  end if;
  if v_original.reversed_operation_id is not null or v_original.cancelled_at is not null then
    return jsonb_build_object('ok', false, 'already_cancelled', true, 'message', 'この廃棄はすでに取り消されています');
  end if;

  select * into v_lot from public.qr_lots where id = v_original.lot_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'not_found', true, 'message', '対象QRロットが見つかりません');
  end if;

  insert into public.qr_lot_movements (
    movement_type, lot_id, lot_no, qr_key, item_id, item_name, origin, supplier, cooperative_name,
    qty, unit, destination, storage_location, user_id, user_name, memo,
    container_type, lot_manage_type, weight, before_quantity, after_quantity,
    before_weight, after_weight, weight_status, reason,
    operation_id, reversed_operation_id, device_meta, operation_meta
  ) values (
    '取消', v_original.lot_id, v_original.lot_no, v_original.qr_key, v_original.item_id, v_original.item_name,
    v_original.origin, v_original.supplier, v_lot.cooperative_name,
    0, v_original.unit, v_original.destination, v_lot.storage_location, p_user_id, p_user_name,
    coalesce(p_memo, '廃棄記録のみ取消（在庫数は変更なし）'),
    v_original.container_type, v_original.lot_manage_type, null,
    v_lot.current_qty, v_lot.current_qty, v_lot.current_weight, v_lot.current_weight, v_original.weight_status,
    '廃棄記録のみ取消（在庫数は変更なし）',
    p_cancel_operation_id, p_original_operation_id,
    coalesce(p_device_meta, '{}'::jsonb), coalesce(p_operation_meta, '{}'::jsonb) || jsonb_build_object('recordOnly', true)
  ) returning * into v_cancel;

  update public.qr_lot_movements
  set reversed_operation_id = p_cancel_operation_id,
      cancelled_at = now(),
      cancelled_by = coalesce(p_user_id, p_user_name)
  where id = v_original.id;

  return jsonb_build_object('ok', true, 'idempotent', false, 'movement_id', v_cancel.id,
                            'lot_id', v_lot.id, 'after_quantity', v_lot.current_qty);
end;
$function$;

revoke all on function public.cancel_qr_waste_record_only_v1232(uuid, uuid, text, text, jsonb, jsonb, text) from public, anon;
grant execute on function public.cancel_qr_waste_record_only_v1232(uuid, uuid, text, text, jsonb, jsonb, text) to authenticated, service_role;

commit;

-- 確認：1行表示されれば成功
select p.proname as 関数名, has_function_privilege('anon', p.oid, 'execute') as 未ログインで実行可
from pg_proc p where p.proname = 'cancel_qr_waste_record_only_v1232';
