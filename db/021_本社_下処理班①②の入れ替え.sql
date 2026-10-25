/*
021_本社_下処理班①②の入れ替え.sql（v1.199-c59）
下処理班①と下処理班②のメンバーを、そのまま入れ替えます。
（今の①の10名 → ②へ、今の②の12名 → ①へ。班名と印刷グループの両方を入れ替えます）
前提：019・020を実行済みであること。
1回だけ入れ替わるようにしてあります。2回実行しても元に戻りません（実行済みの印を残します）。
QRはそのまま使えます。入れ替えたあとは、①と②の一覧ボードを印刷し直してください。
過去の作業時間の記録に残っている班名は変えません。
説明は行頭のハイフン2つを使わない書き方にしています（スマホから貼り付けても壊れないようにするため）。
*/
begin;
update public.hq_staff_v1500
set team = case team when '下処理班①' then '下処理班②' else '下処理班①' end,
    print_group = case print_group when 1 then 2 else 1 end,
    updated_at = now()
where deleted_at is null
  and ((team = '下処理班①' and print_group = 1) or (team = '下処理班②' and print_group = 2))
  and not exists (select 1 from public.hq_settings_v1500 where key = 'done_021_swap_prep12');
insert into public.hq_settings_v1500(key, value, updated_by_name)
values ('done_021_swap_prep12', to_jsonb(now()::text), '021 下処理班①②の入れ替え')
on conflict (key) do nothing;
commit;

/* 成功の確かめ方：下のSELECTを実行して、2行とも「OK」になれば成功です。 */
select '①下処理班' as グループ, count(*) as 人数,
  case when count(*) filter (where name = '市毛 志津子') = 1 and count(*) filter (where name = '大内 せつ子') = 0 then 'OK' else 'NG' end as 結果
from public.hq_staff_v1500 where print_group = 1 and deleted_at is null
union all
select '②下処理班', count(*),
  case when count(*) filter (where name = '大内 せつ子') = 1 and count(*) filter (where name = '市毛 志津子') = 0 then 'OK' else 'NG' end
from public.hq_staff_v1500 where print_group = 2 and deleted_at is null;
