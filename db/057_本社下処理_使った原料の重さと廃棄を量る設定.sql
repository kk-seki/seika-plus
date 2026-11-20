/*
057_本社下処理_使った原料の重さと廃棄を量る設定.sql（v1.199-c136）

目的（方針：仕様/本社下処理_使用原料と廃棄の見直し_方針_2026-11-20、11/20 平田さんの決定で変更）：
  使った原料のkgを「箱の数 × 量目」ではなく、下処理の日報で量って入れた重さ（合計kg）にする。
  在庫は今までどおり箱の数で引く（開けた箱は1箱として引き、次に使うときは数えない）。
  1. hq_works_v1500.used_kg：日報で入れた「使った原料の重さ（合計kg）」。
  2. hq_prep_report_save_v1199c136：日報の保存。ケースの原料があるときは used_kg が必須。
     1箱あたりkg＝（使った原料の重さ − kgの原料の合計）÷ 箱の数 を、この保存の間だけ
     hq_c117_lot_pack_kg が返すようにし、今までの保存（v1199c120）をそのまま呼ぶ。
     → 原料の記録（pack_kg）・使用原料kg・廃棄の自動計算・チェックが、量った重さにそろう。
  3. hq_work_materials_v1500.kg_basis：使った原料のkgが「実測」か「推定」か。
  4. hq_item_rules_v1600.waste_measured：廃棄を量る品目か（初期値は量る）。
     キャベツ・白菜・紫キャベツは「量らない」。紫キャベツは品目ルールに追加（期限なし）。
  5. hq_works_v1500.waste_basis：廃棄が「実測」か「推定」か（廃棄kgを保存したときに品目の設定から付ける）。
  6. hq_set_waste_measured_v1199c136：廃棄を量る／量らないの切り替え（管理者・本社社員）。

過去の下処理の記録・数字は直しません（kg_basis・waste_basis・used_kg は空のまま＝画面では「推定」）。
何度実行しても同じ結果になります。
*/
begin;

-- ===== 1. 列の追加 =====
alter table public.hq_works_v1500 add column if not exists used_kg numeric;
alter table public.hq_works_v1500 drop constraint if exists hq_works_used_kg_check;
alter table public.hq_works_v1500 add constraint hq_works_used_kg_check check (used_kg is null or used_kg > 0);

alter table public.hq_work_materials_v1500 add column if not exists kg_basis text;
alter table public.hq_work_materials_v1500 drop constraint if exists hq_work_materials_kg_basis_check;
alter table public.hq_work_materials_v1500 add constraint hq_work_materials_kg_basis_check check (kg_basis is null or kg_basis in ('実測','推定'));

alter table public.hq_works_v1500 add column if not exists waste_basis text;
alter table public.hq_works_v1500 drop constraint if exists hq_works_waste_basis_check;
alter table public.hq_works_v1500 add constraint hq_works_waste_basis_check check (waste_basis is null or waste_basis in ('実測','推定'));

alter table public.hq_item_rules_v1600 add column if not exists waste_measured boolean not null default true;

-- ===== 2. 初期設定：キャベツ・白菜・紫キャベツは廃棄を量らない =====
insert into public.hq_item_rules_v1600(item_name, limit_days, ng_sign, aliases, sort_order, updated_by_name)
select '紫キャベツ', null, null, array['紫きゃべつ','むらさきキャベツ','レッドキャベツ'],
       coalesce((select max(sort_order) from public.hq_item_rules_v1600), 0) + 1, 'SQL 057'
where not exists (select 1 from public.hq_item_rules_v1600 where item_name = '紫キャベツ');
update public.hq_item_rules_v1600 set waste_measured = false
 where item_name in ('キャベツ','白菜','紫キャベツ') and waste_measured;

-- ===== 3. 品目名 → 廃棄を量るか（画面の hqItemRuleOf と同じ順で照合。見つからなければ量る） =====
create or replace function public.hq_waste_measured_v1199c136(p_item text)
returns boolean
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  raw text := btrim(coalesce(p_item, ''));
  plain text;
  r public.hq_item_rules_v1600%rowtype;
