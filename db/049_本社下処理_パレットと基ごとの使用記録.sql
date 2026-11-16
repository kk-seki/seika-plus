/*
049_本社下処理_パレットと基ごとの使用記録.sql（v1.199-c122）

前提：019〜048 を番号順に実行済みであること。
下処理中に、原料ロットのパレット（通常容器）又は基（大型容器）ごとの使用を記録します。
SQLの適用だけでは、既存の作業・原料使用数・在庫・履歴を変更しません。
*/
begin;

do $block$
begin
  if to_regclass('public.hq_works_v1500') is null
     or to_regclass('public.hq_work_materials_v1500') is null
     or to_regclass('public.hq_lots_v1400') is null
     or to_regprocedure('public.hq_actor_v1400(text[])') is null
     or to_regprocedure('public.hq_c117_available_qty(uuid,uuid)') is null
     or to_regprocedure('public.hq_c117_guard_reservations(uuid)') is null
     or to_regprocedure('public.hq_c117_lot_pack_kg(public.hq_lots_v1400)') is null then
    raise exception '先に db/019〜048 を番号順に実行してください';
  end if;
end $block$;

create table if not exists public.hq_work_material_units_v1199c122 (
  id uuid primary key default gen_random_uuid(),
  work_id uuid not null references public.hq_works_v1500(id) on delete cascade,
  material_id uuid not null references public.hq_work_materials_v1500(id) on delete cascade,
  lot_id uuid not null,
  unit_no integer,
  unit_total numeric not null check (unit_total > 0),
  mode text not null check (mode in ('全量','半端')),
  used_qty numeric not null check (used_qty >= 0),
  remaining_qty numeric not null check (remaining_qty >= 0),
  operation_id uuid not null unique,
  created_by_name text,
  created_at timestamptz not null default now(),
  cancelled_at timestamptz,
  cancelled_by_name text
);
create index if not exists hq_work_material_units_v1199c122_lot_unit_idx
  on public.hq_work_material_units_v1199c122(lot_id, unit_no, created_at);
create index if not exists hq_work_material_units_v1199c122_work_idx
  on public.hq_work_material_units_v1199c122(work_id, created_at);
alter table public.hq_work_material_units_v1199c122 enable row level security;
revoke all on table public.hq_work_material_units_v1199c122 from public, anon, authenticated;
grant all on table public.hq_work_material_units_v1199c122 to service_role;

