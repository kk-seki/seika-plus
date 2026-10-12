-- ============================================================
-- SEIKA＋ 履歴保存RPCの型不一致を修正（SQLSTATE 42883）
--
--   43番の結果：
--     waste_records.id / inventory_records.id /
--     inventory_movements.id / record_id   … すべて text
--     seika_uuid_v188()                    … uuid を返す
--
--   このため id = seika_uuid_v188(...) が
--   「operator does not exist: text = uuid」で必ず失敗していた。
--   削除対象が空でも文自体が型検査で落ちるため、
--   admin / worker は履歴保存が毎回失敗していた。
--
--   対処：uuid を返す箇所をすべて ::text に揃える。
--   ロジックは一切変更していない。
-- ============================================================

create or replace function public.save_history_records_v188(
  p_records              jsonb   default '[]'::jsonb,
  p_waste_records        jsonb   default '[]'::jsonb,
  p_movements            jsonb   default '[]'::jsonb,
  p_delete_record_ids    text[]  default '{}'::text[],
  p_delete_waste_ids     text[]  default '{}'::text[],
  p_delete_movement_ids  text[]  default '{}'::text[])
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public'
as $function$
declare
  v_profile public.profiles%rowtype;
  x jsonb;
begin
  select * into v_profile from public.profiles where id=auth.uid() and active=true;
  if not found then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
  if v_profile.role not in ('admin','worker','sales') then raise exception '履歴保存権限がありません' using errcode='42501'; end if;
  if jsonb_typeof(p_records)<>'array' or jsonb_typeof(p_waste_records)<>'array' or jsonb_typeof(p_movements)<>'array' then raise exception '履歴は配列で指定してください' using errcode='22023'; end if;
  if v_profile.role='sales' and (jsonb_array_length(p_records)>0 or jsonb_array_length(p_movements)>0 or cardinality(p_delete_record_ids)>0 or cardinality(p_delete_waste_ids)>0 or cardinality(p_delete_movement_ids)>0) then raise exception '営業担当者は廃棄履歴の登録・修正のみ可能です' using errcode='42501'; end if;
  if v_profile.role='worker' and (cardinality(p_delete_record_ids)>0 or cardinality(p_delete_movement_ids)>0) then raise exception '青果社員は通常在庫履歴を削除できません' using errcode='42501'; end if;

  if v_profile.role='admin' then
    delete from public.inventory_records
     where id = any(array(select public.seika_uuid_v188(v)::text from unnest(coalesce(p_delete_record_ids,'{}')) v where nullif(trim(v),'') is not null));
    delete from public.inventory_movements
     where id = any(array(select public.seika_uuid_v188(v)::text from unnest(coalesce(p_delete_movement_ids,'{}')) v where nullif(trim(v),'') is not null));
  end if;
  if v_profile.role in ('admin','worker') then
    delete from public.waste_records
     where id = any(array(select public.seika_uuid_v188(v)::text from unnest(coalesce(p_delete_waste_ids,'{}')) v where nullif(trim(v),'') is not null));
  end if;

  if v_profile.role in ('admin','worker') then
    for x in select value from jsonb_array_elements(p_records) loop
      insert into public.inventory_records(id,item_id,item_name,kind,total,status,user_name,user_role,created_at,updated_at,data)
      values(public.seika_uuid_v188(x->>'id')::text,x->>'itemId',x->>'itemName',x->>'kind',coalesce((x->>'total')::numeric,0),x->>'status',coalesce(x->>'user',v_profile.display_name),v_profile.role,coalesce((x->>'createdAt')::timestamptz,now()),now(),x)
      on conflict(id) do update set item_id=excluded.item_id,item_name=excluded.item_name,kind=excluded.kind,total=excluded.total,status=excluded.status,updated_at=now(),data=excluded.data;
    end loop;
    for x in select value from jsonb_array_elements(p_movements) loop
      insert into public.inventory_movements(id,record_id,item_id,item_name,movement_type,before_total,after_total,diff_kg,user_name,user_role,created_at,data)
      values(public.seika_uuid_v188(x->>'id')::text,
             case when nullif(x->>'recordId','') is null then null else public.seika_uuid_v188(x->>'recordId')::text end,
             x->>'itemId',x->>'itemName',x->>'type',coalesce((x->>'beforeTotal')::numeric,0),coalesce((x->>'afterTotal')::numeric,0),coalesce((x->>'diffKg')::numeric,0),coalesce(x->>'user',v_profile.display_name),v_profile.role,coalesce((x->>'createdAt')::timestamptz,now()),x)
      on conflict(id) do update set record_id=excluded.record_id,item_id=excluded.item_id,item_name=excluded.item_name,movement_type=excluded.movement_type,before_total=excluded.before_total,after_total=excluded.after_total,diff_kg=excluded.diff_kg,data=excluded.data;
    end loop;
  end if;

  for x in select value from jsonb_array_elements(p_waste_records) loop
    if v_profile.role='sales' then
      if not exists(select 1 from public.waste_records where id=public.seika_uuid_v188(x->>'id')::text) then
        raise exception '営業担当者は廃棄履歴を新規作成できません' using errcode='42501';
      end if;
      update public.waste_records wr
      set unit_price=coalesce((x->>'unitPrice')::numeric,wr.unit_price),
          amount=coalesce((x->>'amount')::numeric,wr.amount),
          updated_at=now(),
          data=jsonb_set(jsonb_set(coalesce(wr.data,'{}'::jsonb),'{unitPrice}',to_jsonb(coalesce((x->>'unitPrice')::numeric,wr.unit_price)),true),'{amount}',to_jsonb(coalesce((x->>'amount')::numeric,wr.amount)),true)
      where wr.id=public.seika_uuid_v188(x->>'id')::text;
    else
      insert into public.waste_records(id,waste_date,item_name,qty,unit_price,amount,user_name,user_id,created_at,updated_at,data)
      values(public.seika_uuid_v188(x->>'id')::text,coalesce((x->>'date')::date,current_date),coalesce(nullif(x->>'itemName',''),'-'),coalesce((x->>'qty')::numeric,0),coalesce((x->>'unitPrice')::numeric,0),coalesce((x->>'amount')::numeric,0),coalesce(x->>'user',v_profile.display_name),coalesce(x->>'userId',v_profile.legacy_user_id),coalesce((x->>'createdAt')::timestamptz,now()),now(),x)
      on conflict(id) do update set waste_date=excluded.waste_date,item_name=excluded.item_name,qty=excluded.qty,unit_price=excluded.unit_price,amount=excluded.amount,updated_at=now(),data=excluded.data;
    end if;
  end loop;

  return jsonb_build_object('ok',true);
end
$function$;

-- 権限（第2段階の方針を維持：未ログインには渡さない）
revoke execute on function public.save_history_records_v188(jsonb,jsonb,jsonb,text[],text[],text[]) from public, anon;
grant  execute on function public.save_history_records_v188(jsonb,jsonb,jsonb,text[],text[],text[]) to authenticated, service_role;

-- 動作確認：管理者になりきって実際に呼ぶ（既存1件を同じ内容で上書きするだけ）
do $$
declare v_uid uuid; v_row jsonb; v_res jsonb;
begin
  select id into v_uid from public.profiles where role='admin' and active=true order by display_name limit 1;
  select data into v_row from public.waste_records where data is not null order by updated_at desc nulls last limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub',v_uid,'role','authenticated')::text, true);
  perform set_config('role','authenticated',true);
  v_res := public.save_history_records_v188(p_waste_records => jsonb_build_array(v_row));
  raise notice '結果: %', v_res;
  perform set_config('role','none',true);
end $$;

select 'save_history_records_v188' as 関数, '修正完了' as 状態,
       (select count(*) from public.waste_records) || ' 行' as 現在の行数;