begin
  if raw = '' then return true; end if;
  plain := btrim(regexp_replace(raw, '[（(][^）)]*[）)]', '', 'g'));
  select * into r from public.hq_item_rules_v1600
   where lower(item_name) in (lower(raw), lower(plain)) limit 1;
  if found then return r.waste_measured; end if;
  select * into r from public.hq_item_rules_v1600
   where exists (select 1 from unnest(aliases) a where lower(a) in (lower(raw), lower(plain))) limit 1;
  if found then return r.waste_measured; end if;
  if raw ~ '(皮むき|カット)' then return true; end if;
  select x.* into r from (
    select t.*, k from public.hq_item_rules_v1600 t, unnest(array[t.item_name] || t.aliases) k
  ) x
  where length(x.k) > 0 and position(lower(x.k) in lower(plain)) > 0
  order by length(x.k) desc limit 1;
  if found then return r.waste_measured; end if;
  return true;
end $function$;

-- ===== 4. 1箱あたりkg：日報の保存中は「量った重さ」から出した値、それ以外は今までどおり量目 =====
create or replace function public.hq_c117_lot_pack_kg(p_lot public.hq_lots_v1400)
returns numeric
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare v_total numeric; v_pack numeric; v_set text := coalesce(current_setting('seika.c136_case_kg', true), '');
begin
  if p_lot.unit = 'kg' then return null; end if;
  if v_set <> '' then return v_set::numeric; end if;
  v_pack := public.hq_pack_kg_v1500(p_lot.pack_weight);
  if v_pack is not null and v_pack > 0 then return v_pack; end if;
  begin v_total := nullif(to_jsonb(p_lot)->>'total_weight','')::numeric; exception when others then v_total := null; end;
  if v_total is not null and v_total > 0 and coalesce(p_lot.received_qty,0) > 0 then return v_total / p_lot.received_qty; end if;
  return null;
end $function$;

-- ===== 5. 原料の記録：実測／推定 =====
create or replace function public.hq_c136_material_kg_trigger()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if new.unit = 'kg' then
    new.kg_basis := '実測';
  elsif coalesce(current_setting('seika.c136_case_kg', true), '') <> '' then
    new.kg_basis := '実測';
  elsif tg_op = 'INSERT' then
    new.kg_basis := '推定';
  end if;
  return new;
end $function$;

drop trigger if exists hq_c136_material_kg on public.hq_work_materials_v1500;
create trigger hq_c136_material_kg
  before insert or update of lot_id, unit, pack_kg, qty on public.hq_work_materials_v1500
  for each row execute function public.hq_c136_material_kg_trigger();

-- ===== 6. 下処理：使った原料の重さと、廃棄の実測／推定 =====
create or replace function public.hq_c136_waste_basis_trigger()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare v_used text := coalesce(current_setting('seika.c136_used_kg', true), '');
begin
  if new.kind is distinct from '下処理' then return new; end if;
  if v_used <> '' then new.used_kg := v_used::numeric; end if;
  if new.waste_kg is null then
    new.waste_basis := null;
  elsif tg_op = 'INSERT' or new.waste_kg is distinct from old.waste_kg or new.raw_item_name is distinct from old.raw_item_name then
    new.waste_basis := case when public.hq_waste_measured_v1199c136(new.raw_item_name) then '実測' else '推定' end;
  end if;
  return new;
end $function$;

drop trigger if exists hq_c136_waste_basis on public.hq_works_v1500;
create trigger hq_c136_waste_basis
  before insert or update on public.hq_works_v1500
  for each row execute function public.hq_c136_waste_basis_trigger();

