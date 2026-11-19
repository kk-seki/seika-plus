/*
055_表記をまとめても最後に動いた日を変えない.sql（v1.199-c134）

目的：
  仕入先・単協名を「正式名にまとめる」と、ロットの updated_at（最後に動いた日）が今日に変わり、
  在庫0のまま90日以上たったロットが「在庫なし」「すべて」の一覧にまた出てくる。これを直す。
  1. set_updated_at：設定 seika.keep_updated_at が on のときは updated_at を変えない。
  2. qr_party_merge_v1199c130：表記を直すときだけ、その設定を on にする。
  3. すでにまとめた分（2026-11-19）の在庫0のロットの updated_at を、そのロットの最後の入出庫の日時に戻す。

ロットの数量・表記・履歴は変わりません。何度実行しても同じ結果になります。
*/
begin;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path to 'pg_catalog','public'
as $f$
begin
  if tg_op = 'UPDATE' and coalesce(current_setting('seika.keep_updated_at', true), '') = 'on' then
    new.updated_at = old.updated_at;
  else
    new.updated_at = now();
  end if;
  return new;
end
$f$;

-- ===== 表記を正式名にまとめる：過去のロット・履歴の表記も直す（管理者） =====
create or replace function public.qr_party_merge_v1199c130(p_kind text, p_from text, p_to text)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public'
as $f$
declare
  v_profile public.profiles%rowtype;
  v_from text := btrim(coalesce(p_from,''));
  v_to text := btrim(coalesce(p_to,''));
  v_fn text; v_lots integer := 0; v_moves integer := 0; v_hq integer := 0;
  v_col text;
begin
  perform public.seika_require_role_v1240(array['admin']);
  select * into v_profile from public.profiles where id = auth.uid() and active limit 1;
  if v_profile.id is null then raise exception 'ログインが必要です' using errcode = '42501'; end if;
  if p_kind not in ('supplier','cooperative') then raise exception '種類が正しくありません' using errcode = '22023'; end if;
  if v_from = '' or v_to = '' then return jsonb_build_object('ok', false, 'message', '名称が空です'); end if;
  if v_from = v_to then return jsonb_build_object('ok', false, 'message', '同じ名称です'); end if;
  perform pg_advisory_xact_lock(hashtext('qr_party_merge_v1199c130'));
  v_fn := public.seika_party_norm_v1280(v_from);
  v_col := case when p_kind = 'supplier' then 'supplier' else 'cooperative_name' end;
  -- c134：表記を直しても「最後に動いた日（updated_at）」は変えない（在庫0の古いロットが一覧に戻らないように）
  perform set_config('seika.keep_updated_at', 'on', true);

  execute format('update public.qr_lots set %1$I = $1 where public.seika_party_norm_v1280(%1$I) = $2 and %1$I is distinct from $1', v_col)
    using v_to, v_fn;
  get diagnostics v_lots = row_count;
  execute format('update public.qr_lot_movements set %1$I = $1 where public.seika_party_norm_v1280(%1$I) = $2 and %1$I is distinct from $1', v_col)
    using v_to, v_fn;
  get diagnostics v_moves = row_count;
  if to_regclass('public.hq_lots_v1400') is not null then
    execute format('update public.hq_lots_v1400 set %1$I = $1 where public.seika_party_norm_v1280(%1$I) = $2 and %1$I is distinct from $1', v_col)
      using v_to, v_fn;
    get diagnostics v_hq = row_count;
  end if;
  perform set_config('seika.keep_updated_at', '', true);

  -- マスタ：正式名を有効にし、元の表記は「別名（次からは自動で正式名に直す）」にする
  if public.seika_party_norm_v1280(v_to) <> v_fn then
    perform public.set_qr_party_name_v1280(p_kind, v_from, 'deleted', v_to);
  else
    perform public.set_qr_party_name_v1280(p_kind, v_to, 'active', null);
  end if;

  insert into public.qr_party_merge_log_v1199c130(kind, from_name, to_name, lots, movements, hq_lots, done_by, done_by_name)
  values (p_kind, v_from, v_to, v_lots, v_moves, v_hq, v_profile.id, coalesce(v_profile.display_name,''));
  return jsonb_build_object('ok', true, 'lots', v_lots, 'movements', v_moves, 'hq_lots', v_hq);
end
$f$;

-- 3. すでにまとめた分を戻す（まとめた時間帯に updated_at が変わった、まとめ先の表記を持つ在庫0のロットだけ）
do $b$
declare v_from timestamptz; v_to timestamptz; v_n integer;
begin
  select min(done_at) - interval '5 seconds', max(done_at) + interval '5 seconds' into v_from, v_to from public.qr_party_merge_log_v1199c130;
  if v_from is null then return; end if;
  perform set_config('seika.keep_updated_at', '', true);
  create temp table c134_restore on commit drop as
  select l.id, greatest(l.created_at, coalesce(max(coalesce(m.occurred_at, m.created_at)), l.created_at)) as last_at
  from public.qr_lots l
  left join public.qr_lot_movements m on m.lot_id = l.id
  where l.updated_at between v_from and v_to
    and coalesce(l.current_qty, 0) <= 0
    and exists (select 1 from public.qr_party_merge_log_v1199c130 g
                where (g.kind = 'supplier' and l.supplier = g.to_name) or (g.kind = 'cooperative' and l.cooperative_name = g.to_name))
  group by l.id, l.created_at;
  alter table public.qr_lots disable trigger user;
  update public.qr_lots l set updated_at = r.last_at from c134_restore r where l.id = r.id and l.updated_at is distinct from r.last_at;
  get diagnostics v_n = row_count;
  alter table public.qr_lots enable trigger user;
  raise notice '最後に動いた日を戻したロット：%件', v_n;
end $b$;

commit;

-- 確認：2行とも「OK」なら成功です
select '最後に動いた日を変えない仕組み' as 確認項目, case when position('keep_updated_at' in pg_get_functiondef('public.set_updated_at()'::regprocedure)) > 0
  and position('keep_updated_at' in pg_get_functiondef('public.qr_party_merge_v1199c130(text,text,text)'::regprocedure)) > 0 then 'OK' else '要確認' end as 判定
union all
select 'まとめた時間帯の在庫0ロット', case when not exists (
  select 1 from public.qr_lots l, (select min(done_at) - interval '5 seconds' a, max(done_at) + interval '5 seconds' b from public.qr_party_merge_log_v1199c130) w
  where l.updated_at between w.a and w.b and coalesce(l.current_qty,0) <= 0
    and exists (select 1 from public.qr_party_merge_log_v1199c130 g where (g.kind='supplier' and l.supplier=g.to_name) or (g.kind='cooperative' and l.cooperative_name=g.to_name))
    and not exists (select 1 from public.qr_lot_movements m where m.lot_id = l.id and coalesce(m.occurred_at, m.created_at) between w.a and w.b)  -- その時間に実際に出庫したロットは除く
) then 'OK' else '要確認' end;
