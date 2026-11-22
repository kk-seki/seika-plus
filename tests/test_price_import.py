"""c148：週間予想原料価格のExcelから仕入れ価格表（市場価格）を取り込む。
架空の「週間」シートをページの中で SheetJS で作る（実物のファイルはリポジトリに入れない）。"""
import functools
import threading
import unittest
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

from playwright.sync_api import sync_playwright

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
MOCK = (HERE / "mock_hq.js").read_text(encoding="utf-8")

# 実物と同じ形：4行目が見出し（担当者・商品名・単位・規格…）、週の列は「価格・トピック」の2列ずつ。いちばん右の週の見出しは書き直し忘れ（前の週のまま）
BOOK = """()=>{
 const H=['担当者','商品名','単位','規格','11月契約内容',null,null,null,'市場相場','11/9～11/15','トピック','11/16～11/22','トピック','11/16～11/22','原料供給MTG　内容'];
 const rows=[[null,'週間予想原料価格'],[],[],H,
  ['坂本','小葱','kg','契約',null,null,null,null,'1200/kg',1000,null,1000,null,890],
  [null,null,null,null,'㎏/630'],
  ['坂本','大葉','kg',null,null,null,null,null,'1トレー','2100/箱',null,'2100/箱',null,'2100/箱'],
  ['坂本','ズッキーニ','kg'],
  ['斎藤（大）','ニラ','kg','契約',null,null,null,null,750,750,null,750,null,750],
  [null,null,null,null,null,null,null,null,null,'社内売りは契約価格',null,'社内売りは契約価格',null,'社内売りは契約価格'],
  ['斎藤（大）','茄子','kg',null,null,null,null,null,440,'長茄子380',null,'長茄子500',null,'長茄子500'],
  [null,null,null,null,null,null,null,null,null,'短茄子500',null,'短茄子575',null,'短茄子575'],
  ['斎藤（大）','胡瓜','kg','A',null,null,null,null,520,500,null,500,null,500],
  [null,null,null,null,466],
  [null,null,null,'B',null,null,null,null,480,460,null,460,null,460],
  ['斎藤（大）','トマト','箱','4㎏',null,null,null,null,2600,2400,null,2400,null,3000],
  ['斎藤（大）','南瓜','kg','3～8玉',null,null,null,null,300,350,null,350,null,'市場/350'],
  ['斉藤（大）','大根','kg','葉付き',null,null,null,null,120,68,null,66,null,58],
  [null,null,null,null,80],
  [null,null,'kg','切り',null,null,null,null,70,65,null,62,null,52],
  ['荒木','国産人参','kg','加工用',null,null,null,null,null,85],
  ['吉田','レタス','箱','契約',null,null,null,null,1100,1250,null,1250,null,1250],
  ['吉田','サニーレタス','箱','契約',null,null,null,null,'k/275','k/320',null,'k/320',null,'ｋ/320'],
  ['吉田','白菜','kg','社内加工',null,null,null,null,'k/70','k/80',null,'k/80',null,'k/80'],
  [null,null,null,'原体出し',null,null,null,null,null,'k/90',null,'k/90',null,'k/90'],
  ['関（宏）','玉葱','kg','2L',null,null,null,null,null,null,null,null,null,120]];
 const ws=XLSX.utils.aoa_to_sheet(rows);return {SheetNames:['週間','推移2'],Sheets:{'週間':ws,'推移2':XLSX.utils.aoa_to_sheet([['x']])}};
}"""


class PriceImportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        handler = type("Quiet", (SimpleHTTPRequestHandler,), {"log_message": lambda *args: None})
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(handler, directory=str(ROOT)))
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()
        cls.url = f"http://127.0.0.1:{cls.server.server_port}/index.html"
        cls.local = urlparse(cls.url).netloc
        cls.playwright = sync_playwright().start()
        cls.browser = cls.playwright.chromium.launch()

    @classmethod
    def tearDownClass(cls):
        cls.browser.close()
        cls.playwright.stop()
        cls.server.shutdown()
        cls.server.server_close()

    def open_app(self, role="clerk"):
        context = self.browser.new_context(viewport={"width": 820, "height": 1180}, service_workers="block", timezone_id="Asia/Tokyo")
        self.addCleanup(context.close)
        context.route("**/*", lambda route: route.continue_() if urlparse(route.request.url).netloc == self.local else route.abort())
        page = context.new_page()
        errors = []
        page.on("pageerror", lambda error: errors.append(str(error)))
        self.addCleanup(lambda: self.assertEqual(errors, []))
        page.goto(self.url, wait_until="load")
        page.wait_for_function("()=>typeof c148Lib==='object'&&typeof XLSX!=='undefined'")
        page.wait_for_timeout(500)
        page.evaluate(MOCK, role)
        page.evaluate("""()=>{window.confirm=()=>true;window.__rpc=[];
          window.__prices=[{week_start:'2026-11-16',item_name:'小葱',origin:'',supplier:'市場',price_yen_per_kg:1000,price_type:'market'},
                           {week_start:'2026-11-23',item_name:'キャベツ',origin:'',supplier:'市場',price_yen_per_kg:70,price_type:'market'}];
          callRpc=async(n,a)=>{window.__rpc.push([n,JSON.parse(JSON.stringify(a||{}))]);if(n==='get_purchase_prices')return JSON.parse(JSON.stringify(__prices));if(n==='upsert_purchase_price_v1117'){if(window.__failItem===a.p_item_name)return {ok:false,message:'だめ'};return {ok:true}}return []}}""")
        return page

    def parse(self, page, name="週間予想原料価格（26.11.23）.xlsx"):
        return page.evaluate(f"(name)=>c148Lib.c148Parse(({BOOK})(),name)", name)

    def test_reads_the_rightmost_week_like_the_hand_entered_prices(self):
        page = self.open_app()
        p = self.parse(page)
        self.assertEqual(p["week"], "2026-11-23")  # ファイル名の日付（見出しは 11/16～11/22 のまま）
        self.assertEqual(p["header"], "11/16～11/22")
        got = {r["item"]: r["price"] for r in p["rows"]}
        self.assertEqual(got, {
            "小葱": 890, "長茄子": 500, "茄子": 575, "胡瓜": 460, "トマト": 750, "南瓜": 350,
            "葉付き大根": 58, "カット大根": 52, "レタス": 156, "サニー": 320, "白菜": 80,
        })
        why = {(s["name"], s.get("item", "")): s["why"] for s in p["skipped"]}
        self.assertIn("値が空", why[("ズッキーニ", "ズッキーニ")])
        self.assertIn("値が空", why[("国産人参", "人参")])  # 空は前の週を引き継がない
        self.assertIn("注記", why[("ニラ", "ニラ")])
        self.assertIn("決まりにない", why[("大葉", "")])
        self.assertIn("決まりにない", why[("玉葱", "")])

    def test_week_from_file_name_and_number_formats(self):
        page = self.open_app()
        out = page.evaluate("""()=>[c148Lib.c148WeekFromName('週間予想原料価格（26.11.23）.xlsx'),c148Lib.c148WeekFromName('価格 2026-11-26.xlsx'),c148Lib.c148WeekFromName('価格.xlsx'),
          c148Lib.c148Num('k/300'),c148Lib.c148Num('ｋ/365'),c148Lib.c148Num('市場/350'),c148Lib.c148Num(' 240 '),c148Lib.c148Num('2100/箱'),c148Lib.c148Num('青果用/750'),c148Lib.c148Num('')]""")
        self.assertEqual(out, ["2026-11-23", "2026-11-23", "", 300, 365, 350, 240, None, None, None])

    def test_preview_and_save_as_market_prices(self):
        page = self.open_app()
        page.evaluate("()=>purchasePricesPage('2026-11-23')")
        page.locator("#c148Entry").wait_for()
        page.evaluate(f"""async()=>{{const wb=({BOOK})();const buf=XLSX.write(wb,{{type:'array',bookType:'xlsx'}});
          const f=new File([buf],'週間予想原料価格（26.11.23）.xlsx');await c148ReadFile({{files:[f]}})}}""")
        page.locator("#c148SaveBtn").wait_for()
        text = page.inner_text("#app")
        self.assertIn("2026/11/23 の週", text)
        self.assertIn("ファイル名の日付から", text)  # 見出しの週とずれている注意
        self.assertIn("-110", text)  # 小葱 1000 → 890
        self.assertIn("取り込まないもの", text)
        page.locator("#c148SaveBtn").click()
        page.wait_for_function("()=>currentScreen==='purchasePrices'")
        saved = page.evaluate("()=>__rpc.filter(x=>x[0]==='upsert_purchase_price_v1117').map(x=>x[1])")
        self.assertEqual(len(saved), 11)
        self.assertTrue(all(s["p_week_start"] == "2026-11-23" and s["p_supplier"] == "市場" and s["p_price_type"] == "market" and s["p_origin"] == "" for s in saved))
        self.assertIn({"p_week_start": "2026-11-23", "p_item_name": "トマト", "p_origin": "", "p_supplier": "市場", "p_price_yen_per_kg": 750, "p_price_type": "market"}, saved)
        self.assertIn("11品目の市場価格を登録しました", page.inner_text("#app"))

    def test_failure_keeps_the_preview(self):
        page = self.open_app()
        page.evaluate("()=>{window.__failItem='トマト';window.__alerts=[];window.alert=m=>__alerts.push(String(m))}")
        page.evaluate(f"""async()=>{{const wb=({BOOK})();const buf=XLSX.write(wb,{{type:'array',bookType:'xlsx'}});
          await c148ReadFile({{files:[new File([buf],'週間予想原料価格（26.11.23）.xlsx')]}})}}""")
        page.locator("#c148SaveBtn").click()
        page.wait_for_function("()=>__alerts.length>0")
        self.assertIn("トマト：だめ", page.evaluate("()=>__alerts[0]"))
        self.assertEqual(page.evaluate("()=>currentScreen"), "c148PreviewPage")
        self.assertFalse(page.locator("#c148SaveBtn").is_disabled())

    def test_change_week_and_viewer_cannot_import(self):
        page = self.open_app()
        page.evaluate(f"""async()=>{{const wb=({BOOK})();const buf=XLSX.write(wb,{{type:'array',bookType:'xlsx'}});
          await c148ReadFile({{files:[new File([buf],'価格.xlsx')]}})}}""")
        page.locator("#c148SaveBtn").wait_for()
        page.evaluate("()=>c148SetWeek('2026-11-26')")
        self.assertIn("2026/11/23 の週", page.inner_text("#app"))
        viewer = self.open_app("viewer")
        viewer.evaluate("()=>{window.__alerts=[];window.alert=m=>__alerts.push(String(m))}")
        viewer.evaluate("()=>purchasePricesPage('2026-11-23')")
        viewer.wait_for_timeout(300)
        self.assertEqual(viewer.locator("#c148Entry").count(), 0)


if __name__ == "__main__":
    unittest.main()
