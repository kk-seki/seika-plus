/*
060_本社下処理_サインだけで提出.sql（v1.199-c139）

平田さんの決定（2026-11-20）：日報の提出は、サインがあれば「入力した人」の選択はいらない。
直したこと：
  1. hq_prep_signatures_v1199c121.signer_staff_id を空でもよいようにする（名前を選ばずにサインだけで提出した記録）。
     signer_name は空文字で入れる（列は今までどおり必須）。
  2. hq_prep_submit_v1199c121：下処理班はサイン（画像）だけ必須。名前（p_signer_staff_id）は任意。
     名前を渡したときは、今までどおり在籍中のスタッフか確かめる。サイン画像の検査は今までどおり。
  3. hq_c121_submit_internal：サイン画像があれば、名前がなくてもサインの記録を残す。
社員・管理者がサインなしで「社員の確認待ち」にする動きは今までどおり。
何度実行しても同じ結果になります。
*/
begin;

alter table public.hq_prep_signatures_v1199c121 alter column signer_staff_id drop not null;

create or replace function public.hq_prep_submit_v1199c121(p_work_id uuid, p_operation_id uuid, p_expected_updated_at timestamp with time zone, p_signer_staff_id uuid, p_signature_png text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v public.profiles; signer_name text:=''; image_bytes bytea; image_md5 text; payload jsonb;
  has_staff boolean:=p_signer_staff_id is not null; has_image boolean:=nullif(btrim(coalesce(p_signature_png,'')),'') is not null;
  image_body text; chunk_at integer; chunk_length integer; chunk_type text; saw_ihdr boolean:=false; saw_idat boolean:=false; saw_iend boolean:=false;
begin
  v:=public.hq_actor_v1400(array['admin','hq_worker','hq_prep']);
  if (has_staff and not has_image) or (v.role='hq_prep' and not has_image) then
    raise exception 'サインが必要です';
  end if;
  if not has_image then
    payload:=jsonb_build_object('work_id',p_work_id,'expected_updated_at',p_expected_updated_at);
    return public.hq_c121_submit_internal(p_work_id,p_operation_id,p_expected_updated_at,v,payload,null,null,null,null);
  end if;
  if has_staff then
    select s.name into signer_name from public.hq_staff_v1500 s where s.id=p_signer_staff_id and s.deleted_at is null;
    if signer_name is null then raise exception '在籍中のスタッフを選んでください'; end if;
  end if;
  if left(p_signature_png,22)<>'data:image/png;base64,' then raise exception 'サイン画像はPNGで送ってください'; end if;
  image_body:=substring(p_signature_png from 23);
  begin image_bytes:=decode(image_body,'base64'); exception when others then raise exception 'サイン画像はPNGとして読み取れません'; end;
  if octet_length(image_bytes)<700 or octet_length(image_bytes)>204800
     or encode(substring(image_bytes from 1 for 8),'hex')<>'89504e470d0a1a0a' then
    raise exception 'サイン画像は有効なPNGを入れてください';
  end if;
  chunk_at:=8;
  while chunk_at < octet_length(image_bytes) loop
    if chunk_at+12 > octet_length(image_bytes) then raise exception 'サイン画像は有効なPNGを入れてください'; end if;
    chunk_length:=get_byte(image_bytes,chunk_at)*16777216+get_byte(image_bytes,chunk_at+1)*65536+get_byte(image_bytes,chunk_at+2)*256+get_byte(image_bytes,chunk_at+3);
    if chunk_at+12+chunk_length > octet_length(image_bytes) then raise exception 'サイン画像は有効なPNGを入れてください'; end if;
    chunk_type:=convert_from(substring(image_bytes from chunk_at+5 for 4),'SQL_ASCII');
    if not saw_ihdr then
      if chunk_type<>'IHDR' or chunk_length<>13
         or get_byte(image_bytes,chunk_at+8)*16777216+get_byte(image_bytes,chunk_at+9)*65536+get_byte(image_bytes,chunk_at+10)*256+get_byte(image_bytes,chunk_at+11)=0
         or get_byte(image_bytes,chunk_at+12)*16777216+get_byte(image_bytes,chunk_at+13)*65536+get_byte(image_bytes,chunk_at+14)*256+get_byte(image_bytes,chunk_at+15)<32
         or get_byte(image_bytes,chunk_at+8)*16777216+get_byte(image_bytes,chunk_at+9)*65536+get_byte(image_bytes,chunk_at+10)*256+get_byte(image_bytes,chunk_at+11)<32 then
        raise exception 'サイン画像は有効なPNGを入れてください';
      end if;
      saw_ihdr:=true;
    elsif chunk_type='IDAT' and chunk_length>0 then
      saw_idat:=true;
    elsif chunk_type='IEND' then
      if chunk_length<>0 or not saw_idat or chunk_at+12<>octet_length(image_bytes) then raise exception 'サイン画像は有効なPNGを入れてください'; end if;
      saw_iend:=true;
    end if;
    chunk_at:=chunk_at+12+chunk_length;
  end loop;
  if not saw_ihdr or not saw_idat or not saw_iend then raise exception 'サイン画像は有効なPNGを入れてください'; end if;
  image_md5:=md5(image_bytes);
  payload:=jsonb_build_object('work_id',p_work_id,'expected_updated_at',p_expected_updated_at,'signer_staff_id',p_signer_staff_id,'signature_md5',image_md5);
  return public.hq_c121_submit_internal(p_work_id,p_operation_id,p_expected_updated_at,v,payload,p_signer_staff_id,signer_name,p_signature_png,image_md5);
end $function$;

create or replace function public.hq_c121_submit_internal(p_work_id uuid, p_operation_id uuid, p_expected_updated_at timestamp with time zone, p_by public.profiles, p_payload jsonb, p_signer_staff_id uuid, p_signer_name text, p_signature_png text, p_signature_md5 text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare w public.hq_works_v1500%rowtype; r jsonb; updated timestamptz; before jsonb; signature_id uuid; content_hash text; event jsonb; result jsonb;
begin
  r:=public.hq_c120_record_operation(p_operation_id,p_work_id,'提出',p_payload,p_by); if r is not null then return r; end if;
  select * into w from public.hq_works_v1500 where id=p_work_id for update;
  if not found or w.kind<>'下処理' then raise exception '下処理が見つかりません'; end if;
  if w.updated_at is distinct from p_expected_updated_at then return public.hq_c120_finish_operation(p_operation_id,jsonb_build_object('ok',false,'conflict',true,'current_updated_at',w.updated_at,'message','他の操作で内容が変わりました。画面を開き直してください')); end if;
  if not w.c120_flow then perform public.hq_c120_adopt_legacy(w.id,'提出',p_by); select * into w from public.hq_works_v1500 where id=p_work_id for update; end if;
  if w.review_status not in ('draft','returned') or w.status<>'完了' or w.inputs_saved_at is null then raise exception '日報を保存してから内容確認をしてください'; end if;
  if not exists(select 1 from public.hq_work_materials_v1500 where work_id=w.id) or not exists(select 1 from public.hq_work_members_v1500 where work_id=w.id and phase='作業') then raise exception '原料と作業者を保存してください'; end if;
  before:=public.hq_c120_work_snapshot(w.id); content_hash:=md5(before::text);
  -- c139：サイン画像があれば、名前がなくてもサインの記録を残す
  if nullif(btrim(coalesce(p_signature_png,'')),'') is not null then signature_id:=gen_random_uuid(); end if;
  event:=jsonb_build_object('at',now(),'by',p_by.display_name,'actor_id',p_by.id,
    'action',case when signature_id is null then '入力者確認・社員確認待ち' else '入力者サイン付き・社員確認待ち' end,
    'before',before,'after',before||jsonb_build_object('review_status','submitted'));
  if signature_id is not null then event:=event||jsonb_build_object('signer_staff_id',p_signer_staff_id,'signer_name',coalesce(p_signer_name,''),'signature_id',signature_id,'content_hash',content_hash); end if;
  update public.hq_works_v1500 set review_status='submitted',review_reason=null,reviewed_at=now(),reviewed_by_name=p_by.display_name,
    history=history||jsonb_build_array(event),updated_at=now() where id=w.id returning updated_at into updated;
  if signature_id is not null then
    insert into public.hq_prep_signatures_v1199c121(id,work_id,operation_id,signer_staff_id,signer_name,signature_png,signature_md5,content_hash,signed_by_profile_id,signed_by_account_name,signed_at,submitted_updated_at)
    values(signature_id,w.id,p_operation_id,p_signer_staff_id,coalesce(p_signer_name,''),p_signature_png,p_signature_md5,content_hash,p_by.id,p_by.display_name,now(),updated);
  end if;
  result:=jsonb_build_object('ok',true,'id',w.id,'updated_at',updated,'review_status','submitted');
  if signature_id is not null then
    result:=result||jsonb_build_object('signature_id',signature_id,'signer_name',nullif(coalesce(p_signer_name,''),''),'signed_at',(select signed_at from public.hq_prep_signatures_v1199c121 where id=signature_id));
  else
    result:=result||jsonb_build_object('signature_id',null,'signer_name',null,'signed_at',null);
  end if;
  return public.hq_c120_finish_operation(p_operation_id,result);
end $function$;

commit;
notify pgrst, 'reload schema';

-- 確認：3行とも「OK」なら成功です
select 'サインの名前は空でもよい' as 確認項目, case when (select not attnotnull from pg_attribute where attrelid='public.hq_prep_signatures_v1199c121'::regclass and attname='signer_staff_id') then 'OK' else '要確認' end as 判定
union all
select '提出：サインだけ必須', case when (select prosrc from pg_proc where proname='hq_prep_submit_v1199c121') like '%サインが必要です%' then 'OK' else '要確認' end
union all
select '名前なしでもサインを記録', case when (select prosrc from pg_proc where proname='hq_c121_submit_internal') like '%c139%' then 'OK' else '要確認' end;
