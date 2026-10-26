/*
022_本社_作業の削除と仕入れ価格表.sql（v1.199-c60）
1. 本社社員・管理者が、下処理・作業・清掃の記録を完全に削除できるようにします（試しに入力したものを消すため）。
   確定済みで在庫を減らしていた下処理は、在庫と下処理ロスを元に戻してから消します。
   消した内容は、念のため「削除の記録」（hq_deleted_works_v1500）に残します（画面には出ません）。
2. 本社の仕入れ価格表に、表示している期間に市場価格が登録されている品目をすべて出します（契約産地の価格は使いません）。
前提：019を実行済みであること。何度実行しても同じ結果になります。
説明は行頭のハイフン2つを使わない書き方にしています（スマホから貼り付けても壊れないようにするため）。
*/
begin;

create table if not exists public.hq_deleted_works_v1500 (
  id uuid primary key default gen_random_uuid(),
  work_id uuid not null,
  work jsonb not null,
  materials jsonb not null default '[]'::jsonb,
  members jsonb not null default '[]'::jsonb,
  deleted_by_name text,
  deleted_at timestamptz not null default now()
);
alter table public.hq_deleted_works_v1500 enable row level security;
drop policy if exists hq_deleted_works_v1500_read on public.hq_deleted_works_v1500;
create policy hq_deleted_works_v1500_read on public.hq_deleted_works_v1500 for select to authenticated using (true);
revoke all on public.hq_deleted_works_v1500 from anon, public;
grant select on public.hq_deleted_works_v1500 to authenticated;
grant all on public.hq_deleted_works_v1500 to service_role;

create or replace function public.hq_work_delete_v1500(p_work_id uuid)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles; w public.hq_works_v1500%rowtype; restored boolean := false;
begin
  v := public.hq_actor_v1400(array['admin','hq_worker']);
  select * into w from public.hq_works_v1500 where id = p_work_id for update;
  if not found then raise exception '作業が見つかりません（すでに削除されています）'; end if;
  if w.stock_applied then
    perform public.hq_prep_unapply_v1500(w.id, v);
    restored := true;
  end if;
  insert into public.hq_deleted_works_v1500(work_id, work, materials, members, deleted_by_name)
  values (w.id, to_jsonb(w),
    coalesce((select jsonb_agg(to_jsonb(m)) from public.hq_work_materials_v1500 m where m.work_id = w.id), '[]'::jsonb),
    coalesce((select jsonb_agg(to_jsonb(m)) from public.hq_work_members_v1500 m where m.work_id = w.id), '[]'::jsonb),
    v.display_name);
  delete from public.hq_lot_movements_v1400 where work_id = w.id and (cancelled_at is not null or movement_type = '下処理取消');
  delete from public.hq_waste_v1500 where work_id = w.id and kind = '下処理ロス';
  delete from public.hq_work_materials_v1500 where work_id = w.id;
  delete from public.hq_work_members_v1500 where work_id = w.id;
  delete from public.hq_works_v1500 where id = w.id;
  return jsonb_build_object('ok', true, 'restored', restored);
end $$;
revoke all on function public.hq_work_delete_v1500(uuid) from public, anon;
grant execute on function public.hq_work_delete_v1500(uuid) to authenticated, service_role;

create or replace function public.hq_price_table_v1500(p_from date, p_to date, p_items text[] default null)
returns jsonb language plpgsql stable security definer set search_path to ''
as $$
declare v public.profiles; res jsonb;
begin
  v := public.hq_actor_v1400(array['admin','worker','buyer','sales','clerk','office_viewer','viewer','hq_worker','hq_clerk','hq_receiver']);
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 800 then raise exception '期間が正しくありません'; end if;
  with base_names as (
    select distinct n from (
      select unnest(p_items) n
      union select name from public.hq_items_v1400 where p_items is null
      union select name from public.hq_normal_items_v1410 where p_items is null
      union select item_name from public.hq_prep_masters_v1500 where p_items is null
    ) z where btrim(coalesce(n,'')) <> ''
  ),
  market_names as (
    select distinct btrim(pp.item_name) n
    from public.purchase_prices pp
    where p_items is null
      and (pp.price_type = 'market' or btrim(pp.supplier) in ('市場','水戸大同','大同','水戸中央','中央','東一','シティ'))
      and pp.price_yen_per_kg >= 0
      and pp.week_start >= date_trunc('week', p_from)::date and pp.week_start <= p_to
      and btrim(coalesce(pp.item_name,'')) <> ''
  ),
  names as (
    select n from base_names
    union
    select min(m.n) from market_names m
    where not exists (select 1 from base_names b where m.n = any(public.seika_item_name_group_v1200(b.n)))
    group by (select min(x) from unnest(public.seika_item_name_group_v1200(m.n)) x)
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


commit;

/* 成功の確かめ方：下のSELECTを実行して、2行とも「OK」になれば成功です。 */
select '作業の削除' as 項目, case when to_regprocedure('public.hq_work_delete_v1500(uuid)') is not null and to_regclass('public.hq_deleted_works_v1500') is not null then 'OK' else 'NG' end as 結果
union all
select '仕入れ価格表', case when position('market_names' in pg_get_functiondef('public.hq_price_table_v1500(date,date,text[])'::regprocedure)) > 0 then 'OK' else 'NG' end;
