/*
063_動作の重さの記録.sql（v1.199-c152）

目的：
  アプリの動きが重い原因を、実際の端末で測る。
  アプリ（js/33-c152-perf.js）が、通信（どのデータを何ミリ秒・何バイトで受け取ったか）、
  画面を開くのにかかった時間、固まった時間（長い処理）を端末にためて、1分ごと・画面を閉じたときにまとめてここへ送る。
  1. 記録の表（app_perf_logs_v1199c152）。30日より古い記録は、送るたびに自動で消す。
  2. 送る関数（log_app_perf_v1199c152）。ログインしている人ならだれでも送れる（自分の記録だけ）。1回200件まで。

権限：送る＝ログインしている全員（石岡・本社のすべての役割）／見る＝管理者だけ。
SQLを実行しただけでは、在庫・QRロット・伝票・出荷予定・アプリのデータは変わりません。何度実行しても同じ結果になります。
このSQLを実行する前でも、アプリは今までどおり動きます（送れなかった記録は端末の中で捨てます）。

元に戻すとき：
  drop function if exists public.log_app_perf_v1199c152(jsonb);
  drop table if exists public.app_perf_logs_v1199c152;
*/
begin;

create table if not exists public.app_perf_logs_v1199c152(
  id bigserial primary key,
  at timestamptz not null default now(),
  received_at timestamptz not null default now(),
  user_id uuid,
  role text not null default '',
  device text not null default '',
  app_version text not null default '',
  kind text not null default '',      -- net（通信）・page（画面）・long（固まった時間）・start（起動）
  name text not null default '',      -- 表の名前・関数の名前・画面の名前
  ms numeric,
  bytes bigint,
  screen text not null default '',
  extra jsonb not null default '{}'::jsonb
);
create index if not exists app_perf_logs_v1199c152_at on public.app_perf_logs_v1199c152(at);
create index if not exists app_perf_logs_v1199c152_kind_name on public.app_perf_logs_v1199c152(kind,name);

alter table public.app_perf_logs_v1199c152 enable row level security;
drop policy if exists app_perf_logs_v1199c152_read on public.app_perf_logs_v1199c152;
create policy app_perf_logs_v1199c152_read on public.app_perf_logs_v1199c152 for select to authenticated using (public.has_any_role(array['admin']));
revoke insert, update, delete on public.app_perf_logs_v1199c152 from anon, authenticated;

create or replace function public.log_app_perf_v1199c152(p_rows jsonb)
returns integer
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_n integer := 0;
begin
  if v_uid is null then
    raise exception 'ログインしてから送ってください';
  end if;
  if jsonb_typeof(p_rows) <> 'array' then
    return 0;
  end if;
  insert into public.app_perf_logs_v1199c152(at,user_id,role,device,app_version,kind,name,ms,bytes,screen,extra)
  select
    coalesce(nullif(r->>'at','')::timestamptz, now()),
    v_uid,
    left(coalesce(r->>'role',''),40),
    left(coalesce(r->>'device',''),200),
    left(coalesce(r->>'app_version',''),40),
    left(coalesce(r->>'kind',''),20),
    left(coalesce(r->>'name',''),200),
    case when (r->>'ms') ~ '^[0-9]+(\.[0-9]+)?$' then least((r->>'ms')::numeric, 3600000) end,
    case when (r->>'bytes') ~ '^[0-9]+$' then least((r->>'bytes')::bigint, 1000000000) end,
    left(coalesce(r->>'screen',''),80),
    case when jsonb_typeof(r->'extra')='object' and length((r->'extra')::text) <= 2000 then r->'extra' else '{}'::jsonb end
  from (select value r from jsonb_array_elements(p_rows) limit 200) x;
  get diagnostics v_n = row_count;
  /* 30日より古い記録は消す（表が大きくならないように） */
  delete from public.app_perf_logs_v1199c152 where at < now() - interval '30 days';
  return v_n;
end;
$fn$;

revoke all on function public.log_app_perf_v1199c152(jsonb) from public, anon;
grant execute on function public.log_app_perf_v1199c152(jsonb) to authenticated;

commit;

-- 確認（成功なら OK が2つ出ます）
select case when to_regclass('public.app_perf_logs_v1199c152') is not null then 'OK' else 'NG' end as 記録の表,
       case when to_regprocedure('public.log_app_perf_v1199c152(jsonb)') is not null then 'OK' else 'NG' end as 送る関数;
