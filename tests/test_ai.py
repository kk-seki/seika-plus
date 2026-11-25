"""c165：AI（毎日のまとめ・AIに聞く・写真で品質評価の候補・帳票の読み取りの補助）の画面を、AIの呼び出しを差し替えて確認する。"""
import functools, threading, unittest
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
MOCK = (ROOT / 'tests' / 'mock_hq.js').read_text(encoding='utf-8')
AI_MOCK = """()=>{
  window.__ai=[];window.__alert='';window.alert=m=>{window.__alert=String(m)};window.confirm=()=>true;
  authEnsure=async()=>true;authToken=()=> 'token';
  const realFetch=window.fetch;
  window.fetch=async(u,o)=>{if(String(u).includes('/functions/v1/seika-ai')){const b=JSON.parse(o.body);window.__ai.push(b);
    const r=b.action==='summary'?{ok:true,body:'・キャベツ 明日100kg\\n・人参の在庫が少ない',created_at:'2026-11-26T06:10:00+09:00'}
     :b.action==='ask'?{ok:true,answer:'先週のキャベツの廃棄は 12kg です。',used:[{kind:'waste',from:'2026-11-19',to:'2026-11-25',item:'キャベツ'}]}
     :b.action==='photo'?{ok:true,grade:'review',issues:['変色','しおれ'],memo:'葉先が少し黄色い',confidence:'medium'}
     :{ok:true,items:[{key:'k1',item:'キャベツ',reason:'名前が近い'}],qty:[{key:'q1',kg:200,reason:'15kg×13+5kg×1'}],customers:[]};
    return new Response(JSON.stringify(r),{status:200,headers:{'Content-Type':'application/json'}})}
   return realFetch(u,o)};
  const base=qrSelect;qrSelect=async(t,q)=>t==='ai_daily_summaries_v1199c165'?(window.__cached||[]):base(t,q);
}"""


