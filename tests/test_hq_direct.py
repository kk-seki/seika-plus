import functools
import json
import os
import threading
import unittest
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

from playwright.sync_api import sync_playwright

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
MOCK = (HERE / "mock_hq.js").read_text(encoding="utf-8")

SETUP = """()=>{
 window.__t={rpc:[],alerts:[]};
 window.alert=m=>window.__t.alerts.push(String(m));
 window.confirm=()=>true;
 callRpc=async(n,a)=>{
  window.__t.rpc.push([n,a]);
  if(n==='hq_direct_inbound_v1400'||n==='hq_direct_via_ishioka_v1199c83')return{lot:{id:'LX',qr_key:'KX'}};
  return[];
 };
 try{localStorage.setItem('seika_hq_site','honsha')}catch(e){}
}"""

SHEET_LOT = {
    "id": "L1", "lot_no": "H20261106-0095", "qr_key": "H20261106-0095", "item_name": "長葱",
    "status": "入荷待ち", "via_ishioka": True, "source_kind": "本社直接入荷", "unit": "ケース",
    "planned_qty": 60, "pack_weight": "10kg", "supplier": "JA水戸", "origin": "茨城県",
    "cooperative_name": "JA水戸", "planned_date": "2026-11-06", "ship_run": "市場便",
    "ship_run_time": "15時以降", "ship_day": "当日便", "created_by_name": "フレンキ",
    "container_type": "ダンボール",
}
SHEET_PAGES = [{"label": "パレット 1/2", "qty": "30 ケース"}, {"label": "パレット 2/2", "qty": "30 ケース"}]

NATURAL_HEIGHT = """()=>[...document.querySelectorAll('.sheet')].map(s=>{
 const t=s.querySelector('table'),left=s.querySelector('.left'),available=left.clientHeight;
 t.style.height='auto';t.style.flex='none';
 return{rows:t.querySelectorAll('tr').length,natural:t.getBoundingClientRect().height,available,
  text:t.innerText,name:t.querySelector('td.name').innerText.trim(),
  nameRowHeight:Math.round(t.querySelector('td.name').getBoundingClientRect().height)};
})"""


def start_server():
    handler = type("Quiet", (SimpleHTTPRequestHandler,), {"log_message": lambda *args: None})
    server = ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(handler, directory=str(ROOT)))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


class HqDirectTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = None
        cls.url = os.environ.get("SEIKA_URL", "")
        if not cls.url:
            cls.server = start_server()
            cls.url = f"http://127.0.0.1:{cls.server.server_port}/index.html"
        if urlparse(cls.url).hostname not in {"127.0.0.1", "localhost"}:
            raise ValueError("検証URLはローカルサーバーだけを指定してください")
        cls.local = urlparse(cls.url).netloc
        cls.playwright = sync_playwright().start()
        cls.browser = cls.playwright.chromium.launch()

    @classmethod
    def tearDownClass(cls):
        cls.browser.close()
        cls.playwright.stop()
        if cls.server:
            cls.server.shutdown()
            cls.server.server_close()

    def open_app(self, role):
        context = self.browser.new_context(viewport={"width": 820, "height": 1180}, service_workers="block")
        self.addCleanup(context.close)
        context.route(
            "**/*",
            lambda route: route.continue_() if urlparse(route.request.url).netloc == self.local else route.abort(),
        )
        page = context.new_page()
        errors = []
        page.on("pageerror", lambda error: errors.append(str(error)))
        self.addCleanup(lambda: self.assertEqual(errors, []))
        page.goto(self.url, wait_until="load")
        page.wait_for_function("()=>typeof ymdKey==='function'")
        page.wait_for_timeout(800)
        page.evaluate(MOCK, role)
        page.evaluate(SETUP)
        return page

    def calls(self, page):
        return page.evaluate("()=>window.__t.rpc.filter(x=>/^hq_direct_/.test(x[0]))")

    def alerts(self, page):
        return page.evaluate("()=>window.__t.alerts")

    def direct_page(self):
        page = self.open_app("hq_worker")
        page.evaluate("()=>hqDirectPage()")
        page.wait_for_selector("#hqDItem option[value='']", state="attached")
        page.wait_for_function("()=>document.querySelectorAll('#hqDItem option').length>1")
        return page

    def fill_direct(self, page, **overrides):
        values = {"hqDQty": "10", "hqDPack": "10kg", "hqDSup": "JA水戸", "hqDOri": "茨城県", "hqDCoop": "", "hqDSpec": ""}
        values.update(overrides)
        page.select_option("#hqDItem", "キャベツ")
        for field, value in values.items():
            page.fill(f"#{field}", value)
        return page

    def via_page(self):
        page = self.open_app("admin")
        page.evaluate("()=>c83ViaPage()")
        page.wait_for_selector("#c83Item")
        page.wait_for_function("()=>document.querySelectorAll('#c83Item option').length>1")
        return page

    def fill_via(self, page, **overrides):
        values = {"c83Qty": "10", "c83Pack": "10kg", "c83Sup": "JA水戸", "c83Ori": "茨城県", "c83Coop": "", "c83Spec": ""}
        values.update(overrides)
        page.select_option("#c83Item", "キャベツ")
        for field, value in values.items():
            page.fill(f"#{field}", value)
        page.select_option("#c83Run", "0")
        page.select_option("#c83Day", "当日便")
        return page

    def test_container_is_a_choice_in_both_forms(self):
        for open_page, select in ((self.direct_page, "#hqDCont"), (self.via_page, "#c83Cont")):
            with self.subTest(select=select):
                page = open_page()
                options = page.eval_on_selector_all(f"{select} option", "els=>els.map(e=>e.textContent)")
                self.assertEqual(options[:3], ["ダンボール", "コンテナ", "網コンテナ"])
                self.assertEqual(len(options), len(set(options)))

    def test_container_counts_in_cases(self):
        page = self.direct_page()
        self.fill_direct(page)
        page.select_option("#hqDCont", "コンテナ")
        page.click("[data-seika-click-action=hqDoDirect]")
        page.wait_for_function("()=>window.__t.rpc.some(x=>x[0]==='hq_direct_inbound_v1400')")
        self.assertEqual(self.calls(page)[0][1]["p_container_type"], "コンテナ")
        self.assertNotIn("コンテナ", page.evaluate("()=>window.c83Hq.HQ_BIG_CONTAINERS"))

    def test_direct_form_has_optional_spec_and_required_marks(self):
        page = self.direct_page()
        labels = page.evaluate(
            "()=>Object.fromEntries(['hqDQty','hqDPack','hqDSup','hqDOri','hqDDate','hqDCoop','hqDSpec'].map(i=>[i,document.getElementById(i).previousElementSibling.textContent.trim()]))"
        )
        for field in ("hqDQty", "hqDPack", "hqDSup", "hqDOri", "hqDDate"):
            self.assertIn("必須", labels[field], field)
        for field in ("hqDCoop", "hqDSpec"):
            self.assertIn("任意", labels[field], field)

    def test_direct_requires_fields_that_ishioka_requires(self):
        cases = [
            ("hqDPack", "量目"),
            ("hqDSup", "仕入先"),
            ("hqDOri", "産地"),
            ("hqDDate", "入荷日"),
            ("hqDQty", "数量"),
        ]
        for field, word in cases:
            with self.subTest(field=field):
                page = self.direct_page()
                self.fill_direct(page)
                page.fill(f"#{field}", "")
                page.click("[data-seika-click-action=hqDoDirect]")
                self.assertEqual(self.calls(page), [])
                self.assertTrue(any(word in message for message in self.alerts(page)), self.alerts(page))
        page = self.direct_page()
        page.click("[data-seika-click-action=hqDoDirect]")
        self.assertEqual(self.calls(page), [])
        self.assertTrue(any("品目" in message for message in self.alerts(page)))

    def test_direct_pack_weight_not_required_for_large_containers(self):
        page = self.direct_page()
        self.fill_direct(page, hqDPack="")
        page.select_option("#hqDCont", "網コンテナ")
        self.assertEqual(page.evaluate("()=>document.getElementById('hqDPackMark').style.display"), "none")
        page.select_option("#hqDCont", "ダンボール")
        self.assertEqual(page.evaluate("()=>document.getElementById('hqDPackMark').style.display"), "")
        page.select_option("#hqDCont", "網コンテナ")
        page.click("[data-seika-click-action=hqDoDirect]")
        page.wait_for_function("()=>window.__t.rpc.some(x=>x[0]==='hq_direct_inbound_v1400')")
        self.assertEqual(self.calls(page)[0][1]["p_container_type"], "網コンテナ")

    def test_direct_saves_spec_only_when_entered(self):
        for spec, memo in (("3L", "規格：3L"), ("", None), ("  秀品 / 赤  ", "規格：秀品／赤")):
            with self.subTest(spec=spec):
                page = self.direct_page()
                self.fill_direct(page, hqDSpec=spec)
                page.click("[data-seika-click-action=hqDoDirect]")
                page.wait_for_function("()=>window.__t.rpc.some(x=>x[0]==='hq_direct_inbound_v1400')")
                args = self.calls(page)[0][1]
                self.assertEqual(args["p_memo"], memo)
                self.assertEqual(args["p_supplier"], "JA水戸")
                self.assertEqual(args["p_origin"], "茨城県")
                self.assertEqual(args["p_cooperative_name"], "")
                self.assertTrue(args["p_date"])

    def test_via_form_has_optional_spec_and_required_marks(self):
        page = self.via_page()
        labels = page.evaluate(
            "()=>Object.fromEntries(['c83Item','c83Pack','c83Sup','c83Ori','c83Coop','c83Spec'].map(i=>[i,document.getElementById(i).previousElementSibling.textContent.trim()]))"
        )
        for field in ("c83Item", "c83Pack", "c83Sup", "c83Ori"):
            self.assertIn("必須", labels[field], field)
        for field in ("c83Coop", "c83Spec"):
            self.assertIn("任意", labels[field], field)

    def test_via_requires_fields_that_ishioka_requires(self):
        for field, word in (("c83Pack", "量目"), ("c83Sup", "仕入先"), ("c83Ori", "産地"), ("c83Qty", "数量")):
            with self.subTest(field=field):
                page = self.via_page()
                self.fill_via(page)
                page.fill(f"#{field}", "")
                page.click("[data-seika-click-action=c83Save]")
                self.assertEqual(self.calls(page), [])
                self.assertTrue(any(word in message for message in self.alerts(page)), self.alerts(page))

    def test_via_pack_weight_not_required_for_large_containers(self):
        page = self.via_page()
        page.select_option("#c83Cont", "鉄コンテナ")
        self.fill_via(page, c83Pack="")
        self.assertEqual(page.evaluate("()=>document.getElementById('c83PackMark').style.display"), "none")
        page.click("[data-seika-click-action=c83Save]")
        page.wait_for_function("()=>window.__t.rpc.some(x=>x[0]==='hq_direct_via_ishioka_v1199c83')")
        args = self.calls(page)[0][1]
        self.assertEqual(args["p_container_type"], "鉄コンテナ")
        self.assertEqual(args["p_count"], 10)

    def test_via_saves_spec_only_when_entered(self):
        for spec, memo in (("3L", "規格：3L"), ("", None)):
            with self.subTest(spec=spec):
                page = self.via_page()
                self.fill_via(page, c83Spec=spec)
                page.click("[data-seika-click-action=c83Save]")
                page.wait_for_function("()=>window.__t.rpc.some(x=>x[0]==='hq_direct_via_ishioka_v1199c83')")
                self.assertEqual(self.calls(page)[0][1]["p_memo"], memo)

    def test_spec_is_shown_on_lot_card(self):
        page = self.open_app("hq_worker")
        html = page.evaluate(
            "(l)=>window.c83Hq.hqLotCard(l,false)",
            {**SHEET_LOT, "memo": "規格：3L / 取消（架空）：入力の間違い"},
        )
        self.assertIn("規格", html)
        self.assertIn("3L", html)
        self.assertNotIn("取消", html)
        for memo in (None, "石岡で出庫が取り消されました（本社は確定済み）"):
            html = page.evaluate("(l)=>window.c83Hq.hqLotCard(l,false)", {**SHEET_LOT, "memo": memo})
            self.assertNotIn("<span>規格</span>", html)

    def sheet(self, page, **overrides):
        html = page.evaluate("([l,p])=>window.c83Hq.hqSheetHtml(l,p)", [{**SHEET_LOT, **overrides}, SHEET_PAGES])
        view = page.context.new_page()
        view.set_viewport_size({"width": 1123, "height": 794})
        view.emulate_media(media="print")
        view.set_content(html)
        return view.evaluate(NATURAL_HEIGHT)[0]

    def test_via_sheet_omits_cooperative_when_supplier_exists(self):
        page = self.open_app("hq_worker")
        both = self.sheet(page)
        self.assertIn("仕入先", both["text"])
        self.assertIn("JA水戸", both["text"])
        self.assertNotIn("単協名", both["text"])
        self.assertEqual(both["rows"], 7)
        self.assertLessEqual(both["natural"], both["available"] * 0.85)

    def test_via_sheet_keeps_cooperative_without_supplier(self):
        page = self.open_app("hq_worker")
        only_coop = self.sheet(page, supplier="")
        self.assertIn("単協名", only_coop["text"])
        self.assertEqual(only_coop["rows"], 8)

    def test_other_sheets_are_unchanged(self):
        page = self.open_app("hq_worker")
        direct = self.sheet(page, via_ishioka=False)
        self.assertIn("単協名", direct["text"])
        self.assertEqual(direct["rows"], 8)
        from_ishioka = self.sheet(page, source_kind="石岡から", via_ishioka=False)
        self.assertNotIn("単協名", from_ishioka["text"])

    def test_sheet_prints_spec_next_to_item_name_without_new_row(self):
        page = self.open_app("hq_worker")
        plain = self.sheet(page)
        with_spec = self.sheet(page, memo="規格：3L")
        self.assertEqual(with_spec["rows"], plain["rows"])
        self.assertEqual(with_spec["name"], "長葱3L")
        self.assertEqual(plain["name"], "長葱")
        self.assertEqual(with_spec["nameRowHeight"], plain["nameRowHeight"])
        self.assertLessEqual(with_spec["natural"], with_spec["available"])

    def test_sheet_with_longest_spec_still_fits(self):
        page = self.open_app("hq_worker")
        longest = self.sheet(page, item_name="ミニトマト（アイコ）", memo="規格：" + "秀品3L赤" * 5)
        self.assertLessEqual(longest["natural"], longest["available"])

    def test_sheet_ignores_other_memo_text(self):
        page = self.open_app("hq_worker")
        self.assertEqual(self.sheet(page, memo="取消（架空）：入力の間違い")["name"], "長葱")

    def test_guides_describe_required_and_optional_fields(self):
        page = self.open_app("admin")
        text = json.dumps(
            page.evaluate("()=>[V198_GUIDE_SECTIONS.c83Via,Object.values(V195_ROLE_GUIDES.hq_receiver.sections).filter(s=>s.title.includes('直接届いた'))]"),
            ensure_ascii=False,
        )
        self.assertIn("必須", text)
        self.assertIn("規格", text)
        self.assertIn("品名の隣", text)
        self.assertIn("単協名", text)
        self.assertIn("コンテナ", text)


if __name__ == "__main__":
    unittest.main()
