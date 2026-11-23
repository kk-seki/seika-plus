"""c153：出荷予定と確定のちがい（仕入れ担当者別）。アプリ全体を開き、データだけ架空のものに差し替えて確かめる。"""
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

# 11/24 納品：社外2客先＋埼玉・深谷。11/23 出荷の出庫で埼玉・深谷の確定
DATA = """()=>{
 const P=(c,i,kg)=>({customer:c,item:i,kg}),A=(c,i,kg)=>({customer:c,item:i,kg});
 window.__plan={'2026-11-24':[P('東部アシード','人参',200),P('フジフーズ(株) 千葉工場(ニチノウ)','人参',200),P('(株)せき 埼玉工場','人参',100),
   P('東部アシード','キャベツ',300),P('(株)せき 深谷青果センター','キャベツ',400),P('東部アシード','小松菜',50),P('ない客先','小松菜',500),
   P('東部アシード','大葉',3),P('東部アシード','トマト',100)]};
 window.__actual={'2026-11-24':[A('東部アシード','人参',150),A('フジフーズ(株) 千葉工場(ニチノウ)','人参',120),A('東部アシード','キャベツ',290),
   A('東部アシード','小松菜',52),A('東部アシード','大葉',5),A('東部アシード','トマト',100),A('東部アシード','ピーマン',40)]};
 const add=(k,n)=>{const d=new Date(k+'T00:00:00Z');d.setUTCDate(d.getUTCDate()+n);return d.toISOString().slice(0,10)};
 window.c140Lib={...window.c140Lib,addDays:add,canView:()=>true,sqlMissing:()=>false,
  loadPlan:async d=>{const ls=__plan[d];return {active:ls?{id:d}:null,lines:ls||[]}},
  loadActual:async d=>{const ls=__actual[d];return {active:ls?{id:d}:null,lines:ls||[]}}};
 window.c151InhouseOut=async d=>{window.__shipDay=d;return {'埼玉':new Map([['人参',100]]),'深谷':new Map([['キャベツ',380]])}};
 todayKey=()=>'2026-11-23';
 v1144PurchaseStaffCandidates=()=>[{legacy_user_id:'araki',display_name:'荒木'},{legacy_user_id:'saito_dai',display_name:'斎藤'}];
 buyerFullName=(id,n)=>({araki:'荒木 貴裕',saito_dai:'斎藤 大'})[id]||n;
 window.c149BuyerItemNames=id=>({araki:['人参'],saito_dai:['キャベツ','トマト','ピーマン']})[id]||[];
}"""


