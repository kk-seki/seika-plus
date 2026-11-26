/*
070_AIの予定と確定の差.sql（v1.199-c167）

目的：AI（ai_data_v1199c165 の plan_vs_actual）の「予定と確定の差」を、アプリのホームのカード（c151）と同じ考え方にする。
  ・埼玉・深谷（社内）は産地報告書に入らないので除く（「実績が未入力」と誤って出ていた）。
  ・その日の産地報告書に出てくる客先だけを比べる。
  ・予定にあって産地報告書にない行は「キャンセル（産地報告書にない）」とする（産地報告書にはキャンセル後の数だけを書く運用）。
  ・行ごとに status（キャンセル／予定より多い／予定より少ない／予定どおり／予定にない追加）を付ける。
  ・別便（産地報告書には入れないが出荷している客先×品目。例：フジフーズ(株) 千葉工場の土付きじゃが芋は別便で引取り）を登録する表
    ship_separate_v1199c167 を作り、登録した客先×品目は比べに出さない（キャンセルとも言わない）。ホームのカードと「出荷予定と確定のちがい」も同じ表を見る。
    見るのはログインしている人、登録・外すのは管理者（set_ship_separate_v1199c167）。
前提：069 を実行済みであること。今までのデータは変わりません（別便の表を1つ足し、フジフーズ×土付きじゃが芋を1件入れます）。何度実行しても同じ結果になります。
元に戻すとき：069 をもう一度実行し、drop function if exists public.set_ship_separate_v1199c167(text, text, boolean, text); drop table if exists public.ship_separate_v1199c167;
*/
begin;

-- 別便（産地報告書には入れないが出荷している客先×品目）
create table if not exists public.ship_separate_v1199c167(
  customer_name text not null,
  item_name text not null,
  note text not null default '',
  created_by_name text not null default '',
  created_at timestamptz not null default now(),
  primary key (customer_name, item_name)
);
alter table public.ship_separate_v1199c167 enable row level security;
revoke all on public.ship_separate_v1199c167 from public, anon, authenticated;
grant select on public.ship_separate_v1199c167 to authenticated;
grant all on public.ship_separate_v1199c167 to service_role;
drop policy if exists ship_separate_v1199c167_read on public.ship_separate_v1199c167;
create policy ship_separate_v1199c167_read on public.ship_separate_v1199c167 for select to authenticated using (true);
insert into public.ship_separate_v1199c167(customer_name, item_name, note, created_by_name)
values ('フジフーズ(株) 千葉工場', '土付きじゃが芋', '別便で引取り（産地報告書に入れない）', '初期登録（c167）')
on conflict do nothing;

create or replace function public.set_ship_separate_v1199c167(p_customer text, p_item text, p_on boolean, p_note text default '')
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public'
as $s$
declare v_profile public.profiles%rowtype; v_c text := btrim(coalesce(p_customer, '')); v_i text := btrim(coalesce(p_item, ''));
begin
  v_profile := public.trimming_require_role(array['admin']);
  if v_c = '' or v_i = '' then raise exception '客先と品目を選んでください' using errcode = '22023'; end if;
  if coalesce(p_on, true) then
    insert into public.ship_separate_v1199c167(customer_name, item_name, note, created_by_name)
    values (v_c, v_i, left(btrim(coalesce(p_note, '')), 200), coalesce(v_profile.display_name, ''))
    on conflict (customer_name, item_name) do update set note = excluded.note, created_by_name = excluded.created_by_name, created_at = now();
  else
    delete from public.ship_separate_v1199c167 where customer_name = v_c and item_name = v_i;
  end if;
  return jsonb_build_object('ok', true);
end
$s$;
revoke all on function public.set_ship_separate_v1199c167(text, text, boolean, text) from public, anon;
grant execute on function public.set_ship_separate_v1199c167(text, text, boolean, text) to authenticated;

