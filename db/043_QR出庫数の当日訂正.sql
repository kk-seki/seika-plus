-- v1.199-c113 QR出庫数の当日訂正（埼玉・深谷の当日出庫）
-- 元行は変更せず、取消と訂正後の出庫を同一トランザクションで記録する。
begin;

-- 既存のCHECKを作り直さない。取消が未登録なら中断して先に既存の取消SQLを適用する。
do $block$
begin
  if not exists (
    select 1 from pg_constraint c join pg_class t on t.oid=c.conrelid join pg_namespace n on n.oid=t.relnamespace
    where n.nspname='public' and t.relname='qr_lot_movements' and c.contype='c' and pg_get_constraintdef(c.oid) like '%取消%'
  ) then
    raise exception 'qr_lot_movements の履歴種類に「取消」がありません。先に取消対応SQLを適用してください';
  end if;
end $block$;

-- 通常取消は訂正済み出庫を取り消せない。専用RPC内だけ、transaction-localの照合値で許可する。
create or replace function public.seika_reject_cancelled_outbound_correction_v1199c113()
returns trigger language plpgsql security definer set search_path to 'pg_catalog','public'
as $f$
declare v_meta jsonb; v_gate text;
begin
  if new.movement_type='取消' and new.reversed_operation_id is not null then
    select operation_meta into v_meta from public.qr_lot_movements where operation_id=new.reversed_operation_id;
    if v_meta ? 'outbound_correction_operation_id' then
      v_gate:=current_setting('seika.c113_outbound_correction_cancel',true);
      if v_gate is distinct from (v_meta->>'outbound_correction_operation_id') then
        raise exception '出庫数訂正で作成した出庫は、通常の取消では取り消せません。訂正画面から正しい数量を入れてください。';
      end if;
    end if;
  end if;
  return new;
end $f$;
drop trigger if exists seika_reject_cancelled_outbound_correction_v1199c113 on public.qr_lot_movements;
create trigger seika_reject_cancelled_outbound_correction_v1199c113 before insert on public.qr_lot_movements
for each row execute function public.seika_reject_cancelled_outbound_correction_v1199c113();

