/*
050_本社下処理_箱の半端と廃棄の手入力.sql（v1.199-c123）

前提：019〜049を番号順に実行済みであること。
箱原料の開封済み残量と、日報後入力の手入力廃棄を保存します。
SQLの適用だけでは既存の作業・在庫・履歴を変更しません。
*/
begin;

do $block$
begin
  if to_regclass('public.hq_work_material_units_v1199c122') is null
     or to_regprocedure('public.hq_work_pallet_use_v1199c122(uuid,uuid,integer,text,numeric,numeric,uuid)') is null
     or to_regprocedure('public.hq_prep_report_save_v1199c120(uuid,uuid,timestamp with time zone,jsonb)') is null then
    raise exception '先に db/019〜049 を番号順に実行してください';
  end if;
end $block$;

alter table public.hq_work_material_units_v1199c122 add column if not exists unopened_cases numeric;
alter table public.hq_work_material_units_v1199c122 add column if not exists open_box_kg numeric;

create or replace function public.hq_work_pallet_use_v1199c123(
  p_work_id uuid,p_lot_id uuid,p_unit_no integer,p_mode text,p_unopened_cases numeric,
  p_open_box_kg numeric,p_remaining numeric,p_unit_total numeric,p_operation_id uuid
) returns jsonb language plpgsql security definer set search_path to ''
as $f$
declare v public.profiles; w public.hq_works_v1500%rowtype; l public.hq_lots_v1400%rowtype;
  mt public.hq_work_materials_v1500%rowtype; old public.hq_work_material_units_v1199c122%rowtype;
  definition jsonb; x jsonb; source text; v_unit_total numeric; before_qty numeric; used numeric; remaining numeric;
  pack numeric; v_unopened numeric; v_open numeric; v_box_remainder boolean:=false; updated timestamptz;
