/*
023_本社_使用期限とトレース表.sql（v1.199-c61）
1. 本社の原料の使用期限（本社入荷日から数える）と、NGサイン（傷みの見分け方）を品目ごとに持ちます。
   最初は「原料使用期限・廃棄目安（2026.8.12更新）」の日数を入れます。本社社員・管理者が画面で変えられます。
   同じ品目の別の書き方（例：胡瓜＝きゅうり）も、ここでまとめます。
2. 期限を過ぎた原料を使うときに、確認した人を記録します。
3. 本社の仕入れ価格表で、同じ品目の別の書き方を1行にまとめます。
4. トレース表（ロットの動きの明細）を、ログインしている人なら誰でも作れるようにします。
前提：019・022を実行済みであること。何度実行しても同じ結果になります（画面で変えた日数は上書きしません）。
説明は行頭のハイフン2つを使わない書き方にしています（スマホから貼り付けても壊れないようにするため）。
*/
begin;

create table if not exists public.hq_item_rules_v1600 (
  item_name text primary key,
  limit_days integer check (limit_days is null or limit_days > 0),
  ng_sign text,
  aliases text[] not null default '{}',
  sort_order integer not null default 0,
  updated_by_name text,
  updated_at timestamptz not null default now()
);
insert into public.hq_item_rules_v1600(item_name, limit_days, ng_sign, aliases, sort_order) values
  ('馬鈴薯',30,'軟化、カビ、腐敗臭、発芽、緑化が進みすぎ（品質低下）',array['じゃがいも','じゃが芋','ジャガイモ','ばれいしょ'],1),
  ('南瓜',14,'カビ、腐敗臭、表面または内部が溶ける／崩れる',array['かぼちゃ','カボチャ'],2),
  ('白菜',7,'カビ、黄ばみが急速に進行、表面が溶ける',array['はくさい','ハクサイ'],3),
  ('キャベツ',7,'カビ、黄ばみが急速に進行、表面が溶ける',array['きゃべつ'],4),
  ('長ネギ',7,'表面の溶け、ふやけ（押すと弱くなる／傷みが進む）、カビ、腐敗臭、発生が急に進む・汁が増える',array['長葱','長ねぎ','ねぎ','ネギ','葱'],5),
  ('人参',7,'カビ広がり、腐敗臭、表面が溶ける／崩れる、軟化（押すと潰れる）',array['にんじん','ニンジン','人参（国産）','国産人参'],6),
  ('さつまいも',7,'カビ広がり、腐敗臭、表面が溶ける／崩れる、軟化（押すと潰れる）',array['さつま芋','サツマイモ','薩摩芋'],7),
  ('牛蒡',7,'カビ広がり、腐敗臭、表面が溶ける／崩れる、軟化（押すと潰れる）',array['ごぼう','ゴボウ'],8),
  ('大根',7,'カビ広がり、腐敗臭、表面が溶ける／崩れる、軟化（押すと潰れる）',array['だいこん','ダイコン'],9),
  ('かぶ',7,'カビ広がり、腐敗臭、表面が溶ける／崩れる、軟化（押すと潰れる）',array['カブ','蕪'],10),
  ('ピーマン',7,'果肉の崩れ、カビ、異臭、汁が増えている、極端な変色',array['ぴーまん'],11),
  ('パプリカ',7,'果肉の崩れ、カビ、異臭、汁が増えている、極端な変色',array['ぱぷりか'],12),
  ('ししとう',7,'果肉の崩れ、カビ、異臭、汁が増えている、極端な変色',array['シシトウ','獅子唐'],13),
  ('しめじ',7,'糸を引く、ぬめり、黒ずみが急増、腐敗臭、パック内が液体化',array['ぶなしめじ','シメジ'],14),
  ('えのき',7,'糸を引く、ぬめり、黒ずみが急増、腐敗臭、パック内が液体化',array['えのき茸','エノキ'],15),
  ('舞茸',7,'糸を引く、ぬめり、黒ずみが急増、腐敗臭、パック内が液体化',array['まいたけ','マイタケ'],16),
  ('エリンギ',7,'糸を引く、ぬめり、黒ずみが急増、腐敗臭、パック内が液体化',array['えりんぎ'],17),
  ('きゅうり',5,'果肉の崩れ、カビ、異臭、汁が増えている、極端な変色',array['胡瓜','キュウリ'],18),
  ('なす',5,'果肉の崩れ、カビ、異臭、汁が増えている、極端な変色',array['茄子','ナス','長茄子','長なす'],19),
  ('トマト',5,'果肉の崩れ、カビ、異臭、汁が増えている、極端な変色',array['とまと'],20),
  ('ミニトマト',5,'果肉の崩れ、カビ、異臭、汁が増えている、極端な変色',array['プチトマト'],21),
  ('ほうれん草',5,'葉先、茎のとろけ、黄ばみが急速に進行、汁漏れがある',array['ほうれんそう','ホウレンソウ'],22),
  ('小松菜',5,'葉先、茎のとろけ、黄ばみが急速に進行、汁漏れがある',array['こまつな','コマツナ'],23),
  ('水菜',5,'葉先、茎のとろけ、黄ばみが急速に進行、汁漏れがある',array['みずな','ミズナ'],24),
  ('春菊',5,'葉先、茎のとろけ、黄ばみが急速に進行、汁漏れがある',array['しゅんぎく','シュンギク'],25),
  ('ニラ',5,'葉先、茎のとろけ、黄ばみが急速に進行、汁漏れがある',array['にら','韮'],26),
  ('こねぎ',5,'葉先、茎のとろけ、黄ばみが急速に進行、汁漏れがある',array['小葱','小ねぎ','小ネギ','青葱','青ねぎ'],27),
  ('セロリ',5,'葉先、茎のとろけ、黄ばみが急速に進行、汁漏れがある',array['せろり'],28),
  ('みつば',3,'葉先、茎のとろけ、黄ばみが急速に進行、汁漏れがある',array['みつ葉','三つ葉','ミツバ'],29),
  ('大葉',3,'葉先、茎のとろけ、黄ばみが急速に進行、汁漏れがある',array['青じそ','青紫蘇','おおば'],30),
  ('もやし',3,'葉先、茎のとろけ、黄ばみが急速に進行、汁漏れがある',array['モヤシ'],31),
  ('玉葱',null,null,array['玉ねぎ','たまねぎ','タマネギ'],40)
