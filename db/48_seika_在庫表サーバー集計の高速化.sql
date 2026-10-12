-- ============================================================
-- SEIKA＋ 在庫表のサーバー側集計を高速化（45番の置き換え）
--
--   45番の関数は、呼ぶたびに移動履歴を一時テーブルへ写し、
--   ロットごと・月ごとに月末スナップショットを全件探していたため、
--   ログイン利用者の制限時間（8秒）を超えて失敗していました。
--
--   ・移動履歴と月末スナップショットを1回ずつ読み、ロット単位にまとめてから計算
--   ・一時テーブルを使わない
--   ・計算ルールは45番とまったく同じ（結果は同一）
--   ・関数名と引数は同じなので、アプリ側の変更は不要
--
--   既存データは変更しません。何度実行しても安全です。
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
  v_today     date := (now() at time zone 'Asia/Tokyo')::date;
  v_from      date;
  v_to        date;
  v_row       record;
  v_lot       jsonb;
  v_moves     jsonb[];
  v_ats       timestamptz[];
  v_snaps     jsonb;
  v_n         int;
  v_out       jsonb[] := '{}'::jsonb[];
  v_changes   jsonb[];
  v_received  date;
  v_recv_qty  numeric;
  v_month     date;
  v_month_end date;
  v_ym        text;
  v_day       date;
  v_day_end   timestamptz;
  v_day_from  date;
  v_day_to    date;
  v_start     timestamptz;
  v_qty       numeric;
  v_loc       text;
  v_del       boolean;
  v_skipped   boolean;
  v_idx       int;
  v_m         jsonb;
  v_s         jsonb;
  v_at        timestamptz;
  v_type      text;
  v_mloc      text;
  v_after     numeric;
  v_before    numeric;
  v_amount    numeric;
  v_same      boolean;
  v_found     boolean;
  v_prev_q    numeric;
  v_prev_l    text;
  v_prev_d    boolean;
  v_has_prev  boolean;
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and active = true) then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;

  v_from := coalesce(p_from, v_today - 97);
  v_to   := least(coalesce(p_to, v_today), v_today);
  if v_from > v_to then
    return jsonb_build_object('ok', true, 'today', to_char(v_today,'YYYY-MM-DD'),
                              'from', to_char(v_from,'YYYY-MM-DD'), 'to', to_char(v_to,'YYYY-MM-DD'),
                              'lots', '[]'::jsonb);
  end if;

  for v_row in
    with lots as (
      select to_jsonb(l) as j from public.qr_lots l
    ),
    lk as (
      select j,
             coalesce(j->>'id','')      as lid,
             nullif(j->>'qr_key','')    as qk,
             nullif(j->>'lot_no','')    as ln
      from lots
    ),
    mv as (
      select t.j,
             nullif(t.j->>'lot_id','') as k_lot,
             nullif(t.j->>'qr_key','') as k_qr,
             nullif(t.j->>'lot_no','') as k_no,
             coalesce((t.j->>'occurred_at')::timestamptz,
                      (t.j->>'created_at')::timestamptz,
                      (t.j->>'updated_at')::timestamptz,
                      'epoch'::timestamptz) as at
      from (select to_jsonb(m) as j from public.qr_lot_movements m) t
    ),
    pairs as (
      select lk.lid, mv.j, mv.at from lk join mv on mv.k_lot = lk.lid
      union all
      select lk.lid, mv.j, mv.at from lk join mv on mv.k_qr  = lk.qk
      union all
      select lk.lid, mv.j, mv.at from lk join mv on mv.k_no  = lk.ln
    ),
    uniq as (
      select distinct on (lid, coalesce(j->>'id', at::text)) lid, j, at
      from pairs
      order by lid, coalesce(j->>'id', at::text), at
    ),
    agg as (
      select lid, array_agg(j order by at) as moves, array_agg(at order by at) as ats
      from uniq group by lid
    ),
    sn as (
      select coalesce(s.j->>'lot_id','') as lid,
             jsonb_agg(jsonb_build_object(
               'ym',  substr(s.j->>'target_month',1,7),
               'q',   (s.j->>'quantity')::numeric,
               'loc', coalesce(s.j->>'storage_location',''),
               'del', ((s.j->>'deleted') = 'true'))
               order by substr(s.j->>'target_month',1,7) desc) as snaps
      from (select to_jsonb(x) as j from public.qr_lot_monthly_snapshots x) s
      group by 1
    )
    select lk.j, a.moves, a.ats, sn.snaps
    from lk
    left join agg a on a.lid = lk.lid
    left join sn    on sn.lid = lk.lid
    order by lk.j->>'qr_key'
  loop
    v_lot := v_row.j;

    if coalesce(substr(v_lot->>'received_date',1,10),'') ~ '^\d{4}-\d{2}-\d{2}$' then
      v_received := substr(v_lot->>'received_date',1,10)::date;
    else
      v_received := (coalesce((v_lot->>'created_at')::timestamptz,
                              (v_lot->>'updated_at')::timestamptz)
                     at time zone 'Asia/Tokyo')::date;
    end if;
    if v_received is null then continue; end if;

    v_day_from := greatest(v_from, v_received);
    v_day_to   := v_to;
    if v_day_from > v_day_to then continue; end if;

    v_recv_qty := coalesce((v_lot->>'received_qty')::numeric,
                           (v_lot->>'initial_quantity')::numeric, 0);
    v_moves := coalesce(v_row.moves, '{}'::jsonb[]);
    v_ats   := coalesce(v_row.ats,   '{}'::timestamptz[]);
    v_n     := coalesce(array_length(v_moves,1),0);
    v_snaps := coalesce(v_row.snaps, '[]'::jsonb);

    v_changes  := '{}'::jsonb[];
    v_has_prev := false;

    v_month := date_trunc('month', v_day_from)::date;
    while v_month <= v_day_to loop
      v_month_end := (v_month + interval '1 month - 1 day')::date;
      v_ym := to_char(v_month,'YYYY-MM');

      v_found := false;
      for v_s in select e from jsonb_array_elements(v_snaps) e loop
        if (v_s->>'ym') < v_ym then
          if v_s->>'q' is not null then
            v_found := true;
            v_qty     := (v_s->>'q')::numeric;
            v_loc     := coalesce(v_s->>'loc','');
            v_del     := coalesce((v_s->>'del')::boolean,false);
            v_skipped := true;
            v_start   := (((date_trunc('month', ((v_s->>'ym')||'-01')::date) + interval '1 month')::date)::text
                          ||' 00:00:00')::timestamp at time zone 'Asia/Tokyo';
          end if;
          exit;
        end if;
      end loop;

      if not v_found then
        v_qty     := v_recv_qty;
        v_loc     := btrim(coalesce(v_lot->>'storage_location',''));
        v_del     := false;
        v_skipped := false;
        v_start   := '-infinity'::timestamptz;
      end if;

      v_idx := 1;
      v_day := greatest(v_month, v_day_from);
      while v_day <= least(v_month_end, v_day_to) loop
        v_day_end := (v_day::text||' 23:59:59.999')::timestamp at time zone 'Asia/Tokyo';
        while v_idx <= v_n loop
          v_at := v_ats[v_idx];
          exit when v_at > v_day_end;
          if v_at >= v_start then
            v_m    := v_moves[v_idx];
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

        if (not v_has_prev)
           or v_prev_q is distinct from greatest(round(v_qty,2),0)
           or v_prev_l is distinct from v_loc
           or v_prev_d is distinct from v_del then
          v_prev_q := greatest(round(v_qty,2),0);
          v_prev_l := v_loc;
          v_prev_d := v_del;
          v_has_prev := true;
          v_changes := array_append(v_changes,
                         jsonb_build_array(to_char(v_day,'YYYY-MM-DD'), v_prev_q, v_prev_l, v_prev_d));
        end if;

        v_day := v_day + 1;
      end loop;

      v_month := (v_month + interval '1 month')::date;
    end loop;

    if coalesce(array_length(v_changes,1),0) > 0 then
      v_out := array_append(v_out, jsonb_build_object(
                 'id',   v_lot->>'id',
                 'from', to_char(v_day_from,'YYYY-MM-DD'),
                 'ch',   to_jsonb(v_changes)));
    end if;
  end loop;

  return jsonb_build_object('ok', true,
                            'today', to_char(v_today,'YYYY-MM-DD'),
                            'from',  to_char(v_from,'YYYY-MM-DD'),
                            'to',    to_char(v_to,'YYYY-MM-DD'),
                            'lots',  to_jsonb(v_out));
