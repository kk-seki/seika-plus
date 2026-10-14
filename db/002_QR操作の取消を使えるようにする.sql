-- 002 QR操作の取消を使えるようにする
-- 目的：qr_lot_movements の区分に「取消」を追加する。
--       取消の仕組み（cancel_qr_lot_operation）はすでにあるが、区分の制約に「取消」が無く、保存できなかった。
-- 影響：制約の許可リストに1語足すだけ。既存の行・関数・権限は変更しない。
begin;

alter table public.qr_lot_movements
  drop constraint if exists qr_lot_movements_movement_type_check;

alter table public.qr_lot_movements
  add constraint qr_lot_movements_movement_type_check
  check (movement_type = any (array[
    '棚卸し調整増','棚卸し調整減','入庫','出庫','廃棄',
    '出庫・調整減','入庫・調整増','差分なし','調整',
    '重量確定','重量更新','ロット情報訂正','取消'
  ]::text[]));

commit;

-- 確認：結果に「取消」が含まれていれば成功
select pg_get_constraintdef(oid) as 区分の制約
from pg_constraint
where conname = 'qr_lot_movements_movement_type_check';