-- ===== 7. 日報の保存（使った原料の重さ付き） =====
create or replace function public.hq_prep_report_save_v1199c136(p_work_id uuid, p_operation_id uuid, p_expected_updated_at timestamptz, p_report jsonb)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_used numeric; v_kg numeric := 0; v_cases numeric := 0; v_has_case boolean := false; v_case_kg numeric; r jsonb;
begin
  begin v_used := nullif(btrim(coalesce(p_report->>'used_kg','')), '')::numeric;
  exception when others then raise exception '使った原料の重さ（kg）を数字で入れてください'; end;
  select coalesce(sum(case when l.unit = 'kg' then (m->>'qty')::numeric else 0 end), 0),
         coalesce(sum(case when l.unit <> 'kg' then (m->>'qty')::numeric else 0 end), 0),
         coalesce(bool_or(l.unit <> 'kg'), false)
    into v_kg, v_cases, v_has_case
    from jsonb_array_elements(coalesce(p_report->'materials', '[]'::jsonb)) m
    join public.hq_lots_v1400 l on l.id = nullif(m->>'lot_id','')::uuid;
  if v_has_case then
    if v_used is null or v_used <= 0 then raise exception '使った原料の重さ（kg）を量って入れてください'; end if;
    if v_cases <= 0 then raise exception '使った箱の数を入れてください'; end if;
    if v_used <= v_kg then raise exception '使った原料の重さが、kgの原料の合計より少なくなっています'; end if;
    v_case_kg := ceil((v_used - v_kg) / v_cases * 1000000) / 1000000;
    perform set_config('seika.c136_case_kg', v_case_kg::text, true);
    perform set_config('seika.c136_used_kg', v_used::text, true);
  else
    perform set_config('seika.c136_case_kg', '', true);
    perform set_config('seika.c136_used_kg', case when v_kg > 0 then v_kg::text else '' end, true);
  end if;
  r := public.hq_prep_report_save_v1199c120(p_work_id, p_operation_id, p_expected_updated_at, p_report - 'used_kg');
  perform set_config('seika.c136_case_kg', '', true);
  perform set_config('seika.c136_used_kg', '', true);
  return r;
end $function$;

revoke all on function public.hq_prep_report_save_v1199c136(uuid, uuid, timestamptz, jsonb) from public, anon;
grant execute on function public.hq_prep_report_save_v1199c136(uuid, uuid, timestamptz, jsonb) to authenticated, service_role;

-- ===== 8. 廃棄を量る／量らないの切り替え（管理者・本社社員） =====
create or replace function public.hq_set_waste_measured_v1199c136(p_item_name text, p_measured boolean)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare v public.profiles;
begin
  v := public.hq_actor_v1400(array['admin','hq_worker']);
  if p_measured is null then raise exception '量る／量らないを選んでください'; end if;
  update public.hq_item_rules_v1600 set waste_measured = p_measured, updated_by_name = v.display_name, updated_at = now()
   where item_name = btrim(coalesce(p_item_name, ''));
  if not found then raise exception '品目の設定が見つかりません'; end if;
  return jsonb_build_object('ok', true, 'item_name', btrim(p_item_name), 'waste_measured', p_measured);
end $function$;

revoke all on function public.hq_set_waste_measured_v1199c136(text, boolean) from public, anon;
grant execute on function public.hq_set_waste_measured_v1199c136(text, boolean) to authenticated, service_role;
revoke all on function public.hq_waste_measured_v1199c136(text) from public, anon;
grant execute on function public.hq_waste_measured_v1199c136(text) to authenticated, service_role;

commit;
notify pgrst, 'reload schema';

-- 確認：4行とも「OK」なら成功です
select '列の追加' as 確認項目, case when (select count(*) from information_schema.columns where table_schema='public' and
  ((table_name='hq_works_v1500' and column_name in ('used_kg','waste_basis')) or (table_name='hq_work_materials_v1500' and column_name='kg_basis')
   or (table_name='hq_item_rules_v1600' and column_name='waste_measured'))) = 4 then 'OK' else '要確認' end as 判定
union all
select '量らない品目（キャベツ・白菜・紫キャベツ）', case when (select count(*) from public.hq_item_rules_v1600 where item_name in ('キャベツ','白菜','紫キャベツ') and not waste_measured) = 3
  and not public.hq_waste_measured_v1199c136('紫キャベツ') and not public.hq_waste_measured_v1199c136('きゃべつ') and public.hq_waste_measured_v1199c136('茄子') then 'OK' else '要確認' end
union all
select '関数とトリガー', case when (select count(*) from pg_proc where proname in ('hq_prep_report_save_v1199c136','hq_set_waste_measured_v1199c136','hq_waste_measured_v1199c136','hq_c136_material_kg_trigger','hq_c136_waste_basis_trigger')) = 5
  and (select count(*) from pg_trigger where tgname in ('hq_c136_material_kg','hq_c136_waste_basis') and not tgisinternal) = 2 then 'OK' else '要確認' end
union all
select '過去の記録はそのまま', case when not exists (select 1 from public.hq_works_v1500 where used_kg is not null or waste_basis is not null) then 'OK' else '要確認' end;
