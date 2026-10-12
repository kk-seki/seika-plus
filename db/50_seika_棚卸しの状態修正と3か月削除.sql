-- 50 棚卸しの状態修正と3か月経過分の削除
--  1) 現在の棚卸しデータを退避（元に戻せるように）
--  2) 確定済みの月末棚卸しの状態を completed に戻す
--  3) 開始処理が「確定日がある棚卸し」を進行中と誤判定しないようにする
--  4) 確定から3か月を過ぎた棚卸しを削除する関数を追加（管理者が棚卸しモードを開いたときにアプリが呼び出します）
begin;

-- 1) 退避
create table if not exists public.seika_inventory_counts_backup_v1205 (
  id bigserial primary key,
  backed_at timestamptz not null default now(),
  reason text not null,
  session jsonb not null
);
alter table public.seika_inventory_counts_backup_v1205 enable row level security;
revoke all on public.seika_inventory_counts_backup_v1205 from public, anon, authenticated;

insert into public.seika_inventory_counts_backup_v1205 (reason, session)
select '50_状態修正前', e
  from public.app_state a,
       jsonb_array_elements(coalesce(a.data->'inventoryCounts'->'sessions','[]'::jsonb)) e
 where a.id = 'ishioka_inventory_production_v2';

-- 2) 状態の修正
update public.app_state a
   set data = jsonb_set(
         a.data, '{inventoryCounts,sessions}',
         coalesce((
           select jsonb_agg(
                    case when x.e->>'monthEndMode' = 'month_end_v188'
                           and nullif(x.e->>'v188ConfirmedAt','') is not null
                           and coalesce(x.e->>'status','') <> 'completed'
                         then x.e || '{"status":"completed"}'::jsonb
                         else x.e end
                    order by x.ord)
             from jsonb_array_elements(a.data->'inventoryCounts'->'sessions') with ordinality x(e, ord)
         ), '[]'::jsonb)),
       version = version + 1,
       updated_at = now()
 where a.id = 'ishioka_inventory_production_v2'
   and exists (
     select 1 from jsonb_array_elements(coalesce(a.data->'inventoryCounts'->'sessions','[]'::jsonb)) e
      where e->>'monthEndMode' = 'month_end_v188'
        and nullif(e->>'v188ConfirmedAt','') is not null
        and coalesce(e->>'status','') <> 'completed');

-- 3) 開始処理の判定を補強（現在の関数定義の該当1か所だけを書き換えます）
do $$
declare
  v_def text;
  v_old text := $q$and coalesce(v_existing->>'status', '') not in ('completed', 'confirmed', 'test_confirmed', 'reversed', 'cancelled') then$q$;
  v_new text := $q$and coalesce(v_existing->>'status', '') not in ('completed', 'confirmed', 'test_confirmed', 'reversed', 'cancelled')
       and nullif(v_existing->>'v188ConfirmedAt', '') is null then$q$;
begin
  v_def := pg_get_functiondef('public.v177_create_inventory_count_session(text,jsonb,text)'::regprocedure);
  if position('v188ConfirmedAt' in v_def) > 0 then
    raise notice '開始処理は修正済みです';
  elsif position(v_old in v_def) = 0 then
    raise notice '開始処理の該当箇所が見つからないため変更しませんでした（状態修正だけで開始できます）';
  else
    execute replace(v_def, v_old, v_new);
    raise notice '開始処理を修正しました';
  end if;
end $$;

-- 4) 3か月経過分の削除関数
create or replace function public.seika_purge_old_inventory_counts_v1205(p_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_profile public.profiles%rowtype;
  v_state public.app_state%rowtype;
  v_keep jsonb;
  v_deleted jsonb;
  v_count int;
  v_version bigint;
begin
  if p_id <> 'ishioka_inventory_production_v2' then
    raise exception '対象が不正です' using errcode = '22023';
  end if;
  select * into v_profile from public.seika_inventory_count_profile_v123();
  if not found or v_profile.role <> 'admin' then
    raise exception '棚卸しの削除は管理者のみです' using errcode = '42501';
  end if;

  select * into v_state from public.app_state where id = p_id for update;
  if not found then
    raise exception '棚卸し状態が見つかりません' using errcode = 'P0002';
  end if;

  with s as (
    select x.e, x.ord,
           case
             when x.e->>'monthEndMode' = 'month_end_v188' then nullif(x.e->>'v188ConfirmedAt','')
             when coalesce(x.e->>'status','') in ('completed','confirmed','test_confirmed','reversed','cancelled')
               then coalesce(nullif(x.e->>'v177CompletedAt',''), nullif(x.e->>'v177AppliedAt',''),
                             nullif(x.e->>'v186ConfirmedAt',''), nullif(x.e->>'confirmedAt',''),
                             nullif(x.e->>'updatedAt',''), nullif(x.e->>'startedAt',''))
             else null
           end as closed_text
      from jsonb_array_elements(coalesce(v_state.data->'inventoryCounts'->'sessions','[]'::jsonb)) with ordinality x(e, ord)
  ), j as (
    select e, ord,
           closed_text ~ '^\d{4}-\d{2}-\d{2}'
           and (closed_text::timestamptz + interval '3 months') <= pg_catalog.now() as expired
      from s
  )
  select coalesce(jsonb_agg(e order by ord) filter (where not coalesce(expired,false)), '[]'::jsonb),
         coalesce(jsonb_agg(e order by ord) filter (where coalesce(expired,false)), '[]'::jsonb)
    into v_keep, v_deleted
    from j;

  v_count := jsonb_array_length(v_deleted);
  if v_count = 0 then
    return jsonb_build_object('ok', true, 'deleted', 0);
  end if;

  insert into public.seika_inventory_counts_backup_v1205 (reason, session)
  select '3か月経過で削除', e from jsonb_array_elements(v_deleted) e;

  update public.app_state
     set data = jsonb_set(data, '{inventoryCounts,sessions}', v_keep),
         version = version + 1,
         updated_at = pg_catalog.now()
   where id = v_state.id
   returning version into v_version;

  return jsonb_build_object('ok', true, 'deleted', v_count, 'version', v_version,
    'countNos', (select jsonb_agg(e->>'countNo') from jsonb_array_elements(v_deleted) e));
end;
$function$;

revoke all on function public.seika_purge_old_inventory_counts_v1205(text) from public, anon;
grant execute on function public.seika_purge_old_inventory_counts_v1205(text) to authenticated, service_role;

commit;

-- 確認（判定欄が空ならOK）
select e->>'countNo' as 棚卸し番号, e->>'room' as 冷蔵庫, e->>'status' as 状態,
       case when coalesce(e->>'status','') not in ('completed','confirmed','test_confirmed','reversed','cancelled')
             and nullif(e->>'v188ConfirmedAt','') is null
            then '★開始を妨げている' else '' end as 判定,
       e->>'v188ConfirmedAt' as 確定日時
  from public.app_state a,
       jsonb_array_elements(coalesce(a.data->'inventoryCounts'->'sessions','[]'::jsonb)) e
 where a.id = 'ishioka_inventory_production_v2';
