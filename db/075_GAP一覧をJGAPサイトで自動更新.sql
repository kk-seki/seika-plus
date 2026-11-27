/*
075_GAP一覧をJGAPサイトで自動更新.sql（v1.199-c174）

目的：月2回、日本GAP協会の認証農場検索（https://jgap.jp/certification/farm-search/）で、
  GAP一覧のうち期限切れ・期限が近い JGAP／ASIAGAP の単協を調べ、サイトの有効期限のほうが新しければ GAP一覧に反映する。
  調べるのは平田さんのPCのChrome（Claude in Chrome）。このSQLは「何を調べるか」と「結果をどう反映するか」を決める。
しくみ：
  ・gap_jgap_targets_v1199c174(p_days)：調べる単協（期限切れ＋p_days日以内に切れる JGAP／ASIAGAP）と検索語
  ・gap_jgap_apply_v1199c174(p_results, p_days)：サイトの検索結果を受け取り、決まりどおりに反映する
    反映するのは「名前が合う農場が1つだけ」「その農場の品目にこの品目がある」「認証の種類が合う」「サイトの期限のほうが新しい」ときだけ。
    名前の候補が2つ以上・品目がない・見つからないものは反映せず、結果の一覧に残す（人が確かめる）。
  ・反映したものは qr_gap_auto_updates_v1199c174 に、チェックの結果は qr_gap_jgap_runs_v1199c174 に残す（GAP一覧の画面で見られる）。
  ・Excelの取り込み（全部置き換え）で、Excelより新しい自動反映の期限は残す（replace_qr_gap_certs_v1199c130 を置き換え）。
  ・反映の関数はアプリからは呼べない（データベースの管理用の接続だけ）。
前提：052・053 まで実行済みであること。今までのデータは変わりません。何度実行しても同じ結果になります。
元に戻すとき：053 をもう一度実行し、drop function if exists public.gap_jgap_apply_v1199c174(jsonb, integer), public.gap_jgap_targets_v1199c174(integer), public.gap_jgap_item_words_v1199c174(text), public.gap_jgap_core_v1199c174(text);
  drop table if exists public.qr_gap_auto_updates_v1199c174, public.qr_gap_jgap_runs_v1199c174;
*/
begin;

create table if not exists public.qr_gap_jgap_runs_v1199c174(
  id bigserial primary key,
  run_at timestamptz not null default now(),
  days integer not null,
  summary jsonb not null default '{}'::jsonb,
  report jsonb not null default '[]'::jsonb
);
create table if not exists public.qr_gap_auto_updates_v1199c174(
  id bigserial primary key,
  run_id bigint references public.qr_gap_jgap_runs_v1199c174(id) on delete set null,
  coop_norm text not null, item_norm text not null,
  coop_name text not null, item_name text not null, certification text not null,
  old_expires date, new_expires date not null,
  jgap_name text not null default '', jgap_no text not null default '', jgap_items text not null default '',
  created_at timestamptz not null default now()
);
create index if not exists qr_gap_auto_updates_v1199c174_key on public.qr_gap_auto_updates_v1199c174(coop_norm, item_norm, created_at desc);
alter table public.qr_gap_jgap_runs_v1199c174 enable row level security;
alter table public.qr_gap_auto_updates_v1199c174 enable row level security;
revoke all on public.qr_gap_jgap_runs_v1199c174, public.qr_gap_auto_updates_v1199c174 from public, anon, authenticated;
grant select on public.qr_gap_jgap_runs_v1199c174, public.qr_gap_auto_updates_v1199c174 to authenticated;
grant all on public.qr_gap_jgap_runs_v1199c174, public.qr_gap_auto_updates_v1199c174 to service_role;
drop policy if exists qr_gap_jgap_runs_v1199c174_read on public.qr_gap_jgap_runs_v1199c174;
create policy qr_gap_jgap_runs_v1199c174_read on public.qr_gap_jgap_runs_v1199c174 for select to authenticated using (true);
drop policy if exists qr_gap_auto_updates_v1199c174_read on public.qr_gap_auto_updates_v1199c174;
create policy qr_gap_auto_updates_v1199c174_read on public.qr_gap_auto_updates_v1199c174 for select to authenticated using (true);

-- 名前の芯（会社の種類・かっこ・空白を外す）。検索語にも使う
create or replace function public.gap_jgap_core_v1199c174(p text)
returns text language sql immutable set search_path to 'pg_catalog' as $c$
  select regexp_replace(regexp_replace(normalize(coalesce(p, ''), NFKC),
    '(株式会社|有限会社|合同会社|農事組合法人|一般社団法人|\(株\)|\(有\)|㈱|㈲)', '', 'g'), '[\s　]', '', 'g');
