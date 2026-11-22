/*
061_出荷予定の取り込み.sql（v1.199-c140）

目的：
  積み込み表（Excel）から読んだ出荷予定を、客先ごとの数量まで保存する。
  1. 取り込み1回分（ship_plan_imports_v1199c140）と、その明細（ship_plan_lines_v1199c140）
     ・同じ納品日をもう一度取り込んだら、前の取り込みは「置き換え済み」にして残す（消さない）
     ・出荷日＝納品日の前日（月をまたいでも前日）
  2. 品名読み替えマスタ（ship_plan_item_aliases_v1199c140）
     ・積み込み表の書き方 → SEIKA＋の品目。マスタにない品名は推測しない（アプリで「要確認」）
  3. 標準ケースの重さ（ship_plan_case_std_v1199c140）
     ・初期値：キャベツ10kg、葉付き大根15kg、人参15kg、カット大根15kg（現場で入れ替えたあとの入数）
     ・ケース数＝kg ÷ 標準ケース を切り上げ。割り切れないときは「端数あり」

権限：
  ・取り込み・品名読み替えの追加：管理者・青果社員・事務員
  ・品名読み替えの削除・標準ケースの変更：管理者
  ・見る：石岡の役割（管理者・青果社員・仕入れ担当者・営業・事務員・総務（閲覧）・閲覧者）。本社の役割は見られない
  ・表への書き込みは関数だけ（アプリから直接は書けない）

前提：seika_require_role_v1240・has_any_role があること（db/005・db/010 以降）。
SQLを実行しただけでは、在庫・QRロット・伝票は変わりません。
何度実行しても同じ結果になります。

元に戻すとき（この機能を使う前に戻す）：
  drop function if exists public.replace_ship_plan_v1199c140(uuid,date,jsonb,jsonb);
  drop function if exists public.save_ship_plan_alias_v1199c140(text,text,text,boolean);
  drop function if exists public.delete_ship_plan_alias_v1199c140(text);
  drop function if exists public.save_ship_plan_case_std_v1199c140(text,numeric);
  drop table if exists public.ship_plan_lines_v1199c140, public.ship_plan_imports_v1199c140,
    public.ship_plan_item_aliases_v1199c140, public.ship_plan_case_std_v1199c140;
*/
begin;

do $block$
begin
  if to_regprocedure('public.seika_require_role_v1240(text[])') is null
     or to_regprocedure('public.has_any_role(text[])') is null then
    raise exception '先に db/010 までを番号順に実行してください';
  end if;
end $block$;

-- ===== 取り込み1回分 =====
create table if not exists public.ship_plan_imports_v1199c140(
  id uuid primary key,
  delivery_date date not null,
  ship_date date not null,
  status text not null default 'active' check (status in ('active','replaced')),
  files jsonb not null default '[]'::jsonb,
  line_count integer not null default 0,
  total_kg numeric not null default 0,
  replaced_by uuid,
  replaced_at timestamptz,
  imported_by uuid,
  imported_by_name text not null default '',
  imported_at timestamptz not null default now(),
  check (ship_date = delivery_date - 1)
);
create unique index if not exists ship_plan_imports_v1199c140_active
  on public.ship_plan_imports_v1199c140(delivery_date) where status = 'active';
create index if not exists ship_plan_imports_v1199c140_date
  on public.ship_plan_imports_v1199c140(delivery_date, imported_at desc);

