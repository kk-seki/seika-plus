-- 010_仕入先・単協名の候補を共有.sql
-- 目的：QR入庫の「仕入先」「単協名」の候補（追加・非表示・削除・名称修正）を専用の表で管理し、
--       全員の端末に同じ内容が反映されるようにする。
-- ・これまで端末側の設定に保存していた「追加した名称」「非表示にした名称」は、この表へ引き継ぎます。
-- ・削除しても過去のQRロットや履歴の記録は消えません（候補に出なくなるだけです）。
-- ・何度実行しても同じ結果になります。
begin;

create table if not exists public.qr_party_names_v1280(
  kind text not null check (kind in ('supplier','cooperative')),
  norm text not null,
  name text not null,
  status text not null default 'active' check (status in ('active','hidden','deleted')),
  renamed_to text,
  updated_by uuid,
  updated_by_name text not null default '',
  updated_at timestamptz not null default now(),
  primary key (kind, norm)
);
alter table public.qr_party_names_v1280 enable row level security;
revoke all on public.qr_party_names_v1280 from public, anon, authenticated;
grant select on public.qr_party_names_v1280 to authenticated;
grant all on public.qr_party_names_v1280 to service_role;
drop policy if exists qr_party_names_v1280_read on public.qr_party_names_v1280;
create policy qr_party_names_v1280_read on public.qr_party_names_v1280 for select to authenticated using (true);

create or replace function public.seika_party_norm_v1280(p text)
returns text language sql immutable set search_path to 'pg_catalog' as $f$
  select regexp_replace(replace(replace(coalesce(p,''),'（','('),'）',')'),'\s+','','g')
$f$;

create or replace function public.set_qr_party_name_v1280(p_kind text, p_name text, p_status text, p_renamed_to text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public'
as $f$
declare
  v_profile public.profiles%rowtype;
  v_name text := btrim(coalesce(p_name,''));
  v_new text := nullif(btrim(coalesce(p_renamed_to,'')),'');
  v_norm text;
begin
  perform public.seika_require_role_v1240(array['admin','worker']);
  select * into v_profile from public.profiles where id = auth.uid() and active limit 1;
  if v_profile.id is null then raise exception 'ログインが必要です' using errcode = '42501'; end if;
  if p_kind not in ('supplier','cooperative') then raise exception '種類が正しくありません' using errcode = '22023'; end if;
  if p_status not in ('active','hidden','deleted') then raise exception '状態が正しくありません' using errcode = '22023'; end if;
  v_norm := public.seika_party_norm_v1280(v_name);
  if v_norm = '' then return jsonb_build_object('ok', false, 'message', '名称が空です'); end if;

  insert into public.qr_party_names_v1280(kind, norm, name, status, renamed_to, updated_by, updated_by_name, updated_at)
  values (p_kind, v_norm, v_name, p_status, v_new, v_profile.id, coalesce(v_profile.display_name,''), now())
  on conflict (kind, norm) do update set
    name = case when excluded.status = 'active' then excluded.name else public.qr_party_names_v1280.name end,
    status = excluded.status, renamed_to = excluded.renamed_to,
    updated_by = excluded.updated_by, updated_by_name = excluded.updated_by_name, updated_at = now();

  if v_new is not null and public.seika_party_norm_v1280(v_new) <> v_norm then
    insert into public.qr_party_names_v1280(kind, norm, name, status, updated_by, updated_by_name, updated_at)
    values (p_kind, public.seika_party_norm_v1280(v_new), v_new, 'active', v_profile.id, coalesce(v_profile.display_name,''), now())
    on conflict (kind, norm) do update set name = excluded.name, status = 'active', renamed_to = null,
      updated_by = excluded.updated_by, updated_by_name = excluded.updated_by_name, updated_at = now();
  end if;
  return jsonb_build_object('ok', true);
end
$f$;
revoke all on function public.set_qr_party_name_v1280(text, text, text, text) from public, anon;
grant execute on function public.set_qr_party_name_v1280(text, text, text, text) to authenticated, service_role;

-- これまでの端末設定（app_state）から、追加・非表示にした名称を引き継ぐ（既に表にあるものは変えない）
insert into public.qr_party_names_v1280(kind, norm, name, status, updated_by_name)
select distinct on (k, public.seika_party_norm_v1280(v)) k, public.seika_party_norm_v1280(v), btrim(v), st, '引き継ぎ'
from (
  select 'supplier' k, jsonb_array_elements_text(coalesce(s.data->'qrSupplierHidden','[]'::jsonb)) v, 'hidden' st, 1 pri from public.app_state s
  union all select 'cooperative', jsonb_array_elements_text(coalesce(s.data->'qrCooperativeHidden','[]'::jsonb)), 'hidden', 1 from public.app_state s
  union all select 'supplier', jsonb_array_elements_text(coalesce(s.data->'qrSuppliers','[]'::jsonb)), 'active', 2 from public.app_state s
  union all select 'cooperative', jsonb_array_elements_text(coalesce(s.data->'qrCooperatives','[]'::jsonb)), 'active', 2 from public.app_state s
) x
where public.seika_party_norm_v1280(v) <> ''
order by k, public.seika_party_norm_v1280(v), pri
on conflict (kind, norm) do nothing;

commit;

-- 確認：3行とも「OK」なら成功です（件数は参考）
select '候補の表' as 確認項目, case when to_regclass('public.qr_party_names_v1280') is not null then 'OK' else '要確認' end as 判定, '' as 件数
union all select '候補の保存', case when exists (select 1 from pg_proc where proname = 'set_qr_party_name_v1280') then 'OK' else '要確認' end, ''
union all select '引き継ぎ', 'OK', (select '候補 ' || count(*) filter (where status='active') || '件／非表示 ' || count(*) filter (where status='hidden') || '件' from public.qr_party_names_v1280);