begin
  v:=public.hq_actor_v1400(array['admin','hq_worker','hq_prep']);
  if p_operation_id is null then raise exception '操作IDが必要です'; end if;
  if p_mode not in ('全量','半端') then raise exception '使用方法は全量か半端を選んでください'; end if;
  if p_unit_total is not null and (p_unit_total<=0 or p_unit_total::text in ('NaN','Infinity','-Infinity')) then raise exception '元の量は0より大きい数で入れてください'; end if;
  if p_remaining is not null and (p_remaining<0 or p_remaining::text in ('NaN','Infinity','-Infinity')) then raise exception '残りは正しい数で入れてください'; end if;
  if p_unopened_cases is not null and (p_unopened_cases<0 or p_unopened_cases<>trunc(p_unopened_cases) or p_unopened_cases::text in ('NaN','Infinity','-Infinity')) then raise exception '開けていない箱は0以上の整数で入れてください'; end if;
  if p_open_box_kg is not null and (p_open_box_kg<0 or p_open_box_kg::text in ('NaN','Infinity','-Infinity')) then raise exception '開けた箱の残りは0以上の数字で入れてください'; end if;
  select * into w from public.hq_works_v1500 where id=p_work_id for update;
  if not found then raise exception '下処理が見つかりません'; end if;
  if w.kind<>'下処理' or w.status<>'作業中' or w.confirm_status<>'未確定' then raise exception '原料の使用は未確定の作業中の下処理だけ記録できます'; end if;
  select * into l from public.hq_lots_v1400 where id=p_lot_id for update;
  if not found then raise exception '原料が見つかりません'; end if;
  if l.item_name<>w.raw_item_name then raise exception '原料 %（%）は、この下処理の原料（%）と違います',l.lot_no,l.item_name,w.raw_item_name; end if;
  if l.status<>'在庫あり' or coalesce(l.current_qty,0)<=0 then raise exception '原料 % は在庫ありで、残数があるロットだけ追加できます',l.lot_no; end if;
  if p_mode='全量' and (p_unopened_cases is not null or p_open_box_kg is not null or p_remaining is not null) then raise exception '全量では残りを指定できません'; end if;
  if l.unit<>'kg' and p_mode='半端' and (p_unopened_cases is not null or p_open_box_kg is not null) then
    if p_unopened_cases is null or p_open_box_kg is null or p_remaining is not null then raise exception '箱の半端は未開封ケースと開けた箱の残りkgを両方入れてください'; end if;
    pack:=public.hq_c117_lot_pack_kg(l);
    if pack is null or pack<=0 then raise exception '原料 % の量目が不明です',l.lot_no; end if;
    if p_open_box_kg>=pack then raise exception '開けた箱の残りは1箱の量目より小さく入れてください'; end if;
    if p_unopened_cases=0 and p_open_box_kg=0 then raise exception '残りが0なら「全部使った」を選んでください'; end if;
    v_unopened:=p_unopened_cases; v_open:=round(p_open_box_kg,3); remaining:=round((v_unopened*pack+v_open)/pack,6); v_box_remainder:=true;
  elsif p_mode='半端' then
    if p_remaining is null then raise exception '残りは正しい数で入れてください'; end if;
    remaining:=round(p_remaining,6);
  else
    remaining:=0;
  end if;
  select * into old from public.hq_work_material_units_v1199c122 where operation_id=p_operation_id for update;
  if found then
    if old.work_id=p_work_id and old.lot_id=p_lot_id and old.unit_no is not distinct from p_unit_no and old.mode=p_mode
       and old.unopened_cases is not distinct from (case when v_box_remainder then v_unopened else null end)
       and old.open_box_kg is not distinct from (case when v_box_remainder then v_open else null end)
       and old.remaining_qty is not distinct from remaining then
      return jsonb_build_object('ok',true,'already',true,'entry_id',old.id,'material_id',old.material_id,
        'unopened_cases',old.unopened_cases,'open_box_kg',old.open_box_kg,'used_qty',old.used_qty,
        'remaining_qty',old.remaining_qty,'unit_total',old.unit_total,'unit_no',old.unit_no);
    end if;
    raise exception 'この操作IDは別の内容で使われています';
  end if;
  definition:=public.hq_c122_units(l); source:=definition->>'source';
  if source='manual' or p_unit_no is null then
    if p_unit_total is null or p_unit_total<=0 then raise exception '元の量は0より大きい数で入れてください'; end if;
    v_unit_total:=round(p_unit_total,6);
  else
    select value into x from jsonb_array_elements(definition->'units') where (value->>'no')::integer=p_unit_no;
    if x is null then raise exception 'パレット（基）の番号が正しくありません'; end if;
    v_unit_total:=round((x->>'total')::numeric,6);
  end if;
  if source<>'manual' and p_unit_no is null and (p_unit_total is null or p_unit_total<=0) then raise exception '元の量は0より大きい数で入れてください'; end if;
  select * into mt from public.hq_work_materials_v1500 where work_id=w.id and lot_id=l.id for update;
  if not found then
    insert into public.hq_work_materials_v1500(work_id,lot_id,lot_no,item_name,unit,pack_kg,qty)
    values(w.id,l.id,l.lot_no,l.item_name,l.unit,case when l.unit='kg' then null else public.hq_c117_lot_pack_kg(l) end,0)
    returning * into mt;
  end if;
  if source='manual' or p_unit_no is null then before_qty:=v_unit_total;
  else
    select v_unit_total-coalesce(sum(e.used_qty),0) into before_qty
    from public.hq_work_material_units_v1199c122 e join public.hq_works_v1500 ew on ew.id=e.work_id
    where e.lot_id=l.id and e.unit_no=p_unit_no and e.cancelled_at is null and ew.kind='下処理' and ew.status<>'取消';
    before_qty:=round(before_qty,6);
  end if;
  if before_qty<=0 then raise exception 'このパレット（基）は、もう使い切っています'; end if;
  if p_mode='全量' then used:=before_qty;
  else
    if remaining<=0 or remaining>=before_qty then
      raise exception '残りは、0より大きく%より小さい数で入れてください。残りが0なら「全部使った」を選んでください',before_qty;
    end if;
    used:=round(before_qty-remaining,6);
  end if;
  if used<=0 then raise exception '使用量は0より大きくしてください'; end if;
  insert into public.hq_work_material_units_v1199c122(work_id,material_id,lot_id,unit_no,unit_total,mode,used_qty,remaining_qty,unopened_cases,open_box_kg,operation_id,created_by_name)
  values(w.id,mt.id,l.id,p_unit_no,v_unit_total,p_mode,used,remaining,case when v_box_remainder then v_unopened end,case when v_box_remainder then v_open end,p_operation_id,v.display_name) returning * into old;
  update public.hq_work_materials_v1500 set qty=coalesce(qty,0)+used where id=mt.id returning * into mt;
  perform public.hq_c117_guard_reservations(w.id);
  update public.hq_works_v1500 set history=history||jsonb_build_array(jsonb_build_object(
    'at',now(),'by',v.display_name,'action','パレット／基の使用を記録','lot_id',l.id,'material_id',mt.id,'unit_no',p_unit_no,
    'mode',p_mode,'used',used,'remaining',remaining,'unopened_cases',case when v_box_remainder then v_unopened end,'open_box_kg',case when v_box_remainder then v_open end)),updated_at=now() where id=w.id returning updated_at into updated;
  return jsonb_build_object('ok',true,'entry_id',old.id,'material_id',mt.id,'unopened_cases',old.unopened_cases,'open_box_kg',old.open_box_kg,
    'used_qty',used,'remaining_qty',remaining,'material_qty',mt.qty,'unit_total',v_unit_total,'unit_no',p_unit_no,'updated_at',updated);
