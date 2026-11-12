/*
045_本社下処理_訂正と休憩と同時製造.sql（v1.199-c116）

前提：019・022・042を実行済みであること。

下処理の訂正、休憩・中断、キャベツ1/4芯と1/4葉の同時製造を追加します。
原料・廃棄・在庫の既存履歴は消さず、訂正・取消時も復元できる履歴を残します。
何度実行しても同じ定義にできます。SQLだけでは画面は変わりません。
*/
begin;

-- 045 は、019/022/042 がある本番だけに適用する。
do $block$
begin
  if to_regclass('public.hq_works_v1500') is null
     or to_regclass('public.hq_work_materials_v1500') is null
     or to_regclass('public.hq_work_members_v1500') is null
     or to_regprocedure('public.hq_actor_v1400(text[])') is null
     or to_regprocedure('public.hq_work_add_material_v1199c112(uuid,uuid)') is null
     or to_regclass('public.hq_deleted_works_v1500') is null then
    raise exception '先に db/019、022、042 を番号順に実行してください';
  end if;
end $block$;

-- 作業の現在の表示用。旧作業は空配列のまま読み、関数側で従来の prep_master_id を補います。
alter table public.hq_works_v1500 add column if not exists pause_kind text not null default '';
alter table public.hq_works_v1500 add column if not exists outputs jsonb not null default '[]'::jsonb;
alter table public.hq_works_v1500 drop constraint if exists hq_works_v1500_pause_kind_check;
alter table public.hq_works_v1500 add constraint hq_works_v1500_pause_kind_check
  check (pause_kind in ('','休憩','中断'));
alter table public.hq_works_v1500 drop constraint if exists hq_works_v1500_outputs_array_check;
alter table public.hq_works_v1500 add constraint hq_works_v1500_outputs_array_check
  check (jsonb_typeof(outputs) = 'array');

-- 既存の履歴種類を残したまま、訂正の差分履歴だけを追加する。
-- 019後に追加された種類も、列挙し直して失わないよう現在の制約から復元する。
do $block$
declare v_def text; v_expression text;
begin
  select pg_get_constraintdef(c.oid) into v_def from pg_constraint c
    where c.conrelid='public.hq_lot_movements_v1400'::regclass
      and c.conname='hq_lot_movements_v1400_movement_type_check';
  if v_def is null then raise exception 'hq_lot_movements_v1400 の履歴種類制約が見つかりません'; end if;
  if position('下処理訂正取消' in v_def)=0 then
    v_expression:=substring(v_def from 8 for length(v_def)-8);
    execute 'alter table public.hq_lot_movements_v1400 drop constraint hq_lot_movements_v1400_movement_type_check';
    execute format('alter table public.hq_lot_movements_v1400 add constraint hq_lot_movements_v1400_movement_type_check check ((%s) or movement_type in (%L,%L))',v_expression,'下処理訂正','下処理訂正取消');
  end if;
end $block$;

create table if not exists public.hq_work_pauses_v1199c116 (
  id uuid primary key default gen_random_uuid(),
  operation_id uuid not null unique,
  work_id uuid not null references public.hq_works_v1500(id) on delete cascade,
  kind text not null check (kind in ('休憩','中断','後入力休憩')),
  start_at timestamptz not null,
  end_at timestamptz,
  staff_ids uuid[] not null default '{}',
  resumed_staff_ids uuid[] not null default '{}',
  by_name text,
  excluded_staff_ids uuid[] not null default '{}',
  resume_operation_id uuid unique,
  created_at timestamptz not null default now(),
  check (end_at is null or end_at > start_at)
);
create index if not exists hq_work_pauses_v1199c116_work_idx
  on public.hq_work_pauses_v1199c116(work_id, start_at desc);

-- operation_id の再送内容と結果を保持する。訂正は同一IDで二重に在庫を動かさない。
create table if not exists public.hq_prep_operations_v1199c116 (
  operation_id uuid primary key,
  work_id uuid references public.hq_works_v1500(id) on delete set null,
  action text not null check (action in ('訂正','再開')),
  input jsonb not null,
  result jsonb,
  created_by_name text,
  created_at timestamptz not null default now(),
  completed_at timestamptz

);

-- 045を再実行した場合も、削除済み作業に新表の外部キーが残らないようにする。
alter table public.hq_work_pauses_v1199c116 drop constraint if exists hq_work_pauses_v1199c116_work_id_fkey;
alter table public.hq_work_pauses_v1199c116 add constraint hq_work_pauses_v1199c116_work_id_fkey
  foreign key (work_id) references public.hq_works_v1500(id) on delete cascade;
alter table public.hq_prep_operations_v1199c116 drop constraint if exists hq_prep_operations_v1199c116_work_id_fkey;
alter table public.hq_prep_operations_v1199c116 add constraint hq_prep_operations_v1199c116_work_id_fkey
  foreign key (work_id) references public.hq_works_v1500(id) on delete set null;

-- 045で追加した表は、ログイン中の人は読むだけ。変更はSECURITY DEFINER関数からだけ行う。
do $block$
declare t text;
begin
  foreach t in array array['hq_work_pauses_v1199c116','hq_prep_operations_v1199c116'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    execute format('create policy %I on public.%I for select to authenticated using (true)', t || '_read', t);
    execute format('revoke all on public.%I from anon, public', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('grant all on public.%I to service_role', t);
  end loop;
end $block$;

-- JSON中の数値は、null/NaN/Infinity/負数を受け付けない。
create or replace function public.hq_c116_nonnegative(p_value text, p_label text)
returns numeric language plpgsql immutable security definer set search_path to ''
as $f$
declare v numeric;
begin
  if nullif(btrim(coalesce(p_value,'')),'') is null then
    raise exception '%を入れてください', p_label;
  end if;
  begin v := p_value::numeric; exception when others then raise exception '%は0以上の数字で入れてください', p_label; end;
  if v < 0 or v::text in ('NaN','Infinity','-Infinity') then
    raise exception '%は0以上の数字で入れてください', p_label;
  end if;
  return v;
end $f$;

-- クライアントが渡した出力IDと数量だけを受け、名前・賞味期限は必ずDBマスタから作り直す。
create or replace function public.hq_c116_outputs(
  p_master_ids uuid[], p_outputs jsonb
) returns jsonb language plpgsql security definer set search_path to ''
as $f$
declare r jsonb; v_id uuid; v_qty numeric; v_count integer; v_result jsonb;
begin
  if jsonb_typeof(coalesce(p_outputs,'[]'::jsonb)) <> 'array' then
    raise exception '出来高の形が正しくありません';
  end if;
  if coalesce(array_length(p_master_ids,1),0) < 1
     or (select count(*) from unnest(p_master_ids) x) <> (select count(distinct x) from unnest(p_master_ids) x) then
    raise exception '仕掛品を正しく選んでください';
  end if;
  if jsonb_array_length(p_outputs) <> array_length(p_master_ids,1) then
    raise exception '選んだ仕掛品すべての出来高を入れてください';
  end if;
  for r in select value from jsonb_array_elements(p_outputs) loop
    if jsonb_typeof(r) <> 'object' then raise exception '出来高の形が正しくありません'; end if;
    begin v_id := (r->>'master_id')::uuid; exception when others then raise exception '仕掛品を正しく選んでください'; end;
    if v_id is null or not (v_id = any(p_master_ids)) then raise exception '選んでいない仕掛品は登録できません'; end if;
    v_qty := public.hq_c116_nonnegative(r->>'yield_kg','出来高（kg）');
  end loop;
  select count(*) into v_count
  from (select (value->>'master_id')::uuid id from jsonb_array_elements(p_outputs)) x;
  if v_count <> (select count(distinct (value->>'master_id')::uuid) from jsonb_array_elements(p_outputs))
     or exists(select 1 from jsonb_array_elements(p_outputs) x where nullif(btrim(x.value->>'master_id'),'') is null) then
    raise exception '同じ仕掛品を重複して登録できません';
  end if;
  if exists (
    select 1 from unnest(p_master_ids) id
    where not exists (select 1 from jsonb_array_elements(p_outputs) x where (x->>'master_id')::uuid = id)
  ) then
    raise exception '選んだ仕掛品すべての出来高を入れてください';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('master_id',m.id,'name',m.name,
      'expiry_days',m.expiry_days,'yield_kg',public.hq_c116_nonnegative(x.value->>'yield_kg','出来高（kg）')) order by m.id),'[]'::jsonb)
  into v_result
  from public.hq_prep_masters_v1500 m
  join lateral (
    select value from jsonb_array_elements(p_outputs) where (value->>'master_id')::uuid=m.id
  ) x on true
  where m.id = any(p_master_ids); -- 開始時の有効判定は validate_master_set、過去作業の訂正は停止済みマスタも許可する。
  if jsonb_array_length(v_result) <> array_length(p_master_ids,1) then
    raise exception '仕掛品が見つかりません';
  end if;
  return v_result;
