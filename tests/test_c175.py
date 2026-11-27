"""c168：アカウント別の利用状況。見られる人だけメニューにボタンが出て、画面に最後に使った日・画面・操作の件数が出る。"""
import functools, threading, unittest
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
MOCK = (ROOT / 'tests' / 'mock_hq.js').read_text(encoding='utf-8')
class C175Tests(unittest.TestCase):
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
        page.wait_for_function("()=>typeof c175LettucePage==='function'&&typeof hqMakePdf==='function'")
        page.wait_for_timeout(500)
        page.evaluate(MOCK, role)
        self.addCleanup(ctx.close)
        self.addCleanup(lambda: self.assertEqual(errs, []))
        return page

    def test_hq_sheet_rows_line_up(self):
        # ①本社移動用の貼り紙：「ロット合計」の行だけ線がずれていた（アプリの .total の見た目が混ざっていた）
        page = self.open_app()
        rows = page.evaluate("""async()=>{let geo=null;const H=window.html2canvas;window.html2canvas=async(el,o)=>{geo=geo||[...el.querySelectorAll('tr')].map(tr=>[...tr.children].map(c=>{const b=c.getBoundingClientRect();return [Math.round(b.top),Math.round(b.bottom)]}));return document.createElement('canvas')};
          const J=window.jspdf.jsPDF;window.jspdf.jsPDF=function(){return {addPage(){},addImage(){},output(){return new Blob()},save(){}}};
          try{await hqMakePdf({item_name:'白菜',unit:'kg',source_kind:'石岡から',hq_received_date:'2026-11-26',received_qty:2018,qr_key:'X',lot_no:'H1',supplier:'黒岩農事',origin:'群馬県産',ishioka_received_date:'2026-11-25',source_lot_no:'L1',status:'入荷済み'},[{qty:'1基 288.3 kg',label:'1 / 7 基目',note:'（7基）'}])}catch(e){}
          window.jspdf.jsPDF=J;window.html2canvas=H;return geo}""")
        self.assertGreaterEqual(len(rows), 5)
        for th, td in rows:
            self.assertEqual(th, td)

    def test_lettuce_variance_page_and_excel(self):
        page = self.open_app("buyer")
        page.evaluate("""()=>{window.__q=[];const imps=[{id:'I1',delivery_date:'2026-11-27'},{id:'I2',delivery_date:'2026-11-28'}];
          const lines=[
            {delivery_date:'2026-11-27',customer_name:'プライムデリカ 龍ヶ崎工場',item_name:'レタス',qty_raw:'8k 61',boxes:61,pack_kg:8,kg:403},
            {delivery_date:'2026-11-27',customer_name:'プライムデリカ 相模原第二工場',item_name:'レタス',qty_raw:'8k 24',boxes:24,pack_kg:8,kg:160},
            {delivery_date:'2026-11-28',customer_name:'プライムデリカ 相模原第二工場',item_name:'レタス',qty_raw:'8k 20',boxes:20,pack_kg:8,kg:170},
            {delivery_date:'2026-11-28',customer_name:'(株)日本デリカサービス八千代工場',item_name:'レタス',qty_raw:'8k80(556k) 8k10(75k)',boxes:90,pack_kg:8,kg:631},
            {delivery_date:'2026-11-28',customer_name:'美野里デリカ',item_name:'レタス',qty_raw:'8k 6',boxes:6,pack_kg:8,kg:48}];
          const plan=[{delivery_date:'2026-11-27',customer_name:'プライムデリカ 龍ヶ崎工場',item_name:'レタス',boxes:50,pack_kg:8,kg:400,cases:50},
            {delivery_date:'2026-11-27',customer_name:'プライムデリカ 相模原第二工場',item_name:'レタス',boxes:20,pack_kg:8,kg:160,cases:20},
            {delivery_date:'2026-11-28',customer_name:'プライムデリカ 相模原第二工場',item_name:'レタス',boxes:20,pack_kg:8,kg:160,cases:20}];
          qrSelect=async(t,q)=>{__q.push([t,q]);if(t==='ship_actual_imports_v1199c142'||t==='ship_plan_imports_v1199c140')return imps;if(t==='ship_actual_lines_v1199c142')return lines;if(t==='ship_plan_lines_v1199c140')return plan;return []};
          window.__wb=[];XLSX.writeFile=(wb,name)=>__wb.push({name,sheets:wb.SheetNames.map(n=>({n,rows:XLSX.utils.sheet_to_json(wb.Sheets[n],{header:1,defval:''})}))})}""")
        page.evaluate("()=>c175LettucePage('2026-11-01','2026-11-30')")
        page.get_by_text("客先ごとの合計").wait_for()
        text = page.inner_text("#app")
        self.assertNotIn("美野里", text)  # 重さを出していない客先は入れない
        self.assertIn("日ごと（4件）", text)
        self.assertIn("400kg（50）", text)  # 予定（積み込み表）
        r = page.evaluate("()=>c175Lib.c175Calc({delivery_date:'d',customer_name:'c',item_name:'レタス',boxes:61,pack_kg:8,kg:403})")
        self.assertEqual((r["need"], r["needCeil"], r["diffCases"], r["diffKg"], r["avg"]), (50.4, 51, 10.6, 85, 6.6))
        r = page.evaluate("()=>c175Lib.c175Calc({delivery_date:'d',customer_name:'c',item_name:'レタス',boxes:61,pack_kg:8,kg:403},{kg:400,cases:50})")
        self.assertEqual((r["planKg"], r["planCases"], r["vsPlanCases"], r["vsPlanKg"]), (400, 50, 11, 3))  # 予定400kg＝50ケースのところ61ケース（＋11）
        q = page.evaluate("()=>__q.map(x=>x[1]).join('|')")
        self.assertIn("status=eq.active", q); self.assertIn("item_name=eq.", q)
        page.locator("button", has_text="Excelで出力").click()
        page.wait_for_function("()=>__wb.length===1")
        wb = page.evaluate("()=>__wb[0]")
        self.assertEqual([x["n"] for x in wb["sheets"]], ["客先ごと", "日ごと"])
        by = {row[0]: row for row in wb["sheets"][0]["rows"][3:]}
        sag = by["プライムデリカ 相模原第二工場"]
        # 日数・予定320kg・予定40ケース・使った44・量った330kg・予定より+4ケース・+10kg・本来41.3・多く2.8・差22kg・平均7.5kg
        self.assertEqual(sag[1:12], [2, 320, 40, 44, 330, 4, 10, 41.3, 2.8, 22, 7.5])
        self.assertEqual(by["(株)日本デリカサービス八千代工場"][2], "")  # 予定がない客先は空  # 2日・44ケース・330kg・本来41.3ケース・2.8ケース多い・22kg
        self.assertEqual(len(wb["sheets"][1]["rows"]) - 3, 4)
        self.assertIn("2026-11-01_2026-11-30", wb["name"])

    def test_entry_on_gap_page_and_permissions(self):
        page = self.open_app("admin")
        page.evaluate("()=>{qrSelect=async()=>[];c153GapPage('2026-11-28')}")
        page.locator("#c175Btn").wait_for()
        clerk = self.open_app("clerk")
        clerk.evaluate("()=>{window.__al=[];window.alert=m=>__al.push(m);c175LettucePage()}")
        self.assertIn("使えます", clerk.evaluate("()=>__al.join()"))


if __name__ == '__main__':
    unittest.main()
