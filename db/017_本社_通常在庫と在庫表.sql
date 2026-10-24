-- 017_本社_通常在庫と在庫表.sql
-- 本社の通常在庫（QRで管理しない品目）の品目・在庫入力と、QR品目と合わせた「在庫表」。
-- 016_本社_第1段階.sql を実行したあとに実行してください。石岡の表と関数は変更しません。
-- 何度実行しても同じ結果になります。

begin;

-- 1. 本社の通常在庫の品目
create table if not exists public.hq_normal_items_v1410 (
  name text primary key,
  pack_weight_kg numeric not null check (pack_weight_kg > 0),
  sort_order integer not null default 0,
  active boolean not null default true,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 2. 本社の通常在庫の入力（品目ごと・1日1件。入れ直すと上書き）
create table if not exists public.hq_normal_counts_v1410 (
  id uuid primary key default gen_random_uuid(),
  count_date date not null,
  item_name text not null references public.hq_normal_items_v1410(name) on update cascade,
  cases numeric not null default 0 check (cases >= 0),
  bara_kg numeric not null default 0 check (bara_kg >= 0),
  pack_weight_kg numeric not null,
  total_kg numeric not null,
  user_id uuid,
  user_name text,
  updated_at timestamptz not null default now(),
  unique (count_date, item_name)
);
create index if not exists hq_normal_counts_v1410_date_idx on public.hq_normal_counts_v1410(count_date);

alter table public.hq_normal_items_v1410 enable row level security;
alter table public.hq_normal_counts_v1410 enable row level security;
drop policy if exists hq_normal_items_v1410_read on public.hq_normal_items_v1410;
create policy hq_normal_items_v1410_read on public.hq_normal_items_v1410 for select to authenticated using (true);
drop policy if exists hq_normal_counts_v1410_read on public.hq_normal_counts_v1410;
create policy hq_normal_counts_v1410_read on public.hq_normal_counts_v1410 for select to authenticated using (true);
revoke all on public.hq_normal_items_v1410, public.hq_normal_counts_v1410 from anon, public;
grant select on public.hq_normal_items_v1410, public.hq_normal_counts_v1410 to authenticated;
grant all on public.hq_normal_items_v1410, public.hq_normal_counts_v1410 to service_role;

-- 3. 通常在庫の品目の追加・変更（本社社員・管理者）
create or replace function public.hq_save_normal_item_v1410(p_name text, p_pack_weight_kg numeric, p_active boolean default true)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles; v_name text := btrim(coalesce(p_name,''));
begin
  v := public.hq_actor_v1400(array['admin','hq_worker']);
  if v_name = '' then raise exception '品目名を入れてください'; end if;
  if p_pack_weight_kg is null or p_pack_weight_kg <= 0 then raise exception '1ケースのkgを入れてください'; end if;
  if exists (select 1 from public.hq_items_v1400 where name = v_name)
     or exists (select 1 from public.hq_lots_v1400 where item_name = v_name and status <> '取消') then
    raise exception '「%」はQR品目に登録されています。QR品目と通常在庫の品目に同じ名前は登録できません', v_name;
  end if;
  insert into public.hq_normal_items_v1410(name, pack_weight_kg, active, sort_order, created_by)
  values (v_name, p_pack_weight_kg, coalesce(p_active,true),
    (select coalesce(max(sort_order),0)+1 from public.hq_normal_items_v1410), v.display_name)
  on conflict (name) do update set pack_weight_kg = excluded.pack_weight_kg, active = excluded.active, updated_at = now();
  return jsonb_build_object('ok', true);
end $$;

-- 4. QR品目の追加でも、通常在庫の品目と同じ名前は登録できないようにする
create or replace function public.hq_save_item_v1400(p_name text, p_default_unit text, p_pack_weight text, p_active boolean default true)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles;
begin
  v := public.hq_actor_v1400(array['admin','hq_worker']);
  if btrim(coalesce(p_name,'')) = '' then raise exception '品目名を入れてください'; end if;
  if p_default_unit not in ('ケース','kg') then raise exception '単位はケースかkgです'; end if;
  if exists (select 1 from public.hq_normal_items_v1410 where name = btrim(p_name)) then
    raise exception '「%」は通常在庫の品目に登録されています。QR品目と通常在庫の品目に同じ名前は登録できません', btrim(p_name);
  end if;
  insert into public.hq_items_v1400(name, default_unit, pack_weight, active, sort_order, created_by)
  values (btrim(p_name), p_default_unit, nullif(btrim(coalesce(p_pack_weight,'')),''), coalesce(p_active,true),
    (select coalesce(max(sort_order),0)+1 from public.hq_items_v1400), v.display_name)
  on conflict (name) do update set default_unit = excluded.default_unit, pack_weight = excluded.pack_weight,
    active = excluded.active, updated_at = now();
  return jsonb_build_object('ok', true);
end $$;

-- 5. 通常在庫の入力（本社社員・荷受け担当者・管理者）。ケースもバラも空の品目は、その日の入力を消します。
create or replace function public.hq_save_normal_counts_v1410(p_date date, p_rows jsonb)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles; r jsonb; it public.hq_normal_items_v1410%rowtype; v_cases numeric; v_bara numeric; n_saved int := 0; n_cleared int := 0;
begin
  v := public.hq_actor_v1400(array['admin','hq_worker','hq_receiver']);
  if p_date is null then raise exception '日付を選んでください'; end if;
  if p_date > (now() at time zone 'Asia/Tokyo')::date then raise exception '先の日付には入力できません'; end if;
  if jsonb_typeof(p_rows) <> 'array' then raise exception '入力の形が正しくありません'; end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    select * into it from public.hq_normal_items_v1410 where name = r->>'item_name';
    if not found then raise exception '品目「%」が見つかりません', r->>'item_name'; end if;
    v_cases := nullif(r->>'cases','')::numeric;
    v_bara := nullif(r->>'bara_kg','')::numeric;
    if v_cases is null and v_bara is null then
      delete from public.hq_normal_counts_v1410 where count_date = p_date and item_name = it.name;
      if found then n_cleared := n_cleared + 1; end if;
      continue;
    end if;
    if coalesce(v_cases,0) < 0 or coalesce(v_bara,0) < 0 then raise exception '「%」にマイナスは入れられません', it.name; end if;
    insert into public.hq_normal_counts_v1410(count_date, item_name, cases, bara_kg, pack_weight_kg, total_kg, user_id, user_name, updated_at)
    values (p_date, it.name, coalesce(v_cases,0), coalesce(v_bara,0), it.pack_weight_kg,
      round(coalesce(v_cases,0) * it.pack_weight_kg + coalesce(v_bara,0), 2), v.id, v.display_name, now())
    on conflict (count_date, item_name) do update set cases = excluded.cases, bara_kg = excluded.bara_kg,
      pack_weight_kg = excluded.pack_weight_kg, total_kg = excluded.total_kg, user_id = excluded.user_id,
      user_name = excluded.user_name, updated_at = now();
    n_saved := n_saved + 1;
  end loop;
  return jsonb_build_object('ok', true, 'saved', n_saved, 'cleared', n_cleared);
end $$;

-- 6. 在庫表（本社のQR品目＋通常在庫の品目、日ごとのkg）。最大62日分。
--    QR品目：その日の終わりの在庫。取り消した出庫・受け入れは、はじめからなかったものとして数えます。
--    通常在庫：その日に入力したkg（入力がない日は空欄）。
create or replace function public.get_hq_stock_table_v1410(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path to ''
as $$
declare v_rows jsonb;
begin
  if auth.uid() is null or not exists (select 1 from public.profiles where id = auth.uid() and active = true) then
    raise exception '再ログインしてください' using errcode = '42501';
  end if;
  if p_from is null or p_to is null or p_from > p_to then raise exception '期間が正しくありません'; end if;
  if p_to - p_from > 61 then raise exception '在庫表は62日分までです'; end if;
  with days as (
    select d::date as d from generate_series(p_from, p_to, interval '1 day') g(d)
  ), lot_w as (
    select l.id, l.item_name, l.unit,
      case when l.unit = 'kg' then 1::numeric else public.seika_parse_kg_v1162(l.pack_weight) end as kg_per
    from public.hq_lots_v1400 l
  ), deltas as (
    select m.lot_id, (m.occurred_at at time zone 'Asia/Tokyo')::date as md,
      case m.movement_type when '入庫確定' then m.qty when '出庫' then -m.qty
        when '実数調整' then coalesce(m.after_qty,0) - coalesce(m.before_qty,0) else 0 end as dq
    from public.hq_lot_movements_v1400 m
    where m.cancelled_at is null and m.movement_type in ('入庫確定','出庫','実数調整')
  ), lot_day as (
    select lw.item_name, lw.kg_per, dy.d, sum(dl.dq) as q
    from lot_w lw join deltas dl on dl.lot_id = lw.id join days dy on dl.md <= dy.d
    group by lw.id, lw.item_name, lw.kg_per, dy.d
  ), qr_day as (
    select item_name, d, round(sum(case when kg_per is not null then q * kg_per else 0 end), 2) as kg,
      sum(case when kg_per is null then q else 0 end) as unknown_qty
    from lot_day group by item_name, d
  ), qr_items as (
    select name as item_name, sort_order from public.hq_items_v1400 where active
    union select item_name, 9999 from qr_day where kg <> 0 or unknown_qty <> 0
  ), normal_items as (
    select name as item_name, sort_order from public.hq_normal_items_v1410 where active
    union select item_name, 9999 from public.hq_normal_counts_v1410 where count_date between p_from and p_to
  ), qr_rows as (
    select qi.item_name, min(qi.sort_order) as so,
      (select jsonb_agg(jsonb_build_object('date', dy.d, 'kg', coalesce(q.kg,0), 'unknown_qty', coalesce(q.unknown_qty,0)) order by dy.d)
         from days dy left join qr_day q on q.item_name = qi.item_name and q.d = dy.d) as vals
    from qr_items qi group by qi.item_name
  ), normal_rows as (
    select ni.item_name, min(ni.sort_order) as so,
      (select jsonb_agg(jsonb_build_object('date', dy.d, 'kg', c.total_kg, 'cases', c.cases, 'bara_kg', c.bara_kg) order by dy.d)
         from days dy left join public.hq_normal_counts_v1410 c on c.item_name = ni.item_name and c.count_date = dy.d) as vals
    from normal_items ni group by ni.item_name
  )
  select coalesce(jsonb_agg(x.j order by x.k, x.so, x.item_name), '[]'::jsonb) into v_rows from (
    select 1 as k, so, item_name, jsonb_build_object('item_name', item_name, 'kind', 'QR', 'values', vals) as j from qr_rows
    union all
    select 2, so, item_name, jsonb_build_object('item_name', item_name, 'kind', '通常', 'values', vals) from normal_rows
  ) x;
  return jsonb_build_object('ok', true, 'from', p_from, 'to', p_to, 'rows', v_rows);
end $$;

-- 7. 実行権限
do $$
declare f text;
begin
  foreach f in array array[
    'public.hq_save_normal_item_v1410(text,numeric,boolean)',
    'public.hq_save_item_v1400(text,text,text,boolean)',
    'public.hq_save_normal_counts_v1410(date,jsonb)',
    'public.get_hq_stock_table_v1410(date,date)'
  ] loop
    execute 'revoke all on function ' || f || ' from public, anon';
    execute 'grant execute on function ' || f || ' to authenticated, service_role';
  end loop;
end $$;

commit;

-- 確認（すべて OK になれば成功）
select '1.通常在庫の表' as 確認, case when to_regclass('public.hq_normal_items_v1410') is not null and to_regclass('public.hq_normal_counts_v1410') is not null then 'OK' else 'NG' end as 結果
union all select '2.関数', case when (select count(*) from pg_proc where proname in ('hq_save_normal_item_v1410','hq_save_normal_counts_v1410','get_hq_stock_table_v1410')) = 3 then 'OK' else 'NG' end
union all select '3.品目名の重なり防止', case when pg_get_functiondef('public.hq_save_item_v1400(text,text,text,boolean)'::regprocedure) like '%hq_normal_items_v1410%' then 'OK' else 'NG' end
union all select '4.未ログインでは使えない', case when not has_function_privilege('anon','public.get_hq_stock_table_v1410(date,date)','execute')
  and not has_function_privilege('anon','public.hq_save_normal_counts_v1410(date,jsonb)','execute') then 'OK' else 'NG' end;
