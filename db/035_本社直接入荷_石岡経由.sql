-- v1.199-c83 本社直接入荷（石岡経由）
-- 目的：本社へ直接入荷する原料のうち、一度石岡を経由して積み込むものを、石岡で入庫せずに
--       本社の「入荷待ち原料」として登録し、本社移動用の貼り紙を発行できるようにする。
--  1) 本社の原料に「石岡経由」の印（via_ishioka）を追加する。入荷区分は「本社直接入荷」のまま。
--  2) 石岡の管理者・青果社員が登録できる処理を追加する（便・本社入荷日も記録）。
--  3) 本社が受け入れる前なら、石岡の管理者・青果社員が取消できる処理を追加する。
--  石岡のQR在庫（qr_lots）・在庫表・在庫/出庫の分析には入りません。
--  016・018・033を実行済みであることが前提です。何度実行しても同じ結果になります。既存の原料は変わりません。
begin;

alter table public.hq_lots_v1400 add column if not exists via_ishioka boolean not null default false;

create or replace function public.hq_direct_via_ishioka_v1199c83(p_item_name text, p_origin text, p_supplier text,
  p_cooperative_name text, p_container_type text, p_pack_weight text, p_qty numeric, p_count numeric,
  p_planned_date date, p_ship_run text, p_ship_run_time text, p_ship_day text, p_memo text default null)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles; r public.hq_lots_v1400%rowtype; v_unit text; v_today date;
begin
  v := public.hq_actor_v1400(array['admin','worker']);
  v_today := (now() at time zone 'Asia/Tokyo')::date;
  v_unit := public.hq_unit_for_v1400(p_container_type);
  if btrim(coalesce(p_item_name,'')) = '' then raise exception '品目を選んでください'; end if;
  if not exists (select 1 from public.hq_items_v1400 where name = btrim(p_item_name)) then raise exception '本社の品目にない品目です'; end if;
  if btrim(coalesce(p_ship_run,'')) = '' then raise exception '本社への便を選んでください'; end if;
  if coalesce(p_ship_day,'') not in ('当日便','翌日便') then raise exception '当日便か翌日便かを選んでください'; end if;
  if v_unit = 'kg' then
    if p_count is null or p_count < 1 or p_count <> trunc(p_count) then raise exception '基数を入れてください'; end if;
  elsif coalesce(p_qty,0) <= 0 then raise exception '数量を入れてください';
  end if;
  insert into public.hq_lots_v1400(lot_no, qr_key, source_kind, via_ishioka, item_name, origin, supplier, cooperative_name,
    container_type, pack_weight, unit, planned_qty, planned_count, planned_date, status, memo, created_by, created_by_name,
    shipped_date, ship_run, ship_run_time, ship_day)
  values (public.hq_new_lot_no_v1400(), 'HQ-' || replace(gen_random_uuid()::text,'-',''), '本社直接入荷', true, btrim(p_item_name),
    nullif(btrim(coalesce(p_origin,'')),''), nullif(btrim(coalesce(p_supplier,'')),''), nullif(btrim(coalesce(p_cooperative_name,'')),''),
    nullif(p_container_type,''), nullif(btrim(coalesce(p_pack_weight,'')),''), v_unit,
    case when v_unit = 'kg' then 0 else p_qty end, case when v_unit = 'kg' then p_count end,
    coalesce(p_planned_date, v_today + case when p_ship_day = '翌日便' then 1 else 0 end), '入荷待ち',
    nullif(btrim(coalesce(p_memo,'')),''), v.id, v.display_name,
    v_today, btrim(p_ship_run), nullif(btrim(coalesce(p_ship_run_time,'')),''), p_ship_day)
  returning * into r;
  return jsonb_build_object('ok', true, 'lot', to_jsonb(r));
end $$;

create or replace function public.hq_cancel_via_ishioka_v1199c83(p_lot_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles;
begin
  v := public.hq_actor_v1400(array['admin','worker']);
  update public.hq_lots_v1400 set status = '取消',
    memo = concat_ws(' / ', memo, '取消（' || v.display_name || '）：' || coalesce(nullif(btrim(p_reason),''),'理由なし')), updated_at = now()
  where id = p_lot_id and status = '入荷待ち' and via_ishioka;
  if not found then raise exception '取消できる原料がありません（本社で受け入れ済みか、すでに取消されています）'; end if;
  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.hq_direct_via_ishioka_v1199c83(text,text,text,text,text,text,numeric,numeric,date,text,text,text,text) from public, anon;
grant execute on function public.hq_direct_via_ishioka_v1199c83(text,text,text,text,text,text,numeric,numeric,date,text,text,text,text) to authenticated, service_role;
revoke all on function public.hq_cancel_via_ishioka_v1199c83(uuid,text) from public, anon;
grant execute on function public.hq_cancel_via_ishioka_v1199c83(uuid,text) to authenticated, service_role;

commit;
notify pgrst, 'reload schema';

-- 確認：3行とも「OK」なら成功です
select '本社の原料に「石岡経由」の印' as 確認項目,
       case when exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'hq_lots_v1400' and column_name = 'via_ishioka') then 'OK' else '要確認' end as 判定
union all
select '石岡で登録する仕組み',
       case when to_regprocedure('public.hq_direct_via_ishioka_v1199c83(text,text,text,text,text,text,numeric,numeric,date,text,text,text,text)') is not null then 'OK' else '要確認' end
union all
select '石岡で取消する仕組み',
       case when to_regprocedure('public.hq_cancel_via_ishioka_v1199c83(uuid,text)') is not null then 'OK' else '要確認' end;
