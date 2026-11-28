/*
076_GAP一覧をGLOBALGAPサイトで自動更新.sql（v1.199-c176）

目的：月2回（1日・15日）のGAPチェックで、GLOBALG.A.P.（GGAP）も GLOBALG.A.P. Supply Chain Portal
  （https://prod.osapiens.cloud/portal/webbundle/foodplus/field-service-os/supply-chain-portal）で調べ、
  サイトの有効期限のほうが新しければ GAP一覧に反映する。
しくみ：
  ・SEIKA＋の GAP一覧には GGN（GLOBALG.A.P. の番号）がないので、調べる行と GGN は平田さんの GAP一覧Excel（GAP認証産地○○更新.xlsx）から取る。
    調べるのは平田さんのPCのブラウザ。サイトはログインしないと認証の品目が見られないので、GGN が合い、
    「Integrated Farm Assurance (IFA)」が Certified の期限だけを使う（品目は確かめない。2026-11-28 平田さん了承）。
  ・gap_ggap_apply_v1199c176(p_rows, p_run_id)：Excelの行ごとのサイトの結果を受け取り、GAP一覧の GGAP の行に反映する。
    p_rows：[{coop_name, item_name, ggn, result, valid_to, group_name}]
      coop_name・item_name は Excel の書き方のまま（「ＮＣＴファームネット（小出博基）」なども可）。
      result：certified（IFA が Certified）／expired（サイトで認証が切れている）／not_found（GGNがサイトにない）／no_ggn（ExcelにGGNがない）／not_searched（調べられなかった）
      valid_to：'YYYY-MM-DD'（certified のとき）
    GAP一覧の行の探し方：認証が GGAP、品目が同じ、単協名が Excel の名前・かっこの中・かっこの前のどれかと同じ（会社の種類・空白・全角半角を外して比べる）。
    結果（行ごと）：updated 反映した／same 期限が同じ／older サイトのほうが古い／ambiguous 当てはまる行が2つ以上／
      not_in_list SEIKA＋のGAP一覧にない（Excelだけ更新。Excelを取り込み直すと入る）／site_expired／not_found／no_ggn／not_searched
  ・p_run_id に JGAP のチェック（gap_jgap_apply_v1199c174）の run_id を渡すと、同じチェックの結果に足す（GAP一覧の画面で一緒に見られる）。
    null なら新しいチェックとして記録する。
  ・反映したものは qr_gap_auto_updates_v1199c174 に残す（jgap_no に GGN、jgap_name にグループ名）。Excelの取り込み（全部置き換え）でも新しい期限は残る（075 のしくみ）。
  ・反映の関数はアプリからは呼べない（データベースの管理用の接続だけ）。
前提：075 まで実行済みであること。今までのデータは変わりません。何度実行しても同じ結果になります。
元に戻すとき：drop function if exists public.gap_ggap_apply_v1199c176(jsonb, bigint), public.gap_ggap_names_v1199c176(text);
*/
begin;

-- Excel の単協名から、照らし合わせる名前（そのまま・かっこの中・かっこの前）を作る（会社の種類・空白を外した形）
create or replace function public.gap_ggap_names_v1199c176(p text)
returns text[] language sql immutable set search_path to 'pg_catalog','public' as $n$
  with s as (select regexp_replace(normalize(coalesce(p, ''), NFKC), '[\s　]', '', 'g') v),
       m as (select v, regexp_match(v, '^(.*?)\(([^()]+)\)$') k from s)
  select array(select distinct x from (
    select public.gap_jgap_core_v1199c174(v) x from m
    union all select public.gap_jgap_core_v1199c174(k[2]) from m where k is not null
    union all select public.gap_jgap_core_v1199c174(k[1]) from m where k is not null) t where x <> '');
$n$;

create or replace function public.gap_ggap_apply_v1199c176(p_rows jsonb, p_run_id bigint default null)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','public' as $a$
declare
  x jsonb; c record; v_run bigint; rep jsonb := '[]'::jsonb; cnt jsonb := '{}'::jsonb; st text; res text;
  names text[]; inorm text; n integer; new_exp date; v_coop text; v_item text; v_old date;
  old_sum jsonb; k text;
