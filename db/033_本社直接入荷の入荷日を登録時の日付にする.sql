-- v1.199-c79 本社に直接入荷した原料も、登録したときに入れた入荷日を本社入荷日にする
-- 原因：032では石岡から来た原料だけを直したため、本社直接入荷は「確定して本社の在庫にする」を押した日（今日）になっていた。
-- 修正：
--  1) 本社直接入荷も、受け入れを確定したとき、登録時に入れた入荷日のままにする（入荷日がまだ先の日付のときだけ確定した日）。
--  2) すでに受け入れた本社直接入荷の原料も、同じルールで本社入荷日を直す。
--  在庫表・品目別使用数量は、032で本社入荷日で数えるようになっているので、そのまま反映されます。
--  032を実行済みであることが前提です。何度実行しても同じ結果になります。
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
    hq_received_date = case when l.planned_date is not null
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

drop table if exists pg_temp.c79_fixed;
create temp table c79_fixed as
with t as (
  update public.hq_lots_v1400 l
     set hq_received_date = least(l.planned_date, coalesce((l.confirmed_at at time zone 'Asia/Tokyo')::date, l.hq_received_date)),
         updated_at = now()
   where l.source_kind = '本社直接入荷'
     and l.status in ('在庫あり','在庫なし')
     and l.planned_date is not null
     and l.hq_received_date is distinct from least(l.planned_date, coalesce((l.confirmed_at at time zone 'Asia/Tokyo')::date, l.hq_received_date))
  returning l.id
) select count(*) n from t;

commit;

-- 確認：3行とも「OK」なら成功です（1行目は今回直した件数。2回目以降は0件）
select '直した本社入荷日（本社直接入荷） ' || (select n from pg_temp.c79_fixed) || '件' as 確認項目, 'OK' as 判定
union all
select '受け入れ確定：登録時の入荷日を使う（直接入荷も）',
       case when pg_get_functiondef('public.hq_receive_v1400(uuid,uuid,numeric,text,text[],text,text[])'::regprocedure) like '%case when l.planned_date is not null%'
            then 'OK' else '要確認' end
union all
select '受け入れ済み：本社入荷日がずれている原料が残っていない',
       case when not exists (select 1 from public.hq_lots_v1400 l where l.status in ('在庫あり','在庫なし')
              and l.planned_date is not null
              and l.hq_received_date is distinct from least(l.planned_date, coalesce((l.confirmed_at at time zone 'Asia/Tokyo')::date, l.hq_received_date)))
            then 'OK' else '要確認' end;
