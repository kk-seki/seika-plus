-- 016_本社_第1段階.sql
-- 本社の第1段階（石岡からの移動中表示・本社移動用の貼り紙・受け入れ・品質評価・確定・使用出庫・取消・本社直接入荷・本社品目・本社のアカウント権限）
-- 石岡の在庫・履歴の表と関数は変更しません。本社用の表を新しく作ります。
-- 何度実行しても同じ結果になります。
-- 本社の入荷待ちづくりで問題が起きても、石岡の出庫は止めずに保存します。

begin;

-- 1. 本社の役割を追加（本社社員・本社事務・荷受け担当者・下処理班）
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check check (role = any (array[
  'admin','worker','buyer','sales','clerk','office_viewer','viewer',
  'hq_worker','hq_clerk','hq_receiver','hq_prep'
]::text[]));

-- 2. 本社の表
create sequence if not exists public.hq_lot_no_seq_v1400;

create table if not exists public.hq_items_v1400 (
  name text primary key,
  default_unit text not null default 'ケース',
  pack_weight text,
  sort_order integer not null default 0,
  active boolean not null default true,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.hq_destinations_v1400 (
  name text primary key,
  sort_order integer not null default 0,
  active boolean not null default true
);

create table if not exists public.hq_lots_v1400 (
  id uuid primary key default gen_random_uuid(),
  lot_no text not null unique,
  qr_key text not null unique,
  source_kind text not null check (source_kind in ('石岡から','本社直接入荷')),
  source_movement_id uuid unique,
  source_lot_id uuid,
  source_lot_no text,
  ishioka_received_date date,
  item_name text not null,
  origin text,
  supplier text,
  cooperative_name text,
  container_type text,
  pack_weight text,
  unit text not null default 'ケース',
  planned_qty numeric not null default 0,
  received_qty numeric not null default 0,
  current_qty numeric not null default 0,
  planned_date date,
  hq_received_date date,
  status text not null default '入荷待ち' check (status in ('入荷待ち','在庫あり','在庫なし','取消')),
  grade text check (grade in ('good','review','bad')),
  issues text[] not null default '{}',
  quality_memo text,
  photo_paths text[] not null default '{}',
  evaluated_by uuid,
  evaluated_by_name text,
  confirmed_at timestamptz,
  confirmed_by uuid,
  confirmed_by_name text,
  memo text,
  created_by uuid,
  created_by_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists hq_lots_v1400_status_idx on public.hq_lots_v1400(status, updated_at desc);

create table if not exists public.hq_lot_movements_v1400 (
  id uuid primary key default gen_random_uuid(),
  operation_id uuid not null unique,
  lot_id uuid not null references public.hq_lots_v1400(id),
  movement_type text not null check (movement_type in ('入庫確定','出庫','実数調整','取消')),
  qty numeric not null default 0,
  unit text,
  before_qty numeric,
  after_qty numeric,
  destination text,
  reason text,
  memo text,
  item_name text,
  lot_no text,
  user_id uuid,
  user_name text,
  occurred_at timestamptz not null default now()
);
create index if not exists hq_lot_movements_v1400_lot_idx on public.hq_lot_movements_v1400(lot_id, occurred_at desc);
create index if not exists hq_lot_movements_v1400_time_idx on public.hq_lot_movements_v1400(occurred_at desc);

-- 2b. 貼り紙（パレット・基ごと）と取消のための列
alter table public.hq_lots_v1400 add column if not exists planned_count numeric;
alter table public.hq_lots_v1400 add column if not exists unit_weight_kg numeric;
alter table public.hq_lots_v1400 add column if not exists sheet_meta jsonb not null default '{}'::jsonb;
alter table public.hq_lot_movements_v1400 add column if not exists cancelled_at timestamptz;
alter table public.hq_lot_movements_v1400 add column if not exists cancelled_by_name text;
alter table public.hq_lot_movements_v1400 add column if not exists reversed_movement_id uuid;
alter table public.hq_lot_movements_v1400 drop constraint if exists hq_lot_movements_v1400_movement_type_check;
alter table public.hq_lot_movements_v1400 add constraint hq_lot_movements_v1400_movement_type_check
  check (movement_type in ('入庫確定','出庫','実数調整','取消','出庫取消','受入取消'));

insert into public.hq_destinations_v1400(name, sort_order) values ('下処理',1),('原料出し',2)
on conflict (name) do nothing;
insert into public.hq_items_v1400(name, default_unit, sort_order) values
  ('加工用玉葱','ケース',1),('皮むき人参(国産)','ケース',2),('皮むき人参(中国)','ケース',3),('皮むきじゃが芋','ケース',4)
on conflict (name) do nothing;

-- 保管目安（入荷日＋3日）。いまの「保管目安の設定」画面と同じ表に入れるので、あとから画面で変えられます。
insert into public.qr_storage_limits_v1250(item_name, limit_days, sort_order)
select v.n, 3, coalesce((select max(sort_order) from public.qr_storage_limits_v1250),0) + v.o * 10
from (values ('加工用玉葱',1),('皮むき人参(国産)',2),('皮むき人参(中国)',3),('皮むきじゃが芋',4)) as v(n,o)
on conflict (item_name) do nothing;

-- 3. 見るのはログインした人全員。書き込みは下の関数からだけ。
alter table public.hq_items_v1400 enable row level security;
alter table public.hq_destinations_v1400 enable row level security;
alter table public.hq_lots_v1400 enable row level security;
alter table public.hq_lot_movements_v1400 enable row level security;
drop policy if exists hq_items_v1400_read on public.hq_items_v1400;
create policy hq_items_v1400_read on public.hq_items_v1400 for select to authenticated using (true);
drop policy if exists hq_destinations_v1400_read on public.hq_destinations_v1400;
create policy hq_destinations_v1400_read on public.hq_destinations_v1400 for select to authenticated using (true);
drop policy if exists hq_lots_v1400_read on public.hq_lots_v1400;
create policy hq_lots_v1400_read on public.hq_lots_v1400 for select to authenticated using (true);
drop policy if exists hq_lot_movements_v1400_read on public.hq_lot_movements_v1400;
create policy hq_lot_movements_v1400_read on public.hq_lot_movements_v1400 for select to authenticated using (true);
revoke all on public.hq_items_v1400, public.hq_destinations_v1400, public.hq_lots_v1400, public.hq_lot_movements_v1400 from anon, public;
grant select on public.hq_items_v1400, public.hq_destinations_v1400, public.hq_lots_v1400, public.hq_lot_movements_v1400 to authenticated;
grant all on public.hq_items_v1400, public.hq_destinations_v1400, public.hq_lots_v1400, public.hq_lot_movements_v1400 to service_role;

-- 4. 共通：ログイン本人と役割の確認
create or replace function public.hq_actor_v1400(p_roles text[])
returns public.profiles
language plpgsql stable security definer set search_path to ''
as $$
declare v public.profiles%rowtype;
begin
  select * into v from public.profiles where id = auth.uid() and active = true;
  if not found then raise exception '再ログインしてください' using errcode = '42501'; end if;
  if not (v.role = any (p_roles)) then raise exception 'この操作の権限がありません' using errcode = '42501'; end if;
  return v;
end $$;

create or replace function public.hq_unit_for_v1400(p_container text)
returns text language sql immutable set search_path to ''
as $$ select case when coalesce(p_container,'') in ('網コンテナ','鉄コンテナ','パレテーナ') then 'kg' else 'ケース' end $$;

create or replace function public.hq_new_lot_no_v1400()
returns text language sql volatile security definer set search_path to ''
as $$ select 'H' || to_char((now() at time zone 'Asia/Tokyo')::date, 'YYYYMMDD') || '-' || lpad(nextval('public.hq_lot_no_seq_v1400')::text, 4, '0') $$;

-- 5. 石岡で「本社」へ出庫したら、本社の「入荷待ち原料」を自動で作る。取消されたら入荷待ちも取消。
create or replace function public.hq_capture_ishioka_transfer_v1400()
returns trigger language plpgsql security definer set search_path to ''
as $$
declare l public.qr_lots%rowtype; v_unit text; v_qty numeric; v_per numeric;
begin
 begin
  if tg_op = 'INSERT' and new.reversed_operation_id is not null then
    update public.hq_lots_v1400 h set status = '取消', updated_at = now()
    from public.qr_lot_movements m
    where m.operation_id = new.reversed_operation_id and h.source_movement_id = m.id and h.status = '入荷待ち';
    update public.hq_lots_v1400 h set memo = concat_ws(' / ', h.memo, '石岡で出庫が取り消されました（本社は確定済み）'), updated_at = now()
    from public.qr_lot_movements m
    where m.operation_id = new.reversed_operation_id and h.source_movement_id = m.id and h.status in ('在庫あり','在庫なし')
      and coalesce(h.memo,'') not like '%石岡で出庫が取り消されました%';
    return new;
  end if;
  if tg_op = 'INSERT' then
    if new.movement_type <> '出庫' or btrim(coalesce(new.destination,'')) <> '本社' or new.cancelled_at is not null then
      return new;
    end if;
    select * into l from public.qr_lots where id = new.lot_id;
    v_unit := public.hq_unit_for_v1400(coalesce(new.container_type, l.container_type));
    v_per := case when coalesce(l.total_weight,0) > 0 and coalesce(l.received_qty,0) > 0 then round(l.total_weight / l.received_qty, 1) end;
    v_qty := case when v_unit = 'kg' then coalesce(case when v_per is not null then round(new.qty * v_per, 1) end, nullif(new.weight,0), new.qty) else new.qty end;
    insert into public.hq_lots_v1400(lot_no, qr_key, source_kind, source_movement_id, source_lot_id, source_lot_no,
      ishioka_received_date, item_name, origin, supplier, cooperative_name, container_type, pack_weight, unit,
      planned_qty, planned_count, unit_weight_kg, planned_date, status, created_by_name)
    values (public.hq_new_lot_no_v1400(), 'HQ-' || replace(gen_random_uuid()::text,'-',''), '石岡から', new.id, new.lot_id,
      coalesce(new.lot_no, l.lot_no), l.received_date, new.item_name, coalesce(new.origin, l.origin),
      coalesce(new.supplier, l.supplier), coalesce(new.cooperative_name, l.cooperative_name),
      coalesce(new.container_type, l.container_type), l.pack_weight, v_unit, coalesce(v_qty,0),
      new.qty, case when v_unit = 'kg' then v_per end,
      (new.occurred_at at time zone 'Asia/Tokyo')::date, '入荷待ち', new.user_name)
    on conflict (source_movement_id) do nothing;
  elsif tg_op = 'UPDATE' then
    if new.cancelled_at is not null and old.cancelled_at is null then
      update public.hq_lots_v1400 set status = '取消', updated_at = now()
      where source_movement_id = new.id and status = '入荷待ち';
    end if;
  end if;
 exception when others then
  raise warning '本社の入荷待ちを作れませんでした（石岡の出庫はそのまま保存します）：%', sqlerrm;
 end;
  return new;
end $$;

drop trigger if exists hq_capture_ishioka_transfer_v1400_trg on public.qr_lot_movements;
create trigger hq_capture_ishioka_transfer_v1400_trg
after insert or update of cancelled_at on public.qr_lot_movements
for each row execute function public.hq_capture_ishioka_transfer_v1400();

-- 6. 本社入荷日の変更（貼り紙の印刷前）
create or replace function public.hq_set_planned_date_v1400(p_lot_id uuid, p_date date)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles;
begin
  v := public.hq_actor_v1400(array['admin','worker','hq_worker','hq_receiver']);
  update public.hq_lots_v1400 set planned_date = p_date, updated_at = now() where id = p_lot_id and status = '入荷待ち';
  if not found then raise exception '入荷待ちの原料が見つかりません'; end if;
  return jsonb_build_object('ok', true);
end $$;

-- 7. 本社直接入荷（入荷待ちとして作り、続けて品質評価・確定する）
create or replace function public.hq_direct_inbound_v1400(p_item_name text, p_origin text, p_supplier text,
  p_cooperative_name text, p_container_type text, p_pack_weight text, p_qty numeric, p_date date, p_memo text default null)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles; r public.hq_lots_v1400%rowtype;
begin
  v := public.hq_actor_v1400(array['admin','hq_worker','hq_receiver']);
  if btrim(coalesce(p_item_name,'')) = '' then raise exception '品目を選んでください'; end if;
  if coalesce(p_qty,0) <= 0 then raise exception '数量を入れてください'; end if;
  insert into public.hq_lots_v1400(lot_no, qr_key, source_kind, item_name, origin, supplier, cooperative_name,
    container_type, pack_weight, unit, planned_qty, planned_date, status, memo, created_by, created_by_name)
  values (public.hq_new_lot_no_v1400(), 'HQ-' || replace(gen_random_uuid()::text,'-',''), '本社直接入荷', btrim(p_item_name),
    nullif(btrim(coalesce(p_origin,'')),''), nullif(btrim(coalesce(p_supplier,'')),''), nullif(btrim(coalesce(p_cooperative_name,'')),''),
    nullif(p_container_type,''), nullif(btrim(coalesce(p_pack_weight,'')),''), public.hq_unit_for_v1400(p_container_type),
    p_qty, coalesce(p_date,(now() at time zone 'Asia/Tokyo')::date), '入荷待ち', p_memo, v.id, v.display_name)
  returning * into r;
  return jsonb_build_object('ok', true, 'lot', to_jsonb(r));
end $$;

-- 8. 受け入れ確定（品質評価と数量。確定した時点で本社の在庫になる）
create or replace function public.hq_receive_v1400(p_operation_id uuid, p_lot_id uuid, p_qty numeric, p_grade text,
  p_issues text[] default '{}', p_quality_memo text default null, p_photo_paths text[] default '{}')
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles; l public.hq_lots_v1400%rowtype;
begin
  v := public.hq_actor_v1400(array['admin','hq_worker','hq_receiver']);
  if exists (select 1 from public.hq_lot_movements_v1400 where operation_id = p_operation_id) then
    return jsonb_build_object('ok', true, 'already', true);
  end if;
  select * into l from public.hq_lots_v1400 where id = p_lot_id for update;
  if not found then raise exception '原料が見つかりません'; end if;
  if l.status <> '入荷待ち' then raise exception 'この原料はすでに確定済みか取消されています（%）', l.status; end if;
  if p_grade not in ('good','review','bad') then raise exception '品質評価を選んでください'; end if;
  if p_grade in ('review','bad') and coalesce(array_length(p_photo_paths,1),0) < 1 then
    raise exception '要確認・不良のときは写真を1枚以上付けてください';
  end if;
  if coalesce(p_qty,-1) < 0 then raise exception '数量を入れてください'; end if;
  update public.hq_lots_v1400 set received_qty = p_qty, current_qty = p_qty,
    status = case when p_qty > 0 then '在庫あり' else '在庫なし' end,
    hq_received_date = (now() at time zone 'Asia/Tokyo')::date,
    grade = p_grade, issues = coalesce(p_issues,'{}'), quality_memo = p_quality_memo, photo_paths = coalesce(p_photo_paths,'{}'),
    evaluated_by = v.id, evaluated_by_name = v.display_name,
    confirmed_at = now(), confirmed_by = v.id, confirmed_by_name = v.display_name, updated_at = now()
  where id = l.id;
  insert into public.hq_lot_movements_v1400(operation_id, lot_id, movement_type, qty, unit, before_qty, after_qty, memo, item_name, lot_no, user_id, user_name)
  values (p_operation_id, l.id, '入庫確定', p_qty, l.unit, 0, p_qty,
    case when p_qty <> l.planned_qty then '予定 ' || l.planned_qty || l.unit || ' → 実際 ' || p_qty || l.unit end,
    l.item_name, l.lot_no, v.id, v.display_name);
  return jsonb_build_object('ok', true);
end $$;

-- 9. 使用時の出庫
create or replace function public.hq_outbound_v1400(p_operation_id uuid, p_lot_id uuid, p_qty numeric, p_destination text, p_memo text default null)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles; l public.hq_lots_v1400%rowtype; v_after numeric;
begin
  v := public.hq_actor_v1400(array['admin','hq_worker','hq_prep']);
  if exists (select 1 from public.hq_lot_movements_v1400 where operation_id = p_operation_id) then
    return jsonb_build_object('ok', true, 'already', true);
  end if;
  if not exists (select 1 from public.hq_destinations_v1400 where name = p_destination and active) then
    raise exception '出庫先を選んでください';
  end if;
  select * into l from public.hq_lots_v1400 where id = p_lot_id for update;
  if not found then raise exception '原料が見つかりません'; end if;
  if l.status = '入荷待ち' then raise exception 'まだ受け入れが確定していません。先に品質評価と確定をしてください'; end if;
  if l.status not in ('在庫あり') then raise exception 'この原料は在庫がありません'; end if;
  if coalesce(p_qty,0) <= 0 then raise exception '数量を入れてください'; end if;
  if p_qty > l.current_qty then raise exception '在庫（%）より多くは出庫できません', l.current_qty || l.unit; end if;
  v_after := l.current_qty - p_qty;
  update public.hq_lots_v1400 set current_qty = v_after, status = case when v_after > 0 then '在庫あり' else '在庫なし' end, updated_at = now()
  where id = l.id;
  insert into public.hq_lot_movements_v1400(operation_id, lot_id, movement_type, qty, unit, before_qty, after_qty, destination, memo, item_name, lot_no, user_id, user_name)
  values (p_operation_id, l.id, '出庫', p_qty, l.unit, l.current_qty, v_after, p_destination, p_memo, l.item_name, l.lot_no, v.id, v.display_name);
  return jsonb_build_object('ok', true, 'after_qty', v_after);
end $$;

-- 10. 実数調整（本社社員・管理者）
create or replace function public.hq_adjust_v1400(p_operation_id uuid, p_lot_id uuid, p_after_qty numeric, p_reason text)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles; l public.hq_lots_v1400%rowtype;
begin
  v := public.hq_actor_v1400(array['admin','hq_worker']);
  if exists (select 1 from public.hq_lot_movements_v1400 where operation_id = p_operation_id) then
    return jsonb_build_object('ok', true, 'already', true);
  end if;
  if btrim(coalesce(p_reason,'')) = '' then raise exception '理由を入れてください'; end if;
  select * into l from public.hq_lots_v1400 where id = p_lot_id for update;
  if not found or l.status not in ('在庫あり','在庫なし') then raise exception '確定済みの原料が見つかりません'; end if;
  if coalesce(p_after_qty,-1) < 0 then raise exception '実数を入れてください'; end if;
  update public.hq_lots_v1400 set current_qty = p_after_qty, status = case when p_after_qty > 0 then '在庫あり' else '在庫なし' end, updated_at = now()
  where id = l.id;
  insert into public.hq_lot_movements_v1400(operation_id, lot_id, movement_type, qty, unit, before_qty, after_qty, reason, item_name, lot_no, user_id, user_name)
  values (p_operation_id, l.id, '実数調整', p_after_qty - l.current_qty, l.unit, l.current_qty, p_after_qty, p_reason, l.item_name, l.lot_no, v.id, v.display_name);
  return jsonb_build_object('ok', true);
end $$;

-- 11. 本社直接入荷の入荷待ちを取消（石岡からの分は石岡側の出庫取消で自動的に取消）
create or replace function public.hq_cancel_pending_v1400(p_lot_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles;
begin
  v := public.hq_actor_v1400(array['admin','hq_worker']);
  update public.hq_lots_v1400 set status = '取消', memo = concat_ws(' / ', memo, '取消：' || coalesce(p_reason,'')), updated_at = now()
  where id = p_lot_id and status = '入荷待ち' and source_kind = '本社直接入荷';
  if not found then raise exception '取消できる入荷待ちがありません（石岡からの分は石岡で出庫を取消してください）'; end if;
  return jsonb_build_object('ok', true);
end $$;

-- 12. 本社品目の追加・表示切替（本社社員・管理者）
create or replace function public.hq_save_item_v1400(p_name text, p_default_unit text, p_pack_weight text, p_active boolean default true)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles;
begin
  v := public.hq_actor_v1400(array['admin','hq_worker']);
  if btrim(coalesce(p_name,'')) = '' then raise exception '品目名を入れてください'; end if;
  if p_default_unit not in ('ケース','kg') then raise exception '単位はケースかkgです'; end if;
  insert into public.hq_items_v1400(name, default_unit, pack_weight, active, sort_order, created_by)
  values (btrim(p_name), p_default_unit, nullif(btrim(coalesce(p_pack_weight,'')),''), coalesce(p_active,true),
    (select coalesce(max(sort_order),0)+1 from public.hq_items_v1400), v.display_name)
  on conflict (name) do update set default_unit = excluded.default_unit, pack_weight = excluded.pack_weight,
    active = excluded.active, updated_at = now();
  return jsonb_build_object('ok', true);
end $$;

-- 13. 役割と初回パスワード変更の設定（管理者だけ）
create or replace function public.seika_set_user_role_v1400(p_profile_id uuid, p_role text, p_must_change boolean)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles;
begin
  v := public.hq_actor_v1400(array['admin']);
  if p_profile_id = v.id and p_role <> 'admin' then raise exception '自分自身の権限は変更できません'; end if;
  if p_role not in ('admin','worker','buyer','sales','clerk','office_viewer','viewer','hq_worker','hq_clerk','hq_receiver','hq_prep') then
    raise exception '権限の値が正しくありません';
  end if;
  update public.profiles set role = p_role, must_change_password = coalesce(p_must_change, must_change_password), updated_at = now()
  where id = p_profile_id;
  if not found then raise exception 'ユーザーが見つかりません'; end if;
  return jsonb_build_object('ok', true);
end $$;

-- 13b. 貼り紙の設定（パレット枚数・1パレットのケース数・印刷枚数）を保存
create or replace function public.hq_save_sheet_v1400(p_lot_id uuid, p_meta jsonb)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles;
begin
  v := public.hq_actor_v1400(array['admin','worker','hq_worker','hq_receiver']);
  if jsonb_typeof(p_meta) <> 'object' then raise exception '貼り紙の設定が正しくありません'; end if;
  update public.hq_lots_v1400 set sheet_meta = p_meta || jsonb_build_object('saved_by', v.display_name, 'saved_at', now()), updated_at = now()
  where id = p_lot_id and status <> '取消';
  if not found then raise exception '原料が見つかりません'; end if;
  return jsonb_build_object('ok', true);
end $$;

-- 13c. 本社の出庫の取消（出庫した本人はその日のうち、本社社員・管理者はいつでも）
create or replace function public.hq_cancel_out_v1400(p_operation_id uuid, p_movement_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles; m public.hq_lot_movements_v1400%rowtype; l public.hq_lots_v1400%rowtype; v_after numeric;
begin
  v := public.hq_actor_v1400(array['admin','hq_worker','hq_prep']);
  if exists (select 1 from public.hq_lot_movements_v1400 where operation_id = p_operation_id) then
    return jsonb_build_object('ok', true, 'already', true);
  end if;
  select * into m from public.hq_lot_movements_v1400 where id = p_movement_id for update;
  if not found or m.movement_type <> '出庫' then raise exception '取り消せる出庫が見つかりません'; end if;
  if m.cancelled_at is not null then raise exception 'この出庫はすでに取り消されています'; end if;
  if v.role not in ('admin','hq_worker') then
    if m.user_id is distinct from v.id then raise exception '自分が出庫したもの以外は、本社社員に取り消してもらってください' using errcode = '42501'; end if;
    if (m.occurred_at at time zone 'Asia/Tokyo')::date <> (now() at time zone 'Asia/Tokyo')::date then
      raise exception '前の日の出庫は、本社社員に取り消してもらってください' using errcode = '42501';
    end if;
  end if;
  select * into l from public.hq_lots_v1400 where id = m.lot_id for update;
  if l.status not in ('在庫あり','在庫なし') then raise exception 'この原料は取り消せる状態ではありません（%）', l.status; end if;
  v_after := l.current_qty + m.qty;
  update public.hq_lots_v1400 set current_qty = v_after, status = case when v_after > 0 then '在庫あり' else '在庫なし' end, updated_at = now()
  where id = l.id;
  update public.hq_lot_movements_v1400 set cancelled_at = now(), cancelled_by_name = v.display_name where id = m.id;
  insert into public.hq_lot_movements_v1400(operation_id, lot_id, movement_type, qty, unit, before_qty, after_qty, destination, reason, item_name, lot_no, user_id, user_name, reversed_movement_id)
  values (p_operation_id, l.id, '出庫取消', m.qty, l.unit, l.current_qty, v_after, m.destination, nullif(btrim(coalesce(p_reason,'')),''), l.item_name, l.lot_no, v.id, v.display_name, m.id);
  return jsonb_build_object('ok', true, 'after_qty', v_after);
end $$;

-- 13d. 受け入れ確定の取消（本社社員・管理者。出庫や実数調整がある場合は先にそれを取り消す）
create or replace function public.hq_cancel_receive_v1400(p_operation_id uuid, p_lot_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles; l public.hq_lots_v1400%rowtype;
begin
  v := public.hq_actor_v1400(array['admin','hq_worker']);
  if exists (select 1 from public.hq_lot_movements_v1400 where operation_id = p_operation_id) then
    return jsonb_build_object('ok', true, 'already', true);
  end if;
  select * into l from public.hq_lots_v1400 where id = p_lot_id for update;
  if not found or l.status not in ('在庫あり','在庫なし') then raise exception '確定済みの原料が見つかりません'; end if;
  if exists (select 1 from public.hq_lot_movements_v1400 where lot_id = l.id and movement_type in ('出庫','実数調整') and cancelled_at is null) then
    raise exception 'この原料には出庫か実数調整があります。先にそれを取り消してください';
  end if;
  update public.hq_lot_movements_v1400 set cancelled_at = now(), cancelled_by_name = v.display_name
  where lot_id = l.id and movement_type = '入庫確定' and cancelled_at is null;
  update public.hq_lots_v1400 set status = '入荷待ち', received_qty = 0, current_qty = 0, hq_received_date = null,
    grade = null, issues = '{}', quality_memo = null, photo_paths = '{}', evaluated_by = null, evaluated_by_name = null,
    confirmed_at = null, confirmed_by = null, confirmed_by_name = null,
    memo = concat_ws(' / ', memo, '受入取消：' || coalesce(nullif(btrim(coalesce(p_reason,'')),''),'理由なし')), updated_at = now()
  where id = l.id;
  insert into public.hq_lot_movements_v1400(operation_id, lot_id, movement_type, qty, unit, before_qty, after_qty, reason, item_name, lot_no, user_id, user_name)
  values (p_operation_id, l.id, '受入取消', l.current_qty, l.unit, l.current_qty, 0, nullif(btrim(coalesce(p_reason,'')),''), l.item_name, l.lot_no, v.id, v.display_name);
  return jsonb_build_object('ok', true);
end $$;

-- 14. 実行権限
do $$
declare f text;
begin
  foreach f in array array[
    'public.hq_actor_v1400(text[])',
    'public.hq_new_lot_no_v1400()',
    'public.hq_set_planned_date_v1400(uuid,date)',
    'public.hq_direct_inbound_v1400(text,text,text,text,text,text,numeric,date,text)',
    'public.hq_receive_v1400(uuid,uuid,numeric,text,text[],text,text[])',
    'public.hq_outbound_v1400(uuid,uuid,numeric,text,text)',
    'public.hq_adjust_v1400(uuid,uuid,numeric,text)',
    'public.hq_cancel_pending_v1400(uuid,text)',
    'public.hq_save_item_v1400(text,text,text,boolean)',
    'public.seika_set_user_role_v1400(uuid,text,boolean)',
    'public.hq_save_sheet_v1400(uuid,jsonb)',
    'public.hq_cancel_out_v1400(uuid,uuid,text)',
    'public.hq_cancel_receive_v1400(uuid,uuid,text)'
  ] loop
    execute 'revoke all on function ' || f || ' from public, anon';
    execute 'grant execute on function ' || f || ' to authenticated, service_role';
  end loop;
  execute 'revoke all on function public.hq_capture_ishioka_transfer_v1400() from public, anon, authenticated';
end $$;

-- 15. 本社の品質写真の保管場所（非公開）
do $$
begin
  if to_regclass('storage.buckets') is not null then
    insert into storage.buckets(id, name, public) values ('hq-quality-photos','hq-quality-photos', false)
    on conflict (id) do nothing;
  end if;
  begin
    execute 'drop policy if exists hq_photos_v1400_read on storage.objects';
    execute 'create policy hq_photos_v1400_read on storage.objects for select to authenticated using (bucket_id = ''hq-quality-photos'')';
    execute 'drop policy if exists hq_photos_v1400_insert on storage.objects';
    execute 'create policy hq_photos_v1400_insert on storage.objects for insert to authenticated with check (bucket_id = ''hq-quality-photos'' and public.current_app_role() = any (array[''admin'',''hq_worker'',''hq_receiver'']))';
  exception when others then
    raise notice '写真の保管場所の設定に失敗しました：%', sqlerrm;
  end;
end $$;

commit;

-- 確認（すべて OK になれば成功）
select '1.役割' as 確認, case when pg_get_constraintdef(oid) like '%hq_receiver%' then 'OK' else 'NG' end as 結果
  from pg_constraint where conname = 'profiles_role_check'
union all select '2.本社の表', case when to_regclass('public.hq_lots_v1400') is not null and to_regclass('public.hq_lot_movements_v1400') is not null then 'OK' else 'NG' end
union all select '3.出庫先', case when (select count(*) from public.hq_destinations_v1400 where name in ('下処理','原料出し')) = 2 then 'OK' else 'NG' end
union all select '4.本社品目', case when (select count(*) from public.hq_items_v1400 where name in ('加工用玉葱','皮むき人参(国産)','皮むき人参(中国)','皮むきじゃが芋')) = 4 then 'OK' else 'NG' end
union all select '4b.保管目安3日', case when (select count(*) from public.qr_storage_limits_v1250 where item_name in ('加工用玉葱','皮むき人参(国産)','皮むき人参(中国)','皮むきじゃが芋') and limit_days = 3) = 4 then 'OK' else 'NG（すでに別の日数が入っている可能性）' end
union all select '5.自動の入荷待ち', case when exists (select 1 from pg_trigger where tgname = 'hq_capture_ishioka_transfer_v1400_trg') then 'OK' else 'NG' end
union all select '6.関数', case when (select count(*) from pg_proc where proname in ('hq_receive_v1400','hq_outbound_v1400','hq_adjust_v1400','hq_direct_inbound_v1400','hq_cancel_pending_v1400','hq_save_item_v1400','hq_set_planned_date_v1400','seika_set_user_role_v1400','hq_save_sheet_v1400','hq_cancel_out_v1400','hq_cancel_receive_v1400')) = 11 then 'OK' else 'NG' end
union all select '6b.貼り紙・取消の列', case when exists (select 1 from information_schema.columns where table_name = 'hq_lots_v1400' and column_name = 'sheet_meta')
  and exists (select 1 from information_schema.columns where table_name = 'hq_lot_movements_v1400' and column_name = 'cancelled_at') then 'OK' else 'NG' end
union all select '7.写真の保管場所', case when to_regclass('storage.buckets') is null then 'OK（対象外）'
  when exists (select 1 from pg_policies where schemaname = 'storage' and policyname = 'hq_photos_v1400_insert') then 'OK' else 'NG' end;
