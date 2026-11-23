/*
064_営業担当の客先.sql（v1.199-c154）

目的：
  「出荷予定と確定のちがい」（c153）を、仕入れ担当者だけでなく営業担当者にも送れるようにする。
  客先ごとの営業担当を「客先名に含まれる言葉 → 担当者」で持つ（例：「虎昭」→ 斎藤 大明。虎昭産業 もおか工場・茨城工場・館林工場がまとめて当たる）。
  1. 営業担当の決まりの表（ship_sales_customers_v1199c154）。初期値は「07_営業仕入れ担当者カード（2026.5月版）」の客先別営業担当の27件。
  2. 読む関数（list_sales_customers_v1199c154）：決まりの一覧と、仕入れ担当者・営業担当者（有効なアカウント）の一覧を返す。
  3. 変える関数（save_sales_customer_v1199c154・delete_sales_customer_v1199c154）：管理者・青果社員だけ。

権限：読む＝管理者・青果社員・仕入れ担当者・営業担当者・事務員／変える＝管理者・青果社員。
SQLを実行しただけでは、在庫・QRロット・伝票・出荷予定・確定・アプリのデータは変わりません。何度実行しても同じ結果になります（初期値は、同じ言葉がまだないときだけ入れます）。

元に戻すとき：
  drop function if exists public.list_sales_customers_v1199c154();
  drop function if exists public.save_sales_customer_v1199c154(bigint,text,uuid);
  drop function if exists public.delete_sales_customer_v1199c154(bigint);
  drop table if exists public.ship_sales_customers_v1199c154;
*/
begin;

create table if not exists public.ship_sales_customers_v1199c154(
  id bigserial primary key,
  keyword text not null unique,           -- 客先名に含まれる言葉（空白を除いて比べる）
  staff_profile_id uuid references public.profiles(id),
  note text not null default '',
  updated_by_name text not null default '',
  updated_at timestamptz not null default now()
);

alter table public.ship_sales_customers_v1199c154 enable row level security;
revoke all on public.ship_sales_customers_v1199c154 from public, anon, authenticated;

/* 初期値：07_営業仕入れ担当者カード（2026.5月版）の客先別営業担当 */
insert into public.ship_sales_customers_v1199c154(keyword, staff_profile_id, note, updated_by_name)
select k, (select id from public.profiles where display_name = n and active order by role limit 1), '2026.5月版の担当者カード', '初期値'
from (values
  ('虎昭','斎藤 大明'),('デリカシェフ','斎藤 大明'),('全農青果','斎藤 大明'),('KTR','斎藤 大明'),('青空農園','斎藤 大明'),
  ('ファームアライアンス','斎藤 大明'),('ブレスト','斎藤 大明'),('トラサンデリカ','斎藤 大明'),
  ('プライムデリカ','斎藤 綾香'),('成城石井','斎藤 綾香'),('わらべや','斎藤 綾香'),
  ('タマムラデリカ','蕨岡 愛姫'),('麺の杜','蕨岡 愛姫'),('フジフーズ','蕨岡 愛姫'),('北燦食品','蕨岡 愛姫'),('ファーストフーズ','蕨岡 愛姫'),
  ('武蔵野千葉','蕨岡 愛姫'),('ニッセーデリカ','蕨岡 愛姫'),('東部アシード','蕨岡 愛姫'),
  ('美野里デリカ','坂本 美穂'),
  ('日本デリカ','吉田 智彦'),('デリカフーズ','吉田 智彦'),('旭物産','吉田 智彦'),('米川商事','吉田 智彦'),('靖光','吉田 智彦'),
  ('アグリフード千葉','吉田 智彦'),('永野青果','吉田 智彦')
) v(k, n)
on conflict (keyword) do nothing;

create or replace function public.list_sales_customers_v1199c154()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $f$
begin
  perform public.seika_require_role_v1240(array['admin','worker','buyer','sales','clerk']);
  return jsonb_build_object('ok', true,
    'rules', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'keyword', r.keyword, 'staff_profile_id', r.staff_profile_id,
        'staff_name', coalesce(p.display_name, ''), 'note', r.note, 'updated_by_name', r.updated_by_name, 'updated_at', r.updated_at)
        order by coalesce(p.display_name, 'ん'), r.keyword)
      from public.ship_sales_customers_v1199c154 r left join public.profiles p on p.id = r.staff_profile_id), '[]'::jsonb),
    'staff', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'display_name', p.display_name, 'role', p.role,
        'legacy_user_id', p.legacy_user_id) order by p.role, p.display_name)
      from public.profiles p where p.active and p.role in ('buyer','sales')), '[]'::jsonb));
end
$f$;

create or replace function public.save_sales_customer_v1199c154(p_id bigint, p_keyword text, p_staff uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $f$
declare v_name text; v_kw text := btrim(regexp_replace(coalesce(p_keyword,''), '\s+', ' ', 'g')); v_id bigint;
begin
  perform public.seika_require_role_v1240(array['admin','worker']);
  if v_kw = '' then raise exception '客先名に含まれる言葉を入れてください' using errcode = '22023'; end if;
  if p_staff is not null and not exists (select 1 from public.profiles where id = p_staff and active and role in ('buyer','sales')) then
    raise exception '担当者は、有効な仕入れ担当者か営業担当者から選んでください' using errcode = '22023';
  end if;
  select coalesce(display_name,'') into v_name from public.profiles where id = auth.uid();
  if p_id is null then
    insert into public.ship_sales_customers_v1199c154(keyword, staff_profile_id, updated_by_name, updated_at)
    values (v_kw, p_staff, coalesce(v_name,''), now())
    on conflict (keyword) do update set staff_profile_id = excluded.staff_profile_id, updated_by_name = excluded.updated_by_name, updated_at = now()
    returning id into v_id;
  else
    update public.ship_sales_customers_v1199c154 set keyword = v_kw, staff_profile_id = p_staff, updated_by_name = coalesce(v_name,''), updated_at = now()
    where id = p_id returning id into v_id;
    if v_id is null then raise exception 'この決まりは見つかりません（ほかの人が消した可能性があります）' using errcode = '22023'; end if;
  end if;
  return jsonb_build_object('ok', true, 'id', v_id);
exception when unique_violation then
  raise exception '同じ言葉の決まりがすでにあります' using errcode = '22023';
end
$f$;

create or replace function public.delete_sales_customer_v1199c154(p_id bigint)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $f$
begin
  perform public.seika_require_role_v1240(array['admin','worker']);
  delete from public.ship_sales_customers_v1199c154 where id = p_id;
  return jsonb_build_object('ok', true);
end
$f$;

do $block$
declare f text;
begin
  foreach f in array array['public.list_sales_customers_v1199c154()','public.save_sales_customer_v1199c154(bigint,text,uuid)',
                           'public.delete_sales_customer_v1199c154(bigint)'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $block$;

commit;

-- ===== 確認（1行で、どちらも OK なら成功） =====
select
  (select case when count(*) >= 27 then 'OK' else 'NG' end from public.ship_sales_customers_v1199c154 where staff_profile_id is not null) as "営業担当の決まり",
  (select case when count(*) = 3 then 'OK' else 'NG' end from pg_proc
    where proname in ('list_sales_customers_v1199c154','save_sales_customer_v1199c154','delete_sales_customer_v1199c154')) as "営業担当の関数";
