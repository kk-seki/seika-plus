-- v1.199-c89 適正在庫の変更履歴（いつ・誰が・何kgから何kgへ）をサーバーに保存する
--  ・今までは仕入れ担当者が数字を変えたときの履歴がサーバーに残っていませんでした（数字そのものは保存済み）。
--  ・履歴は追加だけで、上書き・削除はしません。在庫・適正在庫の数字・担当は変わりません。
--  何度実行しても同じ結果になります。
begin;

create table if not exists public.optimal_stock_change_logs_v1199c89 (
  id text primary key,
  item_id text not null,
  item_name text,
  old_min numeric, old_max numeric, new_min numeric, new_max numeric,
  changed_by text, changed_by_id text, role text, memo text,
  changed_at timestamptz not null default now(),
  saved_by uuid,
  saved_at timestamptz not null default now()
);
create index if not exists optimal_stock_change_logs_v1199c89_item on public.optimal_stock_change_logs_v1199c89(item_id, changed_at desc);
alter table public.optimal_stock_change_logs_v1199c89 enable row level security;
drop policy if exists optimal_stock_change_logs_v1199c89_read on public.optimal_stock_change_logs_v1199c89;
create policy optimal_stock_change_logs_v1199c89_read on public.optimal_stock_change_logs_v1199c89 for select to authenticated using (public.is_active_user());
revoke all on public.optimal_stock_change_logs_v1199c89 from anon;
grant select on public.optimal_stock_change_logs_v1199c89 to authenticated;

create or replace function public.save_optimal_stock_change_log_v1199c89(p_log jsonb)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles%rowtype; v_at timestamptz;
begin
  v := public.seika_v1136_require_roles(array['admin','buyer']);
  if jsonb_typeof(coalesce(p_log,'null'::jsonb)) <> 'object' or nullif(p_log->>'id','') is null or nullif(p_log->>'itemId','') is null then
    raise exception '履歴のデータが正しくありません';
  end if;
  begin v_at := (p_log->>'changedAt')::timestamptz; exception when others then v_at := now(); end;
  insert into public.optimal_stock_change_logs_v1199c89(id,item_id,item_name,old_min,old_max,new_min,new_max,changed_by,changed_by_id,role,memo,changed_at,saved_by)
  values (left(p_log->>'id',100), left(p_log->>'itemId',100), left(p_log->>'itemName',100),
    nullif(p_log->>'oldMin','')::numeric, nullif(p_log->>'oldMax','')::numeric, nullif(p_log->>'newMin','')::numeric, nullif(p_log->>'newMax','')::numeric,
    coalesce(nullif(v.display_name,''), left(p_log->>'changedBy',60)), left(p_log->>'changedById',60), v.role, left(p_log->>'memo',200), coalesce(v_at, now()), v.id)
  on conflict (id) do nothing;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.save_optimal_stock_change_log_v1199c89(jsonb) from public, anon;
grant execute on function public.save_optimal_stock_change_log_v1199c89(jsonb) to authenticated, service_role;

commit;
notify pgrst, 'reload schema';

-- 確認：2行とも「OK」なら成功です
select '変更履歴を残す場所' as 確認項目,
       case when to_regclass('public.optimal_stock_change_logs_v1199c89') is not null then 'OK' else '要確認' end as 判定
union all
select '変更履歴を保存する仕組み',
       case when to_regprocedure('public.save_optimal_stock_change_log_v1199c89(jsonb)') is not null then 'OK' else '要確認' end;
