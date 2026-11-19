/*
052_単協・仕入先マスタとGAP一覧.sql（v1.199-c130）

目的：
  1. 単協・仕入先マスタ（qr_party_names_v1280）を正式なマスタとして使えるようにする。
     ・ロットに入っている表記の件数を見る（qr_party_usage_v1199c130）
     ・間違えて入れた表記を、正式名にまとめて過去のロット・履歴も直す（qr_party_merge_v1199c130、管理者のみ）
  2. GAP一覧（単協＋品目ごとの認証区分と有効期限）を保存する（qr_gap_certs_v1199c130）
     ・取り込みは全部置き換え（replace_qr_gap_certs_v1199c130、管理者のみ）
     ・在庫が残るロットに、さかのぼって認証区分を入れる（qr_gap_backfill_v1199c130、管理者のみ）

前提：db/010（仕入先・単協名の候補を共有）まで実行済みであること。
SQLを実行しただけでは、ロット・履歴・GAPの中身は変わりません（アプリの操作で変わります）。
何度実行しても同じ結果になります。
*/
begin;

do $block$
begin
  if to_regclass('public.qr_party_names_v1280') is null
     or to_regprocedure('public.seika_party_norm_v1280(text)') is null
     or to_regprocedure('public.seika_require_role_v1240(text[])') is null then
    raise exception '先に db/010 までを番号順に実行してください';
  end if;
end $block$;

-- ===== GAP一覧 =====
create table if not exists public.qr_gap_certs_v1199c130(
  coop_norm text not null,
  coop_name text not null,
  item_norm text not null,
  item_name text not null,
  certification text not null check (certification in ('JGAP','GGAP','ASIAGAP')),
  expires_on date not null,
  note text not null default '',
  imported_by_name text not null default '',
  imported_at timestamptz not null default now(),
  primary key (coop_norm, item_norm)
);
alter table public.qr_gap_certs_v1199c130 enable row level security;
revoke all on public.qr_gap_certs_v1199c130 from public, anon, authenticated;
grant select on public.qr_gap_certs_v1199c130 to authenticated;
grant all on public.qr_gap_certs_v1199c130 to service_role;
drop policy if exists qr_gap_certs_v1199c130_read on public.qr_gap_certs_v1199c130;
create policy qr_gap_certs_v1199c130_read on public.qr_gap_certs_v1199c130 for select to authenticated using (true);

-- 表記をまとめた記録（あとから確認するため）
create table if not exists public.qr_party_merge_log_v1199c130(
  id bigserial primary key,
  kind text not null,
  from_name text not null,
  to_name text not null,
  lots integer not null default 0,
  movements integer not null default 0,
  hq_lots integer not null default 0,
  done_by uuid,
  done_by_name text not null default '',
  done_at timestamptz not null default now()
);
alter table public.qr_party_merge_log_v1199c130 enable row level security;
revoke all on public.qr_party_merge_log_v1199c130 from public, anon, authenticated;
grant select on public.qr_party_merge_log_v1199c130 to authenticated;
grant all on public.qr_party_merge_log_v1199c130 to service_role;
drop policy if exists qr_party_merge_log_v1199c130_read on public.qr_party_merge_log_v1199c130;
create policy qr_party_merge_log_v1199c130_read on public.qr_party_merge_log_v1199c130 for select to authenticated using (true);

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

  delete from public.qr_gap_certs_v1199c130;
  insert into public.qr_gap_certs_v1199c130(coop_norm, coop_name, item_norm, item_name, certification, expires_on, note, imported_by_name, imported_at)
  select coop_norm, coop_name, item_norm, item_name, certification, expires_on, note, coalesce(v_profile.display_name,''), now() from c130_gap_new;
  return jsonb_build_object('ok', true, 'count', v_n);
end
$f$;
revoke all on function public.replace_qr_gap_certs_v1199c130(jsonb) from public, anon;
grant execute on function public.replace_qr_gap_certs_v1199c130(jsonb) to authenticated, service_role;

-- ===== 在庫が残るロットに、さかのぼってGAPを入れる（管理者）。p_apply=false は対象の確認だけ =====
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
  with t as (
    select l.id, l.lot_no, l.item_name, l.cooperative_name, l.received_date, g.certification, g.expires_on
    from public.qr_lots l
    join public.qr_gap_certs_v1199c130 g
      on g.coop_norm = public.seika_party_norm_v1280(l.cooperative_name)
     and g.item_norm = public.seika_party_norm_v1280(l.item_name)
    where coalesce(l.active, true)
      and coalesce(l.current_qty, 0) > 0
      and coalesce(btrim(l.certification), '') = ''
      and coalesce(btrim(l.cooperative_name), '') <> ''
      and l.received_date is not null
      and l.received_date <= g.expires_on
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'lot_no', lot_no, 'item_name', item_name, 'cooperative_name', cooperative_name,
           'received_date', received_date, 'certification', certification, 'expires_on', expires_on) order by item_name, received_date), '[]'::jsonb),
         count(*)
    into v_rows, v_n from t;

  if p_apply and v_n > 0 then
    update public.qr_lots l set certification = g.certification
    from public.qr_gap_certs_v1199c130 g
    where g.coop_norm = public.seika_party_norm_v1280(l.cooperative_name)
      and g.item_norm = public.seika_party_norm_v1280(l.item_name)
      and coalesce(l.active, true)
      and coalesce(l.current_qty, 0) > 0
      and coalesce(btrim(l.certification), '') = ''
      and coalesce(btrim(l.cooperative_name), '') <> ''
      and l.received_date is not null
      and l.received_date <= g.expires_on;
    get diagnostics v_n = row_count;
  end if;
  return jsonb_build_object('ok', true, 'applied', p_apply, 'count', v_n, 'rows', v_rows);
