-- v1.199-c71 月末棚卸し：規格別ロットの確定エラー修正
-- 原因：規格ごとの「帳簿−実数」の差が、その規格の今の残りより大きいとき、
--       規格の数は0で止まるのに、ロット全体はそのまま減っていたため、合計チェックで確定が止まっていた。
-- 修正：ロット全体を減らす量も、規格が実際に減らせる量にそろえる（規格なしのロットと同じく0で止まる）。
-- 何度実行しても同じ結果になります。
begin;

create or replace function public.apply_month_end_grade_adjustment_v1300(p_qr_key text, p_grade text, p_operation_id text,
  p_target_month text, p_as_of_date text, p_book_qty numeric, p_actual_qty numeric, p_reason text, p_memo text,
  p_session_id text, p_count_no text)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public'
as $f$
declare
  v_lot public.qr_lots%rowtype;
  v_cur numeric;
  v_diff numeric;
  v_eff numeric;
  v_memo text;
  v_deltas jsonb;
  v_ans jsonb;
begin
  perform public.seika_require_role_v1240(array['admin','worker']);
  if p_book_qty is null or p_actual_qty is null then
    raise exception '月末棚卸しQR調整データが不正です' using errcode = '22023';
  end if;
  select * into v_lot from public.qr_lots where qr_key = p_qr_key for update;
  if not found then
    raise exception 'QRロットが見つかりません' using errcode = 'P0002';
  end if;
  select current_qty into v_cur from public.qr_lot_grades_v1300 where lot_id = v_lot.id and grade = btrim(coalesce(p_grade, '')) for update;
  if not found then
    raise exception 'このロットに規格「%」はありません', p_grade using errcode = '22023';
  end if;
  v_diff := p_actual_qty - p_book_qty;
  v_eff := greatest(v_diff, -coalesce(v_cur, 0));
  v_memo := '規格 ' || btrim(p_grade);
  if v_eff <> v_diff then
    v_memo := v_memo || ' / 棚卸し表の帳簿は' || trim(to_char(p_book_qty, 'FM999999990.####'), '.')
      || '。規格の残り' || trim(to_char(coalesce(v_cur, 0), 'FM999999990.####'), '.') || 'だけ減らしました';
  end if;
  v_memo := btrim(v_memo || coalesce(' / ' || nullif(btrim(coalesce(p_memo, '')), ''), ''));
  v_ans := public.v188_apply_month_end_qr_adjustment(p_qr_key, p_operation_id, p_target_month, p_as_of_date,
             p_actual_qty - v_eff, p_actual_qty, p_reason, v_memo, p_session_id, p_count_no);
  if coalesce((v_ans->>'ok')::boolean, false)
     and not coalesce((v_ans->>'idempotent')::boolean, false)
     and not coalesce((v_ans->>'skipped')::boolean, false) then
    v_deltas := jsonb_build_array(jsonb_build_object('grade', btrim(p_grade), 'delta', v_eff));
    update public.qr_lot_grades_v1300
       set current_qty = current_qty + v_eff, updated_at = now()
     where lot_id = v_lot.id and grade = btrim(p_grade);
    update public.qr_lot_movements
       set operation_meta = coalesce(operation_meta, '{}'::jsonb) || jsonb_build_object('grades', v_deltas)
     where operation_id::text = p_operation_id;
  end if;
  return v_ans;
end
$f$;

revoke all on function public.apply_month_end_grade_adjustment_v1300(text, text, text, text, text, numeric, numeric, text, text, text, text) from public, anon;
grant execute on function public.apply_month_end_grade_adjustment_v1300(text, text, text, text, text, numeric, numeric, text, text, text, text) to authenticated, service_role;

commit;

-- 確認：1行「OK」なら成功です
select '月末棚卸し：規格別ロットの減らし方' as 確認項目,
       case when exists (
         select 1 from pg_proc
          where proname = 'apply_month_end_grade_adjustment_v1300'
            and pg_get_functiondef(oid) like '%v_eff := greatest(v_diff%'
       ) then 'OK' else '要確認' end as 判定;