end $f$;

-- 作業に結び付く出力マスタ。旧作業は prep_master_id から1件として扱う。
create or replace function public.hq_c116_work_master_ids(p_work public.hq_works_v1500)
returns uuid[] language sql stable security definer set search_path to ''
as $f$
  select case when jsonb_array_length(coalesce(p_work.outputs,'[]'::jsonb)) > 0
    then array(select (value->>'master_id')::uuid from jsonb_array_elements(p_work.outputs) order by (value->>'master_id')::uuid)
    when p_work.prep_master_id is not null then array[p_work.prep_master_id]
    else '{}'::uuid[] end
$f$;

create or replace function public.hq_c116_work_outputs(p_work public.hq_works_v1500,p_outputs jsonb)
returns jsonb language sql security definer set search_path to ''
as $f$
  select jsonb_agg(value || jsonb_build_object(
    'name',coalesce(previous->>'name',p_work.product_name,value->>'name'),
    'expiry_days',coalesce(previous->'expiry_days',to_jsonb(p_work.expiry_days),value->'expiry_days')) order by value->>'master_id')
  from jsonb_array_elements(public.hq_c116_outputs(public.hq_c116_work_master_ids(p_work),p_outputs)) current(value)
  left join lateral (
    select value as previous from jsonb_array_elements(p_work.outputs)
      where value->>'master_id'=current.value->>'master_id'
  ) old on true
$f$;

-- 同時製造は「キャベツ」の1/4芯・1/4葉の組だけに限定する。
create or replace function public.hq_c116_validate_master_set(p_master_ids uuid[])
returns void language plpgsql security definer set search_path to ''
as $f$
declare n integer; m record;
begin
  n := coalesce(array_length(p_master_ids,1),0);
  if n not in (1,2) or (select count(*) from unnest(p_master_ids) x) <> n
     or (select count(*) from public.hq_prep_masters_v1500 where id=any(p_master_ids) and active) <> n then
    raise exception '仕掛品を正しく選んでください';
  end if;
  if n = 2 then
    if not exists (
      select 1 from public.hq_prep_masters_v1500 a join public.hq_prep_masters_v1500 b on a.id<>b.id
      where a.id=any(p_master_ids) and b.id=any(p_master_ids)
        and a.item_name='キャベツ' and b.item_name='キャベツ'
        and ((regexp_replace(a.name,'[[:space:]　]','','g')='1/4芯' and regexp_replace(b.name,'[[:space:]　]','','g')='1/4葉')
          or (regexp_replace(a.name,'[[:space:]　]','','g')='1/4葉' and regexp_replace(b.name,'[[:space:]　]','','g')='1/4芯'))
    ) then
      raise exception '同時製造できるのは、キャベツの「1/4芯」と「1/4葉」の組だけです';
    end if;
  end if;
end $f$;

-- 原料の入力を現在の作業に保存する共通処理。保存時は在庫を動かさない。
create or replace function public.hq_c116_save_inputs(
  p_work_id uuid, p_materials jsonb, p_waste_kg numeric, p_outputs jsonb, p_by public.profiles
) returns jsonb language plpgsql security definer set search_path to ''
as $f$
declare w public.hq_works_v1500%rowtype; ids uuid[]; r jsonb; v_id uuid; v_qty numeric; v_outputs jsonb; v_yield numeric;
begin
  if jsonb_typeof(coalesce(p_materials,'[]'::jsonb)) <> 'array' then raise exception '使用原料の形が正しくありません'; end if;
  if p_waste_kg is null or p_waste_kg < 0 or p_waste_kg::text in ('NaN','Infinity','-Infinity') then
    raise exception '廃棄（kg）は0以上の数字で入れてください';
  end if;
  select * into w from public.hq_works_v1500 where id=p_work_id for update;
  if not found or w.kind <> '下処理' then raise exception '下処理が見つかりません'; end if;
  if w.status='作業中' then raise exception '先に「作業終了」をしてください'; end if;
  if w.status='取消' or w.confirm_status <> '未確定' then raise exception 'この下処理は確定済みか取消済みです。訂正画面から直してください'; end if;
  if w.pause_kind <> '' then raise exception '休憩・中断中の作業は、先に再開するか休憩を終えてください'; end if;
  ids := array(select id from public.hq_work_materials_v1500 where work_id=w.id order by id);
  if jsonb_array_length(p_materials) <> coalesce(array_length(ids,1),0) then raise exception 'すべての原料の使用数を入れてください'; end if;
  if exists(select 1 from jsonb_array_elements(p_materials) x where jsonb_typeof(x.value)<>'object') then raise exception '使用原料の形が正しくありません'; end if;
  if exists(select 1 from jsonb_array_elements(p_materials) x group by x.value->>'id' having count(*)>1) then raise exception '同じ原料を重複して登録できません'; end if;
  for r in select value from jsonb_array_elements(p_materials) loop
    begin v_id := (r->>'id')::uuid; exception when others then raise exception '使用原料が見つかりません'; end;
    if v_id is null or not (v_id=any(ids)) then raise exception '使用原料が見つかりません'; end if;
    v_qty := public.hq_c116_nonnegative(r->>'qty','使用原料の数');
    update public.hq_work_materials_v1500 set qty=v_qty where id=v_id and work_id=w.id;
  end loop;
  v_outputs := public.hq_c116_work_outputs(w,p_outputs);
  select coalesce(sum((value->>'yield_kg')::numeric),0) into v_yield from jsonb_array_elements(v_outputs);
  update public.hq_works_v1500 set waste_kg=p_waste_kg, yield_kg=v_yield, outputs=v_outputs,
    inputs_saved_at=now(), inputs_saved_by_name=p_by.display_name, updated_at=now()
  where id=w.id;
  return jsonb_build_object('ok',true,'yield_kg',v_yield,'outputs',v_outputs);
end $f$;

-- 新しい開始RPC。単一製造は従来どおり、許可された同時製造だけoutputsを2件で開始する。
create or replace function public.hq_work_start_v1199c116(
  p_operation_id uuid, p_kind text, p_task_name text, p_place text,
  p_master_ids uuid[], p_lot_ids uuid[], p_staff_ids uuid[]
) returns jsonb language plpgsql security definer set search_path to ''
as $f$
declare v public.profiles; w public.hq_works_v1500%rowtype; m public.hq_prep_masters_v1500%rowtype;
  lot public.hq_lots_v1400%rowtype; ids uuid[]; v_outputs jsonb; v_product text; v_expiry integer; v_task text;
begin
  v := public.hq_actor_v1400(array['admin','hq_worker','hq_prep']);
  if p_operation_id is null then raise exception 'operation_idが必要です'; end if;
  select * into w from public.hq_works_v1500 where operation_id=p_operation_id for update;
  if found then return jsonb_build_object('ok',true,'already',true,'id',w.id); end if;
  if p_kind <> '下処理' then
    if coalesce(array_length(p_master_ids,1),0) > 0 then raise exception '下処理以外に仕掛品は指定できません'; end if;
    return public.hq_work_start_v1500(p_operation_id,p_kind,p_task_name,p_place,null,p_lot_ids,p_staff_ids);
  end if;
  if coalesce(array_length(p_staff_ids,1),0)<1 then raise exception '作業する人のスタッフQRを読み取ってください'; end if;
  if coalesce(array_length(p_lot_ids,1),0)<1 then raise exception '原料のQRを読み取ってください'; end if;
  perform public.hq_c116_validate_master_set(p_master_ids);
  select item_name into v_task from public.hq_prep_masters_v1500 where id=p_master_ids[1];
  if exists(select 1 from public.hq_prep_masters_v1500 where id=any(p_master_ids) and item_name<>v_task) then
    raise exception '同時製造の原料品目が一致しません';
  end if;
  ids := array(select distinct x from unnest(p_lot_ids) x order by x);
  if array_length(ids,1) <> array_length(p_lot_ids,1) then raise exception '同じ原料ロットを重複して読み取れません'; end if;
  for lot in select * from public.hq_lots_v1400 where id=any(ids) order by id for update loop
    if lot.status not in ('在庫あり','在庫なし') then raise exception '原料 % は受け入れが確定していません',lot.lot_no; end if;
    if lot.item_name<>v_task then raise exception '原料 %（%）は、選んだ仕掛品の原料（%）と違います',lot.lot_no,lot.item_name,v_task; end if;
  end loop;
  if (select count(*) from public.hq_lots_v1400 where id=any(ids)) <> array_length(ids,1) then raise exception '原料が見つかりません'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('master_id',id,'name',name,'expiry_days',expiry_days,'yield_kg',0) order by id),'[]'::jsonb),
      string_agg(name,'・' order by id), max(expiry_days)
  into v_outputs,v_product,v_expiry from public.hq_prep_masters_v1500 where id=any(p_master_ids);
  insert into public.hq_works_v1500(operation_id,kind,task_name,place,work_date,status,prep_master_id,raw_item_name,
    product_name,expiry_days,outputs,started_at,created_by_name,history)
  values(p_operation_id,'下処理','下処理',nullif(btrim(coalesce(p_place,'')),''),(now() at time zone 'Asia/Tokyo')::date,'作業中',
    p_master_ids[1],v_task,v_product,v_expiry,v_outputs,now(),v.display_name,
    jsonb_build_array(jsonb_build_object('at',now(),'by',v.display_name,'action','下処理開始','outputs',v_outputs)))
  returning * into w;
  insert into public.hq_work_materials_v1500(work_id,lot_id,lot_no,item_name,unit,pack_kg)
  select w.id,l.id,l.lot_no,l.item_name,l.unit,case when l.unit='kg' then null else public.hq_pack_kg_v1500(l.pack_weight) end
  from public.hq_lots_v1400 l where l.id=any(ids);
  perform public.hq_work_add_members_v1500(w.id,p_staff_ids,'作業');
  return jsonb_build_object('ok',true,'id',w.id,'outputs',v_outputs);
