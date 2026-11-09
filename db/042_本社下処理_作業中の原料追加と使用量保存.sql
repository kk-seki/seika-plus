/*
042_本社下処理_作業中の原料追加と使用量保存.sql（v1.199-c112）

前提：019・023を実行済みであること。
下処理の作業中だけ、同じ原料品目の在庫ロットを追加し、ロット別の使用数を保存できます。
在庫はここでは減らしません。既存の「下処理の確定」で、保存した使用数だけ在庫を減らします。
原料の使用期限の画面上の確認・記録は、既存の hqLimitGuard / hq_limit_check_v1600 をそのまま使います。
*/
begin;

create or replace function public.hq_work_add_material_v1199c112(p_work_id uuid, p_lot_id uuid)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare
  v public.profiles;
  w public.hq_works_v1500%rowtype;
  l public.hq_lots_v1400%rowtype;
  mt public.hq_work_materials_v1500%rowtype;
begin
  v := public.hq_actor_v1400(array['admin','hq_worker','hq_prep']);

  select * into w from public.hq_works_v1500 where id = p_work_id for update;
  if not found then raise exception '下処理が見つかりません'; end if;
  if w.kind <> '下処理' then raise exception '下処理だけに原料を追加できます'; end if;
  if w.status <> '作業中' then raise exception '原料は作業中だけ追加できます'; end if;
  if w.confirm_status <> '未確定' then raise exception '確定済みまたは取消済みの下処理には原料を追加できません'; end if;

  select * into l from public.hq_lots_v1400 where id = p_lot_id for update;
  if not found then raise exception '原料が見つかりません'; end if;
  if l.item_name <> w.raw_item_name then
    raise exception '原料 %（%）は、この下処理の原料（%）と違います', l.lot_no, l.item_name, w.raw_item_name;
  end if;
  if l.status <> '在庫あり' or coalesce(l.current_qty, 0) <= 0 then
    raise exception '原料 % は在庫ありで、残数があるロットだけ追加できます', l.lot_no;
  end if;

  select * into mt from public.hq_work_materials_v1500
  where work_id = w.id and lot_id = l.id;
  if found then
    return jsonb_build_object('ok', true, 'already', true, 'material_id', mt.id);
  end if;

  insert into public.hq_work_materials_v1500(work_id, lot_id, lot_no, item_name, unit, pack_kg)
  values (w.id, l.id, l.lot_no, l.item_name, l.unit,
    case when l.unit = 'kg' then null else public.hq_pack_kg_v1500(l.pack_weight) end)
  returning * into mt;

  update public.hq_works_v1500
  set history = history || jsonb_build_array(jsonb_build_object(
        'at', now(), 'by', v.display_name, 'action', '作業中に原料を追加', 'lot_id', l.id)),
      updated_at = now()
  where id = w.id;

  return jsonb_build_object('ok', true, 'material_id', mt.id);
end $$;

create or replace function public.hq_work_save_material_qty_v1199c112(p_work_id uuid, p_material_id uuid, p_qty numeric)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare
  v public.profiles;
  w public.hq_works_v1500%rowtype;
  mt public.hq_work_materials_v1500%rowtype;
begin
  v := public.hq_actor_v1400(array['admin','hq_worker','hq_prep']);
  if p_qty is null or p_qty < 0 or p_qty::text in ('NaN', 'Infinity', '-Infinity') then
    raise exception '使用原料の数は0以上の数で入れてください';
  end if;

  select * into w from public.hq_works_v1500 where id = p_work_id for update;
  if not found then raise exception '下処理が見つかりません'; end if;
  if w.kind <> '下処理' then raise exception '下処理だけに使用原料の数を保存できます'; end if;
  if w.status <> '作業中' then raise exception '使用原料の数は作業中だけ保存できます'; end if;
  if w.confirm_status <> '未確定' then raise exception '確定済みまたは取消済みの下処理には保存できません'; end if;

  select * into mt from public.hq_work_materials_v1500
  where id = p_material_id and work_id = w.id for update;
  if not found then raise exception 'この下処理の使用原料が見つかりません'; end if;

  update public.hq_work_materials_v1500 set qty = p_qty where id = mt.id;
  update public.hq_works_v1500
  set history = history || jsonb_build_array(jsonb_build_object(
        'at', now(), 'by', v.display_name, 'action', '作業中に原料使用数を保存',
        'lot_id', mt.lot_id, 'material_id', mt.id, 'qty', p_qty)),
      updated_at = now()
  where id = w.id;

  return jsonb_build_object('ok', true, 'material_id', mt.id, 'qty', p_qty);
end $$;

do $$
begin
  revoke all on function public.hq_work_add_material_v1199c112(uuid,uuid) from public, anon;
  revoke all on function public.hq_work_save_material_qty_v1199c112(uuid,uuid,numeric) from public, anon;
  grant execute on function public.hq_work_add_material_v1199c112(uuid,uuid) to authenticated, service_role;
  grant execute on function public.hq_work_save_material_qty_v1199c112(uuid,uuid,numeric) to authenticated, service_role;
end $$;

commit;
notify pgrst, 'reload schema';

/* 成功の確かめ方：下の2行がOKなら成功です。 */
select '作業中の原料追加' as 確認,
  case when to_regprocedure('public.hq_work_add_material_v1199c112(uuid,uuid)') is not null then 'OK' else 'NG' end as 結果
union all
select '作業中の使用数保存',
  case when to_regprocedure('public.hq_work_save_material_qty_v1199c112(uuid,uuid,numeric)') is not null then 'OK' else 'NG' end;
