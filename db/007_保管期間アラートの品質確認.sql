-- 007_保管期間アラートの品質確認.sql
-- 目的：QRロット一覧の「保管期間アラート（5段階）」で、期限に達したロット（要品質確認）を
--       社員が実物確認したとき、その記録を残す。記録はその日（日本時間）のあいだだけ有効。
-- 内容：確認記録の表と、記録を保存する関数を作る。
--       保存できるのは管理者・青果社員だけ。記録者はログインしている本人で自動的に記録する。
-- ・保管期間（品目ごとの日数）はアプリ側で持つので、品目の表は変更しません。
-- ・何度実行しても同じ結果になります。
begin;

create table if not exists public.qr_lot_storage_checks_v1250(
  id uuid primary key default gen_random_uuid(),
  lot_id uuid not null references public.qr_lots(id) on delete cascade,
  check_date date not null,
  checked_by text not null,
  checked_by_name text not null,
  note text not null default '',
  created_at timestamptz not null default now(),
  unique(lot_id, check_date)
);
create index if not exists qr_lot_storage_checks_v1250_date_idx on public.qr_lot_storage_checks_v1250(check_date);

alter table public.qr_lot_storage_checks_v1250 enable row level security;
revoke all on public.qr_lot_storage_checks_v1250 from public, anon, authenticated;
grant select on public.qr_lot_storage_checks_v1250 to authenticated;
grant all on public.qr_lot_storage_checks_v1250 to service_role;
drop policy if exists qr_lot_storage_checks_v1250_read on public.qr_lot_storage_checks_v1250;
create policy qr_lot_storage_checks_v1250_read on public.qr_lot_storage_checks_v1250
  for select to authenticated using (true);

create or replace function public.confirm_qr_lot_storage_check_v1250(p_lot_id uuid, p_note text default '')
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public'
as $f$
declare
  v_profile public.profiles%rowtype;
  v_today date := (now() at time zone 'Asia/Tokyo')::date;
begin
  perform public.seika_require_role_v1240(array['admin','worker']);
  select * into v_profile from public.profiles where id = auth.uid() and active limit 1;
  if v_profile.id is null then
    raise exception 'ログインが必要です' using errcode = '42501';
  end if;
  if not exists (select 1 from public.qr_lots where id = p_lot_id and active) then
    return jsonb_build_object('ok', false, 'message', 'ロットが見つかりません');
  end if;
  insert into public.qr_lot_storage_checks_v1250(lot_id, check_date, checked_by, checked_by_name, note)
  values (p_lot_id, v_today, v_profile.legacy_user_id, v_profile.display_name, coalesce(p_note, ''))
  on conflict (lot_id, check_date) do update
    set checked_by = excluded.checked_by,
        checked_by_name = excluded.checked_by_name,
        note = excluded.note,
        created_at = now();
  return jsonb_build_object('ok', true, 'check_date', v_today, 'checked_by_name', v_profile.display_name);
end
$f$;
revoke all on function public.confirm_qr_lot_storage_check_v1250(uuid, text) from public, anon;
grant execute on function public.confirm_qr_lot_storage_check_v1250(uuid, text) to authenticated, service_role;

commit;

-- 確認：2行とも「OK」なら成功です
select '品質確認の記録表' as 確認項目,
       case when to_regclass('public.qr_lot_storage_checks_v1250') is not null then 'OK' else '要確認' end as 判定
union all
select '品質確認を保存する関数',
       case when exists (select 1 from pg_proc where proname = 'confirm_qr_lot_storage_check_v1250') then 'OK' else '要確認' end;
