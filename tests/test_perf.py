"""c152：動作の重さを測る（js/33-c152-perf.js）。アプリ全体を開き、測って送る部分だけを確かめる（画面と動きは変えない）。"""
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


class PerfTests(unittest.TestCase):
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

    def open_app(self, role="worker"):
        context = self.browser.new_context(viewport={"width": 820, "height": 1180}, service_workers="block", timezone_id="Asia/Tokyo")
        self.addCleanup(context.close)
        context.route("**/*", lambda route: route.continue_() if urlparse(route.request.url).netloc == self.local else route.abort())
        page = context.new_page()
        errors = []
        page.on("pageerror", lambda error: errors.append(str(error)))
        self.addCleanup(lambda: self.assertEqual(errors, []))
        page.goto(self.url, wait_until="load")
        page.wait_for_function("()=>typeof c152Perf==='object'")
        page.wait_for_timeout(500)
        page.evaluate(MOCK, role)
        page.evaluate("()=>{window.__sent=[];callRpc=async(n,a)=>{if(n==='log_app_perf_v1199c152'){__sent.push(a.p_rows);if(window.__noSql)throw new Error('PGRST202 Could not find the function');return a.p_rows.length}return []}}")
        return page

    def test_labels_keep_only_table_or_function_names(self):
        page = self.open_app()
        out = page.evaluate("""()=>[c152Perf.label('https://x.supabase.co/rest/v1/app_state?id=eq.ishioka&select=data'),
          c152Perf.label('https://x.supabase.co/rest/v1/rpc/get_purchase_prices'),
          c152Perf.label('https://x.supabase.co/auth/v1/token?grant_type=refresh_token'),
          c152Perf.label('https://x.supabase.co/storage/v1/object/qr-quality-photos/0f9945e9-a77b-470a-80c9-7d89350f3f2f/a.jpg'),
          c152Perf.label('/js/02-core.js')]""")
        self.assertEqual(out, ["rest:app_state", "rest:rpc/get_purchase_prices", "auth:token", "storage:object/qr-quality-photos/…", None])

    def test_network_and_pages_are_measured_and_sent_without_contents(self):
        page = self.open_app()
        page.evaluate("async()=>{await fetch('/rest/v1/app_state?id=eq.secret&select=data').catch(()=>{});await fetch('/rest/v1/rpc/log_app_perf_v1199c152').catch(()=>{})}")
        page.wait_for_function("()=>c152Perf.queue().some(r=>r.kind==='net')")
        page.evaluate("()=>home()")
        page.wait_for_function("()=>c152Perf.queue().some(r=>r.kind==='page'&&r.name==='home')")
        rows = page.evaluate("()=>c152Perf.queue()")
        net = [r for r in rows if r["kind"] == "net"]
        self.assertEqual([r["name"] for r in net], ["rest:app_state"])  # 送る通信そのものは測らない
        self.assertNotIn("secret", str(rows))
        self.assertIsInstance(net[0]["ms"], int)
        self.assertGreater(net[0]["bytes"], 0)
        page.evaluate("()=>c152Perf.flush()")
        page.wait_for_function("()=>__sent.length===1")
        sent = page.evaluate("()=>__sent[0]")
        self.assertTrue(all(r["role"] == "worker" and r["device"] and "app_version" in r for r in sent))
        self.assertEqual(page.evaluate("()=>c152Perf.queue().length"), 0)

    def test_stops_quietly_when_sql_is_not_run_yet(self):
        page = self.open_app()
        page.evaluate("()=>{window.__noSql=true;c152Perf.add('page','x',10)}")
        page.evaluate("async()=>{await c152Perf.flush()}")
        page.evaluate("()=>c152Perf.add('page','y',10)")
        self.assertEqual(page.evaluate("()=>c152Perf.queue().length"), 0)
        page.evaluate("async()=>{await c152Perf.flush()}")
        self.assertEqual(page.evaluate("()=>__sent.length"), 1)

    def test_pages_still_work_after_wrapping(self):
        page = self.open_app("buyer")
        self.assertTrue(page.evaluate("()=>home.__c152===true"))
        page.evaluate("()=>home()")
        page.wait_for_selector("#app .homePrimary, #app .homeSummary")


if __name__ == "__main__":
    unittest.main()