end $f$;

create or replace function public.hq_pallet_candidates_v1199c122(p_work_id uuid,p_lot_id uuid)
returns jsonb language plpgsql security definer set search_path to ''
as $f$
declare v public.profiles; w public.hq_works_v1500%rowtype; l public.hq_lots_v1400%rowtype;
  definition jsonb; x jsonb; n integer; total numeric; used numeric; mine numeric; remaining numeric;
  units jsonb:='[]'::jsonb; next_no integer; available numeric; pack numeric; unopened numeric; open_kg numeric;
begin
  v:=public.hq_actor_v1400(array['admin','hq_worker','hq_prep']);
  select * into w from public.hq_works_v1500 where id=p_work_id;
  if not found or w.kind<>'下処理' then raise exception '下処理が見つかりません'; end if;
  select * into l from public.hq_lots_v1400 where id=p_lot_id;
  if not found or l.status not in ('在庫あり','在庫なし') then raise exception 'この原料は、まだ使えません'; end if;
  definition:=public.hq_c122_units(l);
  pack:=case when l.unit='kg' then null else public.hq_c117_lot_pack_kg(l) end;
  for x in select value from jsonb_array_elements(definition->'units') loop
    n:=(x->>'no')::integer; total:=(x->>'total')::numeric;
    select coalesce(sum(e.used_qty),0),coalesce(sum(e.used_qty) filter(where e.work_id=p_work_id),0) into used,mine
    from public.hq_work_material_units_v1199c122 e join public.hq_works_v1500 ew on ew.id=e.work_id
    where e.lot_id=l.id and e.unit_no=n and e.cancelled_at is null and ew.kind='下処理' and ew.status<>'取消';
    remaining:=greatest(round(total-used,6),0);
    unopened:=case when l.unit='kg' or pack is null or pack<=0 then null else floor(remaining) end;
    open_kg:=case when l.unit='kg' or pack is null or pack<=0 then null else round((remaining-floor(remaining))*pack,3) end;
    units:=units||jsonb_build_array(jsonb_strip_nulls(jsonb_build_object('no',n,'total',total,'used',round(used,6),'remaining',remaining,
      'mine',round(mine,6),'state',case when used=0 then 'unused' when remaining>0 then 'partial' else 'done' end,
      'remaining_unopened',unopened,'remaining_open_kg',open_kg)));
  end loop;
  select (value->>'no')::integer into next_no from jsonb_array_elements(units) where value->>'state'='partial' order by (value->>'no')::integer limit 1;
  if next_no is null then select (value->>'no')::integer into next_no from jsonb_array_elements(units) where value->>'state'='unused' order by (value->>'no')::integer limit 1; end if;
  available:=public.hq_c117_available_qty(l.id,p_work_id);
  return jsonb_build_object('ok',true,'lot_id',l.id,'lot_no',l.lot_no,'item_name',l.item_name,'qty_unit',case when l.unit='kg' then 'kg' else 'ケース' end,
    'large',(definition->>'source')='container','pack_kg',pack,'source',definition->>'source','units',units,'next_no',next_no,'lot_available',available);
