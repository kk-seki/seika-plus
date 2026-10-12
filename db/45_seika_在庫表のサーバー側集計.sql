-- ============================================================
-- SEIKA＋ 在庫表の集計をサーバー側へ移す（第1段）
--
--   目的：
--     在庫表は毎回 qr_lots 全件 + qr_lot_movements 全件を
--     ダウンロードし、端末側で for(ロット)×for(98日) の
--     二重ループで移動履歴を再生していた。
--     移動履歴は増え続けるため、この構造は必ず破綻する。
--
--   方針：
--     「日ごとの在庫数と保管場所」の算出だけをサーバーへ移す。
--     品目名の解決・kg換算・大型容器・片岡などの業務判定は
--     端末側の既存処理をそのまま使う（数字を変えないため）。
--
--   返すのは「変化した日」だけ。端末側で次の変化日まで
--   引き延ばして使う。移動履歴のダウンロードは不要になる。
--
--   端末側 v1101LotSnapshotAtDayEnd と同一の手順を移植:
--     ・受入日より前／今日より後は対象外
--     ・月次スナップショットがあればそれを起点にする
--     ・保管場所は移動に記載があれば上書き
--     ・削除 → 数量0
--     ・after_quantity があればそれを採用
--     ・取消 → before_quantity へ戻す
--     ・廃棄／出庫／調整減 → 減算
--     ・入庫／調整増 → 加算（初回入庫の二重計上は1回だけ除外）
--     ・最後に 0 未満は 0、小数2桁に丸め
--   日付はすべて Asia/Tokyo。
-- ============================================================

create or replace function public.qr_lot_daily_state_v1211(
  p_from date,
  p_to   date)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public'
as $function$
declare
  v_profile   public.profiles%rowtype;
  v_today     date := (now() at time zone 'Asia/Tokyo')::date;
  v_from      date;
  v_to        date;
  v_lot       record;
  v_moves     jsonb[];
  v_out       jsonb := '[]'::jsonb;
  v_changes   jsonb;
  v_received  date;
  v_recv_qty  numeric;
  v_month     date;
  v_month_end date;
  v_day       date;
  v_day_from  date;
  v_day_to    date;
  v_base      record;
  v_start     timestamptz;
  v_qty       numeric;
  v_loc       text;
  v_del       boolean;
  v_skipped   boolean;
  v_idx       int;
  v_m         jsonb;
  v_at        timestamptz;
  v_type      text;
  v_mloc      text;
  v_after     numeric;
  v_before    numeric;
  v_amount    numeric;
  v_same      boolean;
  v_prev_q    numeric;
  v_prev_l    text;
  v_prev_d    boolean;
  v_has_prev  boolean;
