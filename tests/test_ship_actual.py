"""c142：産地報告書からの確定数量の取り込み（読み取り・客先の読み替え・登録・予定との比較）を、架空の産地報告書で確認する。"""
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

# 架空の産地報告書：1行目に納品日、客先名は表の2行上、「品目・産地・単協名・cs」の表が左右に並ぶ
BOOK = """(date)=>{
 const serial=d=>Math.round((new Date(d+'T00:00:00Z')-new Date('1899-12-30T00:00:00Z'))/864e5);
 const a=XLSX.utils.aoa_to_sheet([
  ['産地報告',null,null],
  [],
  [],
  ['架空デリカ　龍ケ崎工場',null,null,null,null,'架空フーズ'],
  [],
  ['品目','産地','単協名','cs',null,'品目','産地','cs'],
  ['キャベツ','茨城','架空農協(JGAP)','10ｋ',null,'人参','北海道','15ｋ13　5ｋ1'],
  [null,null,null,12],
  ['レタス','茨城','架空(JGAP)','8ｋ58',null,'胡瓜　BM','宮崎','15ｋ2'],
  ['水菜','茨城',null,'5ｋ'],
  ['大葉','愛知',null,'3ｋ1',null,'小松菜','茨城','7ｋ1　3ｋ1'],
  [null,null,null,null,null,null,null,'10ｋ1'],
 ]);
 a['C1']={t:'n',v:serial(date)};
 const b=XLSX.utils.aoa_to_sheet([['産地報告',null,null,null,null],[],[],['重量'],[],['納品先',null,'単協',null,'kg'],['龍ヶ崎',null,'架空',null,403],[],[],[],
  ['架空青果　第二工場'],[],['品目','産地','cs'],['レタス','茨城','8ｋ193(1191ｋ)'],['白菜','長野','15ｋ1あ']]);
 b['E1']={t:'n',v:serial(date)};
 const c=XLSX.utils.aoa_to_sheet([[null],[],['品目']]);
 return {SheetNames:['シート1','シート2','計算用'],Sheets:{'シート1':a,'シート2':b,'計算用':c}};
}"""

MASTERS = """{alias:new Map([['大根',{item_name:'カット大根',in_master:true}]]),std:new Map([['キャベツ',10],['人参',15]]),aliasRows:[],stdRows:[]}"""


