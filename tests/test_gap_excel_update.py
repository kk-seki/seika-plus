"""tools/gap_excel_update.py（GAP一覧Excelの期限を書き換える。月2回のGAPチェック用）"""
import datetime
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import openpyxl

ROOT = Path(__file__).resolve().parents[1]
PROG = ROOT / 'tools/gap_excel_update.py'


def make_book(path):
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = 'Sheet1'
    ws['E1'] = 'GAP認証農場取引及び検討一覧'
    ws['B3'], ws['D3'], ws['AO3'], ws['AP3'], ws['AQ3'] = '産地', '品目', '認証', '番号', '認証期限'
    rows = [
        ('★認証取得済', 'エプロン', '玉葱', 'JGAP', 10000155, '2026/07/05\t', None),
        ('★品目追加予定', '永野青果', '玉葱', 'JGAP', 420000027, datetime.datetime(2026, 12, 26), None),
        ('★認証取得済', '永野青果', 'レタス', 'JGAP', 420000027, datetime.datetime(2026, 12, 26), None),
        ('★認証取得済', '山下潤(JA全農青果センター）', 'キャベツ', 'GGAP', '00113-TKNPV-0005\t', datetime.datetime(2027, 1, 19), 4063651335163),
        ('★認証取得済', '丸西産業', 'レタス', 'GGAP', 4069453240773, '-', 4063651583083),
        ('★認証取得済', 'ＮＣＴファームネット（伊藤長美）', 'レタス', 'GGAP', None, '-', '00109-LLKXP-0003'),
        ('★認証取得済', 'シナジーファーム', '胡瓜', 'GGAP', 4056186018359, datetime.datetime(2027, 5, 17), None),  # 期限が先
        ('★取引検討中', '検討農園', 'レタス', 'GGAP', 4050000000001, None, None),
    ]
    for i, (a, b, d, ao, ap, aq, ar) in enumerate(rows, start=5):
        ws.cell(i, 1, a); ws.cell(i, 2, b); ws.cell(i, 4, d); ws.cell(i, 41, ao); ws.cell(i, 42, ap); ws.cell(i, 43, aq); ws.cell(i, 44, ar)
        ws.cell(i, 43).number_format = 'yyyy/m/d;@'
    ws2 = wb.create_sheet('Sheet2')
    ws2['A2'] = '玉葱GAP産地'
    wb.save(path)


def run(*args):
    r = subprocess.run([sys.executable, '-I', str(PROG), *map(str, args)], capture_output=True, text=True, timeout=60)
    if r.returncode:
        raise AssertionError(r.stderr)
    return json.loads(r.stdout)


class GapExcelUpdateTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.d = Path(self.tmp.name)
        self.src = self.d / 'GAP認証産地　26.10.01更新 .xlsx'
        make_book(self.src)

    def tearDown(self):
        self.tmp.cleanup()

    def values(self, path):
        ws = openpyxl.load_workbook(path)['Sheet1']
        return {r: ws.cell(r, 43).value for r in range(5, 13)}, ws

    def test_jgap_then_ggap_same_day_and_marks(self):
        ups = self.d / 'ups.json'
        ups.write_text(json.dumps([{'coop_name': 'エプロン', 'item_name': '玉葱', 'jgap_no': '010000155', 'jgap_name': '株式会社エプロン', 'old_expires': '2026-07-05', 'new_expires': '2028-07-05'},
                                   {'coop_name': '永野青果', 'item_name': 'レタス', 'jgap_no': '420000027', 'jgap_name': '株式会社 永野青果', 'old_expires': '2026-12-26', 'new_expires': '2028-12-26'},
                                   {'coop_name': 'どこにもない', 'item_name': 'レタス', 'jgap_no': '1', 'new_expires': '2028-01-01'}], ensure_ascii=False), encoding='utf-8')
        out = self.d / 'GAP認証産地　26.12.01更新.xlsx'
        r = run('jgap', self.src, ups, out, '2026-12-01')
        self.assertTrue(r['saved'])
        self.assertEqual([c['row'] for c in r['changed']], [5, 7])
        self.assertEqual(len(r['not_found']), 1)
        # GGAP：調べる行（期限切れ・60日以内・空欄、★認証取得済だけ）とGGN（AP か AR の 40… の13けた）
        t = run('ggap-targets', out, '2026-12-01', 60)
        self.assertEqual([(x['row'], x['ggn']) for x in t], [(8, '4063651335163'), (9, '4069453240773'), (10, None)])
        res = self.d / 'res.json'
        res.write_text(json.dumps([{'row': 8, 'ggn': '4063651335163', 'result': 'certified', 'valid_to': '2027-01-19'},
                                   {'row': 9, 'ggn': '4069453240773', 'result': 'certified', 'valid_to': '2027-07-12', 'group_name': 'Marunishi Sangyo Co., Ltd.'},
                                   {'row': 10, 'ggn': None, 'result': 'no_ggn'},
                                   {'row': 11, 'ggn': '9999999999999', 'result': 'certified', 'valid_to': '2030-01-01'}], ensure_ascii=False), encoding='utf-8')
        g = run('ggap-apply', out, res, out, '2026-12-01')
        self.assertTrue(g['saved'])
        self.assertEqual([(c['row'], c['before'], c['after']) for c in g['changed']], [(9, '-', '2027/07/12')])
        self.assertEqual([x['result'] for x in g['rows']], ['certified', 'certified', 'no_ggn'])  # GGNが合わない行（11）は書かない
        v, ws = self.values(out)
        self.assertEqual(v[5], datetime.datetime(2028, 7, 5))
        self.assertEqual(v[6], datetime.datetime(2026, 12, 26))   # ★品目追加予定の玉葱は触らない
        self.assertEqual(v[9], datetime.datetime(2027, 7, 12))
        self.assertEqual(v[11], datetime.datetime(2027, 5, 17))
        yellow = [r for r in range(5, 13) if ws.cell(r, 43).fill.fill_type == 'solid']
        self.assertEqual(yellow, [5, 7, 9])  # 同じ日の JGAP と GGAP の黄色は両方残る
        self.assertIn('GLOBALG.A.P.サイトで自動更新 2026/12/01', ws.cell(9, 43).comment.text)
        # 次の回（別の日）：前の黄色・メモは消え、今回の分だけ黄色
        ups.write_text(json.dumps([{'coop_name': '永野青果', 'item_name': 'レタス', 'jgap_no': '420000027', 'new_expires': '2029-12-26'}], ensure_ascii=False), encoding='utf-8')
        out2 = self.d / 'GAP認証産地　26.12.15更新.xlsx'
        run('jgap', out, ups, out2, '2026-12-15')
        _, ws2 = self.values(out2)
        self.assertEqual([r for r in range(5, 13) if ws2.cell(r, 43).fill.fill_type == 'solid'], [7])
        self.assertIsNone(ws2.cell(5, 43).comment)
        self.assertEqual(openpyxl.load_workbook(out2)['Sheet2']['A2'].value, '玉葱GAP産地')

    def test_nothing_changed_is_not_saved_and_legacy_args(self):
        ups = self.d / 'ups.json'
        ups.write_text('[{"coop_name":"永野青果","item_name":"レタス","jgap_no":"420000027","new_expires":"2026-12-26"}]', encoding='utf-8')
        out = self.d / 'out.xlsx'
        r = run(self.src, ups, out, '2026-12-01')  # 昔の形（モード名なし）
        self.assertFalse(r['saved'])
        self.assertFalse(out.exists())


if __name__ == '__main__':
    unittest.main()
