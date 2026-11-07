import functools
import io
import os
import re
import threading
import unittest
import zipfile
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse
from xml.etree import ElementTree

from playwright.sync_api import sync_playwright

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
MOCK = (HERE / "mock_hq.js").read_text(encoding="utf-8")

NS = {
    "m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main",
    "r": "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
    "p": "http://schemas.openxmlformats.org/package/2006/relationships",
}

FIXED_CLOCK = """(()=>{const Real=Date,fixed=Date.parse('2026-11-06T03:00:00Z');
class Fixed extends Real{constructor(...a){super(...(a.length?a:[fixed]))}static now(){return fixed}}
window.Date=Fixed})()"""

SETUP = """()=>{
 window.__alerts=[];
 window.alert=message=>window.__alerts.push(String(message));
 window.confirm=()=>true;
 __T.hq_lot_movements_v1400=[{id:'MV1',movement_type:'入荷確定',item_name:'キャベツ',lot_no:'H261025-01',qty:8,unit:'case',before_qty:0,after_qty:8,user_name:'仮の担当者',occurred_at:'2026-11-01T03:00:00Z'}];
 const base=callRpc;
 callRpc=async(name,args)=>{
  if(name==='get_monthly_quality_export_v1102')return{evaluations:[{id:'Q1',qr_key:'K1',lot_no:'H261025-01',item_name:'キャベツ',supplier:'みどり農園（架空）',received_date:'2026-10-25',grade:'good',issues:['傷み','変色'],memo:'仮の評価',evaluated_at:'2026-10-25T03:00:00Z',evaluated_by_name:'仮の担当者',photos:[]}]};
  if(name==='list_monthly_quality_archives_v1166'||name==='list_monthly_archives_v1101')return{archives:[]};
  return base(name,args);
 };
}"""

INVENTORY_ROWS = """[{createdAt:'2026-11-01T03:00:00Z',itemName:'キャベツ',itemId:'fixture',total:80,setting:{min:50,max:100},status:'normal',lines:[{pack:10,cases:8}],user:'仮の担当者',kind:'一括入力'}]"""


def column_index(ref):
    letters = re.match(r"[A-Z]+", ref).group(0)
    index = 0
    for char in letters:
        index = index * 26 + ord(char) - 64
    return index - 1


def cell_value(cell, shared):
    kind = cell.get("t")
    if kind == "inlineStr":
        return "".join(t.text or "" for t in cell.iterfind(".//m:t", NS))
    node = cell.find("m:v", NS)
    if node is None or node.text is None:
        return ""
    if kind == "s":
        return shared[int(node.text)]
    if kind in ("str", "e"):
        return node.text
    if kind == "b":
        return node.text == "1"
    number = float(node.text)
    return int(number) if number.is_integer() else number


def read_xlsx(data):
    sheets = {}
    with zipfile.ZipFile(io.BytesIO(data)) as book:
        if book.testzip() is not None:
            raise AssertionError("xlsxのZIPが壊れています")
        shared = []
        if "xl/sharedStrings.xml" in book.namelist():
            root = ElementTree.fromstring(book.read("xl/sharedStrings.xml"))
            shared = ["".join(t.text or "" for t in si.iterfind(".//m:t", NS)) for si in root.iterfind("m:si", NS)]
        targets = {
            rel.get("Id"): rel.get("Target")
            for rel in ElementTree.fromstring(book.read("xl/_rels/workbook.xml.rels")).iterfind("p:Relationship", NS)
        }
        workbook = ElementTree.fromstring(book.read("xl/workbook.xml"))
        for sheet in workbook.iterfind("m:sheets/m:sheet", NS):
            target = targets[sheet.get(f"{{{NS['r']}}}id")].lstrip("/")
            path = target if target.startswith("xl/") else f"xl/{target}"
            rows = []
            for row in ElementTree.fromstring(book.read(path)).iterfind(".//m:sheetData/m:row", NS):
                values = []
                for cell in row.iterfind("m:c", NS):
                    index = column_index(cell.get("r"))
                    values.extend([""] * (index - len(values)))
                    values.append(cell_value(cell, shared))
                rows.append(values)
            sheets[sheet.get("name")] = rows
    return sheets


def start_server():
    handler = type("Quiet", (SimpleHTTPRequestHandler,), {"log_message": lambda *args: None})
    server = ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(handler, directory=str(ROOT)))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


class ExcelOutputTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = None
        cls.url = os.environ.get("SEIKA_URL", "")
        if not cls.url:
            cls.server = start_server()
            cls.url = f"http://127.0.0.1:{cls.server.server_port}/index.html"
        if urlparse(cls.url).hostname not in {"127.0.0.1", "localhost"}:
            raise ValueError("検証URLはローカルサーバーだけを指定してください")
        cls.local = urlparse(cls.url).netloc
        cls.playwright = sync_playwright().start()
        cls.browser = cls.playwright.chromium.launch()

    @classmethod
    def tearDownClass(cls):
        cls.browser.close()
        cls.playwright.stop()
        if cls.server:
            cls.server.shutdown()
            cls.server.server_close()

    def open_app(self):
        context = self.browser.new_context(
            viewport={"width": 820, "height": 1180},
            service_workers="block",
            accept_downloads=True,
            timezone_id="Asia/Tokyo",
            locale="ja-JP",
        )
        self.addCleanup(context.close)
        context.add_init_script(FIXED_CLOCK)
        context.route(
            "**/*",
            lambda route: route.continue_() if urlparse(route.request.url).netloc == self.local else route.abort(),
        )
        page = context.new_page()
        errors = []
        page.on("pageerror", lambda error: errors.append(str(error)))
        self.addCleanup(lambda: self.assertEqual(errors, []))
        page.goto(self.url, wait_until="load")
        page.wait_for_function("()=>typeof ymdKey==='function'&&typeof XLSX!=='undefined'&&typeof ExcelJS!=='undefined'")
        page.wait_for_timeout(800)
        page.evaluate(MOCK, "admin")
        page.evaluate(SETUP)
        return page

    def export(self, expression):
        page = self.open_app()
        with page.expect_download(timeout=30000) as event:
            page.evaluate(expression)
        download = event.value
        self.assertIsNone(download.failure())
        self.assertEqual(page.evaluate("()=>window.__alerts"), [])
        return download.suggested_filename, read_xlsx(Path(download.path()).read_bytes())

    def test_hq_stock_and_history_excel(self):
        name, sheets = self.export("()=>window.hqExcel('2026-11')")
        self.assertEqual(name, "本社在庫・入出庫_2026-11.xlsx")
        self.assertEqual(list(sheets), ["本社在庫（現在）", "入出庫履歴 2026-11", "通常在庫 2026-11", "在庫表 2026-11"])
        stock = sheets["本社在庫（現在）"]
        self.assertEqual(stock[0][:6], ["品名", "本社ロットNo.", "元ロットNo.", "入荷区分", "数量", "単位"])
        cabbage = next(row for row in stock[1:] if row[1] == "H261025-01")
        self.assertEqual([cabbage[0], cabbage[3], cabbage[4], cabbage[5], cabbage[6]], ["キャベツ", "石岡から", 8, "case", "10kg"])
        onion = next(row for row in stock[1:] if row[1] == "H261025-02")
        self.assertEqual([onion[0], onion[4], onion[6]], ["玉ねぎ", 6, "20kg"])
        self.assertEqual(len(stock), 3)
        history = sheets["入出庫履歴 2026-11"]
        self.assertEqual(history[0][:5], ["日時", "区分", "品名", "本社ロットNo.", "数量"])
        self.assertEqual(history[1][1:8], ["入荷確定", "キャベツ", "H261025-01", 8, "case", 0, 8])
        self.assertTrue(history[1][0].startswith("2026/11/1"))
        self.assertEqual(history[1][-1], "仮の担当者")

    def test_hq_report_stock_excel(self):
        name, sheets = self.export("()=>window.h2ExcelOut('stock','2026-11')")
        self.assertEqual(name, "本社_在庫_2026年11月.xlsx")
        self.assertEqual(list(sheets), ["本社在庫（現在）", "入出庫"])
        stock = sheets["本社在庫（現在）"]
        self.assertEqual(stock[0][:6], ["品名", "本社ロットNo.", "元ロットNo.", "入荷区分", "数量", "単位"])
        self.assertEqual(sorted(row[1] for row in stock[1:]), ["H261025-01", "H261025-02"])
        self.assertEqual(next(row[4] for row in stock[1:] if row[1] == "H261025-01"), 8)
        moves = sheets["入出庫"]
        self.assertEqual(moves[0][:5], ["日時", "区分", "品名", "本社ロットNo.", "数量"])
        self.assertEqual(moves[1][1:8], ["入荷確定", "キャベツ", "H261025-01", 8, "case", 0, 8])

    def test_ishioka_inventory_history_excel(self):
        name, sheets = self.export(f"()=>downloadInventoryHistoryXlsx('2026-11',{INVENTORY_ROWS},'在庫表履歴_2026-11.xlsx')")
        self.assertEqual(name, "在庫表履歴_2026-11.xlsx")
        self.assertEqual(
            list(sheets),
            ["第1週_11月01日-11月01日", "第2週_11月02日-11月08日", "第3週_11月09日-11月15日",
             "第4週_11月16日-11月22日", "第5週_11月23日-11月29日", "第6週_11月30日-11月30日"],
        )
        first = sheets["第1週_11月01日-11月01日"]
        self.assertEqual(first[0], ["日付", "品名", "現在庫kg", "適正在庫kg", "差分kg", "状態", "産地/規格・明細", "入力者", "最終更新", "区分"])
        self.assertEqual(first[1][:8], ["2026-11-01", "キャベツ", 80, "50〜100", 0, "適正", "10kg×8ケース", "仮の担当者"])
        self.assertEqual(first[1][9], "一括入力")
        self.assertEqual(len(sheets["第2週_11月02日-11月08日"]), 1)

    def test_ishioka_quality_excel(self):
        name, sheets = self.export("()=>v1102DownloadQualityExcel('2026-10')")
        self.assertEqual(name, "QR品質評価履歴_2026-10.xlsx")
        self.assertEqual(list(sheets), ["品質評価履歴", "出力情報"])
        quality = sheets["品質評価履歴"]
        self.assertEqual(quality[0][:12], ["評価日時", "品名", "仕入先", "入荷日", "ロット番号", "QRキー", "判定", "状態", "メモ", "評価者", "訂正理由", "訂正前"])
        self.assertEqual(quality[1][1:10], ["キャベツ", "みどり農園（架空）", "2026-10-25", "H261025-01", "K1", "良好", "傷み、変色", "仮の評価", "仮の担当者"])
        self.assertEqual(len(quality), 2)
        info = dict(row[:2] for row in sheets["出力情報"])
        self.assertEqual([info["対象月"], info["評価件数"], info["写真枚数"]], ["2026-10", 1, 0])


if __name__ == "__main__":
    unittest.main()
