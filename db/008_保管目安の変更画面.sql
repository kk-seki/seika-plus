-- 008_保管目安の変更画面.sql
-- 目的：品目ごとの保管目安（日数）を、アプリの「QR在庫管理 → 保管目安の設定」から変更できるようにする。
-- 内容：保管目安の表を作り、現在の目安（指定どおりの日数）を初期値として入れる。
--       変更・追加・削除できるのは管理者・青果社員だけ。変更した人はログイン本人で自動記録する。
-- ・先に 007_保管期間アラートの品質確認.sql を実行しておいてください。
-- ・初期値は表が空のときだけ入れます。何度実行しても、画面で変更・追加・削除した内容は上書きしません。
begin;

create table if not exists public.qr_storage_limits_v1250(
  item_name text primary key,
  limit_days integer not null check (limit_days between 1 and 365),
  sort_order integer not null default 0,
  updated_by text not null default '',
  updated_by_name text not null default '',
  updated_at timestamptz not null default now()
);
alter table public.qr_storage_limits_v1250 enable row level security;
revoke all on public.qr_storage_limits_v1250 from public, anon, authenticated;
grant select on public.qr_storage_limits_v1250 to authenticated;
grant all on public.qr_storage_limits_v1250 to service_role;
drop policy if exists qr_storage_limits_v1250_read on public.qr_storage_limits_v1250;
create policy qr_storage_limits_v1250_read on public.qr_storage_limits_v1250
  for select to authenticated using (true);

insert into public.qr_storage_limits_v1250(item_name, limit_days, sort_order)
select v.item_name, v.limit_days, v.sort_order from (values
  ('じゃがいも',30,10),
  ('牛蒡',30,20),
  ('玉葱',20,30),
  ('さつまいも',20,40),
  ('南瓜',14,50),
  ('レモン',14,60),
  ('長葱',7,70),
  ('人参',7,80),
  ('大根',7,90),
  ('カット大根',7,100),
  ('葉付き大根',7,110),
  ('かぶ',7,120),
  ('レンコン',7,130),
  ('キャベツ',7,140),
  ('紫キャベツ',7,150),
  ('白菜',7,160),
  ('長芋',7,170),
  ('里芋',7,180),
  ('ぶなしめじ',7,190),
  ('まいたけ',7,200),
  ('しいたけ',7,210),
  ('エリンギ',7,220),
  ('ピーマン',7,230),
  ('とんがりピーマン',7,240),
  ('赤ピーマン',7,250),
  ('赤パプリカ',7,260),
  ('黄パプリカ',7,270),
  ('ししとう',7,280),
  ('ズッキーニ',7,290),
  ('ゴーヤ',7,300),
  ('胡瓜',5,310),
  ('ミニトマト',5,320),
  ('トマト',5,330),
  ('レタス',5,340),
  ('ロメインレタス',5,350),
  ('グリーンリーフ',5,360),
  ('サニーレタス',5,370),
  ('ほうれん草',5,380),
  ('小松菜',5,390),
  ('わさび菜',5,400),
  ('水菜',5,410),
  ('春菊',5,420),
  ('なす',5,430),
  ('セロリ',5,440),
  ('ニラ',5,450),
  ('青梗菜',5,460),
  ('小葱',4,470),
  ('青葱',4,480),
  ('みつ葉',3,490),
  ('大葉',3,500),
  ('もやし',3,510),
  ('皮むき玉葱',3,520),
  ('皮むき牛蒡',3,530)
) as v(item_name, limit_days, sort_order)
where not exists (select 1 from public.qr_storage_limits_v1250);

create or replace function public.save_qr_storage_limit_v1250(p_item_name text, p_limit_days integer, p_old_name text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public'
as $f$
declare
  v_profile public.profiles%rowtype;
  v_name text := btrim(coalesce(p_item_name, ''));
  v_old text := nullif(btrim(coalesce(p_old_name, '')), '');
  v_sort integer;
begin
  perform public.seika_require_role_v1240(array['admin','worker']);
  select * into v_profile from public.profiles where id = auth.uid() and active limit 1;
  if v_profile.id is null then
    raise exception 'ログインが必要です' using errcode = '42501';
  end if;
  if v_name = '' then
    return jsonb_build_object('ok', false, 'message', '品目名を入力してください');
  end if;
  if p_limit_days is null or p_limit_days < 1 or p_limit_days > 365 then
    return jsonb_build_object('ok', false, 'message', '日数は1〜365の整数で入力してください');
  end if;
  if v_old is not null and v_old <> v_name then
    if exists (select 1 from public.qr_storage_limits_v1250 where item_name = v_name) then
      return jsonb_build_object('ok', false, 'message', '同じ品目名がすでに登録されています');
    end if;
    update public.qr_storage_limits_v1250
       set item_name = v_name, limit_days = p_limit_days,
           updated_by = v_profile.legacy_user_id, updated_by_name = v_profile.display_name, updated_at = now()
     where item_name = v_old;
    if found then
      return jsonb_build_object('ok', true, 'item_name', v_name, 'limit_days', p_limit_days);
    end if;
  end if;
  select coalesce(max(sort_order), 0) + 10 into v_sort from public.qr_storage_limits_v1250;
  insert into public.qr_storage_limits_v1250(item_name, limit_days, sort_order, updated_by, updated_by_name)
  values (v_name, p_limit_days, v_sort, v_profile.legacy_user_id, v_profile.display_name)
  on conflict (item_name) do update
    set limit_days = excluded.limit_days,
        updated_by = excluded.updated_by,
        updated_by_name = excluded.updated_by_name,
        updated_at = now();
  return jsonb_build_object('ok', true, 'item_name', v_name, 'limit_days', p_limit_days);
end
$f$;

create or replace function public.delete_qr_storage_limit_v1250(p_item_name text)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public'
as $f$
begin
  perform public.seika_require_role_v1240(array['admin','worker']);
  if not exists (select 1 from public.profiles where id = auth.uid() and active) then
    raise exception 'ログインが必要です' using errcode = '42501';
  end if;
  delete from public.qr_storage_limits_v1250 where item_name = btrim(coalesce(p_item_name, ''));
  return jsonb_build_object('ok', found);
end
$f$;

revoke all on function public.save_qr_storage_limit_v1250(text, integer, text) from public, anon;
revoke all on function public.delete_qr_storage_limit_v1250(text) from public, anon;
grant execute on function public.save_qr_storage_limit_v1250(text, integer, text) to authenticated, service_role;
grant execute on function public.delete_qr_storage_limit_v1250(text) to authenticated, service_role;

commit;

-- 確認：3行とも「OK」、品目数が 53 以上なら成功です
select '保管目安の表' as 確認項目,
       case when to_regclass('public.qr_storage_limits_v1250') is not null then 'OK' else '要確認' end as 判定,
       (select count(*) from public.qr_storage_limits_v1250)::text as 品目数
union all
select '保管目安を保存する関数',
       case when exists (select 1 from pg_proc where proname = 'save_qr_storage_limit_v1250') then 'OK' else '要確認' end, ''
union all
select '保管目安を削除する関数',
       case when exists (select 1 from pg_proc where proname = 'delete_qr_storage_limit_v1250') then 'OK' else '要確認' end, '';
