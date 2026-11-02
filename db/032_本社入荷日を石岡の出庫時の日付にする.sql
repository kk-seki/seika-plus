-- v1.199-c77 本社入荷日を、石岡で出庫したときに決めた本社入荷日にする
-- 原因：本社で「確定して本社の在庫にする」を押すと、本社入荷日が押した日（今日）で上書きされていた。
-- 修正：
--  1) 石岡から来た原料は、受け入れを確定しても、石岡の出庫時に決めた本社入荷日（予定）のままにする。
--     （予定日がまだ先の日付のときだけは、確定した日にする）本社直接入荷は今までどおり。
--  2) すでに受け入れた石岡からの原料も、同じルールで本社入荷日を直す。
--  3) 在庫表・品目別使用数量も、本社入荷日の日に入ったものとして数える。
--  入出庫履歴の「入庫確定」の日時（誰がいつ押したか）は、記録のためそのまま残します。
-- 何度実行しても同じ結果になります。
begin;

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
    hq_received_date = case when l.source_kind = '石岡から' and l.planned_date is not null
                            then least(l.planned_date, (now() at time zone 'Asia/Tokyo')::date)
                            else (now() at time zone 'Asia/Tokyo')::date end,
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

drop table if exists pg_temp.c77_fixed;
create temp table c77_fixed as
with t as (
  update public.hq_lots_v1400 l
     set hq_received_date = least(l.planned_date, coalesce((l.confirmed_at at time zone 'Asia/Tokyo')::date, l.hq_received_date)),
         updated_at = now()
   where l.source_kind = '石岡から'
     and l.status in ('在庫あり','在庫なし')
     and l.planned_date is not null
     and l.hq_received_date is distinct from least(l.planned_date, coalesce((l.confirmed_at at time zone 'Asia/Tokyo')::date, l.hq_received_date))
  returning l.id
) select count(*) n from t;

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
    select m.lot_id,
      case when m.movement_type = '入庫確定' and hl.hq_received_date is not null
           then least(hl.hq_received_date, (m.occurred_at at time zone 'Asia/Tokyo')::date)
           else (m.occurred_at at time zone 'Asia/Tokyo')::date end dt,
      m.movement_type, m.destination,
      case m.movement_type when '入庫確定' then m.qty when '出庫' then -m.qty when '実数調整' then m.qty
        when '下処理使用' then -m.qty when '廃棄' then -m.qty else 0 end dq, m.qty
    from public.hq_lot_movements_v1400 m join public.hq_lots_v1400 hl on hl.id = m.lot_id
    where m.cancelled_at is null
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

commit;

-- 確認：4行とも「OK」なら成功です（1行目は今回直した件数。2回目以降は0件）
select '直した本社入荷日 ' || (select n from pg_temp.c77_fixed) || '件' as 確認項目, 'OK' as 判定
union all
select '受け入れ確定：石岡の本社入荷日を使う',
       case when pg_get_functiondef('public.hq_receive_v1400(uuid,uuid,numeric,text,text[],text,text[])'::regprocedure) like '%least(l.planned_date%'
            then 'OK' else '要確認' end
union all
select '受け入れ済み：本社入荷日がずれている原料が残っていない',
       case when not exists (select 1 from public.hq_lots_v1400 l where l.source_kind = '石岡から' and l.status in ('在庫あり','在庫なし')
              and l.planned_date is not null
              and l.hq_received_date is distinct from least(l.planned_date, coalesce((l.confirmed_at at time zone 'Asia/Tokyo')::date, l.hq_received_date)))
            then 'OK' else '要確認' end
union all
select '在庫表：本社入荷日で数える',
       case when pg_get_functiondef('public.get_hq_stock_table_v1500(date,date)'::regprocedure) like '%hl.hq_received_date%'
            then 'OK' else '要確認' end;
