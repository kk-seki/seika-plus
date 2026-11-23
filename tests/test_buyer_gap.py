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
 window.c151InhouseOut=async d=>{window.__shipDay=window.__shipDay||d;return {'埼玉':new Map([['人参',100]]),'深谷':new Map([['キャベツ',380]])}};
 todayKey=()=>'2026-11-23';
 v1144PurchaseStaffCandidates=()=>[{legacy_user_id:'araki',display_name:'荒木'},{legacy_user_id:'saito_dai',display_name:'斎藤'}];
 buyerFullName=(id,n)=>({araki:'荒木 貴裕',saito_dai:'斎藤 大'})[id]||n;
 window.c149BuyerItemNames=id=>({araki:['人参'],saito_dai:['キャベツ','トマト','ピーマン']})[id]||[];
 /* c154：仕入れ担当者・営業担当者と、営業担当の決まり（SQL 064） */
 window.__staff=[{id:'P-ARAKI',display_name:'荒木 貴裕',role:'buyer',legacy_user_id:'araki'},{id:'P-SAITO',display_name:'斎藤 大明',role:'buyer',legacy_user_id:'saito_dai'},
   {id:'P-WARA',display_name:'蕨岡 愛姫',role:'sales',legacy_user_id:'sales_warabioka_aki'},{id:'P-IKEDA',display_name:'池田 進',role:'sales',legacy_user_id:'ikeda'}];
 window.__rules=[{id:1,keyword:'東部アシード',staff_profile_id:'P-WARA'},{id:2,keyword:'フジフーズ',staff_profile_id:'P-WARA'}];
 window.__calls=[];
 const rpc=callRpc;callRpc=async(n,a)=>{__calls.push([n,a]);
  if(n==='list_sales_customers_v1199c154'){if(window.__noSql)throw new Error('PGRST202 Could not find the function list_sales_customers_v1199c154');return {ok:true,rules:JSON.parse(JSON.stringify(__rules)),staff:JSON.parse(JSON.stringify(__staff))}}
  if(n==='save_sales_customer_v1199c154'){if(a.p_id)Object.assign(__rules.find(r=>r.id===a.p_id),{keyword:a.p_keyword,staff_profile_id:a.p_staff});else __rules.push({id:__rules.length+10,keyword:a.p_keyword,staff_profile_id:a.p_staff});return {ok:true}}
  if(n==='delete_sales_customer_v1199c154'){__rules=__rules.filter(r=>r.id!==a.p_id);return {ok:true}}
  return rpc(n,a)};
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
        # c154：前の日に先送りした出庫を足した分は、客先の内訳に「先送り」と書く
        ahead = page.evaluate("()=>{const r=c153Lib.c153Compare(__plan['2026-11-24'],__actual['2026-11-24'],{'埼玉':new Map([['人参',60]]),'深谷':new Map(),ahead:{'埼玉':new Map([['人参',40]]),'深谷':new Map()}});return r.find(x=>x.item==='人参').parts.find(p=>p.customer==='埼玉')}")
        self.assertEqual((ahead["plan"], ahead["actual"], ahead["ahead"]), (100, 60, 40))

    def test_worker_gets_text_per_buyer_with_copy_buttons(self):
        page = self.open_app("worker")
        page.evaluate("()=>c153GapPage()")
        page.locator("#c153TextAll").wait_for()
        self.assertEqual(page.evaluate("()=>__shipDay"), "2026-11-23")  # 確定の出庫は出荷日（納品日の前日）
        text = page.inner_text("#app")
        self.assertIn("11/24（火）納品", text)
        self.assertIn("荒木 貴裕さん", text)
        self.assertIn("斎藤 大さん", text)
        self.assertIn("蕨岡 愛姫さん", text)
        self.assertNotIn("池田", text)  # 担当のない営業担当者は出さない（閲覧者などのアカウントも出ない）
        self.assertIn("仕入れ担当なしの品目", text)  # 小松菜はだれの担当でもない
        araki = page.input_value("#c153Text0")
        self.assertIn("【出荷予定と確定のちがい】11/24（火）納品\n荒木 貴裕さん\n\n＜仕入れ担当の品目＞", araki)
        self.assertIn("・人参：予定 500kg → 確定 370kg（−130kg・−26%）", araki)
        self.assertIn("フジフーズ 千葉工場 200→120／東部アシード 200→150", araki)  # ちがいの大きい客先から
        self.assertNotIn("キャベツ", araki)
        saito = page.input_value("#c153Text1")
        self.assertIn("・ピーマン：予定 0kg → 確定 40kg（+40kg・予定なし）", saito)
        self.assertIn("■2割未満（2品目）", saito)
        self.assertIn("・キャベツ：700 → 670kg（−4%）", saito)
        self.assertNotIn("＜営業担当の客先＞", saito)
        wara = page.input_value("#c153Text2")
        self.assertIn("＜営業担当の客先＞", wara)
        self.assertIn("・フジフーズ 千葉工場：1品目ちがう（2割以上 1）\n　人参 200→120（−40%）", wara)
        self.assertIn("・東部アシード：4品目ちがう（2割以上 2）", wara)
        self.assertNotIn("＜仕入れ担当の品目＞", wara)
        self.assertEqual(page.locator("button", has_text="LINE WORKSで共有").count(), 5)  # 3人分＋仕入れ担当なし＋全員分
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
        viewer = self.open_app("viewer")
        viewer.evaluate("()=>{window.__alerts=[];window.alert=m=>__alerts.push(String(m))}")
        viewer.evaluate("()=>c153GapPage()")
        self.assertTrue(viewer.evaluate("()=>__alerts.length>0"))

    def test_sales_sees_own_customers(self):
        # c154：営業担当者は、自分の担当客先のちがいだけを見る
        page = self.open_app("sales")
        page.evaluate("()=>{db.userId='sales_warabioka_aki'}")
        page.evaluate("()=>c153GapPage()")
        page.locator(".c153Tbl").first.wait_for()
        text = page.inner_text("#app")
        self.assertIn("担当客先", text)
        self.assertIn("フジフーズ 千葉工場", text)
        self.assertIn("東部アシード", text)
        self.assertNotIn("仕入れ担当の品目", text)
        self.assertEqual(page.locator("textarea").count(), 0)

    def test_before_sql_064_only_buyers(self):
        page = self.open_app("worker")
        page.evaluate("()=>{window.__noSql=true}")
        page.evaluate("()=>c153GapPage()")
        page.locator("#c153TextAll").wait_for()
        text = page.inner_text("#app")
        self.assertIn("営業担当の割り振り（SQL 064）がまだ実行されていない", text)
        self.assertIn("荒木 貴裕さん", text)
        self.assertNotIn("蕨岡", text)
        self.assertEqual(page.locator("button", has_text="営業担当の客先を変える").count(), 0)

    def test_edit_sales_customers(self):
        page = self.open_app("worker")
        page.evaluate("()=>{window.confirm=()=>true}")
        page.evaluate("()=>c154SalesCustomersPage('2026-11-24')")
        page.locator("#c154NewKw").wait_for()
        text = page.inner_text("#app")
        # 東部アシード・フジフーズは決まりに当たる。ない客先は確定がないので出てこない
        self.assertIn("営業担当が決まっていない客先", text)
        self.assertIn("当たる客先：フジフーズ 千葉工場", text)
        # 新しい決まりを追加
        page.fill("#c154NewKw", "虎昭")
        page.select_option("#c154NewSt", "P-SAITO")
        page.locator("button", has_text="追加").click()
        page.get_by_text("「虎昭」を追加しました。").wait_for()
        saved = page.evaluate("()=>__calls.filter(c=>c[0]==='save_sales_customer_v1199c154').map(c=>c[1])")
        self.assertEqual(saved, [{"p_id": None, "p_keyword": "虎昭", "p_staff": "P-SAITO"}])
        # 担当者を変えて保存・削除
        page.select_option("#c154St1", "P-SAITO")
        page.locator("button", has_text="保存").first.click()
        page.get_by_text("「東部アシード」を保存しました。").wait_for()
        self.assertEqual(page.evaluate("()=>__rules.find(r=>r.id===1).staff_profile_id"), "P-SAITO")
        page.locator("button", has_text="削除").first.click()
        page.get_by_text("を削除しました。").wait_for()
        # 青果社員・管理者以外は変えられない
        buyer = self.open_app("buyer")
        buyer.evaluate("()=>{window.__alerts=[];window.alert=m=>__alerts.push(String(m))}")
        buyer.evaluate("()=>c154SalesCustomersPage()")
        self.assertTrue(buyer.evaluate("()=>__alerts.some(a=>a.includes('管理者・青果社員'))"))

    def test_staff_rule_prefers_longer_keyword(self):
        page = self.open_app("worker")
        out = page.evaluate("""()=>[c153Lib.c154StaffOf('(株)武蔵野 千葉工場',[{id:1,keyword:'武蔵野千葉',staff_profile_id:'A'}])?.staff_profile_id,
          c153Lib.c154StaffOf('プライムデリカ 龍ヶ崎工場',[{id:1,keyword:'プライム',staff_profile_id:'A'},{id:2,keyword:'プライムデリカ 龍ヶ崎',staff_profile_id:'B'}])?.staff_profile_id,
          c153Lib.c154StaffOf('ティキューシー',[{id:1,keyword:'虎昭',staff_profile_id:'A'}])]""")
        self.assertEqual(out, ["A", "B", None])

    def test_entry_on_ship_plan_and_line_copy_pages(self):
        page = self.open_app("worker")
        page.evaluate("()=>c140ShipPlanPage('2026-11-24','')")
        page.locator("#c153Entry").wait_for()
        self.assertIn("担当者別・送る用", page.inner_text("#c153Entry"))
        page.evaluate("()=>{window.makeLineCopyText=async()=>'在庫報告';lineCopyPage()}")
        page.wait_for_function("()=>currentScreen==='lineCopyPage'")
        page.locator("#c153Entry").wait_for()


if __name__ == "__main__":
    unittest.main()
