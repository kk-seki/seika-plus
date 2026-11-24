/*
066_納品先マスタをクラウドに.sql（v1.199-c160）

目的：
  納品先マスタ（出庫先の選択肢・社外の客先）は、これまで各端末の中だけに保存され、クラウドに送られていなかった。
  そのため、追加した出庫先が再読込で消え、端末ごとに中身が違っていた。
  クラウドの表（dest_master_v1199c160）に移し、どの端末でも同じ内容にする。

区分（kind）：
  内＝社内（本社・埼玉・深谷・荻沼など）
  外＝社外の客先（産地報告に入る。group_name＝産地報告のシート）
  販＝外販先（産地報告に入らない社外。旭物産・イバラキ食品など）

初期値：アプリの初期値（社内9件・社外の客先20件）と、外販先5件（旭物産・イバラキ食品・アグリフード千葉・KTR・坂東商会。出庫先に表示する）。
すでに同じ名前があるときは変えません（何度実行しても同じ）。
在庫・QRロット・出庫の記録・伝票・出荷予定は変わりません。

元に戻すとき：
  drop function if exists public.list_dest_master_v1199c160();
  drop function if exists public.save_dest_master_v1199c160(text, jsonb);
  drop function if exists public.delete_dest_master_v1199c160(text);
  drop table if exists public.dest_master_v1199c160;
*/

create table if not exists public.dest_master_v1199c160(
  name text primary key,
  formal text not null default '',
  kind text not null default '内' check (kind in ('内','外','販')),
  group_name text not null default '',
  outbound boolean not null default true,
  weight boolean not null default false,
  active boolean not null default true,
  sort_order integer not null default 1000,
  updated_by_name text not null default '',
  updated_at timestamptz not null default now()
);
alter table public.dest_master_v1199c160 enable row level security;
revoke all on public.dest_master_v1199c160 from public, anon, authenticated;

insert into public.dest_master_v1199c160(name, formal, kind, group_name, outbound, weight, sort_order)
values
  ('本社','',  '内','社内',true,false,1),
  ('埼玉','',  '内','社内',true,false,2),
  ('深谷','',  '内','社内',true,false,3),
  ('社外','',  '内','社内',true,false,4),
  ('荻沼','',  '内','社内',true,false,5),
  ('石岡冷凍','',  '内','社内',true,false,6),
  ('現場作業','',  '内','社内',true,false,7),
  ('その他','',  '内','社内',true,false,8),
  ('廃棄','',  '内','社内',true,false,9),
  ('美野里デリカ','美野里デリカ株式会社','外','美野里D・デリカシェフ',false,false,100),
  ('デリカシェフ 久喜工場','株式会社デリカシェフ 久喜工場','外','美野里D・デリカシェフ',false,false,101),
  ('麺の杜','麺の杜株式会社','外','美野里D・デリカシェフ',false,false,102),
  ('虎昭産業 館林工場','虎昭産業株式会社 館林工場','外','虎昭・タマムラ',false,false,103),
  ('虎昭産業 茨城工場','虎昭産業株式会社 茨城工場','外','虎昭・タマムラ',false,false,104),
  ('虎昭産業 もおか工場','虎昭産業株式会社 もおか工場','外','虎昭・タマムラ',false,false,105),
  ('タマムラデリカ 佐野田沼工場','タマムラデリカ株式会社 佐野田沼工場','外','虎昭・タマムラ',false,false,106),
  ('東部アシード','株式会社東部アシード','外','虎昭・タマムラ',false,false,107),
  ('ティキューシー','株式会社ティキューシー','外','虎昭・タマムラ',false,false,108),
  ('プライムデリカ 相模原工場','プライムデリカ株式会社 相模原工場','外','プライム',false,true,109),
  ('プライムデリカ 相模原第二工場','プライムデリカ株式会社 相模原第二工場','外','プライム',false,true,110),
  ('プライムデリカ 龍ケ崎工場','プライムデリカ株式会社 龍ケ崎工場','外','プライム',false,true,111),
  ('フジフーズ 千葉工場','フジフーズ株式会社 千葉工場','外','フジ・日本デリカ・成城',false,false,112),
  ('日本デリカサービス 八千代工場','株式会社日本デリカサービス 八千代工場','外','フジ・日本デリカ・成城',false,false,113),
  ('成城石井','株式会社成城石井','外','フジ・日本デリカ・成城',false,false,114),
  ('武蔵野 千葉工場','株式会社武蔵野 千葉工場','外','フジ・日本デリカ・成城',false,false,115),
  ('わらべや日洋食品 吉川工場','わらべや日洋食品株式会社 吉川工場','外','フジ・日本デリカ・成城',false,false,116),
  ('わらべや日洋食品 浦和工場','わらべや日洋食品株式会社 浦和工場','外','フジ・日本デリカ・成城',false,false,117),
  ('わらべや日洋食品 茨城工場','わらべや日洋食品株式会社 茨城工場','外','フジ・日本デリカ・成城',false,false,118),
  ('ファーストフーズつくば','株式会社ファーストフーズつくば','外','フジ・日本デリカ・成城',false,false,119),
  ('旭物産','','販','外販先',true,false,200),
  ('イバラキ食品','','販','外販先',true,false,201),
  ('アグリフード千葉','','販','外販先',true,false,202),
  ('KTR','','販','外販先',true,false,203),
  ('坂東商会','','販','外販先',true,false,204)
