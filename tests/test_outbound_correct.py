import functools
import threading
import unittest
from datetime import datetime, timedelta, timezone
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse
from zoneinfo import ZoneInfo

from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parent.parent
OP = "11111111-1111-4111-8111-111111111111"


class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, *_args):
        pass


class OutboundCorrectTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(QuietHandler, directory=str(ROOT)))
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

    def open_app(self, role="admin"):
        context = self.browser.new_context(
            viewport={"width": 820, "height": 1180}, service_workers="block", timezone_id="Asia/Tokyo"
        )
        self.addCleanup(context.close)
        # The test server is the sole permitted origin: no production/cloud request may escape.
        context.route("**/*", lambda route: route.continue_() if urlparse(route.request.url).netloc == self.local else route.abort())
        page = context.new_page()
        errors = []
        page.on("pageerror", lambda error: errors.append(str(error)))
        self.addCleanup(lambda: self.assertEqual(errors, [], "browser errors"))
        page.goto(self.url, wait_until="load")
        page.wait_for_function("()=>typeof c113CorrectPage==='function' && typeof v1144OutboundCards==='function'")
        page.wait_for_timeout(500)
        page.evaluate("""role=>{
          db.role=role; db.user='テスト'; window.__alerts=[]; window.__confirms=[];
          window.alert=m=>window.__alerts.push(String(m)); window.confirm=m=>(window.__confirms.push(String(m)),true);
        }""", role)
        return page

    def install_api(self, page, *, destination="埼玉", qty=3, stock=5, grades=None, big=False, occurred_at=None):
        occurred_at = occurred_at or datetime.now(timezone.utc).isoformat()
        page.evaluate("""data=>{
          const movement={id:'movement-1',operation_id:data.op,lot_id:'lot-1',destination:data.destination,
            occurred_at:data.occurred_at,qty:data.qty,unit:'ケース',item_name:'キャベツ',
            container_type:data.big?'網コンテナ':'ダンボール',operation_meta:data.grades?{grades:data.grades.map(g=>({grade:g.grade,delta:-g.qty}))}:{}};
          const lot={id:'lot-1',current_qty:data.stock,unit:'ケース',container_type:movement.container_type};
          const gradeRows=(data.grades||[]).map((g,i)=>({grade:g.grade,current_qty:g.stock,sort_order:i+1}));
          window.__selects=[]; window.__calls=[]; window.__history=[]; window.__rpc=async()=>({ok:true});
          window.qrSelect=async(table, query)=>{window.__selects.push([table,query]);
            if(table==='qr_lot_movements')return [movement]; if(table==='qr_lots')return [lot];
            if(table==='qr_lot_grades_v1300')return gradeRows; throw new Error('unexpected select '+table)};
          window.callRpc=async(name,args)=>{window.__calls.push([name,args]);return window.__rpc(name,args)};
          window.v1144QrOutboundHistoryPage=async args=>window.__history.push(['page',args]);
          window.v1144LoadOutboundHistory=async force=>window.__history.push(['load',force]);
        }""", {"op": OP, "destination": destination, "qty": qty, "stock": stock, "grades": grades, "big": big, "occurred_at": occurred_at})

    def open_correction(self, page):
        page.evaluate("op=>c113CorrectPage(op)", OP)
        page.locator("#c113Qty").wait_for()

    def save(self, page):
        page.evaluate("()=>c113Save()")

    def test_eligibility_roles_hq_cancel_and_tokyo_day_boundary(self):
        page = self.open_app("admin")
        now = datetime.now(ZoneInfo("Asia/Tokyo"))
        today = now.replace(hour=0, minute=1, second=0, microsecond=0).astimezone(timezone.utc).isoformat()
        yesterday = (now.replace(hour=0, minute=0, second=0, microsecond=0) - timedelta(seconds=1)).astimezone(timezone.utc).isoformat()
        row = lambda **extra: {"destination": "埼玉", "operation_id": OP, "occurred_at": today, "item_name": "a", "qty": 1, "unit": "ケース", **extra}
        self.assertIn("数を訂正", page.evaluate("r=>v1144OutboundCards([r])", row()))
        for bad in (row(destination="本社"), row(destination="大阪"), row(occurred_at=yesterday), row(movement_type="取消"), row(is_cancelled=True), row(cancelled_at="x"), row(reversed_operation_id="x")):
            self.assertNotIn("数を訂正", page.evaluate("r=>v1144OutboundCards([r])", bad), bad)
        for role in ("worker",):
            worker = self.open_app(role)
            self.assertIn("数を訂正", worker.evaluate("r=>v1144OutboundCards([r])", row()))
        for role in ("buyer", "clerk", "sales", "viewer"):
            other = self.open_app(role)
            self.assertNotIn("数を訂正", other.evaluate("r=>v1144OutboundCards([r])", row()), role)

    def test_saves_decrease_increase_and_zero_with_actual_rpc_and_history(self):
        page = self.open_app()
        self.install_api(page)
        for value, expected in (("2", 2), ("4", 4), ("0", 0)):
            self.open_correction(page)
            page.locator("#c113Qty").fill(value)
            target = len(page.evaluate("()=>window.__calls")) + 1
            self.save(page)
            page.wait_for_function("n=>window.__calls.length>=n", arg=target)
            name, args = page.evaluate("()=>window.__calls.at(-1)")
            self.assertEqual(name, "correct_qr_outbound_v1199c113")
            self.assertEqual(args["p_original_operation_id"], OP)
            self.assertEqual(args["p_qty"], expected)
            self.assertEqual(args["p_expected_qty"], 5)
            self.assertEqual(args["p_grades"], [])
            self.assertIsNone(args["p_total_kg"])
        self.assertGreaterEqual(len(page.evaluate("()=>window.__history")), 6)

    def test_grade_fraction_big_kg_and_validation(self):
        page = self.open_app()
        self.install_api(page, big=True, grades=[{"grade": "A", "qty": 2, "stock": 3}, {"grade": "B", "qty": 1, "stock": 2}])
        self.open_correction(page)
        page.locator("#c113Qty").fill("2.5")
        page.locator("#c113Grade_0").fill("1.25")
        page.locator("#c113Grade_1").fill("1.25")
        page.locator("#c113Kg").fill("99.5")
        self.save(page)
        page.wait_for_function("()=>__calls.length===1")
        args = page.evaluate("()=>__calls[0][1]")
        self.assertEqual(args["p_qty"], 2.5)
        self.assertEqual(args["p_grades"], [{"grade": "A", "qty": 1.25}, {"grade": "B", "qty": 1.25}])
        self.assertEqual(args["p_total_kg"], 99.5)
        self.open_correction(page)
        page.locator("#c113Qty").fill("99")
        self.save(page)
        self.assertIn("必要な在庫", page.evaluate("()=>__alerts.at(-1)"))
        page.locator("#c113Qty").fill("")
        self.save(page)
        self.assertIn("0以上の数字", page.evaluate("()=>__alerts.at(-1)"))
        page.locator("#c113Qty").fill("1")
        page.locator("#c113Grade_0").fill("")
        self.save(page)
        self.assertIn("規格ごとの数量", page.evaluate("()=>__alerts.at(-1)"))

    def test_uncertain_network_retry_preserves_id_and_data_but_changed_input_is_blocked(self):
        page = self.open_app()
        self.install_api(page)
        page.evaluate("""()=>{let n=0;window.__rpc=async()=>{if(n++===0)throw new Error('network down');return {ok:true}}}""")
        self.open_correction(page)
        page.locator("#c113Qty").fill("2")
        self.save(page)
        page.wait_for_function("()=>__calls.length===1")
        first = page.evaluate("()=>__calls[0][1]")
        page.locator("#c113Qty").fill("3")
        self.save(page)
        self.assertEqual(page.evaluate("()=>__calls.length"), 1)
        self.assertIn("同じ入力で再試行", page.evaluate("()=>__alerts.at(-1)"))
        page.locator("#c113Qty").fill("2")
        self.save(page)
        page.wait_for_function("()=>__calls.length===2")
        second = page.evaluate("()=>__calls[1][1]")
        self.assertEqual(second["p_operation_id"], first["p_operation_id"])
        self.assertEqual(second["p_qty"], 2)

    def test_known_rpc_failure_allows_changed_retry_same_id_and_busy_blocks_double_submit(self):
        page = self.open_app()
        self.install_api(page)
        page.evaluate("""()=>{let resolve;window.__gate=new Promise(r=>resolve=r);window.__release=resolve;
          window.__rpc=async()=>window.__gate}""")
        self.open_correction(page)
        # Do not await the pending RPC: the second click must happen while it is busy.
        page.evaluate("()=>{c113Save();c113Save()}")
        page.wait_for_function("()=>__calls.length===1")
        page.evaluate("()=>__release({ok:false,message:'server rejected'})")
        page.wait_for_function("()=>document.querySelector('#c113Message').textContent.includes('server rejected')")
        first = page.evaluate("()=>__calls[0][1]")
        page.locator("#c113Qty").fill("2")
        page.evaluate("()=>{window.__rpc=async()=>({ok:true})}")
        self.save(page)
        page.wait_for_function("()=>__calls.length===2")
        second = page.evaluate("()=>__calls[1][1]")
        self.assertEqual(second["p_operation_id"], first["p_operation_id"])
        self.assertEqual(second["p_qty"], 2)

    def test_grade_load_failure_permission_recheck_and_guide(self):
        page = self.open_app()
        self.install_api(page)
        page.evaluate("""()=>{const select=qrSelect;qrSelect=async(t,q)=>t==='qr_lot_grades_v1300'?Promise.reject(new Error('grade load failed')):select(t,q)}""")
        page.evaluate("op=>c113CorrectPage(op)", OP)
        page.wait_for_function("()=>__alerts.length===1")
        self.assertIn("grade load failed", page.evaluate("()=>__alerts[0]"))
        self.install_api(page)
        self.open_correction(page)
        page.locator("#c113Qty").fill("2")
        page.evaluate("()=>db.role='buyer'")
        self.save(page)
        self.assertEqual(page.evaluate("()=>__calls.length"), 0)
        self.assertIn("管理者・青果社員", page.evaluate("()=>__alerts.at(-1)"))
        self.assertTrue(page.evaluate("()=>['admin','worker'].every(r=>V195_ROLE_GUIDES[r].sections.some(s=>s.title.includes('出庫数を訂正')))"))


if __name__ == "__main__":
    unittest.main()