-- ===== 明細（1行＝客先×品目） =====
create table if not exists public.ship_plan_lines_v1199c140(
  id bigint generated always as identity primary key,
  import_id uuid not null references public.ship_plan_imports_v1199c140(id) on delete cascade,
  line_no integer not null,
  delivery_date date not null,
  ship_date date not null,
  route text not null default '',
  customer_name text not null,
  customer_norm text not null,
  customer_id uuid,                      -- 将来の客先マスタ（社外セット）とつなぐ。今は空
  item_name text not null,               -- SEIKA＋の品目（マスタにない品目は積み込み表の名前）
  item_in_master boolean not null default true,
  item_raw text not null,                -- 積み込み表の書き方そのまま
  qty_raw text not null default '',
  unit text not null check (unit in ('cs','kg','pc')),
  boxes numeric,
  pack_kg numeric,
  kg numeric check (kg is null or kg >= 0),
  case_std_kg numeric,
  cases_exact numeric,
  cases integer,
  has_fraction boolean not null default false,
  note text not null default '',
  source_file text not null default '',
  source_sheet text not null default '',
  source_row integer,
  source_col text not null default '',
  unique (import_id, line_no)
);
create index if not exists ship_plan_lines_v1199c140_import on public.ship_plan_lines_v1199c140(import_id);
create index if not exists ship_plan_lines_v1199c140_date on public.ship_plan_lines_v1199c140(delivery_date, item_name);

-- ===== 品名読み替えマスタ =====
create table if not exists public.ship_plan_item_aliases_v1199c140(
  raw_key text primary key,              -- アプリで作る照合キー（全角半角・空白・大文字小文字をそろえたもの）
  raw_name text not null,
  item_name text not null,
  in_master boolean not null default true,
  updated_by_name text not null default '',
  updated_at timestamptz not null default now()
);

-- ===== 標準ケースの重さ =====
create table if not exists public.ship_plan_case_std_v1199c140(
  item_name text primary key,
  case_kg numeric not null check (case_kg > 0),
  updated_by_name text not null default '',
  updated_at timestamptz not null default now()
);
insert into public.ship_plan_case_std_v1199c140(item_name, case_kg, updated_by_name) values
  ('キャベツ',10,'初期値'),('葉付き大根',15,'初期値'),('人参',15,'初期値'),('カット大根',15,'初期値')
on conflict (item_name) do nothing;

-- 書き方の違いの初期登録（ほかは取り込みの確認画面で選ぶ）
-- 大根・加工用大根・レタス剥き・カットしめじは 2026-11-22 平田さんの指定
insert into public.ship_plan_item_aliases_v1199c140(raw_key, raw_name, item_name, in_master, updated_by_name) values
  ('gリーフ','Gリーフ','グリーンリーフ',true,'初期値'),
  ('葉付大根','葉付大根','葉付き大根',true,'初期値'),
  ('長ねぎ','長ねぎ','長葱',true,'初期値'),
  ('大根','大根','カット大根',true,'初期値'),
  ('加工用大根','加工用大根','カット大根',true,'初期値'),
  ('レタス剥き','レタス剥き','レタス',true,'初期値'),
  ('カットしめじ','カットしめじ','しめじ',true,'初期値')
on conflict (raw_key) do nothing;