begin
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then raise exception '結果がありません' using errcode = '22023'; end if;
  perform pg_advisory_xact_lock(hashtext('qr_gap_certs_v1199c130'));
  if p_run_id is not null and exists (select 1 from public.qr_gap_jgap_runs_v1199c174 where id = p_run_id) then v_run := p_run_id;
  else insert into public.qr_gap_jgap_runs_v1199c174(days) values (60) returning id into v_run;
  end if;

  for x in select value from jsonb_array_elements(p_rows) loop
    v_coop := btrim(coalesce(x->>'coop_name', '')); v_item := btrim(coalesce(x->>'item_name', ''));
    res := coalesce(nullif(x->>'result', ''), 'not_searched');
    new_exp := null; v_old := null;
    if v_coop = '' or v_item = '' then continue; end if;
    names := public.gap_ggap_names_v1199c176(v_coop);
    inorm := public.seika_party_norm_v1280(v_item);
    select count(*) into n from public.qr_gap_certs_v1199c130 g
     where g.certification = 'GGAP' and g.item_norm = inorm
       and (public.gap_jgap_core_v1199c174(g.coop_name) = any(names)
            or public.gap_jgap_core_v1199c174(regexp_replace(normalize(g.coop_name, NFKC), '\([^()]*\)$', '')) = any(names));
    if n = 1 then
      select * into c from public.qr_gap_certs_v1199c130 g
       where g.certification = 'GGAP' and g.item_norm = inorm
         and (public.gap_jgap_core_v1199c174(g.coop_name) = any(names)
              or public.gap_jgap_core_v1199c174(regexp_replace(normalize(g.coop_name, NFKC), '\([^()]*\)$', '')) = any(names))
       for update;
      v_old := c.expires_on;
    end if;

    if res = 'certified' then
      begin new_exp := (x->>'valid_to')::date; exception when others then new_exp := null; end;
      if new_exp is null then st := 'not_searched';
      elsif n = 0 then st := 'not_in_list';
      elsif n > 1 then st := 'ambiguous';
      elsif new_exp > c.expires_on then
        st := 'updated';
        update public.qr_gap_certs_v1199c130 set expires_on = new_exp where coop_norm = c.coop_norm and item_norm = c.item_norm;
        insert into public.qr_gap_auto_updates_v1199c174(run_id, coop_norm, item_norm, coop_name, item_name, certification, old_expires, new_expires, jgap_name, jgap_no, jgap_items)
        values (v_run, c.coop_norm, c.item_norm, c.coop_name, c.item_name, 'GGAP', c.expires_on, new_exp,
                left(coalesce(x->>'group_name', ''), 200), coalesce(x->>'ggn', ''), 'GLOBALG.A.P. IFA（品目はサイトで見られないため未確認）');
      elsif new_exp = c.expires_on then st := 'same';
      else st := 'older';
      end if;
    elsif res = 'expired' then st := 'site_expired';
    elsif res in ('not_found', 'no_ggn', 'not_searched') then st := res;
    else st := 'not_searched';
    end if;

    cnt := jsonb_set(cnt, array[st], to_jsonb(coalesce((cnt->>st)::integer, 0) + 1));
    rep := rep || jsonb_build_array(jsonb_build_object(
      'coop_name', case when n = 1 then c.coop_name else v_coop end,
      'excel_name', v_coop, 'item_name', case when n = 1 then c.item_name else v_item end, 'certification', 'GGAP',
      'expires_on', v_old, 'status', st, 'new_expires', new_exp, 'jgap_name', nullif(x->>'group_name', ''), 'jgap_no', nullif(x->>'ggn', ''),
      'candidates', null));
  end loop;

  select summary into old_sum from public.qr_gap_jgap_runs_v1199c174 where id = v_run;
  old_sum := coalesce(old_sum, '{}'::jsonb);
  for k in select jsonb_object_keys(cnt) loop
    old_sum := jsonb_set(old_sum, array[k], to_jsonb(coalesce((old_sum->>k)::integer, 0) + (cnt->>k)::integer));
  end loop;
  update public.qr_gap_jgap_runs_v1199c174 set summary = old_sum, report = coalesce(report, '[]'::jsonb) || rep where id = v_run;
  return jsonb_build_object('ok', true, 'run_id', v_run, 'summary', cnt, 'report', rep);
end
$a$;
-- アプリ（ログインした人）からは呼べない。データベースの管理用の接続（月2回のチェック）だけ
revoke all on function public.gap_ggap_apply_v1199c176(jsonb, bigint) from public, anon, authenticated;
grant execute on function public.gap_ggap_apply_v1199c176(jsonb, bigint) to service_role;
revoke all on function public.gap_ggap_names_v1199c176(text) from public, anon;
grant execute on function public.gap_ggap_names_v1199c176(text) to authenticated, service_role;

commit;

-- ===== 確認（OK なら成功） =====
select
  (select case when to_regprocedure('public.gap_ggap_apply_v1199c176(jsonb,bigint)') is not null
                and not has_function_privilege('authenticated', 'public.gap_ggap_apply_v1199c176(jsonb,bigint)', 'execute') then 'OK' else 'NG' end) as "GLOBALGAPサイトの反映（アプリからは呼べない）",
  (select case when public.gap_ggap_names_v1199c176('ＮＣＴファームネット（小出博基）') @> array['NCTファームネット'] then 'OK' else 'NG' end) as "名前の照らし合わせ";