end
$function$;

revoke execute on function public.qr_lot_daily_state_v1211(date,date) from public, anon;
grant  execute on function public.qr_lot_daily_state_v1211(date,date) to authenticated, service_role;

-- 動作確認：アプリと同じ条件（ログイン利用者・制限8秒）で98日分を実際に計算し、所要時間を表示
create temp table if not exists _seika_v1216_check(項目 text, 結果 text);
truncate _seika_v1216_check;
do $$
declare v_uid uuid; v_res jsonb; t0 timestamptz; ms numeric; err text;
begin
  select id into v_uid from public.profiles where role='admin' and active=true order by display_name limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub',v_uid,'role','authenticated')::text, true);
  perform set_config('role','authenticated',true);
  perform set_config('statement_timeout','8s',true);
  t0 := clock_timestamp();
  begin
    v_res := public.qr_lot_daily_state_v1211(((now() at time zone 'Asia/Tokyo')::date - 97),
                                              (now() at time zone 'Asia/Tokyo')::date);
  exception when others then err := SQLERRM;
  end;
  ms := round(extract(epoch from clock_timestamp()-t0)*1000);
  perform set_config('role','none',true);
  perform set_config('statement_timeout','0',true);
  insert into _seika_v1216_check values
    ('結果', case when err is null then 'OK（サーバー集計が使えます）' else 'エラー：'||err end),
    ('所要時間', ms||' ミリ秒（8000未満なら合格）'),
    ('対象ロット数', coalesce(jsonb_array_length(v_res->'lots'),0)::text),
    ('返すデータ量', coalesce(round(length(v_res::text)/1024.0)::text,'0')||' KB');
end $$;
select * from _seika_v1216_check;
