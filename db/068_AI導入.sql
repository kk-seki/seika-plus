/*
068_AI導入.sql（v1.199-c165）

目的：SEIKA＋に AI（Claude）を入れるための、データベース側の準備。
 ・AI が使う「読むだけ」のデータの取り出し口（ai_data_v1199c165）。在庫・出庫・廃棄・出荷予定・確定・下処理・GAP・品質評価・仕入れ価格を、
   日付・品目・客先でしぼって、品目ごとなどの合計で返す（1回 80 行まで）。仕入れ価格は管理者・仕入れ担当だけ。書き込みはしない。
 ・毎日のまとめ（役割ごとに1日1回作って保存。ai_daily_summaries_v1199c165）。
 ・AI の利用記録（ai_usage_v1199c165）。月ごとの使った量を出し、決めた上限を超えたら止める（Edge Function seika-ai が見る）。
 使えるのは管理者・青果社員・仕入れ担当・営業。
 AI の呼び出しそのものは Edge Function「seika-ai」（supabase/functions/seika-ai/index.ts）で行う。APIキーは Edge Function のシークレット ANTHROPIC_API_KEY に入れる。

前提：001〜067 を実行済みであること。何度実行しても同じ結果になります。今までのデータは変わりません。

元に戻すとき：
  drop function if exists public.ai_data_v1199c165(text, date, date, text, text);
  drop function if exists public.ai_usage_month_v1199c165();
  drop table if exists public.ai_daily_summaries_v1199c165;
  drop table if exists public.ai_usage_v1199c165;
*/
begin;

-- 1) 利用記録（Edge Function だけが書く）
create table if not exists public.ai_usage_v1199c165(
  id bigserial primary key,
  created_at timestamptz not null default now(),
  user_id uuid,
  user_name text not null default '',
  role text not null default '',
  action text not null,
  model text not null default '',
  input_tokens integer not null default 0,
  output_tokens integer not null default 0,
  cost_usd numeric not null default 0,
  ok boolean not null default true,
  note text not null default ''
);
create index if not exists ai_usage_v1199c165_time_idx on public.ai_usage_v1199c165(created_at desc);
alter table public.ai_usage_v1199c165 enable row level security;
revoke all on public.ai_usage_v1199c165 from public, anon, authenticated;
grant all on public.ai_usage_v1199c165 to service_role;
grant usage, select on sequence public.ai_usage_v1199c165_id_seq to service_role;

-- 2) 毎日のまとめ（役割ごと・1日1つ。Edge Function だけが書く。読むのはその役割の人と管理者）
create table if not exists public.ai_daily_summaries_v1199c165(
  day date not null,
  role text not null check (role in ('admin','worker','buyer','sales')),
  body text not null,
  model text not null default '',
  created_at timestamptz not null default now(),
  primary key (day, role)
);
alter table public.ai_daily_summaries_v1199c165 enable row level security;
revoke all on public.ai_daily_summaries_v1199c165 from public, anon, authenticated;
grant select on public.ai_daily_summaries_v1199c165 to authenticated;
grant all on public.ai_daily_summaries_v1199c165 to service_role;
drop policy if exists ai_daily_summaries_v1199c165_read on public.ai_daily_summaries_v1199c165;
create policy ai_daily_summaries_v1199c165_read on public.ai_daily_summaries_v1199c165 for select to authenticated
  using (public.current_app_role() = 'admin' or public.current_app_role() = role);

