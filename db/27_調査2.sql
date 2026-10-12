/* SEIKA＋ ロメインレタス未計算の調査。1文のみ。読み取り専用。 */

select 'A 価格表の品目名' as 区分,
       concat(pp.item_name, ' / ', pp.price_type, ' / 件数', count(*)::text,
              ' / 最古', min(pp.week_start)::text, ' / 最新', max(pp.week_start)::text) as 内容
from public.purchase_prices pp
where pp.item_name ilike '%レタス%'
   or pp.item_name ilike '%ロメイン%'
   or pp.item_name ilike '%リーフ%'
group by pp.item_name, pp.price_type

union all
select 'B ロメインレタスの完全一致',
       concat('件数', count(*)::text)
from public.purchase_prices pp
where btrim(pp.item_name) = 'ロメインレタス'

union all
select 'C トリミング明細の品目名',
       concat('品目[', coalesce(l.item_name,''), '] 産地[', coalesce(l.origin,''),
              '] 仕入先[', coalesce(l.supplier,''), '] 使用', coalesce(l.used_weight_kg,0)::text, 'kg')
from public.trimming_job_lots l
where l.item_name ilike '%ロメイン%'

union all
select 'D 対象ロット',
       concat('品目[', coalesce(q.item_name,''), '] 産地[', coalesce(q.origin,''),
              '] 仕入先[', coalesce(q.supplier,''), '] 入荷', coalesce(q.received_date::text,''))
from public.qr_lots q
where q.lot_no = '20260904-ロメインレタス-66403'

order by 1, 2;