create or replace function public.correct_qr_outbound_v1199c113(
 p_operation_id uuid,p_original_operation_id uuid,p_qty numeric,p_expected_qty numeric,
 p_grades jsonb default '[]'::jsonb,p_total_kg numeric default null,p_device_meta jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','public'
as $f$
declare
 v_profile public.profiles%rowtype; v_original public.qr_lot_movements%rowtype; v_lot public.qr_lots%rowtype;
 v_done public.qr_lot_movements%rowtype; v_cancel public.qr_lot_movements%rowtype; v_old_adjust public.qr_slip_adjust_v1199c86%rowtype;
 v_cancel_operation_id uuid; v_before numeric; v_after_cancel numeric; v_after numeric; v_before_weight numeric; v_after_cancel_weight numeric; v_after_weight numeric; v_unit_weight numeric;
 v_meta jsonb; v_input jsonb; v_slip jsonb; v_is_big boolean; v_grade_count integer; v_input_grade_count integer; v_input_grade_sum numeric; v_cancel_at timestamptz; v_out_at timestamptz; v_previous_gate text; r record;
begin
 v_profile:=public.seika_v1136_require_roles(array['admin','worker']);
 if p_operation_id is null or p_original_operation_id is null or p_operation_id=p_original_operation_id then raise exception '訂正operation_idと元出庫operation_idを正しく指定してください'; end if;
 if p_qty is null or p_qty<0 or p_qty::text in ('NaN','Infinity','-Infinity') or p_expected_qty is null or p_expected_qty<0 or p_expected_qty::text in ('NaN','Infinity','-Infinity') then raise exception '訂正後の数量と現在の残数は0以上で入力してください'; end if;
 if p_total_kg is not null and (p_total_kg<=0 or p_total_kg>=100000 or p_total_kg::text in ('NaN','Infinity','-Infinity')) then raise exception '総重量は0より大きい数字で入力してください'; end if;
 if jsonb_typeof(coalesce(p_grades,'[]'::jsonb))<>'array' then raise exception '規格は配列で入力してください'; end if;
 v_input:=jsonb_build_object('original_operation_id',p_original_operation_id::text,'qty',p_qty,'expected_qty',p_expected_qty,'grades',coalesce(p_grades,'[]'::jsonb),'total_kg',p_total_kg);
 perform pg_advisory_xact_lock(hashtext(p_operation_id::text));
 -- operation_idは取消だけ（0訂正）又は再出庫だけ（通常訂正）に一意。行ロック後に全入力を照合する。
 select * into v_done from public.qr_lot_movements where operation_id=p_operation_id for update;
 if found then
   if v_done.operation_meta->'outbound_correction_input' is distinct from v_input then return jsonb_build_object('ok',false,'idempotency_conflict',true,'message','同じ訂正operation_idに異なる内容は使用できません'); end if;
   if v_done.movement_type='取消' then
     return jsonb_build_object('ok',true,'idempotent',true,'after_quantity',v_done.after_quantity,'movement_id',v_done.id,'cancel_movement_id',v_done.id);
   end if;
   select * into v_cancel from public.qr_lot_movements where operation_id=(v_done.operation_meta->>'outbound_correction_cancel_operation_id')::uuid;
   return jsonb_build_object('ok',true,'idempotent',true,'after_quantity',v_done.after_quantity,'movement_id',v_done.id,'cancel_movement_id',v_cancel.id);
 end if;
 select * into v_original from public.qr_lot_movements where operation_id=p_original_operation_id for update;
 if not found then return jsonb_build_object('ok',false,'not_found',true,'message','元の出庫履歴が見つかりません'); end if;
 if v_original.movement_type<>'出庫' or v_original.destination is null or v_original.destination not in ('埼玉','深谷') then raise exception '埼玉・深谷へのQR出庫だけ訂正できます'; end if;
 if v_original.cancelled_at is not null or v_original.reversed_operation_id is not null then raise exception '元の出庫はすでに取り消されています'; end if;
 if (coalesce(v_original.occurred_at,v_original.created_at) at time zone 'Asia/Tokyo')::date <> (now() at time zone 'Asia/Tokyo')::date then raise exception '出庫した当日だけ訂正できます'; end if;
 select * into v_lot from public.qr_lots where id=v_original.lot_id and active=true for update;
 if not found then return jsonb_build_object('ok',false,'not_found',true,'message','対象QRロットが見つかりません'); end if;
 -- ロットをロックしてから再確認。通常出庫・取消以外の後続操作があれば帳簿確定済みとして拒否する。
 if exists(select 1 from public.qr_lot_movements m where m.lot_id=v_lot.id and (m.created_at>v_original.created_at or(m.created_at=v_original.created_at and m.id>v_original.id)) and m.movement_type not in ('出庫','取消')) then raise exception '元出庫の後に棚卸し・実数調整などの在庫確定操作があります。訂正できません'; end if;
 if v_lot.current_qty is null or v_lot.current_qty is distinct from p_expected_qty then return jsonb_build_object('ok',false,'conflict',true,'current_quantity',v_lot.current_qty,'message','他の操作で残数が変わりました。画面を開き直してください'); end if;
 v_is_big:=coalesce(v_original.container_type,v_lot.container_type) in ('網コンテナ','鉄コンテナ','パレテーナ');
 if v_is_big and p_qty>0 and p_total_kg is null then raise exception '大型容器は訂正後の総重量が必要です'; end if;
 if not v_is_big and p_total_kg is not null then raise exception '総重量は大型容器だけ入力できます'; end if;
 -- 規格行を先に決まった順でロック。count(*) FOR UPDATEは使わない。
 perform 1 from public.qr_lot_grades_v1300 where lot_id=v_lot.id order by grade for update;
 select count(*) into v_grade_count from public.qr_lot_grades_v1300 where lot_id=v_lot.id;
 if exists(select 1 from jsonb_array_elements(coalesce(p_grades,'[]'::jsonb)) x where jsonb_typeof(x)<>'object' or nullif(btrim(x->>'grade'),'') is null or nullif(btrim(x->>'qty'),'') is null or not ((x->>'qty') ~ '^(0|[1-9][0-9]*)(\.[0-9]+)?$'))
    or exists(select 1 from jsonb_array_elements(coalesce(p_grades,'[]'::jsonb)) x group by btrim(x->>'grade') having count(*)>1) then raise exception '規格名と0以上の数量を重複なく入力してください'; end if;
 select count(*),coalesce(sum((x->>'qty')::numeric),0) into v_input_grade_count,v_input_grade_sum from jsonb_array_elements(coalesce(p_grades,'[]'::jsonb)) x;
 if v_grade_count=0 and v_input_grade_count<>0 then raise exception 'このロットは規格別ロットではありません'; end if;
 if v_grade_count>0 and (v_input_grade_count<>v_grade_count or v_input_grade_sum<>p_qty or exists(select 1 from public.qr_lot_grades_v1300 g where g.lot_id=v_lot.id and not exists(select 1 from jsonb_array_elements(p_grades) x where btrim(x->>'grade')=g.grade))) then raise exception '規格別ロットは全規格（0を含む）の訂正後数量を入力し、合計を出庫数と一致させてください'; end if;
 if v_grade_count>0 then
   if coalesce(jsonb_typeof(v_original.operation_meta->'grades'),'')<>'array' then raise exception '元出庫の規格履歴がありません'; end if;
   if exists(select 1 from jsonb_array_elements(v_original.operation_meta->'grades') x
       where jsonb_typeof(x)<>'object' or nullif(btrim(x->>'grade'),'') is null or x->>'delta' is null
         or (x->>'delta')::numeric>0 or (x->>'delta')::numeric::text in ('NaN','Infinity','-Infinity')
         or not exists(select 1 from public.qr_lot_grades_v1300 g where g.lot_id=v_lot.id and g.grade=x->>'grade'))
      or exists(select 1 from jsonb_array_elements(v_original.operation_meta->'grades') x group by x->>'grade' having count(*)>1)
      or (select coalesce(-sum((x->>'delta')::numeric),0) from jsonb_array_elements(v_original.operation_meta->'grades') x)<>v_original.qty then
     raise exception '元出庫の規格履歴と出庫数が一致しません';
   end if;
   if exists(select 1 from public.qr_lot_grades_v1300 g
       left join lateral (select (x->>'delta')::numeric delta from jsonb_array_elements(v_original.operation_meta->'grades') x where x->>'grade'=g.grade) old on true
       join lateral (select (x->>'qty')::numeric qty from jsonb_array_elements(p_grades) x where btrim(x->>'grade')=g.grade) next on true
       where g.lot_id=v_lot.id and g.current_qty-coalesce(old.delta,0)-next.qty<0) then
     raise exception '訂正後の規格別在庫が不足しています';
   end if;
 end if;
 if v_original.qty<=0 or v_original.qty::text in ('NaN','Infinity','-Infinity') then raise exception '元出庫の数量が不正です'; end if;
 v_before := v_lot.current_qty; v_after_cancel := v_before + v_original.qty; v_after := v_after_cancel - p_qty;
 if v_after<0 then return jsonb_build_object('ok',false,'insufficient_stock',true,'current_quantity',v_before,'message','訂正後の出庫数に必要な在庫がありません'); end if;
 v_before_weight:=v_lot.current_weight;
 v_unit_weight:=case when v_original.qty>0 and v_original.before_weight is not null and v_original.after_weight is not null then abs(v_original.before_weight-v_original.after_weight)/v_original.qty when v_before>0 and v_before_weight is not null then v_before_weight/v_before else null end;
 v_after_cancel_weight:=case when v_before_weight is null or v_unit_weight is null then v_before_weight else round(v_before_weight+v_original.qty*v_unit_weight,3) end;
 v_after_weight:=case when v_after_cancel_weight is null or v_unit_weight is null then v_after_cancel_weight else round(v_after_cancel_weight-p_qty*v_unit_weight,3) end;
 v_cancel_operation_id:=(substr(md5(p_operation_id::text||':cancel'),1,8)||'-'||substr(md5(p_operation_id::text||':cancel'),9,4)||'-'||substr(md5(p_operation_id::text||':cancel'),13,4)||'-'||substr(md5(p_operation_id::text||':cancel'),17,4)||'-'||substr(md5(p_operation_id::text||':cancel'),21,12))::uuid;
 v_meta:=coalesce(v_original.operation_meta,'{}'::jsonb); select * into v_old_adjust from public.qr_slip_adjust_v1199c86 where movement_id=v_original.id for update;
 v_slip:=coalesce(v_meta->'slip','{}'::jsonb); if v_old_adjust.total_kg is not null then v_slip:=v_slip||jsonb_build_object('kg',v_old_adjust.total_kg); end if; if v_old_adjust.pack is not null then v_slip:=v_slip||jsonb_build_object('pack',v_old_adjust.pack); end if; if p_total_kg is not null then v_slip:=v_slip||jsonb_build_object('kg',p_total_kg); end if;
 v_cancel_at:=greatest(clock_timestamp(),(select max(greatest(occurred_at,created_at))+interval '1 millisecond' from public.qr_lot_movements where lot_id=v_lot.id));
 v_out_at:=v_cancel_at+interval '1 millisecond';
 if (v_out_at at time zone 'Asia/Tokyo')::date<>(clock_timestamp() at time zone 'Asia/Tokyo')::date then raise exception '日付が変わるため訂正できません。履歴を開き直してください'; end if;
 v_previous_gate:=current_setting('seika.c113_outbound_correction_cancel',true);
 perform set_config('seika.c113_outbound_correction_cancel',coalesce(v_original.operation_meta->>'outbound_correction_operation_id',''),true);
 update public.qr_lots set current_qty=v_after_cancel,current_weight=v_after_cancel_weight,status=case when v_after_cancel>0 then '在庫あり' else '在庫なし' end,updated_at=now() where id=v_lot.id;
 insert into public.qr_lot_movements(movement_type,lot_id,lot_no,qr_key,item_id,item_name,origin,supplier,cooperative_name,qty,unit,destination,storage_location,user_id,user_name,memo,container_type,lot_manage_type,weight,before_quantity,after_quantity,before_weight,after_weight,weight_status,reason,operation_id,reversed_operation_id,device_meta,operation_meta,occurred_at,created_at)
 values('取消',v_original.lot_id,v_original.lot_no,v_original.qr_key,v_original.item_id,v_original.item_name,v_original.origin,v_original.supplier,v_original.cooperative_name,v_original.qty,v_original.unit,v_original.destination,v_lot.storage_location,v_profile.id::text,coalesce(v_profile.display_name,''),'出庫数訂正のため元出庫を取消',v_original.container_type,v_original.lot_manage_type,v_original.weight,v_before,v_after_cancel,v_before_weight,v_after_cancel_weight,v_original.weight_status,'出庫数訂正',case when p_qty=0 then p_operation_id else v_cancel_operation_id end,p_original_operation_id,coalesce(p_device_meta,'{}'::jsonb),jsonb_build_object('outbound_correction_operation_id',p_operation_id::text,'outbound_correction_cancel_operation_id',v_cancel_operation_id::text,'outbound_correction_input',v_input),v_cancel_at,v_cancel_at) returning * into v_cancel;
 perform set_config('seika.c113_outbound_correction_cancel',coalesce(v_previous_gate,''),true);
 update public.qr_lot_movements set reversed_operation_id=case when p_qty=0 then p_operation_id else v_cancel_operation_id end,cancelled_at=now(),cancelled_by=v_profile.id::text where id=v_original.id;
 if p_qty=0 then return jsonb_build_object('ok',true,'after_quantity',v_after_cancel,'movement_id',v_cancel.id,'cancel_movement_id',v_cancel.id); end if;
 update public.qr_lots set current_qty=v_after,current_weight=v_after_weight,status=case when v_after>0 then '在庫あり' else '在庫なし' end,updated_at=now() where id=v_lot.id;
 if v_grade_count>0 then for r in select value d from jsonb_array_elements(p_grades) loop update public.qr_lot_grades_v1300 set current_qty=current_qty-(r.d->>'qty')::numeric,updated_at=now() where lot_id=v_lot.id and grade=btrim(r.d->>'grade'); end loop; end if;
 insert into public.qr_lot_movements(movement_type,lot_id,lot_no,qr_key,item_id,item_name,origin,supplier,cooperative_name,qty,unit,destination,storage_location,user_id,user_name,memo,container_type,lot_manage_type,weight,before_quantity,after_quantity,before_weight,after_weight,weight_status,reason,operation_id,device_meta,operation_meta,occurred_at,created_at)
 values('出庫',v_original.lot_id,v_original.lot_no,v_original.qr_key,v_original.item_id,v_original.item_name,v_original.origin,v_original.supplier,v_original.cooperative_name,p_qty,v_original.unit,v_original.destination,v_lot.storage_location,v_profile.id::text,coalesce(v_profile.display_name,''),v_original.memo,v_original.container_type,v_original.lot_manage_type,case when v_unit_weight is null then v_original.weight else round(p_qty*v_unit_weight,3) end,v_after_cancel,v_after,v_after_cancel_weight,v_after_weight,v_original.weight_status,'出庫数訂正',p_operation_id,coalesce(p_device_meta,'{}'::jsonb),v_meta||jsonb_build_object('slip',v_slip,'outbound_correction_operation_id',p_operation_id::text,'outbound_correction_original_operation_id',p_original_operation_id::text,'outbound_correction_cancel_operation_id',v_cancel_operation_id::text,'outbound_correction_input',v_input,'grades',case when v_grade_count>0 then(select coalesce(jsonb_agg(jsonb_build_object('grade',btrim(x->>'grade'),'delta',-((x->>'qty')::numeric))),'[]'::jsonb)from jsonb_array_elements(p_grades)x)else '[]'::jsonb end),v_out_at,v_out_at) returning * into v_done;
 if v_old_adjust.movement_id is not null or v_slip?'kg' or v_slip?'pack' then insert into public.qr_slip_adjust_v1199c86(movement_id,total_kg,pack,updated_by,updated_by_name,updated_at) values(v_done.id,coalesce(p_total_kg,v_old_adjust.total_kg),coalesce(v_old_adjust.pack,v_slip->>'pack'),v_profile.id,v_profile.display_name,now()) on conflict(movement_id) do update set total_kg=excluded.total_kg,pack=excluded.pack,updated_by=excluded.updated_by,updated_by_name=excluded.updated_by_name,updated_at=now(); end if;
 return jsonb_build_object('ok',true,'message','出庫数を訂正しました','after_quantity',v_after,'movement_id',v_done.id,'cancel_movement_id',v_cancel.id);
end $f$;
revoke all on function public.correct_qr_outbound_v1199c113(uuid,uuid,numeric,numeric,jsonb,numeric,jsonb) from public,anon;
grant execute on function public.correct_qr_outbound_v1199c113(uuid,uuid,numeric,numeric,jsonb,numeric,jsonb) to authenticated,service_role;
commit;
notify pgrst,'reload schema';
select case when to_regprocedure('public.correct_qr_outbound_v1199c113(uuid,uuid,numeric,numeric,jsonb,numeric,jsonb)') is not null then 'OK' else '要確認' end as 出庫訂正RPC;
