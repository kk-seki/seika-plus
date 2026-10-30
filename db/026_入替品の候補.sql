/*
026_入替品の候補.sql（v1.199-c68）
日報登録の出来高（入替品）の候補リストを作ります。どの端末からも同じ候補が出ます。
・初回だけ、在庫表「その他」のキャベツ〜小葱の12品を候補として入れます（2回目以降は入れ直しません）。
・候補の追加・名前の変更・並び替え・候補から外す（隠すだけ）は、製造・歩留まりの「入替品登録」で行います（管理者・青果社員）。
前提：000〜025を実行済みであること。何度実行しても同じ結果になります。在庫は変わりません。
*/
begin;

create table if not exists public.trim_output_candidates_v1680(
  id uuid primary key default gen_random_uuid(),
  name text not null,
  sort integer not null default 0,
  active boolean not null default true,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists trim_output_candidates_v1680_name_uq on public.trim_output_candidates_v1680(name);
alter table public.trim_output_candidates_v1680 enable row level security;
revoke all on table public.trim_output_candidates_v1680 from anon, authenticated;

do $$
begin
  if not exists(select 1 from public.trim_output_candidates_v1680) then
    insert into public.trim_output_candidates_v1680(name,sort)
    select n, o*10 from unnest(array[
      'キャベツ 10kg/入替品','葉付大根 15kg/入替品','カット大根 15kg/入替品',
      '人参 15kg/入替品','人参 10kg/入替品','人参 5kg/入替品',
      '紫キャベツ 10kg/入替品','胡瓜 15kg/入替品','胡瓜 10kg/入替品','胡瓜 5kg/入替品',
      'トヨシロ 10kg入れ','小葱5kg/入替品'
    ]) with ordinality as t(n,o);
  end if;
end $$;

create or replace function public.list_trim_output_candidates_v1680(p_include_hidden boolean default false)
returns jsonb language plpgsql stable security definer set search_path to ''
as $function$
begin
  perform public.seika_v1144_require_active_profile();
  return jsonb_build_object('ok',true,'rows',coalesce((
    select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'sort',c.sort,'active',c.active) order by c.sort, c.name)
    from public.trim_output_candidates_v1680 c where coalesce(p_include_hidden,false) or c.active),'[]'::jsonb));
end;
$function$;

create or replace function public.save_trim_output_candidate_v1680(p_id uuid, p_name text, p_active boolean default true)
returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare v_name text := btrim(regexp_replace(coalesce(p_name,''),'\s+',' ','g')); v_row public.trim_output_candidates_v1680;
begin
  perform public.trimming_require_role(array['admin','worker']);
  if v_name = '' then return jsonb_build_object('ok',false,'message','名前を入力してください'); end if;
  if exists(select 1 from public.trim_output_candidates_v1680 where name = v_name and (p_id is null or id <> p_id)) then
    return jsonb_build_object('ok',false,'message','同じ名前の候補がすでにあります（候補から外した中も含みます）');
  end if;
  if p_id is null then
    insert into public.trim_output_candidates_v1680(name,sort,active,created_by)
    values(v_name,coalesce((select max(sort) from public.trim_output_candidates_v1680),0)+10,coalesce(p_active,true),auth.uid())
    returning * into v_row;
  else
    update public.trim_output_candidates_v1680 set name=v_name, active=coalesce(p_active,active), updated_at=now()
    where id=p_id returning * into v_row;
    if not found then return jsonb_build_object('ok',false,'message','候補が見つかりません。画面を開き直してください'); end if;
  end if;
  return jsonb_build_object('ok',true,'row',to_jsonb(v_row));
end;
$function$;

create or replace function public.move_trim_output_candidate_v1680(p_id uuid, p_dir integer)
returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare v_cur public.trim_output_candidates_v1680; v_other public.trim_output_candidates_v1680;
begin
  perform public.trimming_require_role(array['admin','worker']);
  with o as (select id, row_number() over(order by sort, name)*10 rn from public.trim_output_candidates_v1680)
  update public.trim_output_candidates_v1680 c set sort=o.rn from o where c.id=o.id and c.sort<>o.rn;
  select * into v_cur from public.trim_output_candidates_v1680 where id=p_id;
  if not found then return jsonb_build_object('ok',false,'message','候補が見つかりません'); end if;
  if p_dir < 0 then
    select * into v_other from public.trim_output_candidates_v1680 where sort < v_cur.sort order by sort desc limit 1;
  else
    select * into v_other from public.trim_output_candidates_v1680 where sort > v_cur.sort order by sort limit 1;
  end if;
  if v_other.id is null then return jsonb_build_object('ok',true,'moved',false); end if;
  update public.trim_output_candidates_v1680 set sort=v_other.sort, updated_at=now() where id=v_cur.id;
  update public.trim_output_candidates_v1680 set sort=v_cur.sort, updated_at=now() where id=v_other.id;
  return jsonb_build_object('ok',true,'moved',true);
end;
$function$;

revoke all on function public.list_trim_output_candidates_v1680(boolean) from public, anon;
grant execute on function public.list_trim_output_candidates_v1680(boolean) to authenticated, service_role;
revoke all on function public.save_trim_output_candidate_v1680(uuid,text,boolean) from public, anon;
grant execute on function public.save_trim_output_candidate_v1680(uuid,text,boolean) to authenticated, service_role;
revoke all on function public.move_trim_output_candidate_v1680(uuid,integer) from public, anon;
grant execute on function public.move_trim_output_candidate_v1680(uuid,integer) to authenticated, service_role;

commit;

notify pgrst, 'reload schema';

/* 成功の確かめ方：下のSELECTの4行がすべて「OK」なら成功です。 */
select '入替品の候補の表' as 項目, case when to_regclass('public.trim_output_candidates_v1680') is not null then 'OK' else 'NG' end as 結果
union all select '最初の候補（12品）', case when (select count(*) from public.trim_output_candidates_v1680)>=12 then 'OK（'||(select count(*) from public.trim_output_candidates_v1680)||'品）' else 'NG' end
union all select '候補を読み込む処理', case when to_regprocedure('public.list_trim_output_candidates_v1680(boolean)') is not null then 'OK' else 'NG' end
union all select '候補を登録・並び替える処理', case when to_regprocedure('public.save_trim_output_candidate_v1680(uuid,text,boolean)') is not null and to_regprocedure('public.move_trim_output_candidate_v1680(uuid,integer)') is not null then 'OK' else 'NG' end;
