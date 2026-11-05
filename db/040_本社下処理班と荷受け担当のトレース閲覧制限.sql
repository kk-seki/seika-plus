-- v1.199-c92 本社 下処理班・荷受け担当者のトレース閲覧制限
--  ・本社 下処理班（hq_prep）と本社 荷受け担当者（hq_receiver）は、トレース表の画面表示・印刷用データを取得できないようにします。
--  ・023で作成した get_lot_trace_v1600 の、ログイン・有効確認の直後に権限確認を追加します。
--  ・上記以外の有効なアカウントのトレース内容、既存の関数名・引数・戻り値・実行権限は変わりません。
-- 前提：023を実行済みであること。何度実行しても同じ結果になります。
begin;

do $$
begin
  if to_regprocedure('public.get_lot_trace_v1600(text,text)') is null then
    raise exception '先に db/023_本社_使用期限とトレース表.sql を実行してください';
  end if;
end $$;

create or replace function public.get_lot_trace_v1600(p_kind text, p_key text)
returns jsonb language plpgsql stable security definer set search_path to ''
as $$
declare v public.profiles; q public.qr_lots%rowtype; h public.hq_lots_v1400%rowtype; hq_ids uuid[]; k text := btrim(coalesce(p_key,''));
begin
  select * into v from public.profiles where id = auth.uid() and active = true;
  if not found then raise exception '再ログインしてください' using errcode = '42501'; end if;
  if v.role in ('hq_prep','hq_receiver') then
    raise exception 'この権限ではトレース表を閲覧できません' using errcode = '42501';
  end if;
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

commit;

-- 確認：このSQLの実行後、下の1行が「OK」なら成功です。
-- 関数があるだけでなく、hq_prep・hq_receiverを42501で拒否する記述が入っていることを確かめます。
select '本社 下処理班・荷受け担当者のトレース閲覧制限' as 確認項目,
  case when exists (
    select 1
    from pg_proc p
    where p.oid = to_regprocedure('public.get_lot_trace_v1600(text,text)')
      and p.prosrc like '%v.role in (''hq_prep'',''hq_receiver'')%'
      and p.prosrc like '%この権限ではトレース表を閲覧できません%'
      and p.prosrc like '%errcode = ''42501''%'
  ) then 'OK' else 'NG' end as 判定;
