-- 004 事務員の廃棄保存・削除の型修正
-- 目的：waste_records.id は text、seika_uuid_v188() は uuid を返すため、比較で「text = uuid」エラー（42883）になっていた。
--       事務員の廃棄が履歴テーブルへ保存されない／削除できない原因。管理者・社員用の保存（save_history_records_v188）と同じく ::text で比較する。
-- 影響：2つの関数の比較部分だけを変更。引数・戻り値・権限は変えない。
begin;

CREATE OR REPLACE FUNCTION public.save_clerk_waste_history_v188(p_waste_records jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_profile public.profiles%rowtype;
  x jsonb;
  v_existing public.waste_records%rowtype;
  v_clean_data jsonb;
begin
  select * into v_profile
  from public.profiles
  where id = auth.uid() and active = true;

  if not found then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;
  if v_profile.role <> 'clerk' then
    raise exception '事務員専用の保存処理です' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_waste_records, '[]'::jsonb)) <> 'array' then
    raise exception '廃棄履歴は配列で指定してください' using errcode = '22023';
  end if;

  for x in select value from jsonb_array_elements(coalesce(p_waste_records, '[]'::jsonb)) loop
    if nullif(x->>'id', '') is null then
      raise exception '廃棄履歴IDが必要です' using errcode = '22023';
    end if;
    if coalesce((x->>'qty')::numeric, 0) < 0 or coalesce((x->>'unitPrice')::numeric, 0) < 0 then
      raise exception '数量または単価が正しくありません' using errcode = '22023';
    end if;

    select * into v_existing
    from public.waste_records
    where id = public.seika_uuid_v188(x->>'id')::text
    for update;

    if found then
      v_clean_data := coalesce(v_existing.data, '{}'::jsonb)
        || (x - 'user' - 'userId' - 'createdAt')
        || jsonb_build_object(
          'user', coalesce(v_existing.data->>'user', v_existing.user_name),
          'userId', coalesce(v_existing.data->>'userId', v_existing.user_id),
          'createdAt', coalesce(v_existing.data->>'createdAt', v_existing.created_at::text),
          'updatedAt', now()
        );

      update public.waste_records wr
      set waste_date = coalesce((x->>'date')::date, wr.waste_date),
          item_name = coalesce(nullif(x->>'itemName', ''), wr.item_name),
          qty = coalesce((x->>'qty')::numeric, wr.qty),
          unit_price = coalesce((x->>'unitPrice')::numeric, wr.unit_price),
          amount = coalesce((x->>'amount')::numeric, wr.amount),
          updated_at = now(),
          data = v_clean_data
      where wr.id = public.seika_uuid_v188(x->>'id')::text;
    else
      v_clean_data := (x - 'user' - 'userId')
        || jsonb_build_object('user', v_profile.display_name, 'userId', v_profile.legacy_user_id);

      insert into public.waste_records(
        id, waste_date, item_name, qty, unit_price, amount,
        user_name, user_id, created_at, updated_at, data
      ) values (
        public.seika_uuid_v188(x->>'id')::text,
        coalesce((x->>'date')::date, current_date),
        x->>'itemName',
        coalesce((x->>'qty')::numeric, 0),
        coalesce((x->>'unitPrice')::numeric, 0),
        coalesce((x->>'amount')::numeric, 0),
        v_profile.display_name,
        v_profile.legacy_user_id,
        coalesce((x->>'createdAt')::timestamptz, now()),
        now(),
        v_clean_data
      );
    end if;
  end loop;

  return jsonb_build_object('ok', true);
end
$function$
;;

CREATE OR REPLACE FUNCTION public.delete_clerk_waste_v188(p_id text, p_expected_version bigint, p_waste_id text, p_operation_id text DEFAULT NULL::text, p_device_meta jsonb DEFAULT '{}'::jsonb, p_operation_meta jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_profile public.profiles%rowtype;
  v_state public.app_state%rowtype;
  v_next_data jsonb;
  v_next_version bigint;
  v_operation_uuid uuid;
begin
  v_operation_uuid := case when nullif(trim(coalesce(p_operation_id,'')),'') is null then null else public.seika_uuid_v188(p_operation_id) end;
  select * into v_profile from public.profiles where id = auth.uid() and active = true;
  if not found then raise exception 'AUTH_REQUIRED' using errcode = '42501'; end if;
  if v_profile.role <> 'clerk' then raise exception '事務員専用の削除処理です' using errcode = '42501'; end if;
  if p_id <> 'ishioka_inventory_production_v2' or nullif(trim(coalesce(p_waste_id, '')), '') is null then
    raise exception '削除対象が正しくありません' using errcode = '22023';
  end if;

  select * into v_state from public.app_state where id = p_id for update;
  if not found then return jsonb_build_object('ok', false, 'message', '保存先が見つかりません'); end if;
  if v_state.version is distinct from p_expected_version then
    return jsonb_build_object('ok', false, 'conflict', true, 'message', '他端末の更新があります', 'version', v_state.version);
  end if;

  v_next_data := jsonb_set(
    coalesce(v_state.data, '{}'::jsonb),
    '{wasteRecords}',
    coalesce((select jsonb_agg(x) from jsonb_array_elements(coalesce(v_state.data->'wasteRecords','[]'::jsonb)) x where x->>'id' <> p_waste_id), '[]'::jsonb),
    true
  );
  v_next_version := v_state.version + 1;

  delete from public.waste_records where id = public.seika_uuid_v188(p_waste_id)::text;
  update public.app_state
  set data = v_next_data,
      version = v_next_version,
      updated_at = now(),
      last_operation_id = v_operation_uuid,
      last_device_meta = coalesce(p_device_meta, '{}'::jsonb),
      last_operation_meta = coalesce(p_operation_meta, '{}'::jsonb)
  where id = p_id;

  return jsonb_build_object('ok', true, 'version', v_next_version, 'updated_at', now());
end
$function$
;;

commit;

-- 確認：2行とも「修正済み」が true なら成功
select p.proname as 関数名,
       pg_get_functiondef(p.oid) like '%seika_uuid_v188(%)::text%' as 修正済み
from pg_proc p
where p.proname in ('save_clerk_waste_history_v188','delete_clerk_waste_v188');
