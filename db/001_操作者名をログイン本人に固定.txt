-- 001_操作者名をログイン本人に固定.sql
-- 改善5（認証の第3段階）
-- QRロット・QR入出庫・QRスキャン記録・製造日報・品質評価を新しく保存するとき、
-- 「誰が操作したか」をアプリから送られた名前ではなく、ログインしている本人の情報で上書きします。
-- ・ログインしていない操作（SQLエディタでの手作業など）は今までどおりで、何も変えません。
-- ・既に保存されている記録は変更しません。
-- ・何度実行しても同じ結果になります。
-- ・元に戻すときは、ファイル末尾の「切り戻し」を実行します。

create or replace function public.seika_stamp_operator_v1230()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','public'
as $f$
declare
  v_uid uuid := auth.uid();
  v_p public.profiles%rowtype;
begin
  if v_uid is null then
    return new;
  end if;
  select * into v_p from public.profiles where id = v_uid and active limit 1;
  if not found then
    return new;
  end if;

  if tg_table_name in ('qr_lots','qr_lot_movements','qr_scan_logs') then
    new.user_id   := v_p.legacy_user_id;
    new.user_name := v_p.display_name;
  elsif tg_table_name = 'trimming_jobs' then
    new.created_by      := v_uid;
    new.created_by_name := v_p.display_name;
  elsif tg_table_name = 'qr_quality_evaluations' then
    new.evaluated_by      := v_uid;
    new.evaluated_by_name := v_p.display_name;
  end if;
  return new;
end
$f$;

revoke all on function public.seika_stamp_operator_v1230() from public, anon, authenticated;

drop trigger if exists seika_stamp_operator_v1230 on public.qr_lots;
create trigger seika_stamp_operator_v1230 before insert on public.qr_lots
  for each row execute function public.seika_stamp_operator_v1230();

drop trigger if exists seika_stamp_operator_v1230 on public.qr_lot_movements;
create trigger seika_stamp_operator_v1230 before insert on public.qr_lot_movements
  for each row execute function public.seika_stamp_operator_v1230();

drop trigger if exists seika_stamp_operator_v1230 on public.qr_scan_logs;
create trigger seika_stamp_operator_v1230 before insert on public.qr_scan_logs
  for each row execute function public.seika_stamp_operator_v1230();

drop trigger if exists seika_stamp_operator_v1230 on public.trimming_jobs;
create trigger seika_stamp_operator_v1230 before insert on public.trimming_jobs
  for each row execute function public.seika_stamp_operator_v1230();

drop trigger if exists seika_stamp_operator_v1230 on public.qr_quality_evaluations;
create trigger seika_stamp_operator_v1230 before insert on public.qr_quality_evaluations
  for each row execute function public.seika_stamp_operator_v1230();

-- 確認：5行（5つの表）と出れば完了です
select c.relname as 対象の表, t.tgname as 仕組み
from pg_trigger t join pg_class c on c.oid = t.tgrelid
where t.tgname = 'seika_stamp_operator_v1230'
order by 1;

-- ===== 切り戻し（問題があったときだけ、下の6行の先頭の「-- 」を消して実行）
-- drop trigger if exists seika_stamp_operator_v1230 on public.qr_lots;
-- drop trigger if exists seika_stamp_operator_v1230 on public.qr_lot_movements;
-- drop trigger if exists seika_stamp_operator_v1230 on public.qr_scan_logs;
-- drop trigger if exists seika_stamp_operator_v1230 on public.trimming_jobs;
-- drop trigger if exists seika_stamp_operator_v1230 on public.qr_quality_evaluations;
-- drop function if exists public.seika_stamp_operator_v1230();