$c$;

-- 品目名 → サイトでの品目の書き方（ひらがな・正式名）。表にない品目は、その名前のまま探す
create or replace function public.gap_jgap_item_words_v1199c174(p_item text)
returns text[] language plpgsql immutable set search_path to 'pg_catalog' as $w$
declare k text := regexp_replace(normalize(coalesce(p_item, ''), NFKC), '[\s　]', '', 'g'); m jsonb := '{"キャベツ": ["キャベツ"], "紫キャベツ": ["キャベツ", "むらさきキャベツ", "紫キャベツ"], "白菜": ["はくさい"], "はくさい": ["はくさい"], "レタス": ["レタス"], "サニー": ["サニーレタス"], "サニーレタス": ["サニーレタス"], "リーフ": ["リーフレタス", "グリーンリーフ"], "リーフレタス": ["リーフレタス", "グリーンリーフ"], "グリーンリーフ": ["リーフレタス", "グリーンリーフ"], "ロメイン": ["ロメインレタス", "ロメイン"], "ロメインレタス": ["ロメインレタス", "ロメイン"], "玉葱": ["たまねぎ"], "玉ねぎ": ["たまねぎ"], "たまねぎ": ["たまねぎ"], "長葱": ["ねぎ"], "長ねぎ": ["ねぎ"], "ねぎ": ["ねぎ"], "小葱": ["こねぎ", "ねぎ"], "人参": ["にんじん"], "にんじん": ["にんじん"], "大根": ["だいこん"], "カット大根": ["だいこん"], "葉付き大根": ["だいこん"], "葉付大根": ["だいこん"], "水菜": ["みずな"], "ほうれん草": ["ほうれんそう"], "小松菜": ["こまつな"], "青梗菜": ["ちんげんさい"], "チンゲン菜": ["ちんげんさい"], "胡瓜": ["きゅうり"], "きゅうり": ["きゅうり"], "茄子": ["なす"], "なす": ["なす"], "ピーマン": ["ピーマン"], "パプリカ": ["パプリカ"], "ズッキーニ": ["ズッキーニ"], "トマト": ["トマト"], "ミニトマト": ["ミニトマト"], "ブロッコリー": ["ブロッコリー"], "牛蒡": ["ごぼう"], "ごぼう": ["ごぼう"], "南瓜": ["かぼちゃ"], "かぼちゃ": ["かぼちゃ"], "じゃが芋": ["ばれいしょ", "じゃがいも"], "じゃがいも": ["ばれいしょ", "じゃがいも"], "馬鈴薯": ["ばれいしょ", "じゃがいも"], "さつま芋": ["かんしょ", "さつまいも"], "さつまいも": ["かんしょ", "さつまいも"], "生姜": ["しょうが"], "大葉": ["しそ", "おおば"], "しめじ": ["ぶなしめじ", "しめじ"], "ニラ": ["にら"], "にら": ["にら"], "ゴーヤ": ["にがうり", "ゴーヤ"]}'::jsonb;
begin
  if m ? k then return array(select jsonb_array_elements_text(m -> k)); end if;
  return array[k];
end
$w$;

-- 調べる単協（期限切れ＋p_days日以内に切れる JGAP／ASIAGAP）と検索語
create or replace function public.gap_jgap_targets_v1199c174(p_days integer default 60)
returns jsonb language sql stable security definer set search_path to 'pg_catalog','public' as $t$
  select coalesce(jsonb_agg(jsonb_build_object('coop_name', coop_name, 'query', q) order by coop_name), '[]'::jsonb)
    from (select distinct coop_name, public.gap_jgap_core_v1199c174(coop_name) q from public.qr_gap_certs_v1199c130
           where certification in ('JGAP','ASIAGAP') and expires_on <= (now() at time zone 'Asia/Tokyo')::date + greatest(coalesce(p_days, 60), 0)) t
   where q <> '';
$t$;
revoke all on function public.gap_jgap_targets_v1199c174(integer) from public, anon;
grant execute on function public.gap_jgap_targets_v1199c174(integer) to authenticated, service_role;

/* サイトの検索結果を反映する。p_results：[{coop_name, query, rows:[{name, no, pref, ver, items, expires}]}]（expires は 'YYYY/MM/DD'）
   結果（行ごと）：updated 反映した／same 期限が同じ／older サイトのほうが古い／ambiguous 候補が2つ以上／item_missing 品目がない／
   cert_missing 認証の種類が違う／not_found 見つからない／not_searched 検索結果がない（調べられなかった） */