end $f$;

-- 新しい保存RPC。outputs合計をyield_kgへ保存する。
create or replace function public.hq_work_save_inputs_v1199c116(
  p_work_id uuid, p_materials jsonb, p_waste_kg numeric, p_outputs jsonb
) returns jsonb language plpgsql security definer set search_path to ''
as $f$
declare v public.profiles;
begin
  v := public.hq_actor_v1400(array['admin','hq_worker','hq_prep']);
  return public.hq_c116_save_inputs(p_work_id,p_materials,p_waste_kg,p_outputs,v);
end $f$;

-- 確定時は、現在保存されている原料使用数だけを在庫から引く。既存の履歴は変更しない。
create or replace function public.hq_prep_confirm_v1199c116(
  p_work_id uuid, p_materials jsonb, p_waste_kg numeric, p_outputs jsonb, p_reason text
) returns jsonb language plpgsql security definer set search_path to ''
as $f$
declare v public.profiles; w public.hq_works_v1500%rowtype; mt public.hq_work_materials_v1500%rowtype;
  l public.hq_lots_v1400%rowtype; v_after numeric; v_mid uuid; v_apply boolean; v_saved jsonb;
  v_existing_materials jsonb; v_new_outputs jsonb; v_saved_outputs jsonb;
begin
  v := public.hq_actor_v1400(array['admin','hq_worker']);
  select * into w from public.hq_works_v1500 where id=p_work_id for update;
  if not found or w.kind<>'下処理' then raise exception '下処理が見つかりません'; end if;
  -- 送信結果を受け取れなかった同じ初回確定は、在庫を二重に動かさず成功として返す。
  if w.confirm_status='確定' then
    if jsonb_typeof(coalesce(p_materials,'[]'::jsonb))<>'array' or p_waste_kg is null then
      raise exception '確定済みの下処理は訂正画面から直してください';
    end if;
    select coalesce(jsonb_agg(jsonb_build_object('id',id,'qty',coalesce(qty,0)) order by id),'[]'::jsonb)
      into v_existing_materials from public.hq_work_materials_v1500 where work_id=w.id;
    v_new_outputs := public.hq_c116_work_outputs(w,p_outputs);
    if v_existing_materials = (select coalesce(jsonb_agg(jsonb_build_object('id',(x.value->>'id')::uuid,'qty',public.hq_c116_nonnegative(x.value->>'qty','使用原料の数')) order by (x.value->>'id')::uuid),'[]'::jsonb) from jsonb_array_elements(p_materials) x)
       and coalesce(w.waste_kg,0)=p_waste_kg and v_new_outputs=w.outputs then
      return jsonb_build_object('ok',true,'already',true,'stock_applied',w.stock_applied,'outputs',w.outputs);
    end if;
    raise exception '確定済みの下処理は訂正画面から直してください';
  end if;
  if w.status in ('作業中','取消') or w.confirm_status='取消' then raise exception 'この下処理は確定できません'; end if;
  -- 初回確定は従来どおり理由不要。理由があれば履歴に残すが、訂正だけ必須にする。
  v_saved := public.hq_c116_save_inputs(p_work_id,p_materials,p_waste_kg,p_outputs,v);
  select * into w from public.hq_works_v1500 where id=p_work_id for update;
  v_apply := public.hq_setting_on_v1500('stage2_stock');
  if v_apply then
    for mt in select * from public.hq_work_materials_v1500 where work_id=w.id and coalesce(qty,0)>0 order by lot_id for update loop
      select * into l from public.hq_lots_v1400 where id=mt.lot_id for update;
      if l.status not in ('在庫あり','在庫なし') then raise exception '原料 % は受け入れ済みではありません',l.lot_no; end if;
      if mt.item_name<>w.raw_item_name then raise exception '原料品目が一致しません'; end if;
      if mt.qty>l.current_qty then raise exception '原料 % の在庫が不足しています',l.lot_no; end if;
      v_after := l.current_qty-mt.qty;
      update public.hq_lots_v1400 set current_qty=v_after,status=case when v_after>0 then '在庫あり' else '在庫なし' end,updated_at=now() where id=l.id;
      insert into public.hq_lot_movements_v1400(operation_id,lot_id,movement_type,qty,unit,before_qty,after_qty,destination,memo,item_name,lot_no,user_id,user_name,occurred_at,work_id)
      values(gen_random_uuid(),l.id,'下処理使用',mt.qty,l.unit,l.current_qty,v_after,'下処理',w.product_name,l.item_name,l.lot_no,v.id,v.display_name,coalesce(w.ended_at,w.started_at),w.id)
      returning id into v_mid;
      update public.hq_work_materials_v1500 set movement_id=v_mid where id=mt.id;
    end loop;
  end if;
  update public.hq_waste_v1500 set cancelled_at=now(),cancelled_by_name=v.display_name
    where work_id=w.id and kind='下処理ロス' and cancelled_at is null;
  if p_waste_kg>0 then
    insert into public.hq_waste_v1500(kind,waste_date,item_name,kg,work_id,memo,user_name)
    values('下処理ロス',w.work_date,coalesce(w.raw_item_name,w.product_name),p_waste_kg,w.id,w.product_name,v.display_name);
  end if;
  update public.hq_works_v1500 set confirm_status='確定',confirmed_at=now(),confirmed_by_name=v.display_name,stock_applied=v_apply,
    history=history||jsonb_build_array(jsonb_strip_nulls(jsonb_build_object('at',now(),'by',v.display_name,'action','確定',
      'reason',nullif(btrim(coalesce(p_reason,'')),''),'stock',v_apply,'after',v_saved))), updated_at=now() where id=w.id;
  return jsonb_build_object('ok',true,'stock_applied',v_apply,'outputs',v_saved->'outputs');
end $f$;

-- 確定後訂正。先に対象ロットをUUID順でロックし、旧使用数-新使用数の差だけを現在在庫へ反映する。
create or replace function public.hq_prep_correct_v1199c116(
  p_work_id uuid, p_operation_id uuid, p_expected_updated_at timestamptz,
  p_materials jsonb, p_waste_kg numeric, p_outputs jsonb, p_reason text
) returns jsonb language plpgsql security definer set search_path to ''
as $f$
declare v public.profiles; w public.hq_works_v1500%rowtype; r jsonb; mt public.hq_work_materials_v1500%rowtype;
  lot public.hq_lots_v1400%rowtype; v_lot_id uuid; v_qty numeric; ids uuid[]; v_input jsonb; v_existing public.hq_prep_operations_v1199c116%rowtype;
  v_outputs jsonb; v_yield numeric; v_old jsonb; v_after jsonb; v_delta numeric; v_before numeric; v_stock_after numeric; v_mid uuid;
