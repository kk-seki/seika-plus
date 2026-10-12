-- ============================================================
-- SEIKA＋  歩留まり100%超を許可するための CHECK 制約の付け替え
--   対象テーブル : public.trimming_jobs
--   背景 : 29番のSQLで関数側の拒否は撤廃したが、テーブルに
--          「ロスは0以上」「歩留まりは100以下」の制約が残っており
--          登録時に違反エラーになるため。
--   方針 : 実測どおりの数字を保存できるようにしつつ、
--          異常値（極端なマイナス、桁違い）は引き続き防ぐ。
-- ============================================================
begin;

-- ① ロス重量：マイナスを許可する
--    出来高が使用原料を上回るとロスはマイナスになる。
--    ただし桁違いの異常は防ぐため、使用原料と同量までのマイナスに限定する。
alter table public.trimming_jobs
  drop constraint if exists trimming_jobs_loss_weight_kg_check;

alter table public.trimming_jobs
  add constraint trimming_jobs_loss_weight_kg_check
  check (loss_weight_kg >= -1 * greatest(input_weight_kg, 0));

-- ② 歩留まり：100%超を許可する
--    下限0%は維持。上限は桁違いの誤入力を防ぐため1000%とする。
alter table public.trimming_jobs
  drop constraint if exists trimming_jobs_yield_percent_check;

alter table public.trimming_jobs
  add constraint trimming_jobs_yield_percent_check
  check (yield_percent >= 0 and yield_percent <= 1000);

-- ③ 残す制約（変更しない）
--    trimming_jobs_output_weight_kg_check : 出来高は0以上
--    trimming_jobs_weight_balance         : 使用原料 − 出来高 = ロス の整合性

commit;

-- 確認：現在の制約を再表示する
select conname, pg_get_constraintdef(oid) as 定義
from pg_constraint
where conrelid='public.trimming_jobs'::regclass
  and contype='c'
order by conname;