create or replace function public.gap_jgap_apply_v1199c174(p_results jsonb, p_days integer default 60)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','public' as $a$
declare
  c record; res jsonb; cand jsonb; hit jsonb; core text; words text[]; new_exp date;
  v_run bigint; rep jsonb := '[]'::jsonb; st text; cnt jsonb := '{}'::jsonb; n integer;
begin
  if p_results is null or jsonb_typeof(p_results) <> 'array' then raise exception '検索結果がありません' using errcode = '22023'; end if;
  perform pg_advisory_xact_lock(hashtext('qr_gap_certs_v1199c130'));
  insert into public.qr_gap_jgap_runs_v1199c174(days) values (greatest(coalesce(p_days, 60), 0)) returning id into v_run;
  for c in select * from public.qr_gap_certs_v1199c130
            where certification in ('JGAP','ASIAGAP') and expires_on <= (now() at time zone 'Asia/Tokyo')::date + greatest(coalesce(p_days, 60), 0)
            order by coop_name, item_name for update loop
    core := public.gap_jgap_core_v1199c174(c.coop_name);
    res := null; hit := null; new_exp := null;
    select value into res from jsonb_array_elements(p_results) where value->>'coop_name' = c.coop_name limit 1;
    if res is null or jsonb_typeof(res->'rows') is distinct from 'array' then st := 'not_searched';
    else
      -- 名前が合う農場（どちらかがもう一方を含む）
      select coalesce(jsonb_agg(value), '[]'::jsonb) into cand from jsonb_array_elements(res->'rows')
       where length(core) >= 2 and public.gap_jgap_core_v1199c174(value->>'name') <> ''
         and (public.gap_jgap_core_v1199c174(value->>'name') like '%' || core || '%' or core like '%' || public.gap_jgap_core_v1199c174(value->>'name') || '%');
      if jsonb_array_length(cand) = 0 then st := 'not_found';
      else
        words := public.gap_jgap_item_words_v1199c174(c.item_name);
        -- 品目：サイトの品目を「、」で分け、かっこの中も1語として、完全に一致するものがある農場
        select coalesce(jsonb_agg(v.value), '[]'::jsonb) into cand from jsonb_array_elements(cand) v(value)
         where exists (
           select 1 from regexp_split_to_table(regexp_replace(normalize(coalesce(v.value->>'items', ''), NFKC), '\([^)]*(栽培|収穫|取扱)[^)]*\)', '、', 'g'), '[、,\s]+') tok
             cross join lateral unnest(array[regexp_replace(tok, '\(.*$', ''), coalesce(substring(tok from '\(([^)]*)\)'), '')]) w
            where w <> '' and w = any(words));
        n := jsonb_array_length(cand);
        if n = 0 then st := 'item_missing';
        elsif n > 1 then st := 'ambiguous';
        else
          hit := cand->0;
          if position(c.certification in upper(coalesce(hit->>'ver', ''))) = 0 then st := 'cert_missing';
          else
            begin new_exp := to_date(hit->>'expires', 'YYYY/MM/DD'); exception when others then new_exp := null; end;
            if new_exp is null then st := 'not_found';
            elsif new_exp > c.expires_on then
              st := 'updated';
              update public.qr_gap_certs_v1199c130 set expires_on = new_exp where coop_norm = c.coop_norm and item_norm = c.item_norm;
              insert into public.qr_gap_auto_updates_v1199c174(run_id, coop_norm, item_norm, coop_name, item_name, certification, old_expires, new_expires, jgap_name, jgap_no, jgap_items)
              values (v_run, c.coop_norm, c.item_norm, c.coop_name, c.item_name, c.certification, c.expires_on, new_exp,
                      coalesce(hit->>'name', ''), coalesce(hit->>'no', ''), left(coalesce(hit->>'items', ''), 300));
            elsif new_exp = c.expires_on then st := 'same';
            else st := 'older';
            end if;
          end if;
        end if;
      end if;
    end if;
    cnt := jsonb_set(cnt, array[st], to_jsonb(coalesce((cnt->>st)::integer, 0) + 1));
    rep := rep || jsonb_build_array(jsonb_build_object('coop_name', c.coop_name, 'item_name', c.item_name, 'certification', c.certification,
      'expires_on', c.expires_on, 'status', st, 'new_expires', new_exp, 'jgap_name', hit->>'name', 'jgap_no', hit->>'no',
      'candidates', case when st = 'ambiguous' then (select jsonb_agg(value->>'name') from jsonb_array_elements(cand)) end));
  end loop;
  update public.qr_gap_jgap_runs_v1199c174 set summary = cnt, report = rep where id = v_run;
  return jsonb_build_object('ok', true, 'run_id', v_run, 'summary', cnt, 'report', rep);
