"""c140：積み込み表からの出荷予定の取り込み（読み取り・要確認・登録・表示）を、架空の積み込み表で確認する。
積み込み表は、ページの中で SheetJS を使って作る（実物のファイルはリポジトリに入れない）。"""
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

# 架空の積み込み表：B1＝納品日（シリアル値）、便（2行×5列の結合）、客先（3列の結合）、品名・数量・単位・メモ・番号の5列×3ブロック
BOOKS = """(date)=>{
 const serial=d=>Math.round((new Date(d+'T00:00:00Z')-new Date('1899-12-30T00:00:00Z'))/864e5);
 const mk=(rows,merges,b1)=>{const ws=XLSX.utils.aoa_to_sheet(rows);ws['!merges']=merges.map(([r1,c1,r2,c2])=>({s:{r:r1,c:c1},e:{r:r2,c:c2}}));
  ws['B1']={t:'n',v:serial(b1)};return ws};
 const a=[[null,null],['架空便'],[],['架空デリカ 本社工場',null,null,null,null,'架空フーズ'],
  ['キャベツ　10kg',12,'ｃｓ',null,180,'人参　10kg','15kg*3,5kg*1','cs',null,103],
  ['大根　15kg【U】',7,'cs',null,181,'小松菜　7㎏','7kg*21.3kg*1','ｃｓ',null,104],
  ['葉付大根　10kg',null,'cs',null,182,'大葉　3kg',2,'cs',null,105],
  ['Gリーフ　4kg',0,'cs',null,183,'※メモの行'],
  ['キャベツ',700,'kg']];
 const wa=mk(a,[[1,0,2,4],[3,0,3,2],[3,5,3,7]],date);
 const wOther=mk([[null,null],['別の日']],[],'2026-01-01');
 const b=[[null,null],['架空 引き取り便'],[],['架空青果 第二工場'],['トヨシロ　10kg',20,'ｃｓ'],['胡瓜　BM/15kg','15kg*2','cs']];
 const wb1={SheetNames:['1','2'],Sheets:{'1':wOther,'2':wa}},wb2={SheetNames:['2'],Sheets:{'2':mk(b,[[1,0,2,4],[3,0,3,4]],date)}};
 return [{name:'11月_積み込み表.xlsx',wb:wb1},{name:'11月_積み込み表_その2.xlsx',wb:wb2}];
}"""

MASTERS = """{alias:new Map([['gリーフ',{item_name:'グリーンリーフ',in_master:true}],['葉付大根',{item_name:'葉付き大根',in_master:true}]]),
 std:new Map([['キャベツ',10],['葉付き大根',15],['人参',15],['カット大根',15]]),aliasRows:[],stdRows:[]}"""


