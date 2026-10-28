/*
025_日報の廃棄を廃棄一覧へ自動反映.sql（v1.199-c64）
1. 製造日報（トリミング日報）に「廃棄した重さ」を記録できるようにします。
2. 日報に記録した廃棄を、廃棄一覧・週次廃棄レポート・Excelに「トリミング廃棄」として出します。
   廃棄の重さは、使った原料ロットの使用量の割合で分けて、ロットごとに1行にします。
   単価は、日報の原料ロットの単価（ロットの仕入先を仕入れ価格表と照らし合わせた単価）をそのまま使います。
   日報を修正・削除すると、廃棄一覧の行も一緒に変わります（廃棄を別に保存しないため）。
3. これまでに登録した日報には廃棄の重さが無いので、廃棄一覧には出ません。
前提：000〜024を実行済みであること。何度実行しても同じ結果になります。
在庫（通常在庫・QR在庫）は変わりません。
説明は行頭のハイフン2つを使わない書き方にしています（スマホから貼り付けても壊れないようにするため）。
*/
begin;

alter table public.trimming_jobs add column if not exists waste_weight_kg numeric(14,3);

create or replace function public.set_trimming_waste_v1640(p_job_id uuid, p_waste_kg numeric)
returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare v_job public.trimming_jobs;
begin
  perform public.trimming_require_role(array['admin','worker']);
  if p_waste_kg is not null and p_waste_kg < 0 then raise exception '廃棄の重さは0以上で入力してください'; end if;
  update public.trimming_jobs set waste_weight_kg = case when p_waste_kg is null then null else round(p_waste_kg,3) end, updated_at = now()
  where id = p_job_id returning * into v_job;
  if not found then return jsonb_build_object('ok',false,'message','日報が見つかりません。画面を再読み込みしてください。'); end if;
  return jsonb_build_object('ok',true,'job_id',v_job.id,'waste_weight_kg',v_job.waste_weight_kg);
end;
$function$;

create or replace function public.list_trimming_waste_v1640(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path to ''
as $function$
declare
  v_from date := least(coalesce(p_from,(now() at time zone 'Asia/Tokyo')::date),coalesce(p_to,(now() at time zone 'Asia/Tokyo')::date));
  v_to date := greatest(coalesce(p_from,(now() at time zone 'Asia/Tokyo')::date),coalesce(p_to,(now() at time zone 'Asia/Tokyo')::date));
  v_rows jsonb;
begin
  perform public.seika_v1144_require_active_profile();
  with base as (
    select j.id job_id, j.work_date, j.waste_weight_kg, j.created_by_name, j.created_at, j.note,
      l.id lot_row_id, l.item_name, l.lot_no, l.qr_key, l.origin, l.supplier, l.used_weight_kg,
      l.purchase_price_yen_per_kg, l.price_match_type, l.price_match_reason,
      sum(l.used_weight_kg) over (partition by j.id) total_used,
      count(*) over (partition by j.id) lot_count,
      row_number() over (partition by j.id order by l.created_at, l.id) rn
    from public.trimming_jobs j
    join public.trimming_job_lots l on l.trimming_job_id = j.id
    where j.work_date between v_from and v_to and j.waste_weight_kg is not null and j.waste_weight_kg > 0
  ), split as (
    select b.*,
      case when b.total_used > 0 then round(b.waste_weight_kg * b.used_weight_kg / b.total_used, 3)
           else round(b.waste_weight_kg / b.lot_count, 3) end share
    from base b
  ), fixed as (
    select s.*,
      s.share + case when s.rn = 1 then s.waste_weight_kg - sum(s.share) over (partition by s.job_id) else 0 end weight
    from split s
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'source','trim','source_id',f.lot_row_id,'job_id',f.job_id,'date',f.work_date,
      'item_name',f.item_name,'lot_no',f.lot_no,'qr_key',f.qr_key,'origin',f.origin,'supplier',f.supplier,
      'weight',f.weight,'job_waste_kg',f.waste_weight_kg,
      'purchase_price_yen_per_kg',f.purchase_price_yen_per_kg,
      'waste_amount_yen',case when f.purchase_price_yen_per_kg is not null and f.purchase_price_yen_per_kg > 0 then round(f.weight * f.purchase_price_yen_per_kg) else null end,
      'price_match_type',coalesce(f.price_match_type,'未計算'),'price_match_reason',coalesce(f.price_match_reason,''),
      'user_name',f.created_by_name,'occurred_at',f.created_at,'memo',f.note
    ) order by f.work_date desc, f.created_at desc, f.rn), '[]'::jsonb)
  into v_rows from fixed f;
  return jsonb_build_object('ok',true,'rows',v_rows);
end;
$function$;

revoke all on function public.set_trimming_waste_v1640(uuid,numeric) from public, anon;
grant execute on function public.set_trimming_waste_v1640(uuid,numeric) to authenticated, service_role;
revoke all on function public.list_trimming_waste_v1640(date,date) from public, anon;
grant execute on function public.list_trimming_waste_v1640(date,date) to authenticated, service_role;

commit;

notify pgrst, 'reload schema';

/* 成功の確かめ方：下のSELECTを実行して、3行とも「OK」になれば成功です。 */
select '日報に廃棄の重さの欄' as 項目, case when exists(select 1 from information_schema.columns where table_schema='public' and table_name='trimming_jobs' and column_name='waste_weight_kg') then 'OK' else 'NG' end as 結果
union all select '廃棄の重さを保存する処理', case when to_regprocedure('public.set_trimming_waste_v1640(uuid,numeric)') is not null then 'OK' else 'NG' end
union all select '廃棄一覧へ出す処理', case when to_regprocedure('public.list_trimming_waste_v1640(date,date)') is not null then 'OK' else 'NG' end;
