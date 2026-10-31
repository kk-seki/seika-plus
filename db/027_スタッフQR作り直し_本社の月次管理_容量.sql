/*
027_スタッフQR作り直し_本社の月次管理_容量.sql（v1.199-c69）
1. スタッフQRを1人分だけ作り直す（古いQRは読めなくなる）
2. 本社のデータの月次管理（Excel作成・保管済みの記録・3か月たった月の整理）
3. データの容量（管理者だけが見られる）
前提：000〜026を実行済みであること。何度実行しても同じ結果になります。
このSQLを実行しただけでは、データは消えません（整理は管理者が画面で月を選んで行います）。
*/
begin;

-- 1. スタッフQRの作り直し
create or replace function public.hq_reissue_staff_qr_v1690(p_id uuid)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles; r public.hq_staff_v1500%rowtype;
begin
  v := public.hq_actor_v1400(array['admin','hq_worker']);
  update public.hq_staff_v1500
     set qr_key = 'HQST-' || replace(gen_random_uuid()::text,'-',''), updated_at = now()
   where id = p_id and deleted_at is null
  returning * into r;
  if not found then raise exception 'スタッフが見つかりません。画面を開き直してください'; end if;
  return jsonb_build_object('ok', true, 'id', r.id, 'name', r.name, 'team', r.team, 'qr_key', r.qr_key);
end $$;

-- 2. 本社の月次管理
create table if not exists public.hq_monthly_archives_v1690 (
  target_month date primary key check (target_month = date_trunc('month', target_month)::date),
  status text not null default 'pending' check (status in ('pending','excel_created','excel_saved','deleted')),
  file_name text,
  excel_created_at timestamptz, excel_created_by_name text,
  excel_saved_at timestamptz, excel_saved_by_name text,
  deleted_at timestamptz, deleted_by_name text, deleted_counts jsonb,
  updated_at timestamptz not null default now()
);
alter table public.hq_monthly_archives_v1690 enable row level security;
revoke all on table public.hq_monthly_archives_v1690 from anon, authenticated;

create or replace function public.hq_monthly_counts_v1690(p_month date)
returns jsonb language sql stable security definer set search_path to ''
as $$
  select jsonb_build_object(
    'movements', (select count(*) from public.hq_lot_movements_v1400 m join public.hq_lots_v1400 l on l.id = m.lot_id
                   where (m.occurred_at at time zone 'Asia/Tokyo')::date >= p_month
                     and (m.occurred_at at time zone 'Asia/Tokyo')::date < (p_month + interval '1 month')::date
                     and l.status in ('在庫なし','取消')),
    'waste', (select count(*) from public.hq_waste_v1500 where waste_date >= p_month and waste_date < (p_month + interval '1 month')::date),
    'works', (select count(*) from public.hq_works_v1500 where work_date >= p_month and work_date < (p_month + interval '1 month')::date
               and status in ('完了','取消') and (kind <> '下処理' or confirm_status <> '未確定')),
    'counts', (select count(*) from public.hq_stock_counts_v1500 where count_date >= p_month and count_date < (p_month + interval '1 month')::date),
    'limit_checks', (select count(*) from public.hq_limit_checks_v1600 where (created_at at time zone 'Asia/Tokyo')::date >= p_month
               and (created_at at time zone 'Asia/Tokyo')::date < (p_month + interval '1 month')::date),
    'deleted_works', (select count(*) from public.hq_deleted_works_v1500 where (deleted_at at time zone 'Asia/Tokyo')::date >= p_month
               and (deleted_at at time zone 'Asia/Tokyo')::date < (p_month + interval '1 month')::date)
  );
$$;
revoke all on function public.hq_monthly_counts_v1690(date) from public, anon, authenticated;