end
$f$;
revoke all on function public.qr_gap_backfill_v1199c130(boolean) from public, anon;
grant execute on function public.qr_gap_backfill_v1199c130(boolean) to authenticated, service_role;

-- ===== ロットに入っている表記と件数（管理者・青果社員） =====
create or replace function public.qr_party_usage_v1199c130(p_kind text)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','public'
as $f$
declare v jsonb;
begin
  perform public.seika_require_role_v1240(array['admin','worker']);
  if p_kind not in ('supplier','cooperative') then raise exception '種類が正しくありません' using errcode = '22023'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('name', name, 'norm', norm, 'lots', lots, 'last_date', last_date) order by lots desc, name), '[]'::jsonb)
    into v
  from (
    select public.seika_party_norm_v1280(n) norm, min(btrim(n)) name, count(*) lots, max(received_date) last_date
    from (select case when p_kind = 'supplier' then supplier else cooperative_name end n, received_date
          from public.qr_lots where coalesce(active, true)) x
    where coalesce(btrim(n), '') <> ''
    group by 1
  ) s;
  return v;
end
$f$;
revoke all on function public.qr_party_usage_v1199c130(text) from public, anon;
grant execute on function public.qr_party_usage_v1199c130(text) to authenticated, service_role;

-- ===== 表記を正式名にまとめる：過去のロット・履歴の表記も直す（管理者） =====
create or replace function public.qr_party_merge_v1199c130(p_kind text, p_from text, p_to text)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public'
as $f$
declare
  v_profile public.profiles%rowtype;
  v_from text := btrim(coalesce(p_from,''));
  v_to text := btrim(coalesce(p_to,''));
  v_fn text; v_lots integer := 0; v_moves integer := 0; v_hq integer := 0;
  v_col text;
begin
  perform public.seika_require_role_v1240(array['admin']);
  select * into v_profile from public.profiles where id = auth.uid() and active limit 1;
  if v_profile.id is null then raise exception 'ログインが必要です' using errcode = '42501'; end if;
  if p_kind not in ('supplier','cooperative') then raise exception '種類が正しくありません' using errcode = '22023'; end if;
  if v_from = '' or v_to = '' then return jsonb_build_object('ok', false, 'message', '名称が空です'); end if;
  if v_from = v_to then return jsonb_build_object('ok', false, 'message', '同じ名称です'); end if;
  perform pg_advisory_xact_lock(hashtext('qr_party_merge_v1199c130'));
  v_fn := public.seika_party_norm_v1280(v_from);
  v_col := case when p_kind = 'supplier' then 'supplier' else 'cooperative_name' end;

  execute format('update public.qr_lots set %1$I = $1 where public.seika_party_norm_v1280(%1$I) = $2 and %1$I is distinct from $1', v_col)
    using v_to, v_fn;
  get diagnostics v_lots = row_count;
  execute format('update public.qr_lot_movements set %1$I = $1 where public.seika_party_norm_v1280(%1$I) = $2 and %1$I is distinct from $1', v_col)
    using v_to, v_fn;
  get diagnostics v_moves = row_count;
  if to_regclass('public.hq_lots_v1400') is not null then
    execute format('update public.hq_lots_v1400 set %1$I = $1 where public.seika_party_norm_v1280(%1$I) = $2 and %1$I is distinct from $1', v_col)
      using v_to, v_fn;
    get diagnostics v_hq = row_count;
  end if;

  -- マスタ：正式名を有効にし、元の表記は「別名（次からは自動で正式名に直す）」にする
  if public.seika_party_norm_v1280(v_to) <> v_fn then
    perform public.set_qr_party_name_v1280(p_kind, v_from, 'deleted', v_to);
  else
    perform public.set_qr_party_name_v1280(p_kind, v_to, 'active', null);
  end if;

  insert into public.qr_party_merge_log_v1199c130(kind, from_name, to_name, lots, movements, hq_lots, done_by, done_by_name)
  values (p_kind, v_from, v_to, v_lots, v_moves, v_hq, v_profile.id, coalesce(v_profile.display_name,''));
  return jsonb_build_object('ok', true, 'lots', v_lots, 'movements', v_moves, 'hq_lots', v_hq);
end
$f$;
revoke all on function public.qr_party_merge_v1199c130(text, text, text) from public, anon;
grant execute on function public.qr_party_merge_v1199c130(text, text, text) to authenticated, service_role;

commit;

-- 確認：5行とも「OK」なら成功です
select 'GAP一覧の表' as 確認項目, case when to_regclass('public.qr_gap_certs_v1199c130') is not null then 'OK' else '要確認' end as 判定
union all select 'GAP一覧の取り込み', case when to_regprocedure('public.replace_qr_gap_certs_v1199c130(jsonb)') is not null then 'OK' else '要確認' end
union all select 'さかのぼって入れる', case when to_regprocedure('public.qr_gap_backfill_v1199c130(boolean)') is not null then 'OK' else '要確認' end
union all select '表記の件数', case when to_regprocedure('public.qr_party_usage_v1199c130(text)') is not null then 'OK' else '要確認' end
union all select '表記をまとめる', case when to_regprocedure('public.qr_party_merge_v1199c130(text,text,text)') is not null then 'OK' else '要確認' end;
