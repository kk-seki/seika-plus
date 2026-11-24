"""c160：納品先マスタをクラウドに（3区分・外販先）。"""
import functools, sys, threading, unittest
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
MOCK = (ROOT / 'tests' / 'mock_hq.js').read_text(encoding='utf-8')
SERVER_MOCK = """()=>{
  window.__srv=[{name:'本社',formal:'',kind:'内',group:'社内',outbound:true,weight:false,active:true,sort:1},
    {name:'埼玉',formal:'',kind:'内',group:'社内',outbound:true,weight:false,active:true,sort:2},
    {name:'プライムデリカ 龍ケ崎工場',formal:'',kind:'外',group:'プライム',outbound:false,weight:true,active:true,sort:100},
    {name:'旭物産',formal:'',kind:'販',group:'外販先',outbound:true,weight:false,active:true,sort:200}];
  window.__calls=[];
  callRpc=async(n,a)=>{__calls.push([n,a]);
    if(n==='list_dest_master_v1199c160')return JSON.parse(JSON.stringify(__srv));
    if(n==='save_dest_master_v1199c160'){const r=a.p_row;if(a.p_old_name){const i=__srv.findIndex(x=>x.name===a.p_old_name);__srv[i]={...__srv[i],...r}}else __srv.push({...r,sort:300});return {ok:true}}
    if(n==='delete_dest_master_v1199c160'){__srv=__srv.filter(x=>x.name!==a.p_name);return {ok:true}}
    return null};
  window.alert=()=>{};window.confirm=()=>true;
}"""


class DestMasterTests(unittest.TestCase):
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

    def open_app(self, role="admin"):
        ctx = self.browser.new_context(service_workers="block", timezone_id="Asia/Tokyo")
        local = urlparse(self.url).netloc
        ctx.route("**/*", lambda r: r.continue_() if urlparse(r.request.url).netloc == local else r.abort())
        page = ctx.new_page(); errs = []
        page.on("pageerror", lambda e: errs.append(str(e)))
        page.goto(self.url, wait_until="load")
        page.wait_for_function("()=>typeof c160LoadDests==='function'")
        page.wait_for_timeout(500)  # 起動時のログイン確認が終わってから役割を入れる
        page.evaluate(MOCK, role); page.evaluate(SERVER_MOCK)
        self.addCleanup(ctx.close); self.errs = errs
        return page

    def test_loads_from_cloud_and_sets_outbound_choices(self):
        page = self.open_app("worker")
        page.evaluate("()=>c160LoadDests(true)")
        self.assertEqual(page.evaluate("()=>[...QR_OUT_DESTINATIONS]"), ["本社", "埼玉", "旭物産"])
        self.assertEqual(page.evaluate("()=>v194EnsureDestinations().find(r=>r.name==='旭物産').kind"), "販")

    def test_admin_adds_external_seller_and_it_survives_reload(self):
        page = self.open_app("admin")
        page.evaluate("()=>v194DestinationsPage()")
        page.wait_for_selector("#v194DestName")
        self.assertIn("外販先（産地報告に入らない）", page.inner_text("#app"))
        self.assertTrue(page.locator("#c134DestTabs").count() == 1)
        page.fill("#v194DestName", "イバラキ食品")
        page.select_option("#v194DestKind", "販")
        page.evaluate("()=>c160AddDest()")
        page.wait_for_function("()=>document.body.innerText.includes('納品先を追加しました')")
        saved = page.evaluate("()=>__calls.find(c=>c[0]==='save_dest_master_v1199c160')[1]")
        self.assertEqual((saved["p_old_name"], saved["p_row"]["kind"], saved["p_row"]["group"], saved["p_row"]["outbound"]), (None, "販", "外販先", True))
        # 再読込したつもり：端末の中を消してクラウドから読み直す
        page.evaluate("()=>{db.v194Destinations=[];c160State.loaded=false;return c160LoadDests(true)}")
        self.assertIn("イバラキ食品", page.evaluate("()=>[...QR_OUT_DESTINATIONS]"))

    def test_toggle_change_kind_and_delete_by_name(self):
        page = self.open_app("admin")
        page.evaluate("()=>v194DestinationsPage()"); page.wait_for_selector("#v194DestName")
        page.evaluate("()=>c160ToggleOutbound('旭物産')")
        page.wait_for_function("()=>document.body.innerText.includes('旭物産 を出庫先に表示しないようにしました')")
        self.assertNotIn("旭物産", page.evaluate("()=>[...QR_OUT_DESTINATIONS]"))
        page.evaluate("()=>{window.prompt=()=> 'プライム';const i=v194EnsureDestinations().findIndex(r=>r.name==='旭物産');document.getElementById('c160Kind_'+i).value='外';return c160SetKind('旭物産',i)}")
        page.wait_for_function("()=>document.body.innerText.includes('「社外の客先」にしました')")
        self.assertEqual(page.evaluate("()=>__srv.find(r=>r.name==='旭物産').group"), "プライム")
        page.evaluate("()=>c160RemoveDest('旭物産')")
        page.wait_for_function("()=>document.body.innerText.includes('削除しました')")
        self.assertFalse(page.evaluate("()=>__srv.some(r=>r.name==='旭物産')"))

    def test_cloud_rows_survive_when_db_is_replaced_c161(self):
        # c161：再読込などで db が入れ替わり、端末の古い内容（旭物産なし）に戻っても、クラウドの内容を使う
        page = self.open_app("admin")
        page.evaluate("()=>c160LoadDests(true)")
        page.evaluate("()=>{db.v194Destinations=[{name:'本社',kind:'内',group:'社内',outbound:true}]}")
        self.assertIn("旭物産", page.evaluate("()=>v194EnsureDestinations().map(r=>r.name)"))
        page.evaluate("()=>v194DestinationsPage()")
        self.assertIn("旭物産", page.inner_text("#app"))
        page.evaluate("()=>{window.__a=[];window.alert=m=>__a.push(m)}")
        page.fill("#v194DestName", "旭物産")
        page.evaluate("()=>c160AddDest()")
        self.assertIn("すでに「外販先」に入っています", page.evaluate("()=>__a.join()"))
        self.assertFalse(page.evaluate("()=>__calls.some(c=>c[0]==='save_dest_master_v1199c160')"))

    def test_before_sql_066_keeps_local_and_shows_notice(self):
        page = self.open_app("admin")
        page.evaluate("()=>{const base=callRpc;callRpc=async(n,a)=>{if(n==='list_dest_master_v1199c160')throw new Error('Could not find the function public.list_dest_master_v1199c160 PGRST202');return base(n,a)};c160State.loaded=false}")
        page.evaluate("()=>v194DestinationsPage()")
        self.assertEqual(page.evaluate("()=>currentScreen"), "v194DestinationsPage", page.inner_text("body")[:300])
        self.assertIn("SQL 066 が未実行", page.inner_text("#app"))
        self.assertIn("本社", page.evaluate("()=>[...QR_OUT_DESTINATIONS]"))

    def test_non_admin_cannot_open(self):
        page = self.open_app("worker")
        page.evaluate("()=>{window.__a=[];window.alert=m=>__a.push(m)}")
        page.evaluate("()=>c160Page()")
        self.assertIn("納品先マスタは管理者のみです", page.evaluate("()=>__a.join()"))


if __name__ == "__main__":
    unittest.main()
