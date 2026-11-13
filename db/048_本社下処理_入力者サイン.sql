/*
048_本社下処理_入力者サイン.sql（v1.199-c121）

前提：047 を実行済みであること。
共有アカウントで日報を提出する下処理班について、入力者氏名と手書きサインを
提出時点の内容ハッシュ・共有アカウントとともに保存します。SQL適用だけでは
既存の作業・日報・履歴を変更しません。
*/
begin;

do $block$
begin
  if to_regclass('public.hq_works_v1500') is null
     or to_regclass('public.hq_staff_v1500') is null
     or to_regclass('public.hq_prep_operations_v1199c120') is null
     or to_regprocedure('public.hq_c120_work_snapshot(uuid)') is null
     or to_regprocedure('public.hq_c120_record_operation(uuid,uuid,text,jsonb,public.profiles)') is null then
    raise exception '先に db/047_本社下処理_確認と差し戻しと作業時刻.sql を実行してください';
  end if;
end $block$;

create table if not exists public.hq_prep_signatures_v1199c121 (
  id uuid primary key,
  work_id uuid not null references public.hq_works_v1500(id) on delete cascade,
  operation_id uuid not null unique,
  signer_staff_id uuid not null references public.hq_staff_v1500(id),
  signer_name text not null,
  signature_png text not null,
  signature_md5 text not null,
  content_hash text not null,
  signed_by_profile_id uuid not null references public.profiles(id),
  signed_by_account_name text not null,
  signed_at timestamptz not null default now(),
  submitted_updated_at timestamptz not null
);
create index if not exists hq_prep_signatures_v1199c121_work_signed_idx
  on public.hq_prep_signatures_v1199c121(work_id, signed_at desc, id desc);
alter table public.hq_prep_signatures_v1199c121 enable row level security;
revoke all on table public.hq_prep_signatures_v1199c121 from public, anon, authenticated;
grant all on table public.hq_prep_signatures_v1199c121 to service_role;

-- 画像そのものは再送台帳へ入れず、内容比較に必要なMD5だけを保存する。
create or replace function public.hq_c121_submit_internal(
  p_work_id uuid,p_operation_id uuid,p_expected_updated_at timestamptz,
  p_by public.profiles,p_payload jsonb,p_signer_staff_id uuid,p_signer_name text,
  p_signature_png text,p_signature_md5 text
) returns jsonb language plpgsql security definer set search_path to ''
as $f$
declare
  w public.hq_works_v1500%rowtype; r jsonb; updated timestamptz; before jsonb;
  signature_id uuid; content_hash text; event jsonb; result jsonb;
begin
  r:=public.hq_c120_record_operation(p_operation_id,p_work_id,'提出',p_payload,p_by);
  if r is not null then return r; end if;
  select * into w from public.hq_works_v1500 where id=p_work_id for update;
  if not found or w.kind<>'下処理' then raise exception '下処理が見つかりません'; end if;
  if w.updated_at is distinct from p_expected_updated_at then
    return public.hq_c120_finish_operation(p_operation_id,jsonb_build_object('ok',false,'conflict',true,'current_updated_at',w.updated_at,'message','他の操作で内容が変わりました。画面を開き直してください'));
  end if;
  if not w.c120_flow then
    perform public.hq_c120_adopt_legacy(w.id,'提出',p_by);
    select * into w from public.hq_works_v1500 where id=p_work_id for update;
  end if;
  if w.review_status not in ('draft','returned') or w.status<>'完了' or w.inputs_saved_at is null then
    raise exception '日報を保存してから内容確認をしてください';
  end if;
  if not exists(select 1 from public.hq_work_materials_v1500 where work_id=w.id)
     or not exists(select 1 from public.hq_work_members_v1500 where work_id=w.id and phase='作業') then
    raise exception '原料と作業者を保存してください';
  end if;

  before:=public.hq_c120_work_snapshot(w.id);
  content_hash:=md5(before::text);
  if p_signer_staff_id is not null then signature_id:=gen_random_uuid(); end if;
  event:=jsonb_build_object(
    'at',now(),'by',p_by.display_name,'actor_id',p_by.id,
    'action',case when signature_id is null then '入力者確認・社員確認待ち' else '入力者サイン付き・社員確認待ち' end,
    'before',before,'after',before||jsonb_build_object('review_status','submitted')
  );
  if signature_id is not null then
    event:=event||jsonb_build_object('signer_staff_id',p_signer_staff_id,'signer_name',p_signer_name,'signature_id',signature_id,'content_hash',content_hash);
  end if;
  update public.hq_works_v1500
     set review_status='submitted',review_reason=null,reviewed_at=now(),reviewed_by_name=p_by.display_name,
         history=history||jsonb_build_array(event),updated_at=now()
   where id=w.id returning updated_at into updated;
  if signature_id is not null then
    insert into public.hq_prep_signatures_v1199c121(
      id,work_id,operation_id,signer_staff_id,signer_name,signature_png,signature_md5,content_hash,
      signed_by_profile_id,signed_by_account_name,signed_at,submitted_updated_at
    ) values (
      signature_id,w.id,p_operation_id,p_signer_staff_id,p_signer_name,p_signature_png,p_signature_md5,content_hash,
      p_by.id,p_by.display_name,now(),updated
    );
  end if;
  result:=jsonb_build_object('ok',true,'id',w.id,'updated_at',updated,'review_status','submitted');
  if signature_id is not null then
    result:=result||jsonb_build_object('signature_id',signature_id,'signer_name',p_signer_name,'signed_at',(select signed_at from public.hq_prep_signatures_v1199c121 where id=signature_id));
  else
    result:=result||jsonb_build_object('signature_id',null,'signer_name',null,'signed_at',null);
  end if;
  return public.hq_c120_finish_operation(p_operation_id,result);
