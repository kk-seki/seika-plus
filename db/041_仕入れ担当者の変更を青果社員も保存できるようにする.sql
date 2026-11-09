-- v1.199-c110 仕入れ担当者の変更を青果社員も保存できるようにする
-- 目的: 品目設定の「仕入れ担当者の変更」を管理者・青果社員の両方が使えるようにする。
--       これまで青果社員は buyerAssignments（品目ごとの仕入れ担当者）を保存できず、変更が反映されなかった。
-- 内容: 保存用の関数2つ（update_app_state_if_version_v187 / update_app_state_partial_v188）で、
--       青果社員(worker)が保存できる項目に buyerAssignments を1つ追加するだけ。他の権限・処理は変更しない。
-- 実行順: このSQLを先に実行し、確認SELECTで2行とも ok = true を確認してからPRをmainへマージする。
-- 確認方法（実行後、下の SELECT を実行して、2行とも ok = true になれば成功）:
--   select p.proname,
--          (regexp_match(pg_get_functiondef(p.oid), 'when ''worker'' then array\[([^\]]*)\]'))[1] like '%buyerAssignments%' as ok
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--   where n.nspname = 'public' and p.proname in ('update_app_state_if_version_v187','update_app_state_partial_v188');

BEGIN;

CREATE OR REPLACE FUNCTION public.update_app_state_if_version_v187(p_id text, p_expected_version bigint, p_data jsonb, p_operation_id text DEFAULT NULL::text, p_device_meta jsonb DEFAULT '{}'::jsonb, p_operation_meta jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  current_row public.app_state%rowtype;
  app_role text;
  allowed_keys text[];
  changed_key text;
  next_data jsonb;
  next_version bigint;
  operation_uuid uuid;
begin
  if p_operation_id is not null then
    begin
      operation_uuid := p_operation_id::uuid;
    exception when invalid_text_representation then
      operation_uuid := (substr(md5(p_operation_id),1,8)||'-'||substr(md5(p_operation_id),9,4)||'-'||substr(md5(p_operation_id),13,4)||'-'||substr(md5(p_operation_id),17,4)||'-'||substr(md5(p_operation_id),21,12))::uuid;
    end;
  end if;

  app_role := public.current_app_role();
  if app_role is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;

  select * into current_row
  from public.app_state
  where id = p_id
  for update;

  if not found then
    return jsonb_build_object('ok', false, 'code', 'NOT_FOUND');
  end if;

  if current_row.version is distinct from p_expected_version then
    return jsonb_build_object(
      'ok', false,
      'code', 'VERSION_CONFLICT',
      'version', current_row.version,
      'updated_at', current_row.updated_at
    );
  end if;

  if p_operation_id is not null and current_row.last_operation_id = operation_uuid then
    return jsonb_build_object('ok', true, 'duplicate', true, 'version', current_row.version);
  end if;

  allowed_keys := case app_role
    when 'admin' then array[
      'settings','records','movements','notifications','items','purchaseMemos','purchaseMemoMeta','pins',
      'buyerAssignments','monthlyArchives','optimalStockChangeLogs','historyCleanups','duplicateDeleteLogs',
      'specialItems','specialRecords','wasteRecords','itemDetails','meshContainers','qrManagedItems',
      'qrManagedPresetVersion','purchaseStaffByItem','qrSuppliers','qrCooperatives','operationLogs','inventoryCounts'
    ]::text[]
    when 'worker' then array[
      'records','movements','notifications','items','buyerAssignments','purchaseMemos','purchaseMemoMeta','specialItems',
      'specialRecords','wasteRecords','itemDetails','meshContainers','qrManagedItems','qrManagedPresetVersion',
      'purchaseStaffByItem','qrSuppliers','qrCooperatives','operationLogs','inventoryCounts'
    ]::text[]
    when 'buyer' then array['settings','purchaseMemos','purchaseMemoMeta','operationLogs']::text[]
    when 'sales' then array['wasteRecords','operationLogs']::text[]
    when 'clerk' then array['wasteRecords','operationLogs']::text[]
    else array[]::text[]
  end;

  -- users / pins はクライアントから送信しないため、権限差分判定より先にサーバー値を復元する。
  next_data := coalesce(p_data, '{}'::jsonb);
  next_data := jsonb_set(next_data, '{users}', coalesce(current_row.data->'users', '[]'::jsonb), true);
  next_data := jsonb_set(next_data, '{pins}', coalesce(current_row.data->'pins', '{}'::jsonb), true);

  select k into changed_key
  from (
    select key as k from jsonb_object_keys(coalesce(current_row.data, '{}'::jsonb)) key
    union
    select key as k from jsonb_object_keys(next_data) key
  ) keys
  where not (k = any(allowed_keys))
    and current_row.data->k is distinct from next_data->k
  limit 1;

  if changed_key is not null then
    return jsonb_build_object('ok', false, 'code', 'FORBIDDEN_FIELD', 'field', changed_key);
  end if;

  next_version := current_row.version + 1;

  update public.app_state
  set data = next_data,
      version = next_version,
      updated_at = now(),
      last_operation_id = operation_uuid,
      last_device_meta = coalesce(p_device_meta, '{}'::jsonb),
      last_operation_meta = coalesce(p_operation_meta, '{}'::jsonb)
  where id = p_id;

  return jsonb_build_object('ok', true, 'version', next_version, 'updated_at', now());
end
$function$
;

CREATE OR REPLACE FUNCTION public.update_app_state_partial_v188(p_id text, p_expected_version bigint, p_changes jsonb, p_operation_id text DEFAULT NULL::text, p_device_meta jsonb DEFAULT '{}'::jsonb, p_operation_meta jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_profile public.profiles%rowtype;
  v_state public.app_state%rowtype;
  v_allowed text[];
  v_key text;
  v_ignored text[] := array[]::text[];
  v_applied integer := 0;
  v_next jsonb;
  v_next_version bigint;
  v_operation_uuid uuid;
begin
  v_operation_uuid := case when nullif(trim(coalesce(p_operation_id,'')),'') is null then null else public.seika_uuid_v188(p_operation_id) end;
  select * into v_profile from public.profiles where id=auth.uid() and active=true;
  if not found then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
  if p_id <> 'ishioka_inventory_production_v2' then raise exception '保存先が正しくありません' using errcode='22023'; end if;
  if jsonb_typeof(coalesce(p_changes,'{}'::jsonb)) <> 'object' then raise exception '保存データが正しくありません' using errcode='22023'; end if;

  v_allowed := case v_profile.role
    when 'admin' then array['settings','records','movements','notifications','items','purchaseMemos','purchaseMemoMeta','buyerAssignments','monthlyArchives','optimalStockChangeLogs','historyCleanups','duplicateDeleteLogs','specialItems','specialRecords','wasteRecords','itemDetails','meshContainers','qrManagedItems','qrManagedPresetVersion','purchaseStaffByItem','qrSuppliers','qrCooperatives','operationLogs','inventoryCounts']::text[]
    when 'worker' then array['records','movements','notifications','items','buyerAssignments','purchaseMemos','purchaseMemoMeta','specialItems','specialRecords','wasteRecords','itemDetails','meshContainers','qrManagedItems','qrManagedPresetVersion','purchaseStaffByItem','qrSuppliers','qrCooperatives','operationLogs','inventoryCounts']::text[]
    when 'buyer' then array['settings','purchaseMemos','purchaseMemoMeta','operationLogs']::text[]
    when 'sales' then array['operationLogs']::text[]
    else array[]::text[]
  end;
  if coalesce(array_length(v_allowed,1),0)=0 then raise exception 'この権限では保存できません' using errcode='42501'; end if;
  for v_key in select jsonb_object_keys(p_changes) loop
    if not (v_key=any(v_allowed)) then
      v_ignored := array_append(v_ignored,v_key);
    end if;
  end loop;

  select * into v_state from public.app_state where id=p_id for update;
  if not found then return jsonb_build_object('ok',false,'message','保存先が見つかりません'); end if;
  if v_state.version is distinct from p_expected_version then
    return jsonb_build_object('ok',false,'conflict',true,'message','他端末の更新があります','version',v_state.version);
  end if;
  if v_operation_uuid is not null and v_state.last_operation_id=v_operation_uuid then
    return jsonb_build_object('ok',true,'duplicate',true,'version',v_state.version);
  end if;

  v_next:=coalesce(v_state.data,'{}'::jsonb);
  for v_key in select jsonb_object_keys(p_changes) loop
    if v_key=any(v_allowed) then
      v_next:=jsonb_set(v_next,array[v_key],p_changes->v_key,true);
      v_applied:=v_applied+1;
    end if;
  end loop;
  if v_applied=0 then
    return jsonb_build_object('ok',true,'noop',true,'version',v_state.version,'ignored_fields',to_jsonb(v_ignored));
  end if;
  v_next_version:=v_state.version+1;
  update public.app_state set data=v_next,version=v_next_version,updated_at=now(),last_operation_id=v_operation_uuid,last_device_meta=coalesce(p_device_meta,'{}'::jsonb),last_operation_meta=coalesce(p_operation_meta,'{}'::jsonb) where id=p_id;
  return jsonb_build_object('ok',true,'version',v_next_version,'updated_at',now(),'applied_count',v_applied,'ignored_fields',to_jsonb(v_ignored));
end
$function$
;

COMMIT;