create or replace function public.hq_monthly_list_v1690()
returns jsonb language plpgsql stable security definer set search_path to ''
as $$
declare v public.profiles; v_cur date := date_trunc('month', now() at time zone 'Asia/Tokyo')::date; v_rows jsonb;
begin
  v := public.hq_actor_v1400(array['admin']);
  with months as (
    select date_trunc('month', occurred_at at time zone 'Asia/Tokyo')::date m from public.hq_lot_movements_v1400
    union select date_trunc('month', waste_date)::date from public.hq_waste_v1500
    union select date_trunc('month', work_date)::date from public.hq_works_v1500
    union select date_trunc('month', count_date)::date from public.hq_stock_counts_v1500
    union select target_month from public.hq_monthly_archives_v1690
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'target_month', to_char(m.m,'YYYY-MM'),
      'status', coalesce(a.status,'pending'),
      'counts', case when coalesce(a.status,'') = 'deleted' then a.deleted_counts else public.hq_monthly_counts_v1690(m.m) end,
      'file_name', a.file_name,
      'excel_created_at', a.excel_created_at, 'excel_created_by_name', a.excel_created_by_name,
      'excel_saved_at', a.excel_saved_at, 'excel_saved_by_name', a.excel_saved_by_name,
      'deleted_at', a.deleted_at, 'deleted_by_name', a.deleted_by_name,
      'deletable', m.m < (v_cur - interval '3 months')::date
    ) order by m.m desc), '[]'::jsonb)
  into v_rows
  from months m left join public.hq_monthly_archives_v1690 a on a.target_month = m.m
  where m.m is not null and m.m < v_cur;
  return jsonb_build_object('ok', true, 'rows', v_rows);
end $$;

create or replace function public.hq_monthly_mark_created_v1690(p_month date, p_file_name text)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles; v_m date := date_trunc('month', p_month)::date;
begin
  v := public.hq_actor_v1400(array['admin']);
  if v_m >= date_trunc('month', now() at time zone 'Asia/Tokyo')::date then raise exception '保管の対象は先月以前の月です'; end if;
  insert into public.hq_monthly_archives_v1690(target_month, status, file_name, excel_created_at, excel_created_by_name)
  values (v_m, 'excel_created', left(coalesce(p_file_name,''),240), now(), v.display_name)
  on conflict (target_month) do update set
    status = case when public.hq_monthly_archives_v1690.status = 'deleted' then 'deleted' else 'excel_created' end,
    file_name = excluded.file_name, excel_created_at = excluded.excel_created_at, excel_created_by_name = excluded.excel_created_by_name,
    excel_saved_at = case when public.hq_monthly_archives_v1690.status = 'deleted' then public.hq_monthly_archives_v1690.excel_saved_at end,
    excel_saved_by_name = case when public.hq_monthly_archives_v1690.status = 'deleted' then public.hq_monthly_archives_v1690.excel_saved_by_name end,
    updated_at = now();
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.hq_monthly_confirm_saved_v1690(p_month date)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles;
begin
  v := public.hq_actor_v1400(array['admin']);
  update public.hq_monthly_archives_v1690
     set status = 'excel_saved', excel_saved_at = now(), excel_saved_by_name = v.display_name, updated_at = now()
   where target_month = date_trunc('month', p_month)::date and status in ('excel_created','excel_saved');
  if not found then raise exception '先にこの月のExcelを作ってください'; end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.hq_monthly_delete_v1690(p_month date)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare
  v public.profiles; v_m date := date_trunc('month', p_month)::date; v_n date := (date_trunc('month', p_month) + interval '1 month')::date;
  a public.hq_monthly_archives_v1690%rowtype; c jsonb; w uuid[];
