-- v1.199-c91 本社アカウントで石岡の情報を見る／本社 荷受け担当者の「下処理」出庫
--  ・本社社員・本社事務が、石岡の「仕入れ価格表」を見られるようにします（見るだけ。登録・変更はできません）。
--    ほかの5つ（QR出庫履歴・品質評価一覧・品質レポート・在庫・出庫の分析・産地状況・市場動向メモ）は、今のままで見られるのでSQLの変更はありません。
--  ・本社 荷受け担当者が、在庫反映がオフの間だけ、出庫先「下処理」で出庫できるようにします。
--    在庫反映をオンにすると、今までどおり誰も「下処理」へは出庫できません（下処理の確定で減ります）。
--  在庫・価格などのデータは変わりません。何度実行しても同じ結果になります。
begin;

-- 1. 仕入れ価格表を見られる権限に、本社社員（hq_worker）・本社事務（hq_clerk）を追加
CREATE OR REPLACE FUNCTION public.get_purchase_prices(p_week_start date DEFAULT NULL::date)
 RETURNS SETOF purchase_prices
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform public.trimming_require_role(array['admin','worker','buyer','sales','clerk','viewer','office_viewer','hq_worker','hq_clerk']);
  return query select pp.* from public.purchase_prices pp
    where p_week_start is null or pp.week_start = public.trimming_week_start(p_week_start)
    order by pp.week_start desc, pp.item_name, pp.origin, pp.supplier;
end;
$function$;

-- 2. 本社の使用出庫：在庫反映オフの間は、荷受け担当者（hq_receiver）も「下処理」へ出庫できる
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
    v := public.hq_actor_v1400(array['admin','hq_worker','hq_prep','hq_receiver']);
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

commit;

-- 確認：2行とも「OK」なら成功です
select '仕入れ価格表を本社で見る' as 確認項目, case when exists (select 1 from pg_proc where proname = 'get_purchase_prices' and position('hq_clerk' in prosrc) > 0) then 'OK' else '要確認' end as 判定
union all select '荷受け担当者の下処理出庫', case when exists (select 1 from pg_proc where proname = 'hq_outbound_v1500' and position('''hq_prep'',''hq_receiver''' in prosrc) > 0) then 'OK' else '要確認' end;
