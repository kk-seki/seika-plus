"""c168：アカウント別の利用状況。見られる人だけメニューにボタンが出て、画面に最後に使った日・画面・操作の件数が出る。"""
import functools, threading, unittest
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
MOCK = (ROOT / 'tests' / 'mock_hq.js').read_text(encoding='utf-8')
USAGE_MOCK = """(can)=>{
  window.__calls=[];
  const now=new Date().toISOString(),y=new Date(Date.now()-864e5).toISOString();
  const rpc=callRpc;callRpc=async(n,a)=>{
   if(n==='can_view_usage_v1199c168'){__calls.push([n,a]);return can}
   if(n==='usage_by_account_v1199c168'){__calls.push([n,a]);if(!can)throw new Error('この画面は見られません');
    return {days:a.p_days,from:'2026-11-20',to:'2026-11-26',rows:[
     {name:'フレンキ',role:'worker',last_seen:now,days:5,screens:6,top_screens:[{screen:'qrHome',days:5},{screen:'qrCreatePage',days:4},{screen:'mystery',days:1}],ops:{'入荷':12,'出庫':30,'スキャン':40},ops_total:82},
     {name:'本社 太郎',role:'hq_worker',last_seen:y,days:2,screens:2,top_screens:[{screen:'hqHome',days:2}],ops:{'本社の操作':8},ops_total:8},
     {name:'見るだけ 花子',role:'sales',last_seen:y,days:1,screens:1,top_screens:[{screen:'home',days:1}],ops:{},ops_total:0},
     {name:'使ってない 次郎',role:'buyer',last_seen:null,days:0,screens:0,top_screens:[],ops:{},ops_total:0}]}}
   return rpc(n,a)};
}"""


class UsageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        h = type("Q", (SimpleHTTPRequestHandler,), {"log_message": lambda *a: None})
        cls.srv = ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(h, directory=str(ROOT)))
        threading.Thread(target=cls.srv.serve_forever, daemon=True).start()
        cls.url = f"http://127.0.0.1:{cls.srv.server_port}/index.html"
        cls.pw = sync_playwright().start(); cls.browser = cls.pw.chromium.launch()

    @classmethod
    def tearDownClass(cls):
        cls.browser.close(); cls.pw.stop(); cls.srv.shutdown()

    def open_app(self, role="admin", can=True):
        ctx = self.browser.new_context(service_workers="block", timezone_id="Asia/Tokyo")
        local = urlparse(self.url).netloc
        ctx.route("**/*", lambda r: r.continue_() if urlparse(r.request.url).netloc == local else r.abort())
        page = ctx.new_page(); errs = []
        page.on("pageerror", lambda e: errs.append(str(e)))
        page.goto(self.url, wait_until="load")
        page.wait_for_function("()=>typeof c168UsagePage==='function'")
        page.wait_for_timeout(500)
        page.evaluate(MOCK, role); page.evaluate(USAGE_MOCK, can)
        self.addCleanup(ctx.close)
        self.addCleanup(lambda: self.assertEqual(errs, []))
        return page

    def test_viewer_sees_menu_and_page(self):
        page = self.open_app("admin", True)
        page.evaluate("()=>accountMenu()")
        page.locator("#c168MenuUsage").wait_for()
        page.locator("#c168MenuUsage").click()
        page.get_by_text("フレンキ").wait_for()
        text = page.inner_text("#app")
        self.assertIn("今日", text)
        self.assertIn("QR作成（入荷）", text)  # 画面名は日本語に
        self.assertIn("mystery", text)  # 知らない画面はそのまま
        self.assertIn("入荷 12", text)
        self.assertIn("操作なし（見るだけ）", text)
        self.assertIn("期間中は使っていません", text)
        self.assertIn("使っていない：使ってない 次郎", text)
        self.assertEqual(page.evaluate("()=>__calls.filter(c=>c[0]==='usage_by_account_v1199c168').map(c=>c[1].p_days)"), [7])
        # 30日・本社だけ
        page.locator("button", has_text="30日").click()
        page.wait_for_function("()=>__calls.filter(c=>c[0]==='usage_by_account_v1199c168').length===2")
        page.locator("button", has_text="本社").first.click()
        page.get_by_text("本社 太郎").wait_for()
        page.wait_for_timeout(200)
        self.assertNotIn("フレンキ", page.inner_text("#app"))
        self.assertEqual(page.evaluate("()=>__calls.filter(c=>c[0]==='usage_by_account_v1199c168').map(c=>c[1].p_days)"), [7, 30, 30])

    def test_others_do_not_see_it(self):
        # 管理者でも見られる人でなければ、ボタンが出ず、画面も開けない
        page = self.open_app("admin", False)
        page.evaluate("()=>accountMenu()")
        page.wait_for_timeout(500)
        self.assertFalse(page.evaluate("()=>!!document.getElementById('c168MenuUsage')"))
        page.evaluate("()=>c168UsagePage()")
        page.get_by_text("この画面は見られません").wait_for()
        self.assertEqual(page.evaluate("()=>__calls.filter(c=>c[0]==='usage_by_account_v1199c168').length"), 0)
        # 管理者以外はサーバーに聞きもしない
        worker = self.open_app("worker", True)
        worker.evaluate("()=>accountMenu()")
        worker.wait_for_timeout(500)
        self.assertFalse(worker.evaluate("()=>!!document.getElementById('c168MenuUsage')"))
        self.assertEqual(worker.evaluate("()=>__calls.length"), 0)


if __name__ == '__main__':
    unittest.main()
