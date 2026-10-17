-- 014_通信量を減らす_履歴の更新時刻.sql
-- 目的：在庫入力・廃棄・在庫修正の履歴に「サーバーで更新した時刻（synced_at）」を付け、
--       アプリが「変わった行だけ」を受け取れるようにする（通信量を減らす第1段階）。
-- データの中身は変えません。何度実行しても同じ結果になります。

alter table public.inventory_records   add column if not exists synced_at timestamptz not null default now();
alter table public.waste_records       add column if not exists synced_at timestamptz not null default now();
alter table public.inventory_movements add column if not exists synced_at timestamptz not null default now();

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

drop trigger if exists seika_touch_synced_at_v1240 on public.inventory_records;
create trigger seika_touch_synced_at_v1240 before insert or update on public.inventory_records
  for each row execute function public.seika_touch_synced_at_v1240();
drop trigger if exists seika_touch_synced_at_v1240 on public.waste_records;
create trigger seika_touch_synced_at_v1240 before insert or update on public.waste_records
  for each row execute function public.seika_touch_synced_at_v1240();
drop trigger if exists seika_touch_synced_at_v1240 on public.inventory_movements;
create trigger seika_touch_synced_at_v1240 before insert or update on public.inventory_movements
  for each row execute function public.seika_touch_synced_at_v1240();

notify pgrst, 'reload schema';

-- 確認（3行とも OK になれば成功）
select t as 表, case when c.n=1 and g.n=1 then 'OK' else 'NG' end as 結果
from (values ('inventory_records'),('waste_records'),('inventory_movements')) v(t)
cross join lateral (select count(*) n from information_schema.columns where table_schema='public' and table_name=v.t and column_name='synced_at') c
cross join lateral (select count(*) n from pg_trigger tg join pg_class cl on cl.oid=tg.tgrelid join pg_namespace ns on ns.oid=cl.relnamespace
                    where ns.nspname='public' and cl.relname=v.t and tg.tgname='seika_touch_synced_at_v1240' and not tg.tgisinternal) g
order by 1;
