"""c130：仕入先・単協マスタ、GAP一覧（取り込みの確認・QR入庫の自動入力）、伝票のGAP表示と荻沼の伝票を、架空データで確認する。"""
import functools
import threading
import unittest
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

from playwright.sync_api import sync_playwright

from test_hq_pack import run_c86, slip_of, PACK_LOT, BIG_LOT

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
MOCK = (HERE / "mock_hq.js").read_text(encoding="utf-8")

SETUP = """([gap,parties,lots,moves,history])=>{
 const T=window.__T;T.qr_gap_certs_v1199c130=gap;T.qr_party_names_v1280=parties;T.qr_lots=lots;T.qr_lot_movements=moves;T.qr_slip_adjust_v1199c86=[];
 window.__x={rpc:[],confirm:true,alerts:[]};window.confirm=()=>window.__x.confirm;window.alert=m=>window.__x.alerts.push(String(m));
 const base=qrSelect;
 qrSelect=async(t,q)=>{const m=String(q).match(/(?:^|&)(\\w+)=in\\.\\(([^)]*)\\)/);if(m&&T[t]){const vs=decodeURIComponent(m[2]).split(',');return JSON.parse(JSON.stringify(T[t].filter(r=>vs.includes(String(r[m[1]])))))}return base(t,q)};
 callRpc=async(n,a)=>{window.__x.rpc.push([n,JSON.parse(JSON.stringify(a||{}))]);
  if(n==='list_qr_outbound_history_v1144'){const rows=(history[a.p_work_date]||[]);return{rows,total_count:rows.length}}
  if(n==='set_qr_party_name_v1280'){const k=a.p_kind,nm=a.p_name;T.qr_party_names_v1280=T.qr_party_names_v1280.filter(r=>!(r.kind===k&&qrNormalizeName(r.name)===qrNormalizeName(nm)));T.qr_party_names_v1280.push({kind:k,norm:qrNormalizeName(nm),name:nm,status:a.p_status,renamed_to:a.p_renamed_to});return{ok:true}}
  if(n==='qr_party_usage_v1199c130')return a.p_kind==='cooperative'?[{name:'JA水戸',norm:'JA水戸',lots:3,last_date:'2026-11-10'},{name:'JA水戸市',norm:'JA水戸市',lots:2,last_date:'2026-11-09'}]:[];
  return{ok:true}};
}"""

def ymd(days):
    return f"(()=>ymdKey(new Date(Date.now()+({days})*864e5)))()"


