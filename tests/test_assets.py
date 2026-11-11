import json
import re
import subprocess
import threading
import unittest
from html.parser import HTMLParser
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urljoin, urlsplit

from playwright.sync_api import sync_playwright

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
MOCK = (HERE / "mock_hq.js").read_text(encoding="utf-8")
PREFIX = "/seika-plus/"
OLD_CACHE_NAME = "seika-static-v1.199-c94-r3"
OLD_SHELL = [
    "./", "./index.html", "./manifest.webmanifest", "./icons/seika-192.png",
    "./icons/seika-512.png", "./vendor/exceljs-4.4.0.min.js",
    "./vendor/html2canvas-1.4.1.min.js", "./vendor/html5-qrcode-2.3.8.min.js",
    "./vendor/jspdf-2.5.1.umd.min.js", "./vendor/xlsx-js-style-1.2.0.bundle.js",
]
OLD_HTML = '<!doctype html><meta charset="utf-8"><title>old</title><script>navigator.serviceWorker.register("./sw.js",{scope:"./"})</script>'
OLD_SW = (
    'const CACHE_NAME="seika-static-v1.199-c94-r3";'
    'const APP_SHELL=["./","./index.html","./manifest.webmanifest","./icons/seika-192.png","./icons/seika-512.png","./vendor/exceljs-4.4.0.min.js","./vendor/html2canvas-1.4.1.min.js","./vendor/html5-qrcode-2.3.8.min.js","./vendor/jspdf-2.5.1.umd.min.js","./vendor/xlsx-js-style-1.2.0.bundle.js"];'
    'self.addEventListener("install",event=>event.waitUntil(caches.open(CACHE_NAME).then(cache=>cache.addAll(APP_SHELL))));'
    'self.addEventListener("activate",event=>event.waitUntil(self.clients.claim()));'
    'self.addEventListener("fetch",event=>{if(event.request.method!=="GET")return;event.respondWith(caches.match(event.request).then(hit=>hit||fetch(event.request)));});'
)
CSS_LOAD_ORDER = [
    "./css/01-base.css", "./css/02-kataoka-stock.css", "./css/03-qr-edit.css",
    "./css/04-role-home.css", "./css/05-operation-guide.css", "./css/06-year-summary.css",
    "./css/07-home-layout.css", "./css/08-qr-flow.css", "./css/09-home-colors.css",
    "./css/10-home-gradients.css", "./css/11-quality-tasks.css", "./css/12-honsha.css",
]
SCRIPT_LOAD_ORDER = [
    "vendor/xlsx-js-style-1.2.0.bundle.js", "vendor/exceljs-4.4.0.min.js",
    "./js/01-events.js", "vendor/html5-qrcode-2.3.8.min.js",
    "vendor/html2canvas-1.4.1.min.js", "vendor/jspdf-2.5.1.umd.min.js",
    "./js/02-core.js", "./js/03-inventory.js", "./js/04-honsha.js",
    "./js/05-c52-qr-outbound.js", "./js/06-c55-qr-poster.js",
    "./js/07-c56-qr-storage.js", "./js/08-c64-daily-report.js",
    "./js/09-c68-replacement-items.js", "./js/10-c69-honsha-management.js",
    "./js/11-c73-button-descriptions.js", "./js/12-c74-stock-copy.js",
    "./js/13-c81-analysis.js", "./js/14-c83-direct-via.js",
    "./js/15-c84-delivery-slips.js", "./js/16-c85-sunday-loading.js",
    "./js/17-c86-container-weight.js", "./js/18-c88-optimal-review.js",
    "./js/19-c89-optimal-history.js", "./js/20-c91-honsha-views.js",
    "./js/21-c107-stock-print.js", "./js/22-c110-buyer-assign.js",
    "./js/23-c113-outbound-correct.js",
]


class Nodes(HTMLParser):
    def __init__(self):
        super().__init__()
        self.scripts = []
        self.links = []
        self.styles = 0
        self.inline = []
        self._script = None

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "script":
            self.scripts.append(attrs)
            if not attrs.get("src"):
                self._script = []
        elif tag == "link" and "stylesheet" in attrs.get("rel", "").lower():
            self.links.append(attrs)
        elif tag == "style":
            self.styles += 1

    def handle_data(self, data):
        if self._script is not None:
            self._script.append(data)

    def handle_endtag(self, tag):
        if tag == "script" and self._script is not None:
            self.inline.append("".join(self._script))
            self._script = None


class PrefixServer(ThreadingHTTPServer):
    allow_reuse_address = True
    legacy = False