begin
  v := public.hq_actor_v1400(array['admin','hq_worker']);
  if p_operation_id is null then raise exception 'operation_idが必要です'; end if;
  if p_expected_updated_at is null then raise exception '画面を開いた時刻が必要です。画面を開き直してください'; end if;
  if btrim(coalesce(p_reason,''))='' then raise exception '訂正理由を入れてください'; end if;
  if jsonb_typeof(coalesce(p_materials,'[]'::jsonb))<>'array' then raise exception '使用原料の形が正しくありません'; end if;
  if p_waste_kg is null or p_waste_kg<0 or p_waste_kg::text in ('NaN','Infinity','-Infinity') then raise exception '廃棄（kg）は0以上の数字で入れてください'; end if;
  -- expected_updated_at は初回の競合検知だけに使う。再送比較には入れず、成功後のupdated_at変更で再送を壊さない。
  v_input := jsonb_build_object('work_id',p_work_id,'materials',p_materials,
    'waste_kg',p_waste_kg,'outputs',p_outputs,'reason',btrim(p_reason));
  insert into public.hq_prep_operations_v1199c116(operation_id,work_id,action,input,created_by_name)
  values(p_operation_id,p_work_id,'訂正',v_input,v.display_name) on conflict(operation_id) do nothing;
  if not found then
    select * into v_existing from public.hq_prep_operations_v1199c116 where operation_id=p_operation_id for update;
    if not found then raise exception '訂正操作を確認できません。再度実行してください'; end if;
    if v_existing.action<>'訂正' or v_existing.input is distinct from v_input then
      return jsonb_build_object('ok',false,'idempotency_conflict',true,'message','同じoperation_idに異なる内容は使えません');
    end if;
    if v_existing.result is null then raise exception '同じ訂正が処理中です。しばらく待ってから再表示してください'; end if;
    return v_existing.result || jsonb_build_object('idempotent',true);
  end if;
  select * into w from public.hq_works_v1500 where id=p_work_id for update;
  if not found or w.kind<>'下処理' then raise exception '下処理が見つかりません'; end if;
  if w.inputs_saved_at is null or w.ended_at is null then raise exception '作業終了後に入力済みの下処理だけ訂正できます'; end if;
  if w.confirm_status='取消' or w.status='取消' then raise exception '取消済みの下処理は訂正できません'; end if;
  if w.updated_at is distinct from p_expected_updated_at then
    update public.hq_prep_operations_v1199c116 set result=jsonb_build_object('ok',false,'conflict',true,
      'current_updated_at',w.updated_at,'message','他の操作で内容が変わりました。画面を開き直してください'),completed_at=now()
      where operation_id=p_operation_id;
    return (select result from public.hq_prep_operations_v1199c116 where operation_id=p_operation_id);
  end if;
  if p_materials is null or jsonb_array_length(p_materials)=0
     or exists(select 1 from jsonb_array_elements(p_materials) x where jsonb_typeof(x.value)<>'object' or nullif(btrim(x.value->>'lot_id'),'') is null)
     or exists(select 1 from jsonb_array_elements(p_materials) x group by x.value->>'lot_id' having count(*)>1) then
    raise exception '原料ロットを重複なく指定してください';
  end if;
  ids := array(select distinct lot_id from public.hq_work_materials_v1500 where work_id=w.id
    union select (value->>'lot_id')::uuid from jsonb_array_elements(p_materials) order by 1);
  for lot in select * from public.hq_lots_v1400 where id=any(ids) order by id for update loop
    if lot.status not in ('在庫あり','在庫なし') then raise exception '原料 % は受け入れ済みではありません',lot.lot_no; end if;
    if lot.item_name<>w.raw_item_name then raise exception '原料 %（%）は、この下処理の原料（%）と違います',lot.lot_no,lot.item_name,w.raw_item_name; end if;
  end loop;
  if (select count(*) from public.hq_lots_v1400 where id=any(ids))<>coalesce(array_length(ids,1),0) then raise exception '原料が見つかりません'; end if;
  -- 旧原料を0へ戻し、新入力を設定する。行を残すため、後の取消・削除でも元の移動履歴を追える。
  select coalesce(jsonb_agg(jsonb_build_object('lot_id',lot_id,'qty',coalesce(qty,0)) order by lot_id),'[]'::jsonb)
    into v_old from public.hq_work_materials_v1500 where work_id=w.id;
  update public.hq_work_materials_v1500 set qty=0 where work_id=w.id;
  for r in select value from jsonb_array_elements(p_materials) loop
    begin v_lot_id := (r->>'lot_id')::uuid; exception when others then raise exception '原料ロットを正しく指定してください'; end;
    if v_lot_id is null then raise exception '原料ロットを正しく指定してください'; end if;
    v_qty := public.hq_c116_nonnegative(r->>'qty','使用原料の数');
    insert into public.hq_work_materials_v1500(work_id,lot_id,lot_no,item_name,unit,pack_kg,qty)
    select w.id,l.id,l.lot_no,l.item_name,l.unit,case when l.unit='kg' then null else public.hq_pack_kg_v1500(l.pack_weight) end,v_qty
    from public.hq_lots_v1400 l where l.id=v_lot_id
    on conflict(work_id,lot_id) do update set qty=excluded.qty;
  end loop;
  v_outputs := public.hq_c116_work_outputs(w,p_outputs);
  select coalesce(sum((value->>'yield_kg')::numeric),0) into v_yield from jsonb_array_elements(v_outputs);
  select coalesce(jsonb_agg(jsonb_build_object('lot_id',lot_id,'qty',coalesce(qty,0)) order by lot_id),'[]'::jsonb)
    into v_after from public.hq_work_materials_v1500 where work_id=w.id;
  if w.stock_applied then
    for lot in select * from public.hq_lots_v1400 where id=any(ids) order by id for update loop
      select coalesce(sum(qty),0) into v_qty from public.hq_work_materials_v1500 where work_id=w.id and lot_id=lot.id;
      select coalesce(sum((value->>'qty')::numeric),0) into v_delta
        from jsonb_array_elements(v_old) x where (x.value->>'lot_id')::uuid=lot.id;
      -- 正の差は在庫へ戻す、負の差は現在在庫から追加で引く。
      v_delta := coalesce(v_delta,0)-coalesce(v_qty,0);
      if v_delta<0 and lot.current_qty < -v_delta then raise exception '原料 % の現在在庫が不足しています',lot.lot_no; end if;
      if v_delta<>0 then
        v_before := lot.current_qty; v_stock_after := v_before+v_delta;
        update public.hq_lots_v1400 set current_qty=v_stock_after,status=case when v_stock_after>0 then '在庫あり' else '在庫なし' end,updated_at=now() where id=lot.id;
        insert into public.hq_lot_movements_v1400(operation_id,lot_id,movement_type,qty,unit,before_qty,after_qty,reason,memo,item_name,lot_no,user_id,user_name,occurred_at,work_id)
        values((substr(md5(p_operation_id::text||':'||lot.id::text),1,8)||'-'||substr(md5(p_operation_id::text||':'||lot.id::text),9,4)||'-'||substr(md5(p_operation_id::text||':'||lot.id::text),13,4)||'-'||substr(md5(p_operation_id::text||':'||lot.id::text),17,4)||'-'||substr(md5(p_operation_id::text||':'||lot.id::text),21,12))::uuid,
          lot.id,'下処理訂正',v_delta,lot.unit,v_before,v_stock_after,btrim(p_reason),w.product_name,lot.item_name,lot.lot_no,v.id,v.display_name,now(),w.id)
        returning id into v_mid;
      end if;
    end loop;
  end if;
  update public.hq_waste_v1500 set cancelled_at=now(),cancelled_by_name=v.display_name
    where work_id=w.id and kind='下処理ロス' and cancelled_at is null;
  if w.confirm_status='確定' and p_waste_kg>0 then insert into public.hq_waste_v1500(kind,waste_date,item_name,kg,work_id,memo,user_name)
    values('下処理ロス',w.work_date,coalesce(w.raw_item_name,w.product_name),p_waste_kg,w.id,w.product_name,v.display_name); end if;
  update public.hq_works_v1500 set waste_kg=p_waste_kg,yield_kg=v_yield,outputs=v_outputs,
    inputs_saved_at=now(),inputs_saved_by_name=v.display_name,
    history=history||jsonb_build_array(jsonb_build_object('at',now(),'by',v.display_name,'action','訂正','reason',btrim(p_reason),'before',jsonb_build_object('materials',v_old,'waste_kg',w.waste_kg,'outputs',w.outputs),'after',jsonb_build_object('materials',v_after,'waste_kg',p_waste_kg,'outputs',v_outputs))),
    updated_at=now() where id=w.id;
  update public.hq_prep_operations_v1199c116 set result=jsonb_build_object('ok',true,'work_id',w.id,'stock_applied',w.stock_applied,'outputs',v_outputs),completed_at=now()
    where operation_id=p_operation_id;
  return (select result from public.hq_prep_operations_v1199c116 where operation_id=p_operation_id);
end $f$;