class ShipActualBrowserTests(unittest.TestCase):
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

    def open_app(self, role="clerk"):
        context = self.browser.new_context(viewport={"width": 820, "height": 1180}, service_workers="block", timezone_id="Asia/Tokyo")
        self.addCleanup(context.close)
        context.route("**/*", lambda route: route.continue_() if urlparse(route.request.url).netloc == self.local else route.abort())
        page = context.new_page()
        errors = []
        page.on("pageerror", lambda error: errors.append(str(error)))
        self.addCleanup(lambda: self.assertEqual(errors, []))
        page.goto(self.url, wait_until="load")
        page.wait_for_function("()=>typeof c142Prepare==='function'&&typeof XLSX!=='undefined'")
        page.wait_for_timeout(500)
        page.evaluate(MOCK, role)
        page.evaluate("""()=>{const T=window.__T;for(const t of ['ship_plan_imports_v1199c140','ship_plan_lines_v1199c140','ship_plan_item_aliases_v1199c140','ship_plan_case_std_v1199c140','ship_actual_imports_v1199c142','ship_actual_lines_v1199c142','ship_customer_aliases_v1199c142'])T[t]=T[t]||[];
          T.ship_plan_case_std_v1199c140=[{item_name:'キャベツ',case_kg:10},{item_name:'人参',case_kg:15}];
          window.qrAllowedItemNames=()=>['キャベツ','人参','レタス','胡瓜','大葉','小松菜','白菜'];
          window.__rpc=[];callRpc=async(n,a)=>{window.__rpc.push([n,JSON.parse(JSON.stringify(a||{}))]);return n==='replace_ship_actual_v1199c142'?{ok:true,count:a.p_lines.length,replaced:false}:{ok:true}}}""")
        return page

    def test_quantity_writing(self):
        page = self.open_app()
        out = page.evaluate("""()=>{const q=c142Parse.parseReportQty;return ['10ｋ 6','15ｋ26 10ｋ1','15ｋ13　5ｋ1','8ｋ193(1191ｋ)','5k1','15ｋ','','403','15ｋ1あ'].map(s=>q(s))}""")
        self.assertEqual([o and o.get("kg") for o in out[:5]], [60, 400, 200, 1191, 5])
        self.assertEqual([o and o.get("boxes") for o in out[:5]], [6, 27, 14, 193, 1])
        self.assertEqual(out[0]["pack"], 10)
        self.assertIsNone(out[1]["pack"])            # 箱の重さが混ざると1つに決めない
        self.assertIsNone(out[5])                    # 規格だけ＝出していない
        self.assertIsNone(out[6])
        self.assertTrue(out[7]["bad"])               # 規格のない数だけ＝読めない
        self.assertTrue(out[8]["bad"])

    def test_reads_blocks_titles_and_skips_weight_table(self):
        page = self.open_app()
        r = page.evaluate(f"""()=>{{const rep=c142Parse.readReport(({BOOK})('2026-11-23'),'産地報告.xlsx');
          return {{dates:[...rep.dates],errors:rep.errors,skipped:rep.skipped,file:rep.file,lines:rep.lines.map(l=>[l.sheet,l.cell,l.customerRaw,l.raw,l.kg,l.boxes,l.origin,l.coop,l.issues.join(),l.note?1:0])}}}}""")
        self.assertEqual(r["dates"], ["2026-11-23"])
        self.assertEqual(r["errors"], [])
        self.assertEqual(r["file"], "産地報告.xlsx")
        self.assertEqual(r["skipped"], [])
        rows = {(x[0], x[1]): x for x in r["lines"]}
        self.assertEqual(rows[("シート1", "A7")][2:8], ["架空デリカ 龍ケ崎工場", "キャベツ", 120, 12, "茨城", "架空農協(JGAP)"])
        self.assertNotIn(("シート1", "A10"), rows)                      # 水菜：規格だけ＝出していない
        self.assertEqual(rows[("シート1", "A9")][3:5], ["レタス", 464])
        self.assertEqual(rows[("シート2", "A7")][2:5], ["龍ヶ崎", "レタス", 403])   # 重量の表（計量したkg）
        self.assertEqual(rows[("シート1", "A11")][4], 3)
        self.assertEqual(rows[("シート1", "F7")][2:6], ["架空フーズ", "人参", 200, 14])
        self.assertEqual(rows[("シート1", "F11")][4:6], [20, 3])          # 次の行の「10ｋ1」も同じ品目
        self.assertEqual(rows[("シート2", "A14")][2:5], ["架空青果 第二工場", "レタス", 1191])
        self.assertEqual(rows[("シート2", "A14")][9], 1)
        self.assertIn("qty", rows[("シート2", "A15")][8])

    def test_c162_split_origins_and_weight_rows(self):
        """c162：産地が分かれて2段（かっこの合計kgが段ごと・JGAPの印つき）、重量の表の2段目（納品先が空の行・品名の行）を読む"""
        page = self.open_app()
        q = page.evaluate("""()=>{const q=c142Parse.parseReportQty;return ['8ｋ30(198ｋ)JGAP 8ｋ46(358ｋ)','8ｋ30(198ｋ) 8ｋ46','8ｋ193(1191ｋ)JGAP','10ｋ6 (JGAP)'].map(s=>q(s))}""")
        self.assertEqual([q[0]["kg"], q[0]["boxes"], q[0]["pack"], q[0]["calcKg"]], [556, 76, 8, 608])
        self.assertEqual(q[1]["kg"], 566)                 # 合計の書いていない段は箱から計算
        self.assertEqual(q[2]["kg"], 1191)
        self.assertEqual(q[3]["kg"], 60)
        r = page.evaluate("""()=>{
          const serial=d=>Math.round((new Date(d+'T00:00:00Z')-new Date('1899-12-30T00:00:00Z'))/864e5);
          const a=XLSX.utils.aoa_to_sheet([
           ['産地報告'],[],['重量'],[],
           ['納品先',null,'単協',null,'kg'],
           ['龍ヶ崎',null,'SYC',null,213,'kg'],
           [null,null,'市場商事',null,190],
           ['プライム第二',null,'SYC',null,145,'kg'],
           ['剝きレタス',null,'カルゲン',null,15],
           [],[],
           ['架空デリカ　龍ケ崎工場'],[],
           ['品目','産地','単協名','cs'],
           ['レタス','茨城','SYC協同組合(JGAP)30','8ｋ55'],
           [null,null,'市場商事25'],
           [],[],
           ['架空デリカ　相模原第二工場'],[],
           ['品目','産地','単協名','cs'],
           ['レタス剥き','茨城','SYC協同組合(JGAP)24','8ｋ26'],
           [null,null,'カルゲン会さしま(JGAP)2'],
           [],[],
           ['架空サービス'],[],
           ['品目','産地','cs'],
           ['レタス','茨城','8ｋ30(198ｋ)JGAP'],
           [null,'長崎','8ｋ46(358ｋ)'],
           [null,'(JGAP)'],
           ['胡瓜','宮崎','15ｋ1　10ｋ1'],
          ]);
          a['C1']={t:'n',v:serial('2026-11-25')};
          const rep=c142Parse.readReport({SheetNames:['S'],Sheets:{S:a}},'産地報告.xlsx');
          const raw=rep.lines.map(l=>[l.cell,l.customerRaw,l.raw,l.kg,l.origin,l.coop,l.issues.join()]);
          c142Prepare(rep,{alias:new Map([['剝きレタス',{item_name:'レタス',in_master:true}],['レタス剥き',{item_name:'レタス',in_master:true}]]),std:new Map(),aliasRows:[],stdRows:[]},
            {active:{id:'P'},lines:[{customer_name:'架空デリカ 龍ヶ崎工場',item_name:'レタス',kg:440},{customer_name:'架空デリカ 相模原第二工場',item_name:'レタス',kg:208},{customer_name:'架空サービス',item_name:'レタス',kg:600},{customer_name:'架空サービス',item_name:'胡瓜',kg:25}]},
            [{raw_key:'龍ケ崎',customer_name:'架空デリカ 龍ヶ崎工場'},{raw_key:'プライム第二',customer_name:'架空デリカ 相模原第二工場'}],null);
          const eff=c142Auto.eff().map(l=>[l.cell,l.customer,l.item,l.kg,l.note,l.open.join()]);
          return {raw,eff}}""")
        raw = {x[0]: x for x in r["raw"]}
        self.assertEqual(raw["A7"][1:4], ["龍ヶ崎", "レタス", 190])                 # 納品先が空の2段目は上の納品先の続き
        self.assertEqual(raw["A8"][1:4], ["プライム第二", "剝きレタス", 145])
        self.assertEqual(raw["A9"][1:4], ["プライム第二", "剝きレタス", 15])       # 品名の行は上の納品先の続き
        self.assertEqual(raw["A29"][3:5], [556, "茨城・長崎(JGAP)"])
        self.assertEqual(raw["A29"][6], "")
        self.assertEqual(raw["A32"][3], 25)
        eff = {x[0]: x for x in r["eff"]}
        self.assertEqual(set(eff), {"A15", "A22", "A29", "A32"})                     # 重量の行はケースの行にまとまる
        self.assertEqual(eff["A15"][3], 403)
        self.assertIn("213＋190＝403kg", eff["A15"][4])
        self.assertEqual(eff["A22"][1:4], ["架空デリカ 相模原第二工場", "レタス", 160])
        self.assertEqual(eff["A29"][3], 556)
        self.assertTrue(all(x[5] == "" for x in r["eff"]))

    def test_different_dates_stop(self):
        page = self.open_app()
        r = page.evaluate(f"""()=>{{const wb=({BOOK})('2026-11-23');wb.Sheets['シート2']['E1'].v+=1;return c142Parse.readReport(wb,'x').errors}}""")
        self.assertIn("シートごとに納品日が違います", r[0])

    def test_confirm_maps_customers_and_saves(self):
        page = self.open_app("worker")
        page.evaluate(f"""()=>{{const rep=c142Parse.readReport(({BOOK})('2026-11-23'),'産地報告.xlsx');
          const plan={{active:{{id:'P'}},lines:[{{customer_name:'架空デリカ 龍ヶ崎工場',item_name:'キャベツ',kg:100}},{{customer_name:'架空フーズ(八千代)',item_name:'人参',kg:200}},{{customer_name:'架空青果 第二工場',item_name:'レタス',kg:1200}}]}};
          c142Prepare(rep,{MASTERS},plan,[],null);return c142PreviewPage()}}""")
        page.wait_for_selector("text=要確認：積み込み表と書き方が違う客先")
        text = page.inner_text("#app")
        self.assertIn("架空フーズ", text)
        self.assertNotIn("架空デリカ 龍ケ崎工場（", text.split("要確認：積み込み表と書き方が違う客先")[1].split("要確認：数量")[0])  # ケ・ヶの違いは自動でそろう
        self.assertEqual(page.locator("text=この内容で確定数量を登録する").count(), 0)
        page.evaluate("()=>c142PickCustomer(c142Parse.ckey('架空フーズ'),'架空フーズ(八千代)')")
        page.wait_for_timeout(50)
        page.evaluate("()=>c142PickCustomer(c142Parse.ckey('龍ヶ崎'),'架空デリカ 龍ヶ崎工場')")
        page.locator("input[placeholder=kg]").first.fill("15")
        page.locator("input[placeholder=kg]").first.dispatch_event("change")
        page.wait_for_selector("text=この内容で確定数量を登録する")
        page.click("text=この内容で確定数量を登録する")
        page.wait_for_function("()=>window.__rpc.some(r=>r[0]==='replace_ship_actual_v1199c142')")
        rpc = page.evaluate("()=>window.__rpc")
        self.assertEqual(rpc[0], ["save_ship_customer_alias_v1199c142", {"p_key": "架空フーズ", "p_raw": "架空フーズ", "p_customer": "架空フーズ(八千代)"}])
        args = rpc[-1][1]
        self.assertEqual(args["p_delivery_date"], "2026-11-23")
        by = {(l["source_sheet"], l["source_cell"]): l for l in args["p_lines"]}
        self.assertEqual(by[("シート1", "A7")]["customer_name"], "架空デリカ 龍ヶ崎工場")
        self.assertEqual(by[("シート1", "A7")]["customer_raw"], "架空デリカ 龍ケ崎工場")
        self.assertEqual(by[("シート1", "F7")]["customer_name"], "架空フーズ(八千代)")
        self.assertEqual(by[("シート2", "A15")]["kg"], 15)
        self.assertEqual(by[("シート1", "A7")]["coop"], "架空農協(JGAP)")
        # 計量したkgがケースの行に入り、重量の行そのものは送らない
        self.assertEqual(by[("シート1", "A9")]["kg"], 403)
        self.assertIn("計量 403kg", by[("シート1", "A9")]["note"])
        self.assertNotIn(("シート2", "A7"), by)

    def test_compare_uses_kg_and_only_customers_with_actuals(self):
        page = self.open_app("admin")
        page.evaluate("""()=>{const T=window.__T;
          T.ship_plan_imports_v1199c140=[{id:'P1',delivery_date:'2026-11-23',ship_date:'2026-11-22',status:'active',files:[],line_count:3,total_kg:1000,imported_by_name:'事務',imported_at:'2026-11-21T08:00:00Z'}];
          T.ship_plan_lines_v1199c140=[{import_id:'P1',line_no:1,customer_name:'架空デリカ',item_name:'ほうれん草',item_in_master:true,item_raw:'業務用ほうれん草 5kg',qty_raw:'120',unit:'cs',kg:600,pack_kg:5,boxes:120},
            {import_id:'P1',line_no:2,customer_name:'架空フーズ',item_name:'ほうれん草',item_in_master:true,item_raw:'ほうれん草 8kg',qty_raw:'14',unit:'cs',kg:112,pack_kg:8,boxes:14},
            {import_id:'P1',line_no:3,customer_name:'(株)せき 埼玉工場',item_name:'ほうれん草',item_in_master:true,item_raw:'ほうれん草',qty_raw:'400',unit:'kg',kg:400,pack_kg:null}];
          T.ship_actual_imports_v1199c142=[{id:'A1',delivery_date:'2026-11-23',ship_date:'2026-11-22',status:'active',line_count:2,total_kg:712,imported_by_name:'社員',imported_at:'2026-11-22T08:00:00Z'}];
          T.ship_actual_lines_v1199c142=[{import_id:'A1',line_no:1,customer_name:'架空デリカ',item_name:'ほうれん草',item_in_master:true,item_raw:'ほうれん草',kg:600,pack_kg:6,boxes:100},
            {import_id:'A1',line_no:2,customer_name:'架空フーズ',item_name:'ほうれん草',item_in_master:true,item_raw:'ほうれん草',kg:112,pack_kg:null,boxes:19}]}""")
        page.evaluate("()=>c140ShipPlanPage('2026-11-23','')")
        page.wait_for_selector("text=品目ごとの合計")
        text = page.inner_text("#app")
        self.assertNotIn("違い", text.split("品目ごとの合計")[1].split("ケース数は")[0])   # kgが同じなら、ケースの数が違っても「違い」にしない
        self.assertIn("確定のある客先の予定：", text)                                      # 埼玉は比べない
        self.assertIn("1,112kg（8kg×14・5kg×120）", text)     # 書いてある箱の重さ×箱数のまま
        self.assertIn("712kg（6kg×100・重さ混在19箱）", text)
        self.assertNotIn("違い1", text)                                   # 確定のない客先（埼玉）は「違い」にしない

    def test_view_shows_plan_and_actual_side_by_side(self):
        page = self.open_app("buyer")
        page.evaluate("""()=>{const T=window.__T;
          T.ship_plan_imports_v1199c140=[{id:'P1',delivery_date:'2026-11-23',ship_date:'2026-11-22',status:'active',files:[],line_count:1,total_kg:100,imported_by_name:'事務',imported_at:'2026-11-21T08:00:00Z'}];
          T.ship_plan_lines_v1199c140=[{import_id:'P1',line_no:1,customer_name:'架空デリカ',item_name:'キャベツ',item_in_master:true,item_raw:'キャベツ 10kg',qty_raw:'10',unit:'cs',kg:100,pack_kg:10}];
          T.ship_actual_imports_v1199c142=[{id:'A1',delivery_date:'2026-11-23',ship_date:'2026-11-22',status:'active',line_count:1,total_kg:120,imported_by_name:'社員',imported_at:'2026-11-22T08:00:00Z'}];
          T.ship_actual_lines_v1199c142=[{import_id:'A1',line_no:1,customer_name:'架空デリカ',item_name:'キャベツ',item_in_master:true,item_raw:'キャベツ',kg:120,pack_kg:10,origin:'茨城',coop:'架空農協'}]}""")
        page.evaluate("()=>c140ShipPlanPage('2026-11-23','')")
        page.wait_for_selector("text=品目ごとの合計")
        text = page.inner_text("#app")
        self.assertIn("確定（産地報告書）", text)
        self.assertIn("違い", text)
        self.assertIn("12ケース", text)
        self.assertIn("10ケース", text)
        self.assertEqual(page.locator("text=産地報告書を取り込む").count(), 0)   # 仕入れ担当者は見るだけ


if __name__ == "__main__":
    unittest.main()