end $f$;

create or replace function public.hq_work_pallet_list_v1199c122(p_work_ids uuid[])
returns jsonb language plpgsql stable security definer set search_path to ''
as $f$
begin
  perform public.hq_actor_v1400(array['admin','hq_worker','hq_prep']);
  return coalesce((select jsonb_agg(jsonb_build_object('entry_id',e.id,'work_id',e.work_id,'material_id',e.material_id,'lot_id',e.lot_id,'unit_no',e.unit_no,
    'unit_total',e.unit_total,'mode',e.mode,'used_qty',e.used_qty,'remaining_qty',e.remaining_qty,'unopened_cases',e.unopened_cases,'open_box_kg',e.open_box_kg,
    'created_at',e.created_at,'created_by_name',e.created_by_name) order by e.created_at,e.id)
    from public.hq_work_material_units_v1199c122 e where e.work_id=any(coalesce(p_work_ids,'{}'::uuid[])) and e.cancelled_at is null),'[]'::jsonb);
end $f$;

-- c117の日報後入力を旧保存・初回確定・確定後訂正のいずれからも、手入力廃棄の範囲で保存できるようにする。
create or replace function public.hq_c116_save_inputs(
  p_work_id uuid,p_materials jsonb,p_waste_kg numeric,p_outputs jsonb,p_by public.profiles
) returns jsonb language plpgsql security definer set search_path to ''
as $f$
declare w public.hq_works_v1500%rowtype; ids uuid[]; r jsonb; v_id uuid; v_qty numeric; v_outputs jsonb; v_yield numeric;
  v_raw_kg numeric:=0; v_standard numeric; v_tolerance numeric; v_master_ids uuid[]; mt public.hq_work_materials_v1500%rowtype;