on conflict (item_name) do nothing;

create table if not exists public.hq_limit_checks_v1600 (
  id uuid primary key default gen_random_uuid(),
  lot_id uuid not null,
  lot_no text,
  item_name text,
  elapsed_days integer,
  limit_days integer,
  action text,
  checked_by_name text,
  created_at timestamptz not null default now()
);

do $$
declare t text;
begin
  foreach t in array array['hq_item_rules_v1600','hq_limit_checks_v1600'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    execute format('create policy %I on public.%I for select to authenticated using (true)', t || '_read', t);
    execute format('revoke all on public.%I from anon, public', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('grant all on public.%I to service_role', t);
  end loop;
end $$;

create or replace function public.hq_save_item_rule_v1600(p_old_name text, p_item_name text, p_limit_days integer, p_ng_sign text, p_aliases text[])
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles; al text[];
begin
  v := public.hq_actor_v1400(array['admin','hq_worker']);
  if btrim(coalesce(p_item_name,'')) = '' then raise exception '品目名を入れてください'; end if;
  if p_limit_days is not null and p_limit_days <= 0 then raise exception '日数は1以上で入れてください'; end if;
  select coalesce(array_agg(distinct btrim(a)) filter (where btrim(a) <> '' and btrim(a) <> btrim(p_item_name)), '{}') into al from unnest(coalesce(p_aliases,'{}')) a;
  if btrim(coalesce(p_old_name,'')) <> '' and btrim(p_old_name) <> btrim(p_item_name) then
    delete from public.hq_item_rules_v1600 where item_name = btrim(p_old_name);
  end if;
  insert into public.hq_item_rules_v1600(item_name, limit_days, ng_sign, aliases, sort_order, updated_by_name)
  values (btrim(p_item_name), p_limit_days, nullif(btrim(coalesce(p_ng_sign,'')),''), al,
    (select coalesce(max(sort_order),0)+1 from public.hq_item_rules_v1600), v.display_name)
  on conflict (item_name) do update set limit_days = excluded.limit_days, ng_sign = excluded.ng_sign, aliases = excluded.aliases,
    updated_by_name = excluded.updated_by_name, updated_at = now();
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.hq_delete_item_rule_v1600(p_item_name text)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles;
begin
  v := public.hq_actor_v1400(array['admin','hq_worker']);
  delete from public.hq_item_rules_v1600 where item_name = btrim(coalesce(p_item_name,''));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.hq_limit_check_v1600(p_lot_id uuid, p_action text, p_elapsed integer, p_limit integer)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v public.profiles; l public.hq_lots_v1400%rowtype;
begin
  v := public.hq_actor_v1400(array['admin','hq_worker']);
  select * into l from public.hq_lots_v1400 where id = p_lot_id;
  if not found then raise exception '原料が見つかりません'; end if;
  insert into public.hq_limit_checks_v1600(lot_id, lot_no, item_name, elapsed_days, limit_days, action, checked_by_name)
  values (l.id, l.lot_no, l.item_name, p_elapsed, p_limit, p_action, v.display_name);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.hq_item_canon_v1600(p_name text)
returns text language sql stable security definer set search_path to ''
as $$
  select coalesce(
    (select r.item_name from public.hq_item_rules_v1600 r
      where r.item_name = btrim(coalesce(p_name,'')) or btrim(coalesce(p_name,'')) = any(r.aliases) limit 1),
    btrim(coalesce(p_name,'')));
$$;

create or replace function public.hq_price_table_v1500(p_from date, p_to date, p_items text[] default null)
returns jsonb language plpgsql stable security definer set search_path to ''
as $$
declare v public.profiles; res jsonb;
begin
  v := public.hq_actor_v1400(array['admin','worker','buyer','sales','clerk','office_viewer','viewer','hq_worker','hq_clerk','hq_receiver']);
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 800 then raise exception '期間が正しくありません'; end if;
  with mp as (
    select pp.week_start, btrim(pp.item_name) item_name, public.hq_item_canon_v1600(pp.item_name) canon, pp.price_yen_per_kg price
    from public.purchase_prices pp
    where (pp.price_type = 'market' or btrim(pp.supplier) in ('市場','水戸大同','大同','水戸中央','中央','東一','シティ'))
      and pp.price_yen_per_kg >= 0 and btrim(coalesce(pp.item_name,'')) <> ''
  ),
  names as (
    select distinct n disp, public.hq_item_canon_v1600(n) canon from unnest(p_items) n
    where p_items is not null and btrim(coalesce(n,'')) <> ''
    union
    select distinct public.hq_item_canon_v1600(n), public.hq_item_canon_v1600(n) from (
      select name n from public.hq_items_v1400
      union select name from public.hq_normal_items_v1410
      union select item_name from public.hq_prep_masters_v1500
      union select item_name from mp where week_start >= date_trunc('week', p_from)::date and week_start <= p_to
    ) z where p_items is null and btrim(coalesce(n,'')) <> ''
  ),
  weeks as (select generate_series(date_trunc('week', p_from)::date, date_trunc('week', p_to)::date, interval '7 day')::date wk),
  pick as (
    select n.disp, n.canon, w.wk,
      (select max(mp.week_start) from mp where (mp.canon = n.canon or mp.item_name = any(public.seika_item_name_group_v1200(n.disp))) and mp.week_start <= w.wk) src
    from names n cross join weeks w
  )
  select coalesce(jsonb_agg(jsonb_build_object('item_name', p.disp, 'week', p.wk, 'src_week', p.src,
    'price', (select round(avg(mp.price),2) from mp where (mp.canon = p.canon or mp.item_name = any(public.seika_item_name_group_v1200(p.disp))) and mp.week_start = p.src),
    'count', (select count(*) from mp where (mp.canon = p.canon or mp.item_name = any(public.seika_item_name_group_v1200(p.disp))) and mp.week_start = p.src))
    order by p.disp, p.wk),'[]'::jsonb)
  into res from pick p;
  return res;
end $$;

create or replace function public.get_lot_trace_v1600(p_kind text, p_key text)
returns jsonb language plpgsql stable security definer set search_path to ''
as $$
declare v public.profiles; q public.qr_lots%rowtype; h public.hq_lots_v1400%rowtype; hq_ids uuid[]; k text := btrim(coalesce(p_key,''));
begin
  select * into v from public.profiles where id = auth.uid() and active = true;
  if not found then raise exception '再ログインしてください' using errcode = '42501'; end if;
  if k = '' then raise exception 'ロットを選んでください'; end if;
  if p_kind = 'hq' then
    select * into h from public.hq_lots_v1400 where qr_key = k or lot_no = k or id::text = k limit 1;
    if not found then raise exception 'このロットは見つかりません'; end if;
    if h.source_lot_id is not null then select * into q from public.qr_lots where id = h.source_lot_id; end if;
  else
    select * into q from public.qr_lots where qr_key = k or lot_no = k or id::text = k limit 1;
    if not found then raise exception 'このロットは見つかりません'; end if;
  end if;
  if q.id is not null then
    select array_agg(id) into hq_ids from public.hq_lots_v1400 where source_lot_id = q.id;
  else
    hq_ids := array[h.id];
  end if;
  hq_ids := coalesce(hq_ids, '{}');
  return jsonb_build_object(
    'printed_by', v.display_name,
    'start_kind', p_kind,
    'start_hq_id', h.id,
    'qr_lot', case when q.id is null then null else to_jsonb(q) end,
    'qr_moves', coalesce((select jsonb_agg(to_jsonb(m) order by m.occurred_at) from public.qr_lot_movements m where q.id is not null and m.lot_id = q.id), '[]'::jsonb),
    'hq_lots', coalesce((select jsonb_agg(to_jsonb(l) order by l.created_at) from public.hq_lots_v1400 l where l.id = any(hq_ids)), '[]'::jsonb),
    'hq_moves', coalesce((select jsonb_agg(to_jsonb(m) order by m.occurred_at) from public.hq_lot_movements_v1400 m where m.lot_id = any(hq_ids)), '[]'::jsonb),
    'works', coalesce((select jsonb_agg(jsonb_build_object('work', to_jsonb(w), 'materials',
        (select jsonb_agg(to_jsonb(mt)) from public.hq_work_materials_v1500 mt where mt.work_id = w.id and mt.lot_id = any(hq_ids))) order by w.started_at)
      from public.hq_works_v1500 w where exists (select 1 from public.hq_work_materials_v1500 mt where mt.work_id = w.id and mt.lot_id = any(hq_ids))), '[]'::jsonb),
    'waste', coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at) from public.hq_waste_v1500 x where x.lot_id = any(hq_ids)), '[]'::jsonb)
  );
end $$;

do $$
declare f text;
begin
  foreach f in array array[
    'public.hq_save_item_rule_v1600(text,text,integer,text,text[])',
    'public.hq_delete_item_rule_v1600(text)',
    'public.hq_limit_check_v1600(uuid,text,integer,integer)',
    'public.hq_item_canon_v1600(text)',
    'public.hq_price_table_v1500(date,date,text[])',
    'public.get_lot_trace_v1600(text,text)'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
  end loop;
end $$;

commit;

/* 成功の確かめ方：下のSELECTを実行して、4行とも「OK」になれば成功です。 */
select '使用期限の表' as 項目, case when (select count(*) from public.hq_item_rules_v1600 where limit_days is not null) >= 31 then 'OK' else 'NG' end as 結果
union all select '期限切れの確認記録', case when to_regprocedure('public.hq_limit_check_v1600(uuid,text,integer,integer)') is not null then 'OK' else 'NG' end
union all select '仕入れ価格表のまとめ', case when public.hq_item_canon_v1600('胡瓜') = 'きゅうり' then 'OK' else 'NG' end
union all select 'トレース表', case when to_regprocedure('public.get_lot_trace_v1600(text,text)') is not null then 'OK' else 'NG' end;