-- 取消・削除で、通常確定分と訂正差分の両方を現在在庫へ戻す。過去の移動行は取消済みとして残す。
create or replace function public.hq_prep_unapply_v1500(p_work_id uuid, p_by public.profiles)
returns void language plpgsql security definer set search_path to ''
as $f$
declare l public.hq_lots_v1400%rowtype; v_undo numeric; v_after numeric;
begin
  -- ロットを同じUUID順に先に全てロックし、取消差分をロット単位で合算する。
  -- 複数訂正の途中値で在庫が一時的に負になることを避ける。
  for l in select * from public.hq_lots_v1400 where id in (
    select distinct lot_id from public.hq_lot_movements_v1400
      where work_id=p_work_id and cancelled_at is null and movement_type in ('下処理使用','下処理訂正')
  ) order by id for update loop
    select coalesce(sum(case when movement_type='下処理使用' then qty else -qty end),0) into v_undo
      from public.hq_lot_movements_v1400 where work_id=p_work_id and lot_id=l.id
        and cancelled_at is null and movement_type in ('下処理使用','下処理訂正');
    if l.current_qty+v_undo<0 then raise exception '下処理取消後の原料 % の在庫が負になります',l.lot_no; end if;
  end loop;
  for l in select * from public.hq_lots_v1400 where id in (
    select distinct lot_id from public.hq_lot_movements_v1400
      where work_id=p_work_id and cancelled_at is null and movement_type in ('下処理使用','下処理訂正')
  ) order by id for update loop
    select coalesce(sum(case when movement_type='下処理使用' then qty else -qty end),0) into v_undo
      from public.hq_lot_movements_v1400 where work_id=p_work_id and lot_id=l.id
        and cancelled_at is null and movement_type in ('下処理使用','下処理訂正');
    v_after:=l.current_qty+v_undo;
    update public.hq_lots_v1400 set current_qty=v_after,status=case when v_after>0 then '在庫あり' else '在庫なし' end,updated_at=now() where id=l.id;
    update public.hq_lot_movements_v1400 set cancelled_at=now(),cancelled_by_name=p_by.display_name
      where work_id=p_work_id and lot_id=l.id and cancelled_at is null and movement_type in ('下処理使用','下処理訂正');
    insert into public.hq_lot_movements_v1400(operation_id,lot_id,movement_type,qty,unit,before_qty,after_qty,reason,item_name,lot_no,user_id,user_name,work_id)
    values(gen_random_uuid(),l.id,'下処理取消',v_undo,l.unit,l.current_qty,v_after,'下処理の取消',l.item_name,l.lot_no,p_by.id,p_by.display_name,p_work_id);
  end loop;
  update public.hq_work_materials_v1500 set movement_id=null where work_id=p_work_id;
  update public.hq_waste_v1500 set cancelled_at=now(),cancelled_by_name=p_by.display_name where work_id=p_work_id and kind='下処理ロス' and cancelled_at is null;
  update public.hq_works_v1500 set stock_applied=false where id=p_work_id;
end $f$;

-- 休憩・中断：除外者以外の現在参加者だけを終了させる。中断も全員を閉じ、他作業へ移れる。
create or replace function public.hq_work_pause_v1199c116(
  p_work_id uuid, p_operation_id uuid, p_kind text, p_excluded_staff_ids uuid[] default '{}'
) returns jsonb language plpgsql security definer set search_path to ''
as $f$
declare v public.profiles; w public.hq_works_v1500%rowtype; ids uuid[]; excluded uuid[]; bad uuid[]; at_time timestamptz:=clock_timestamp(); existing public.hq_work_pauses_v1199c116%rowtype;
begin
  v:=public.hq_actor_v1400(array['admin','hq_worker','hq_prep']);
  if p_operation_id is null then raise exception 'operation_idが必要です'; end if;
  if p_kind not in ('休憩','中断') then raise exception '休憩または中断を選んでください'; end if;
  excluded:=array(select distinct x from unnest(coalesce(p_excluded_staff_ids,'{}'::uuid[])) x order by x);
  if array_length(excluded,1)<>array_length(p_excluded_staff_ids,1) then raise exception '休憩に入らない人を重複して指定できません'; end if;
  if p_kind='中断' and coalesce(array_length(excluded,1),0)>0 then raise exception '中断では全員を中断してください（除外者は選べません）'; end if;
  select * into existing from public.hq_work_pauses_v1199c116 where operation_id=p_operation_id for update;
  if found then
    if existing.work_id=p_work_id and existing.kind=p_kind and existing.excluded_staff_ids=excluded then
      return jsonb_build_object('ok',true,'already',true,'work_id',existing.work_id,'staff_ids',existing.staff_ids);
    end if;
    raise exception '同じoperation_idに異なる休憩・中断は使えません';
  end if;
  select * into w from public.hq_works_v1500 where id=p_work_id for update;
  if not found or w.kind<>'下処理' or w.status<>'作業中' or w.confirm_status='取消' then raise exception '休憩・中断できる下処理が見つかりません'; end if;
  -- work行のロック待ち中の同一再送も、内容を照合して返す。
  select * into existing from public.hq_work_pauses_v1199c116 where operation_id=p_operation_id for update;
  if found then
    if existing.work_id=p_work_id and existing.kind=p_kind and existing.excluded_staff_ids=excluded then return jsonb_build_object('ok',true,'already',true,'work_id',existing.work_id,'staff_ids',existing.staff_ids); end if;
    raise exception '同じoperation_idに異なる休憩・中断は使えません';
  end if;
  if w.pause_kind<>'' then raise exception 'すでに休憩または中断中です'; end if;
  select array_agg(staff_id order by staff_id) into bad from unnest(excluded) x(staff_id)
    where not exists(select 1 from public.hq_work_members_v1500 m where m.work_id=w.id and m.staff_id=x.staff_id and m.end_at is null and m.phase='作業');
  if bad is not null then raise exception '休憩に入らない人は、いまこの下処理に参加している人だけ選べます'; end if;
  select coalesce(array_agg(staff_id order by staff_id),'{}') into ids from public.hq_work_members_v1500
    where work_id=w.id and end_at is null and phase='作業' and not(staff_id=any(excluded));
  if array_length(ids,1) is null then raise exception '休憩・中断にする参加者がいません'; end if;
  insert into public.hq_work_pauses_v1199c116(operation_id,work_id,kind,start_at,staff_ids,by_name,excluded_staff_ids)
  values(p_operation_id,w.id,p_kind,at_time,ids,v.display_name,excluded);
  update public.hq_work_members_v1500 set end_at=at_time,end_reason=p_kind where work_id=w.id and end_at is null and phase='作業' and staff_id=any(ids);
  update public.hq_works_v1500 set pause_kind=p_kind,history=history||jsonb_build_array(jsonb_build_object('at',at_time,'by',v.display_name,'action',p_kind,'staff_ids',ids,'excluded_staff_ids',excluded)),updated_at=now() where id=w.id;
  return jsonb_build_object('ok',true,'work_id',w.id,'staff_ids',ids);
end $f$;

-- 再開は直前の休憩・中断の未再開者だけを作業区間へ戻す。再開操作ごとに台帳を残す。
create or replace function public.hq_work_resume_v1199c116(
  p_work_id uuid, p_operation_id uuid, p_staff_ids uuid[]
) returns jsonb language plpgsql security definer set search_path to ''
as $f$
declare v public.profiles; w public.hq_works_v1500%rowtype; p public.hq_work_pauses_v1199c116%rowtype;
  staff public.hq_staff_v1500%rowtype; busy text; ids uuid[]; resumed uuid[]; remaining uuid[];
  at_time timestamptz:=clock_timestamp(); v_input jsonb; v_existing public.hq_prep_operations_v1199c116%rowtype;