begin
  if jsonb_typeof(coalesce(p_materials,'[]'::jsonb))<>'array' then raise exception '使用原料の形が正しくありません'; end if;
  if p_waste_kg is null or p_waste_kg<0 or p_waste_kg::text in ('NaN','Infinity','-Infinity') then raise exception '廃棄（kg）は0以上の数字で入れてください'; end if;
  select * into w from public.hq_works_v1500 where id=p_work_id for update;
  if not found or w.kind<>'下処理' then raise exception '下処理が見つかりません'; end if;
  if w.status='作業中' then raise exception '先に「作業終了」をしてください'; end if;
  if w.status='取消' or w.confirm_status<>'未確定' then raise exception 'この下処理は確定済みか取消済みです。訂正画面から直してください'; end if;
  if w.pause_kind<>'' then raise exception '休憩・中断中の作業は、先に再開するか休憩を終えてください'; end if;
  ids:=array(select id from public.hq_work_materials_v1500 where work_id=w.id order by id);
  if jsonb_array_length(p_materials)<>coalesce(array_length(ids,1),0) then raise exception 'すべての原料の使用数を入れてください'; end if;
  if exists(select 1 from jsonb_array_elements(p_materials) x where jsonb_typeof(x.value)<>'object') or exists(select 1 from jsonb_array_elements(p_materials) x group by x.value->>'id' having count(*)>1) then raise exception '使用原料の形が正しくありません'; end if;
  for r in select value from jsonb_array_elements(p_materials) loop
    begin v_id:=(r->>'id')::uuid; exception when others then raise exception '使用原料が見つかりません'; end;
    if v_id is null or not(v_id=any(ids)) then raise exception '使用原料が見つかりません'; end if;
    v_qty:=public.hq_c116_nonnegative(r->>'qty','使用原料の数');
    update public.hq_work_materials_v1500 set qty=v_qty where id=v_id and work_id=w.id;
  end loop;
  perform public.hq_c117_guard_reservations(w.id);
  v_outputs:=public.hq_c116_work_outputs(w,p_outputs);
  select coalesce(sum((value->>'yield_kg')::numeric),0) into v_yield from jsonb_array_elements(v_outputs);
  if w.report_entered_at is not null then
    for mt in select * from public.hq_work_materials_v1500 where work_id=w.id order by lot_id loop
      if mt.unit='kg' then v_raw_kg:=v_raw_kg+coalesce(mt.qty,0);
      elsif mt.pack_kg is null or mt.pack_kg<=0 then raise exception '原料 % の量目が不明です',coalesce(mt.lot_no,mt.lot_id::text);
      else v_raw_kg:=v_raw_kg+coalesce(mt.qty,0)*mt.pack_kg;
      end if;
    end loop;
    if v_raw_kg<=0 then raise exception '使用重量の合計は0より大きくしてください'; end if;
    if v_yield+p_waste_kg>v_raw_kg then raise exception '出来高と廃棄の合計が、使用した原料の重さを超えています'; end if;
  end if;
  if w.standard_rate is null and w.tolerance_points is null and w.report_entered_at is null then
    v_master_ids:=public.hq_c116_work_master_ids(w);
    select standard_rate,tolerance_points into v_standard,v_tolerance from public.hq_prep_standards_v1199c117 where master_ids=v_master_ids;
    v_tolerance:=coalesce(v_tolerance,5);
  end if;
  update public.hq_works_v1500 set waste_kg=p_waste_kg,yield_kg=v_yield,outputs=v_outputs,
    report_raw_kg=case when w.report_entered_at is not null then v_raw_kg else report_raw_kg end,
    report_waste_kg=case when w.report_entered_at is not null then p_waste_kg else report_waste_kg end,
    standard_rate=case when w.standard_rate is null and w.tolerance_points is null and w.report_entered_at is null then v_standard else standard_rate end,
    tolerance_points=case when w.standard_rate is null and w.tolerance_points is null and w.report_entered_at is null then v_tolerance else tolerance_points end,
    inputs_saved_at=now(),inputs_saved_by_name=p_by.display_name,updated_at=now() where id=w.id;
  return jsonb_build_object('ok',true,'yield_kg',v_yield,'outputs',v_outputs);
end $f$;

create or replace function public.hq_c117_report_integrity_trigger()
returns trigger language plpgsql security definer set search_path to ''
as $f$
declare v_raw numeric; v_bad boolean; w public.hq_works_v1500%rowtype;
begin
  select * into w from public.hq_works_v1500 where id=new.id;
  if not found or w.report_entered_at is null or w.status='取消' or w.confirm_status='取消' then return new; end if;
  select coalesce(sum(case when m.unit='kg' then coalesce(m.qty,0) when m.pack_kg is not null and m.pack_kg>0 then coalesce(m.qty,0)*m.pack_kg else null end),0),
    bool_or((m.unit<>'kg') and (m.pack_kg is null or m.pack_kg<=0)) into v_raw,v_bad from public.hq_work_materials_v1500 m where m.work_id=new.id;
  if coalesce(v_bad,false) or v_raw<=0 then raise exception '日報後入力の原料重量を確認してください'; end if;
  if w.yield_kg is null or w.waste_kg is null or w.yield_kg::text in ('NaN','Infinity','-Infinity') or w.waste_kg::text in ('NaN','Infinity','-Infinity')
     or w.yield_kg<0 or w.waste_kg<0 or w.yield_kg+w.waste_kg>v_raw then
    raise exception '出来高と廃棄の合計が、使用した原料の重さを超えています';
  end if;
  if w.report_raw_kg is distinct from v_raw or w.report_waste_kg is distinct from w.waste_kg then
    update public.hq_works_v1500 set report_raw_kg=v_raw,report_waste_kg=w.waste_kg where id=w.id;
  end if;
  return new;
end $f$;