class AiTests(unittest.TestCase):
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
        page.wait_for_function("()=>typeof c165AskPage==='function'")
        page.wait_for_timeout(500)
        page.evaluate(MOCK, role); page.evaluate(AI_MOCK)
        self.addCleanup(ctx.close); self.errs = errs
        return page

    def test_home_summary_for_four_roles_and_cache(self):
        for role in ("admin", "worker", "buyer", "sales"):
            with self.subTest(role=role):
                page = self.open_app(role)
                page.evaluate("()=>{c165State.sum.day='';home()}")
                page.wait_for_function("()=>document.getElementById('c165Sum')?.innerText.includes('キャベツ 明日100kg')", timeout=8000)
                self.assertEqual(page.evaluate("()=>__ai.filter(x=>x.action==='summary').length"), 1)
                self.assertEqual(page.evaluate("()=>!!document.querySelector('#c165Sum button[data-seika-click-action=\"c165RefreshSummary\"]')"), role == "admin")
        page = self.open_app("sales")
        page.evaluate("()=>{window.__cached=[{body:'保存済みのまとめ',created_at:'2026-11-26T06:00:00+09:00'}];c165State.sum.day='';home()}")
        page.wait_for_function("()=>document.getElementById('c165Sum')?.innerText.includes('保存済みのまとめ')")
        self.assertEqual(page.evaluate("()=>__ai.length"), 0)  # 保存済みならAIを呼ばない
        page = self.open_app("clerk")
        page.evaluate("()=>home()"); page.wait_for_timeout(600)
        self.assertFalse(page.evaluate("()=>!!document.getElementById('c165Sum')"))

    def test_ask_page(self):
        page = self.open_app("buyer")
        page.evaluate("()=>c165AskPage()")
        page.wait_for_selector("#c165AskText")
        page.fill("#c165AskText", "先週のキャベツの廃棄は？")
        page.evaluate("()=>c165AskSend()")
        page.wait_for_function("()=>document.body.innerText.includes('先週のキャベツの廃棄は 12kg です。')")
        self.assertIn("調べたデータ：廃棄 2026-11-19〜2026-11-25 キャベツ", page.inner_text("#app"))
        page.fill("#c165AskText", "人参は？")
        page.evaluate("()=>c165AskSend()")
        page.wait_for_function("()=>__ai.length===2")
        self.assertEqual(page.evaluate("()=>__ai[1].history"), [{"q": "先週のキャベツの廃棄は？", "a": "先週のキャベツの廃棄は 12kg です。"}])
        # c166：例を押しても聞かず、入力欄に入るだけ。答えの **太字** は記号を出さない
        page.evaluate("()=>c165AskExample('今いちばん在庫が多い品目は？')")
        self.assertEqual(page.input_value("#c165AskText"), "今いちばん在庫が多い品目は？")
        self.assertEqual(page.evaluate("()=>__ai.length"), 2)
        page.evaluate("()=>{c165State.ask.history.push({q:'x',a:'答えは **6kg** です',used:[]});c165AskPage()}")
        self.assertIn("<b>6kg</b>", page.inner_html("#app"))
        self.assertNotIn("**", page.inner_text("#app"))
        page = self.open_app("clerk")
        page.evaluate("()=>c165AskPage()")
        self.assertIn("管理者・青果社員・仕入れ担当・営業", page.evaluate("()=>window.__alert"))

    def test_photo_candidate_fills_quality_form(self):
        page = self.open_app("worker")
        page.evaluate("""()=>{setScreen('v1102QualityPage',[]);pageShell('QR品質評価','',`<div class="card"><input type="radio" name="v1102Grade" value="good"><input type="radio" name="v1102Grade" value="review"><input type="radio" name="v1102Grade" value="bad">
          <div id="v1102ProblemFields">${V1102_QUALITY_ISSUES.map(x=>`<input type="checkbox" name="v1102Issue" value="${x}">`).join('')}</div><textarea id="v1102QualityMemo"></textarea></div>`);c165InjectQuality()}""")
        page.wait_for_selector("#c165Photo")
        page.evaluate("async()=>{v1102CompressPhoto=async()=>new Blob(['x'],{type:'image/jpeg'});await c165PhotoPicked({files:[new File(['x'],'a.jpg',{type:'image/jpeg'})]})}")
        self.assertEqual(page.evaluate("()=>document.querySelector('input[name=v1102Grade]:checked').value"), "review")
        self.assertEqual(page.evaluate("()=>[...document.querySelectorAll('input[name=v1102Issue]:checked')].map(x=>x.value)"), ["変色", "しおれ"])
        self.assertEqual(page.evaluate("()=>document.getElementById('v1102QualityMemo').value"), "（AIの候補）葉先が少し黄色い")
        self.assertEqual(page.evaluate("()=>__ai[0].action"), "photo")

    def test_parse_assist_uses_only_chosen_candidates(self):
        page = self.open_app("admin")
        page.evaluate("""()=>{window.__used=[];window.c140PickItem=(k,v)=>__used.push(['item',k,v]);window.c140FixKg=(k,v)=>__used.push(['kg',k,v]);window.c140FixCust=(k,v)=>__used.push(['cust',k,v]);
          window.c165PlanAssistData=()=>({kind:'plan',items:[{key:'k1',base:'ｷｬﾍﾞﾂ玉',samples:['ｷｬﾍﾞﾂ玉']}],qty:[{key:'q1',item:'キャベツ',qty_raw:'15kg*13.5kg*1',unit:'',case_kg:10,customer:'美野里',label:'11/27・美野里'}],customers:[],known_customers:['美野里デリカ'],apply:{item:'c140PickItem',kg:'c140FixKg',customer:'c140FixCust'}});
          setScreen('c140PreviewPage',[]);pageShell('積み込み表の取り込み（確認）','','<div class="card warn">要確認</div>')}""")
        page.wait_for_selector("#c165Assist")
        page.evaluate("()=>c165AssistRun()")
        page.wait_for_function("()=>document.getElementById('c165Assist').innerText.includes('200kg')")
        self.assertEqual(page.evaluate("()=>__used"), [])  # 押すまで入らない
        self.assertEqual(page.evaluate("()=>Array.isArray(__ai[0].master_items)&&__ai[0].kind"), "plan")
        page.evaluate("()=>c165AssistUse('kg','q1')")
        self.assertEqual(page.evaluate("()=>__used"), [["kg", "q1", "200"]])
        page.evaluate("()=>c165AssistUseAll()")
        self.assertIn(["item", "k1", "キャベツ"], page.evaluate("()=>__used"))
        self.assertEqual(self.errs, [])


if __name__ == "__main__":
    unittest.main()