begin
  select * into v_profile from public.profiles where id = auth.uid() and active = true;
  if not found then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;

  v_from := coalesce(p_from, v_today - 97);
  v_to   := least(coalesce(p_to, v_today), v_today);
  if v_from > v_to then
    return jsonb_build_object('ok', true, 'today', v_today, 'from', v_from, 'to', v_to, 'lots', '[]'::jsonb);
  end if;

  -- 移動履歴を一度だけ取り出す（列構成の差異に耐えるため jsonb 経由）
  create temp table if not exists _v1211_mv(
    j       jsonb,
    k_lot   text,
    k_qr    text,
    k_no    text,
    at      timestamptz
  ) on commit drop;
  delete from _v1211_mv;

  insert into _v1211_mv(j, k_lot, k_qr, k_no, at)
  select t.j,
         coalesce(t.j->>'lot_id',''),
         coalesce(t.j->>'qr_key',''),
         coalesce(t.j->>'lot_no',''),
         coalesce((t.j->>'occurred_at')::timestamptz,
                  (t.j->>'created_at')::timestamptz,
                  (t.j->>'updated_at')::timestamptz,
                  'epoch'::timestamptz)
  from (select to_jsonb(m) as j from public.qr_lot_movements m) t;

  create index if not exists _v1211_mv_lot on _v1211_mv(k_lot);
  create index if not exists _v1211_mv_qr  on _v1211_mv(k_qr);
  create index if not exists _v1211_mv_no  on _v1211_mv(k_no);
  analyze _v1211_mv;

  for v_lot in
    select to_jsonb(l) as j, l.id
    from public.qr_lots l
    order by l.qr_key
  loop
    -- 受入日（端末側 v163LotReceivedKey と同じ判定）
    if coalesce(substr(v_lot.j->>'received_date',1,10),'') ~ '^\d{4}-\d{2}-\d{2}$' then
      v_received := substr(v_lot.j->>'received_date',1,10)::date;
    else
      v_received := (coalesce((v_lot.j->>'created_at')::timestamptz,
                              (v_lot.j->>'updated_at')::timestamptz)
                     at time zone 'Asia/Tokyo')::date;
    end if;
    if v_received is null then continue; end if;

    v_day_from := greatest(v_from, v_received);
    v_day_to   := v_to;
    if v_day_from > v_day_to then continue; end if;

    v_recv_qty := coalesce((v_lot.j->>'received_qty')::numeric,
                           (v_lot.j->>'initial_quantity')::numeric, 0);

    select array_agg(x.j order by x.at)
      into v_moves
    from (
      select distinct on (coalesce(mv.j->>'id', mv.at::text)) mv.j, mv.at
      from _v1211_mv mv
      where (nullif(mv.k_lot,'') is not null and mv.k_lot = v_lot.j->>'id')
         or (nullif(mv.k_qr ,'') is not null and mv.k_qr  = v_lot.j->>'qr_key')
         or (nullif(mv.k_no ,'') is not null and mv.k_no  = v_lot.j->>'lot_no')
      order by coalesce(mv.j->>'id', mv.at::text), mv.at
    ) x;
    v_moves := coalesce(v_moves, '{}'::jsonb[]);

    v_changes  := '[]'::jsonb;
    v_has_prev := false;

    -- 月ごとに起点（月次スナップショット）を決め直す
    v_month := date_trunc('month', v_day_from)::date;
    while v_month <= v_day_to loop
      v_month_end := (v_month + interval '1 month - 1 day')::date;

      select (s.j->>'quantity')::numeric          as qty,
             coalesce(s.j->>'storage_location','') as loc,
             ((s.j->>'deleted') = 'true')          as del,
             (date_trunc('month', (substr(s.j->>'target_month',1,7)||'-01')::date)
               + interval '1 month')::date         as start_key
        into v_base
      from (select to_jsonb(sn) as j
            from public.qr_lot_monthly_snapshots sn
            where sn.lot_id::text = v_lot.j->>'id') s
      where substr(s.j->>'target_month',1,7) < to_char(v_month,'YYYY-MM')
      order by substr(s.j->>'target_month',1,7) desc
      limit 1;

      if v_base.qty is not null then
        v_qty     := coalesce(v_base.qty,0);
        v_loc     := coalesce(v_base.loc,'');
        v_del     := coalesce(v_base.del,false);
        v_skipped := true;
        v_start   := (v_base.start_key::text||' 00:00:00')::timestamp at time zone 'Asia/Tokyo';
      else
        v_qty     := v_recv_qty;
        v_loc     := btrim(coalesce(v_lot.j->>'storage_location',''));
        v_del     := false;
        v_skipped := false;
        v_start   := '-infinity'::timestamptz;
      end if;

      v_idx := 1;
      v_day := greatest(v_month, v_day_from);
      while v_day <= least(v_month_end, v_day_to) loop
        -- その日の終わりまでの移動を順に適用
        while v_idx <= coalesce(array_length(v_moves,1),0) loop
          v_m  := v_moves[v_idx];
          v_at := coalesce((v_m->>'occurred_at')::timestamptz,
                           (v_m->>'created_at')::timestamptz,
                           (v_m->>'updated_at')::timestamptz,
                           'epoch'::timestamptz);
          exit when v_at > ((v_day::text||' 23:59:59.999')::timestamp at time zone 'Asia/Tokyo');
          if v_at >= v_start then
            v_type := coalesce(v_m->>'movement_type','');
            v_mloc := btrim(coalesce(v_m->>'storage_location',''));
            if v_mloc <> '' then v_loc := v_mloc; end if;

            if position('削除' in v_type) > 0 then
              v_qty := 0; v_del := true;
            else
              v_after := (v_m->>'after_quantity')::numeric;
              if v_after is not null then
                v_qty := v_after; v_del := false;
              else
                v_amount := abs(coalesce((v_m->>'qty')::numeric,
                                         (v_m->>'quantity')::numeric, 0));
                if position('取消' in v_type) > 0 then
                  v_before := (v_m->>'before_quantity')::numeric;
                  if v_before is not null then v_qty := v_before; end if;
                elsif position('廃棄' in v_type) > 0
                   or position('出庫' in v_type) > 0
                   or position('調整減' in v_type) > 0 then
                  v_qty := v_qty - v_amount;
                elsif position('入庫' in v_type) > 0
                   or position('調整増' in v_type) > 0 then
                  v_before := (v_m->>'before_quantity')::numeric;
                  v_same := (not v_skipped)
                            and position('入庫' in v_type) > 0
                            and (v_before is null or v_before = 0)
                            and abs(v_amount - v_recv_qty) < 1e-9
                            and (v_at at time zone 'Asia/Tokyo')::date = v_received;
                  if v_same then
                    v_skipped := true;
                  else
                    v_qty := v_qty + v_amount;
                  end if;
                end if;
              end if;
            end if;
          end if;
          v_idx := v_idx + 1;
        end loop;

        -- 変化した日だけ記録する
        if (not v_has_prev)
           or v_prev_q is distinct from greatest(round(v_qty,2),0)
           or v_prev_l is distinct from v_loc
           or v_prev_d is distinct from v_del then
          v_prev_q := greatest(round(v_qty,2),0);
          v_prev_l := v_loc;
          v_prev_d := v_del;
          v_has_prev := true;
          v_changes := v_changes || jsonb_build_array(
                         jsonb_build_array(to_char(v_day,'YYYY-MM-DD'), v_prev_q, v_prev_l, v_prev_d));
        end if;

        v_day := v_day + 1;
      end loop;

      v_month := (v_month + interval '1 month')::date;
    end loop;

    if jsonb_array_length(v_changes) > 0 then
      v_out := v_out || jsonb_build_array(jsonb_build_object(
                 'id',     v_lot.j->>'id',
                 'from',   to_char(v_day_from,'YYYY-MM-DD'),
                 'ch',     v_changes));
    end if;
  end loop;

  return jsonb_build_object('ok', true,
                            'today', to_char(v_today,'YYYY-MM-DD'),
                            'from',  to_char(v_from,'YYYY-MM-DD'),
                            'to',    to_char(v_to,'YYYY-MM-DD'),
                            'lots',  v_out);
end
$function$;

revoke execute on function public.qr_lot_daily_state_v1211(date,date) from public, anon;
grant  execute on function public.qr_lot_daily_state_v1211(date,date) to authenticated, service_role;

-- 動作確認（管理者になりきって98日分を取得し、件数を見る）
do $$
declare v_uid uuid; v_res jsonb;
begin
  select id into v_uid from public.profiles where role='admin' and active=true order by display_name limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub',v_uid,'role','authenticated')::text, true);
  perform set_config('role','authenticated',true);
  v_res := public.qr_lot_daily_state_v1211(((now() at time zone 'Asia/Tokyo')::date - 97),
                                            (now() at time zone 'Asia/Tokyo')::date);
  raise notice '対象ロット数: % / 期間: % 〜 %',
    jsonb_array_length(v_res->'lots'), v_res->>'from', v_res->>'to';
  perform set_config('role','none',true);
end $$;

select 'qr_lot_daily_state_v1211' as 関数,
       '作成完了' as 状態,
       (select count(*) from public.qr_lots) || ' ロット' as ロット数,
       (select count(*) from public.qr_lot_movements) || ' 件' as 移動履歴件数;
