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

SETUP = """()=>{
 window.__alerts=[];window.alert=m=>window.__alerts.push(String(m));window.confirm=()=>true;
 window.save=()=>{window.__saves=(window.__saves||0)+1};
}"""

SNAPSHOT = """()=>{
 const names=['キャベツ','人参','人参（国産）','国産人参','白菜','カット大根','葉付き大根','じゃが芋','男爵じゃが芋','とうや','さやか','シャドークイーン','玉葱','玉ねぎ','小松菜','小葱','レタス','リーフ','サニー','ロメイン'];
 const qr={};names.forEach(n=>{const c=v1144AutoPurchaseStaffForItemName(n);qr[n]=c?c.legacy_user_id:null});
 const items={};db.items.filter(i=>i.deleted!==true).forEach(i=>{items[i.name]=assignedBuyerIds(i.id).sort()});
 return{qr,items,assign:JSON.parse(JSON.stringify(db.buyerAssignments)),staff:JSON.parse(JSON.stringify(db.purchaseStaffByItem||{}))}
}"""


class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, *_args):
        pass


class BuyerAssignTests(unittest.TestCase):
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
        context = self.browser.new_context(viewport={"width": 820, "height": 1180}, service_workers="block", timezone_id="Asia/Tokyo")
        self.addCleanup(context.close)
        context.route("**/*", lambda r: r.continue_() if urlparse(r.request.url).netloc == self.local else r.abort())
        page = context.new_page()
        errors = []
        page.on("pageerror", lambda e: errors.append(str(e)))
        self.addCleanup(lambda: self.assertEqual(errors, []))
        page.goto(self.url, wait_until="load")
        page.wait_for_function("()=>typeof ymdKey==='function'&&typeof c110Handover==='function'")
        page.wait_for_timeout(800)
        page.evaluate(MOCK, role)
        page.evaluate(SETUP)
        return page

    def select(self, page, element_id, value):
        page.evaluate("()=>{const d=document.querySelector('#c110Panel details');if(d)d.open=true}")
        page.select_option(f"#{element_id}", value)

    def test_panel_is_shown_on_items_page_for_admin_and_worker(self):
        for role in ("admin", "worker"):
            page = self.open_app(role)
            page.evaluate("()=>itemsPage()")
            self.assertEqual(page.locator("#c110Panel").count(), 1, role)
            self.assertIn("担当者ごとにまとめて交代", page.locator("#c110Panel").inner_text())

    def test_other_roles_cannot_open_items_page(self):
        page = self.open_app("buyer")
        page.evaluate("()=>itemsPage()")
        self.assertEqual(page.locator("#c110Panel").count(), 0)
        self.assertTrue(any("品目設定は管理者・青果社員のみです" in m for m in page.evaluate("()=>window.__alerts")))

    def test_handover_moves_normal_and_qr_items_and_keeps_others(self):
        page = self.open_app("admin")
        before = page.evaluate(SNAPSHOT)
        moved_normal = [n for n, ids in before["items"].items() if ids == ["saito_dai"]]
        moved_qr = [n for n, c in before["qr"].items() if c == "saito_dai"]
        self.assertTrue(moved_normal and moved_qr, (moved_normal, moved_qr))
        page.evaluate("()=>itemsPage()")
        self.select(page, "c110From", "saito_dai")
        self.assertIn("斎藤", page.locator("#c110Preview").inner_text())
        self.select(page, "c110To", "yoshida")
        page.evaluate("()=>c110Handover()")
        after = page.evaluate(SNAPSHOT)
        for name in moved_normal:
            self.assertEqual(after["items"][name], ["yoshida"], name)
        for name in moved_qr:
            self.assertEqual(after["qr"][name], "yoshida", name)
        for name, ids in before["items"].items():
            if name not in moved_normal:
                self.assertEqual(after["items"][name], ids, name)
        for name, c in before["qr"].items():
            if name not in moved_qr:
                self.assertEqual(after["qr"][name], c, name)
        self.assertEqual(page.evaluate("()=>window.__saves"), 1)
        self.assertIn("交代しました", page.locator(".ok.flash").inner_text())

    def test_handover_covers_every_potato_name(self):
        page = self.open_app("admin")
        page.evaluate("()=>itemsPage()")
        self.select(page, "c110From", "seki_hiroshi")
        self.select(page, "c110To", "araki")
        page.evaluate("()=>c110Handover()")
        got = page.evaluate("()=>['じゃが芋','ジャガイモ','男爵','男爵じゃが芋','メークイン','とうや','インカのめざめ','北海黄金','キタアカリ','さやか','シャドークイーン','玉葱','玉ねぎ'].map(n=>[n,(v1144AutoPurchaseStaffForItemName(n)||{}).legacy_user_id])")
        for name, staff in got:
            self.assertEqual(staff, "araki", name)

    def test_handover_to_same_person_or_missing_choice_changes_nothing(self):
        page = self.open_app("admin")
        before = page.evaluate(SNAPSHOT)
        page.evaluate("()=>itemsPage()")
        page.evaluate("()=>c110Handover()")
        self.select(page, "c110From", "saito_dai")
        self.select(page, "c110To", "saito_dai")
        page.evaluate("()=>c110Handover()")
        self.assertEqual(page.evaluate(SNAPSHOT), before)
        self.assertFalse(page.evaluate("()=>window.__saves||0"))

    def test_handover_from_stopped_buyer_is_possible_and_cleans_old_assignment(self):
        page = self.open_app("admin")
        page.evaluate("()=>{db.users.find(u=>u.id==='araki').active=false}")
        page.evaluate("()=>itemsPage()")
        options = page.locator("#c110From option").all_inner_texts()
        self.assertTrue(any("荒木" in o and "利用停止" in o for o in options), options)
        self.assertFalse(any("荒木" in o for o in page.locator("#c110To option").all_inner_texts()))
        self.select(page, "c110From", "araki")
        self.select(page, "c110To", "yoshida")
        page.evaluate("()=>c110Handover()")
        after = page.evaluate(SNAPSHOT)
        self.assertEqual(after["qr"]["人参"], "yoshida")
        self.assertEqual(after["qr"]["人参（国産）"], "yoshida")
        self.assertFalse([k for k, v in after["assign"].items() if k == "araki" and v])

    def test_change_one_normal_item_also_follows_in_qr(self):
        page = self.open_app("worker")
        before = page.evaluate(SNAPSHOT)
        item = page.evaluate("()=>db.items.find(i=>i.name==='白菜')?.id")
        self.assertTrue(item)
        page.evaluate("()=>itemsPage()")
        sel = f"c110Sel_n_{item}"
        self.select(page, sel, "sakamoto")
        page.evaluate("([k])=>c110ChangeItem('n',k)", [item])
        after = page.evaluate(SNAPSHOT)
        self.assertEqual(before["items"]["白菜"], ["yoshida"])
        self.assertEqual(after["items"]["白菜"], ["sakamoto"])
        self.assertEqual(after["qr"]["白菜"], "sakamoto")
        self.assertEqual(after["qr"]["レタス"], before["qr"]["レタス"])
        self.assertEqual(after["items"]["レタス"], before["items"]["レタス"])
        self.assertEqual(after["qr"]["キャベツ"], before["qr"]["キャベツ"])

    def test_change_one_qr_only_item(self):
        page = self.open_app("admin")
        page.evaluate("()=>itemsPage()")
        idx = page.evaluate("()=>qrManagedItemList().findIndex(r=>r.name==='カット大根')")
        self.assertGreaterEqual(idx, 0)
        self.select(page, f"c110Sel_q_{idx}", "yoshida")
        page.evaluate("([k])=>c110ChangeItem('q',k)", [idx])
        got = page.evaluate("()=>v1144AutoPurchaseStaffForItemName('カット大根').legacy_user_id")
        self.assertEqual(got, "yoshida")
        self.assertEqual(page.evaluate("()=>db.purchaseStaffByItem['カット大根']"), page.evaluate("()=>v1144AutoPurchaseStaffForItemName('カット大根').display_name"))
        self.assertEqual(page.evaluate("()=>v1144AutoPurchaseStaffForItemName('葉付き大根').legacy_user_id"), "saito_dai")

    def test_keep_option_does_not_change_anything(self):
        page = self.open_app("admin")
        page.evaluate("()=>{db.users.find(u=>u.id==='yoshida').active=false}")
        before = page.evaluate(SNAPSHOT)
        item = page.evaluate("()=>db.items.find(i=>i.name==='白菜').id")
        page.evaluate("()=>itemsPage()")
        self.assertEqual(page.locator(f"#c110Sel_n_{item}").input_value(), "__keep__")
        page.evaluate("([k])=>c110ChangeItem('n',k)", [item])
        self.assertEqual(page.evaluate(SNAPSHOT), before)

    def test_worker_can_send_buyer_assignments_but_other_roles_cannot(self):
        page = self.open_app("worker")
        got = page.evaluate("""()=>{
          const p={buyerAssignments:{a:['x']},items:[],purchaseStaffByItem:{}};
          const has=r=>Object.prototype.hasOwnProperty.call(v188RolePayload(p,r),'buyerAssignments');
          return {admin:has('admin'),worker:has('worker'),buyer:has('buyer'),clerk:has('clerk'),sales:has('sales'),
                  workerValue:v188RolePayload(p,'worker').buyerAssignments}}""")
        self.assertTrue(got["admin"] and got["worker"])
        self.assertFalse(got["buyer"] or got["clerk"] or got["sales"])
        self.assertEqual(got["workerValue"], {"a": ["x"]})

    def test_operation_guide_has_new_section_for_admin_and_worker_only(self):
        page = self.open_app("admin")
        got = page.evaluate("()=>Object.fromEntries(Object.entries(V195_ROLE_GUIDES).map(([r,g])=>[r,(g.sections||[]).filter(s=>s.title==='仕入れ担当者を変更する').length]))")
        self.assertEqual(got["admin"], 1)
        self.assertEqual(got["worker"], 1)
        self.assertFalse([r for r, n in got.items() if n and r not in ("admin", "worker")])


if __name__ == "__main__":
    unittest.main()
