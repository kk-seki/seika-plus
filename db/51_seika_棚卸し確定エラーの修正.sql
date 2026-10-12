-- 51 棚卸し確定エラー（operator does not exist: uuid = text）の修正
-- 原因：v188_apply_month_end_qr_adjustment の二重実行チェックで、
--       qr_lot_movements.operation_id（uuid型）と引数 p_operation_id（text型）をそのまま比較していた。
--       QRロットに差異がある棚卸しを確定すると、最初のQRロットの反映前に必ず失敗する。
-- 対応：該当の比較1か所だけを operation_id::text = p_operation_id に書き換えます（ほかの処理は変更しません）。
do $$
declare
  v_def text;
  v_pat text := '(\m(?:[a-z_]+\.)?operation_id)\s*=\s*p_operation_id\M';
  v_new text;
begin
  v_def := pg_get_functiondef('public.v188_apply_month_end_qr_adjustment(text,text,text,text,numeric,numeric,text,text,text,text)'::regprocedure);
  if v_def !~ v_pat then
    if position('operation_id::text = p_operation_id' in v_def) > 0 then
      raise notice '修正済みです（変更なし）';
      return;
    end if;
    raise exception '該当箇所が見つかりません。この結果をそのまま送ってください';
  end if;
  v_new := regexp_replace(v_def, v_pat, '\1::text = p_operation_id', 'g');
  execute v_new;
  raise notice '月末棚卸しQR調整を修正しました';
end $$;

-- 確認：「修正後」が true なら完了
select position('operation_id::text = p_operation_id' in
         pg_get_functiondef('public.v188_apply_month_end_qr_adjustment(text,text,text,text,numeric,numeric,text,text,text,text)'::regprocedure)) > 0 as 修正後;