begin
  v:=public.hq_actor_v1400(array['admin','hq_worker','hq_prep']);
  if p_operation_id is null then raise exception 'operation_idが必要です'; end if;
  if coalesce(array_length(p_staff_ids,1),0)<1 or array_position(p_staff_ids,null) is not null then raise exception '再開する人を選んでください'; end if;
  ids:=array(select distinct x from unnest(p_staff_ids) x order by x);
  if array_length(ids,1)<>array_length(p_staff_ids,1) then raise exception '再開する人を重複して指定できません'; end if;
  v_input:=jsonb_build_object('work_id',p_work_id,'staff_ids',ids);
  -- 訂正と同じ台帳で、同じ操作の再送は結果を返し、別内容の再送は拒否する。
  insert into public.hq_prep_operations_v1199c116(operation_id,work_id,action,input,created_by_name)
  values(p_operation_id,p_work_id,'再開',v_input,v.display_name) on conflict(operation_id) do nothing;
  if not found then
    select * into v_existing from public.hq_prep_operations_v1199c116 where operation_id=p_operation_id for update;
    if not found then raise exception '再開操作を確認できません。再度実行してください'; end if;
    if v_existing.action<>'再開' or v_existing.input is distinct from v_input then
      return jsonb_build_object('ok',false,'idempotency_conflict',true,'message','同じoperation_idに異なる内容は使えません');
    end if;
    if v_existing.result is null then raise exception '同じ再開が処理中です。しばらく待ってから再表示してください'; end if;
    return v_existing.result || jsonb_build_object('idempotent',true,'already',true);
  end if;
  select * into w from public.hq_works_v1500 where id=p_work_id for update;
  if not found or w.kind<>'下処理' or w.status<>'作業中' then raise exception '再開できる下処理が見つかりません'; end if;
  if w.pause_kind='' then raise exception '再開できる休憩・中断中の作業が見つかりません'; end if;
  select * into p from public.hq_work_pauses_v1199c116
    where work_id=w.id and kind in ('休憩','中断') and end_at is null
    order by start_at desc limit 1 for update;
  if not found then raise exception '再開できる休憩・中断の記録が見つかりません'; end if;
  if exists(select 1 from unnest(ids) x where not x=any(p.staff_ids)) then raise exception '休憩・中断に入っていた人だけを再開できます'; end if;
  -- 同じ人を異なる再開操作で二重に戻さない。部分再開後も pause は開いたままにする。
  if exists(select 1 from unnest(ids) x where x=any(p.resumed_staff_ids)) then raise exception '選んだ人には、すでに再開済みの人が含まれます'; end if;
  for staff in select * from public.hq_staff_v1500 where id=any(ids) order by id for update loop
    if staff.deleted_at is not null then raise exception '%さんは削除済みです',staff.name; end if;
    select o.task_name||coalesce('（'||o.place||'）','') into busy from public.hq_work_members_v1500 m join public.hq_works_v1500 o on o.id=m.work_id
      where m.staff_id=staff.id and m.end_at is null and m.work_id<>w.id limit 1;
    if busy is not null then raise exception '%さんは、ほかの作業（%）に入っています',staff.name,busy; end if;
  end loop;
  insert into public.hq_work_members_v1500(work_id,staff_id,staff_name,team,phase,start_at)
    select w.id,s.id,s.name,s.team,'作業',at_time from public.hq_staff_v1500 s where s.id=any(ids);
  resumed:=array(select distinct x from unnest(coalesce(p.resumed_staff_ids,'{}'::uuid[])||ids) x order by x);
  remaining:=array(select x from unnest(p.staff_ids) x where not x=any(resumed) order by x);
  update public.hq_work_pauses_v1199c116
    set resumed_staff_ids=resumed,
        end_at=case when coalesce(array_length(remaining,1),0)=0 then at_time else null end,
        resume_operation_id=case when coalesce(array_length(remaining,1),0)=0 then p_operation_id else null end
    where id=p.id;
  update public.hq_works_v1500
    set pause_kind=case when coalesce(array_length(remaining,1),0)=0 then '' else w.pause_kind end,
        history=history||jsonb_build_array(jsonb_build_object('at',at_time,'by',v.display_name,'action','再開','staff_ids',ids)),
        updated_at=now()
    where id=w.id;
  update public.hq_prep_operations_v1199c116
    set result=jsonb_build_object('ok',true,'work_id',w.id,'pause_id',p.id,'staff_ids',ids,
      'resumed_at',at_time,'remaining_staff_ids',remaining),completed_at=now()
    where operation_id=p_operation_id;
  return (select result from public.hq_prep_operations_v1199c116 where operation_id=p_operation_id);
end $f$;

-- 後入力休憩は対象時間に「作業」だった人だけを区間分割する。休憩・中断との重複は人単位で拒否する。
create or replace function public.hq_work_break_add_v1199c116(
  p_work_id uuid, p_operation_id uuid, p_start timestamptz, p_end timestamptz, p_excluded_staff_ids uuid[] default '{}'
) returns jsonb language plpgsql security definer set search_path to ''
as $f$
declare v public.profiles; w public.hq_works_v1500%rowtype; member_row public.hq_work_members_v1500%rowtype; ids uuid[]; excluded uuid[]; existing public.hq_work_pauses_v1199c116%rowtype;
begin
  v:=public.hq_actor_v1400(array['admin','hq_worker','hq_prep']);
  if p_operation_id is null then raise exception 'operation_idが必要です'; end if;
  if p_start is null or p_end is null or p_end<=p_start or p_end>clock_timestamp() then raise exception '休憩の開始・終了時刻を正しく入れてください'; end if;
  excluded:=array(select distinct x from unnest(coalesce(p_excluded_staff_ids,'{}'::uuid[])) x order by x);
  if array_length(excluded,1)<>array_length(p_excluded_staff_ids,1) then raise exception '休憩に入らない人を重複して指定できません'; end if;
  select * into existing from public.hq_work_pauses_v1199c116 where operation_id=p_operation_id for update;
  if found then
    if existing.work_id=p_work_id and existing.kind='後入力休憩' and existing.start_at=p_start and existing.end_at=p_end and existing.excluded_staff_ids=excluded then return jsonb_build_object('ok',true,'already',true,'work_id',existing.work_id,'staff_ids',existing.staff_ids); end if;
    raise exception '同じoperation_idに異なる後入力休憩は使えません';
  end if;
  select * into w from public.hq_works_v1500 where id=p_work_id for update;
  if not found or w.kind<>'下処理' then raise exception '下処理が見つかりません'; end if;
  if w.confirm_status='取消' or w.status='取消' then raise exception '取消済みの作業には休憩を追加できません'; end if;
  if p_start<w.started_at or (w.ended_at is not null and p_end>w.ended_at) then raise exception '休憩は作業の開始から終了までの範囲で入れてください'; end if;
  select * into existing from public.hq_work_pauses_v1199c116 where operation_id=p_operation_id for update;
  if found then
    if existing.work_id=p_work_id and existing.kind='後入力休憩' and existing.start_at=p_start and existing.end_at=p_end and existing.excluded_staff_ids=excluded then return jsonb_build_object('ok',true,'already',true,'work_id',existing.work_id,'staff_ids',existing.staff_ids); end if;
    raise exception '同じoperation_idに異なる後入力休憩は使えません';
  end if;
  select coalesce(array_agg(distinct staff_id order by staff_id),'{}') into ids from public.hq_work_members_v1500
    where work_id=w.id and phase='作業' and start_at<p_end and coalesce(end_at,'infinity'::timestamptz)>p_start and not(staff_id=any(excluded));
  if array_length(ids,1) is null then raise exception 'この時間に休憩へ入れる参加者がいません'; end if;
  if exists(select 1 from unnest(excluded) x where not exists(select 1 from public.hq_work_members_v1500 m where m.work_id=w.id and m.phase='作業' and m.staff_id=x and m.start_at<p_end and coalesce(m.end_at,'infinity'::timestamptz)>p_start)) then raise exception '休憩に入らない人は、この時間に下処理へ参加していた人だけ選べます'; end if;
  -- 部分再開は人ごとの再開時刻までを休憩区間とする。未再開者だけは現在まで重複を防ぐ。
  if exists(
    select 1 from public.hq_work_pauses_v1199c116 p
      cross join lateral unnest(p.staff_ids) paused(staff_id)
    where p.work_id=w.id and p.kind in ('休憩','中断','後入力休憩')
      and paused.staff_id=any(ids) and p.start_at<p_end
      and coalesce((
        select min((o.result->>'resumed_at')::timestamptz)
          from public.hq_prep_operations_v1199c116 o
         where o.action='再開' and o.work_id=w.id and o.result->>'pause_id'=p.id::text
           and o.input->'staff_ids' @> jsonb_build_array(paused.staff_id)
      ),p.end_at,clock_timestamp())>p_start
  ) then raise exception '同じ人の休憩・中断と時間が重なります'; end if;
  insert into public.hq_work_pauses_v1199c116(operation_id,work_id,kind,start_at,end_at,staff_ids,by_name,excluded_staff_ids) values(p_operation_id,w.id,'後入力休憩',p_start,p_end,ids,v.display_name,excluded);
  for member_row in select * from public.hq_work_members_v1500 where work_id=w.id and phase='作業' and staff_id=any(ids) and start_at<p_end and coalesce(end_at,'infinity'::timestamptz)>p_start order by staff_id,start_at for update loop
    if member_row.start_at>=p_start then delete from public.hq_work_members_v1500 where id=member_row.id;
    else update public.hq_work_members_v1500 set end_at=p_start,end_reason='休憩（後入力）' where id=member_row.id; end if;
    if coalesce(member_row.end_at,'infinity'::timestamptz)>p_end then
      insert into public.hq_work_members_v1500(work_id,staff_id,staff_name,team,phase,start_at,end_at,end_reason,fixed_by_name,fixed_at)
      values(w.id,member_row.staff_id,member_row.staff_name,member_row.team,'作業',p_end,member_row.end_at,coalesce(member_row.end_reason,'休憩後に再開'),v.display_name,now());
    end if;
  end loop;
  update public.hq_works_v1500 set history=history||jsonb_build_array(jsonb_build_object('at',now(),'by',v.display_name,'action','後入力休憩','start_at',p_start,'end_at',p_end,'staff_ids',ids,'excluded_staff_ids',excluded)),updated_at=now() where id=w.id;
  return jsonb_build_object('ok',true,'work_id',w.id,'staff_ids',ids);
