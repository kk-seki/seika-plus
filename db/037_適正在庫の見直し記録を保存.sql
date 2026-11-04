-- v1.199-c88 適正在庫の見直し記録（いつ・誰が「継続」「変更」したか）をサーバーに保存する
--  ・今までは端末の中にだけ残っていたため、別の端末では「見直しが必要」と出ていました。
--  ・品目ごとに新しい記録だけを上書きします。ほかのデータ（在庫・適正在庫の数字・担当）は変わりません。
--  何度実行しても同じ結果になります。
begin;

create or replace function public.save_optimal_stock_meta_v1199c88(p_meta jsonb)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare
  v public.profiles%rowtype;
  v_state public.app_state%rowtype;
  v_cur jsonb;
  v_key text;
  v_val jsonb;
  v_old jsonb;
  v_new jsonb;
  v_out jsonb := '{}'::jsonb;
begin
  v := public.seika_v1136_require_roles(array['admin','buyer']);
  if jsonb_typeof(coalesce(p_meta,'null'::jsonb)) <> 'object' then raise exception '保存データが正しくありません'; end if;
  select * into v_state from public.app_state where id = 'ishioka_inventory_production_v2' for update;
  if not found then raise exception '保存先が見つかりません'; end if;
  v_cur := case when jsonb_typeof(v_state.data->'optimalStockMeta') = 'object' then v_state.data->'optimalStockMeta' else '{}'::jsonb end;
  for v_key, v_val in select key, value from jsonb_each(p_meta) loop
    continue when jsonb_typeof(v_val) <> 'object' or nullif(v_val->>'updatedAt','') is null or length(v_key) > 100;
    v_new := jsonb_build_object(
      'updatedAt', left(v_val->>'updatedAt', 40),
      'updatedBy', coalesce(nullif(v.display_name,''), left(coalesce(v_val->>'updatedBy',''), 60)),
      'userId', left(coalesce(v_val->>'userId',''), 60),
      'reviewResult', left(coalesce(v_val->>'reviewResult',''), 20));
    v_old := v_cur->v_key;
    if v_old is null or coalesce(v_old->>'updatedAt','') <= (v_new->>'updatedAt') then
      v_cur := jsonb_set(v_cur, array[v_key], v_new, true);
    end if;
    v_out := jsonb_set(v_out, array[v_key], v_cur->v_key, true);
  end loop;
  update public.app_state set data = jsonb_set(coalesce(data,'{}'::jsonb), '{optimalStockMeta}', v_cur, true)
   where id = 'ishioka_inventory_production_v2';
  return jsonb_build_object('ok', true, 'meta', v_out);
end $$;
revoke all on function public.save_optimal_stock_meta_v1199c88(jsonb) from public, anon;
grant execute on function public.save_optimal_stock_meta_v1199c88(jsonb) to authenticated, service_role;

commit;
notify pgrst, 'reload schema';

-- 確認：「OK」と出れば成功です
select '見直しの記録を保存する仕組み' as 確認項目,
       case when to_regprocedure('public.save_optimal_stock_meta_v1199c88(jsonb)') is not null then 'OK' else '要確認' end as 判定;
