/*
062_確定数量の取り込み.sql（v1.199-c142）

目的：
  社外の客先の確定数量は「産地報告書」（プライム産地報告.xlsx）にだけあり、翌日には次の日の分で上書きされる。
  セット後に産地報告書を取り込み、客先×品目の確定数量（産地・単協名つき）を保存して、出荷予定（積み込み表）と並べて見られるようにする。
  1. 取り込み1回分（ship_actual_imports_v1199c142）と明細（ship_actual_lines_v1199c142）
     ・同じ納品日をもう一度取り込んだら、前の取り込みは「置き換え済み」にして残す（消さない）
  2. 客先の読み替え（ship_customer_aliases_v1199c142）
     ・産地報告書の客先名 → 積み込み表の客先名（例：「虎昭産業　館林工場」→ 積み込み表の書き方）
  ・品名の読み替え・標準ケースは 061 のものを使う。ケース数は 061 と同じ決め方（標準ケースで割って切り上げ）。

権限：061 と同じ（取り込み：管理者・青果社員・事務員／客先読み替えの削除：管理者／見る：石岡の役割）。
前提：061 を実行済みであること。SQLを実行しただけでは、在庫・QRロット・伝票・出荷予定は変わりません。何度実行しても同じ結果になります。

元に戻すとき：
  drop function if exists public.replace_ship_actual_v1199c142(uuid,date,text,jsonb,jsonb);
  drop function if exists public.save_ship_customer_alias_v1199c142(text,text,text);
  drop function if exists public.delete_ship_customer_alias_v1199c142(text);
  drop table if exists public.ship_actual_lines_v1199c142, public.ship_actual_imports_v1199c142, public.ship_customer_aliases_v1199c142;
*/
begin;

do $block$
begin
  if to_regclass('public.ship_plan_case_std_v1199c140') is null then
    raise exception '先に db/061（出荷予定の取り込み）を実行してください';
  end if;
end $block$;

create table if not exists public.ship_actual_imports_v1199c142(
  id uuid primary key,
  delivery_date date not null,
  ship_date date not null,
  status text not null default 'active' check (status in ('active','replaced')),
  file_name text not null default '',
  sheets jsonb not null default '[]'::jsonb,
  line_count integer not null default 0,
  total_kg numeric not null default 0,
  replaced_by uuid,
  replaced_at timestamptz,
  imported_by uuid,
  imported_by_name text not null default '',
  imported_at timestamptz not null default now(),
  check (ship_date = delivery_date - 1)
);
create unique index if not exists ship_actual_imports_v1199c142_active
  on public.ship_actual_imports_v1199c142(delivery_date) where status = 'active';

create table if not exists public.ship_actual_lines_v1199c142(
  id bigint generated always as identity primary key,
  import_id uuid not null references public.ship_actual_imports_v1199c142(id) on delete cascade,
  line_no integer not null,
  delivery_date date not null,
  customer_raw text not null,            -- 産地報告書の書き方
  customer_name text not null,           -- 積み込み表の客先名（読み替え後）
  customer_norm text not null,
  customer_id uuid,                      -- 将来の客先マスタ（社外セット）とつなぐ。今は空
  item_name text not null,
  item_in_master boolean not null default true,
  item_raw text not null,
  origin text not null default '',
  coop text not null default '',
  qty_raw text not null default '',
  boxes numeric,
  pack_kg numeric,
  kg numeric check (kg is null or kg >= 0),
  case_std_kg numeric,
  cases_exact numeric,
  cases integer,
  has_fraction boolean not null default false,
  note text not null default '',
  source_sheet text not null default '',
  source_cell text not null default '',
  unique (import_id, line_no)
);
create index if not exists ship_actual_lines_v1199c142_import on public.ship_actual_lines_v1199c142(import_id);
create index if not exists ship_actual_lines_v1199c142_date on public.ship_actual_lines_v1199c142(delivery_date, item_name);