end $f$;

-- 022の削除結果を維持し、訂正差分も在庫へ戻してから削除する。
create or replace function public.hq_work_delete_v1500(p_work_id uuid)
returns jsonb language plpgsql security definer set search_path to ''
as $f$
declare v public.profiles; w public.hq_works_v1500%rowtype; restored boolean:=false;
begin
  v:=public.hq_actor_v1400(array['admin','hq_worker']);
  select * into w from public.hq_works_v1500 where id=p_work_id for update;
  if not found then raise exception '作業が見つかりません（すでに削除されています）'; end if;
  if w.stock_applied then perform public.hq_prep_unapply_v1500(w.id,v); restored:=true; end if;
  insert into public.hq_deleted_works_v1500(work_id,work,materials,members,deleted_by_name)
  values(w.id,to_jsonb(w),coalesce((select jsonb_agg(to_jsonb(m)) from public.hq_work_materials_v1500 m where m.work_id=w.id),'[]'::jsonb),coalesce((select jsonb_agg(to_jsonb(m)) from public.hq_work_members_v1500 m where m.work_id=w.id),'[]'::jsonb),v.display_name);
  -- 022と同じ削除結果を保つ。045の休憩はCASCADE、訂正再送台帳はwork_idをNULLにして残す。
  delete from public.hq_lot_movements_v1400 where work_id=w.id and (cancelled_at is not null or movement_type='下処理取消');
  delete from public.hq_waste_v1500 where work_id=w.id and kind='下処理ロス';
  delete from public.hq_work_materials_v1500 where work_id=w.id;
  delete from public.hq_work_members_v1500 where work_id=w.id;
  delete from public.hq_works_v1500 where id=w.id;
  return jsonb_build_object('ok',true,'restored',restored);
end $f$;

-- 旧RPCは、単一製造では新しい共通処理へつなぎ、同時製造・休憩中だけ止める。
-- これにより従来の単一製造画面は動作を維持し、複数製品の内訳を1つの出来高で壊しません。
create or replace function public.hq_work_save_inputs_v1500(p_work_id uuid,p_materials jsonb,p_waste_kg numeric,p_yield_kg numeric)
returns jsonb language plpgsql security definer set search_path to ''
as $f$
declare v public.profiles; w public.hq_works_v1500%rowtype;
begin
  v:=public.hq_actor_v1400(array['admin','hq_worker','hq_prep']);
  select * into w from public.hq_works_v1500 where id=p_work_id;
  if not found or w.kind<>'下処理' then raise exception '下処理が見つかりません'; end if;
  if jsonb_array_length(coalesce(w.outputs,'[]'::jsonb))>1 or w.pause_kind<>'' then
    raise exception '同時製造または休憩・中断の作業は、新しい下処理入力画面から保存してください';
  end if;
  if p_yield_kg is null or p_yield_kg<0 or p_yield_kg::text in ('NaN','Infinity','-Infinity') then raise exception '出来高（kg）は0以上の数字で入れてください'; end if;
  return public.hq_c116_save_inputs(p_work_id,p_materials,p_waste_kg,
    jsonb_build_array(jsonb_build_object('master_id',w.prep_master_id,'yield_kg',p_yield_kg)),v);
end $f$;

create or replace function public.hq_prep_confirm_v1500(p_work_id uuid,p_materials jsonb,p_waste_kg numeric,p_yield_kg numeric,p_reason text)
returns jsonb language plpgsql security definer set search_path to ''
as $f$
declare w public.hq_works_v1500%rowtype;
begin
  select * into w from public.hq_works_v1500 where id=p_work_id;
  if not found or w.kind<>'下処理' then raise exception '下処理が見つかりません'; end if;
  if jsonb_array_length(coalesce(w.outputs,'[]'::jsonb))>1 or w.pause_kind<>'' then
    raise exception '同時製造または休憩・中断の作業は、新しい下処理確認画面から確定してください';
  end if;
  return public.hq_prep_confirm_v1199c116(p_work_id,p_materials,p_waste_kg,
    jsonb_build_array(jsonb_build_object('master_id',w.prep_master_id,'yield_kg',p_yield_kg)),p_reason);
end $f$;

create or replace function public.hq_work_end_v1500(p_work_id uuid)
returns jsonb language plpgsql security definer set search_path to ''
as $f$
declare v public.profiles; w public.hq_works_v1500%rowtype;
begin
  v:=public.hq_actor_v1400(array['admin','hq_worker','hq_prep']);
  select * into w from public.hq_works_v1500 where id=p_work_id for update;
  if not found then raise exception '作業が見つかりません'; end if;
  if w.pause_kind<>'' then raise exception '休憩・中断中の作業は終了できません。先に再開してください'; end if;
  if w.status<>'作業中' then return jsonb_build_object('ok',true,'already',true,'status',w.status); end if;
  update public.hq_work_members_v1500 set end_at=now(),end_reason='作業終了' where work_id=w.id and end_at is null;
  update public.hq_works_v1500 set status=case when kind='下処理' then '入力待ち' else '完了' end,ended_at=now(),updated_at=now() where id=w.id;
  return jsonb_build_object('ok',true,'status',case when w.kind='下処理' then '入力待ち' else '完了' end);
end $f$;


-- 既存入口も休憩中の下処理へ人を追加・取消できないようにし、同一スタッフを別作業へ同時に入れない。
create or replace function public.hq_work_add_members_v1500(p_work_id uuid,p_staff_ids uuid[],p_phase text)
returns integer language plpgsql security definer set search_path to ''
as $f$
declare staff public.hq_staff_v1500%rowtype; n integer:=0; busy text;
begin
  if p_phase not in ('作業','清掃') then raise exception '作業区分が正しくありません'; end if;
  if coalesce(array_length(p_staff_ids,1),0)<>coalesce(array_length(array(select distinct x from unnest(coalesce(p_staff_ids,'{}'::uuid[])) x),1),0) then raise exception '同じ作業者を重複して指定できません'; end if;
  for staff in select * from public.hq_staff_v1500 where id=any(coalesce(p_staff_ids,'{}'::uuid[])) order by id for update loop
    if staff.deleted_at is not null then raise exception '%さんは削除済みです',staff.name; end if;
    select w.task_name||coalesce('（'||w.place||'）','') into busy from public.hq_work_members_v1500 m join public.hq_works_v1500 w on w.id=m.work_id where m.staff_id=staff.id and m.end_at is null and m.work_id<>p_work_id limit 1;
    if busy is not null then raise exception '%さんは、ほかの作業（%）に入っています。先にそちらを終えるか、抜けてください',staff.name,busy; end if;
    if exists(select 1 from public.hq_work_members_v1500 where staff_id=staff.id and work_id=p_work_id and end_at is null) then continue; end if;
    insert into public.hq_work_members_v1500(work_id,staff_id,staff_name,team,phase,start_at) values(p_work_id,staff.id,staff.name,staff.team,p_phase,now()); n:=n+1;
  end loop;
  return n;
end $f$;

create or replace function public.hq_work_join_v1500(p_work_id uuid,p_staff_ids uuid[])
returns jsonb language plpgsql security definer set search_path to ''
as $f$
declare v public.profiles; w public.hq_works_v1500%rowtype; n integer;
begin
  v:=public.hq_actor_v1400(array['admin','hq_worker','hq_prep']); select * into w from public.hq_works_v1500 where id=p_work_id for update;
  if not found or w.status not in ('作業中','清掃中') or w.pause_kind<>'' then raise exception 'この作業には、いま途中から入れません（%）',coalesce(w.status,''); end if;
  n:=public.hq_work_add_members_v1500(w.id,p_staff_ids,case when w.status='清掃中' then '清掃' else '作業' end); update public.hq_works_v1500 set updated_at=now() where id=w.id;
  return jsonb_build_object('ok',true,'added',n);
end $f$;

