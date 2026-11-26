/*
071_アカウント別の利用状況.sql（v1.199-c168）

目的：アカウントごとの利用状況（最後に使った日・使った日数・よく開く画面・操作の件数）を見られるようにする。
  ・見られるのは平田 祐希さんのアカウントだけ（管理者のほかの人も見られない）。表 usage_viewers_v1199c168 に入っている人だけ。
  ・画面を開いた記録は「動作の重さの記録」（app_perf_logs_v1199c152、30日で消える）から。なので画面の集計は最大30日。
  ・操作の件数は、QRの入荷（ロット作成）・出庫・廃棄・棚卸し・そのほかの操作・スキャン・廃棄の記録・下処理の日報・本社の操作・返品の記録から（最大90日）。
  ・読むだけ。データは変えません。
前提：063（動作の重さの記録）・067（返品）を実行済みであること。何度実行しても同じ結果になります。
元に戻すとき：drop function if exists public.usage_by_account_v1199c168(integer); drop function if exists public.can_view_usage_v1199c168(); drop table if exists public.usage_viewers_v1199c168;
*/
begin;

-- 見られる人（ここに入っている人だけ）。アプリからは読めない・変えられない
create table if not exists public.usage_viewers_v1199c168(
  profile_id uuid primary key references public.profiles(id) on delete cascade,
  note text not null default '',
  created_at timestamptz not null default now()
);
alter table public.usage_viewers_v1199c168 enable row level security;
revoke all on public.usage_viewers_v1199c168 from public, anon, authenticated;
grant all on public.usage_viewers_v1199c168 to service_role;
insert into public.usage_viewers_v1199c168(profile_id, note)
select id, '平田 祐希（c168 初期登録）' from public.profiles where id = '58b4e90d-43cf-48ad-970f-ef1a884467dd'
on conflict do nothing;

create or replace function public.can_view_usage_v1199c168()
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog','public'
as $c$
  select exists (select 1 from public.usage_viewers_v1199c168 v join public.profiles p on p.id = v.profile_id and p.active where v.profile_id = auth.uid());
$c$;
revoke all on function public.can_view_usage_v1199c168() from public, anon;
grant execute on function public.can_view_usage_v1199c168() to authenticated;

create or replace function public.usage_by_account_v1199c168(p_days integer default 7)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','public'
as $u$
declare
  v_days integer := least(greatest(coalesce(p_days, 7), 1), 90);
  v_today date := (now() at time zone 'Asia/Tokyo')::date;
  v_from date;
  v_since timestamptz;
  v_out jsonb;
begin
  if not public.can_view_usage_v1199c168() then
    raise exception 'この画面は見られません' using errcode = '42501';
  end if;
  v_from := v_today - (v_days - 1);
  v_since := (v_from::timestamp at time zone 'Asia/Tokyo');

  with ppl as (
    select id, display_name, role, legacy_user_id from public.profiles where active
  ),
  -- 画面を開いた記録（動作の重さの記録）
  perf as (
    select user_id, (at at time zone 'Asia/Tokyo')::date d, screen, at from public.app_perf_logs_v1199c152
     where at >= v_since and user_id is not null
  ),
  perf_user as (
    select user_id, max(at) last_at, count(distinct d) days, count(distinct screen) screens from perf group by user_id
  ),
  perf_screen as (
    select user_id, screen, count(distinct d) days, count(*) n from perf where screen is not null and screen <> 'login' group by user_id, screen
  ),
  top_screens as (
    select user_id, jsonb_agg(jsonb_build_object('screen', screen, 'days', days) order by days desc, n desc) filter (where rk <= 8) list
      from (select *, row_number() over (partition by user_id order by days desc, n desc) rk from perf_screen) s group by user_id
  ),
  -- 操作（石岡：legacy_user_id、本社・下処理・返品：profiles.id）
  ops as (
    select l.user_id legacy, null::uuid pid, '入荷' k, l.created_at t from public.qr_lots l where l.created_at >= v_since
    union all
    select m.user_id, null, case when m.movement_type = '出庫' then '出庫' when m.movement_type = '廃棄' then '廃棄'
                                 when m.movement_type in ('棚卸し調整増','棚卸し調整減','差分なし') then '棚卸し' else 'そのほか' end, m.occurred_at
      from public.qr_lot_movements m where m.occurred_at >= v_since
    union all
    select s.user_id, null, 'スキャン', s.scanned_at from public.qr_scan_logs s where s.scanned_at >= v_since
    union all
    select w.user_id, null, '廃棄', w.created_at from public.waste_records w where w.created_at >= v_since
    union all
    select null, j.created_by, '下処理の日報', j.created_at from public.trimming_jobs j where j.created_at >= v_since and j.created_by is not null
    union all
    select null, h.user_id, '本社の操作', h.occurred_at from public.hq_lot_movements_v1400 h where h.occurred_at >= v_since and h.user_id is not null
    union all
    select null, r.created_by, '返品', r.created_at from public.qr_returns_v1199c163 r where r.created_at >= v_since and r.created_by is not null
  ),
  ops_p as (
    select p.id, o.k, o.t from ops o join ppl p on (o.pid is not null and o.pid = p.id) or (o.pid is null and o.legacy is not null and o.legacy = p.legacy_user_id)
  ),
  ops_user as (
    select id, max(t) last_at, jsonb_object_agg(k, n) counts, sum(n) total
      from (select id, k, count(*) n, max(t) t from ops_p group by id, k) x
     group by id
  ),
  ops_days as (
    select id, count(distinct (t at time zone 'Asia/Tokyo')::date) days from ops_p group by id
  )
  select jsonb_agg(jsonb_build_object(
           'id', p.id, 'name', p.display_name, 'role', p.role,
           'last_seen', greatest(pu.last_at, ou.last_at),
           'days', greatest(coalesce(pu.days, 0), coalesce(od.days, 0)),
           'screen_days', coalesce(pu.days, 0), 'screens', coalesce(pu.screens, 0),
           'top_screens', coalesce(ts.list, '[]'::jsonb),
           'ops', coalesce(ou.counts, '{}'::jsonb), 'ops_total', coalesce(ou.total, 0), 'ops_days', coalesce(od.days, 0))
         order by greatest(pu.last_at, ou.last_at) desc nulls last, p.display_name)
    into v_out
    from ppl p
    left join perf_user pu on pu.user_id = p.id
    left join top_screens ts on ts.user_id = p.id
    left join ops_user ou on ou.id = p.id
    left join ops_days od on od.id = p.id;

  return jsonb_build_object('days', v_days, 'from', v_from, 'to', v_today,
    'screen_days_max', least(v_days, 30), 'rows', coalesce(v_out, '[]'::jsonb));
end
$u$;
revoke all on function public.usage_by_account_v1199c168(integer) from public, anon;
grant execute on function public.usage_by_account_v1199c168(integer) to authenticated;

commit;

-- ===== 確認（OK なら成功） =====
select
  (select case when exists (select 1 from public.usage_viewers_v1199c168 where profile_id = '58b4e90d-43cf-48ad-970f-ef1a884467dd') then 'OK' else 'NG' end) as "見られる人（平田さん）",
  (select case when to_regprocedure('public.usage_by_account_v1199c168(integer)') is not null then 'OK' else 'NG' end) as "利用状況の関数";