begin
  v := public.hq_actor_v1400(array['admin']);
  if v_m >= (date_trunc('month', now() at time zone 'Asia/Tokyo') - interval '3 months')::date then
    raise exception '本社のデータは直近3か月を残します。この月はまだ整理できません';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('hq_monthly:' || v_m::text, 1690));
  select * into a from public.hq_monthly_archives_v1690 where target_month = v_m for update;
  if not found or a.status <> 'excel_saved' then raise exception '先にExcelを作って、デスクネッツへの保管を記録してください'; end if;
  c := public.hq_monthly_counts_v1690(v_m);

  select coalesce(array_agg(id), '{}') into w from public.hq_works_v1500
   where work_date >= v_m and work_date < v_n and status in ('完了','取消') and (kind <> '下処理' or confirm_status <> '未確定');
  delete from public.hq_work_members_v1500 where work_id = any (w);
  delete from public.hq_work_materials_v1500 where work_id = any (w);
  delete from public.hq_works_v1500 where id = any (w);
  delete from public.hq_deleted_works_v1500 where (deleted_at at time zone 'Asia/Tokyo')::date >= v_m and (deleted_at at time zone 'Asia/Tokyo')::date < v_n;
  delete from public.hq_waste_v1500 where waste_date >= v_m and waste_date < v_n;
  delete from public.hq_stock_counts_v1500 where count_date >= v_m and count_date < v_n;
  delete from public.hq_limit_checks_v1600 where (created_at at time zone 'Asia/Tokyo')::date >= v_m and (created_at at time zone 'Asia/Tokyo')::date < v_n;
  delete from public.hq_lot_movements_v1400 m using public.hq_lots_v1400 l
   where l.id = m.lot_id and l.status in ('在庫なし','取消')
     and (m.occurred_at at time zone 'Asia/Tokyo')::date >= v_m and (m.occurred_at at time zone 'Asia/Tokyo')::date < v_n;

  update public.hq_monthly_archives_v1690
     set status = 'deleted', deleted_at = now(), deleted_by_name = v.display_name, deleted_counts = c, updated_at = now()
   where target_month = v_m;
  return jsonb_build_object('ok', true, 'counts', c);
end $$;

-- 3. データの容量
create or replace function public.seika_db_size_v1690()
returns jsonb language plpgsql stable security definer set search_path to ''
as $$
declare v public.profiles;
begin
  v := public.hq_actor_v1400(array['admin']);
  return jsonb_build_object('ok', true, 'bytes', pg_catalog.pg_database_size(pg_catalog.current_database()), 'limit_bytes', 500 * 1024 * 1024);
end $$;

revoke all on function public.hq_reissue_staff_qr_v1690(uuid) from public, anon;
grant execute on function public.hq_reissue_staff_qr_v1690(uuid) to authenticated, service_role;
revoke all on function public.hq_monthly_list_v1690() from public, anon;
grant execute on function public.hq_monthly_list_v1690() to authenticated, service_role;
revoke all on function public.hq_monthly_mark_created_v1690(date,text) from public, anon;
grant execute on function public.hq_monthly_mark_created_v1690(date,text) to authenticated, service_role;
revoke all on function public.hq_monthly_confirm_saved_v1690(date) from public, anon;
grant execute on function public.hq_monthly_confirm_saved_v1690(date) to authenticated, service_role;
revoke all on function public.hq_monthly_delete_v1690(date) from public, anon;
grant execute on function public.hq_monthly_delete_v1690(date) to authenticated, service_role;
revoke all on function public.seika_db_size_v1690() from public, anon;
grant execute on function public.seika_db_size_v1690() to authenticated, service_role;

commit;

notify pgrst, 'reload schema';

/* 成功の確かめ方：下のSELECTの4行がすべて「OK」なら成功です。 */
select 'スタッフQRの作り直し' as 項目, case when to_regprocedure('public.hq_reissue_staff_qr_v1690(uuid)') is not null then 'OK' else 'NG' end as 結果
union all select '本社の月次管理の表', case when to_regclass('public.hq_monthly_archives_v1690') is not null then 'OK' else 'NG' end
union all select '本社の月次管理の処理', case when to_regprocedure('public.hq_monthly_list_v1690()') is not null and to_regprocedure('public.hq_monthly_mark_created_v1690(date,text)') is not null and to_regprocedure('public.hq_monthly_confirm_saved_v1690(date)') is not null and to_regprocedure('public.hq_monthly_delete_v1690(date)') is not null then 'OK' else 'NG' end
union all select 'データの容量', case when to_regprocedure('public.seika_db_size_v1690()') is not null then 'OK（いま約'||round(pg_database_size(current_database())/1048576.0)||'MB／500MB）' else 'NG' end;