on conflict (name) do nothing;

/* 読む：ログインしている人なら誰でも（出庫先の選択肢に使う） */
create or replace function public.list_dest_master_v1199c160()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $f$
begin
  if not public.is_active_user() then raise exception 'ログインが必要です' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('name', name, 'formal', formal, 'kind', kind, 'group', group_name,
      'outbound', outbound, 'weight', weight, 'active', active, 'sort', sort_order, 'updated_by_name', updated_by_name, 'updated_at', updated_at)
      order by sort_order, name) from public.dest_master_v1199c160), '[]'::jsonb);
end
$f$;

/* 追加・変更：管理者だけ。p_old_name があればその行を直す（名前の変更も） */
create or replace function public.save_dest_master_v1199c160(p_old_name text, p_row jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $f$
declare
  v_name text := btrim(regexp_replace(coalesce(p_row->>'name',''), '\s+', ' ', 'g'));
  v_kind text := coalesce(nullif(p_row->>'kind',''), '内');
  v_group text := btrim(coalesce(p_row->>'group',''));
  v_by text;
begin
  perform public.seika_require_role_v1240(array['admin']);
  if v_name = '' then raise exception '納品先名を入れてください' using errcode = '22023'; end if;
  if v_kind not in ('内','外','販') then raise exception '区分が正しくありません' using errcode = '22023'; end if;
  if v_group = '' then v_group := case v_kind when '内' then '社内' when '販' then '外販先' else '未分類' end; end if;
  select coalesce(display_name,'') into v_by from public.profiles where id = auth.uid();
  if nullif(btrim(coalesce(p_old_name,'')),'') is null then
    if exists (select 1 from public.dest_master_v1199c160 where name = v_name) then
      raise exception '同じ名前の納品先がすでにあります' using errcode = '22023';
    end if;
    insert into public.dest_master_v1199c160(name, formal, kind, group_name, outbound, weight, active, sort_order, updated_by_name)
    values (v_name, btrim(coalesce(p_row->>'formal','')), v_kind, v_group, coalesce((p_row->>'outbound')::boolean, true),
            coalesce((p_row->>'weight')::boolean, false), coalesce((p_row->>'active')::boolean, true),
            coalesce((select max(sort_order) + 1 from public.dest_master_v1199c160), 1), coalesce(v_by,''));
  else
    if v_name <> p_old_name and exists (select 1 from public.dest_master_v1199c160 where name = v_name) then
      raise exception '同じ名前の納品先がすでにあります' using errcode = '22023';
    end if;
    update public.dest_master_v1199c160 set name = v_name, formal = btrim(coalesce(p_row->>'formal', formal)), kind = v_kind, group_name = v_group,
      outbound = coalesce((p_row->>'outbound')::boolean, outbound), weight = coalesce((p_row->>'weight')::boolean, weight),
      active = coalesce((p_row->>'active')::boolean, active), updated_by_name = coalesce(v_by,''), updated_at = now()
    where name = p_old_name;
    if not found then raise exception 'この納品先は見つかりません（ほかの人が消した可能性があります）' using errcode = '22023'; end if;
  end if;
  return jsonb_build_object('ok', true, 'name', v_name);
end
$f$;

/* 削除：管理者だけ。過去の出庫の記録（出庫先の名前）は残る */
create or replace function public.delete_dest_master_v1199c160(p_name text)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $f$
begin
  perform public.seika_require_role_v1240(array['admin']);
  delete from public.dest_master_v1199c160 where name = p_name;
  return jsonb_build_object('ok', true);
end
$f$;

do $block$
declare f text;
begin
  foreach f in array array['public.list_dest_master_v1199c160()','public.save_dest_master_v1199c160(text,jsonb)',
                           'public.delete_dest_master_v1199c160(text)'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $block$;

-- ===== 確認（どちらも OK なら成功） =====
select
  (select case when count(*) filter (where kind='内') >= 9 and count(*) filter (where kind='販') >= 5 then 'OK' else 'NG' end
     from public.dest_master_v1199c160) as "納品先マスタ",
  (select case when count(*) = 3 then 'OK' else 'NG' end from pg_proc
    where proname in ('list_dest_master_v1199c160','save_dest_master_v1199c160','delete_dest_master_v1199c160')) as "納品先マスタの関数";
