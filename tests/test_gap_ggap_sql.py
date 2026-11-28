import json
import unittest
from pathlib import Path

try:
    import test_gap_jgap_sql as base
except ImportError:  # リポジトリ直下から python3 -m unittest tests.test_gap_ggap_sql
    import tests.test_gap_jgap_sql as base

ROOT = Path(__file__).resolve().parents[1]
SQL076 = (ROOT / 'db/076_GAP一覧をGLOBALGAPサイトで自動更新.sql').read_text(encoding='utf-8')


class GapGgapSqlTests(base.GapJgapSqlTests):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.psql(SQL076)
        cls.psql(SQL076)  # 2回実行しても同じ

    # 075 のテストはもう一度は流さない
    test_targets = test_apply_rules = test_app_cannot_call_apply_and_import_keeps_newer = None

    def seed_g(self):
        rows = [("NCTファームネット", "レタス", "GGAP", "2026-08-27"), ("山下潤(JA全農青果センター)", "キャベツ", "GGAP", "2027-01-19"),
                ("アグリルーツ", "キャベツ", "GGAP", "2026-12-21"), ("山英野菜", "大根", "GGAP", "2026-12-06"),
                ("マルタケ", "人参", "GGAP", "2027-01-25"), ("マルタケ", "白菜", "JGAP", "2026-01-01")]
        vals = ",".join(f"(public.seika_party_norm_v1280('{a}'),'{a}','{b}','{b}','{c}','{d}')" for a, b, c, d in rows)
        self.psql("truncate public.qr_gap_certs_v1199c130; truncate public.qr_gap_auto_updates_v1199c174 cascade; truncate public.qr_gap_jgap_runs_v1199c174 cascade; "
                  f"insert into public.qr_gap_certs_v1199c130(coop_norm,coop_name,item_norm,item_name,certification,expires_on) values {vals}")

    def gapply(self, rows, run=None, user=None):
        sql = "select public.gap_ggap_apply_v1199c176($j$" + json.dumps(rows, ensure_ascii=False) + "$j$::jsonb, " + (str(run) if run else "null") + ")"
        if user:
            sql = f"set role authenticated; set app.\"user\"='{user}'; " + sql
        return json.loads(self.psql(sql, True).splitlines()[-1])

    def rows(self):
        c = lambda coop, item, ggn, vt, grp="": {"coop_name": coop, "item_name": item, "ggn": ggn, "result": "certified", "valid_to": vt, "group_name": grp}
        return [
            c("ＮＣＴファームネット(小出博基)", "レタス", "4063061714947", "2027-08-27", "NCT FARMNET, Inc."),  # かっこの前の名前で当たる・全角
            c("ＮＣＴファームネット（原淳一）", "レタス", "4063061714893", "2027-08-27", "NCT FARMNET, Inc."),   # 同じ行。2回目は同じ期限
            c("山下潤(JA全農青果センター）", "キャベツ", "4063651335163", "2027-01-19"),                        # 名前そのまま（かっこ込み）
            c("アグリルーツ", "キャベツ", "4063651718256", "2027-12-21"),
            c("株式会社 山英野菜", "大根", "4063651082456", "2026-06-06"),                                     # サイトのほうが古い
            c("丸西産業", "レタス", "4069453240773", "2027-07-12", "Marunishi Sangyo Co., Ltd."),             # GAP一覧にない
            {"coop_name": "マルタケ", "item_name": "人参", "ggn": "4063061957016", "result": "expired"},
            {"coop_name": "石嶋農園", "item_name": "長葱", "ggn": None, "result": "no_ggn"},
            {"coop_name": "やすたけ", "item_name": "胡瓜", "ggn": "4052852952552", "result": "not_found"},
        ]

    def test_names(self):
        names = self.psql("select public.gap_ggap_names_v1199c176('(株)野菜くらぶ(アグリフード千葉)')", True)
        for n in ("野菜くらぶ(アグリフード千葉)", "アグリフード千葉", "野菜くらぶ"):
            self.assertIn(n, names)

    def test_apply_rules(self):
        self.seed_g()
        out = self.gapply(self.rows())
        st = [(x["excel_name"], x["status"]) for x in out["report"]]
        self.assertEqual(st, [("ＮＣＴファームネット(小出博基)", "updated"), ("ＮＣＴファームネット（原淳一）", "same"),
                              ("山下潤(JA全農青果センター）", "same"), ("アグリルーツ", "updated"), ("株式会社 山英野菜", "older"),
                              ("丸西産業", "not_in_list"), ("マルタケ", "site_expired"), ("石嶋農園", "no_ggn"), ("やすたけ", "not_found")])
        self.assertEqual(out["report"][0]["coop_name"], "NCTファームネット")  # GAP一覧の名前で出す
        self.assertEqual(self.exp("NCTファームネット", "レタス"), "2027-08-27")
        self.assertEqual(self.exp("アグリルーツ", "キャベツ"), "2027-12-21")
        self.assertEqual(self.exp("山英野菜", "大根"), "2026-12-06")
        self.assertEqual(self.exp("マルタケ", "人参"), "2027-01-25")
        self.assertEqual(self.psql("select string_agg(jgap_no||':'||certification,',' order by id) from public.qr_gap_auto_updates_v1199c174", True),
                         "4063061714947:GGAP,4063651718256:GGAP")
        self.assertEqual(out["summary"]["updated"], 2)

    def test_append_to_jgap_run_and_app_cannot_call(self):
        self.seed_g()
        run = self.psql("insert into public.qr_gap_jgap_runs_v1199c174(days, summary, report) values (60, '{\"updated\":1}', '[{\"coop_name\":\"エプロン\",\"status\":\"updated\"}]') returning id", True).splitlines()[0]
        out = self.gapply(self.rows()[:4], run)
        self.assertEqual(str(out["run_id"]), run)
        sm = json.loads(self.psql(f"select summary from public.qr_gap_jgap_runs_v1199c174 where id={run}", True))
        self.assertEqual(sm["updated"], 3)  # JGAP 1件＋GGAP 2件
        self.assertEqual(self.psql(f"select jsonb_array_length(report) from public.qr_gap_jgap_runs_v1199c174 where id={run}", True), "5")
        self.assertEqual(self.psql("select count(*) from public.qr_gap_jgap_runs_v1199c174", True), "1")
        with self.assertRaises(AssertionError):
            self.gapply(self.rows(), None, base.ADMIN)
        # Excelを取り込み直しても、自動で延ばした新しい期限は残る（075 のしくみ）
        rows = [{"coop_name": "アグリルーツ", "item_name": "キャベツ", "certification": "GGAP", "expires_on": "2026-12-21"}]
        r = json.loads(self.psql(f"set app.\"user\"='{base.ADMIN}'; select public.replace_qr_gap_certs_v1199c130($j${json.dumps(rows, ensure_ascii=False)}$j$::jsonb)", True).splitlines()[-1])
        self.assertEqual(r["kept_auto"], 1)
        self.assertEqual(self.exp("アグリルーツ", "キャベツ"), "2027-12-21")


if __name__ == '__main__':
    unittest.main()
