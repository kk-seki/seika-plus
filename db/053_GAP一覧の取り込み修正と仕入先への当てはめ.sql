/*
053_GAP一覧の取り込み修正と仕入先への当てはめ.sql（v1.199-c131）

目的：
  1. GAP一覧の取り込みで「DELETE requires a WHERE clause」と出て保存できない不具合を直す。
  2. GAP一覧の名前が、ロットの単協名だけでなく仕入先と同じときも、さかのぼって認証区分を入れる（単協名で当たるほうが先）。

前提：db/052 を実行済みであること。関数を作り直すだけで、表の中身は変わりません。何度実行しても同じ結果になります。
*/
begin;

do $block$
begin
  if to_regclass('public.qr_gap_certs_v1199c130') is null or to_regprocedure('public.seika_gap_item_family_v1199c130(text)') is null then
    raise exception '先に db/052 を実行してください';
  end if;
end $block$;

-- ===== GAP一覧を全部置き換える（管理者） =====
create or replace function public.replace_qr_gap_certs_v1199c130(p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public'
as $f$
declare
  v_profile public.profiles%rowtype;
  r jsonb;
  v_coop text; v_item text; v_cert text; v_exp date; v_n integer := 0; v_line integer := 0;
begin
  perform public.seika_require_role_v1240(array['admin']);
  select * into v_profile from public.profiles where id = auth.uid() and active limit 1;
  if v_profile.id is null then raise exception 'ログインが必要です' using errcode = '42501'; end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then raise exception '取り込む行がありません' using errcode = '22023'; end if;
  perform pg_advisory_xact_lock(hashtext('qr_gap_certs_v1199c130'));

  create temp table if not exists c130_gap_new(
    coop_norm text, coop_name text, item_norm text, item_name text, certification text, expires_on date, note text
  ) on commit drop;
  truncate c130_gap_new;

  for r in select value from jsonb_array_elements(p_rows) loop
    v_line := v_line + 1;
    v_coop := btrim(coalesce(r->>'coop_name',''));
    v_item := btrim(coalesce(r->>'item_name',''));
    v_cert := upper(btrim(coalesce(r->>'certification','')));
    if v_coop = '' or v_item = '' then raise exception '%行目：単協名と品目は必須です', v_line using errcode = '22023'; end if;
    if v_cert not in ('JGAP','GGAP','ASIAGAP') then raise exception '%行目：認証区分が正しくありません（%）', v_line, v_cert using errcode = '22023'; end if;
    begin v_exp := (r->>'expires_on')::date;
    exception when others then raise exception '%行目：有効期限が日付ではありません', v_line using errcode = '22023'; end;
    if v_exp is null then raise exception '%行目：有効期限は必須です', v_line using errcode = '22023'; end if;
    insert into c130_gap_new values (public.seika_party_norm_v1280(v_coop), v_coop, public.seika_party_norm_v1280(v_item), v_item, v_cert, v_exp, btrim(coalesce(r->>'note','')));
    v_n := v_n + 1;
  end loop;

  if exists (select 1 from c130_gap_new group by coop_norm, item_norm having count(*) > 1) then
    raise exception '同じ単協・品目の行が2つ以上あります' using errcode = '22023';
  end if;

  -- Supabase では WHERE のない DELETE が止められるため、where true を付ける
  delete from public.qr_gap_certs_v1199c130 where true;
  insert into public.qr_gap_certs_v1199c130(coop_norm, coop_name, item_norm, item_name, certification, expires_on, note, imported_by_name, imported_at)
  select coop_norm, coop_name, item_norm, item_name, certification, expires_on, note, coalesce(v_profile.display_name,''), now() from c130_gap_new;
  return jsonb_build_object('ok', true, 'count', v_n);
end
$f$;
revoke all on function public.replace_qr_gap_certs_v1199c130(jsonb) from public, anon;
grant execute on function public.replace_qr_gap_certs_v1199c130(jsonb) to authenticated, service_role;

-- ===== 在庫が残るロットに、さかのぼってGAPを入れる（管理者）。p_apply=false は対象の確認だけ =====
-- 単協名か仕入先がGAP一覧の名前と同じロットに入れる（単協名で当たる行が先）。品目は、同じ名前の行を先に使い、なければまとめた品目（例：大根）の行を使う
create or replace function public.qr_gap_backfill_v1199c130(p_apply boolean default false)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public'
as $f$
declare
  v_rows jsonb;
  v_n integer := 0;
begin
  perform public.seika_require_role_v1240(array['admin']);
  create temp table if not exists c131_backfill(id uuid, lot_no text, item_name text, cooperative_name text, supplier text, received_date date, certification text, expires_on date) on commit drop;
  truncate c131_backfill;
  insert into c131_backfill
  select distinct on (l.id) l.id, l.lot_no, l.item_name, l.cooperative_name, l.supplier, l.received_date, g.certification, g.expires_on
  from public.qr_lots l
  join public.qr_gap_certs_v1199c130 g
    on g.coop_norm in (public.seika_party_norm_v1280(l.cooperative_name), public.seika_party_norm_v1280(l.supplier))
   and g.coop_norm <> ''
   and g.item_norm in (public.seika_party_norm_v1280(l.item_name), public.seika_gap_item_family_v1199c130(l.item_name))
  where coalesce(l.active, true)
    and coalesce(l.current_qty, 0) > 0
    and coalesce(btrim(l.certification), '') = ''
    and l.received_date is not null
  -- 単協名で当たる行を先に、なければ仕入先で当たる行。品目は同じ名前の行を先に
  order by l.id, (g.coop_norm = public.seika_party_norm_v1280(l.cooperative_name)) desc, (g.item_norm = public.seika_party_norm_v1280(l.item_name)) desc;
  delete from c131_backfill where received_date > expires_on;

  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'lot_no', lot_no, 'item_name', item_name, 'cooperative_name', cooperative_name, 'supplier', supplier,
           'received_date', received_date, 'certification', certification, 'expires_on', expires_on) order by item_name, received_date), '[]'::jsonb),
         count(*)
    into v_rows, v_n from c131_backfill;

  if p_apply and v_n > 0 then
    update public.qr_lots l set certification = b.certification
    from c131_backfill b
    where l.id = b.id and coalesce(btrim(l.certification), '') = '';
    get diagnostics v_n = row_count;
  end if;
  return jsonb_build_object('ok', true, 'applied', p_apply, 'count', v_n, 'rows', v_rows);
end
$f$;
revoke all on function public.qr_gap_backfill_v1199c130(boolean) from public, anon;
grant execute on function public.qr_gap_backfill_v1199c130(boolean) to authenticated, service_role;

commit;

-- 確認：2行とも「OK」なら成功です
select 'GAP一覧の取り込み' as 確認項目, case when position('where true' in pg_get_functiondef('public.replace_qr_gap_certs_v1199c130(jsonb)'::regprocedure)) > 0 then 'OK' else '要確認' end as 判定
union all select '仕入先への当てはめ', case when position('l.supplier' in pg_get_functiondef('public.qr_gap_backfill_v1199c130(boolean)'::regprocedure)) > 0 then 'OK' else '要確認' end;
