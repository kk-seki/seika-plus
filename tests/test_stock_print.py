import functools
import re
import threading
import unittest
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

from playwright.sync_api import sync_playwright

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
MOCK = (HERE / "mock_hq.js").read_text(encoding="utf-8")

SEED = """([extraItems, extraSpecial])=>{
 const today=new Date(),iso=today.toISOString();
 db.records=[];db.specialRecords=[];
 const add=(it,cases)=>{db.records.push({id:'r_'+it.id,itemId:it.id,createdAt:iso,user:'テスト',total:cases*Number(it.pack||10),lines:[{pack:Number(it.pack||10),cases}]})};
 const room3=db.items.slice(0,6);room3.forEach(it=>{it.room='room3';it.active=true});
 add(room3[0],5);add(room3[1],0);add(room3[2],3);
 window.__room3=room3.map(it=>it.name);
 for(let i=0;i<extraItems;i++){
  const it={id:'x'+i,name:'追加品目'+i+(i%5===0?'（長い名前の品目でも折り返して収まる確認用）':''),pack:10,sort:100+i,active:true,useSpec:false,room:'room3'};
  db.items.push(it);add(it,i+1)}
 for(let i=0;i<extraSpecial;i++){
  const sp={id:'sx'+i,name:'その他品目'+i,unit:'ケース',sort:200+i,active:true};
  db.specialItems.exchange.push(sp);
  db.specialRecords.push({id:'sr'+i,tableId:'exchange',itemId:sp.id,createdAt:iso,qty:i%4===0?0:i+1,user:'テスト'})}
}"""


class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, *_args):
        pass


