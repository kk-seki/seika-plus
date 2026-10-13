-- 011_歩留まり履歴の作成記録を許可.sql
-- 目的：月次Excel・履歴管理で「歩留まり・仕入価格履歴」をExcel出力したときに
--       「Excelを作成できませんでした（seika_monthly_archives_module_check）」となる不具合を直す。
-- 原因：作成済みを記録する表の決まりが「廃棄・QR・品質」の3種類だけで、「歩留まり（trimming）」が入っていなかった。
-- ・いまの種類はそのまま残し、「trimming」だけ追加します。
-- ・何度実行しても同じ結果になります。
begin;
do $do$
declare v_def text; v_vals text[];
begin
  select pg_get_constraintdef(c.oid) into v_def
  from pg_constraint c
  where c.conrelid = 'public.seika_monthly_archives'::regclass and c.conname = 'seika_monthly_archives_module_check';
  if v_def is not null and v_def ~ '\mtrimming\M' then return; end if;
  if v_def is not null then
    select array_agg(distinct m[1]) into v_vals from regexp_matches(v_def, '([a-z_]+)', 'g') as m
    where m[1] not in ('check','module','any','array','text');
    execute 'alter table public.seika_monthly_archives drop constraint seika_monthly_archives_module_check';
  end if;
  v_vals := coalesce(v_vals, array['waste','qr','quality']) || array['trimming'];
  execute format('alter table public.seika_monthly_archives add constraint seika_monthly_archives_module_check check (module = any (%L::text[]))', v_vals);
end
$do$;
commit;

-- 確認：「OK」なら成功です
select '歩留まり履歴の作成記録' as 確認項目,
  case when exists (select 1 from pg_constraint where conname = 'seika_monthly_archives_module_check' and pg_get_constraintdef(oid) ~ '\mtrimming\M') then 'OK' else '要確認' end as 判定,
  (select pg_get_constraintdef(oid) from pg_constraint where conname = 'seika_monthly_archives_module_check') as いまの決まり;