create table if not exists public.ship_customer_aliases_v1199c142(
  raw_key text primary key,
  raw_name text not null,
  customer_name text not null,
  updated_by_name text not null default '',
  updated_at timestamptz not null default now()
);

-- 産地報告書の書き方（品名）の初期登録：「剝きレタス」（剝の字・順番が積み込み表と違う）→ レタス
insert into public.ship_plan_item_aliases_v1199c140(raw_key, raw_name, item_name, in_master, updated_by_name) values
  ('剝きレタス','剝きレタス','レタス',true,'初期値'),
  ('剥きレタス','剥きレタス','レタス',true,'初期値')
on conflict (raw_key) do nothing;

do $block$
declare t text;
begin
  foreach t in array array['ship_actual_imports_v1199c142','ship_actual_lines_v1199c142','ship_customer_aliases_v1199c142'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('drop policy if exists %I on public.%I', t||'_read', t);
    execute format($p$create policy %I on public.%I for select to authenticated using (public.has_any_role(array['admin','worker','buyer','sales','clerk','office_viewer','viewer']))$p$, t||'_read', t);
  end loop;
end $block$;

create or replace function public.replace_ship_actual_v1199c142(p_import_id uuid, p_delivery_date date, p_file text, p_sheets jsonb, p_lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $f$
declare
  v_name text; v_old uuid; r jsonb; v_no integer := 0;
  v_item text; v_cust text; v_kg numeric; v_std numeric; v_pack numeric; v_exact numeric; v_cases integer; v_total numeric := 0;
begin
  perform public.seika_require_role_v1240(array['admin','worker','clerk']);
  if p_import_id is null or p_delivery_date is null then raise exception '納品日がありません' using errcode = '22023'; end if;
  if exists (select 1 from public.ship_actual_imports_v1199c142 where id = p_import_id) then
    return jsonb_build_object('ok', true, 'id', p_import_id, 'again', true,
      'count', (select line_count from public.ship_actual_imports_v1199c142 where id = p_import_id));
  end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception '登録する行がありません' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtext('ship_actual_v1199c142:' || p_delivery_date::text));
  select coalesce(nullif(btrim(display_name),''),'') into v_name from public.profiles where id = auth.uid();
  select id into v_old from public.ship_actual_imports_v1199c142 where delivery_date = p_delivery_date and status = 'active';
  if v_old is not null then
    update public.ship_actual_imports_v1199c142 set status = 'replaced', replaced_at = now() where id = v_old;
  end if;
  insert into public.ship_actual_imports_v1199c142(id, delivery_date, ship_date, file_name, sheets, imported_by, imported_by_name)
  values (p_import_id, p_delivery_date, p_delivery_date - 1, coalesce(p_file,''), coalesce(p_sheets,'[]'::jsonb), auth.uid(), coalesce(v_name,''));

  for r in select value from jsonb_array_elements(p_lines) loop
    v_no := v_no + 1;
    v_cust := btrim(coalesce(r->>'customer_name',''));
    v_item := btrim(coalesce(r->>'item_name',''));
    if v_cust = '' then raise exception '%行目：客先がありません', v_no using errcode = '22023'; end if;
    if v_item = '' then raise exception '%行目：品目がありません（要確認の行が残っています）', v_no using errcode = '22023'; end if;
    begin
      v_kg := nullif(r->>'kg','')::numeric;
      v_pack := nullif(r->>'pack_kg','')::numeric;
    exception when others then raise exception '%行目：数量が数字ではありません', v_no using errcode = '22023';
    end;
    if v_kg is not null and v_kg < 0 then raise exception '%行目：数量がマイナスです', v_no using errcode = '22023'; end if;
    select case_kg into v_std from public.ship_plan_case_std_v1199c140 where item_name = v_item;
    v_std := coalesce(v_std, nullif(v_pack, 0));
    if v_kg is not null and v_std is not null and v_std > 0 then
      v_exact := round(v_kg / v_std, 4); v_cases := ceil(v_exact - 0.00001)::integer;
    else
      v_exact := null; v_cases := null;
    end if;
    insert into public.ship_actual_lines_v1199c142(import_id, line_no, delivery_date, customer_raw, customer_name, customer_norm,
      item_name, item_in_master, item_raw, origin, coop, qty_raw, boxes, pack_kg, kg, case_std_kg, cases_exact, cases, has_fraction,
      note, source_sheet, source_cell)
    values (p_import_id, v_no, p_delivery_date, btrim(coalesce(r->>'customer_raw', v_cust)), v_cust,
      coalesce(nullif(btrim(r->>'customer_norm'),''), v_cust),
      v_item, coalesce((r->>'item_in_master')::boolean, true), btrim(coalesce(r->>'item_raw', v_item)),
      btrim(coalesce(r->>'origin','')), btrim(coalesce(r->>'coop','')), coalesce(r->>'qty_raw',''),
      nullif(r->>'boxes','')::numeric, v_pack, v_kg, v_std, v_exact, v_cases,
      coalesce(v_exact is not null and v_exact <> v_cases, false),
      btrim(coalesce(r->>'note','')), coalesce(r->>'source_sheet',''), coalesce(r->>'source_cell',''));
    v_total := v_total + coalesce(v_kg, 0);
  end loop;

  update public.ship_actual_imports_v1199c142 set line_count = v_no, total_kg = v_total where id = p_import_id;
  if v_old is not null then
    update public.ship_actual_imports_v1199c142 set replaced_by = p_import_id where id = v_old;
  end if;
  return jsonb_build_object('ok', true, 'id', p_import_id, 'count', v_no, 'replaced', v_old is not null);
end
$f$;

create or replace function public.save_ship_customer_alias_v1199c142(p_key text, p_raw text, p_customer text)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $f$
declare v_name text;
begin
  perform public.seika_require_role_v1240(array['admin','worker','clerk']);
  if btrim(coalesce(p_key,'')) = '' or btrim(coalesce(p_customer,'')) = '' then
    raise exception '客先名は必須です' using errcode = '22023';
  end if;
  select coalesce(display_name,'') into v_name from public.profiles where id = auth.uid();
  insert into public.ship_customer_aliases_v1199c142(raw_key, raw_name, customer_name, updated_by_name, updated_at)
  values (btrim(p_key), btrim(coalesce(p_raw, p_key)), btrim(p_customer), coalesce(v_name,''), now())
  on conflict (raw_key) do update set raw_name = excluded.raw_name, customer_name = excluded.customer_name,
    updated_by_name = excluded.updated_by_name, updated_at = now();
  return jsonb_build_object('ok', true);
end
$f$;

create or replace function public.delete_ship_customer_alias_v1199c142(p_key text)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $f$
begin
  perform public.seika_require_role_v1240(array['admin']);
  delete from public.ship_customer_aliases_v1199c142 where raw_key = btrim(coalesce(p_key,''));
  return jsonb_build_object('ok', true);
end
$f$;

do $block$
declare f text;
begin
  foreach f in array array['public.replace_ship_actual_v1199c142(uuid,date,text,jsonb,jsonb)','public.save_ship_customer_alias_v1199c142(text,text,text)',
                           'public.delete_ship_customer_alias_v1199c142(text)'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $block$;

commit;

-- ===== 確認（1行で、どちらも OK なら成功） =====
select
  (select case when count(*) = 3 then 'OK' else 'NG' end from pg_class
    where relname in ('ship_actual_imports_v1199c142','ship_actual_lines_v1199c142','ship_customer_aliases_v1199c142') and relrowsecurity) as "確定数量の表",
  (select case when count(*) = 3 then 'OK' else 'NG' end from pg_proc
    where proname in ('replace_ship_actual_v1199c142','save_ship_customer_alias_v1199c142','delete_ship_customer_alias_v1199c142')) as "確定数量の関数";