-- ===== 見る権限（石岡の役割だけ）・書き込みは関数だけ =====
do $block$
declare t text;
begin
  foreach t in array array['ship_plan_imports_v1199c140','ship_plan_lines_v1199c140','ship_plan_item_aliases_v1199c140','ship_plan_case_std_v1199c140'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('drop policy if exists %I on public.%I', t||'_read', t);
    execute format($p$create policy %I on public.%I for select to authenticated using (public.has_any_role(array['admin','worker','buyer','sales','clerk','office_viewer','viewer']))$p$, t||'_read', t);
  end loop;
end $block$;

-- ===== 取り込み（同じ納品日は置き換え・前の分は残す） =====
create or replace function public.replace_ship_plan_v1199c140(p_import_id uuid, p_delivery_date date, p_files jsonb, p_lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $f$
declare
  v_name text;
  v_old uuid;
  r jsonb;
  v_no integer := 0;
  v_item text; v_cust text; v_unit text; v_kg numeric; v_std numeric; v_pack numeric; v_exact numeric; v_cases integer;
  v_total numeric := 0;
begin
  perform public.seika_require_role_v1240(array['admin','worker','clerk']);
  if p_import_id is null or p_delivery_date is null then raise exception '納品日がありません' using errcode = '22023'; end if;
  -- 二重押し・再送：同じ取り込みIDは1回だけ
  if exists (select 1 from public.ship_plan_imports_v1199c140 where id = p_import_id) then
    return jsonb_build_object('ok', true, 'id', p_import_id, 'again', true,
      'count', (select line_count from public.ship_plan_imports_v1199c140 where id = p_import_id));
  end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception '登録する行がありません' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtext('ship_plan_v1199c140:' || p_delivery_date::text));
  select coalesce(nullif(btrim(display_name),''),'') into v_name from public.profiles where id = auth.uid();

  select id into v_old from public.ship_plan_imports_v1199c140 where delivery_date = p_delivery_date and status = 'active';
  if v_old is not null then
    update public.ship_plan_imports_v1199c140 set status = 'replaced', replaced_at = now() where id = v_old;
  end if;
  insert into public.ship_plan_imports_v1199c140(id, delivery_date, ship_date, files, imported_by, imported_by_name)
  values (p_import_id, p_delivery_date, p_delivery_date - 1, coalesce(p_files, '[]'::jsonb), auth.uid(), coalesce(v_name,''));

  for r in select value from jsonb_array_elements(p_lines) loop
    v_no := v_no + 1;
    v_cust := btrim(coalesce(r->>'customer_name',''));
    v_item := btrim(coalesce(r->>'item_name',''));
    v_unit := coalesce(r->>'unit','');
    if v_cust = '' then raise exception '%行目：客先がありません', v_no using errcode = '22023'; end if;
    if v_item = '' then raise exception '%行目：品目がありません（要確認の行が残っています）', v_no using errcode = '22023'; end if;
    if v_unit not in ('cs','kg','pc') then raise exception '%行目：単位が正しくありません', v_no using errcode = '22023'; end if;
    begin
      v_kg := nullif(r->>'kg','')::numeric;
      v_pack := nullif(r->>'pack_kg','')::numeric;
    exception when others then raise exception '%行目：数量が数字ではありません', v_no using errcode = '22023';
    end;
    if v_kg is not null and v_kg < 0 then raise exception '%行目：数量がマイナスです', v_no using errcode = '22023'; end if;
    -- ケース数：標準ケース（マスタ）→ なければ積み込み表の1箱の重さ。切り上げ
    select case_kg into v_std from public.ship_plan_case_std_v1199c140 where item_name = v_item;
    v_std := coalesce(v_std, nullif(v_pack, 0));
    if v_kg is not null and v_std is not null and v_std > 0 then
      v_exact := round(v_kg / v_std, 4);
      v_cases := ceil(v_exact - 0.00001)::integer;
    else
      v_exact := null; v_cases := null;
    end if;
    insert into public.ship_plan_lines_v1199c140(import_id, line_no, delivery_date, ship_date, route, customer_name, customer_norm,
      item_name, item_in_master, item_raw, qty_raw, unit, boxes, pack_kg, kg, case_std_kg, cases_exact, cases, has_fraction,
      note, source_file, source_sheet, source_row, source_col)
    values (p_import_id, v_no, p_delivery_date, p_delivery_date - 1, btrim(coalesce(r->>'route','')), v_cust,
      coalesce(nullif(btrim(r->>'customer_norm'),''), v_cust),
      v_item, coalesce((r->>'item_in_master')::boolean, true), btrim(coalesce(r->>'item_raw', v_item)), coalesce(r->>'qty_raw',''), v_unit,
      nullif(r->>'boxes','')::numeric, v_pack, v_kg, v_std, v_exact, v_cases,
      coalesce(v_exact is not null and v_exact <> v_cases, false),
      btrim(coalesce(r->>'note','')), coalesce(r->>'source_file',''), coalesce(r->>'source_sheet',''),
      nullif(r->>'source_row','')::integer, coalesce(r->>'source_col',''));
    v_total := v_total + coalesce(v_kg, 0);
  end loop;

  update public.ship_plan_imports_v1199c140 set line_count = v_no, total_kg = v_total where id = p_import_id;
  if v_old is not null then
    update public.ship_plan_imports_v1199c140 set replaced_by = p_import_id where id = v_old;
  end if;
  return jsonb_build_object('ok', true, 'id', p_import_id, 'count', v_no, 'replaced', v_old is not null);
end
$f$;

-- ===== 品名読み替え：追加・変更（取り込む人）、削除（管理者） =====
create or replace function public.save_ship_plan_alias_v1199c140(p_key text, p_raw text, p_item text, p_in_master boolean)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $f$
declare v_name text;
begin
  perform public.seika_require_role_v1240(array['admin','worker','clerk']);
  if btrim(coalesce(p_key,'')) = '' or btrim(coalesce(p_item,'')) = '' then
    raise exception '品名と品目は必須です' using errcode = '22023';
  end if;
  select coalesce(display_name,'') into v_name from public.profiles where id = auth.uid();
  insert into public.ship_plan_item_aliases_v1199c140(raw_key, raw_name, item_name, in_master, updated_by_name, updated_at)
  values (btrim(p_key), btrim(coalesce(p_raw, p_key)), btrim(p_item), coalesce(p_in_master, true), coalesce(v_name,''), now())
  on conflict (raw_key) do update set raw_name = excluded.raw_name, item_name = excluded.item_name,
    in_master = excluded.in_master, updated_by_name = excluded.updated_by_name, updated_at = now();
  return jsonb_build_object('ok', true);
end
$f$;

create or replace function public.delete_ship_plan_alias_v1199c140(p_key text)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $f$
begin
  perform public.seika_require_role_v1240(array['admin']);
  delete from public.ship_plan_item_aliases_v1199c140 where raw_key = btrim(coalesce(p_key,''));
  return jsonb_build_object('ok', true);
end
$f$;

-- ===== 標準ケースの重さ（管理者）。p_kg が空なら消す =====
create or replace function public.save_ship_plan_case_std_v1199c140(p_item text, p_kg numeric)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $f$
declare v_name text;
begin
  perform public.seika_require_role_v1240(array['admin']);
  if btrim(coalesce(p_item,'')) = '' then raise exception '品目は必須です' using errcode = '22023'; end if;
  if p_kg is null then
    delete from public.ship_plan_case_std_v1199c140 where item_name = btrim(p_item);
    return jsonb_build_object('ok', true, 'deleted', true);
  end if;
  if p_kg <= 0 then raise exception '重さは0より大きくしてください' using errcode = '22023'; end if;
  select coalesce(display_name,'') into v_name from public.profiles where id = auth.uid();
  insert into public.ship_plan_case_std_v1199c140(item_name, case_kg, updated_by_name, updated_at)
  values (btrim(p_item), p_kg, coalesce(v_name,''), now())
  on conflict (item_name) do update set case_kg = excluded.case_kg, updated_by_name = excluded.updated_by_name, updated_at = now();
  return jsonb_build_object('ok', true);
end
$f$;

do $block$
declare f text;
begin
  foreach f in array array['public.replace_ship_plan_v1199c140(uuid,date,jsonb,jsonb)','public.save_ship_plan_alias_v1199c140(text,text,text,boolean)',
                           'public.delete_ship_plan_alias_v1199c140(text)','public.save_ship_plan_case_std_v1199c140(text,numeric)'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $block$;

commit;

-- ===== 確認（どちらも OK なら成功） =====
select case when count(*) = 4 then 'OK' else 'NG' end as "出荷予定の表"
  from pg_class where relname in ('ship_plan_imports_v1199c140','ship_plan_lines_v1199c140','ship_plan_item_aliases_v1199c140','ship_plan_case_std_v1199c140') and relrowsecurity;
select case when count(*) = 4 then 'OK' else 'NG' end as "出荷予定の関数"
  from pg_proc where proname in ('replace_ship_plan_v1199c140','save_ship_plan_alias_v1199c140','delete_ship_plan_alias_v1199c140','save_ship_plan_case_std_v1199c140');
