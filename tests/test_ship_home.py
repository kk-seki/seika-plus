"""c147：仕入れ担当者・営業担当者のホームの「出荷予定と確定」を、架空のデータで確かめる。
ホームの画面はページの中で小さく作り、js/31-c147-ship-home.js だけを読み込む（本番やクラウドには接続しない）。"""
import functools
import threading
import unittest
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parent.parent

SETUP = """role=>{
 window.db={role,userId:'U1'};window.currentScreen='home';
 window.esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 window.seikaEventAttrs=(e,a,args=[])=>`data-seika-${e}-action="${esc(a)}" data-seika-${e}-args="${esc(encodeURIComponent(JSON.stringify(args)))}"`;
 window.todayKey=()=>'2026-11-23';
 const add=(k,n)=>{const d=new Date(k+'T00:00:00Z');d.setUTCDate(d.getUTCDate()+n);return d.toISOString().slice(0,10)};
 const L=(customer,item,kg)=>({customer,item,kg});
 window.__plan={
  '2026-11-24':[L('A社','キャベツ',300),L('B社','キャベツ',100),L('A社','人参',90),L('A社','小松菜',40),L('埼玉','レタス',500)],
  '2026-11-23':[L('A社','キャベツ',200),L('A社','人参',100),L('A社','大葉',5),L('埼玉','レタス',400),L('A社','ほうれん草',100)],
 };
 window.__actual={'2026-11-23':[L('A社','キャベツ',260),L('A社','人参',105),L('A社','大葉',9),L('A社','トマト',40)]};
 window.c140Lib={addDays:add,canView:()=>true,sqlMissing:()=>false,
  loadPlan:async d=>{const ls=__plan[d];return {active:ls?{id:d}:null,lines:ls||[]}},
  loadActual:async d=>{const ls=__actual[d];return {active:ls?{id:d}:null,lines:ls||[]}}};
 window.v1153BuyerOptimalItems=()=>[{name:'キャベツ'},{name:'人参'},{name:'ほうれん草'},{name:'ごぼう'}];
 window.c134Load=async()=>({by:{'キャベツ':{kg:1200,days:new Set(['a','b','c','d'])},'人参':{kg:300,days:new Set(['a','b'])}}});
 document.getElementById('app').innerHTML='<main class="wrap"><div class="homeSummary">まとめ</div><div class="homePrimary"></div><div id="c134Daily"><div id="c134DailyBtns"><button class="c134Btn"><b>キャベツ</b><em>日量 300kg</em></button><button class="c134Btn"><b>ごぼう</b><em>出庫なし</em></button></div></div></main>';
}"""


class ShipHomeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        handler = type("Quiet", (SimpleHTTPRequestHandler,), {"log_message": lambda *args: None})
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(handler, directory=str(ROOT)))
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()
        cls.base = f"http://127.0.0.1:{cls.server.server_port}"
        cls.local = urlparse(cls.base).netloc
        cls.playwright = sync_playwright().start()
        cls.browser = cls.playwright.chromium.launch()

    @classmethod
    def tearDownClass(cls):
        cls.browser.close()
        cls.playwright.stop()
        cls.server.shutdown()
        cls.server.server_close()

    def open_home(self, role):
        context = self.browser.new_context(viewport={"width": 820, "height": 1180}, service_workers="block", timezone_id="Asia/Tokyo")
        self.addCleanup(context.close)
        context.route("**/*", lambda route: route.continue_() if urlparse(route.request.url).netloc == self.local else route.abort())
        page = context.new_page()
        errors = []
        page.on("pageerror", lambda err: errors.append(str(err)))
        self.addCleanup(lambda: self.assertEqual(errors, [], "browser errors"))
        page.set_content('<!doctype html><html><body><div id="app"></div></body></html>')
        page.evaluate(SETUP, role)
        page.add_script_tag(url=self.base + "/js/31-c147-ship-home.js")
        page.evaluate("()=>c147InjectHome()")
        return page

    def test_buyer_sees_my_items_with_daily_amount_and_big_differences(self):
        page = self.open_home("buyer")
        card = page.locator("#c147Ship")
        card.locator(".c147Sub").first.wait_for()
        text = card.inner_text()
        self.assertIn("（担当品目）", text)
        self.assertIn("明日（11/24納品）の出荷予定", text)
        # 担当品目だけ。キャベツ 400kg ÷ 日量300kg＝1.3倍（多い）、人参 90kg ÷ 日量150kg＝0.6倍（少ない）
        self.assertIn("日量の1.3倍・多い", text)
        self.assertIn("日量の0.6倍・少ない", text)
        self.assertNotIn("小松菜", text)
        self.assertNotIn("レタス", text)
        self.assertIn("予定なし：ごぼう、ほうれん草", text)
        # 確定：キャベツ 200→260（+30%）は出す。人参 100→105（+5%）は2割未満なので出さない
        self.assertIn("11/23納品の確定と予定の違い（2割以上）", text)
        self.assertIn("+30%", text)
        self.assertNotIn("105kg", text)
        # ほうれん草は確定のある客先（A社）の予定にあり、確定にない → -100%
        self.assertIn("-100%", text)
        # 日量のボタンに明日の予定を書き足す
        page.locator("#c134DailyBtns .c147Add").first.wait_for()
        btns = page.locator("#c134DailyBtns").inner_text()
        self.assertIn("明日 400kg（1.3倍）", btns)
        self.assertIn("明日 予定なし", btns)
        # カードはホームの一番上（まとめの前）
        self.assertEqual(page.evaluate("()=>document.querySelector('main').firstElementChild.id"), "c147Ship")

    def test_sales_sees_all_items_and_differences(self):
        page = self.open_home("sales")
        card = page.locator("#c147Ship")
        card.locator(".c147Sub").first.wait_for()
        text = card.inner_text()
        self.assertNotIn("（担当品目）", text)
        self.assertNotIn("日量", text)
        for item in ("レタス", "キャベツ", "人参", "小松菜"):
            self.assertIn(item, text)
        # 埼玉は確定がない客先なので比べない（レタスは違いに出さない）。大葉は両方10kg以下なので出さない
        diff = card.locator(".c147Sec").nth(1).inner_text()
        self.assertNotIn("レタス", diff)
        self.assertNotIn("大葉", diff)
        self.assertIn("予定なし→確定あり", diff)  # トマト
        self.assertIn("キャベツ", diff)

    def test_other_roles_do_not_get_the_card(self):
        page = self.open_home("worker")
        page.wait_for_timeout(200)
        self.assertEqual(page.locator("#c147Ship").count(), 0)

    def test_no_actual_yet_and_no_plan(self):
        context = self.browser.new_context(service_workers="block")
        self.addCleanup(context.close)
        context.route("**/*", lambda route: route.continue_() if urlparse(route.request.url).netloc == self.local else route.abort())
        page = context.new_page()
        page.set_content('<!doctype html><html><body><div id="app"></div></body></html>')
        page.evaluate(SETUP, "sales")
        page.evaluate("()=>{__plan={};__actual={}}")
        page.add_script_tag(url=self.base + "/js/31-c147-ship-home.js")
        page.evaluate("()=>c147InjectHome()")
        page.locator("#c147Ship .c147Sub").first.wait_for()
        text = page.locator("#c147Ship").inner_text()
        self.assertIn("積み込み表はまだ取り込まれていません", text)
        self.assertIn("確定（産地報告書）はまだ取り込まれていません", text)

if __name__ == "__main__":
    unittest.main()
