-- 019_本社_第2段階.sql（v1.199-c58）
-- 本社の第2段階：下処理（入力・確認・確定）、スタッフQRと作業時間、在庫入力（原料・仕掛品）、廃棄一覧、
-- 仕入れ価格表（本社用）、歩留まり、使用数量、品質評価一覧、棚卸し、石岡ホームの数量の差のお知らせ。
-- 前提：016_本社_第1段階・017_本社_通常在庫と在庫表・018_本社_便と実測重量 を実行済みであること。
-- 石岡の表・関数は変更しません（読み取りだけです）。
-- 何度実行しても同じ結果になります。
-- 「第2段階の在庫反映」は最初「オフ」です。オフの間は、下処理を確定しても原料の在庫は減らさず、
-- 今までどおり使用出庫が使えます。実用開始の日に、管理者が画面でオンにします。

begin;

-- 1. 設定（第2段階の在庫反映のオン・オフ）
create table if not exists public.hq_settings_v1500 (
  key text primary key,
  value jsonb not null default 'null'::jsonb,
  updated_by_name text,
  updated_at timestamptz not null default now()
);
insert into public.hq_settings_v1500(key, value) values ('stage2_stock', 'false'::jsonb) on conflict (key) do nothing;

create or replace function public.hq_setting_on_v1500(p_key text)
returns boolean language sql stable security definer set search_path to ''
as $$ select coalesce((select value = 'true'::jsonb from public.hq_settings_v1500 where key = p_key), false) $$;

create or replace function public.hq_set_setting_v1500(p_key text, p_value jsonb)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles;
begin
  v := public.hq_actor_v1400(array['admin']);
  if p_key not in ('stage2_stock') then raise exception '設定の名前が正しくありません'; end if;
  insert into public.hq_settings_v1500(key, value, updated_by_name, updated_at) values (p_key, p_value, v.display_name, now())
  on conflict (key) do update set value = excluded.value, updated_by_name = excluded.updated_by_name, updated_at = now();
  return jsonb_build_object('ok', true);
end $$;

-- 2. 本社の履歴に「下処理使用」「廃棄」とその取消を追加
alter table public.hq_lot_movements_v1400 drop constraint if exists hq_lot_movements_v1400_movement_type_check;
alter table public.hq_lot_movements_v1400 add constraint hq_lot_movements_v1400_movement_type_check
  check (movement_type in ('入庫確定','出庫','実数調整','取消','出庫取消','受入取消','下処理使用','下処理取消','廃棄','廃棄取消'));
alter table public.hq_lot_movements_v1400 add column if not exists work_id uuid;

-- 量目の文字（例：10kg、10キロ）から1ケースのkgを取り出す
create or replace function public.hq_pack_kg_v1500(p_pack text)
returns numeric language sql immutable set search_path to ''
as $$ select nullif(substring(translate(coalesce(p_pack,''), '０１２３４５６７８９．', '0123456789.') from '([0-9]+(\.[0-9]+)?)'), '')::numeric $$;

-- 3. 品質評価：担当の仕入れ担当・確認済み
alter table public.hq_lots_v1400
  add column if not exists purchase_staff text,
  add column if not exists purchase_staff_profile_id uuid,
  add column if not exists quality_checked_at timestamptz,
  add column if not exists quality_checked_by_name text;

create or replace function public.hq_fill_purchase_staff_v1500()
returns trigger language plpgsql security definer set search_path to ''
as $$
begin
  if new.source_lot_id is not null and new.purchase_staff is null then
    select q.purchase_staff, q.purchase_staff_profile_id into new.purchase_staff, new.purchase_staff_profile_id
    from public.qr_lots q where q.id = new.source_lot_id;
  end if;
  return new;
exception when others then
  return new;
end $$;
drop trigger if exists hq_fill_purchase_staff_v1500_trg on public.hq_lots_v1400;
create trigger hq_fill_purchase_staff_v1500_trg before insert on public.hq_lots_v1400
for each row execute function public.hq_fill_purchase_staff_v1500();
update public.hq_lots_v1400 h set purchase_staff = q.purchase_staff, purchase_staff_profile_id = q.purchase_staff_profile_id
from public.qr_lots q where q.id = h.source_lot_id and h.purchase_staff is null and q.purchase_staff is not null;

create table if not exists public.hq_quality_dismiss_v1500 (
  lot_id uuid not null references public.hq_lots_v1400(id),
  user_id uuid not null,
  user_name text,
  dismissed_at timestamptz not null default now(),
  primary key (lot_id, user_id)
);

create or replace function public.hq_quality_check_v1500(p_lot_id uuid)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles; l public.hq_lots_v1400%rowtype;
begin
  v := public.hq_actor_v1400(array['admin','buyer']);
  select * into l from public.hq_lots_v1400 where id = p_lot_id for update;
  if not found or l.grade is null then raise exception '品質評価が見つかりません'; end if;
  if l.grade = 'good' then raise exception '良好の評価は確認不要です'; end if;
  if v.role = 'buyer' and l.purchase_staff_profile_id is distinct from v.id then
    raise exception '担当の仕入れ担当者が確認します' using errcode = '42501';
  end if;
  if v.role = 'admin' and l.purchase_staff_profile_id is not null and l.purchase_staff_profile_id <> v.id then
    raise exception '担当の仕入れ担当者（%）が確認します', coalesce(l.purchase_staff,'') using errcode = '42501';
  end if;
  update public.hq_lots_v1400 set quality_checked_at = now(), quality_checked_by_name = v.display_name, updated_at = now() where id = l.id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.hq_quality_dismiss_v1500(p_lot_id uuid)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles;
begin
  v := public.hq_actor_v1400(array['admin','hq_worker']);
  insert into public.hq_quality_dismiss_v1500(lot_id, user_id, user_name) values (p_lot_id, v.id, v.display_name)
  on conflict (lot_id, user_id) do nothing;
  return jsonb_build_object('ok', true);
end $$;

-- 4. 石岡ホームの「数量の差」のお知らせ（確認しました）
create table if not exists public.hq_diff_acks_v1500 (
  lot_id uuid primary key references public.hq_lots_v1400(id),
  acked_by_name text,
  acked_at timestamptz not null default now()
);
create or replace function public.hq_diff_ack_v1500(p_lot_id uuid)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles;
begin
  v := public.hq_actor_v1400(array['admin','worker']);
  insert into public.hq_diff_acks_v1500(lot_id, acked_by_name) values (p_lot_id, v.display_name) on conflict (lot_id) do nothing;
  return jsonb_build_object('ok', true);
end $$;

-- 5. 下処理マスタ（仕掛品）
create table if not exists public.hq_prep_masters_v1500 (
  id uuid primary key default gen_random_uuid(),
  item_name text not null,
  name text not null,
  default_pack_kg numeric not null check (default_pack_kg > 0),
  expiry_days integer not null default 2 check (expiry_days >= 0),
  active boolean not null default true,
  sort_order integer not null default 0,
  created_by_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (item_name, name)
);
create or replace function public.hq_save_prep_master_v1500(p_id uuid, p_item_name text, p_name text, p_pack_kg numeric, p_expiry_days integer, p_active boolean)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles; r public.hq_prep_masters_v1500%rowtype;
begin
  v := public.hq_actor_v1400(array['admin','hq_worker']);
  if btrim(coalesce(p_item_name,'')) = '' then raise exception '原料の品目を選んでください'; end if;
  if btrim(coalesce(p_name,'')) = '' then raise exception '仕掛品の名前を入れてください'; end if;
  if coalesce(p_pack_kg,0) <= 0 then raise exception '初期入れ数kgを入れてください'; end if;
  if coalesce(p_expiry_days,-1) < 0 then raise exception '使用期限の日数を入れてください'; end if;
  if p_id is null then
    insert into public.hq_prep_masters_v1500(item_name, name, default_pack_kg, expiry_days, active, sort_order, created_by_name)
    values (btrim(p_item_name), btrim(p_name), p_pack_kg, p_expiry_days, coalesce(p_active,true),
      (select coalesce(max(sort_order),0)+1 from public.hq_prep_masters_v1500), v.display_name)
    on conflict (item_name, name) do update set default_pack_kg = excluded.default_pack_kg, expiry_days = excluded.expiry_days,
      active = excluded.active, updated_at = now()
    returning * into r;
  else
    update public.hq_prep_masters_v1500 set item_name = btrim(p_item_name), name = btrim(p_name), default_pack_kg = p_pack_kg,
      expiry_days = p_expiry_days, active = coalesce(p_active,true), updated_at = now()
    where id = p_id returning * into r;
    if not found then raise exception '仕掛品が見つかりません'; end if;
  end if;
  return jsonb_build_object('ok', true, 'id', r.id);