class PrefixHandler(SimpleHTTPRequestHandler):
    def log_message(self, _format, *_args):
        pass

    def do_GET(self):
        path = unquote(urlsplit(self.path).path)
        relative = path.removeprefix(PREFIX)
        if self.server.legacy and path.startswith(PREFIX) and relative in ("", "index.html", "sw.js"):
            body = OLD_SW if relative == "sw.js" else OLD_HTML
            content_type = "application/javascript" if relative == "sw.js" else "text/html; charset=utf-8"
            encoded = body.encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", content_type)
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(encoded)))
            self.end_headers()
            self.wfile.write(encoded)
            return
        super().do_GET()

    def translate_path(self, path):
        path = unquote(urlsplit(path).path)
        if not path.startswith(PREFIX):
            return str(ROOT / "__missing__")
        target = (ROOT / path[len(PREFIX):]).resolve()
        if ROOT not in target.parents and target != ROOT:
            return str(ROOT / "__missing__")
        return str(target)


def start_server():
    server = PrefixServer(("127.0.0.1", 0), PrefixHandler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


def parse_shell():
    source = (ROOT / "sw.js").read_text(encoding="utf-8")
    name = re.search(r'const CACHE_NAME="([^"]+)"', source)
    shell = re.search(r"const APP_SHELL=(\[[^;]+\]);", source)
    if not name or not shell:
        raise AssertionError("sw.jsのキャッシュ定義を読めません")
    return name.group(1), json.loads(shell.group(1))


class AssetTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = start_server()
        cls.base = f"http://127.0.0.1:{cls.server.server_port}{PREFIX}"
        cls.cache_name, cls.shell = parse_shell()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def nodes(self):
        parser = Nodes()
        parser.feed((ROOT / "index.html").read_text(encoding="utf-8"))
        return parser

    def app_assets(self):
        nodes = self.nodes()
        css = [link["href"] for link in nodes.links]
        js = [script["src"] for script in nodes.scripts]
        return css, js

    def test_static_asset_load_order_is_fixed(self):
        css, js = self.app_assets()
        self.assertEqual(css, CSS_LOAD_ORDER)
        self.assertEqual(js, SCRIPT_LOAD_ORDER)

    def test_static_assets_are_external_and_parse(self):
        nodes = self.nodes()
        css, js = self.app_assets()
        self.assertEqual(nodes.styles, 0)
        self.assertEqual(nodes.inline, [])
        self.assertTrue(css and js)
        self.assertEqual(len([path for path in css if path.startswith("./css/")]), 12)
        self.assertEqual(len([path for path in js if path.startswith("./js/")]), 23)
        for attrs in [*nodes.links, *nodes.scripts]:
            self.assertNotIn("async", attrs)
            self.assertNotIn("defer", attrs)
            self.assertNotEqual(attrs.get("type", "").lower(), "module")
        files = [*css, *js, "./sw.js"]
        for path in files:
            self.assertTrue((ROOT / path.removeprefix("./")).is_file(), path)
        command = [
            "node", "-e",
            "for(const p of process.argv.slice(1)){new Function(require('fs').readFileSync(p,'utf8'))}",
            *[str(ROOT / path.removeprefix("./")) for path in files if path.endswith(".js")],
        ]
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr or result.stdout)

    def test_service_worker_caches_every_external_asset(self):
        css, js = self.app_assets()
        new_assets = [path for path in [*css, *js] if path.startswith(("./css/", "./js/"))]
        self.assertEqual(len(new_assets), 35)
        self.assertEqual(len(set(new_assets)), 35)
        shell = set(self.shell)
        self.assertTrue(set(new_assets).issubset(shell), sorted(set(new_assets) - shell))
        for path in [*css, *js]:
            self.assertIn("./" + path.removeprefix("./"), shell, path)
        source = (ROOT / "sw.js").read_text(encoding="utf-8")
        self.assertIn('if(event.data&&event.data.type==="SKIP_WAITING")self.skipWaiting()', source)
        self.assertIn('event.data&&event.data.type==="GET_VERSION"', source)
        self.assertIn('type:"SEIKA_VERSION_READY",version:APP_VERSION', source)

    def test_service_worker_updates_from_c94_cache_to_c95_assets(self):
        self.server.legacy = True
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch()
            try:
                context = browser.new_context(viewport={"width": 820, "height": 1180})
                try:
                    failed, errors = [], []

                    def route(route):
                        if urlsplit(route.request.url).netloc == urlsplit(self.base).netloc:
                            route.continue_()
                        else:
                            route.abort()

                    context.route("**/*", route)
                    page = context.new_page()
                    page.on("pageerror", lambda error: errors.append(str(error)))
                    page.on("requestfailed", lambda request: failed.append(request.url))
                    page.goto(f"{self.base}index.html?legacy=c94-r3", wait_until="load")
                    page.evaluate("()=>navigator.serviceWorker.ready.then(()=>true)")
                    page.wait_for_function("()=>!!navigator.serviceWorker.controller")
                    old_cached = page.evaluate(
                        """async name=>{
                          const cache=await caches.open(name);
                          return (await cache.keys()).map(request=>new URL(request.url).pathname);
                        }""",
                        OLD_CACHE_NAME,
                    )
                    self.assertEqual(len(old_cached), len(OLD_SHELL))
                    self.assertFalse(any(path.startswith(f"{PREFIX}css/") or path.startswith(f"{PREFIX}js/") for path in old_cached))
                    self.server.legacy = False
                    page.evaluate(
                        """async()=>{
                          const registration=await navigator.serviceWorker.getRegistration();
                          await registration.update();
                          await new Promise((resolve,reject)=>{
                            const deadline=setTimeout(()=>reject(new Error('waiting worker timeout')),5000);
                            const check=()=>{
                              if(registration.waiting){clearTimeout(deadline);resolve();}
                            };
                            registration.addEventListener('updatefound',()=>{
                              registration.installing?.addEventListener('statechange',check);
                            });
                            check();
                          });
                          const changed=new Promise(resolve=>navigator.serviceWorker.addEventListener('controllerchange',resolve,{once:true}));
                          registration.waiting.postMessage({type:'SKIP_WAITING'});
                          await changed;
                        }"""
                    )
                    page.evaluate(
                        """async oldName=>{
                          const deadline=Date.now()+5000;
                          while((await caches.keys()).includes(oldName)){
                            if(Date.now()>deadline)throw new Error('old cache was not deleted');
                            await new Promise(resolve=>setTimeout(resolve,25));
                          }
                        }""",
                        OLD_CACHE_NAME,
                    )
                    cache_names = page.evaluate("()=>caches.keys()")
                    self.assertIn(self.cache_name, cache_names)
                    self.assertNotIn(OLD_CACHE_NAME, cache_names)
                    cached = page.evaluate(
                        """async([name,shell])=>{
                          const cache=await caches.open(name);
                          return Promise.all(shell.map(async path=>[path,!!await cache.match(new URL(path,location.href).href)]));
                        }""",
                        [self.cache_name, self.shell],
                    )
                    self.assertEqual([path for path, ok in cached if not ok], [])
                    page.goto(f"{self.base}index.html?updated=c95-r1", wait_until="load")
                    page.wait_for_function("()=>typeof window.hqHome==='function'")
                    context.set_offline(True)
                    page.reload(wait_until="load")
                    page.wait_for_function("()=>typeof window.hqHome==='function'")
                    page.evaluate(MOCK, "hq_worker")
                    page.evaluate("()=>{hqHome();v195RoleGuidePage()}")
                    page.wait_for_selector("#app")
                    self.assertIn("操作ガイド", page.locator("#app").inner_text())
                    local_assets = {urljoin(self.base, path) for path in [*self.app_assets()[0], *self.app_assets()[1]]}
                    self.assertEqual([url for url in failed if url.split("?", 1)[0] in local_assets], [])
                    self.assertEqual(errors, [])
                finally:
                    context.close()
            finally:
                browser.close()
                self.server.legacy = False

    def test_service_worker_reloads_the_cached_app_offline(self):
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch()
            try:
                context = browser.new_context(viewport={"width": 820, "height": 1180})
                try:
                    failed, errors = [], []

                    def route(route):
                        if urlsplit(route.request.url).netloc == urlsplit(self.base).netloc:
                            route.continue_()
                        else:
                            route.abort()

                    context.route("**/*", route)
                    page = context.new_page()
                    page.on("pageerror", lambda error: errors.append(str(error)))
                    page.on("requestfailed", lambda request: failed.append(request.url))
                    url = f"{self.base}index.html?fixture=test"
                    page.goto(url, wait_until="load")
                    page.wait_for_function("()=>typeof window.hqHome==='function'")
                    page.evaluate("()=>navigator.serviceWorker.ready.then(()=>true)")
                    page.reload(wait_until="load")
                    page.wait_for_function("()=>!!navigator.serviceWorker.controller")
                    page.wait_for_function("()=>typeof window.hqHome==='function'")
                    cached = page.evaluate(
                        """async([name,shell])=>{
                          const cache=await caches.open(name);
                          return Promise.all(shell.map(async path=>[path,!!await cache.match(new URL(path,location.href).href)]));
                        }""",
                        [self.cache_name, self.shell],
                    )
                    self.assertEqual([path for path, ok in cached if not ok], [])
                    context.set_offline(True)
                    page.reload(wait_until="load")
                    page.wait_for_function("()=>typeof window.hqHome==='function'")
                    page.evaluate(MOCK, "hq_worker")
                    page.evaluate("()=>{hqHome();v195RoleGuidePage()}")
                    page.wait_for_selector("#app")
                    self.assertIn("操作ガイド", page.locator("#app").inner_text())
                    self.assertTrue(page.evaluate("()=>typeof window.hqMakePdf==='function'"))
                    local_assets = {urljoin(self.base, path) for path in [*self.app_assets()[0], *self.app_assets()[1]]}
                    self.assertEqual([url for url in failed if url.split("?", 1)[0] in local_assets], [])
                    self.assertEqual(errors, [])
                finally:
                    context.close()
            finally:
                browser.close()


if __name__ == "__main__":
    unittest.main()