class PartyGapBrowserTests(unittest.TestCase):
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

    def open_app(self, role="admin", gap=None, parties=None, lots=None, moves=None, history=None):
        context = self.browser.new_context(viewport={"width": 820, "height": 1180}, service_workers="block")
        self.addCleanup(context.close)
        context.route("**/*", lambda route: route.continue_() if urlparse(route.request.url).netloc == self.local else route.abort())
        page = context.new_page()
        errors = []
        page.on("pageerror", lambda error: errors.append(str(error)))
        self.addCleanup(lambda: self.assertEqual(errors, []))
        page.goto(self.url, wait_until="load")
        page.wait_for_function("()=>typeof c130GapPage==='function'&&typeof ymdKey==='function'")
        page.wait_for_timeout(600)
        page.evaluate(MOCK, role)
        today, yday = page.evaluate("()=>[ymdKey(new Date()),ymdKey(new Date(Date.now()-864e5))]")
        self.today, self.yday = today, yday
        hist = {k.replace("TODAY", today).replace("YDAY", yday): v for k, v in (history or {}).items()}
        page.evaluate(SETUP, [gap or [], parties or [], lots or [], moves or [], hist])
        return page

    # ---------- GAP一覧の取り込み（確認） ----------
    def test_import_check_matches_masters_and_reports_errors(self):
        parties = [{"kind": "cooperative", "name": "JA水戸", "status": "active"},
                   {"kind": "cooperative", "name": "JA水戸市", "status": "deleted", "renamed_to": "JA水戸"},
                   {"kind": "cooperative", "name": "ＪＡつくば", "status": "active"},
                   {"kind": "cooperative", "name": "カルゲン会さしま", "status": "active"}]
        page = self.open_app(parties=parties)
        fam = page.evaluate("""async()=>{const m=await c130Master(true);return c130Check([['単協名','品目','認証区分','有効期限'],['さしま農場（カルゲン会さしま）','大根','JGAP','2028/3/27'],['NCTファームネット（小出博基）','レタス','GGAP','2027/8/27']],m)}""")
        # c164：マスタにない名前もそのまま取り込む（マスタにない印つき）
        self.assertEqual([(r["coop_name"], r["item_name"], r["unknown"]) for r in fam["rows"]], [("カルゲン会さしま", "大根", ""), ("NCTファームネット(小出博基)", "レタス", "単協名・仕入先")])
        self.assertEqual(fam["errors"], [])
        rows = [{"coop_norm": "カルゲン会さしま", "item_norm": "大根", "certification": "JGAP", "expires_on": "2028-03-27"},
                {"coop_norm": "カルゲン会さしま", "item_norm": "葉付大根", "certification": "GGAP", "expires_on": "2028-03-27"}]
        found = page.evaluate("(r)=>['カット大根','葉付大根','葉付き大根','人参'].map(i=>{const g=c130Find(r,'カルゲン会さしま',i,'2026-11-19');return g?g.certification:''})", rows)
        self.assertEqual(found, ["JGAP", "GGAP", "JGAP", ""])
        sup = page.evaluate("""async()=>{window.__T.qr_party_names_v1280.push({kind:'supplier',name:'丸西産業',status:'active'});const m=await c130Master(true);
          return c130Check([['単協名・仕入先','品目','認証区分','有効期限'],['丸西産業','レタス','JGAP','2028/1/1'],['無い名前','レタス','JGAP','2028/1/1']],m)}""")
        self.assertEqual([(r["coop_name"], r["item_name"], r["unknown"]) for r in sup["rows"]], [("丸西産業", "レタス", ""), ("無い名前", "レタス", "単協名・仕入先")])
        g2 = [{"coop_norm": "丸西産業", "item_norm": "レタス", "certification": "JGAP", "expires_on": "2028-01-01"},
              {"coop_norm": "JA水戸", "item_norm": "レタス", "certification": "GGAP", "expires_on": "2028-01-01"}]
        self.assertEqual(page.evaluate("(r)=>[['','丸西産業'],['JA水戸','丸西産業'],['JA不明','丸西産業'],['','水戸大同']].map(([c,s])=>{const g=c130Find(r,c,'レタス','2026-11-19',s);return g?g.certification:''})", g2),
                         ["JGAP", "GGAP", "JGAP", ""])
        out = page.evaluate("""async()=>{const m=await c130Master(true);
          const aoa=[['GAP一覧'],['単協名','品目','認証区分','有効期限','備考'],
           ['JA水戸','キャベツ','JGAP','2027/3/31','a'],
           ['JA水戸市','白菜','ggap',46477,''],
           ['JAつくば','キャベツ','J-GAP','R9.3.31',''],
           ['JA未登録','キャベツ','JGAP','2027/3/31',''],
           ['JA水戸','存在しない野菜','JGAP','2027/3/31',''],
           ['JA水戸','人参','ABC','2027/3/31',''],
           ['JA水戸','人参','JGAP','2027/2/30',''],
           ['JA水戸','キャベツ','GGAP','2027/4/1',''],
           ['','','','','']];
          return c130Check(aoa,m)}""")
        rows = {(r["line"], r["coop_name"], r["item_name"], r["certification"], r["expires_on"]) for r in out["rows"]}
        # 10行目は3行目と同じ単協・品目で期限が新しいので、10行目を使う
        self.assertEqual(rows, {(10, "JA水戸", "キャベツ", "GGAP", "2027-04-01"), (4, "JA水戸", "白菜", "GGAP", "2027-03-31"),
                                (5, "ＪＡつくば", "キャベツ", "JGAP", "2027-03-31"), (6, "JA未登録", "キャベツ", "JGAP", "2027-03-31"),
                                (7, "JA水戸", "存在しない野菜", "JGAP", "2027-03-31")})
        self.assertEqual({r["line"]: r["unknown"] for r in out["rows"] if r["unknown"]}, {6: "単協名・仕入先", 7: "品目"})
        self.assertEqual([(x["lines"], x["used"]) for x in out["merged"]], [([3, 10], 10)])
        reasons = {e["line"]: e["reason"] for e in out["errors"]}
        self.assertEqual(set(reasons), {8, 9})
        self.assertIn("認証区分", reasons[8])
        self.assertIn("有効期限", reasons[9])
        self.assertEqual(page.evaluate("()=>['AGAP','ａｓｉａｇａｐ','J-GAP','GLOBALG.A.P.','x'].map(c130Cert)"), ["ASIAGAP", "ASIAGAP", "JGAP", "GGAP", ""])

    def test_import_preview_shows_diff_and_replaces_only_valid_rows(self):
        parties = [{"kind": "cooperative", "name": "JA水戸", "status": "active"}]
        gap = [{"coop_norm": "JA水戸", "coop_name": "JA水戸", "item_norm": "キャベツ", "item_name": "キャベツ", "certification": "GGAP", "expires_on": "2027-01-01", "note": ""},
               {"coop_norm": "JA水戸", "coop_name": "JA水戸", "item_norm": "白菜", "item_name": "白菜", "certification": "JGAP", "expires_on": "2027-01-01", "note": ""}]
        page = self.open_app(parties=parties, gap=gap)
        page.evaluate("""async()=>{const wb=XLSX.utils.book_new();
          XLSX.utils.book_append_sheet(wb,XLSX.utils.aoa_to_sheet([['単協名','品目','認証区分','有効期限','備考'],['JA水戸','キャベツ','JGAP','2027/3/31',''],['JA水戸','人参','JGAP','2027/3/31',''],['JA不明','人参','JGAP','2027/3/31','']]),'GAP一覧');
          const buf=XLSX.write(wb,{type:'array',bookType:'xlsx'});await c130ReadFile({files:[new File([buf],'gap.xlsx')]})}""")
        page.wait_for_selector("text=GAP一覧の取り込み（確認）")
        text = page.inner_text("#app")
        for s in ("追加\n2", "変更\n1", "削除\n1", "マスタにない名前・品目のまま取り込む行（1件）", "この内容で置き換える（3件）"):
            self.assertIn(s, text)
        self.assertNotIn("取り込まない行", text)
        page.click("text=この内容で置き換える（3件）")
        page.wait_for_function("()=>window.__x.rpc.some(x=>x[0]==='replace_qr_gap_certs_v1199c130')")
        sent = page.evaluate("()=>window.__x.rpc.find(x=>x[0]==='replace_qr_gap_certs_v1199c130')[1].p_rows")
        self.assertEqual(sent, [{"coop_name": "JA水戸", "item_name": "キャベツ", "certification": "JGAP", "expires_on": "2027-03-31", "note": ""},
                                {"coop_name": "JA水戸", "item_name": "人参", "certification": "JGAP", "expires_on": "2027-03-31", "note": ""},
                                {"coop_name": "JA不明", "item_name": "人参", "certification": "JGAP", "expires_on": "2027-03-31", "note": ""}])

    def test_c164_reads_company_gap_list_and_prefers_valid_rows(self):
        parties = [{"kind": "cooperative", "name": "カルゲン会さしま", "status": "active"},
                   {"kind": "cooperative", "name": "アグリファクトリー", "status": "active"},
                   {"kind": "supplier", "name": "サンワアグリ", "status": "active"},
                   {"kind": "cooperative", "name": "NCTファームネット", "status": "active"},
                   {"kind": "supplier", "name": "新光製作所", "status": "active"}]
        page = self.open_app(parties=parties)
        out = page.evaluate("""async()=>{const m=await c130Master(true);const D=(y,mo,d)=>new Date(y,mo-1,d);
          const aoa=[[null,null,null,null,'GAP認証農場取引及び検討一覧'],[],
           [null,'産地','産地','品目','４月',null,'認証','番号','認証期限'],
           [null,null,null,null,'上旬'],
           ['★認証取得済','さしま農場（カルゲン会さしま）','茨城','キャベツ','〇',null,'JGAP','080000167',D(2028,3,27)],
           ['★認証取得済','中山ファーム','茨城','キャベツ',null,null,'JGAP','080000165',D(2028,3,29)],
           ['★認証取得済','常総井上農園','茨城','キャベツ',null,null,'JGAP',null,'-','080000149'],
           [null,'※ 紫キャベツ 含む ※'],
           [null,'産地','産地','品目','４月',null,'認証','番号','認証期限'],
           ['★認証取得済','サンワアグリ(アグリファクトリー)','茨城','長葱',null,null,'JGAP','080000138',D(2023,5,19)],
           ['★取引検討中','常総井上農園','茨城','長葱',null,null,'JGAP',null,null],
           ['★認証取得済','アグリファクトリー(サンワアグリ)','茨城','長葱',null,null,'JGAP','080000138',D(2027,5,19)],
           ['★認証取得済','ＮＣＴファームネット(小出博基)','長野','レタス',null,null,'GGAP','00110-HVLNV_x0002_0003',D(2027,8,27),'4063061714947'],
           ['★認証取得済','株式会社\u3000新光製作所','茨城','長葱',null,null,'JGAP','080000229',D(2026,11,21)],
           ['★認証取得済','アグリフード千葉','千葉','ズッキー二','〇',null,'JGAP','120000139',D(2027,1,21)],
           ['★認証取得済','フレッシュ･オガケン','愛知','玉葱',null,null,'AGAP','MIC-S-230000044',D(2028,5,22),'※全農青果センター扱い']];
          return c130Check(aoa,m)}""")
        got = {(r["line"], r["coop_name"], r["item_name"], r["certification"], r["expires_on"]) for r in out["rows"]}
        self.assertIn((5, "カルゲン会さしま", "キャベツ", "JGAP", "2028-03-27"), got)
        self.assertIn((6, "中山ファーム", "キャベツ", "JGAP", "2028-03-29"), got)
        self.assertIn((12, "サンワアグリ", "長葱", "JGAP", "2027-05-19"), got)
        self.assertIn((13, "NCTファームネット", "レタス", "GGAP", "2027-08-27"), got)
        self.assertIn((14, "新光製作所", "長葱", "JGAP", "2026-11-21"), got)
        self.assertIn((15, "アグリフード千葉", "ズッキーニ", "JGAP", "2027-01-21"), got)
        self.assertIn((16, "フレッシュ・オガケン", "玉葱", "ASIAGAP", "2028-05-22"), got)
        self.assertEqual(len(out["rows"]), 7)
        notes = {r["line"]: r["note"] for r in out["rows"]}
        self.assertEqual(notes[5], "認証番号 080000167、茨城")
        self.assertEqual(notes[13], "認証番号 00110-HVLNV-0003、長野")
        self.assertEqual(notes[16], "認証番号 MIC-S-230000044、愛知、※全農青果センター扱い")
        self.assertEqual([(x["lines"], x["used"]) for x in out["merged"]], [([10, 12], 12)])
        reasons = {e["line"]: e["reason"] for e in out["errors"]}
        self.assertEqual(set(reasons), {7, 11})
        self.assertIn("有効期限の記載がありません", reasons[7])
        self.assertIn("★取引検討中", reasons[11])
        # 期限切れの行があっても、有効な行（単協・仕入先のどちらか）を使う。アグリファクトリーはサンワアグリ
        g = [{"coop_norm": "アグリファクトリー", "item_norm": "長葱", "certification": "GGAP", "expires_on": "2023-05-19"},
             {"coop_norm": "サンワアグリ", "item_norm": "長葱", "certification": "JGAP", "expires_on": "2027-05-19"}]
        self.assertEqual(page.evaluate("(r)=>{const a=c130Find(r,'アグリファクトリー','長葱','2026-11-25','サンワアグリ'),b=c130Find(r.slice(1),'アグリファクトリー','長葱','2026-11-25',''),c=c130Find(r.slice(0,1),'アグリファクトリー','長葱','2026-11-25','');return [a.certification,a.valid,b.certification,b.valid,c.valid]}", g),
                         ["JGAP", True, "JGAP", True, False])

    def test_gap_page_lists_expired_and_soon_and_worker_cannot_open(self):
        page = self.open_app()
        rows = page.evaluate(f"""()=>[['JA水戸','キャベツ','JGAP',{ymd(-1)}],['JA水戸','白菜','JGAP',{ymd(10)}],['JA水戸','人参','GGAP',{ymd(60)}]]
          .map(([c,i,g,e])=>({{coop_norm:c,coop_name:c,item_norm:i,item_name:i,certification:g,expires_on:e,note:'',imported_by_name:'管理者',imported_at:new Date().toISOString()}}))""")
        page.evaluate("(r)=>{window.__T.qr_gap_certs_v1199c130=r}", rows)
        page.evaluate("()=>c130GapPage('')")
        page.wait_for_selector("text=期限切れ（1件）")
        text = page.inner_text("#app")
        self.assertIn("30日以内に期限が切れる（1件）", text)
        self.assertIn("登録 3件", text)
        worker = self.open_app("worker")
        worker.evaluate("()=>c130GapPage('')")
        self.assertIn("管理者だけ", worker.evaluate("()=>window.__x.alerts.join()"))

    def test_jgap_auto_check_card_c174(self):
        page = self.open_app()
        page.evaluate("""()=>{window.__T.qr_gap_jgap_runs_v1199c174=[{id:3,run_at:'2026-12-01T00:43:00Z',days:60,summary:{updated:1,ambiguous:1,not_found:1},
          report:[{coop_name:'エプロン',item_name:'玉葱',expires_on:'2026-07-05',status:'updated',new_expires:'2028-07-05',jgap_name:'株式会社エプロン'},
                  {coop_name:'タスパス',item_name:'キャベツ',expires_on:'2026-12-01',status:'ambiguous',candidates:['田原タスパス部会','タスパスくまもと JGAP部会']},
                  {coop_name:'SYC協同組合',item_name:'レタス',expires_on:'2026-10-21',status:'not_found'},
                  {coop_name:'佐賀東部青果',item_name:'玉葱',expires_on:'2026-11-21',status:'same'}]}]}""")
        page.evaluate("()=>c130GapPage('')")
        page.wait_for_selector("text=JGAP・GLOBALG.A.P.サイトでの自動チェック")
        text = page.inner_text("#app")
        self.assertIn("自動で延ばした（1件）", text)
        self.assertIn("確かめてほしいもの（2件）", text)
        self.assertIn("田原タスパス部会、タスパスくまもと JGAP部会", text)
        self.assertIn("サイトで見つからない", text)
        self.assertNotIn("佐賀東部青果", text.split("確かめてほしいもの")[1].split("期限切れ")[0])  # 同じ期限は「確かめて」に出さない

    def test_ggap_results_in_auto_check_card_c176(self):
        page = self.open_app()
        page.evaluate("""()=>{window.__T.qr_gap_jgap_runs_v1199c174=[{id:4,run_at:'2026-12-01T00:43:00Z',days:60,summary:{updated:1,not_in_list:1,no_ggn:1,site_expired:1},
          report:[{coop_name:'アグリルーツ',item_name:'キャベツ',certification:'GGAP',expires_on:'2026-12-21',status:'updated',new_expires:'2027-12-21',jgap_name:'',jgap_no:'4063651718256'},
                  {coop_name:'丸西産業',item_name:'レタス',certification:'GGAP',expires_on:null,status:'not_in_list',new_expires:'2027-07-12',jgap_name:'Marunishi Sangyo Co., Ltd.',jgap_no:'4069453240773'},
                  {coop_name:'石嶋農園',item_name:'長葱',certification:'GGAP',expires_on:null,status:'no_ggn'},
                  {coop_name:'マルタケ',item_name:'人参',certification:'GGAP',expires_on:'2027-01-25',status:'site_expired',jgap_no:'4063061957016'}]}]}""")
        page.evaluate("()=>c130GapPage('')")
        page.wait_for_selector("text=JGAP・GLOBALG.A.P.サイトでの自動チェック")
        text = page.inner_text("#app")
        self.assertIn("自動で延ばした（1件）", text)
        self.assertIn("4063651718256", text)
        self.assertIn("確かめてほしいもの（3件）", text)
        self.assertIn("SEIKA＋のGAP一覧にない（Excelだけ更新）", text)
        self.assertIn("ExcelにGGNがない", text)
        self.assertIn("サイトで認証が切れている", text)

    # ---------- QR入庫の自動入力 ----------
    def test_qr_create_fills_gap_automatically_and_respects_manual_choice(self):
        parties = [{"kind": "cooperative", "name": "JA水戸", "status": "active"},
                   {"kind": "cooperative", "name": "JA水戸市", "status": "deleted", "renamed_to": "JA水戸"}]
        page = self.open_app(parties=parties)
        exp = page.evaluate(ymd(5))
        page.evaluate("(e)=>{window.__T.qr_gap_certs_v1199c130=[{coop_norm:'JA水戸',coop_name:'JA水戸',item_norm:'キャベツ',item_name:'キャベツ',certification:'JGAP',expires_on:e,note:''}]}", exp)
        page.evaluate("()=>qrCreatePage()")
        page.wait_for_selector("#qrCertification")
        page.select_option("#qrItemName", "キャベツ")
        page.fill("#qrCooperativeName", "JA水戸市")
        page.dispatch_event("#qrCooperativeName", "change")
        page.wait_for_function("()=>document.getElementById('qrCertification').value==='JGAP'")
        self.assertIn("自動で入れました", page.inner_text("#c130GapNote"))
        page.fill("#qrReceivedDate", page.evaluate(ymd(6)))
        page.dispatch_event("#qrReceivedDate", "change")
        page.wait_for_function("()=>document.getElementById('qrCertification').value===''")
        self.assertIn("切れているため", page.inner_text("#c130GapNote"))
        page.fill("#qrReceivedDate", page.evaluate(ymd(0)))
        page.dispatch_event("#qrReceivedDate", "change")
        page.wait_for_function("()=>document.getElementById('qrCertification').value==='JGAP'")
        page.select_option("#qrCertification", "GGAP")
        page.fill("#qrCooperativeName", "JA水戸")
        page.dispatch_event("#qrCooperativeName", "change")
        page.wait_for_timeout(300)
        self.assertEqual(page.eval_on_selector("#qrCertification", "e=>e.value"), "GGAP")
        page.fill("#qrCooperativeName", "")
        page.dispatch_event("#qrCooperativeName", "change")
        page.wait_for_timeout(200)
        self.assertEqual(page.eval_on_selector("#qrCertification", "e=>e.value"), "GGAP")

    # ---------- マスタ ----------
    def test_save_check_fixes_alias_and_asks_before_registering_unknown_names(self):
        parties = [{"kind": "supplier", "name": "水戸大同", "status": "active"},
                   {"kind": "cooperative", "name": "JA水戸", "status": "active"},
                   {"kind": "cooperative", "name": "JA水戸市", "status": "deleted", "renamed_to": "JA水戸"}]
        page = self.open_app(parties=parties)
        page.evaluate("""()=>{document.getElementById('app').insertAdjacentHTML('beforeend','<input id="qrSupplier" value="水戸大同 "><input id="qrCooperativeName" value="JA水戸市">')}""")
        self.assertTrue(page.evaluate("()=>c130CheckParties([['supplier','qrSupplier'],['cooperative','qrCooperativeName']])"))
        self.assertEqual(page.evaluate("()=>[qrSupplier.value,qrCooperativeName.value]"), ["水戸大同", "JA水戸"])
        page.evaluate("()=>{qrCooperativeName.value='JA新しい';window.__x.confirm=false}")
        self.assertFalse(page.evaluate("()=>c130CheckParties([['cooperative','qrCooperativeName']])"))
        self.assertFalse(any(x[0] == "set_qr_party_name_v1280" for x in page.evaluate("()=>window.__x.rpc")))
        page.evaluate("()=>{window.__x.confirm=true}")
        self.assertTrue(page.evaluate("()=>c130CheckParties([['cooperative','qrCooperativeName']])"))
        call = [x for x in page.evaluate("()=>window.__x.rpc") if x[0] == "set_qr_party_name_v1280"][-1][1]
        self.assertEqual((call["p_kind"], call["p_name"], call["p_status"]), ("cooperative", "JA新しい", "active"))
        self.assertEqual(sorted(page.evaluate("()=>v1280Candidates('cooperative')")), sorted(["JA新しい", "JA水戸"]))

    def test_party_page_shows_unregistered_names_and_merge_for_admin_only(self):
        parties = [{"kind": "cooperative", "name": "JA水戸", "status": "active"}]
        page = self.open_app(parties=parties)
        page.evaluate("()=>v1208CandidatePage('cooperative','')")
        page.wait_for_selector("text=マスタにない単協名（ロットに入っている表記・1件）")
        self.assertIn("JA水戸市", page.inner_text("#app"))
        page.click("button:has-text('正式名にまとめる')")
        page.wait_for_selector("text=これにまとめる")
        page.click("button:has-text('これにまとめる')")
        page.wait_for_function("()=>window.__x.rpc.some(x=>x[0]==='qr_party_merge_v1199c130')")
        call = page.evaluate("()=>window.__x.rpc.find(x=>x[0]==='qr_party_merge_v1199c130')[1]")
        self.assertEqual(call, {"p_kind": "cooperative", "p_from": "JA水戸市", "p_to": "JA水戸"})
        worker = self.open_app("worker", parties=parties)
        worker.evaluate("()=>v1208CandidatePage('cooperative','')")
        worker.wait_for_selector("text=マスタにない単協名")
        self.assertNotIn("正式名にまとめる", worker.inner_text("#app").replace("「正式名にまとめる」", ""))

    # ---------- 伝票 ----------
    def slip_data(self):
        lots = [{"id": "LA", "qr_key": "QA", "received_date": "2026-11-15", "origin": "茨城県産", "cooperative_name": "JA水戸", "pack_weight": "10kg", "certification": "JGAP"},
                {"id": "LB", "qr_key": "QB", "received_date": "2026-11-16", "origin": "群馬県産", "supplier": "丸果", "pack_weight": "5kg", "certification": ""}]
        moves = [{"id": "M1", "lot_id": "LA", "cooperative_name": "JA水戸", "operation_meta": {}},
                 {"id": "M2", "lot_id": "LA", "cooperative_name": "JA水戸", "operation_meta": {"hqShip": {"run": "原料便", "time": "12時", "day": "当日便"}}},
                 {"id": "M3", "lot_id": "LB", "supplier": "丸果", "operation_meta": {"hqShip": {"run": "配送便", "time": "11時", "day": "翌日便"}}},
                 {"id": "M4", "lot_id": "LB", "supplier": "丸果", "operation_meta": {"hqShip": {"run": "配送便", "time": "11時", "day": "当日便"}}}]
        row = lambda i, dest, item, qty: {"id": i, "destination": dest, "item_name": item, "qty": qty, "unit": "ケース", "container_type": "ダンボール", "memo": "当日分", "lot_no": "L-" + i, "qr_key": "Q" + i}
        history = {"YDAY": [row("M1", "埼玉", "キャベツ", 4), row("M3", "荻沼", "人参", 2), row("M4", "荻沼", "人参", 1)],
                   "TODAY": [row("M2", "荻沼", "キャベツ", 3)]}
        return lots, moves, history

    def test_slips_show_gap_and_build_oginuma_like_honsha(self):
        lots, moves, history = self.slip_data()
        page = self.open_app(lots=lots, moves=moves, history=history)
        page.evaluate(f"()=>c84SlipPage(ymdKey(new Date()))")
        page.wait_for_selector("text=すべての伝票を印刷")
        tickets = page.evaluate("()=>c84Collect(ymdKey(new Date()),new Map).then(it=>c84Build(it,ymdKey(new Date())).map(t=>({title:c84Title(t),dest:t.dest,lines:t.lines.map(g=>[g.item,g.cert,g.qty])})))")
        self.assertEqual(tickets[0], {"title": "埼玉", "dest": "埼玉", "lines": [["キャベツ", "JGAP", 4]]})
        self.assertEqual(sorted(tickets[1:], key=lambda t: t["title"]), [
            {"title": "荻沼　原料便", "dest": "荻沼", "lines": [["キャベツ", "JGAP", 3]]},
            {"title": "荻沼　配送便", "dest": "荻沼", "lines": [["人参", "", 2]]},
        ])
        html = page.evaluate("()=>document.getElementById('app').innerHTML")
        self.assertIn('<span class="gp">JGAP</span>', html)
        self.assertIn("荻沼　御中", html)
        self.assertNotIn("せき　荻沼", html)
        self.assertIn("<td>GAP</td>", html)
        self.assertIn("伝票発行（埼玉・深谷・本社工場・荻沼）", page.inner_text("#app"))
        ogi = page.evaluate("()=>c84Collect(ymdKey(new Date()),new Map).then(it=>c84TicketPages(c84Build(it,ymdKey(new Date())).find(x=>x.dest==='荻沼'))[0])")
        self.assertIn("納　品　書", ogi)
        self.assertNotIn("請　求　書", ogi)
        self.assertEqual(ogi.count('<tr class="r">') + ogi.count('<tr class="b'), 15)

    # ---------- 荻沼へのQR出庫 ----------
    def test_oginuma_outbound_asks_run_like_honsha(self):
        page = self.open_app()
        state = page.evaluate("""()=>{document.getElementById('app').insertAdjacentHTML('beforeend','<select id="qrMoveDestination"><option>埼玉</option><option>荻沼</option><option>本社</option></select>'+c50ShipBoxHtml());
          const d=document.getElementById('qrMoveDestination'),out=[];for(const v of ['埼玉','荻沼','本社']){d.value=v;c50ToggleShipBox();out.push([v,document.getElementById("c50ShipBox").style.display,document.getElementById("c50ShipLabel").textContent])}return out}""")
        self.assertEqual(state, [["埼玉", "none", "本社への便（必須）"], ["荻沼", "block", "荻沼への便（必須）"], ["本社", "block", "本社への便（必須）"]])

    def test_oginuma_pack_input_works_like_honsha(self):
        shown = run_c86("荻沼", PACK_LOT, ["page"])
        self.assertEqual(shown["display"], "block")
        self.assertEqual(run_c86("荻沼", BIG_LOT, ["page"])["display"], "none")
        out = run_c86("荻沼", PACK_LOT, ["page", "save"], pack="12")
        self.assertEqual(slip_of(out), {"pack": "12kg"})
        big = run_c86("荻沼", BIG_LOT, ["page", "save"], kg="")
        self.assertEqual(len(big["calls"]), 1)
        self.assertEqual(big["focus"], [])


if __name__ == "__main__":
    unittest.main()