class StockPrintTests(unittest.TestCase):
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

    def open_app(self, extra_items=0, extra_special=0):
        context = self.browser.new_context(viewport={"width": 820, "height": 1180}, service_workers="block", timezone_id="Asia/Tokyo")
        self.addCleanup(context.close)
        context.route("**/*", lambda r: r.continue_() if urlparse(r.request.url).netloc == self.local else r.abort())
        page = context.new_page()
        errors = []
        page.on("pageerror", lambda e: errors.append(str(e)))
        self.addCleanup(lambda: self.assertEqual(errors, []))
        page.goto(self.url, wait_until="load")
        page.wait_for_function("()=>typeof ymdKey==='function'&&typeof c107StockPrintHtml==='function'")
        page.wait_for_timeout(800)
        page.evaluate(MOCK, "admin")
        page.evaluate(SEED, [extra_items, extra_special])
        return context, page

    def build(self, page, qr):
        return page.evaluate("([g,qr])=>{const b=c107StockPrintHtml(g,qr);return{html:b.html,rows:b.rows.map(r=>({kind:r.kind,name:r.name,qrKg:r.qrKg||null})),scale:b.scale}}", ["room3", qr])

    def render(self, context, html):
        view = context.new_page()
        view.set_viewport_size({"width": 1200, "height": 900})
        view.set_content(html)
        view.emulate_media(media="print")
        return view

    def metrics(self, view):
        return view.evaluate("""()=>{
          const page=document.querySelector('.page').getBoundingClientRect(),c=document.querySelector('.pageContent').getBoundingClientRect();
          const clipped=[...document.querySelectorAll('td,th')].filter(e=>e.scrollWidth>e.clientWidth+1||e.scrollHeight>e.clientHeight+1).map(e=>e.textContent.trim().slice(0,30));
          const lines=[...document.querySelectorAll('td.day')].filter(e=>e.getBoundingClientRect().height>0&&e.textContent.length>0&&e.getBoundingClientRect().width<8).length;
          return{pageBottom:page.bottom,contentBottom:c.bottom,pageRight:page.right,contentRight:c.right,clipped,blocks:document.querySelectorAll('table.blk').length,narrow:lines}}""")

    def pdf_pages(self, view):
        data = view.pdf(prefer_css_page_size=True, print_background=True)
        return len(re.findall(rb"/Type\s*/Page(?!s)", data))

    def test_only_rows_with_stock_are_listed_and_zero_stock_is_hidden(self):
        context, page = self.open_app()
        built = self.build(page, {"totals": {}, "standaloneTotals": {}, "unconvertible": []})
        names = [r["name"] for r in built["rows"] if r["kind"] != "special"]
        room3 = page.evaluate("()=>window.__room3")
        self.assertIn(room3[0], names)
        self.assertIn(room3[2], names)
        self.assertNotIn(room3[1], names)
        self.assertNotIn(room3[3], names)

    def test_qr_stock_is_added_in_kg_in_todays_column(self):
        context, page = self.open_app()
        item_id = page.evaluate("()=>db.items[3].id")
        item_name = page.evaluate("()=>db.items[3].name")
        qr = {"totals": {item_id: 1250.5}, "standaloneTotals": {"k": {"name": "QR専用品目", "total": 80}}, "unconvertible": [{"x": 1}, {"x": 2}]}
        built = self.build(page, qr)
        qr_rows = {r["name"]: r["qrKg"] for r in built["rows"] if r["kind"] == "qr"}
        self.assertEqual(qr_rows, {f"{item_name}（QR）": 1250.5, "QR専用品目（QR）": 80})
        view = self.render(context, built["html"])
        today = page.evaluate("()=>ymdKey(new Date())")
        texts = view.evaluate("()=>[...document.querySelectorAll('tr.qr')].map(tr=>[...tr.children].map(td=>td.textContent))")
        self.assertEqual(len(texts), 2)
        for row in texts:
            self.assertEqual(row[1], "kg")
            filled = [c for c in row[3:] if c]
            self.assertEqual(len(filled), 1)
        self.assertTrue(any("1,250.5" in "".join(r) or "1250.5" in "".join(r) for r in texts))
        self.assertIn("kg換算できないQRロットが2件", built["html"])
        self.assertTrue(today)

    def test_two_blocks_and_every_row_appears_exactly_once(self):
        context, page = self.open_app(extra_items=40, extra_special=10)
        built = self.build(page, {"totals": {}, "standaloneTotals": {}, "unconvertible": []})
        view = self.render(context, built["html"])
        shown = view.evaluate("()=>[...document.querySelectorAll('tr.data td.name')].map(td=>td.textContent)")
        self.assertEqual(sorted(shown), sorted(r["name"] for r in built["rows"]))
        self.assertEqual(self.metrics(view)["blocks"], 2)

    def test_dense_table_fits_one_a4_page_without_clipping(self):
        context, page = self.open_app(extra_items=70, extra_special=30)
        qr_totals = {f"x{i}": 100 + i * 7.5 for i in range(0, 70, 2)}
        built = self.build(page, {"totals": qr_totals, "standaloneTotals": {"k": {"name": "QR専用", "total": 12}}, "unconvertible": []})
        self.assertGreater(len(built["rows"]), 100)
        view = self.render(context, built["html"])
        m = self.metrics(view)
        self.assertLessEqual(m["contentBottom"], m["pageBottom"] + 1)
        self.assertLessEqual(m["contentRight"], m["pageRight"] + 1)
        self.assertEqual(m["clipped"], [])
        self.assertEqual(self.pdf_pages(view), 1)

    def test_normal_amount_fits_one_page_and_numbers_are_not_cut(self):
        context, page = self.open_app(extra_items=25, extra_special=5)
        built = self.build(page, {"totals": {"x1": 12345.5, "x3": 9876.5}, "standaloneTotals": {}, "unconvertible": []})
        view = self.render(context, built["html"])
        m = self.metrics(view)
        self.assertEqual(m["clipped"], [])
        self.assertEqual(self.pdf_pages(view), 1)
        self.assertGreaterEqual(built["scale"], .9)

    def test_empty_stock_still_prints_a_valid_single_page(self):
        context, page = self.open_app()
        page.evaluate("()=>{db.records=[];db.specialRecords=[]}")
        built = self.build(page, {"totals": {}, "standaloneTotals": {}, "unconvertible": []})
        self.assertEqual(built["rows"], [])
        view = self.render(context, built["html"])
        self.assertEqual(self.pdf_pages(view), 1)

    def test_print_button_blocks_printing_when_qr_stock_cannot_be_read(self):
        context, page = self.open_app()
        out = page.evaluate("""async()=>{const alerts=[];let opened=0;window.alert=m=>alerts.push(String(m));window.open=()=>{opened++;return null};
          qrInventoryKgByItemForRoom=async()=>{throw new Error('通信に失敗しました')};await printInventorySheet('room3');return{alerts,opened}}""")
        self.assertEqual(out["opened"], 0)
        self.assertEqual(len(out["alerts"]), 1)
        self.assertIn("QR在庫を取得できない", out["alerts"][0])

    def test_print_button_writes_the_new_layout_to_the_print_window(self):
        context, page = self.open_app()
        html = page.evaluate("""async()=>{let written='';window.alert=()=>{};
          window.open=()=>({document:{open(){},write(h){written+=h},close(){}}});
          qrInventoryKgByItemForRoom=async()=>({totals:{},standaloneTotals:{},unconvertible:[]});await printInventorySheet('room3');return written}""")
        self.assertIn('class="blocks"', html)
        self.assertEqual(html.count('<table class="blk">'), 2)

    def test_home_has_no_entered_or_last_input_tiles_and_counts_include_qr(self):
        context, page = self.open_app()
        page.evaluate("""()=>{db.settings={};db.items.slice(0,2).forEach((it,i)=>{db.settings[it.id]={min:40,max:96}});db.records=[];
          window.__qrKg=0;v1115LineInventoryRows=async()=>db.items.slice(0,2).map(item=>({item,normalKg:0,qrKg:window.__qrKg,unconvertible:false}));
          v1146LoadQrStock=async()=>{v1146QrStockByItem={};db.items.slice(0,2).forEach(it=>{v1146QrStockByItem[String(it.id)]={qrKg:window.__qrKg,unconvertible:false}})}}""")
        def tiles(kg):
            page.evaluate("(kg)=>{window.__qrKg=kg}", kg)
            page.evaluate("async()=>{await v1146LoadQrStock();home()}")
            page.wait_for_timeout(200)
            return page.evaluate("()=>[...document.querySelectorAll('.homeSummary .summaryBox')].map(b=>[b.querySelector('.summaryLabel').textContent,b.querySelector('.summaryValue').textContent])")
        shortage = dict(tiles(0))
        self.assertEqual(list(shortage), ["発注候補", "過多品目"])
        self.assertEqual(shortage["発注候補"], "2")
        self.assertEqual(shortage["過多品目"], "0")
        enough = dict(tiles(60))
        self.assertEqual((enough["発注候補"], enough["過多品目"]), ("0", "0"))
        excess = dict(tiles(200))
        self.assertEqual((excess["発注候補"], excess["過多品目"]), ("0", "2"))
        body = page.evaluate("()=>document.body.innerText")
        self.assertNotIn("本日入力済み", page.evaluate("()=>document.querySelector('.homeSummary').innerText"))
        self.assertNotIn("最終入力", page.evaluate("()=>document.querySelector('.homeSummary').innerText"))
        self.assertTrue(body)

    def test_operation_guide_explains_the_new_print_and_old_home_tiles_are_gone(self):
        context, page = self.open_app()
        out = page.evaluate("""()=>Object.fromEntries(['admin','worker','buyer','sales','clerk','viewer','office_viewer'].map(r=>[r,V195_ROLE_GUIDES[r].sections.filter(s=>s.title==='在庫表を印刷する').length]))""")
        self.assertEqual(set(out.values()), {1})
        text = page.evaluate("()=>JSON.stringify(V195_ROLE_GUIDES)")
        self.assertNotIn("本日入力済み件数", text)


if __name__ == "__main__":
    unittest.main()
