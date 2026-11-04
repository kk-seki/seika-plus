-- v1.199-c86 伝票：大型容器の総重量・入数をあとから入れる・直す
-- 目的：QR出庫した分の「総重量（kg）」「入数（例：12kg）」を、伝票の画面からあとで入力・修正できるようにする。
--  ・入れた値は伝票（印刷・Excel）だけに使います。石岡のQR在庫・在庫表・分析の数字は変わりません。
--  ・出庫のときに入れた総重量・入数は出庫の記録に残るので、このSQLがなくても伝票に出ます。
--    このSQLは「あとから直す」ために必要です。
--  何度実行しても同じ結果になります。既存のデータは変わりません。
begin;

create table if not exists public.qr_slip_adjust_v1199c86 (
  movement_id uuid primary key,
  total_kg numeric check (total_kg is null or total_kg > 0),
  pack text,
  updated_by uuid,
  updated_by_name text,
  updated_at timestamptz not null default now()
);
alter table public.qr_slip_adjust_v1199c86 enable row level security;
drop policy if exists qr_slip_adjust_v1199c86_read on public.qr_slip_adjust_v1199c86;
create policy qr_slip_adjust_v1199c86_read on public.qr_slip_adjust_v1199c86 for select to authenticated using (public.is_active_user());
revoke all on public.qr_slip_adjust_v1199c86 from anon;
grant select on public.qr_slip_adjust_v1199c86 to authenticated;

create or replace function public.qr_slip_adjust_save_v1199c86(p_movement_id uuid, p_total_kg numeric, p_pack text)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles%rowtype; v_pack text := nullif(btrim(coalesce(p_pack,'')),'');
begin
  v := public.seika_v1136_require_roles(array['admin','worker']);
  if not exists (select 1 from public.qr_lot_movements where id = p_movement_id and movement_type = '出庫') then
    raise exception 'この出庫が見つかりません。画面を読み込み直してください';
  end if;
  if p_total_kg is not null and (p_total_kg <= 0 or p_total_kg >= 100000) then raise exception '総重量は0より大きい数字で入れてください'; end if;
  if p_total_kg is null and v_pack is null then
    delete from public.qr_slip_adjust_v1199c86 where movement_id = p_movement_id;
  else
    insert into public.qr_slip_adjust_v1199c86(movement_id, total_kg, pack, updated_by, updated_by_name, updated_at)
    values (p_movement_id, p_total_kg, v_pack, v.id, v.display_name, now())
    on conflict (movement_id) do update set total_kg = excluded.total_kg, pack = excluded.pack,
      updated_by = excluded.updated_by, updated_by_name = excluded.updated_by_name, updated_at = now();
  end if;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.qr_slip_adjust_save_v1199c86(uuid,numeric,text) from public, anon;
grant execute on function public.qr_slip_adjust_save_v1199c86(uuid,numeric,text) to authenticated, service_role;

commit;
notify pgrst, 'reload schema';

-- 確認：2行とも「OK」なら成功です
select '総重量・入数を残す場所' as 確認項目,
       case when to_regclass('public.qr_slip_adjust_v1199c86') is not null then 'OK' else '要確認' end as 判定
union all
select '総重量・入数を保存する仕組み',
       case when to_regprocedure('public.qr_slip_adjust_save_v1199c86(uuid,numeric,text)') is not null then 'OK' else '要確認' end;
