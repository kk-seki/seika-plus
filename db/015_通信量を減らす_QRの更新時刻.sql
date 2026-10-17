-- 015_通信量を減らす_QRの更新時刻.sql
-- 目的：QRロット・QRの移動履歴・月末のQR在庫記録に「サーバーで更新した時刻（synced_at）」を付け、
--       アプリが「変わった行だけ」を受け取れるようにする（通信量を減らす第2段階）。
-- データの中身は変えません。何度実行しても同じ結果になります。

alter table public.qr_lots                  add column if not exists synced_at timestamptz not null default now();
alter table public.qr_lot_movements         add column if not exists synced_at timestamptz not null default now();
alter table public.qr_lot_monthly_snapshots add column if not exists synced_at timestamptz not null default now();

-- 014で作った「更新時刻を入れる仕組み」を同じように使います（014が未実行でも動くよう、ここでも定義します）
create or replace function public.seika_touch_synced_at_v1240()
returns trigger
language plpgsql
set search_path to ''
as $$
begin
  new.synced_at := clock_timestamp();
  return new;
end
$$;

drop trigger if exists seika_touch_synced_at_v1240 on public.qr_lots;
create trigger seika_touch_synced_at_v1240 before insert or update on public.qr_lots
  for each row execute function public.seika_touch_synced_at_v1240();
drop trigger if exists seika_touch_synced_at_v1240 on public.qr_lot_movements;
create trigger seika_touch_synced_at_v1240 before insert or update on public.qr_lot_movements
  for each row execute function public.seika_touch_synced_at_v1240();
drop trigger if exists seika_touch_synced_at_v1240 on public.qr_lot_monthly_snapshots;
create trigger seika_touch_synced_at_v1240 before insert or update on public.qr_lot_monthly_snapshots
  for each row execute function public.seika_touch_synced_at_v1240();

create index if not exists qr_lots_synced_at_idx                  on public.qr_lots (synced_at);
create index if not exists qr_lot_movements_synced_at_idx         on public.qr_lot_movements (synced_at);
create index if not exists qr_lot_monthly_snapshots_synced_at_idx on public.qr_lot_monthly_snapshots (synced_at);

notify pgrst, 'reload schema';

-- 確認（3行とも OK になれば成功）
select t as 表, case when c.n=1 and g.n=1 then 'OK' else 'NG' end as 結果
from (values ('qr_lots'),('qr_lot_movements'),('qr_lot_monthly_snapshots')) v(t)
cross join lateral (select count(*) n from information_schema.columns where table_schema='public' and table_name=v.t and column_name='synced_at') c
cross join lateral (select count(*) n from pg_trigger tg join pg_class cl on cl.oid=tg.tgrelid join pg_namespace ns on ns.oid=cl.relnamespace
                    where ns.nspname='public' and cl.relname=v.t and tg.tgname='seika_touch_synced_at_v1240' and not tg.tgisinternal) g
order by 1;