class ShipPlanBrowserTests(unittest.TestCase):
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
        page.wait_for_function("()=>typeof c140Prepare==='function'&&typeof XLSX!=='undefined'")
        page.wait_for_timeout(500)
        page.evaluate(MOCK, role)
        page.evaluate("""()=>{const T=window.__T;T.ship_plan_imports_v1199c140=[];T.ship_plan_lines_v1199c140=[];
          T.ship_plan_item_aliases_v1199c140=[{raw_key:'gリーフ',raw_name:'Gリーフ',item_name:'グリーンリーフ',in_master:true},{raw_key:'葉付大根',raw_name:'葉付大根',item_name:'葉付き大根',in_master:true}];
          T.ship_plan_case_std_v1199c140=[{item_name:'キャベツ',case_kg:10},{item_name:'葉付き大根',case_kg:15},{item_name:'人参',case_kg:15},{item_name:'カット大根',case_kg:15}];
          window.qrAllowedItemNames=()=>['キャベツ','人参','カット大根','葉付き大根','小松菜','大葉','グリーンリーフ','トヨシロ','胡瓜'];
          window.__rpc=[];callRpc=async(n,a)=>{window.__rpc.push([n,JSON.parse(JSON.stringify(a||{}))]);return n==='replace_ship_plan_v1199c140'?{ok:true,count:a.p_lines.length,replaced:false}:{ok:true}}}""")
        return page

    def test_reads_the_fixed_layout_and_finds_the_sheet_by_b1(self):
        page = self.open_app()
        out = page.evaluate(f"""()=>{{const books=({BOOKS})('2026-11-21');const m={MASTERS};const p=c140Prepare(books,'2026-11-21',m,null);
          return {{sheets:p.sheets,errors:p.errors,lines:p.lines.map(l=>[l.route,l.customer,l.raw,l.base,l.item||'',l.unit,l.kg,l.boxes,l.pack,l.issues.join()])}}}}""")
        self.assertEqual(out["errors"], [])
        self.assertEqual([(s["file"], s["sheet"]) for s in out["sheets"]], [("11月_積み込み表.xlsx", "2"), ("11月_積み込み表_その2.xlsx", "2")])
        rows = {r[2]: r for r in out["lines"]}
        # 空・0の数量は読まない、※のメモ行も読まない
        self.assertNotIn("葉付大根 10kg", rows)
        self.assertNotIn("Gリーフ 4kg", rows)
        self.assertEqual(rows["キャベツ 10kg"][:2], ["架空便", "架空デリカ 本社工場"])
        self.assertEqual(rows["キャベツ 10kg"][4:9], ["キャベツ", "cs", 120, 12, 10])
        self.assertEqual(rows["人参 10kg"][1], "架空フーズ")
        self.assertEqual(rows["人参 10kg"][6:9], [50, 4, None])           # 15kg×3＋5kg×1
        self.assertEqual(rows["キャベツ"][5:7], ["kg", 700])
        # 推測しない：「大根」は要確認、読めない数量も要確認
        self.assertEqual(rows["大根 15kg【U】"][3:5], ["大根", ""])
        self.assertIn("item", rows["大根 15kg【U】"][9])
        self.assertIn("qty", rows["小松菜 7kg"][9])
        # 2つ目のファイル：「引き取り便」は便、客先は次の見出し
        self.assertEqual(rows["トヨシロ 10kg"][:2], ["架空 引き取り便", "架空青果 第二工場"])
        self.assertEqual(rows["胡瓜 BM/15kg"][3:9], ["胡瓜", "胡瓜", "cs", 30, 2, 15])

    def test_wrong_file_is_not_registered(self):
        page = self.open_app()
        out = page.evaluate("""()=>{const ws=XLSX.utils.aoa_to_sheet([['作業予定表'],['長葱',1,'本']]);
          const r=c140Parse.readBooks([{name:'作業予定表.xlsx',wb:{SheetNames:['当日'],Sheets:{'当日':ws}}}],'2026-11-21');return r}""")
        self.assertEqual(out["lines"], [])
        self.assertIn("シートが見つかりません", out["errors"][0])

    def test_cases_round_up_and_small_items_show_weight(self):
        page = self.open_app()
        out = page.evaluate(f"""()=>{{const P=c140Parse,m={MASTERS};
          const lines=[{{item:'人参',kg:50,pack:null}},{{item:'人参',kg:30,pack:15}},{{item:'大葉',kg:6,pack:3}},{{item:'大葉',kg:0.5,pack:null}}];
          const t=P.itemTotals(lines,m);return {{t:t.map(o=>[o.item,o.kg,o.lineCases,o.small,o.frac]),c:P.casesOf('人参',50,null,m),w:[P.weightText(0.5),P.weightText(6.5)]}}}}""")
        self.assertEqual(out["c"], {"std": 15, "exact": 3.3333, "cases": 4, "frac": True})
        self.assertIn(["人参", 80, 6, False, True], out["t"])      # 50kg→4ケース（端数）＋30kg→2ケース
        self.assertIn(["大葉", 6.5, 2, True, False], out["t"])      # 合計10kg以下は重さで表示（0.5kgの行は1箱の重さが分からないのでケースに入らない）
        self.assertEqual(out["w"], ["500g", "6.5kg"])

    def test_confirm_screen_blocks_until_fixed_then_saves_alias_and_plan(self):
        page = self.open_app("clerk")
        page.evaluate(f"""async()=>{{const books=({BOOKS})('2026-11-21');const m={MASTERS};c140Prepare(books,'2026-11-21',m,{{active:null,lines:[]}});return c140PreviewPage()}}""")
        page.wait_for_selector("text=要確認：知らない品名")
        self.assertEqual(page.locator("text=選んだ日を登録する").count(), 0)
        self.assertGreater(page.locator("text=カット大根・葉付き大根などを取り違えない").count(), 0)
        page.evaluate("()=>c140PickItem('大根','カット大根')")
        page.locator("input[placeholder=kg]").first.fill("152")
        page.locator("input[placeholder=kg]").first.dispatch_event("change")
        page.wait_for_selector("text=選んだ日を登録する")
        page.click("text=選んだ日を登録する")
        page.wait_for_function("()=>window.__rpc.some(r=>r[0]==='replace_ship_plan_v1199c140')")
        rpc = page.evaluate("()=>window.__rpc")
        self.assertEqual(rpc[0][0], "save_ship_plan_alias_v1199c140")
        self.assertEqual(rpc[0][1], {"p_key": "大根", "p_raw": "大根", "p_item": "カット大根", "p_in_master": True})
        args = rpc[-1][1]
        self.assertEqual(args["p_delivery_date"], "2026-11-21")
        self.assertRegex(args["p_import_id"], r"^[0-9a-f-]{36}$")
        by = {l["item_raw"]: l for l in args["p_lines"]}
        self.assertEqual(by["大根 15kg【U】"]["item_name"], "カット大根")
        self.assertEqual(by["小松菜 7kg"]["kg"], 152)
        self.assertEqual(by["キャベツ 10kg"]["customer_name"], "架空デリカ 本社工場")
        self.assertEqual(by["キャベツ 10kg"]["source_sheet"], "2")
        self.assertEqual(len(args["p_files"]), 2)

    def test_normal_stock_items_match_and_admin_can_switch_an_alias(self):
        page = self.open_app("admin")
        hit = page.evaluate("""()=>{db.specialItems={exchange:[{id:'x',name:'トレビス',active:true}]};return c140Parse.resolveItem('トレビス',{alias:new Map(),std:new Map()})}""")
        self.assertEqual(hit["item"], "トレビス")
        page.evaluate("""()=>{window.__T.ship_plan_item_aliases_v1199c140.push({raw_key:'馬鈴薯',raw_name:'馬鈴薯',item_name:'さやか',in_master:true});
          const base=window.qrAllowedItemNames;window.qrAllowedItemNames=()=>[...base(),'さやか','とうや'];return c140AliasPage('')}""")
        page.wait_for_selector("text=品名読み替えマスタ")
        page.locator("tr", has_text="馬鈴薯").locator("select").select_option("とうや")
        page.wait_for_function("()=>window.__rpc.some(r=>r[0]==='save_ship_plan_alias_v1199c140')")
        self.assertEqual(page.evaluate("()=>window.__rpc.find(r=>r[0]==='save_ship_plan_alias_v1199c140')[1]"),
                         {"p_key": "馬鈴薯", "p_raw": "馬鈴薯", "p_item": "とうや", "p_in_master": True})

    MULTI = """()=>{
     const serial=d=>Math.round((new Date(d+'T00:00:00Z')-new Date('1899-12-30T00:00:00Z'))/864e5);
     const D=n=>{const t=new Date(todayKey()+'T00:00:00+09:00');t.setDate(t.getDate()+n);return ymdKey(t)};
     const mk=(d,kg)=>{const ws=XLSX.utils.aoa_to_sheet([[null,null],['架空便'],[],['架空デリカ'],['キャベツ　10kg',kg,'cs']]);ws['!merges']=[{s:{r:1,c:0},e:{r:2,c:4}},{s:{r:3,c:0},e:{r:3,c:2}}];ws['B1']={t:'n',v:serial(d)};return ws};
     const mk2=(d)=>{const ws=XLSX.utils.aoa_to_sheet([[null,null],['架空 引き取り便'],[],['架空フーズ'],['人参　10kg','15kg*2','cs']]);ws['!merges']=[{s:{r:1,c:0},e:{r:2,c:4}},{s:{r:3,c:0},e:{r:3,c:2}}];ws['B1']={t:'n',v:serial(d)};return ws};
     const b1={SheetNames:['a','b','c','d'],Sheets:{a:mk(D(-1),5),b:mk(D(1),12),c:mk(D(2),3),d:mk(D(3),7)}};
     const b2={SheetNames:['a','b','c'],Sheets:{a:mk2(D(-1)),b:mk2(D(1)),c:mk2(D(2))}};
     window.__D=[D(-1),D(1),D(2),D(3)];
     return [{name:'その1.xlsx',wb:b1},{name:'その2.xlsx',wb:b2}];
    }"""

    def test_many_days_at_once_skips_unchanged_days_and_resumes(self):
        page = self.open_app("worker")
        page.evaluate(f"""async()=>{{const books=({self.MULTI})();const [p,t1,t2,t3]=window.__D;const m={MASTERS};
          const cur=new Map(window.__D.map(d=>[d,{{active:null,lines:[]}}]));
          cur.set(t1,{{active:{{id:'old',delivery_date:t1}},lines:[{{customer:'架空デリカ',item:'キャベツ',kg:120}},{{customer:'架空フーズ',item:'人参',kg:30}}]}});
          c140Prepare(books,null,m,cur);return c140PreviewPage()}}""")
        page.wait_for_selector("text=取り込む納品日を選ぶ")
        days = page.evaluate("()=>[...document.querySelectorAll('#app label')].filter(l=>l.querySelector('input[type=checkbox]')&&/（/.test(l.textContent)&&!/マスタに追加/.test(l.textContent)).map(l=>[l.querySelector('input').checked,l.textContent.replace(/\\s+/g,' ').trim()])")
        self.assertEqual([d[0] for d in days], [True, True, False, False])          # 片方にしかない日・過去の日（たたんである）は外れている
        self.assertIn("変わらない", days[0][1])
        self.assertIn("新しく登録", days[1][1])
        self.assertIn("シートがありません", days[2][1])
        self.assertIn("過去の日", days[3][1])
        self.assertIn("1日分・変わらない1日は登録しません", page.inner_text("#app"))
        # 過去の日も選べる。2つ目の登録で通信が切れたら、もう一度押すと残りから続ける
        page.evaluate("()=>c140ToggleDate(window.__D[0],true)")
        page.wait_for_selector("text=2日分")
        page.evaluate("""()=>{let n=0;const base=callRpc;callRpc=async(name,a)=>{if(name==='replace_ship_plan_v1199c140'&&++n===2){window.__rpc.push(['fail',a]);throw new Error('通信が切れました')}return base(name,a)};window.alert=()=>{}}""")
        page.click("text=選んだ日を登録する")
        page.wait_for_function("()=>window.__rpc.some(r=>r[0]==='fail')")
        page.wait_for_selector("text=選んだ日を登録する")
        page.click("text=選んだ日を登録する")
        page.wait_for_selector("text=出荷予定を")
        rpc = page.evaluate("()=>window.__rpc.filter(r=>r[0]!=='save_ship_plan_alias_v1199c140').map(r=>[r[0],r[1].p_delivery_date,r[1].p_import_id,(r[1].p_lines||[]).length])")
        D = page.evaluate("()=>window.__D")
        self.assertEqual([(r[0], r[1]) for r in rpc], [("replace_ship_plan_v1199c140", D[0]), ("fail", D[2]), ("replace_ship_plan_v1199c140", D[2])])
        self.assertEqual(rpc[1][2], rpc[2][2])     # 同じ日は同じ取り込みIDで送り直す
        self.assertEqual(rpc[2][3], 2)

    def test_one_file_of_the_pair_is_not_registered(self):
        page = self.open_app("worker")
        page.evaluate(f"""async()=>{{const books=({self.MULTI})();books[0].name='11月.xlsx';books[1].name='11月-埼玉・フジ　他.xlsx';const m={MASTERS};
          c140Prepare([books[0]],null,m,new Map());return c140PreviewPage()}}""")
        page.wait_for_selector("text=取り込む納品日を選ぶ")
        text = page.inner_text("#app")
        self.assertIn("ファイルが足りません", text)
        self.assertIn("11月のもう1つのファイル", text)
        self.assertEqual(page.locator("text=選んだ日を登録する").count(), 0)
        # 前の取り込みにあったファイルが今回ない（名前の決まりに合わないファイルでも止まる）
        page.evaluate(f"""async()=>{{const books=({self.MULTI})();const m={MASTERS};const [p,t1]=window.__D;
          const cur=new Map([[t1,{{active:{{id:'old',delivery_date:t1,files:[{{file:'その1.xlsx'}},{{file:'その2.xlsx'}}]}},lines:[]}}]]);
          c140Prepare([books[0]],null,m,cur);return c140PreviewPage()}}""")
        page.wait_for_selector("text=その2.xlsx がありません")

    def test_home_button_by_role(self):
        for role, expect in (("buyer", "明日の出荷予定を見る"), ("worker", "明日の出荷予定を見る・取り込む"), ("hq_prep", None)):
            page = self.open_app(role)
            page.evaluate("()=>{currentScreen='home';document.getElementById('c140HomeBtn')?.remove();document.querySelector('#app').insertAdjacentHTML('afterbegin','<div class=\"homePrimary\"></div>');c140InjectHome()}")
            btn = page.locator("#c140HomeBtn")
            if expect:
                self.assertEqual(btn.count(), 1, role)
                self.assertIn(expect, btn.inner_text())
            else:
                self.assertEqual(btn.count(), 0, role)

    def test_view_page_shows_totals_and_customers(self):
        page = self.open_app("sales")
        page.evaluate("""()=>{const T=window.__T;T.ship_plan_imports_v1199c140=[{id:'I1',delivery_date:'2026-11-21',ship_date:'2026-11-20',status:'active',files:[{file:'a.xlsx',sheet:'21'}],line_count:2,total_kg:58,imported_by_name:'事務 花子',imported_at:'2026-11-20T08:00:00Z'}];
          T.ship_plan_lines_v1199c140=[{import_id:'I1',line_no:1,customer_name:'架空デリカ',route:'架空便',item_name:'人参',item_in_master:true,item_raw:'人参 10kg',qty_raw:'15kg*3,5kg*1',unit:'cs',kg:50,pack_kg:null},
           {import_id:'I1',line_no:2,customer_name:'架空フーズ',route:'',item_name:'大葉',item_in_master:true,item_raw:'大葉 3kg',qty_raw:'2',unit:'cs',kg:6,pack_kg:3}]}""")
        page.evaluate("()=>c140ShipPlanPage('2026-11-21','')")
        page.wait_for_selector("text=品目ごとの合計")
        text = page.inner_text("#app")
        self.assertIn("出荷日（セット日） 11/20", text)
        self.assertIn("4ケース", text)
        self.assertIn("端数あり", text)
        self.assertIn("6kg", text)
        self.assertIn("架空デリカ", text)
        self.assertEqual(page.locator("text=積み込み表を取り込む").count(), 0)   # 営業は見るだけ


if __name__ == "__main__":
    unittest.main()