create or replace function public.hq_work_cancel_v1500(p_work_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path to ''
as $f$
declare v public.profiles; w public.hq_works_v1500%rowtype;
begin
  v:=public.hq_actor_v1400(array['admin','hq_worker','hq_prep']); select * into w from public.hq_works_v1500 where id=p_work_id for update;
  if not found then raise exception '作業が見つかりません'; end if;
  if w.pause_kind<>'' then raise exception '休憩・中断中の作業は先に再開してください'; end if;
  if w.status='取消' then return jsonb_build_object('ok',true,'already',true); end if;
  if w.confirm_status='確定' then raise exception '確定済みの下処理は「下処理の確認」から取り消してください'; end if;
  if v.role='hq_prep' and w.status<>'作業中' then raise exception '作業終了のあとは、本社社員に取り消してもらってください' using errcode='42501'; end if;
  update public.hq_work_members_v1500 set end_at=now(),end_reason='取消' where work_id=w.id and end_at is null;
  update public.hq_works_v1500 set status='取消',confirm_status=case when kind='下処理' then '取消' else confirm_status end,history=history||jsonb_build_array(jsonb_build_object('at',now(),'by',v.display_name,'action','作業の取消','reason',p_reason)),updated_at=now() where id=w.id;
  return jsonb_build_object('ok',true);
end $f$;

create or replace function public.hq_member_fix_v1500(p_member_id uuid,p_start timestamptz,p_end timestamptz,p_delete boolean)
returns jsonb language plpgsql security definer set search_path to ''
as $f$
declare v public.profiles; m public.hq_work_members_v1500%rowtype; w public.hq_works_v1500%rowtype;
begin
  v:=public.hq_actor_v1400(array['admin','hq_worker']); select * into m from public.hq_work_members_v1500 where id=p_member_id for update;
  if not found then raise exception '記録が見つかりません'; end if; select * into w from public.hq_works_v1500 where id=m.work_id for update;
  if w.pause_kind<>'' then raise exception '休憩・中断中の作業者記録は先に再開してください'; end if;
  -- 既存の作業者修正も、再開処理・別作業開始と同じスタッフ行を先にロックする。
  perform 1 from public.hq_staff_v1500 where id=m.staff_id for update;
  if coalesce(p_delete,false) then delete from public.hq_work_members_v1500 where id=m.id; return jsonb_build_object('ok',true); end if;
  if p_start is null or (p_end is not null and p_end<p_start) then raise exception '開始と終了の時刻を正しく入れてください'; end if;
  if p_end is null and exists(select 1 from public.hq_work_members_v1500 o where o.staff_id=m.staff_id and o.work_id<>m.work_id and o.end_at is null) then raise exception 'ほかの作業中の人を再開できません'; end if;
  update public.hq_work_members_v1500 set start_at=p_start,end_at=p_end,end_reason=case when p_end is null then null else coalesce(end_reason,'修正') end,fixed_by_name=v.display_name,fixed_at=now() where id=m.id;
  return jsonb_build_object('ok',true);
end $f$;


-- 旧の作業者手入力・清掃移行も、休憩・中断中の状態を崩さない。
create or replace function public.hq_member_add_v1500(p_work_id uuid,p_staff_id uuid,p_phase text,p_start timestamptz,p_end timestamptz)
returns jsonb language plpgsql security definer set search_path to ''
as $f$
declare v public.profiles; staff public.hq_staff_v1500%rowtype; w public.hq_works_v1500%rowtype;
begin
  v:=public.hq_actor_v1400(array['admin','hq_worker']);
  if p_phase not in ('作業','清掃') then raise exception '作業か清掃かを選んでください'; end if;
  if p_start is null or p_end is null or p_end<p_start then raise exception '開始と終了の時刻を正しく入れてください'; end if;
  select * into w from public.hq_works_v1500 where id=p_work_id for update;
  if not found then raise exception '作業が見つかりません'; end if;
  if w.pause_kind<>'' then raise exception '休憩・中断中の作業者記録は先に再開してください'; end if;
  select * into staff from public.hq_staff_v1500 where id=p_staff_id for update;
  if not found or staff.deleted_at is not null then raise exception 'スタッフが見つかりません'; end if;
  insert into public.hq_work_members_v1500(work_id,staff_id,staff_name,team,phase,start_at,end_at,end_reason,fixed_by_name,fixed_at)
  values(w.id,staff.id,staff.name,staff.team,p_phase,p_start,p_end,'追加（修正）',v.display_name,now());
  return jsonb_build_object('ok',true);
end $f$;

create or replace function public.hq_work_to_clean_v1500(p_work_id uuid,p_printed boolean)
returns jsonb language plpgsql security definer set search_path to ''
as $f$
declare v public.profiles; w public.hq_works_v1500%rowtype; ids uuid[];
begin
  v:=public.hq_actor_v1400(array['admin','hq_worker','hq_prep']); select * into w from public.hq_works_v1500 where id=p_work_id for update;
  if not found or w.kind<>'下処理' then raise exception '下処理が見つかりません'; end if;
  if w.pause_kind<>'' then raise exception '休憩・中断中の作業は先に再開してください'; end if;
  if w.status<>'入力待ち' then return jsonb_build_object('ok',true,'already',true,'status',w.status); end if;
  if w.inputs_saved_at is null then raise exception '先に使用原料・廃棄・出来高を入れてください'; end if;
  select array_agg(distinct staff_id order by staff_id) into ids from public.hq_work_members_v1500 where work_id=w.id and phase='作業' and end_reason='作業終了';
  update public.hq_works_v1500 set status='清掃中',clean_started_at=now(),label_printed_at=case when p_printed then now() else label_printed_at end,label_print_count=label_print_count+case when p_printed then 1 else 0 end,updated_at=now() where id=w.id;
  if ids is not null then perform public.hq_work_add_members_v1500(w.id,ids,'清掃'); end if;
  return jsonb_build_object('ok',true);
end $f$;

-- 公開RPCだけ authenticated。内部ヘルパーはブラウザから直接呼ばせない。
do $block$
declare f text;
begin
  foreach f in array array[
    'public.hq_work_start_v1199c116(uuid,text,text,text,uuid[],uuid[],uuid[])',
    'public.hq_work_save_inputs_v1199c116(uuid,jsonb,numeric,jsonb)',
    'public.hq_prep_confirm_v1199c116(uuid,jsonb,numeric,jsonb,text)',
    'public.hq_prep_correct_v1199c116(uuid,uuid,timestamptz,jsonb,numeric,jsonb,text)',
    'public.hq_work_pause_v1199c116(uuid,uuid,text,uuid[])',
    'public.hq_work_resume_v1199c116(uuid,uuid,uuid[])',
    'public.hq_work_break_add_v1199c116(uuid,uuid,timestamptz,timestamptz,uuid[])',
    'public.hq_work_end_v1500(uuid)',
    'public.hq_work_save_inputs_v1500(uuid,jsonb,numeric,numeric)',
    'public.hq_prep_confirm_v1500(uuid,jsonb,numeric,numeric,text)',
    'public.hq_work_delete_v1500(uuid)'
  ] loop
    execute format('revoke all on function %s from public, anon',f);
    execute format('grant execute on function %s to authenticated, service_role',f);
  end loop;
  foreach f in array array[
    'public.hq_c116_nonnegative(text,text)',
    'public.hq_c116_outputs(uuid[],jsonb)',
    'public.hq_c116_work_master_ids(public.hq_works_v1500)',
    'public.hq_c116_work_outputs(public.hq_works_v1500,jsonb)',
    'public.hq_c116_validate_master_set(uuid[])',
    'public.hq_c116_save_inputs(uuid,jsonb,numeric,jsonb,public.profiles)',
    'public.hq_prep_unapply_v1500(uuid,public.profiles)'
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated',f);
    execute format('revoke all on function %s from service_role',f);
  end loop;
end $block$;

commit;
notify pgrst, 'reload schema';

/* 成功の確かめ方：5行すべてOKなら成功です。 */
select '045の列' as 確認,case when exists(select 1 from information_schema.columns where table_schema='public' and table_name='hq_works_v1500' and column_name='outputs') then 'OK' else 'NG' end as 結果
union all select '休憩履歴表',case when to_regclass('public.hq_work_pauses_v1199c116') is not null then 'OK' else 'NG' end
union all select '同時製造開始RPC',case when to_regprocedure('public.hq_work_start_v1199c116(uuid,text,text,text,uuid[],uuid[],uuid[])') is not null then 'OK' else 'NG' end
union all select '訂正RPC',case when to_regprocedure('public.hq_prep_correct_v1199c116(uuid,uuid,timestamptz,jsonb,numeric,jsonb,text)') is not null then 'OK' else 'NG' end
union all select '休憩RPC',case when to_regprocedure('public.hq_work_break_add_v1199c116(uuid,uuid,timestamptz,timestamptz,uuid[])') is not null then 'OK' else 'NG' end;
