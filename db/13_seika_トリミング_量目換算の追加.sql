-- ============================================================
-- SEIKA＋ トリミング日報：ケース品（量目）の重量換算を追加
--   エラー: 使用数量または重量換算が不正です: QR20260831-5SI50559 (22023)
--   原因  : create_trimming_job が current_weight / total_weight しか見ておらず、
--           ケース品の量目(pack_weight)を換算に使えない。
--           アプリ側(v195TrimUnitWeight)は量目にフォールバックするため不整合。
--   対応  : サーバー側の換算に「量目」を第3候補として追加する。
--   ※ データは変更しません。関数定義だけを置き換えます。
-- ============================================================

do $$
declare
  v_def text;
  v_new text;
  v_old text := 'v_lot.total_weight/v_lot.received_qty';
  v_add text;
begin
  -- 前提チェック：量目の列があること
  if not exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='qr_lots' and column_name='pack_weight'
  ) then
    raise exception 'public.qr_lots に pack_weight 列がありません（変更していません）';
  end if;

  -- 前提チェック：量目パース関数があること
  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='seika_parse_kg_v1162'
  ) then
    raise exception 'public.seika_parse_kg_v1162 が見つかりません（変更していません）';
  end if;

  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='create_trimming_job';

  if v_def is null then
    raise exception 'public.create_trimming_job が見つかりません';
  end if;

  -- 置換の一意性を確認（複数箇所に一致するなら中断）
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then
    raise exception '換算式の該当箇所が1件ではありません。定義が想定と異なります（変更していません）';
  end if;

  v_add := v_old || E'\n      when public.seika_parse_kg_v1162(v_lot.pack_weight::text) > 0'
                 || E' then public.seika_parse_kg_v1162(v_lot.pack_weight::text)';

  v_new := replace(v_def, v_old, v_add);

  execute v_new;
  raise notice 'create_trimming_job に量目(pack_weight)換算を追加しました';
end $$;

-- ============================================================
-- 確認（結果は1つの表にまとめて表示されます）
--   ① create_trimming_job の修正状態
--   ② 旧列名 initial_quantity が残っている棚卸し系関数の該当行
-- ============================================================
select '① create_trimming_job' as 区分,
       case when pg_get_functiondef(p.oid) like '%seika_parse_kg_v1162(v_lot.pack_weight%'
            then '量目換算あり（修正OK）' else '量目換算なし（未反映）' end as 内容
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'create_trimming_job'

union all

select '② ' || p.proname as 区分,
       btrim(t.line)     as 内容
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace,
     lateral unnest(string_to_array(pg_get_functiondef(p.oid), E'\n')) as t(line)
where n.nspname = 'public'
  and p.prosrc ilike '%initial_quantity%'
  and t.line ilike '%initial_quantity%'
order by 1, 2;
