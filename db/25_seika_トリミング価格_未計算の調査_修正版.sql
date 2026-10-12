-- ============================================================
-- SEIKA＋ ④ トリミング原価「未計算」の調査（修正版）
--
--   24_ は trimming_jobs に item_name 列が無くエラーになりました。
--   ここでは列名に依存しない形に直しています。読み取りのみです。
-- ============================================================

-- ① 「レタス」系の価格がどの表・どの名前で入っているか
do $$
declare r record; sql text;
begin
  create temp table if not exists v1200_price_hits(
    table_name text, item_name text, cnt bigint
  ) on commit preserve rows;
  delete from v1200_price_hits;

  for r in
    select c.table_schema, c.table_name
    from information_schema.columns c
    join information_schema.tables t
      on t.table_schema=c.table_schema and t.table_name=c.table_name
    where c.table_schema='public'
      and c.column_name='item_name'
      and t.table_type='BASE TABLE'
  loop
    sql := format(
      'insert into v1200_price_hits
         select %L, item_name, count(*)
         from %I.%I
        where item_name ilike ''%%レタス%%'' or item_name ilike ''%%ロメイン%%''
                                            or item_name ilike ''%%リーフ%%''
        group by item_name',
      r.table_name, r.table_schema, r.table_name);
    begin execute sql; exception when others then null; end;
  end loop;
end $$;

select 'A. レタス系が登録されている表と品目名' as 区分,
       table_name as 表, item_name as 品目名, cnt as 件数
from v1200_price_hits
order by table_name, item_name;


-- ② trimming_jobs の列構成（次の修正のために必要）
select 'B. trimming_jobs の列' as 区分, ordinal_position as 順, column_name as 列名, data_type as 型
from information_schema.columns
where table_schema='public' and table_name='trimming_jobs'
order by ordinal_position;


-- ③ 対象ロット
select 'C. 対象ロット' as 区分, l.*
from public.qr_lots l
where l.lot_no = '20260904-ロメインレタス-66403';


-- ④ ロメインを含むトリミング登録（列名に依存せず行全体で検索）
select 'D. トリミング登録' as 区分, t.*
from public.trimming_jobs t
where t::text ilike '%ロメイン%'
limit 20;


-- ⑤ 価格解決ロジックの中身
select 'E. 関数定義' as 区分, p.proname as 関数名, pg_get_functiondef(p.oid) as 定義
from pg_proc p
join pg_namespace ns on ns.oid=p.pronamespace
where ns.nspname='public'
  and p.proname in ('resolve_trimming_purchase_price_v1117',
                    'recalc_trimming_job_price_v1195')
order by p.proname;
