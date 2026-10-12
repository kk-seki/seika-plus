-- ============================================================
-- SEIKA＋ トリミング日報 登録エラーの修正
--   エラー: record "v_lot" has no field "initial_quantity" (42703)
--   対象  : public.create_trimming_job
--   内容  : 存在しない列 initial_quantity への参照を received_qty のみに直す
--   ※ データは一切変更しません。関数定義だけを置き換えます。
-- ============================================================

do $$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'create_trimming_job';

  if v_def is null then
    raise exception 'public.create_trimming_job が見つかりません';
  end if;

  v_new := replace(v_def,
    'coalesce(v_lot.received_qty,v_lot.initial_quantity,0)',
    'coalesce(v_lot.received_qty,0)');

  v_new := replace(v_new,
    'coalesce(v_lot.received_qty,v_lot.initial_quantity)',
    'v_lot.received_qty');

  if v_new = v_def then
    raise exception '置換対象が見つかりませんでした。定義が想定と異なります（変更していません）';
  end if;

  if position('initial_quantity' in v_new) > 0 then
    raise exception '想定外の initial_quantity 参照が残っています（変更していません）';
  end if;

  execute v_new;
  raise notice 'create_trimming_job を修正しました';
end $$;

-- 確認：public スキーマに initial_quantity を参照する関数が残っていないこと
-- 0行なら修正完了です。
select p.proname                                 as 残っている関数,
       pg_get_function_identity_arguments(p.oid) as 引数
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.prosrc ilike '%initial_quantity%'
order by p.proname;
