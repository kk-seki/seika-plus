/*
065_標準ケース_トマト類.sql（v1.199-c157）

目的：
  積み込み表で「ケース数だけ」で書かれている行（深谷の「トマト M」「ミニトマトS(日本デリカ)」「グリーンリーフ」）は、
  標準ケースの重さがないため kg が空になり、出荷予定と確定のちがいで比べられていなかった。
  標準ケース（ship_plan_case_std_v1199c140）に3品目を足す。重さは、深谷・埼玉へ出庫しているQRロットの量目
  （トマト 4kg・ミニトマト 3kg・グリーンリーフ 4kg）に合わせた。
  アプリの「品名の読み替え・標準ケース」の画面からも同じことができます。あとから直すときはその画面で直してください。

SQLを実行しただけでは、在庫・QRロット・伝票・出荷予定（保存済みの行）は変わりません。
出荷予定を見るときに「ケース数×標準ケース」で kg を出します。次の自動取り込みでは kg 付きで登録し直されます。
すでに同じ品目の標準ケースがあるときは変えません（何度実行しても同じ）。

元に戻すとき：
  delete from public.ship_plan_case_std_v1199c140 where item_name in ('トマト','ミニトマト','グリーンリーフ') and updated_by_name='c157初期値';
*/
insert into public.ship_plan_case_std_v1199c140(item_name, case_kg, updated_by_name)
values ('トマト', 4, 'c157初期値'), ('ミニトマト', 3, 'c157初期値'), ('グリーンリーフ', 4, 'c157初期値')
on conflict (item_name) do nothing;

-- ===== 確認（OK なら成功） =====
select case when count(*) = 3 then 'OK' else 'NG' end as "標準ケース（トマト・ミニトマト・グリーンリーフ）"
from public.ship_plan_case_std_v1199c140 where item_name in ('トマト','ミニトマト','グリーンリーフ');
