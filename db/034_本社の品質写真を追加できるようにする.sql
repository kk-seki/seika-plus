-- v1.199-c80 本社の品質評価に、あとから写真を追加できるようにする
-- 原因：本社の受け入れ画面の不具合で、写真の中身ではなく「[object Object]」という15文字だけが保存されていた（アプリはc80で修正）。
-- 修正：
--  1) 本社の品質評価一覧の「写真を追加」から、評価済みの原料に写真を追加できるようにする（1件につき5枚まで）。
--     追加できるのは、管理者・本社社員・荷受け担当（受け入れで写真を付けられる人と同じ）。
--  2) 中身が保存されていない写真（1KB未満の壊れた写真）を、品質評価の写真の一覧から外す。
--     写真の枚数が0になった要確認・不良は、一覧に「写真が保存されていません」と出ます。
-- 何度実行しても同じ結果になります。
begin;

create or replace function public.hq_add_quality_photos_v1199c80(p_lot_id uuid, p_photo_paths text[])
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v public.profiles;
  l public.hq_lots_v1400%rowtype;
  p text;
begin
  v := public.hq_actor_v1400(array['admin','hq_worker','hq_receiver']);
  select * into l from public.hq_lots_v1400 where id = p_lot_id for update;
  if not found then raise exception 'ロットが見つかりません'; end if;
  if l.grade is null then raise exception 'まだ品質評価をしていないロットです'; end if;
  if coalesce(array_length(p_photo_paths,1),0) < 1 then raise exception '写真を選んでください'; end if;
  foreach p in array p_photo_paths loop
    if p is null or p not like (p_lot_id::text || '/%') then raise exception '写真の保存場所が正しくありません'; end if;
  end loop;
  if coalesce(array_length(l.photo_paths,1),0) + array_length(p_photo_paths,1) > 5 then
    raise exception '写真は1件につき5枚までです（今 % 枚）', coalesce(array_length(l.photo_paths,1),0);
  end if;
  update public.hq_lots_v1400
     set photo_paths = coalesce(photo_paths,'{}') || p_photo_paths,
         updated_at = now()
   where id = p_lot_id
  returning * into l;
  return jsonb_build_object('ok', true, 'photo_count', coalesce(array_length(l.photo_paths,1),0));
end $$;

revoke all on function public.hq_add_quality_photos_v1199c80(uuid, text[]) from public, anon;
grant execute on function public.hq_add_quality_photos_v1199c80(uuid, text[]) to authenticated;

drop table if exists pg_temp.c80_fixed;
create temp table c80_fixed(n int not null default 0);
insert into c80_fixed values (0);

do $$
declare v_n int := 0;
begin
  if to_regclass('storage.objects') is not null then
    execute $q$
      with broken as (
        select l.id, array_agg(u.p order by u.ord) filter (where c.ok) as keep_paths
          from public.hq_lots_v1400 l
          cross join lateral unnest(l.photo_paths) with ordinality u(p, ord)
          cross join lateral (
            select exists (select 1 from storage.objects o
                            where o.bucket_id = 'hq-quality-photos' and o.name = u.p
                              and coalesce((o.metadata->>'size')::bigint, 0) >= 1024) ok
          ) c
         group by l.id
        having bool_or(not c.ok)
      ), t as (
        update public.hq_lots_v1400 l set photo_paths = coalesce(b.keep_paths, '{}'), updated_at = now()
          from broken b where l.id = b.id
        returning l.id
      ) select count(*) from t
    $q$ into v_n;
  end if;
  update pg_temp.c80_fixed set n = v_n;
end $$;

commit;

-- 確認：3行とも「OK」なら成功です（1行目は今回、壊れた写真を外した件数。2回目以降は0件）
select '壊れた写真を外した品質評価 ' || (select n from pg_temp.c80_fixed) || '件' as 確認項目, 'OK' as 判定
union all
select '写真を追加する仕組み',
       case when to_regprocedure('public.hq_add_quality_photos_v1199c80(uuid,text[])') is not null then 'OK' else '要確認' end
union all
select '写真の保存（本社の写真の置き場所）',
       case when to_regclass('storage.objects') is null then 'OK（対象外）'
            when exists (select 1 from pg_policies where schemaname = 'storage' and policyname = 'hq_photos_v1400_insert') then 'OK' else '要確認' end;
