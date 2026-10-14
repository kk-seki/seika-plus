-- 012_保管目安の特別期間.sql
-- 目的：
--   ・品目ごとに「◯月◯日〜◯月◯日は保管目安◯日」という特別期間を登録できるようにする（毎年くり返す）。
--   ・特別期間に当てはまるかは、ロットの「入荷日」で決める。
--   ・保管目安と特別期間を変更できる人を、管理者・青果社員・仕入れ担当者にする。
-- 前提：007・008 を実行済みであること。
-- 何度実行しても同じ結果になります。登録済みの保管目安・特別期間は消えません。
begin;

create table if not exists public.qr_storage_limit_seasons_v1300(
  id uuid primary key default gen_random_uuid(),
  item_name text not null check (btrim(item_name) <> ''),
  start_md text not null check (start_md ~ '^(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$'),
  end_md text not null check (end_md ~ '^(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$'),
  limit_days integer not null check (limit_days between 1 and 365),
  note text not null default '' check (char_length(note) <= 200),
  updated_by text not null default '',
  updated_by_name text not null default '',
  updated_at timestamptz not null default now()
);
alter table public.qr_storage_limit_seasons_v1300 enable row level security;
revoke all on public.qr_storage_limit_seasons_v1300 from public, anon, authenticated;
grant select on public.qr_storage_limit_seasons_v1300 to authenticated;
grant all on public.qr_storage_limit_seasons_v1300 to service_role;
drop policy if exists qr_storage_limit_seasons_v1300_read on public.qr_storage_limit_seasons_v1300;
create policy qr_storage_limit_seasons_v1300_read on public.qr_storage_limit_seasons_v1300
  for select to authenticated using (true);

create or replace function public.seika_valid_md_v1300(p_md text)
returns boolean
language sql
immutable
set search_path to 'pg_catalog'
as $f$
  select p_md ~ '^(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$'
     and (('2024-' || p_md)::date is not null)
$f$;

create or replace function public.save_qr_storage_season_v1300(
  p_id uuid, p_item_name text, p_start_md text, p_end_md text, p_limit_days integer, p_note text default '')
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public'
as $f$
declare
  v_profile public.profiles%rowtype;
  v_name text := btrim(coalesce(p_item_name, ''));
  v_id uuid;
begin
  perform public.seika_require_role_v1240(array['admin','worker','buyer']);
  select * into v_profile from public.profiles where id = auth.uid() and active limit 1;
  if v_profile.id is null then
    raise exception 'ログインが必要です' using errcode = '42501';
  end if;
  if v_name = '' then
    return jsonb_build_object('ok', false, 'message', '品目を選んでください');
  end if;
  begin
    if not public.seika_valid_md_v1300(p_start_md) or not public.seika_valid_md_v1300(p_end_md) then
      return jsonb_build_object('ok', false, 'message', '期間の日付を確認してください');
    end if;
  exception when others then
    return jsonb_build_object('ok', false, 'message', '期間の日付を確認してください');
  end;
  if p_limit_days is null or p_limit_days < 1 or p_limit_days > 365 then
    return jsonb_build_object('ok', false, 'message', '日数は1〜365の整数で入力してください');
  end if;
  if p_id is not null then
    update public.qr_storage_limit_seasons_v1300
       set item_name = v_name, start_md = p_start_md, end_md = p_end_md, limit_days = p_limit_days,
           note = left(coalesce(p_note, ''), 200),
           updated_by = coalesce(v_profile.legacy_user_id, ''), updated_by_name = coalesce(v_profile.display_name, ''), updated_at = now()
     where id = p_id
     returning id into v_id;
    if v_id is null then
      return jsonb_build_object('ok', false, 'message', '特別期間が見つかりません。画面を開き直してください');
    end if;
  else
    insert into public.qr_storage_limit_seasons_v1300(item_name, start_md, end_md, limit_days, note, updated_by, updated_by_name)
    values (v_name, p_start_md, p_end_md, p_limit_days, left(coalesce(p_note, ''), 200),
            coalesce(v_profile.legacy_user_id, ''), coalesce(v_profile.display_name, ''))
    returning id into v_id;
  end if;
  return jsonb_build_object('ok', true, 'id', v_id);
end
$f$;

create or replace function public.delete_qr_storage_season_v1300(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public'
as $f$
begin
  perform public.seika_require_role_v1240(array['admin','worker','buyer']);
  if not exists (select 1 from public.profiles where id = auth.uid() and active) then
    raise exception 'ログインが必要です' using errcode = '42501';
  end if;
  delete from public.qr_storage_limit_seasons_v1300 where id = p_id;
  return jsonb_build_object('ok', found);
end
$f$;

revoke all on function public.seika_valid_md_v1300(text) from public, anon;
revoke all on function public.save_qr_storage_season_v1300(uuid, text, text, text, integer, text) from public, anon;
revoke all on function public.delete_qr_storage_season_v1300(uuid) from public, anon;
grant execute on function public.seika_valid_md_v1300(text) to authenticated, service_role;
grant execute on function public.save_qr_storage_season_v1300(uuid, text, text, text, integer, text) to authenticated, service_role;
grant execute on function public.delete_qr_storage_season_v1300(uuid) to authenticated, service_role;

-- 保管目安（008）の変更・削除を、仕入れ担当者も行えるようにする（本番の現在の定義をもとに書き換え）
do $do$
declare
  r record;
  v_def text;
  v_new text;
begin
  for r in
    select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname in ('save_qr_storage_limit_v1250', 'delete_qr_storage_limit_v1250')
  loop
    v_def := pg_get_functiondef(r.oid);
    v_new := replace(v_def, 'seika_require_role_v1240(array[''admin'',''worker''])', 'seika_require_role_v1240(array[''admin'',''worker'',''buyer''])');
    if v_new <> v_def then
      execute v_new;
    end if;
  end loop;
end
$do$;

commit;

-- 確認：4行とも「OK」なら成功です
select '特別期間の表' as 確認項目,
       case when to_regclass('public.qr_storage_limit_seasons_v1300') is not null then 'OK' else '要確認' end as 判定
union all
select '特別期間を保存・削除する関数',
       case when (select count(*) from pg_proc where proname in ('save_qr_storage_season_v1300','delete_qr_storage_season_v1300')) = 2 then 'OK' else '要確認' end
union all
select '保管目安の保存（仕入れ担当者も可）',
       case when (select pg_get_functiondef(oid) from pg_proc where proname = 'save_qr_storage_limit_v1250') like '%''buyer''%' then 'OK' else '要確認' end
union all
select '保管目安の削除（仕入れ担当者も可）',
       case when (select pg_get_functiondef(oid) from pg_proc where proname = 'delete_qr_storage_limit_v1250') like '%''buyer''%' then 'OK' else '要確認' end;
