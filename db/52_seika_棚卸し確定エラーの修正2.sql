-- 52 棚卸し確定エラー（23514 check制約違反）の修正
-- 原因：月末棚卸しのQR差異は履歴の種類を「棚卸し調整増／棚卸し調整減」で記録しますが、
--       qr_lot_movements の種類（movement_type）の許可リストにこの2つが入っていなかったため、
--       履歴を書き込む時点で拒否されていました。
-- 対応：
--  1) 種類の許可リストに「棚卸し調整増」「棚卸し調整減」を追加（既存の許可項目・他の条件はそのまま）
--  2) 履歴の「反映後数量」を実際に保存する数量（0未満にならない値）にそろえる
--  3) 最後に qr_lot_movements の制約一覧を表示（まだ失敗する場合の確認用）
begin;

do $$
declare
  r record;
  v_new text;
  v_pat text := '(movement_type\)?(::text)?\s*=\s*ANY\s*\(\(?ARRAY\[)';
begin
  for r in
    select con.conname, pg_get_constraintdef(con.oid) as def
      from pg_constraint con
     where con.conrelid = 'public.qr_lot_movements'::regclass
       and con.contype = 'c'
       and pg_get_constraintdef(con.oid) ilike '%movement_type%'
  loop
    if position('棚卸し調整減' in r.def) > 0 and position('棚卸し調整増' in r.def) > 0 then
      raise notice '% は追加済みです', r.conname;
    elsif r.def ~ v_pat then
      v_new := regexp_replace(r.def, v_pat, '\1''棚卸し調整増''::text, ''棚卸し調整減''::text, ');
      execute format('alter table public.qr_lot_movements drop constraint %I', r.conname);
      execute format('alter table public.qr_lot_movements add constraint %I %s', r.conname, v_new);
      raise notice '% に棚卸し調整増・減を追加しました', r.conname;
    else
      raise notice '% は形式が異なるため変更していません：%', r.conname, r.def;
    end if;
  end loop;
end $$;

do $$
declare
  v_def text;
begin
  v_def := pg_get_functiondef('public.v188_apply_month_end_qr_adjustment(text,text,text,text,numeric,numeric,text,text,text,text)'::regprocedure);
  if position('''after_quantity'', v_after_qty,' in v_def) > 0 then
    execute replace(v_def, '''after_quantity'', v_after_qty,', '''after_quantity'', v_stored_after_qty,');
    raise notice '反映後数量を修正しました';
  else
    raise notice '反映後数量は修正済みです';
  end if;
end $$;

commit;

-- 確認：qr_lot_movements の制約一覧（「棚卸し調整減」が含まれていればOK）
select con.conname as 制約名,
       case when pg_get_constraintdef(con.oid) ilike '%movement_type%'
            then case when position('棚卸し調整減' in pg_get_constraintdef(con.oid)) > 0 then 'OK' else '★未対応' end
            else '' end as 判定,
       pg_get_constraintdef(con.oid) as 定義
  from pg_constraint con
 where con.conrelid = 'public.qr_lot_movements'::regclass
   and con.contype = 'c'
 order by 1;
