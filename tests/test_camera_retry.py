import functools
import threading
import unittest
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parent.parent
FAKE_CAMERA = """
window.__gum = {mode: 'deny', calls: 0};
navigator.mediaDevices.getUserMedia = async () => {
  window.__gum.calls++;
  if (window.__gum.mode === 'deny') throw new DOMException('Permission denied', 'NotAllowedError');
  if (window.__gum.mode === 'dismissed') throw new DOMException('Permission dismissed', 'NotAllowedError');
  if (window.__gum.mode === 'missing') throw new DOMException('Requested device not found', 'NotFoundError');
  const canvas = document.createElement('canvas');
  canvas.width = 640; canvas.height = 480;
  canvas.getContext('2d').fillRect(0, 0, 640, 480);
  return canvas.captureStream(10);
};
"""


class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, *_args):
        pass


class CameraRetryTests(unittest.TestCase):
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
        context = self.browser.new_context(viewport={"width": 820, "height": 1180}, service_workers="block")
        self.addCleanup(context.close)
        context.route("**/*", lambda route: route.continue_() if urlparse(route.request.url).netloc == self.local else route.abort())
        context.add_init_script(FAKE_CAMERA)
        page = context.new_page()
        errors = []
        page.on("pageerror", lambda error: errors.append(str(error)))
        self.addCleanup(lambda: self.assertEqual(errors, [], "browser errors"))
        page.goto(self.url, wait_until="load")
        page.wait_for_function("()=>typeof qrCameraPage==='function' && typeof Html5Qrcode==='function'")
        page.wait_for_timeout(500)
        page.evaluate("role=>{db.role=role;db.user='テスト';window.alert=()=>{}}", role)
        return page

    def open_lot_camera(self, page):
        page.evaluate("()=>qrCameraPage('detail')")
        page.wait_for_selector("#c115CameraHelp_qrReader, #qrReader video", timeout=5000)

    def test_denied_camera_shows_steps_and_retry_button_starts_it_without_reopening_the_screen(self):
        page = self.open_app()
        self.open_lot_camera(page)
        help_text = page.locator("#c115CameraHelp_qrReader").inner_text()
        for word in ("カメラが許可されていません", "アプリ情報", "鍵マーク", "Safari", "許可したので、カメラを起動する"):
            self.assertIn(word, help_text)
        self.assertNotIn("カメラを起動できませんでした", page.locator("#qrCameraMsg").inner_text())
        calls = page.evaluate("()=>__gum.calls")
        page.locator(".c115CameraRetry").click()
        page.wait_for_function("n=>__gum.calls>n", arg=calls)
        self.assertIn("まだ許可されていません", page.locator(".c115CameraNote").inner_text())
        self.assertTrue(page.locator(".c115CameraRetry").is_enabled())
        page.evaluate("()=>{__gum.mode='allow'}")
        page.locator(".c115CameraRetry").click()
        page.wait_for_selector("#qrReader video", timeout=5000)
        self.assertEqual(page.locator("#c115CameraHelp_qrReader").count(), 0)
        self.assertNotIn("カメラを起動できませんでした", page.locator("#qrCameraMsg").inner_text())
        page.evaluate("()=>qrStopActiveCamera('lot')")

    def test_dismissed_prompt_is_treated_the_same_and_can_prompt_again(self):
        page = self.open_app()
        page.evaluate("()=>{__gum.mode='dismissed'}")
        self.open_lot_camera(page)
        self.assertEqual(page.locator("#c115CameraHelp_qrReader").count(), 1)
        page.evaluate("()=>{__gum.mode='allow'}")
        page.locator(".c115CameraRetry").click()
        page.wait_for_selector("#qrReader video", timeout=5000)
        page.evaluate("()=>qrStopActiveCamera('lot')")

    def test_camera_starts_by_itself_when_the_browser_reports_permission_granted(self):
        page = self.open_app()
        page.evaluate("()=>{window.__perm='denied';navigator.permissions.query=async()=>({state:window.__perm,onchange:null})}")
        self.open_lot_camera(page)
        self.assertEqual(page.locator("#c115CameraHelp_qrReader").count(), 1)
        calls = page.evaluate("()=>__gum.calls")
        page.wait_for_timeout(1500)
        self.assertEqual(page.evaluate("()=>__gum.calls"), calls, "denied state must not be retried automatically")
        page.evaluate("()=>{__gum.mode='allow';window.__perm='granted'}")
        page.wait_for_selector("#qrReader video", timeout=6000)
        self.assertEqual(page.locator("#c115CameraHelp_qrReader").count(), 0)
        page.evaluate("()=>qrStopActiveCamera('lot')")

    def test_dismissed_prompt_is_never_retried_in_a_loop(self):
        page = self.open_app()
        page.evaluate("()=>{__gum.mode='dismissed';navigator.permissions.query=async()=>({state:'prompt',onchange:null})}")
        self.open_lot_camera(page)
        calls = page.evaluate("()=>__gum.calls")
        page.wait_for_timeout(2500)
        self.assertEqual(page.evaluate("()=>__gum.calls"), calls)

    def test_other_camera_errors_keep_their_original_message_and_show_no_permission_help(self):
        page = self.open_app()
        page.evaluate("()=>{__gum.mode='missing'}")
        page.evaluate("()=>qrCameraPage('detail')")
        page.wait_for_function("()=>document.getElementById('qrCameraMsg')?.textContent.includes('カメラを起動できませんでした')", timeout=5000)
        self.assertEqual(page.locator(".c115CameraHelp").count(), 0)

    def test_leaving_the_screen_while_waiting_ends_the_pending_start_and_removes_the_help(self):
        page = self.open_app()
        result = page.evaluate("""async()=>{
          const host=document.createElement('div');host.id='c115Probe';document.body.appendChild(host);
          const started=new Html5Qrcode('c115Probe').start({facingMode:'environment'},{fps:5},()=>{}).then(()=>'started',e=>String(e));
          await new Promise(r=>setTimeout(r,300));
          const shown=!!document.getElementById('c115CameraHelp_c115Probe');
          host.remove();
          const outcome=await Promise.race([started,new Promise(r=>setTimeout(()=>r('still pending'),3000))]);
          return {shown,outcome,left:document.querySelectorAll('.c115CameraHelp').length};
        }""")
        self.assertTrue(result["shown"])
        self.assertIn("NotAllowedError", result["outcome"])
        self.assertEqual(result["left"], 0)

    def test_operation_guide_gets_the_camera_section_for_every_role(self):
        page = self.open_app()
        missing = page.evaluate("()=>Object.entries(V195_ROLE_GUIDES).filter(([k,g])=>g.sections&&!g.sections.some(x=>x.title==='カメラを許可していないとき（QRが読み取れない）')).map(([k])=>k)")
        self.assertEqual(missing, [])


if __name__ == "__main__":
    unittest.main()