-- ロットの物理単位の元量を一箇所で判定する。大型容器を通常の貼り紙設定より優先する。
create or replace function public.hq_c122_units(p_lot public.hq_lots_v1400)
returns jsonb language plpgsql stable security definer set search_path to ''
as $f$
declare n integer; i integer; per numeric; total numeric; last_total numeric; source text; values jsonb:='[]'::jsonb; x jsonb;
begin
  if p_lot.unit='kg' and coalesce(p_lot.planned_count,0)>0 and coalesce(p_lot.unit_weight_kg,0)>0 then
    n:=floor(p_lot.planned_count)::integer;
    if n<1 then return jsonb_build_object('source','manual','units','[]'::jsonb); end if;
    per:=round(p_lot.unit_weight_kg,3);
    for i in 1..n loop
      last_total:=round(coalesce(p_lot.planned_qty,0)-(i-1)*per,3);
      total:=case when i=n and last_total>0 then last_total else per end;
      values:=values||jsonb_build_array(jsonb_build_object('no',i,'total',total));
    end loop;
    return jsonb_build_object('source','container','units',values);
  end if;
  if jsonb_typeof(coalesce(p_lot.sheet_meta,'null'::jsonb)->'palletQtys')='array'
     and jsonb_array_length(p_lot.sheet_meta->'palletQtys')>0
     and not exists (
       select 1 from jsonb_array_elements(p_lot.sheet_meta->'palletQtys') q
       where jsonb_typeof(q.value)<>'number' or (q.value #>> '{}')::numeric<=0
     ) then
    i:=0;
    for x in select value from jsonb_array_elements(p_lot.sheet_meta->'palletQtys') loop
      i:=i+1;
      values:=values||jsonb_build_array(jsonb_build_object('no',i,'total',round((x #>> '{}')::numeric,3)));
    end loop;
    return jsonb_build_object('source','sheet','units',values);
  end if;
  return jsonb_build_object('source','manual','units','[]'::jsonb);
end $f$;

create or replace function public.hq_pallet_candidates_v1199c122(p_work_id uuid,p_lot_id uuid)
returns jsonb language plpgsql security definer set search_path to ''
as $f$
declare v public.profiles; w public.hq_works_v1500%rowtype; l public.hq_lots_v1400%rowtype;
  definition jsonb; x jsonb; n integer; total numeric; used numeric; mine numeric; remaining numeric;
  units jsonb:='[]'::jsonb; next_no integer; available numeric; pack numeric;
begin
  v:=public.hq_actor_v1400(array['admin','hq_worker','hq_prep']);
  select * into w from public.hq_works_v1500 where id=p_work_id;
  if not found or w.kind<>'下処理' then raise exception '下処理が見つかりません'; end if;
  select * into l from public.hq_lots_v1400 where id=p_lot_id;
  if not found or l.status not in ('在庫あり','在庫なし') then raise exception 'この原料は、まだ使えません'; end if;
  definition:=public.hq_c122_units(l);
  for x in select value from jsonb_array_elements(definition->'units') loop
    n:=(x->>'no')::integer; total:=(x->>'total')::numeric;
    select coalesce(sum(e.used_qty),0),coalesce(sum(e.used_qty) filter(where e.work_id=p_work_id),0)
      into used,mine
    from public.hq_work_material_units_v1199c122 e
    join public.hq_works_v1500 ew on ew.id=e.work_id
    where e.lot_id=l.id and e.unit_no=n and e.cancelled_at is null
      and ew.kind='下処理' and ew.status<>'取消';
    remaining:=greatest(round(total-used,6),0);
    units:=units||jsonb_build_array(jsonb_build_object('no',n,'total',total,'used',round(used,6),
      'remaining',remaining,'mine',round(mine,6),'state',case when used=0 then 'unused' when remaining>0 then 'partial' else 'done' end));
  end loop;
  select (value->>'no')::integer into next_no from jsonb_array_elements(units)
    where value->>'state'='partial' order by (value->>'no')::integer limit 1;
  if next_no is null then
    select (value->>'no')::integer into next_no from jsonb_array_elements(units)
      where value->>'state'='unused' order by (value->>'no')::integer limit 1;
  end if;
  available:=public.hq_c117_available_qty(l.id,p_work_id);
  pack:=case when l.unit='kg' then null else public.hq_c117_lot_pack_kg(l) end;
  return jsonb_build_object('ok',true,'lot_id',l.id,'lot_no',l.lot_no,'item_name',l.item_name,
    'qty_unit',case when l.unit='kg' then 'kg' else 'ケース' end,'large',(definition->>'source')='container',
    'pack_kg',pack,'source',definition->>'source','units',units,'next_no',next_no,'lot_available',available);
end $f$;

create or replace function public.hq_work_pallet_use_v1199c122(
  p_work_id uuid,p_lot_id uuid,p_unit_no integer,p_mode text,p_remaining numeric,p_unit_total numeric,p_operation_id uuid
) returns jsonb language plpgsql security definer set search_path to ''
as $f$
declare v public.profiles; w public.hq_works_v1500%rowtype; l public.hq_lots_v1400%rowtype;
  mt public.hq_work_materials_v1500%rowtype; old public.hq_work_material_units_v1199c122%rowtype;
  definition jsonb; x jsonb; source text; v_unit_total numeric; before_qty numeric; used numeric; remaining numeric; updated timestamptz;
begin
  v:=public.hq_actor_v1400(array['admin','hq_worker','hq_prep']);
  if p_operation_id is null then raise exception '操作IDが必要です'; end if;
  select * into old from public.hq_work_material_units_v1199c122 where operation_id=p_operation_id for update;
  if found then
    if old.work_id=p_work_id and old.lot_id=p_lot_id and old.unit_no is not distinct from p_unit_no
       and old.mode=p_mode and old.remaining_qty is not distinct from (case when p_mode='全量' then 0 else round(p_remaining,6) end) then
      return jsonb_build_object('ok',true,'already',true,'entry_id',old.id,'material_id',old.material_id,
        'used_qty',old.used_qty,'remaining_qty',old.remaining_qty,'unit_total',old.unit_total,'unit_no',old.unit_no);
    end if;
    raise exception 'この操作IDは別の内容で使われています';
  end if;
  if p_mode not in ('全量','半端') then raise exception '使用方法は全量か半端を選んでください'; end if;
  if p_unit_total is not null and (p_unit_total<0 or p_unit_total::text in ('NaN','Infinity','-Infinity')) then raise exception '元の量は0より大きい数で入れてください'; end if;
  if p_remaining is not null and (p_remaining<0 or p_remaining::text in ('NaN','Infinity','-Infinity')) then raise exception '残りは正しい数で入れてください'; end if;
  select * into w from public.hq_works_v1500 where id=p_work_id for update;
  if not found then raise exception '下処理が見つかりません'; end if;
  if w.kind<>'下処理' or w.status<>'作業中' or w.confirm_status<>'未確定' then raise exception '原料の使用は未確定の作業中の下処理だけ記録できます'; end if;
  select * into l from public.hq_lots_v1400 where id=p_lot_id for update;
  if not found then raise exception '原料が見つかりません'; end if;
  if l.item_name<>w.raw_item_name then raise exception '原料 %（%）は、この下処理の原料（%）と違います',l.lot_no,l.item_name,w.raw_item_name; end if;
  if l.status<>'在庫あり' or coalesce(l.current_qty,0)<=0 then raise exception '原料 % は在庫ありで、残数があるロットだけ追加できます',l.lot_no; end if;
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
  if source='manual' or p_unit_no is null then
    before_qty:=v_unit_total;
  else
    select v_unit_total-coalesce(sum(e.used_qty),0) into before_qty
    from public.hq_work_material_units_v1199c122 e join public.hq_works_v1500 ew on ew.id=e.work_id
    where e.lot_id=l.id and e.unit_no=p_unit_no and e.cancelled_at is null and ew.kind='下処理' and ew.status<>'取消';
    before_qty:=round(before_qty,6);
  end if;
  if before_qty<=0 then raise exception 'このパレット（基）は、もう使い切っています'; end if;
  if p_mode='全量' then used:=before_qty; remaining:=0;
  else
    if p_remaining is null or p_remaining<=0 or p_remaining>=before_qty then
      raise exception '残りは、0より大きく%より小さい数で入れてください',before_qty;
    end if;
    remaining:=round(p_remaining,6); used:=round(before_qty-remaining,6);
  end if;
  if used<=0 then raise exception '使用量は0より大きくしてください'; end if;
  insert into public.hq_work_material_units_v1199c122(work_id,material_id,lot_id,unit_no,unit_total,mode,used_qty,remaining_qty,operation_id,created_by_name)
  values(w.id,mt.id,l.id,p_unit_no,v_unit_total,p_mode,used,remaining,p_operation_id,v.display_name) returning * into old;
  update public.hq_work_materials_v1500 set qty=coalesce(qty,0)+used where id=mt.id returning * into mt;
  perform public.hq_c117_guard_reservations(w.id);
  update public.hq_works_v1500 set history=history||jsonb_build_array(jsonb_build_object(
    'at',now(),'by',v.display_name,'action','パレット／基の使用を記録','lot_id',l.id,'material_id',mt.id,
    'unit_no',p_unit_no,'mode',p_mode,'used',used,'remaining',remaining)),updated_at=now() where id=w.id returning updated_at into updated;
  return jsonb_build_object('ok',true,'entry_id',old.id,'material_id',mt.id,'used_qty',used,'remaining_qty',remaining,
    'material_qty',mt.qty,'unit_total',v_unit_total,'unit_no',p_unit_no,'updated_at',updated);
end $f$;

create or replace function public.hq_work_pallet_cancel_v1199c122(p_work_id uuid,p_entry_id uuid)
returns jsonb language plpgsql security definer set search_path to ''
as $f$
declare v public.profiles; w public.hq_works_v1500%rowtype; e public.hq_work_material_units_v1199c122%rowtype;
  mt public.hq_work_materials_v1500%rowtype; updated timestamptz;
begin
  v:=public.hq_actor_v1400(array['admin','hq_worker','hq_prep']);
  select * into w from public.hq_works_v1500 where id=p_work_id for update;
  if not found or w.kind<>'下処理' or w.status<>'作業中' or w.confirm_status<>'未確定' then raise exception '原料の使用取消は未確定の作業中の下処理だけできます'; end if;
  select * into e from public.hq_work_material_units_v1199c122 where id=p_entry_id and work_id=w.id for update;
  if not found then raise exception '使用記録が見つかりません'; end if;
  if e.cancelled_at is not null then return jsonb_build_object('ok',true,'already',true); end if;
  select * into mt from public.hq_work_materials_v1500 where id=e.material_id and work_id=w.id for update;
  if not found then raise exception '使用原料が見つかりません'; end if;
  update public.hq_work_material_units_v1199c122 set cancelled_at=now(),cancelled_by_name=v.display_name where id=e.id;
  update public.hq_work_materials_v1500 set qty=greatest(coalesce(qty,0)-e.used_qty,0) where id=mt.id returning * into mt;
  perform public.hq_c117_guard_reservations(w.id);
  update public.hq_works_v1500 set history=history||jsonb_build_array(jsonb_build_object(
    'at',now(),'by',v.display_name,'action','パレット／基の使用を取り消し','lot_id',e.lot_id,'material_id',e.material_id,
    'unit_no',e.unit_no,'used',e.used_qty)),updated_at=now() where id=w.id returning updated_at into updated;
  return jsonb_build_object('ok',true,'entry_id',e.id,'material_id',mt.id,'material_qty',mt.qty,'updated_at',updated);
end $f$;

create or replace function public.hq_work_pallet_list_v1199c122(p_work_ids uuid[])
returns jsonb language plpgsql stable security definer set search_path to ''
as $f$
begin
  perform public.hq_actor_v1400(array['admin','hq_worker','hq_prep']);
  return coalesce((select jsonb_agg(jsonb_build_object(
    'entry_id',e.id,'work_id',e.work_id,'material_id',e.material_id,'lot_id',e.lot_id,'unit_no',e.unit_no,
    'unit_total',e.unit_total,'mode',e.mode,'used_qty',e.used_qty,'remaining_qty',e.remaining_qty,
    'created_at',e.created_at,'created_by_name',e.created_by_name) order by e.created_at,e.id)
    from public.hq_work_material_units_v1199c122 e where e.work_id=any(coalesce(p_work_ids,'{}'::uuid[])) and e.cancelled_at is null),'[]'::jsonb);
end $f$;

do $block$
declare f text;
begin
  foreach f in array array[
    'public.hq_pallet_candidates_v1199c122(uuid,uuid)',
    'public.hq_work_pallet_use_v1199c122(uuid,uuid,integer,text,numeric,numeric,uuid)',
    'public.hq_work_pallet_cancel_v1199c122(uuid,uuid)',
    'public.hq_work_pallet_list_v1199c122(uuid[])'
  ] loop
    execute format('revoke all on function %s from public, anon',f);
    execute format('grant execute on function %s to authenticated, service_role',f);
  end loop;
  execute 'revoke all on function public.hq_c122_units(public.hq_lots_v1400) from public, anon, authenticated, service_role';
end $block$;
commit;
notify pgrst,'reload schema';

/* 成功の確かめ方：下の6行がすべてOKなら成功です。 */
select 'c122使用記録表' as 確認,case when to_regclass('public.hq_work_material_units_v1199c122') is not null then 'OK' else 'NG' end as 結果
union all select 'c122候補RPC',case when to_regprocedure('public.hq_pallet_candidates_v1199c122(uuid,uuid)') is not null then 'OK' else 'NG' end
union all select 'c122使用RPC',case when to_regprocedure('public.hq_work_pallet_use_v1199c122(uuid,uuid,integer,text,numeric,numeric,uuid)') is not null then 'OK' else 'NG' end
union all select 'c122取消RPC',case when to_regprocedure('public.hq_work_pallet_cancel_v1199c122(uuid,uuid)') is not null then 'OK' else 'NG' end
union all select 'c122一覧RPC',case when to_regprocedure('public.hq_work_pallet_list_v1199c122(uuid[])') is not null then 'OK' else 'NG' end
union all select 'c122使用記録表権限',case when not has_table_privilege('authenticated','public.hq_work_material_units_v1199c122','select,insert,update,delete') then 'OK' else 'NG' end;