end $f$;

create or replace function public.hq_prep_submit_v1199c121(
  p_work_id uuid,p_operation_id uuid,p_expected_updated_at timestamptz,
  p_signer_staff_id uuid,p_signature_png text
) returns jsonb language plpgsql security definer set search_path to ''
as $f$
declare
  v public.profiles; signer_name text; image_bytes bytea; image_md5 text; payload jsonb;
  has_staff boolean:=p_signer_staff_id is not null; has_image boolean:=nullif(btrim(coalesce(p_signature_png,'')),'') is not null;
  image_body text; chunk_at integer; chunk_length integer; chunk_type text; saw_ihdr boolean:=false; saw_idat boolean:=false; saw_iend boolean:=false;
begin
  v:=public.hq_actor_v1400(array['admin','hq_worker','hq_prep']);
  if has_staff <> has_image or (v.role='hq_prep' and not (has_staff and has_image)) then
    raise exception '入力者の氏名とサインが必要です';
  end if;
  if not has_staff then
    payload:=jsonb_build_object('work_id',p_work_id,'expected_updated_at',p_expected_updated_at);
    return public.hq_c121_submit_internal(p_work_id,p_operation_id,p_expected_updated_at,v,payload,null,null,null,null);
  end if;
  select s.name into signer_name from public.hq_staff_v1500 s where s.id=p_signer_staff_id and s.deleted_at is null;
  if signer_name is null then raise exception '在籍中のスタッフを選んでください'; end if;
  if left(p_signature_png,22)<>'data:image/png;base64,' then raise exception 'サイン画像はPNGで送ってください'; end if;
  image_body:=substring(p_signature_png from 23);
  begin image_bytes:=decode(image_body,'base64'); exception when others then raise exception 'サイン画像はPNGとして読み取れません'; end;
  -- タブレットの600px程度の署名は十分収まり、極端に小さい空画像と約200KB超を拒否する。
  if octet_length(image_bytes)<700 or octet_length(image_bytes)>204800
     or encode(substring(image_bytes from 1 for 8),'hex')<>'89504e470d0a1a0a' then
    raise exception 'サイン画像は有効なPNGを入れてください';
  end if;
  -- PNGの必須チャンクを末尾まで構文検査する。画像データは保存時に復号せず、そのまま凍結する。
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
end $f$;

-- 旧3引数入口は社員アカウントの互換性を保ち、共有下処理アカウントだけ新版へ誘導する。
create or replace function public.hq_prep_submit_v1199c120(p_work_id uuid,p_operation_id uuid,p_expected_updated_at timestamptz)
returns jsonb language plpgsql security definer set search_path to ''
as $f$
declare v public.profiles; payload jsonb;
begin
  v:=public.hq_actor_v1400(array['admin','hq_worker','hq_prep']);
  if v.role='hq_prep' then raise exception '署名が必要です。最新版の画面を使ってください'; end if;
  payload:=jsonb_build_object('work_id',p_work_id,'expected_updated_at',p_expected_updated_at);
  return public.hq_c121_submit_internal(p_work_id,p_operation_id,p_expected_updated_at,v,payload,null,null,null,null);
end $f$;

create or replace function public.hq_prep_signatures_v1199c121(p_work_id uuid)
returns jsonb language plpgsql stable security definer set search_path to ''
as $f$
begin
  perform public.hq_actor_v1400(array['admin','hq_worker','hq_prep']);
  return (select coalesce(jsonb_agg(jsonb_build_object(
    'id',s.id,'signer_staff_id',s.signer_staff_id,'signer_name',s.signer_name,
    'signature_png',s.signature_png,'signed_at',s.signed_at,
    'signed_by_account_name',s.signed_by_account_name,'content_hash',s.content_hash
  ) order by s.signed_at desc,s.id desc),'[]'::jsonb)
  from public.hq_prep_signatures_v1199c121 s where s.work_id=p_work_id);
end $f$;

-- 公開RPCだけ authenticated。署名表・提出内部関数は直接アクセスさせない。
do $block$
declare f text;
begin
  foreach f in array array[
    'public.hq_prep_submit_v1199c120(uuid,uuid,timestamp with time zone)',
    'public.hq_prep_submit_v1199c121(uuid,uuid,timestamp with time zone,uuid,text)',
    'public.hq_prep_signatures_v1199c121(uuid)'
  ] loop
    execute format('revoke all on function %s from public, anon',f);
    execute format('grant execute on function %s to authenticated, service_role',f);
  end loop;
  foreach f in array array[
    'public.hq_c121_submit_internal(uuid,uuid,timestamp with time zone,public.profiles,jsonb,uuid,text,text,text)'
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role',f);
  end loop;
end $block$;
commit;
notify pgrst,'reload schema';

/* 成功の確かめ方：下の5行がすべてOKなら成功です。 */
select 'c121署名表' as 確認,case when to_regclass('public.hq_prep_signatures_v1199c121') is not null then 'OK' else 'NG' end as 結果
union all select 'c121署名提出RPC',case when to_regprocedure('public.hq_prep_submit_v1199c121(uuid,uuid,timestamp with time zone,uuid,text)') is not null then 'OK' else 'NG' end
union all select 'c121署名一覧RPC',case when to_regprocedure('public.hq_prep_signatures_v1199c121(uuid)') is not null then 'OK' else 'NG' end
union all select 'c121旧提出RPC',case when to_regprocedure('public.hq_prep_submit_v1199c120(uuid,uuid,timestamp with time zone)') is not null then 'OK' else 'NG' end
union all select 'c121署名表権限',case when not has_table_privilege('authenticated','public.hq_prep_signatures_v1199c121','select,insert,update') then 'OK' else 'NG' end;
