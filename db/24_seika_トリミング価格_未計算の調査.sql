-- ============================================================
-- SEIKA＋ ④ トリミング原価が「未計算」になる原因の調査
--
--   読み取りのみ。データは一切変更しません。
--   ロメインレタス（20260904-ロメインレタス-66403）が
--   「同一品目の登録価格がありません」と出る理由を特定します。
-- ============================================================

-- ① 価格が入っている表を横断して「レタス」系の登録を探す
--    （item_name 列を持つ全テーブルを対象にする）
do $$
declare r record; n bigint; sql text;
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
    begin
      execute sql;
    exception when others then null;
    end;
  end loop;
end $$;

select 'A. レタス系の登録がある表と品目名' as 区分,
       table_name as 表, item_name as 品目名, cnt as 件数
from v1200_price_hits
order by table_name, item_name;


-- ② 該当ロットの内容
select * from public.qr_lots
where lot_no = '20260904-ロメインレタス-66403';


-- ③ そのロットのトリミング登録
select * from public.trimming_jobs
where item_name ilike '%ロメイン%'
order by created_at desc nulls last
limit 20;


-- ④ 価格解決ロジックの実際の中身（どの表・どの条件で探しているか）
select 'D. 関数定義' as 区分, p.proname as 関数名,
       pg_get_functiondef(p.oid) as 定義
from pg_proc p
join pg_namespace ns on ns.oid=p.pronamespace
where ns.nspname='public'
  and p.proname in ('resolve_trimming_purchase_price_v1117',
                    'recalc_trimming_job_price_v1195')
order by p.proname;
