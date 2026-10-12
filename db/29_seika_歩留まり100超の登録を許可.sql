-- ============================================================
-- SEIKA＋  歩留まりが100%を超える日報も登録できるようにする
--   対象RPC : public.create_trimming_job
--   内容     : 「入替品合計重量が使用重量を超えています」の拒否を撤廃
--   理由     : 10kg入りの原料に10kg以上入っている等、実測で
--              出来高 > 使用原料 になる場合があり、実数のまま
--              登録できないと歩留まり価格が不正確になるため
--   安全性   : 在庫は一切変更しません（このRPCは元々在庫を触りません）
-- ============================================================
do $$
declare
  v_src text;
  v_new text;
  v_guard text := $g$  if v_output_weight>v_input_weight+0.011 then
    raise exception '入替品合計重量が使用重量を超えています' using errcode='22023';
  end if;$g$;
begin
  select pg_get_functiondef(p.oid) into v_src
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='create_trimming_job';

  if v_src is null then
    raise exception 'public.create_trimming_job が見つかりません';
  end if;

  if position('入替品合計重量が使用重量を超えています' in v_src)=0 then
    raise notice '既に上限チェックは撤廃済みです。変更しません。';
    return;
  end if;

  -- 空白差異に強い形で該当ブロックだけを除去する
  v_new := regexp_replace(
    v_src,
    'if\s+v_output_weight\s*>\s*v_input_weight\s*\+\s*0\.011\s+then\s+raise\s+exception\s+''入替品合計重量が使用重量を超えています''\s+using\s+errcode\s*=\s*''22023''\s*;\s*end\s+if\s*;',
    '',
    'g'
  );

  if v_new = v_src then
    raise exception '上限チェックの該当箇所を特定できませんでした（変更していません）';
  end if;

  if position('入替品合計重量が使用重量を超えています' in v_new)>0 then
    raise exception '上限チェックが残っています（変更していません）';
  end if;

  execute v_new;
  raise notice 'create_trimming_job から歩留まり100%%超の拒否を撤廃しました';
end $$;

-- 参考：ロス(loss_weight_kg)や歩留まり(yield_percent)に
--       マイナス・100超を禁止する制約が無いことを確認する
select conname, pg_get_constraintdef(oid) as定義
from pg_constraint
where conrelid='public.trimming_jobs'::regclass
  and contype='c'
  and (pg_get_constraintdef(oid) ilike '%loss_weight_kg%'
    or pg_get_constraintdef(oid) ilike '%yield_percent%'
    or pg_get_constraintdef(oid) ilike '%output_weight_kg%');