class BuyerGapTests(unittest.TestCase):
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

    def open_app(self, role):
        context = self.browser.new_context(viewport={"width": 820, "height": 1180}, service_workers="block", timezone_id="Asia/Tokyo")
        self.addCleanup(context.close)
        context.route("**/*", lambda route: route.continue_() if urlparse(route.request.url).netloc == self.local else route.abort())
        page = context.new_page()
        errors = []
        page.on("pageerror", lambda error: errors.append(str(error)))
        self.addCleanup(lambda: self.assertEqual(errors, []))
        page.goto(self.url, wait_until="load")
        page.wait_for_function("()=>typeof c153GapPage==='function'&&typeof c140Lib==='object'")
        page.wait_for_timeout(500)
        page.evaluate(MOCK, role)
        page.evaluate("()=>{db.userId=db.role==='buyer'?'araki':db.userId;db.user='荒木'}")
        page.evaluate(DATA)
        return page

    def test_compare_by_item_and_customer(self):
        page = self.open_app("worker")
        rows = page.evaluate("()=>c153Lib.c153Compare(__plan['2026-11-24'],__actual['2026-11-24'],{'埼玉':new Map([['人参',100]]),'深谷':new Map([['キャベツ',380]])})")
        by = {r["item"]: r for r in rows}
        # 人参：予定 200+200+埼玉100＝500 → 確定 150+120+埼玉100＝370（−26%）
        self.assertEqual((by["人参"]["plan"], by["人参"]["actual"], by["人参"]["big"]), (500, 370, True))
        # キャベツ：予定 300＋深谷400＝700 → 290＋380＝670（−4%）
        self.assertEqual((by["キャベツ"]["plan"], by["キャベツ"]["actual"], by["キャベツ"]["big"]), (700, 670, False))
        # 小松菜：確定のない客先（ない客先）の予定は比べない → 50→52
        self.assertEqual((by["小松菜"]["plan"], by["小松菜"]["actual"]), (50, 52))
        self.assertNotIn("大葉", by)  # 予定・確定とも10kg以下
        self.assertTrue(by["ピーマン"]["big"])  # 予定なし→確定あり
        self.assertIsNone(by["ピーマン"]["rate"])
        self.assertEqual(rows[0]["item"] in ("人参", "ピーマン"), True)  # 2割以上が先
        self.assertEqual(page.evaluate("()=>[c153Lib.shortCust('フジフーズ(株) 千葉工場(ニチノウ)'),c153Lib.shortCust('(株)せき 埼玉工場')]"), ["フジフーズ 千葉工場", "埼玉"])

    def test_worker_gets_text_per_buyer_with_copy_buttons(self):
        page = self.open_app("worker")
        page.evaluate("()=>c153GapPage()")
        page.locator("#c153TextAll").wait_for()
        self.assertEqual(page.evaluate("()=>__shipDay"), "2026-11-23")  # 確定の出庫は出荷日（納品日の前日）
        text = page.inner_text("#app")
        self.assertIn("11/24（火）納品", text)
        self.assertIn("荒木 貴裕さん", text)
        self.assertIn("斎藤 大さん", text)
        self.assertIn("担当なしの品目", text)  # 小松菜はだれの担当でもない
        araki = page.input_value("#c153Text0")
        self.assertIn("【出荷予定と確定のちがい】11/24（火）納品\n荒木 貴裕さん（担当品目）", araki)
        self.assertIn("・人参：予定 500kg → 確定 370kg（−130kg・−26%）", araki)
        self.assertIn("フジフーズ 千葉工場 200→120／東部アシード 200→150", araki)  # ちがいの大きい客先から
        self.assertNotIn("キャベツ", araki)
        saito = page.input_value("#c153Text1")
        self.assertIn("・ピーマン：予定 0kg → 確定 40kg（+40kg・予定なし）", saito)
        self.assertIn("■2割未満（2品目）", saito)
        self.assertIn("・キャベツ：700 → 670kg（−4%）", saito)
        self.assertEqual(page.locator("button", has_text="LINE WORKSで共有").count(), 4)  # 3人分＋全員分
        page.evaluate("()=>{window.__copied='';navigator.clipboard.writeText=async t=>{__copied=t}}")
        page.locator("button", has_text="コピー").first.click()
        page.wait_for_function("()=>__copied.length>0")
        self.assertIn("荒木 貴裕さん", page.evaluate("()=>__copied"))

    def test_buyer_sees_only_own_items_without_copy(self):
        page = self.open_app("buyer")
        page.evaluate("()=>c153GapPage()")
        page.locator(".c153Tbl").wait_for()
        text = page.inner_text("#app")
        self.assertIn("人参", text)
        self.assertNotIn("キャベツ", text)
        self.assertIn("東部アシード 200→150", text)
        self.assertEqual(page.locator("textarea").count(), 0)

    def test_no_actual_yet_and_other_roles(self):
        page = self.open_app("worker")
        page.evaluate("()=>c153GapPage('2026-11-25')")
        page.get_by_text("この日の確定（産地報告書）はまだ取り込まれていません").wait_for()
        sales = self.open_app("sales")
        sales.evaluate("()=>{window.__alerts=[];window.alert=m=>__alerts.push(String(m))}")
        sales.evaluate("()=>c153GapPage()")
        self.assertTrue(sales.evaluate("()=>__alerts.length>0"))

    def test_entry_on_ship_plan_and_line_copy_pages(self):
        page = self.open_app("worker")
        page.evaluate("()=>c140ShipPlanPage('2026-11-24','')")
        page.locator("#c153Entry").wait_for()
        self.assertIn("仕入れ担当者別・送る用", page.inner_text("#c153Entry"))
        page.evaluate("()=>{window.makeLineCopyText=async()=>'在庫報告';lineCopyPage()}")
        page.wait_for_function("()=>currentScreen==='lineCopyPage'")
        page.locator("#c153Entry").wait_for()


if __name__ == "__main__":
    unittest.main()