end
$a$;
-- アプリ（ログインした人）からは呼べない。データベースの管理用の接続（月2回のチェック）だけ
revoke all on function public.gap_jgap_apply_v1199c174(jsonb, integer) from public, anon, authenticated;
grant execute on function public.gap_jgap_apply_v1199c174(jsonb, integer) to service_role;

-- Excelの取り込み（全部置き換え）：Excelより新しい自動反映の期限は残す
create or replace function public.replace_qr_gap_certs_v1199c130(p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public'
as $f$
declare
  v_profile public.profiles%rowtype;
  r jsonb;
  v_coop text; v_item text; v_cert text; v_exp date; v_n integer := 0; v_line integer := 0; v_kept integer := 0;
begin
  perform public.seika_require_role_v1240(array['admin']);
  select * into v_profile from public.profiles where id = auth.uid() and active limit 1;
  if v_profile.id is null then raise exception 'ログインが必要です' using errcode = '42501'; end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then raise exception '取り込む行がありません' using errcode = '22023'; end if;
  perform pg_advisory_xact_lock(hashtext('qr_gap_certs_v1199c130'));

  create temp table if not exists c130_gap_new(
    coop_norm text, coop_name text, item_norm text, item_name text, certification text, expires_on date, note text
  ) on commit drop;
  truncate c130_gap_new;

  for r in select value from jsonb_array_elements(p_rows) loop
    v_line := v_line + 1;
    v_coop := btrim(coalesce(r->>'coop_name',''));
    v_item := btrim(coalesce(r->>'item_name',''));
    v_cert := upper(btrim(coalesce(r->>'certification','')));
    if v_coop = '' or v_item = '' then raise exception '%行目：単協名と品目は必須です', v_line using errcode = '22023'; end if;
    if v_cert not in ('JGAP','GGAP','ASIAGAP') then raise exception '%行目：認証区分が正しくありません（%）', v_line, v_cert using errcode = '22023'; end if;
    begin v_exp := (r->>'expires_on')::date;
    exception when others then raise exception '%行目：有効期限が日付ではありません', v_line using errcode = '22023'; end;
    if v_exp is null then raise exception '%行目：有効期限は必須です', v_line using errcode = '22023'; end if;
    insert into c130_gap_new values (public.seika_party_norm_v1280(v_coop), v_coop, public.seika_party_norm_v1280(v_item), v_item, v_cert, v_exp, btrim(coalesce(r->>'note','')));
    v_n := v_n + 1;
  end loop;

  if exists (select 1 from c130_gap_new group by coop_norm, item_norm having count(*) > 1) then
    raise exception '同じ単協・品目の行が2つ以上あります' using errcode = '22023';
  end if;

  -- c174：JGAPサイトで自動反映した期限のほうが新しければ、そちらを残す
  update c130_gap_new n set expires_on = u.new_expires
    from (select distinct on (coop_norm, item_norm) coop_norm, item_norm, certification, new_expires
            from public.qr_gap_auto_updates_v1199c174 order by coop_norm, item_norm, created_at desc) u
   where u.coop_norm = n.coop_norm and u.item_norm = n.item_norm and u.certification = n.certification and u.new_expires > n.expires_on;
  get diagnostics v_kept = row_count;

  -- Supabase では WHERE のない DELETE が止められるため、where true を付ける
  delete from public.qr_gap_certs_v1199c130 where true;
  insert into public.qr_gap_certs_v1199c130(coop_norm, coop_name, item_norm, item_name, certification, expires_on, note, imported_by_name, imported_at)
  select coop_norm, coop_name, item_norm, item_name, certification, expires_on, note, coalesce(v_profile.display_name,''), now() from c130_gap_new;
  return jsonb_build_object('ok', true, 'count', v_n, 'kept_auto', v_kept);
end
$f$;
revoke all on function public.replace_qr_gap_certs_v1199c130(jsonb) from public, anon;
grant execute on function public.replace_qr_gap_certs_v1199c130(jsonb) to authenticated, service_role;

commit;

-- ===== 確認（OK なら成功） =====
select
  (select case when to_regprocedure('public.gap_jgap_apply_v1199c174(jsonb,integer)') is not null
                and not has_function_privilege('authenticated', 'public.gap_jgap_apply_v1199c174(jsonb,integer)', 'execute') then 'OK' else 'NG' end) as "JGAPサイトの反映（アプリからは呼べない）",
  (select case when position('qr_gap_auto_updates_v1199c174' in pg_get_functiondef('public.replace_qr_gap_certs_v1199c130(jsonb)'::regprocedure)) > 0 then 'OK' else 'NG' end) as "取り込みで新しい期限を残す",
  (select jsonb_array_length(public.gap_jgap_targets_v1199c174(60))) as "いま調べる単協の数";
