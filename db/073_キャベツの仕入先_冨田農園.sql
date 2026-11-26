/*
073_キャベツの仕入先_冨田農園.sql（v1.199-c170）

困っていたこと（2026-11-26 石岡）：
  キャベツの仕入先は「冨田農園」、単協は「ヴィポート」なのに、仕入先に「ヴィポート」「ヴイポート」と入れてしまう人が多い。
直したこと：
  ・石岡のQRロット（qr_lots）で、品目名に「キャベツ」を含み、仕入先が ヴィポート／ヴイポート（半角・空白・長音なしも同じ）または「富田農園」のものは、
    保存するときに自動で 仕入先＝冨田農園、単協＝ヴィポート にする（トリガー seika_supplier_fix_v1199c170）。仕入先が冨田農園で単協が空のときも単協＝ヴィポート。
  ・いま登録してあるもの（石岡のロット・本社に送ったロット・下処理で使ったロットの記録・ロットの操作履歴）も同じように直す。
前提：今までの番号を実行済みであること。何度実行しても同じ結果になります。
元に戻すとき：drop trigger if exists seika_supplier_fix_v1199c170 on public.qr_lots; drop function if exists public.seika_supplier_fix_v1199c170(); drop function if exists public.seika_supplier_norm_v1199c170(text, text, text);
  （直したデータは戻りません）
*/
begin;

-- 仕入先・単協の直し方（キャベツ×ヴィポート → 冨田農園／ヴィポート）。返すのは [仕入先, 単協]
create or replace function public.seika_supplier_norm_v1199c170(p_item text, p_supplier text, p_coop text)
returns text[]
language sql
immutable
set search_path to 'pg_catalog'
as $n$
  select case
    when coalesce(p_item, '') like '%キャベツ%'
     and (regexp_replace(normalize(coalesce(p_supplier, ''), NFKC), '\s', '', 'g') ~ '^ヴ[イィ]ポー?ト$'
          or regexp_replace(normalize(coalesce(p_supplier, ''), NFKC), '\s', '', 'g') in ('富田農園', '冨田農園'))
      then array['冨田農園', 'ヴィポート']
    else array[p_supplier, p_coop]
  end;
$n$;

create or replace function public.seika_supplier_fix_v1199c170()
returns trigger
language plpgsql
set search_path to 'pg_catalog','public'
as $t$
declare x text[];
begin
  x := public.seika_supplier_norm_v1199c170(new.item_name, new.supplier, new.cooperative_name);
  new.supplier := x[1];
  new.cooperative_name := x[2];
  return new;
end
$t$;
drop trigger if exists seika_supplier_fix_v1199c170 on public.qr_lots;
create trigger seika_supplier_fix_v1199c170 before insert or update of supplier, cooperative_name, item_name on public.qr_lots
  for each row execute function public.seika_supplier_fix_v1199c170();

-- いま登録してあるものを直す（石岡のロットは書き込みの確認があるので、この中だけ管理者として動かす）
select set_config('request.jwt.claims', '{"sub":"58b4e90d-43cf-48ad-970f-ef1a884467dd","role":"authenticated"}', true);
update public.qr_lots set supplier = (public.seika_supplier_norm_v1199c170(item_name, supplier, cooperative_name))[1],
                          cooperative_name = (public.seika_supplier_norm_v1199c170(item_name, supplier, cooperative_name))[2]
 where (supplier, cooperative_name) is distinct from
       ((public.seika_supplier_norm_v1199c170(item_name, supplier, cooperative_name))[1], (public.seika_supplier_norm_v1199c170(item_name, supplier, cooperative_name))[2]);
update public.qr_lot_movements set supplier = (public.seika_supplier_norm_v1199c170(item_name, supplier, cooperative_name))[1],
                                   cooperative_name = (public.seika_supplier_norm_v1199c170(item_name, supplier, cooperative_name))[2]
 where (supplier, cooperative_name) is distinct from
       ((public.seika_supplier_norm_v1199c170(item_name, supplier, cooperative_name))[1], (public.seika_supplier_norm_v1199c170(item_name, supplier, cooperative_name))[2]);
update public.hq_lots_v1400 set supplier = (public.seika_supplier_norm_v1199c170(item_name, supplier, cooperative_name))[1],
                                cooperative_name = (public.seika_supplier_norm_v1199c170(item_name, supplier, cooperative_name))[2]
 where (supplier, cooperative_name) is distinct from
       ((public.seika_supplier_norm_v1199c170(item_name, supplier, cooperative_name))[1], (public.seika_supplier_norm_v1199c170(item_name, supplier, cooperative_name))[2]);
update public.trimming_job_lots set supplier = (public.seika_supplier_norm_v1199c170(item_name, supplier, null))[1]
 where supplier is distinct from (public.seika_supplier_norm_v1199c170(item_name, supplier, null))[1];

commit;

-- ===== 確認（OK なら成功） =====
select
  (select case when exists (select 1 from pg_trigger where tgname = 'seika_supplier_fix_v1199c170' and tgrelid = 'public.qr_lots'::regclass) then 'OK' else 'NG' end) as "自動で冨田農園にする",
  (select case when not exists (select 1 from public.qr_lots where item_name like '%キャベツ%' and supplier !~ '冨田農園' and regexp_replace(normalize(coalesce(supplier,''), NFKC), '\s', '', 'g') ~ '^(ヴ[イィ]ポー?ト|富田農園)$') then 'OK' else 'NG' end) as "いまのロットを直した",
  (select count(*) from public.qr_lots where supplier = '冨田農園') as "冨田農園のロット数";
