"""c143：自動取り込み用のプログラム（tools/ship_auto.js）が、アプリと同じ読み方で登録する内容を出すことを、架空のファイルで確認する。"""
import json
import shutil
import subprocess
import tempfile
import unittest
from datetime import date, timedelta
from pathlib import Path

import openpyxl

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "tools" / "ship_auto.js"
TODAY = date(2026, 11, 22)
MASTERS = {"aliases": [{"raw_key": "大根", "raw_name": "大根", "item_name": "カット大根", "in_master": True}],
           "std": [{"item_name": "キャベツ", "case_kg": 10}, {"item_name": "人参", "case_kg": 15}],
           "items": ["キャベツ", "人参", "カット大根", "レタス", "胡瓜"]}


def plan_book(path, days, extra=None):
    wb = openpyxl.Workbook()
    wb.remove(wb.active)
    for d, kg in days:
        ws = wb.create_sheet(str(d.day))
        ws["B1"] = d
        ws["A2"] = "架空便"
        ws.merge_cells("A2:E3")
        ws["A4"] = "架空デリカ"
        ws.merge_cells("A4:C4")
        ws.append([])
        ws["A5"], ws["B5"], ws["C5"] = "キャベツ　10kg", kg, "cs"
        ws["A6"], ws["B6"], ws["C6"] = "大根　15kg", 2, "cs"
        if extra and d == extra[0]:
            ws["A7"], ws["B7"], ws["C7"] = extra[1], 1, "cs"
    wb.save(path)


def report_book(path, d):
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "シート1"
    ws["A1"], ws["C1"] = "産地報告", d
    ws["A4"] = "架空デリカ"
    ws["A6"], ws["B6"], ws["D6"] = "品目", "産地", "cs"
    ws["A7"], ws["B7"], ws["D7"] = "キャベツ", "茨城", "10ｋ"
    ws["D8"] = 11
    ws["A9"], ws["B9"], ws["D9"] = "大根", "北海道", "15ｋ2"
    wb.save(path)


@unittest.skipUnless(shutil.which("node"), "node がない")
class ShipAutoToolTests(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp(prefix="c143-"))
        self.addCleanup(shutil.rmtree, self.dir, True)
        (self.dir / "m.json").write_text(json.dumps(MASTERS, ensure_ascii=False), encoding="utf-8")

    def run_tool(self, *args):
        out = subprocess.run(["node", str(TOOL), *map(str, args)], capture_output=True, text=True, timeout=120)
        self.assertEqual(out.returncode, 0, out.stderr)
        return json.loads(out.stdout)

    def test_plan_only_tomorrow_to_a_week_and_skips_unchanged_and_unknown(self):
        d1, d2, d3, far = (TODAY + timedelta(days=n) for n in (1, 2, 3, 9))
        past = TODAY - timedelta(days=1)
        a, b = self.dir / "11月.xlsx", self.dir / "11月-埼玉・フジ　他.xlsx"
        plan_book(a, [(past, 5), (d1, 12), (d2, 3), (d3, 4), (far, 9)], extra=(d3, "しょうが　5kg"))
        plan_book(b, [(past, 1), (d1, 1), (d2, 1), (d3, 1), (far, 1)])
        cur = {"imports": [{"id": "I1", "delivery_date": d1.isoformat()}],
               "lines": [{"import_id": "I1", "customer_name": "架空デリカ", "item_name": "キャベツ", "kg": 120 + 10},
                         {"import_id": "I1", "customer_name": "架空デリカ", "item_name": "カット大根", "kg": 60}]}
        (self.dir / "cur.json").write_text(json.dumps(cur, ensure_ascii=False), encoding="utf-8")
        out = self.run_tool("plan", "--masters", self.dir / "m.json", "--current", self.dir / "cur.json", "--today", TODAY.isoformat(), a, b)
        days = {d["date"]: d for d in out["days"]}
        self.assertEqual(sorted(days), [d1.isoformat(), d2.isoformat(), d3.isoformat()])   # 過去の日・1週間より先は読まない
        self.assertEqual(days[d1.isoformat()]["state"], "same")                              # 中身が同じ日は登録しない
        self.assertEqual(days[d1.isoformat()]["lines"], [])
        self.assertEqual(days[d2.isoformat()]["state"], "new")
        self.assertEqual({(l["item_name"], l["kg"]) for l in days[d2.isoformat()]["lines"]}, {("キャベツ", 30), ("カット大根", 30), ("キャベツ", 10), ("カット大根", 30)})
        self.assertEqual(days[d3.isoformat()]["open"], 1)                                    # 知らない品名がある日は登録しない
        self.assertEqual(days[d3.isoformat()]["lines"], [])
        self.assertEqual([i["name"] for i in out["issues"]], ["しょうが 5kg"])

    def test_actual_maps_customers_from_the_plan(self):
        d = TODAY + timedelta(days=1)
        report_book(self.dir / "産地報告.xlsx", d)
        (self.dir / "plan.json").write_text(json.dumps({"active": {"id": "P"}, "lines": [{"customer_name": "架空デリカ", "item_name": "キャベツ", "kg": 100}]}, ensure_ascii=False), encoding="utf-8")
        (self.dir / "ca.json").write_text("[]", encoding="utf-8")
        out = self.run_tool("actual", "--masters", self.dir / "m.json", "--plan", self.dir / "plan.json", "--calias", self.dir / "ca.json", self.dir / "産地報告.xlsx")
        self.assertEqual(out["date"], d.isoformat())
        self.assertEqual(out["open"], 0)
        self.assertEqual({(l["customer_name"], l["item_name"], l["kg"]) for l in out["lines"]}, {("架空デリカ", "キャベツ", 110), ("架空デリカ", "カット大根", 30)})
        # 予定がない（客先が分からない）ときは要確認になり、登録しない
        out = self.run_tool("actual", "--masters", self.dir / "m.json", self.dir / "産地報告.xlsx")
        self.assertEqual(out["open"], 2)
        self.assertEqual({i["what"] for i in out["issues"]}, {"客先"})


if __name__ == "__main__":
    unittest.main()