create or replace function public.ai_data_v1199c165(p_kind text, p_from date default null, p_to date default null, p_item text default null, p_customer text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','public'
as $f$
declare
  v_role text;
  v_today date := (now() at time zone 'Asia/Tokyo')::date;
  v_from date := coalesce(p_from, (now() at time zone 'Asia/Tokyo')::date - 7);
  v_to date := coalesce(p_to, (now() at time zone 'Asia/Tokyo')::date);
  v_item text := nullif(btrim(coalesce(p_item, '')), '');
  v_cust text := nullif(btrim(coalesce(p_customer, '')), '');
  v_out jsonb;
begin
  perform public.seika_require_role_v1240(array['admin','worker','buyer','sales']);
  v_role := public.current_app_role();
  if v_to < v_from then v_from := v_to; end if;
  if v_to - v_from > 92 then raise exception '期間は92日までにしてください' using errcode = '22023'; end if;

  if p_kind = 'stock' then
    -- 今の在庫（品目ごと）。いちばん古い入荷日も出す
    select jsonb_agg(x) into v_out from (
      select jsonb_build_object('item', item_name, 'unit', unit, 'qty', round(sum(current_qty), 2), 'kg', round(sum(current_weight), 1),
                                'lots', count(*), 'oldest_received', min(received_date)) x
        from public.qr_lots
       where coalesce(active, true) and coalesce(current_qty, 0) > 0 and (v_item is null or item_name ilike '%' || v_item || '%')
       group by item_name, unit order by sum(current_qty) desc limit 80) t;

  elsif p_kind = 'outbound' then
    -- 出庫（品目×出庫先ごと。取消は除く）
    select jsonb_agg(x) into v_out from (
      select jsonb_build_object('item', item_name, 'destination', destination, 'unit', unit, 'qty', round(sum(qty), 2), 'kg', round(sum(weight), 1), 'times', count(*)) x
        from public.qr_lot_movements
       where movement_type = '出庫' and cancelled_at is null
         and (occurred_at at time zone 'Asia/Tokyo')::date between v_from and v_to
         and (v_item is null or item_name ilike '%' || v_item || '%')
         and (v_cust is null or destination ilike '%' || v_cust || '%')
       group by item_name, destination, unit order by sum(qty) desc limit 80) t;

  elsif p_kind = 'waste' then
    -- 廃棄（品目ごと）。この会社の「廃棄」は、廃棄の記録・QR廃棄・トリミング廃棄（下処理の日報の廃棄kg）を合わせたもの（c166）
    select jsonb_agg(x) into v_out from (
      select jsonb_build_object('item', item, 'source', src, 'unit', max(u), 'qty', round(sum(q), 2), 'amount_yen', round(sum(a))) x from (
        select item_name item, '廃棄記録' src, null::text u, qty q, amount a from public.waste_records
         where waste_date between v_from and v_to and (v_item is null or item_name ilike '%' || v_item || '%')
        union all
        select item_name, 'QR廃棄', unit, qty, null from public.qr_lot_movements
         where movement_type = '廃棄' and cancelled_at is null and (occurred_at at time zone 'Asia/Tokyo')::date between v_from and v_to
           and (v_item is null or item_name ilike '%' || v_item || '%')
        union all
        select source_item_name, 'トリミング廃棄', 'kg', coalesce(waste_weight_kg, loss_weight_kg), null from public.trimming_jobs
         where work_date between v_from and v_to and coalesce(waste_weight_kg, loss_weight_kg, 0) > 0
           and (v_item is null or source_item_name ilike '%' || v_item || '%')
      ) w group by item, src order by sum(q) desc limit 80) t;

  elsif p_kind = 'plan' then
    -- 出荷予定（今有効な積み込み表。納品日×客先×品目）
    select jsonb_agg(x) into v_out from (
      select jsonb_build_object('delivery_date', l.delivery_date, 'customer', l.customer_name, 'item', l.item_name, 'kg', round(sum(l.kg), 1), 'cases', sum(l.cases)) x
        from public.ship_plan_lines_v1199c140 l join public.ship_plan_imports_v1199c140 i on i.id = l.import_id and i.status = 'active'
       where l.delivery_date between v_from and v_to
         and (v_item is null or l.item_name ilike '%' || v_item || '%')
         and (v_cust is null or l.customer_name ilike '%' || v_cust || '%')
       group by l.delivery_date, l.customer_name, l.item_name order by l.delivery_date, sum(l.kg) desc nulls last limit 80) t;

  elsif p_kind = 'actual' then
    -- 確定数量（今有効な産地報告書。納品日×客先×品目）
    select jsonb_agg(x) into v_out from (
      select jsonb_build_object('delivery_date', l.delivery_date, 'customer', l.customer_name, 'item', l.item_name, 'kg', round(sum(l.kg), 1), 'cases', sum(l.cases)) x
        from public.ship_actual_lines_v1199c142 l join public.ship_actual_imports_v1199c142 i on i.id = l.import_id and i.status = 'active'
       where l.delivery_date between v_from and v_to
         and (v_item is null or l.item_name ilike '%' || v_item || '%')
         and (v_cust is null or l.customer_name ilike '%' || v_cust || '%')
       group by l.delivery_date, l.customer_name, l.item_name order by l.delivery_date, sum(l.kg) desc nulls last limit 80) t;

  elsif p_kind = 'plan_vs_actual' then
    -- 予定と確定の差（c167）：アプリのホームのカード（c151）と同じ考え方。
    --   社外の客先だけ（埼玉・深谷の社内は産地報告書に入らないので除く）。その日の産地報告書に出てくる客先だけを比べる。
    --   予定にあって産地報告書にない行は、キャンセル（産地報告書にはキャンセル後の数だけを書く運用）。
    select jsonb_agg(x) into v_out from (
      select jsonb_build_object('delivery_date', d, 'customer', c, 'item', it, 'plan_kg', round(pk, 1), 'actual_kg', round(coalesce(ak, 0), 1),
                                'diff_kg', round(coalesce(ak, 0) - coalesce(pk, 0), 1),
                                'status', case when ak is null then 'キャンセル（産地報告書にない）' when pk is null then '予定にない追加' when ak > pk then '予定より多い' when ak < pk then '予定より少ない' else '予定どおり' end) x
        from (
          select coalesce(p.d, a.d) d, coalesce(p.c, a.c) c, coalesce(p.it, a.it) it, p.kg pk, a.kg ak
            from (select l.delivery_date d, l.customer_name c, l.item_name it, sum(l.kg) kg from public.ship_plan_lines_v1199c140 l
                    join public.ship_plan_imports_v1199c140 i on i.id = l.import_id and i.status = 'active'
                   where l.delivery_date between v_from and v_to group by 1, 2, 3) p
            full join (select l.delivery_date d, l.customer_name c, l.item_name it, sum(l.kg) kg from public.ship_actual_lines_v1199c142 l
                    join public.ship_actual_imports_v1199c142 i on i.id = l.import_id and i.status = 'active'
                   where l.delivery_date between v_from and v_to group by 1, 2, 3) a
              on a.d = p.d and a.c = p.c and a.it = p.it
        ) z
       where c !~ '(埼玉|深谷)'
         and not exists (select 1 from public.ship_separate_v1199c167 sp where sp.customer_name = z.c and sp.item_name = z.it)
         and exists (select 1 from public.ship_actual_lines_v1199c142 l2 join public.ship_actual_imports_v1199c142 i2 on i2.id = l2.import_id and i2.status = 'active'
                      where l2.delivery_date = z.d and l2.customer_name = z.c)
         and (v_item is null or it ilike '%' || v_item || '%') and (v_cust is null or c ilike '%' || v_cust || '%')
       order by abs(coalesce(ak, 0) - coalesce(pk, 0)) desc limit 80) t;

  elsif p_kind = 'trimming' then
    -- 下処理（日報：品目ごとの原料・出来高・歩留まり）
    select jsonb_agg(x) into v_out from (
      select jsonb_build_object('item', source_item_name, 'days', count(distinct work_date), 'input_kg', round(sum(input_weight_kg), 1),
                                'output_kg', round(sum(output_weight_kg), 1), 'waste_kg', round(sum(coalesce(waste_weight_kg, loss_weight_kg)), 1),
                                'yield_percent', round(100 * sum(output_weight_kg) / nullif(sum(input_weight_kg), 0), 1)) x
        from public.trimming_jobs
       where work_date between v_from and v_to and (v_item is null or source_item_name ilike '%' || v_item || '%')
       group by source_item_name order by sum(input_weight_kg) desc nulls last limit 80) t;

  elsif p_kind = 'quality' then
    -- 品質評価（要確認・不良）
    select jsonb_agg(x) into v_out from (
      select jsonb_build_object('date', (evaluated_at at time zone 'Asia/Tokyo')::date, 'item', item_name, 'lot_no', lot_no, 'grade', grade, 'issues', issues, 'memo', left(coalesce(memo, ''), 80)) x
        from public.qr_quality_evaluations
       where coalesce(active, true) and invalidated_at is null and grade in ('review','bad')
         and (evaluated_at at time zone 'Asia/Tokyo')::date between v_from and v_to
         and (v_item is null or item_name ilike '%' || v_item || '%')
       order by evaluated_at desc limit 80) t;

  elsif p_kind = 'gap' then
    -- GAP認証（期限切れと90日以内に切れるもの）
    select jsonb_agg(x) into v_out from (
      select jsonb_build_object('coop', coop_name, 'item', item_name, 'certification', certification, 'expires_on', expires_on) x
        from public.qr_gap_certs_v1199c130
       where expires_on <= v_today + 90 and (v_item is null or item_name ilike '%' || v_item || '%')
       order by expires_on limit 80) t;

  elsif p_kind = 'prices' then
    -- 仕入れ価格（週ごと。管理者・仕入れ担当だけ）
    if v_role not in ('admin','buyer') then
      return jsonb_build_object('kind', p_kind, 'denied', true, 'message', '仕入れ価格は管理者・仕入れ担当だけが見られます');
    end if;
    select jsonb_agg(x) into v_out from (
      select jsonb_build_object('week_start', week_start, 'item', item_name, 'origin', origin, 'yen_per_kg', price_yen_per_kg) x
        from public.purchase_prices
       where week_start between v_from - 7 and v_to and (v_item is null or item_name ilike '%' || v_item || '%')
       order by week_start desc, item_name limit 80) t;

  else
    raise exception '知らない種類です：%', p_kind using errcode = '22023';
  end if;

  return jsonb_build_object('kind', p_kind, 'from', v_from, 'to', v_to, 'item', v_item, 'customer', v_cust, 'rows', coalesce(v_out, '[]'::jsonb));
end
$f$;

revoke all on function public.ai_data_v1199c165(text, date, date, text, text) from public, anon;
grant execute on function public.ai_data_v1199c165(text, date, date, text, text) to authenticated, service_role;

commit;

-- ===== 確認（OK なら成功） =====
select
  (select case when position('ship_separate_v1199c167' in pg_get_functiondef('public.ai_data_v1199c165(text,date,date,text,text)'::regprocedure)) > 0 then 'OK' else 'NG' end) as "予定と確定の差（c151と同じ・別便を除く）",
  (select case when exists (select 1 from public.ship_separate_v1199c167 where customer_name = 'フジフーズ(株) 千葉工場' and item_name = '土付きじゃが芋') then 'OK' else 'NG' end) as "別便の表（フジフーズのじゃが芋）";