-- 3) 今月の利用量（管理者が画面で見る。Edge Function も上限の確認に使う）
create or replace function public.ai_usage_month_v1199c165()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','public'
as $f$
declare v_start timestamptz := date_trunc('month', now() at time zone 'Asia/Tokyo') at time zone 'Asia/Tokyo';
begin
  perform public.seika_require_role_v1240(array['admin']);
  return jsonb_build_object(
    'since', v_start,
    'cost_usd', coalesce((select round(sum(cost_usd), 4) from public.ai_usage_v1199c165 where created_at >= v_start), 0),
    'calls', (select count(*) from public.ai_usage_v1199c165 where created_at >= v_start),
    'by_action', coalesce((select jsonb_object_agg(action, jsonb_build_object('calls', n, 'cost_usd', c))
                             from (select action, count(*) n, round(sum(cost_usd), 4) c from public.ai_usage_v1199c165 where created_at >= v_start group by action) t), '{}'::jsonb),
    'recent', coalesce((select jsonb_agg(jsonb_build_object('at', created_at, 'user', user_name, 'action', action, 'cost_usd', round(cost_usd, 4), 'ok', ok, 'note', note) order by created_at desc)
                          from (select * from public.ai_usage_v1199c165 order by created_at desc limit 20) r), '[]'::jsonb)
  );
end
$f$;

-- 4) AI が使う読むだけのデータ（呼んだ人の権限で動く。書き込みはしない）
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
    -- 廃棄（廃棄の記録とQR廃棄を品目ごとに）
    select jsonb_agg(x) into v_out from (
      select jsonb_build_object('item', item, 'source', src, 'qty', round(sum(q), 2), 'amount_yen', round(sum(a))) x from (
        select item_name item, '廃棄記録' src, qty q, amount a from public.waste_records
         where waste_date between v_from and v_to and (v_item is null or item_name ilike '%' || v_item || '%')
        union all
        select item_name, 'QR廃棄', qty, null from public.qr_lot_movements
         where movement_type = '廃棄' and cancelled_at is null and (occurred_at at time zone 'Asia/Tokyo')::date between v_from and v_to
           and (v_item is null or item_name ilike '%' || v_item || '%')
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
    -- 予定と確定の差（納品日×客先×品目。確定がある日だけ）
    select jsonb_agg(x) into v_out from (
      select jsonb_build_object('delivery_date', d, 'customer', c, 'item', it, 'plan_kg', round(pk, 1), 'actual_kg', round(ak, 1), 'diff_kg', round(coalesce(ak, 0) - coalesce(pk, 0), 1)) x
        from (
          select coalesce(p.d, a.d) d, coalesce(p.c, a.c) c, coalesce(p.it, a.it) it, p.kg pk, a.kg ak
            from (select l.delivery_date d, l.customer_name c, l.item_name it, sum(l.kg) kg from public.ship_plan_lines_v1199c140 l
                    join public.ship_plan_imports_v1199c140 i on i.id = l.import_id and i.status = 'active'
                   where l.delivery_date between v_from and v_to group by 1, 2, 3) p
            full join (select l.delivery_date d, l.customer_name c, l.item_name it, sum(l.kg) kg from public.ship_actual_lines_v1199c142 l
                    join public.ship_actual_imports_v1199c142 i on i.id = l.import_id and i.status = 'active'
                   where l.delivery_date between v_from and v_to group by 1, 2, 3) a
              on a.d = p.d and a.c = p.c and a.it = p.it
           where exists (select 1 from public.ship_actual_imports_v1199c142 i2 where i2.status = 'active' and i2.delivery_date = coalesce(p.d, a.d))
        ) z
       where (v_item is null or it ilike '%' || v_item || '%') and (v_cust is null or c ilike '%' || v_cust || '%')
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
revoke all on function public.ai_usage_month_v1199c165() from public, anon;
grant execute on function public.ai_usage_month_v1199c165() to authenticated, service_role;

commit;

-- ===== 確認（3つとも OK なら成功） =====
select
  (select case when to_regclass('public.ai_usage_v1199c165') is not null then 'OK' else 'NG' end) as "利用記録の表",
  (select case when to_regclass('public.ai_daily_summaries_v1199c165') is not null then 'OK' else 'NG' end) as "毎日のまとめの表",
  (select case when count(*) = 2 then 'OK' else 'NG' end from pg_proc where proname in ('ai_data_v1199c165','ai_usage_month_v1199c165')) as "AIの関数";
