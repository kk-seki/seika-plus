"""c163：出庫先「返品」と、返品を石岡の在庫に戻す画面。"""
import functools, threading, unittest
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
MOCK = (ROOT / 'tests' / 'mock_hq.js').read_text(encoding='utf-8')
SERVER_MOCK = """()=>{
  window.__calls=[];
  window.__rows=[{movement_id:'m1',operation_id:'o1',out_date:'2026-11-20',destination:'埼玉',lot_id:'l1',qr_key:'QR-1',lot_no:'L-1',
    item_name:'キャベツ',received_date:'2026-11-18',unit:'CS',qty:5,returned:1,left:4,grades:[],lot_active:true,hq:null},
   {movement_id:'m2',operation_id:'o2',out_date:'2026-11-21',destination:'本社',lot_id:'l2',qr_key:'QR-2',lot_no:'L-2',
    item_name:'胡瓜',received_date:'2026-11-19',unit:'CS',qty:3,returned:0,left:3,lot_active:true,
    grades:[{grade:'A',shipped:2,left:2},{grade:'B',shipped:1,left:1}],hq:{status:'在庫あり',unit:'ケース',current_qty:3}}];
  callRpc=async(n,a)=>{__calls.push([n,a]);
    if(n==='list_qr_returnable_v1199c163')return JSON.parse(JSON.stringify(__rows));
    if(n==='list_qr_returns_v1199c163')return [{id:'r1',item_name:'キャベツ',from:'埼玉',qty:1,unit:'CS',return_date:'2026-11-22',out_date:'2026-11-20',lot_no:'L-1',received_date:'2026-11-18',memo:'傷み',created_by_name:'管理者'}];
    if(n==='return_qr_to_ishioka_v1199c163')return {ok:true,before_quantity:0,after_quantity:a.p_qty,hq_action:'在庫から減らす',hq_qty:a.p_qty,hq_unit:'ケース'};
    if(n==='cancel_qr_return_v1199c163')return {ok:true};
    return null};
  window.alert=m=>{window.__alert=m};window.confirm=()=>true;window.prompt=()=> '入れ間違い';
}"""


class ReturnsTests(unittest.TestCase):
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
        page.wait_for_function("()=>typeof c163ReturnsPage==='function'")
        page.wait_for_timeout(500)
        page.evaluate(MOCK, role); page.evaluate(SERVER_MOCK)
        self.addCleanup(ctx.close); self.errs = errs
        return page

    def test_return_destination_needs_no_timing_but_a_memo(self):
        page = self.open_app("worker")
        self.assertEqual(page.evaluate("()=>[c163NoTiming('廃棄'),c163NoTiming(' 返品 '),c163NoTiming('埼玉'),c163IsReturnDest('返品')]"), [True, True, False, True])
        self.assertIn("返品", page.evaluate("()=>[...QR_OUT_DESTINATIONS]"))
        page.evaluate("()=>{v135DefaultValidation('out',{destination:'返品',shipTiming:'',memo:'品質不良'})}")
        msg = page.evaluate("()=>{try{v135DefaultValidation('out',{destination:'返品',shipTiming:'',memo:''});return ''}catch(e){return e.message}}")
        self.assertIn("理由", msg)
        msg = page.evaluate("()=>{try{v135DefaultValidation('out',{destination:'埼玉',shipTiming:'',memo:''});return ''}catch(e){return e.message}}")
        self.assertIn("出庫区分", msg)

    def test_search_by_destination_and_return_with_grades(self):
        page = self.open_app("admin")
        page.evaluate("()=>c163ReturnsPage()")
        page.wait_for_selector("#c163Dest")
        options = page.evaluate("()=>[...document.querySelectorAll('#c163Dest option')].map(o=>o.value)")
        self.assertNotIn("廃棄", options); self.assertNotIn("返品", options)
        page.select_option("#c163Dest", "本社")
        page.evaluate("()=>c163Search()")
        page.wait_for_function("()=>document.body.innerText.includes('胡瓜')")
        call = page.evaluate("()=>__calls.filter(c=>c[0]==='list_qr_returnable_v1199c163').pop()[1]")
        self.assertEqual((call["p_destination"], call["p_qr_key"]), ("本社", None))
        self.assertIn("本社の在庫も減らします", page.inner_text("#c163Results"))
        page.evaluate("()=>c163OpenForm(1)")
        page.wait_for_selector("#c163Grade_1")
        page.fill("#c163Qty", "2"); page.fill("#c163Grade_0", "2"); page.fill("#c163Grade_1", "1")
        page.evaluate("()=>c163Save()")
        self.assertIn("合計", page.evaluate("()=>window.__alert||''"))
        page.fill("#c163Grade_0", "1"); page.fill("#c163Memo", "品質不良")
        page.evaluate("()=>c163Save()")
        page.wait_for_function("()=>document.body.innerText.includes('石岡の在庫に戻しました')")
        args = page.evaluate("()=>__calls.find(c=>c[0]==='return_qr_to_ishioka_v1199c163')[1]")
        self.assertEqual((args["p_movement_id"], args["p_qty"], args["p_memo"]), ("m2", 2, "品質不良"))
        self.assertEqual(args["p_grades"], [{"grade": "A", "qty": 1}, {"grade": "B", "qty": 1}])
        self.assertIn("本社の在庫を 2 ケース 減らしました", page.inner_text("#app"))
        self.assertEqual(self.errs, [])

    def test_qr_search_list_and_cancel(self):
        page = self.open_app("admin")
        page.evaluate("()=>c163ReturnsPage({key:'HQ-9'})")
        page.wait_for_function("()=>document.body.innerText.includes('キャベツ')&&document.getElementById('c163Key')")
        call = page.evaluate("()=>__calls.filter(c=>c[0]==='list_qr_returnable_v1199c163').pop()[1]")
        self.assertEqual(call["p_qr_key"], "HQ-9")
        page.wait_for_function("()=>document.getElementById('c163Returns').innerText.includes('傷み')")
        page.evaluate("()=>c163Cancel('r1')")
        page.wait_for_function("()=>document.body.innerText.includes('返品を取り消しました')")
        args = page.evaluate("()=>__calls.find(c=>c[0]==='cancel_qr_return_v1199c163')[1]")
        self.assertEqual((args["p_return_id"], args["p_reason"]), ("r1", "入れ間違い"))

    def test_buyer_cannot_open(self):
        page = self.open_app("buyer")
        page.evaluate("()=>c163ReturnsPage()")
        self.assertIn("管理者・青果社員", page.evaluate("()=>window.__alert||''"))


if __name__ == "__main__":
    unittest.main()