end $$;

-- 6. スタッフ・班・作業場所・作業名
create table if not exists public.hq_teams_v1500 (
  name text primary key,
  default_group integer not null check (default_group between 1 and 6),
  sort_order integer not null default 0,
  active boolean not null default true
);
insert into public.hq_teams_v1500(name, default_group, sort_order) values
  ('下処理班①',1,1),('下処理班②',2,2),('人参班',3,3),('ライン班',3,4),('製品冷蔵庫セット',3,5),('シール',3,6),('衛生管理',3,7),
  ('手切班',4,8),('機械班',5,9),('原料班',6,10)
on conflict (name) do nothing;

create table if not exists public.hq_staff_v1500 (
  id uuid primary key default gen_random_uuid(),
  qr_key text not null unique default ('HQST-' || replace(gen_random_uuid()::text,'-','')),
  team text not null,
  name text not null,
  print_group integer not null check (print_group between 1 and 6),
  sort_order integer not null default 0,
  deleted_at timestamptz,
  deleted_by_name text,
  created_by_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists hq_staff_v1500_group_idx on public.hq_staff_v1500(print_group, sort_order) where deleted_at is null;

create or replace function public.hq_save_staff_v1500(p_id uuid, p_team text, p_name text, p_group integer)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles; r public.hq_staff_v1500%rowtype;
begin
  v := public.hq_actor_v1400(array['admin','hq_worker']);
  if btrim(coalesce(p_team,'')) = '' then raise exception '班名を選んでください'; end if;
  if btrim(coalesce(p_name,'')) = '' then raise exception '名前を入れてください'; end if;
  if coalesce(p_group,0) not between 1 and 6 then raise exception '印刷グループ（①〜⑥）を選んでください'; end if;
  insert into public.hq_teams_v1500(name, default_group, sort_order)
  values (btrim(p_team), p_group, (select coalesce(max(sort_order),0)+1 from public.hq_teams_v1500))
  on conflict (name) do nothing;
  if p_id is null then
    insert into public.hq_staff_v1500(team, name, print_group, sort_order, created_by_name)
    values (btrim(p_team), btrim(p_name), p_group, (select coalesce(max(sort_order),0)+1 from public.hq_staff_v1500), v.display_name)
    returning * into r;
  else
    update public.hq_staff_v1500 set team = btrim(p_team), name = btrim(p_name), print_group = p_group, updated_at = now()
    where id = p_id and deleted_at is null returning * into r;
    if not found then raise exception 'スタッフが見つかりません'; end if;
  end if;
  return jsonb_build_object('ok', true, 'id', r.id, 'qr_key', r.qr_key);
end $$;

create or replace function public.hq_delete_staff_v1500(p_id uuid)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles;
begin
  v := public.hq_actor_v1400(array['admin','hq_worker']);
  if exists (select 1 from public.hq_work_members_v1500 where staff_id = p_id and end_at is null) then
    raise exception 'この人は作業中です。作業を終えてから削除してください';
  end if;
  update public.hq_staff_v1500 set deleted_at = now(), deleted_by_name = v.display_name, updated_at = now()
  where id = p_id and deleted_at is null;
  if not found then raise exception 'スタッフが見つかりません'; end if;
  return jsonb_build_object('ok', true);
end $$;

create table if not exists public.hq_places_v1500 (
  name text primary key,
  sort_order integer not null default 0,
  active boolean not null default true
);
insert into public.hq_places_v1500(name, sort_order) values ('下処理室①',1),('下処理室②',2) on conflict (name) do nothing;

create table if not exists public.hq_tasks_v1500 (
  name text primary key,
  kind text not null check (kind in ('下処理','清掃','作業')),
  sort_order integer not null default 0,
  active boolean not null default true
);
insert into public.hq_tasks_v1500(name, kind, sort_order) values ('下処理','下処理',1),('清掃','清掃',2) on conflict (name) do nothing;

create or replace function public.hq_save_place_v1500(p_name text, p_active boolean)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles;
begin
  v := public.hq_actor_v1400(array['admin','hq_worker']);
  if btrim(coalesce(p_name,'')) = '' then raise exception '作業場所の名前を入れてください'; end if;
  insert into public.hq_places_v1500(name, active, sort_order) values (btrim(p_name), coalesce(p_active,true),
    (select coalesce(max(sort_order),0)+1 from public.hq_places_v1500))
  on conflict (name) do update set active = excluded.active;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.hq_save_task_v1500(p_name text, p_active boolean)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles;
begin
  v := public.hq_actor_v1400(array['admin','hq_worker']);
  if btrim(coalesce(p_name,'')) = '' then raise exception '作業名を入れてください'; end if;
  if btrim(p_name) in ('下処理','清掃') and p_active is false then raise exception '「下処理」「清掃」は非表示にできません'; end if;
  insert into public.hq_tasks_v1500(name, kind, active, sort_order) values (btrim(p_name), '作業', coalesce(p_active,true),
    (select coalesce(max(sort_order),0)+1 from public.hq_tasks_v1500))
  on conflict (name) do update set active = excluded.active;
  return jsonb_build_object('ok', true);
end $$;

-- 7. 作業（下処理・その他の作業・清掃）と作業者
create table if not exists public.hq_works_v1500 (
  id uuid primary key default gen_random_uuid(),
  operation_id uuid unique,
  kind text not null check (kind in ('下処理','作業','清掃')),
  task_name text not null,
  place text,
  work_date date not null,
  status text not null check (status in ('作業中','入力待ち','清掃中','完了','取消')),
  prep_master_id uuid references public.hq_prep_masters_v1500(id),
  raw_item_name text,
  product_name text,
  expiry_days integer,
  waste_kg numeric,
  yield_kg numeric,
  inputs_saved_at timestamptz,
  inputs_saved_by_name text,
  label_printed_at timestamptz,
  label_print_count integer not null default 0,
  confirm_status text not null default '未確定' check (confirm_status in ('未確定','確定','取消')),
  confirmed_at timestamptz,
  confirmed_by_name text,
  stock_applied boolean not null default false,
  history jsonb not null default '[]'::jsonb,
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  clean_started_at timestamptz,
  clean_ended_at timestamptz,
  created_by_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists hq_works_v1500_date_idx on public.hq_works_v1500(work_date desc);
create index if not exists hq_works_v1500_status_idx on public.hq_works_v1500(status);

create table if not exists public.hq_work_materials_v1500 (
  id uuid primary key default gen_random_uuid(),
  work_id uuid not null references public.hq_works_v1500(id),
  lot_id uuid not null references public.hq_lots_v1400(id),
  lot_no text,
  item_name text,
  unit text,
  pack_kg numeric,
  qty numeric,
  movement_id uuid,
  created_at timestamptz not null default now(),
  unique (work_id, lot_id)
);

create table if not exists public.hq_work_members_v1500 (
  id uuid primary key default gen_random_uuid(),
  work_id uuid not null references public.hq_works_v1500(id),
  staff_id uuid not null references public.hq_staff_v1500(id),
  staff_name text not null,
  team text,
  phase text not null check (phase in ('作業','清掃')),
  start_at timestamptz not null,
  end_at timestamptz,
  end_reason text,
  fixed_by_name text,
  fixed_at timestamptz
);
create index if not exists hq_work_members_v1500_work_idx on public.hq_work_members_v1500(work_id);
create index if not exists hq_work_members_v1500_open_idx on public.hq_work_members_v1500(staff_id) where end_at is null;

create or replace function public.hq_work_add_members_v1500(p_work_id uuid, p_staff_ids uuid[], p_phase text)
returns integer language plpgsql security definer set search_path to ''
as $$
declare s public.hq_staff_v1500%rowtype; n integer := 0; busy text;
begin
  for s in select * from public.hq_staff_v1500 where id = any(coalesce(p_staff_ids,'{}')) loop
    if s.deleted_at is not null then raise exception '%さんは削除済みです', s.name; end if;
    select w.task_name || coalesce('（' || w.place || '）','') into busy
    from public.hq_work_members_v1500 m join public.hq_works_v1500 w on w.id = m.work_id
    where m.staff_id = s.id and m.end_at is null and m.work_id <> p_work_id limit 1;
    if busy is not null then raise exception '%さんは、ほかの作業（%）に入っています。先にそちらを終えるか、抜けてください', s.name, busy; end if;
    if exists (select 1 from public.hq_work_members_v1500 where staff_id = s.id and work_id = p_work_id and end_at is null) then continue; end if;
    insert into public.hq_work_members_v1500(work_id, staff_id, staff_name, team, phase, start_at)
    values (p_work_id, s.id, s.name, s.team, p_phase, now());
    n := n + 1;
  end loop;
  return n;
end $$;

create or replace function public.hq_work_start_v1500(p_operation_id uuid, p_kind text, p_task_name text, p_place text,
  p_master_id uuid, p_lot_ids uuid[], p_staff_ids uuid[])
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles; w public.hq_works_v1500%rowtype; m public.hq_prep_masters_v1500%rowtype; l public.hq_lots_v1400%rowtype;
  v_task text; v_raw text;
begin
  v := public.hq_actor_v1400(array['admin','hq_worker','hq_prep']);
  select * into w from public.hq_works_v1500 where operation_id = p_operation_id;
  if found then return jsonb_build_object('ok', true, 'already', true, 'id', w.id); end if;
  if p_kind not in ('下処理','作業','清掃') then raise exception '作業の種類が正しくありません'; end if;
  if coalesce(array_length(p_staff_ids,1),0) < 1 then raise exception '作業する人のスタッフQRを読み取ってください'; end if;
  if p_kind = '下処理' then
    select * into m from public.hq_prep_masters_v1500 where id = p_master_id and active;
    if not found then raise exception '仕掛品を選んでください'; end if;
    if coalesce(array_length(p_lot_ids,1),0) < 1 then raise exception '原料のQRを読み取ってください'; end if;
    for l in select * from public.hq_lots_v1400 where id = any(p_lot_ids) loop
      if l.status not in ('在庫あり','在庫なし') then raise exception '原料 % は受け入れが確定していません', l.lot_no; end if;
      if l.item_name <> m.item_name then raise exception '原料 %（%）は、仕掛品「%」の原料（%）と違います', l.lot_no, l.item_name, m.name, m.item_name; end if;
    end loop;
    v_task := '下処理'; v_raw := m.item_name;
  elsif p_kind = '清掃' then
    v_task := '清掃';
  else
    select name into v_task from public.hq_tasks_v1500 where name = btrim(coalesce(p_task_name,'')) and kind = '作業' and active;
    if v_task is null then raise exception '作業名を選んでください'; end if;
  end if;
  insert into public.hq_works_v1500(operation_id, kind, task_name, place, work_date, status, prep_master_id, raw_item_name,
    product_name, expiry_days, started_at, clean_started_at, created_by_name)
  values (p_operation_id, p_kind, v_task, nullif(btrim(coalesce(p_place,'')),''), (now() at time zone 'Asia/Tokyo')::date,
    case when p_kind = '清掃' then '清掃中' else '作業中' end, m.id, v_raw, m.name, m.expiry_days, now(),
    case when p_kind = '清掃' then now() end, v.display_name)
  returning * into w;
  if p_kind = '下処理' then
    insert into public.hq_work_materials_v1500(work_id, lot_id, lot_no, item_name, unit, pack_kg)
    select w.id, l2.id, l2.lot_no, l2.item_name, l2.unit,
      case when l2.unit = 'kg' then null else public.hq_pack_kg_v1500(l2.pack_weight) end
    from public.hq_lots_v1400 l2 where l2.id = any(p_lot_ids)
    on conflict (work_id, lot_id) do nothing;
  end if;
  perform public.hq_work_add_members_v1500(w.id, p_staff_ids, case when p_kind = '清掃' then '清掃' else '作業' end);
  return jsonb_build_object('ok', true, 'id', w.id);
end $$;

create or replace function public.hq_work_join_v1500(p_work_id uuid, p_staff_ids uuid[])
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles; w public.hq_works_v1500%rowtype; n integer;
begin
  v := public.hq_actor_v1400(array['admin','hq_worker','hq_prep']);
  select * into w from public.hq_works_v1500 where id = p_work_id for update;
  if not found or w.status not in ('作業中','清掃中') then raise exception 'この作業には、いま途中から入れません（%）', coalesce(w.status,''); end if;
  n := public.hq_work_add_members_v1500(w.id, p_staff_ids, case when w.status = '清掃中' then '清掃' else '作業' end);
  update public.hq_works_v1500 set updated_at = now() where id = w.id;
  return jsonb_build_object('ok', true, 'added', n);
end $$;

create or replace function public.hq_work_leave_v1500(p_work_id uuid, p_staff_id uuid)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles;
begin
  v := public.hq_actor_v1400(array['admin','hq_worker','hq_prep']);
  update public.hq_work_members_v1500 set end_at = now(), end_reason = '途中で抜けた'
  where work_id = p_work_id and staff_id = p_staff_id and end_at is null;
  if not found then raise exception 'この人は、この作業に入っていません'; end if;
  update public.hq_works_v1500 set updated_at = now() where id = p_work_id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.hq_work_end_v1500(p_work_id uuid)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles; w public.hq_works_v1500%rowtype;
begin
  v := public.hq_actor_v1400(array['admin','hq_worker','hq_prep']);
  select * into w from public.hq_works_v1500 where id = p_work_id for update;
  if not found then raise exception '作業が見つかりません'; end if;
  if w.status <> '作業中' then return jsonb_build_object('ok', true, 'already', true, 'status', w.status); end if;
  update public.hq_work_members_v1500 set end_at = now(), end_reason = '作業終了' where work_id = w.id and end_at is null;
  update public.hq_works_v1500 set status = case when w.kind = '下処理' then '入力待ち' else '完了' end, ended_at = now(), updated_at = now()
  where id = w.id;
  return jsonb_build_object('ok', true, 'status', case when w.kind = '下処理' then '入力待ち' else '完了' end);
end $$;

create or replace function public.hq_work_check_inputs_v1500(p_work_id uuid, p_materials jsonb, p_waste_kg numeric, p_yield_kg numeric)
returns void language plpgsql security definer set search_path to ''
as $$
declare r jsonb; n integer := 0;
begin
  if jsonb_typeof(p_materials) <> 'array' then raise exception '使用原料の形が正しくありません'; end if;
  if p_waste_kg is null or p_waste_kg < 0 then raise exception '廃棄（kg）を入れてください（無ければ0）'; end if;
  if p_yield_kg is null or p_yield_kg < 0 then raise exception '出来高（kg）を入れてください'; end if;
  for r in select * from jsonb_array_elements(p_materials) loop
    if not exists (select 1 from public.hq_work_materials_v1500 where id = (r->>'id')::uuid and work_id = p_work_id) then
      raise exception '使用原料が見つかりません';
    end if;
    if nullif(r->>'qty','') is null or (r->>'qty')::numeric < 0 then raise exception '使用原料の数を入れてください'; end if;
    update public.hq_work_materials_v1500 set qty = (r->>'qty')::numeric where id = (r->>'id')::uuid;
    n := n + 1;
  end loop;
  if exists (select 1 from public.hq_work_materials_v1500 where work_id = p_work_id and qty is null) then
    raise exception 'すべての原料の使用数を入れてください';
  end if;
end $$;

create or replace function public.hq_work_save_inputs_v1500(p_work_id uuid, p_materials jsonb, p_waste_kg numeric, p_yield_kg numeric)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles; w public.hq_works_v1500%rowtype;
begin
  v := public.hq_actor_v1400(array['admin','hq_worker','hq_prep']);
  select * into w from public.hq_works_v1500 where id = p_work_id for update;
  if not found or w.kind <> '下処理' then raise exception '下処理が見つかりません'; end if;
  if w.status = '作業中' then raise exception '先に「作業終了」をしてください'; end if;
  if w.status = '取消' or w.confirm_status <> '未確定' then raise exception 'この下処理は確定済みか取消済みです。直すときは本社社員に頼んでください'; end if;
  perform public.hq_work_check_inputs_v1500(p_work_id, p_materials, p_waste_kg, p_yield_kg);
  update public.hq_works_v1500 set waste_kg = p_waste_kg, yield_kg = p_yield_kg, inputs_saved_at = now(),
    inputs_saved_by_name = v.display_name, updated_at = now() where id = w.id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.hq_work_to_clean_v1500(p_work_id uuid, p_printed boolean)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles; w public.hq_works_v1500%rowtype; ids uuid[];
begin
  v := public.hq_actor_v1400(array['admin','hq_worker','hq_prep']);
  select * into w from public.hq_works_v1500 where id = p_work_id for update;
  if not found or w.kind <> '下処理' then raise exception '下処理が見つかりません'; end if;
  if w.status <> '入力待ち' then return jsonb_build_object('ok', true, 'already', true, 'status', w.status); end if;
  if w.inputs_saved_at is null then raise exception '先に使用原料・廃棄・出来高を入れてください'; end if;
  select array_agg(distinct staff_id) into ids from public.hq_work_members_v1500
  where work_id = w.id and phase = '作業' and end_reason = '作業終了';
  update public.hq_works_v1500 set status = '清掃中', clean_started_at = now(),
    label_printed_at = case when p_printed then now() else label_printed_at end,
    label_print_count = label_print_count + case when p_printed then 1 else 0 end, updated_at = now()
  where id = w.id;
  if ids is not null then
    insert into public.hq_work_members_v1500(work_id, staff_id, staff_name, team, phase, start_at)
    select w.id, s.id, s.name, s.team, '清掃', now() from public.hq_staff_v1500 s
    where s.id = any(ids) and s.deleted_at is null
      and not exists (select 1 from public.hq_work_members_v1500 o where o.staff_id = s.id and o.end_at is null);
  end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.hq_work_mark_printed_v1500(p_work_id uuid)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles;
begin
  v := public.hq_actor_v1400(array['admin','hq_worker','hq_prep']);
  update public.hq_works_v1500 set label_printed_at = now(), label_print_count = label_print_count + 1, updated_at = now()
  where id = p_work_id and kind = '下処理';
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.hq_work_clean_end_v1500(p_work_id uuid)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles; w public.hq_works_v1500%rowtype;
begin
  v := public.hq_actor_v1400(array['admin','hq_worker','hq_prep']);
  select * into w from public.hq_works_v1500 where id = p_work_id for update;
  if not found then raise exception '作業が見つかりません'; end if;
  if w.status <> '清掃中' then return jsonb_build_object('ok', true, 'already', true, 'status', w.status); end if;
  update public.hq_work_members_v1500 set end_at = now(), end_reason = '清掃終了' where work_id = w.id and end_at is null;
  update public.hq_works_v1500 set status = '完了', clean_ended_at = now(), updated_at = now() where id = w.id;
  return jsonb_build_object('ok', true);
end $$;

-- 間違えて始めた作業の取消（下処理班は「作業中」のときだけ）
create or replace function public.hq_work_cancel_v1500(p_work_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles; w public.hq_works_v1500%rowtype;
begin
  v := public.hq_actor_v1400(array['admin','hq_worker','hq_prep']);
  select * into w from public.hq_works_v1500 where id = p_work_id for update;
  if not found then raise exception '作業が見つかりません'; end if;
  if w.status = '取消' then return jsonb_build_object('ok', true, 'already', true); end if;
  if w.confirm_status = '確定' then raise exception '確定済みの下処理は「下処理の確認」から取り消してください'; end if;
  if v.role = 'hq_prep' and w.status <> '作業中' then raise exception '作業終了のあとは、本社社員に取り消してもらってください' using errcode = '42501'; end if;
  update public.hq_work_members_v1500 set end_at = now(), end_reason = '取消' where work_id = w.id and end_at is null;
  update public.hq_works_v1500 set status = '取消', confirm_status = case when kind = '下処理' then '取消' else confirm_status end,
    history = history || jsonb_build_array(jsonb_build_object('at', now(), 'by', v.display_name, 'action', '作業の取消', 'reason', p_reason)),
    updated_at = now() where id = w.id;
  return jsonb_build_object('ok', true);
end $$;

-- 読み忘れの修正（本社社員・管理者）
create or replace function public.hq_member_fix_v1500(p_member_id uuid, p_start timestamptz, p_end timestamptz, p_delete boolean)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles;
begin
  v := public.hq_actor_v1400(array['admin','hq_worker']);
  if coalesce(p_delete,false) then
    delete from public.hq_work_members_v1500 where id = p_member_id;
    return jsonb_build_object('ok', true);
  end if;
  if p_start is null then raise exception '開始の時刻を入れてください'; end if;
  if p_end is not null and p_end < p_start then raise exception '終了が開始より前になっています'; end if;
  update public.hq_work_members_v1500 set start_at = p_start, end_at = p_end,
    end_reason = case when p_end is null then null else coalesce(end_reason,'修正') end,
    fixed_by_name = v.display_name, fixed_at = now() where id = p_member_id;
  if not found then raise exception '記録が見つかりません'; end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.hq_member_add_v1500(p_work_id uuid, p_staff_id uuid, p_phase text, p_start timestamptz, p_end timestamptz)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles; s public.hq_staff_v1500%rowtype;
begin
  v := public.hq_actor_v1400(array['admin','hq_worker']);
  select * into s from public.hq_staff_v1500 where id = p_staff_id;
  if not found then raise exception 'スタッフが見つかりません'; end if;
  if p_phase not in ('作業','清掃') then raise exception '作業か清掃かを選んでください'; end if;
  if p_start is null or p_end is null or p_end < p_start then raise exception '開始と終了の時刻を正しく入れてください'; end if;
  if not exists (select 1 from public.hq_works_v1500 where id = p_work_id) then raise exception '作業が見つかりません'; end if;
  insert into public.hq_work_members_v1500(work_id, staff_id, staff_name, team, phase, start_at, end_at, end_reason, fixed_by_name, fixed_at)
  values (p_work_id, s.id, s.name, s.team, p_phase, p_start, p_end, '追加（修正）', v.display_name, now());
  return jsonb_build_object('ok', true);
end $$;

-- 8. 廃棄一覧（下処理ロス・原料出しロス・原料廃棄）
create table if not exists public.hq_waste_v1500 (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('下処理ロス','原料出しロス','原料廃棄')),
  waste_date date not null,
  item_name text not null,
  kg numeric not null default 0,
  qty numeric,
  unit text,
  lot_id uuid,
  lot_no text,
  work_id uuid,
  movement_id uuid,
  memo text,
  user_name text,
  created_at timestamptz not null default now(),
  cancelled_at timestamptz,
  cancelled_by_name text
);
create index if not exists hq_waste_v1500_date_idx on public.hq_waste_v1500(waste_date desc);

create or replace function public.hq_rawout_loss_v1500(p_date date, p_item_name text, p_kg numeric, p_memo text)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles;
begin
  v := public.hq_actor_v1400(array['admin','hq_worker','hq_receiver']);
  if btrim(coalesce(p_item_name,'')) = '' then raise exception '品目を選んでください'; end if;
  if coalesce(p_kg,0) <= 0 then raise exception 'kgを入れてください'; end if;
  if p_date is null or p_date > (now() at time zone 'Asia/Tokyo')::date then raise exception '日付が正しくありません'; end if;
  insert into public.hq_waste_v1500(kind, waste_date, item_name, kg, memo, user_name)
  values ('原料出しロス', p_date, btrim(p_item_name), p_kg, nullif(btrim(coalesce(p_memo,'')),''), v.display_name);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.hq_dispose_v1500(p_operation_id uuid, p_lot_id uuid, p_qty numeric, p_memo text)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles; l public.hq_lots_v1400%rowtype; v_after numeric; v_mid uuid; v_kg numeric;
begin
  v := public.hq_actor_v1400(array['admin','hq_worker','hq_receiver']);
  if exists (select 1 from public.hq_lot_movements_v1400 where operation_id = p_operation_id) then
    return jsonb_build_object('ok', true, 'already', true);
  end if;
  select * into l from public.hq_lots_v1400 where id = p_lot_id for update;
  if not found or l.status <> '在庫あり' then raise exception 'この原料は在庫がありません'; end if;
  if coalesce(p_qty,0) <= 0 then raise exception '数量を入れてください'; end if;
  if p_qty > l.current_qty then raise exception '在庫（%）より多くは廃棄できません', l.current_qty || l.unit; end if;
  v_after := l.current_qty - p_qty;
  v_kg := case when l.unit = 'kg' then p_qty else round(p_qty * public.hq_pack_kg_v1500(l.pack_weight), 2) end;
  update public.hq_lots_v1400 set current_qty = v_after, status = case when v_after > 0 then '在庫あり' else '在庫なし' end, updated_at = now()
  where id = l.id;
  insert into public.hq_lot_movements_v1400(operation_id, lot_id, movement_type, qty, unit, before_qty, after_qty, memo, item_name, lot_no, user_id, user_name)
  values (p_operation_id, l.id, '廃棄', p_qty, l.unit, l.current_qty, v_after, nullif(btrim(coalesce(p_memo,'')),''), l.item_name, l.lot_no, v.id, v.display_name)
  returning id into v_mid;
  insert into public.hq_waste_v1500(kind, waste_date, item_name, kg, qty, unit, lot_id, lot_no, movement_id, memo, user_name)
  values ('原料廃棄', (now() at time zone 'Asia/Tokyo')::date, l.item_name, coalesce(v_kg,0), p_qty, l.unit, l.id, l.lot_no, v_mid,
    nullif(btrim(coalesce(p_memo,'')),''), v.display_name);
  return jsonb_build_object('ok', true, 'after_qty', v_after, 'kg_unknown', v_kg is null);
end $$;

create or replace function public.hq_waste_cancel_v1500(p_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles; r public.hq_waste_v1500%rowtype; m public.hq_lot_movements_v1400%rowtype; l public.hq_lots_v1400%rowtype; v_after numeric;
begin
  v := public.hq_actor_v1400(array['admin','hq_worker']);
  select * into r from public.hq_waste_v1500 where id = p_id for update;
  if not found or r.cancelled_at is not null then raise exception '取り消せる廃棄が見つかりません'; end if;
  if r.kind = '下処理ロス' then raise exception '下処理ロスは「下処理の確認」で直してください'; end if;
  if r.kind = '原料廃棄' and r.movement_id is not null then
    select * into m from public.hq_lot_movements_v1400 where id = r.movement_id for update;
    if found and m.cancelled_at is null then
      select * into l from public.hq_lots_v1400 where id = m.lot_id for update;
      v_after := l.current_qty + m.qty;
      update public.hq_lots_v1400 set current_qty = v_after, status = case when v_after > 0 then '在庫あり' else '在庫なし' end, updated_at = now() where id = l.id;
      update public.hq_lot_movements_v1400 set cancelled_at = now(), cancelled_by_name = v.display_name where id = m.id;
      insert into public.hq_lot_movements_v1400(operation_id, lot_id, movement_type, qty, unit, before_qty, after_qty, reason, item_name, lot_no, user_id, user_name, reversed_movement_id)
      values (gen_random_uuid(), l.id, '廃棄取消', m.qty, l.unit, l.current_qty, v_after, nullif(btrim(coalesce(p_reason,'')),''), l.item_name, l.lot_no, v.id, v.display_name, m.id);
    end if;
  end if;
  update public.hq_waste_v1500 set cancelled_at = now(), cancelled_by_name = v.display_name where id = r.id;
  return jsonb_build_object('ok', true);
end $$;

-- 9. 下処理の確定・修正・取消（本社社員・管理者）
create or replace function public.hq_prep_unapply_v1500(p_work_id uuid, p_by public.profiles)
returns void language plpgsql security definer set search_path to ''
as $$
declare mt public.hq_work_materials_v1500%rowtype; m public.hq_lot_movements_v1400%rowtype; l public.hq_lots_v1400%rowtype; v_after numeric;
begin
  for mt in select * from public.hq_work_materials_v1500 where work_id = p_work_id and movement_id is not null for update loop
    select * into m from public.hq_lot_movements_v1400 where id = mt.movement_id for update;
    if found and m.cancelled_at is null then
      select * into l from public.hq_lots_v1400 where id = m.lot_id for update;
      v_after := l.current_qty + m.qty;
      update public.hq_lots_v1400 set current_qty = v_after, status = case when v_after > 0 then '在庫あり' else '在庫なし' end, updated_at = now() where id = l.id;
      update public.hq_lot_movements_v1400 set cancelled_at = now(), cancelled_by_name = p_by.display_name where id = m.id;
      insert into public.hq_lot_movements_v1400(operation_id, lot_id, movement_type, qty, unit, before_qty, after_qty, item_name, lot_no, user_id, user_name, reversed_movement_id, work_id)
      values (gen_random_uuid(), l.id, '下処理取消', m.qty, l.unit, l.current_qty, v_after, l.item_name, l.lot_no, p_by.id, p_by.display_name, m.id, p_work_id);
    end if;
    update public.hq_work_materials_v1500 set movement_id = null where id = mt.id;
  end loop;
  update public.hq_waste_v1500 set cancelled_at = now(), cancelled_by_name = p_by.display_name
  where work_id = p_work_id and kind = '下処理ロス' and cancelled_at is null;
  update public.hq_works_v1500 set stock_applied = false where id = p_work_id;
end $$;

create or replace function public.hq_prep_confirm_v1500(p_work_id uuid, p_materials jsonb, p_waste_kg numeric, p_yield_kg numeric, p_reason text)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles; w public.hq_works_v1500%rowtype; mt public.hq_work_materials_v1500%rowtype; l public.hq_lots_v1400%rowtype;
  v_after numeric; v_mid uuid; v_apply boolean; v_at timestamptz; v_was text; v_label_changed boolean := false;
begin
  v := public.hq_actor_v1400(array['admin','hq_worker']);
  select * into w from public.hq_works_v1500 where id = p_work_id for update;
  if not found or w.kind <> '下処理' then raise exception '下処理が見つかりません'; end if;
  if w.status in ('作業中','取消') or w.confirm_status = '取消' then raise exception 'この下処理は確定できません（%）', w.status; end if;
  v_was := w.confirm_status;
  if v_was = '確定' then perform public.hq_prep_unapply_v1500(w.id, v); end if;
  perform public.hq_work_check_inputs_v1500(w.id, p_materials, p_waste_kg, p_yield_kg);
  v_apply := public.hq_setting_on_v1500('stage2_stock');
  v_at := coalesce(w.ended_at, w.started_at);
  if v_apply then
    for mt in select * from public.hq_work_materials_v1500 where work_id = w.id and coalesce(qty,0) > 0 order by created_at loop
      select * into l from public.hq_lots_v1400 where id = mt.lot_id for update;
      if l.status not in ('在庫あり','在庫なし') then raise exception '原料 % は在庫から減らせない状態です（%）', l.lot_no, l.status; end if;
      if mt.qty > l.current_qty then
        raise exception '原料 % の在庫（%）より、使用数（%）が多くなっています。在庫を実数調整してから確定してください', l.lot_no, l.current_qty || l.unit, mt.qty || l.unit;
      end if;
      v_after := l.current_qty - mt.qty;
      update public.hq_lots_v1400 set current_qty = v_after, status = case when v_after > 0 then '在庫あり' else '在庫なし' end, updated_at = now() where id = l.id;
      insert into public.hq_lot_movements_v1400(operation_id, lot_id, movement_type, qty, unit, before_qty, after_qty, destination, memo, item_name, lot_no, user_id, user_name, occurred_at, work_id)
      values (gen_random_uuid(), l.id, '下処理使用', mt.qty, l.unit, l.current_qty, v_after, '下処理', w.product_name, l.item_name, l.lot_no, v.id, v.display_name, v_at, w.id)
      returning id into v_mid;
      update public.hq_work_materials_v1500 set movement_id = v_mid where id = mt.id;
    end loop;
  end if;
  if p_waste_kg > 0 then
    insert into public.hq_waste_v1500(kind, waste_date, item_name, kg, work_id, memo, user_name)
    values ('下処理ロス', w.work_date, coalesce(w.raw_item_name, w.product_name), p_waste_kg, w.id, w.product_name, v.display_name);
  end if;
  update public.hq_works_v1500 set waste_kg = p_waste_kg, yield_kg = p_yield_kg, confirm_status = '確定', confirmed_at = now(),
    confirmed_by_name = v.display_name, stock_applied = v_apply,
    inputs_saved_at = coalesce(inputs_saved_at, now()), inputs_saved_by_name = coalesce(inputs_saved_by_name, v.display_name),
    history = history || jsonb_build_array(jsonb_build_object('at', now(), 'by', v.display_name,
      'action', case when v_was = '確定' then '修正して確定' else '確定' end, 'reason', nullif(btrim(coalesce(p_reason,'')),''),
      'stock', v_apply)),
    updated_at = now()
  where id = w.id;
  return jsonb_build_object('ok', true, 'stock_applied', v_apply);
end $$;

create or replace function public.hq_prep_cancel_v1500(p_work_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles; w public.hq_works_v1500%rowtype;
begin
  v := public.hq_actor_v1400(array['admin','hq_worker']);
  if btrim(coalesce(p_reason,'')) = '' then raise exception '取消の理由を入れてください'; end if;
  select * into w from public.hq_works_v1500 where id = p_work_id for update;
  if not found or w.kind <> '下処理' then raise exception '下処理が見つかりません'; end if;
  if w.confirm_status = '取消' then return jsonb_build_object('ok', true, 'already', true); end if;
  perform public.hq_prep_unapply_v1500(w.id, v);
  update public.hq_work_members_v1500 set end_at = now(), end_reason = '取消' where work_id = w.id and end_at is null;
  update public.hq_works_v1500 set confirm_status = '取消', status = case when status in ('作業中','入力待ち','清掃中') then '取消' else status end,
    history = history || jsonb_build_array(jsonb_build_object('at', now(), 'by', v.display_name, 'action', '取消', 'reason', p_reason)),
    updated_at = now() where id = w.id;
  return jsonb_build_object('ok', true);
end $$;

-- 10. 原料出しなどの出庫（在庫反映オンの後は「下処理」への使用出庫を止める）
insert into public.hq_destinations_v1400(name, sort_order) values ('原料出し',2) on conflict (name) do nothing;
create or replace function public.hq_outbound_v1500(p_operation_id uuid, p_lot_id uuid, p_qty numeric, p_destination text, p_memo text default null)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles; l public.hq_lots_v1400%rowtype; v_after numeric; v_on boolean;
begin
  v_on := public.hq_setting_on_v1500('stage2_stock');
  if p_destination = '原料出し' then
    v := public.hq_actor_v1400(case when v_on then array['admin','hq_worker','hq_receiver'] else array['admin','hq_worker','hq_receiver','hq_prep'] end);
  else
    if v_on then raise exception '下処理で使う原料は、下処理の確定で在庫から減ります（使用出庫は使いません）'; end if;
    v := public.hq_actor_v1400(array['admin','hq_worker','hq_prep']);
  end if;
  if exists (select 1 from public.hq_lot_movements_v1400 where operation_id = p_operation_id) then
    return jsonb_build_object('ok', true, 'already', true);
  end if;
  if not exists (select 1 from public.hq_destinations_v1400 where name = p_destination and active) then
    raise exception '出庫先を選んでください';
  end if;
  select * into l from public.hq_lots_v1400 where id = p_lot_id for update;
  if not found then raise exception '原料が見つかりません'; end if;
  if l.status = '入荷待ち' then raise exception 'まだ受け入れが確定していません。先に品質評価と確定をしてください'; end if;
  if l.status <> '在庫あり' then raise exception 'この原料は在庫がありません'; end if;
  if coalesce(p_qty,0) <= 0 then raise exception '数量を入れてください'; end if;
  if p_qty > l.current_qty then raise exception '在庫（%）より多くは出庫できません', l.current_qty || l.unit; end if;
  v_after := l.current_qty - p_qty;
  update public.hq_lots_v1400 set current_qty = v_after, status = case when v_after > 0 then '在庫あり' else '在庫なし' end, updated_at = now()
  where id = l.id;
  insert into public.hq_lot_movements_v1400(operation_id, lot_id, movement_type, qty, unit, before_qty, after_qty, destination, memo, item_name, lot_no, user_id, user_name)
  values (p_operation_id, l.id, '出庫', p_qty, l.unit, l.current_qty, v_after, p_destination, p_memo, l.item_name, l.lot_no, v.id, v.display_name);
  return jsonb_build_object('ok', true, 'after_qty', v_after);
end $$;

-- 11. 在庫入力（原料・仕掛品。1行＝入れ数kg×ケース数）
create table if not exists public.hq_stock_counts_v1500 (
  id uuid primary key default gen_random_uuid(),
  count_date date not null,
  kind text not null check (kind in ('原料','仕掛品')),
  item_name text not null,
  master_id uuid,
  manual boolean not null default false,
  lines jsonb not null default '[]'::jsonb,
  total_cases numeric not null default 0,
  total_kg numeric not null default 0,
  user_id uuid,
  user_name text,
  updated_at timestamptz not null default now(),
  unique (count_date, kind, item_name)
);
-- これまでの通常在庫（ケース＋バラkg）を、入れ数＝1ケースkgの1行として引き継ぐ
insert into public.hq_stock_counts_v1500(count_date, kind, item_name, lines, total_cases, total_kg, user_id, user_name, updated_at)
select c.count_date, '原料', c.item_name,
  jsonb_build_array(jsonb_build_object('pack_kg', c.pack_weight_kg,
    'cases', round(coalesce(c.cases,0) + case when coalesce(c.pack_weight_kg,0) > 0 then coalesce(c.bara_kg,0) / c.pack_weight_kg else 0 end, 3))),
  round(coalesce(c.cases,0) + case when coalesce(c.pack_weight_kg,0) > 0 then coalesce(c.bara_kg,0) / c.pack_weight_kg else 0 end, 3),
  c.total_kg, c.user_id, c.user_name, c.updated_at
from public.hq_normal_counts_v1410 c
on conflict (count_date, kind, item_name) do nothing;

create or replace function public.hq_save_stock_counts_v1500(p_date date, p_rows jsonb)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles; r jsonb; ln jsonb; v_kind text; v_name text; v_lines jsonb; v_cases numeric; v_kg numeric;
  v_pack numeric; v_c numeric; n_saved int := 0; n_cleared int := 0; v_master uuid;
begin
  v := public.hq_actor_v1400(array['admin','hq_worker','hq_receiver']);
  if p_date is null then raise exception '日付を選んでください'; end if;
  if p_date > (now() at time zone 'Asia/Tokyo')::date then raise exception '先の日付には入力できません'; end if;
  if jsonb_typeof(p_rows) <> 'array' then raise exception '入力の形が正しくありません'; end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    v_kind := r->>'kind'; v_name := btrim(coalesce(r->>'item_name',''));
    if v_kind not in ('原料','仕掛品') then raise exception '原料か仕掛品かが分かりません'; end if;
    if v_name = '' then raise exception '品名を入れてください'; end if;
    v_master := nullif(r->>'master_id','')::uuid;
    if v_kind = '原料' and not exists (select 1 from public.hq_normal_items_v1410 where name = v_name) then
      raise exception '原料の品目「%」が見つかりません', v_name;
    end if;
    v_lines := '[]'::jsonb; v_cases := 0; v_kg := 0;
    for ln in select * from jsonb_array_elements(coalesce(r->'lines','[]'::jsonb)) loop
      v_pack := nullif(ln->>'pack_kg','')::numeric; v_c := nullif(ln->>'cases','')::numeric;
      if v_pack is null and v_c is null then continue; end if;
      if v_pack is null or v_pack <= 0 then raise exception '「%」の入れ数kgを入れてください', v_name; end if;
      if v_c is null or v_c < 0 then raise exception '「%」のケース数を入れてください', v_name; end if;
      v_lines := v_lines || jsonb_build_array(jsonb_build_object('pack_kg', v_pack, 'cases', v_c));
      v_cases := v_cases + v_c; v_kg := v_kg + v_pack * v_c;
    end loop;
    if jsonb_array_length(v_lines) = 0 then
      delete from public.hq_stock_counts_v1500 where count_date = p_date and kind = v_kind and item_name = v_name;
      if found then n_cleared := n_cleared + 1; end if;
      continue;
    end if;
    insert into public.hq_stock_counts_v1500(count_date, kind, item_name, master_id, manual, lines, total_cases, total_kg, user_id, user_name, updated_at)
    values (p_date, v_kind, v_name, v_master, coalesce((r->>'manual')::boolean,false), v_lines, v_cases, round(v_kg,2), v.id, v.display_name, now())
    on conflict (count_date, kind, item_name) do update set master_id = excluded.master_id, manual = excluded.manual, lines = excluded.lines,
      total_cases = excluded.total_cases, total_kg = excluded.total_kg, user_id = excluded.user_id, user_name = excluded.user_name, updated_at = now();
    n_saved := n_saved + 1;
  end loop;
  return jsonb_build_object('ok', true, 'saved', n_saved, 'cleared', n_cleared);
end $$;

-- 12. 在庫表（QR品目＋原料＋仕掛品）。QR品目は日ごとの入荷・使用の内訳も返す（使用数量の計算に使う）
create or replace function public.get_hq_stock_table_v1500(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path to ''
as $$
declare v public.profiles; res jsonb;
begin
  v := public.hq_actor_v1400(array['admin','worker','buyer','sales','clerk','office_viewer','viewer','hq_worker','hq_clerk','hq_receiver','hq_prep']);
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 400 then raise exception '期間が正しくありません'; end if;
  with d as (select generate_series(p_from, p_to, interval '1 day')::date dt),
  lots as (
    select l.id, l.item_name, l.unit, case when l.unit = 'kg' then 1::numeric else public.hq_pack_kg_v1500(l.pack_weight) end per
    from public.hq_lots_v1400 l where l.status in ('在庫あり','在庫なし')
  ),
  mv as (
    select m.lot_id, (m.occurred_at at time zone 'Asia/Tokyo')::date dt, m.movement_type, m.destination,
      case m.movement_type when '入庫確定' then m.qty when '出庫' then -m.qty when '実数調整' then m.qty
        when '下処理使用' then -m.qty when '廃棄' then -m.qty else 0 end dq, m.qty
    from public.hq_lot_movements_v1400 m where m.cancelled_at is null
      and m.movement_type in ('入庫確定','出庫','実数調整','下処理使用','廃棄')
      and (m.occurred_at at time zone 'Asia/Tokyo')::date <= p_to
  ),
  items as (select distinct item_name from lots l where exists (select 1 from mv where mv.lot_id = l.id)
            union select name from public.hq_items_v1400 where active),
  qr as (
    select i.item_name, d.dt,
      sum(case when lo.unit = 'kg' then x.q else 0 end) kg_unit_qty,
      sum(case when lo.unit <> 'kg' then x.q else 0 end) case_qty,
      sum(case when lo.per is not null then x.q * lo.per else 0 end) kg,
      sum(case when lo.per is null then x.q else 0 end) unknown_qty,
      sum(case when lo.unit <> 'kg' then x.inq else 0 end) in_cases,
      sum(case when lo.unit = 'kg' then x.inq else 0 end) in_kgu,
      sum(case when lo.per is not null then x.inq * lo.per else 0 end) in_kg,
      sum(case when lo.per is not null then x.wq * lo.per else 0 end) waste_kg,
      sum(case when lo.unit <> 'kg' then x.wq else 0 end) waste_cases,
      sum(case when lo.per is not null then x.rq * lo.per else 0 end) rawout_kg,
      sum(case when lo.unit <> 'kg' then x.rq else 0 end) rawout_cases
    from items i cross join d
    left join lots lo on lo.item_name = i.item_name
    left join lateral (
      select coalesce(sum(mv.dq) filter (where mv.dt <= d.dt),0) q,
        coalesce(sum(mv.qty) filter (where mv.dt = d.dt and mv.movement_type = '入庫確定'),0) inq,
        coalesce(sum(mv.qty) filter (where mv.dt = d.dt and mv.movement_type = '廃棄'),0) wq,
        coalesce(sum(mv.qty) filter (where mv.dt = d.dt and mv.movement_type = '出庫' and mv.destination = '原料出し'),0) rq
      from mv where mv.lot_id = lo.id
    ) x on true
    group by i.item_name, d.dt
  ),
  qr_rows as (
    select jsonb_build_object('item_name', item_name, 'kind', 'QR', 'values',
      jsonb_agg(jsonb_build_object('date', dt, 'kg', round(kg,2), 'unknown_qty', round(unknown_qty,2), 'cases', round(case_qty,2),
        'kg_unit_qty', round(kg_unit_qty,2), 'in_cases', in_cases, 'in_kgu', in_kgu, 'in_kg', round(in_kg,2), 'waste_kg', round(waste_kg,2),
        'waste_cases', waste_cases, 'rawout_kg', round(rawout_kg,2), 'rawout_cases', rawout_cases) order by dt)) j
    from qr group by item_name
  ),
  cnt_items as (
    select '原料'::text kind, name item_name, sort_order so from public.hq_normal_items_v1410 where active
    union select kind, item_name, 9999 from public.hq_stock_counts_v1500 where count_date between p_from and p_to
  ),
  cnt_rows as (
    select jsonb_build_object('item_name', ci.item_name, 'kind', ci.kind, 'values',
      jsonb_agg(jsonb_build_object('date', d.dt, 'kg', c.total_kg, 'cases', c.total_cases) order by d.dt)) j, ci.kind, min(ci.so) so, ci.item_name
    from (select kind, item_name, min(so) so from cnt_items group by kind, item_name) ci cross join d
    left join public.hq_stock_counts_v1500 c on c.count_date = d.dt and c.kind = ci.kind and c.item_name = ci.item_name
    group by ci.kind, ci.item_name
  )
  select jsonb_build_object('rows',
    coalesce((select jsonb_agg(j order by j->>'item_name') from qr_rows),'[]'::jsonb)
    || coalesce((select jsonb_agg(j order by so, item_name) from cnt_rows where kind = '原料'),'[]'::jsonb)
    || coalesce((select jsonb_agg(j order by item_name) from cnt_rows where kind = '仕掛品'),'[]'::jsonb),
    'count_days', coalesce((select jsonb_agg(distinct count_date) from public.hq_stock_counts_v1500 where count_date between p_from and p_to),'[]'::jsonb))
  into res;
  return res;
end $$;

-- 13. 仕入れ価格（本社用）：同じ品目（別名グループ）の、その週の市場価格の平均。無い週は直近の週。
create or replace function public.hq_price_table_v1500(p_from date, p_to date, p_items text[] default null)
returns jsonb language plpgsql stable security definer set search_path to ''
as $$
declare v public.profiles; res jsonb;
begin
  v := public.hq_actor_v1400(array['admin','worker','buyer','sales','clerk','office_viewer','viewer','hq_worker','hq_clerk','hq_receiver']);
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 800 then raise exception '期間が正しくありません'; end if;
  with names as (
    select distinct n from (
      select unnest(p_items) n
      union select name from public.hq_items_v1400 where p_items is null
      union select name from public.hq_normal_items_v1410 where p_items is null
      union select item_name from public.hq_prep_masters_v1500 where p_items is null
    ) z where btrim(coalesce(n,'')) <> ''
  ),
  weeks as (select generate_series(date_trunc('week', p_from)::date, date_trunc('week', p_to)::date, interval '7 day')::date wk),
  mp as (
    select pp.week_start, btrim(pp.item_name) item_name, pp.price_yen_per_kg price
    from public.purchase_prices pp
    where (pp.price_type = 'market' or btrim(pp.supplier) in ('市場','水戸大同','大同','水戸中央','中央','東一','シティ'))
      and pp.price_yen_per_kg >= 0
  ),
  pick as (
    select n.n item_name, w.wk,
      (select max(mp.week_start) from mp where mp.item_name = any(public.seika_item_name_group_v1200(n.n)) and mp.week_start <= w.wk) src
    from names n cross join weeks w
  )
  select coalesce(jsonb_agg(jsonb_build_object('item_name', p.item_name, 'week', p.wk, 'src_week', p.src,
    'price', (select round(avg(mp.price),2) from mp where mp.item_name = any(public.seika_item_name_group_v1200(p.item_name)) and mp.week_start = p.src),
    'count', (select count(*) from mp where mp.item_name = any(public.seika_item_name_group_v1200(p.item_name)) and mp.week_start = p.src))
    order by p.item_name, p.wk),'[]'::jsonb)
  into res from pick p;
  return res;
end $$;

-- 14. 棚卸し（本社社員・管理者）
create table if not exists public.hq_stocktakes_v1500 (
  id uuid primary key default gen_random_uuid(),
  take_date date not null,
  status text not null default '入力中' check (status in ('入力中','確定')),
  rows jsonb not null default '[]'::jsonb,
  result jsonb,
  created_by_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  confirmed_at timestamptz,
  confirmed_by_name text
);
create or replace function public.hq_stocktake_save_v1500(p_id uuid, p_date date, p_rows jsonb)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles; r public.hq_stocktakes_v1500%rowtype;
begin
  v := public.hq_actor_v1400(array['admin','hq_worker']);
  if jsonb_typeof(p_rows) <> 'array' then raise exception '入力の形が正しくありません'; end if;
  if p_date is null or p_date > (now() at time zone 'Asia/Tokyo')::date then raise exception '日付が正しくありません'; end if;
  if p_id is null then
    insert into public.hq_stocktakes_v1500(take_date, rows, created_by_name) values (p_date, p_rows, v.display_name) returning * into r;
  else
    update public.hq_stocktakes_v1500 set rows = p_rows, take_date = p_date, updated_at = now() where id = p_id and status = '入力中' returning * into r;
    if not found then raise exception '入力中の棚卸しが見つかりません'; end if;
  end if;
  return jsonb_build_object('ok', true, 'id', r.id);
end $$;

create or replace function public.hq_stocktake_confirm_v1500(p_id uuid)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles; t public.hq_stocktakes_v1500%rowtype; r jsonb; l public.hq_lots_v1400%rowtype; v_act numeric;
  res jsonb := '[]'::jsonb; v_pack numeric; v_kind text; v_name text; old_kg numeric;
begin
  v := public.hq_actor_v1400(array['admin','hq_worker']);
  select * into t from public.hq_stocktakes_v1500 where id = p_id for update;
  if not found or t.status <> '入力中' then raise exception '入力中の棚卸しが見つかりません'; end if;
  for r in select * from jsonb_array_elements(t.rows) loop
    v_act := nullif(r->>'actual','')::numeric;
    if v_act is null then
      res := res || jsonb_build_array(r || jsonb_build_object('result','未入力'));
      continue;
    end if;
    if v_act < 0 then raise exception '実数にマイナスは入れられません'; end if;
    if r->>'type' = 'QR' then
      select * into l from public.hq_lots_v1400 where id = (r->>'lot_id')::uuid for update;
      if not found or l.status not in ('在庫あり','在庫なし') then
        res := res || jsonb_build_array(r || jsonb_build_object('result','対象外（確定済みの原料ではありません）'));
        continue;
      end if;
      if v_act <> l.current_qty then
        update public.hq_lots_v1400 set current_qty = v_act, status = case when v_act > 0 then '在庫あり' else '在庫なし' end, updated_at = now() where id = l.id;
        insert into public.hq_lot_movements_v1400(operation_id, lot_id, movement_type, qty, unit, before_qty, after_qty, reason, item_name, lot_no, user_id, user_name)
        values (gen_random_uuid(), l.id, '実数調整', v_act - l.current_qty, l.unit, l.current_qty, v_act, '棚卸し（' || t.take_date || '）', l.item_name, l.lot_no, v.id, v.display_name);
      end if;
      res := res || jsonb_build_array(r || jsonb_build_object('book', l.current_qty, 'diff', v_act - l.current_qty, 'result', case when v_act <> l.current_qty then '実数調整' else '差なし' end));
    else
      v_kind := r->>'kind'; v_name := r->>'item_name'; v_pack := nullif(r->>'pack_kg','')::numeric;
      if v_pack is null or v_pack <= 0 then raise exception '「%」の入れ数kgが分かりません', v_name; end if;
      select total_kg into old_kg from public.hq_stock_counts_v1500 where count_date = t.take_date and kind = v_kind and item_name = v_name;
      insert into public.hq_stock_counts_v1500(count_date, kind, item_name, master_id, lines, total_cases, total_kg, user_id, user_name, updated_at)
      values (t.take_date, v_kind, v_name, nullif(r->>'master_id','')::uuid, jsonb_build_array(jsonb_build_object('pack_kg', v_pack, 'cases', v_act)),
        v_act, round(v_pack * v_act, 2), v.id, v.display_name || '（棚卸し）', now())
      on conflict (count_date, kind, item_name) do update set lines = excluded.lines, total_cases = excluded.total_cases,
        total_kg = excluded.total_kg, user_id = excluded.user_id, user_name = excluded.user_name, updated_at = now();
      res := res || jsonb_build_array(r || jsonb_build_object('book_kg', old_kg, 'actual_kg', round(v_pack * v_act, 2), 'result', '在庫入力に保存'));
    end if;
  end loop;
  update public.hq_stocktakes_v1500 set status = '確定', result = res, confirmed_at = now(), confirmed_by_name = v.display_name, updated_at = now()
  where id = t.id;
  return jsonb_build_object('ok', true, 'result', res);
end $$;

-- 15. 見る権限（ログインした人が見る。書き込みは上の関数からだけ）
do $$
declare t text;
begin
  foreach t in array array['hq_settings_v1500','hq_quality_dismiss_v1500','hq_diff_acks_v1500','hq_prep_masters_v1500','hq_teams_v1500',
    'hq_staff_v1500','hq_places_v1500','hq_tasks_v1500','hq_works_v1500','hq_work_materials_v1500','hq_work_members_v1500',
    'hq_waste_v1500','hq_stock_counts_v1500','hq_stocktakes_v1500'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    execute format('create policy %I on public.%I for select to authenticated using (true)', t || '_read', t);
    execute format('revoke all on public.%I from anon, public', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('grant all on public.%I to service_role', t);
  end loop;
end $$;

-- 16. 実行権限
do $$
declare f text;
begin
  foreach f in array array[
    'public.hq_setting_on_v1500(text)',
    'public.hq_set_setting_v1500(text,jsonb)',
    'public.hq_pack_kg_v1500(text)',
    'public.hq_quality_check_v1500(uuid)',
    'public.hq_quality_dismiss_v1500(uuid)',
    'public.hq_diff_ack_v1500(uuid)',
    'public.hq_save_prep_master_v1500(uuid,text,text,numeric,integer,boolean)',
    'public.hq_save_staff_v1500(uuid,text,text,integer)',
    'public.hq_delete_staff_v1500(uuid)',
    'public.hq_save_place_v1500(text,boolean)',
    'public.hq_save_task_v1500(text,boolean)',
    'public.hq_work_start_v1500(uuid,text,text,text,uuid,uuid[],uuid[])',
    'public.hq_work_join_v1500(uuid,uuid[])',
    'public.hq_work_leave_v1500(uuid,uuid)',
    'public.hq_work_end_v1500(uuid)',
    'public.hq_work_save_inputs_v1500(uuid,jsonb,numeric,numeric)',
    'public.hq_work_to_clean_v1500(uuid,boolean)',
    'public.hq_work_mark_printed_v1500(uuid)',
    'public.hq_work_clean_end_v1500(uuid)',
    'public.hq_work_cancel_v1500(uuid,text)',
    'public.hq_member_fix_v1500(uuid,timestamptz,timestamptz,boolean)',
    'public.hq_member_add_v1500(uuid,uuid,text,timestamptz,timestamptz)',
    'public.hq_rawout_loss_v1500(date,text,numeric,text)',
    'public.hq_dispose_v1500(uuid,uuid,numeric,text)',
    'public.hq_waste_cancel_v1500(uuid,text)',
    'public.hq_prep_confirm_v1500(uuid,jsonb,numeric,numeric,text)',
    'public.hq_prep_cancel_v1500(uuid,text)',
    'public.hq_outbound_v1500(uuid,uuid,numeric,text,text)',
    'public.hq_save_stock_counts_v1500(date,jsonb)',
    'public.get_hq_stock_table_v1500(date,date)',
    'public.hq_price_table_v1500(date,date,text[])',
    'public.hq_stocktake_save_v1500(uuid,date,jsonb)',
    'public.hq_stocktake_confirm_v1500(uuid)'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
  end loop;
  -- 内部だけで使う関数（画面から直接は呼ばない）
  foreach f in array array[
    'public.hq_fill_purchase_staff_v1500()',
    'public.hq_work_add_members_v1500(uuid,uuid[],text)',
    'public.hq_work_check_inputs_v1500(uuid,jsonb,numeric,numeric)',
    'public.hq_prep_unapply_v1500(uuid,public.profiles)'
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;

commit;
notify pgrst, 'reload schema';

-- 成功の確かめ方：下のSELECTを実行して、すべての行が「OK」になれば成功です。
select '1.表（14個）' as 確認, case when count(*) = 14 then 'OK' else 'NG（' || count(*) || '個）' end as 結果
from information_schema.tables where table_schema = 'public' and table_name in ('hq_settings_v1500','hq_quality_dismiss_v1500','hq_diff_acks_v1500',
  'hq_prep_masters_v1500','hq_teams_v1500','hq_staff_v1500','hq_places_v1500','hq_tasks_v1500','hq_works_v1500','hq_work_materials_v1500',
  'hq_work_members_v1500','hq_waste_v1500','hq_stock_counts_v1500','hq_stocktakes_v1500')
union all
select '2.関数（37個）', case when count(distinct proname) = 37 then 'OK' else 'NG（' || count(distinct proname) || '個）' end
from pg_proc where pronamespace = 'public'::regnamespace and proname in ('hq_setting_on_v1500','hq_set_setting_v1500','hq_pack_kg_v1500',
  'hq_fill_purchase_staff_v1500','hq_quality_check_v1500','hq_quality_dismiss_v1500','hq_diff_ack_v1500','hq_save_prep_master_v1500',
  'hq_save_staff_v1500','hq_delete_staff_v1500','hq_save_place_v1500','hq_save_task_v1500','hq_work_add_members_v1500','hq_work_start_v1500',
  'hq_work_join_v1500','hq_work_leave_v1500','hq_work_end_v1500','hq_work_check_inputs_v1500','hq_work_save_inputs_v1500','hq_work_to_clean_v1500',
  'hq_work_mark_printed_v1500','hq_work_clean_end_v1500','hq_work_cancel_v1500','hq_member_fix_v1500','hq_member_add_v1500',
  'hq_rawout_loss_v1500','hq_dispose_v1500','hq_waste_cancel_v1500','hq_prep_unapply_v1500','hq_prep_confirm_v1500','hq_prep_cancel_v1500',
  'hq_outbound_v1500','hq_save_stock_counts_v1500','get_hq_stock_table_v1500','hq_price_table_v1500','hq_stocktake_save_v1500','hq_stocktake_confirm_v1500')
union all
select '3.在庫反映の設定（最初はオフ）', case when (select value from public.hq_settings_v1500 where key = 'stage2_stock') is not null then 'OK（いま：' ||
  case when public.hq_setting_on_v1500('stage2_stock') then 'オン' else 'オフ' end || '）' else 'NG' end
union all
select '4.班（10班）', case when (select count(*) from public.hq_teams_v1500) >= 10 then 'OK' else 'NG' end
union all
select '5.通常在庫の引き継ぎ', case when (select count(*) from public.hq_stock_counts_v1500 where kind = '原料') >= (select count(*) from public.hq_normal_counts_v1410) then 'OK' else 'NG' end
union all
select '6.履歴の区分（下処理使用・廃棄）', case when exists (select 1 from pg_constraint where conname = 'hq_lot_movements_v1400_movement_type_check'
  and pg_get_constraintdef(oid) like '%下処理使用%') then 'OK' else 'NG' end;