-- 047のc120保存関数は、既存本体の廃棄自動計算箇所だけを再実行可能に差し替える。
do $block$
declare d text; old_code text; new_code text;
begin
  d:=pg_get_functiondef('public.hq_prep_report_save_v1199c120(uuid,uuid,timestamp with time zone,jsonb)'::regprocedure);
  if position('-- c123 manual waste v1' in d)=0 then
    old_code:='  v_waste_kg:=v_raw_kg-v_yield_kg;'||chr(10)||'  norm:=public.hq_c120_normalize_intervals(p_work_id,v_started,v_ended,p_report->''members'',coalesce(p_report->''breaks'',''[]''::jsonb));';
    new_code:='  -- c123 manual waste v1' || chr(10) ||
      '  if p_report ? ''waste_kg'' and p_report->''waste_kg'' <> ''null''::jsonb then' || chr(10) ||
      '    if jsonb_typeof(p_report->''waste_kg'')<>''number'' then raise exception ''廃棄（kg）は0以上の数字で入れてください''; end if;' || chr(10) ||
      '    v_waste_kg:=public.hq_c117_number(p_report->>''waste_kg'',''廃棄（kg）'');' || chr(10) ||
      '  else v_waste_kg:=v_raw_kg-v_yield_kg; end if;' || chr(10) ||
      '  if v_waste_kg<0 then raise exception ''廃棄（kg）は0以上の数字で入れてください''; end if;' || chr(10) ||
      '  if v_yield_kg+v_waste_kg>v_raw_kg then raise exception ''出来高と廃棄の合計が、使用した原料の重さを超えています''; end if;' || chr(10) ||
      '  norm:=public.hq_c120_normalize_intervals(p_work_id,v_started,v_ended,p_report->''members'',coalesce(p_report->''breaks'',''[]''::jsonb));';
    if position(old_code in d)=0 then raise exception 'c120日報保存RPCの廃棄計算箇所を確認してください'; end if;
    execute replace(d,old_code,new_code);
  end if;
end $block$;

do $block$
declare f text;
begin
  foreach f in array array[
    'public.hq_pallet_candidates_v1199c122(uuid,uuid)',
    'public.hq_work_pallet_use_v1199c123(uuid,uuid,integer,text,numeric,numeric,numeric,numeric,uuid)',
    'public.hq_work_pallet_cancel_v1199c122(uuid,uuid)',
    'public.hq_work_pallet_list_v1199c122(uuid[])'
  ] loop
    execute format('revoke all on function %s from public, anon',f);
    execute format('grant execute on function %s to authenticated, service_role',f);
  end loop;
end $block$;
commit;
notify pgrst,'reload schema';

/* 成功の確かめ方：下の7行がすべてOKなら成功です。 */
select 'c123箱半端列' as 確認,case when exists(select 1 from information_schema.columns where table_schema='public' and table_name='hq_work_material_units_v1199c122' and column_name='open_box_kg') then 'OK' else 'NG' end as 結果
union all select 'c123使用RPC',case when to_regprocedure('public.hq_work_pallet_use_v1199c123(uuid,uuid,integer,text,numeric,numeric,numeric,numeric,uuid)') is not null then 'OK' else 'NG' end
union all select 'c123候補RPC',case when to_regprocedure('public.hq_pallet_candidates_v1199c122(uuid,uuid)') is not null then 'OK' else 'NG' end
union all select 'c123一覧RPC',case when to_regprocedure('public.hq_work_pallet_list_v1199c122(uuid[])') is not null then 'OK' else 'NG' end
union all select 'c123日報廃棄RPC',case when position('-- c123 manual waste v1' in pg_get_functiondef('public.hq_prep_report_save_v1199c120(uuid,uuid,timestamp with time zone,jsonb)'::regprocedure))>0 then 'OK' else 'NG' end
union all select 'c123日報整合検査',case when position('出来高と廃棄の合計が、使用した原料の重さを超えています' in pg_get_functiondef('public.hq_c117_report_integrity_trigger()'::regprocedure))>0 then 'OK' else 'NG' end
union all select 'c123使用記録表権限',case when not has_table_privilege('authenticated','public.hq_work_material_units_v1199c122','select,insert,update,delete') then 'OK' else 'NG' end;
