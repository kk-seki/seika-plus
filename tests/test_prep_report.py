import functools
import threading
import unittest
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parent.parent


class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, *_args):
        pass


class PrepReportBrowserTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(QuietHandler, directory=str(ROOT)))
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()
        cls.base = f"http://127.0.0.1:{cls.server.server_port}"
        cls.local = urlparse(cls.base).netloc
        cls.playwright = sync_playwright().start()
        cls.browser = cls.playwright.chromium.launch()

    @classmethod
    def tearDownClass(cls):
        cls.browser.close()
        cls.playwright.stop()
        cls.server.shutdown()
        cls.server.server_close()

    def open_app(self, role="hq_prep"):
        context = self.browser.new_context(viewport={"width": 820, "height": 1400}, service_workers="block", timezone_id="Asia/Tokyo")
        self.addCleanup(context.close)
        context.route("**/*", lambda route: route.continue_() if urlparse(route.request.url).netloc == self.local else route.abort())
        page = context.new_page()
        errors = []
        page.on("pageerror", lambda err: errors.append(str(err)))
        self.addCleanup(lambda: self.assertEqual(errors, [], "browser errors"))
        # The report module is tested in an isolated browser page: no production/cloud request can occur,
        # and unrelated index startup cannot overwrite the rendered mock screen.
        page.set_content('<!doctype html><html><body><div id="app"></div></body></html>')
        page.evaluate("""()=>{
          window.db={}; window.__h2={}; window.esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
          window.seikaEventAttrs=(event,action,args=[])=>`data-seika-${event}-action="${esc(action)}" data-seika-${event}-args="${esc(encodeURIComponent(JSON.stringify(args)))}"`;
          window.currentScreen=''; window.currentArgs=[]; window.setScreen=(name,args=[])=>{window.currentScreen=name;window.currentArgs=args}; window.pageShell=(title,sub,body)=>document.getElementById('app').innerHTML=`<main class="wrap"><h1>${title}</h1><div>${sub}</div>${body}</main>`;
          let __id=0; window.newId=()=>`00000000-0000-4000-8000-${String(++__id).padStart(12,'0')}`;
        }""")
        page.evaluate("""role=>{
          db.role=role; db.user='テスト'; window.alert=m=>{(window.__alerts ||= []).push(String(m))};
          window.confirm=()=>true; window.__calls=[]; window.__scanner=null;
          const staff=[
            {id:'S1',name:'佐藤',team:'1班',qr_key:'HQST-S1'},
            {id:'S2',name:'鈴木',team:'1班',qr_key:'HQST-S2'}
          ];
          const masters=[
            {id:'P1',name:'1/4芯',item_name:'キャベツ'},
            {id:'P2',name:'1/4葉',item_name:'キャベツ'},
            {id:'P3',name:'千切り',item_name:'キャベツ'}
          ];
          const lots=[
            {id:'L1',qr_key:'HQ-L1',lot_no:'LOT-1',item_name:'キャベツ',unit:'case',pack_weight:'10kg',available_qty:5,received_date:'2026-11-10',received_qty:8,current_qty:5,origin:'茨城',supplier:'せき',cooperative_name:'JA',details:'冷蔵'},
            {id:'L2',qr_key:'HQ-L2',lot_no:'LOT-2',item_name:'人参',unit:'kg',available_qty:12,origin:'群馬',supplier:'生産者',cooperative_name:'',details:''}
          ];
          const work={id:'W1',kind:'下処理',status:'完了',confirm_status:'未確定',updated_at:'2026-11-12T01:00:00Z',work_date:'2026-11-12',place:'作業台A',started_at:'2026-11-12T00:00:05Z',ended_at:'2026-11-12T02:00:07Z',outputs:[{master_id:'P1',name:'1/4芯',yield_kg:30}]};
          const c120work={...work,id:'C120',c120_flow:true,review_status:'draft',raw_item_name:'キャベツ',outputs:[{master_id:'P1',name:'1/4芯',yield_kg:30}]};
          const members=[{id:'M1',work_id:'W1',staff_id:'S1',staff_name:'佐藤',phase:'作業',start_at:'2026-11-12T00:00:05Z',end_at:'2026-11-12T00:30:00Z'}, {id:'M2',work_id:'W1',staff_id:'S1',staff_name:'佐藤',phase:'作業',start_at:'2026-11-12T01:00:00Z',end_at:'2026-11-12T02:00:07Z'}];
          const mats=[{id:'WM1',work_id:'W1',lot_id:'L1',lot_no:'LOT-1',item_name:'キャベツ',unit:'case',pack_kg:10,qty:null}];
          window.__h2.num2=v=>{const s=String(v??'').trim();return s===''?NaN:Number(s)}; window.__h2.h2Loading=()=>'<div>読み込んでいます…</div>'; window.__h2.h2CanPrep=()=>['admin','hq_worker','hq_prep'].includes(db.role); window.__h2.h2CanBoss=()=>['admin','hq_worker'].includes(db.role); window.__h2.h2Err=e=>String(e?.message||e||'');
          window.__h2.h2UsedKg=mats=>{let kg=0,unknown=false;for(const m of mats){const q=Number(m.qty),v=m.unit==='kg'?q:q*Number(m.pack_kg);if(!Number.isFinite(v))unknown=true;else kg+=v}return {kg,unknown}};
          window.__h2.r2=async(name,args)=>{window.__calls.push([name,args]); if(name==='hq_prep_available_lots_v1199c117'||name==='hq_prep_available_lots_v1199c120') return JSON.parse(JSON.stringify(lots)); if(name==='hq_prep_report_save_v1199c120'||name==='hq_prep_report_save_v1199c120'||name==='hq_prep_submit_v1199c120') return window.__rpc ? window.__rpc(name,args) : {ok:true,id:args.p_work_id||'NEW',updated_at:'2026-11-12T03:00:00Z',review_status:name.includes('submit')?'submitted':'draft'}; throw new Error('unexpected rpc '+name)};
          window.__h2.h2Staff=async()=>JSON.parse(JSON.stringify(staff)); window.__h2.h2Places=async()=>[{name:'作業台A'},{name:'作業台B'}]; window.__h2.h2Masters=async()=>JSON.parse(JSON.stringify(masters));
          window.__h2.h2Works=async q=>q.includes('id=eq.C120')?[JSON.parse(JSON.stringify(c120work))]:[JSON.parse(JSON.stringify(work))];
          window.__h2.h2Materials=async()=>JSON.parse(JSON.stringify(mats)); window.__h2.h2Members=async()=>JSON.parse(JSON.stringify(members));
          window.__h2.sel2=async(table)=>table==='hq_work_pauses_v1199c116'?[{kind:'休憩',start_at:'2026-11-12T00:30:00Z',end_at:'2026-11-12T01:00:00Z',excluded_staff_ids:[]}]:[];
          window.__h2.h2OutputParts=w=>Array.isArray(w.outputs)&&w.outputs.length?w.outputs:[{master_id:w.prep_master_id,name:w.product_name,yield_kg:w.yield_kg}];
          window.__h2.h2ScanNotice=o=>{document.getElementById('h2ScanNotice')?.remove();const d=document.createElement('div');d.id='h2ScanNotice';d.textContent=o.title+(o.sub||'');d.__undo=o.undo;document.body.appendChild(d)}; window.__h2.h2QrWrong=(k,opt)=>{const kind=/^HQST-/i.test(k)?'staff':'material';if(!opt.expect||kind===opt.expect)return false;window.__h2.h2ScanNotice({ng:true,title:(kind==='staff'?'スタッフ（人の名前）のQR':'原料の貼り紙のQR')+'を読みました',sub:'ここでは「'+(opt.expect==='staff'?'スタッフ（人の名前）のQR':'原料の貼り紙のQR')+'」を読んでください。'});return true};
          window.__h2.h2StartReader=async(_host,cb,opt={})=>window.__scanner=k=>window.__h2.h2QrWrong(k,opt)?undefined:cb(k); window.__h2.h2StopReader=async()=>{window.__stops=(window.__stops||0)+1};
          window.hqPrepHome=async()=>{setScreen('hqPrepHome',[]);pageShell('作業一覧','','<div id="homeBase"></div>')}; window.hqWorkPage=async id=>{setScreen('hqWorkPage',[id]);pageShell('作業','','<div id="workBase"></div>')};
        }""", role)
        page.add_script_tag(url=self.base + "/js/25-c117-prep-report.js")
        page.wait_for_function("()=>typeof c117ReportPage==='function' && typeof c117ReportSave==='function'")
        return page

    def open_new(self, page):
        page.evaluate("()=>c117ReportPage(null)")
        page.locator("#c117Date").wait_for()
        page.locator("#c117Date").fill("2026-11-12")
        page.locator("#c117Started").fill("2026-11-12T09:00")
        page.locator("#c117Ended").fill("2026-11-12T11:00")
        page.locator("#c117Place").select_option(label="作業台A")
        # c120 filters outputs by the selected raw material, so select the lot first.
        page.select_option("#c117LotSelect", "L1")
        page.evaluate("()=>c117AddMaterialFromSelect()")
        page.locator('input[name="c117Master"][value="P1"]').check()
        page.evaluate("()=>c117MasterToggle()")
        page.locator(".c117Qty").fill("5")
        page.locator('[data-c117-output="P1"] input').fill("40")
        page.select_option("#c117StaffSelect", "S1")
        page.evaluate("()=>c117AddMemberFromSelect()")

    def test_permissions_and_c120_candidate_rpc(self):
        page = self.open_app("viewer")
        page.evaluate("()=>c117ReportPage(null)")
        self.assertIn("権限", page.evaluate("()=>__alerts.at(-1)"))
        page = self.open_app()
        self.open_new(page)
        calls = page.evaluate("()=>__calls.filter(x=>x[0]==='hq_prep_available_lots_v1199c120')")
        self.assertEqual(len(calls), 1)
        self.assertEqual(page.locator("#c117MaterialReader").count(), 1)
        self.assertEqual(page.locator("#c117StaffReader").count(), 1)

    def test_c120_qr_and_same_item_only(self):
        page = self.open_app()
        self.open_new(page)
        page.evaluate("()=>c117OpenMaterialQr()")
        page.evaluate("()=>__scanner('HQST-S2')")
        self.assertIn("スタッフ", page.locator("#h2ScanNotice").inner_text())
        page.evaluate("()=>c117OpenMaterialQr()")
        page.evaluate("()=>__scanner('HQ-L2')")
        self.assertEqual(page.locator('[data-c117-material]').count(), 1)
        page.evaluate("()=>c117OpenStaffQr()")
        page.evaluate("()=>__scanner('HQST-S2')")
        self.assertEqual(page.locator('[data-c117-member="S2"]').count(), 1)
        page.evaluate("()=>c117StopQr('c117StaffReader')")
        self.assertGreaterEqual(page.evaluate("()=>__stops"), 1)

    def test_c120_new_pending_retry_survives_reopen(self):
        page = self.open_app()
        self.open_new(page)
        page.evaluate("""()=>{window.__rpc=async()=>{throw new Error('late network')}}""")
        page.evaluate("()=>c120Review();c120SaveDraft()")
        page.wait_for_function("()=>__calls.filter(x=>x[0]==='hq_prep_report_save_v1199c120').length===1")
        first = page.evaluate("()=>__calls.filter(x=>x[0]==='hq_prep_report_save_v1199c120')[0][1]")
        page.evaluate("()=>c120NewReportPage()")
        page.locator(".c117Qty").wait_for()
        self.assertEqual(page.locator(".c117Qty").input_value(), "5")
        page.evaluate("()=>c120Review();c120SaveDraft()")
        page.wait_for_function("()=>__calls.filter(x=>x[0]==='hq_prep_report_save_v1199c120').length===2")
        self.assertEqual(page.evaluate("()=>__calls.filter(x=>x[0]==='hq_prep_report_save_v1199c120')[1][1]"), first)

    def test_c120_known_rejection_allows_correction(self):
        page = self.open_app()
        self.open_new(page)
        page.evaluate("""()=>{window.__rpc=async()=>{throw new Error(JSON.stringify({code:'P0001',message:'原料の在庫が不足しています'}))}}""")
        page.evaluate("()=>c120Review();c120SaveDraft()")
        first = page.evaluate("()=>__calls.find(x=>x[0]==='hq_prep_report_save_v1199c120')[1]")
        page.evaluate("()=>c120Edit()")
        page.locator(".c117Qty").fill("4")
        page.evaluate("()=>{window.__rpc=async(_n,args)=>({ok:true,id:'NEW',updated_at:'2026-11-12T03:00:00Z',review_status:'draft'})};c120Review();c120SaveDraft()")
        page.wait_for_function("()=>__calls.filter(x=>x[0]==='hq_prep_report_save_v1199c120').length===2")
        second = page.evaluate("()=>__calls.filter(x=>x[0]==='hq_prep_report_save_v1199c120')[1][1]")
        self.assertNotEqual(first['p_operation_id'], second['p_operation_id'])
        self.assertEqual(second['p_report']['materials'][0]['qty'], 4)

    def test_c120_confirmed_employee_edit_and_refreshes_candidates(self):
        page = self.open_app("hq_worker")
        page.evaluate("""()=>{const original=window.__h2.h2Works;window.__h2.h2Works=async q=>(await original(q)).map(w=>w.id==='C120'?{...w,review_status:'confirmed',confirm_status:'確定'}:w)}""")
        page.evaluate("()=>c117ReportPage('C120')")
        page.locator("#c120CorrectionReason").wait_for()
        page.locator(".c117Qty").fill("5")
        page.locator("#c120CorrectionReason").fill("数量を訂正")
        page.evaluate("()=>c120Review();c120SaveDraft()")
        page.wait_for_function("()=>__calls.filter(x=>x[0]==='hq_prep_report_save_v1199c120').length===1")
        saved = page.evaluate("()=>__calls.filter(x=>x[0]==='hq_prep_report_save_v1199c120')[0][1]")
        self.assertEqual(saved['p_report']['correction_reason'], '数量を訂正')
        self.assertIn("訂正を保存しました", page.locator("body").inner_text())
        self.assertGreaterEqual(page.evaluate("()=>__calls.filter(x=>x[0]==='hq_prep_available_lots_v1199c120').length"), 2)
        page.evaluate("()=>c120Edit()")
        self.assertEqual(page.locator(".c117Qty").input_value(), "5")

    def test_c120_partial_resume_keeps_original_breaks_and_work_intervals(self):
        page = self.open_app()
        page.evaluate("""()=>{
          const row=(id,staff,start,end)=>({id,staff_id:staff,staff_name:staff,phase:'作業',start_at:`2026-11-12T${start}Z`,end_at:`2026-11-12T${end}Z`});
          const members=[row('A1','S1','00:00:05','00:30:00'),row('B1','S2','00:00:05','00:30:00'),row('A2','S1','00:45:00','01:30:00'),row('B2','S2','01:00:00','01:30:00'),row('A3','S1','01:45:00','02:00:07'),row('B3','S2','01:45:00','02:00:07')];
          const pauses=[
            {kind:'休憩',start_at:'2026-11-12T00:30:00Z',end_at:'2026-11-12T01:00:00Z',excluded_staff_ids:[],staff_ids:['S1','S2'],resumed_staff_ids:['S1','S2']},
            {kind:'中断',start_at:'2026-11-12T01:30:00Z',end_at:'2026-11-12T01:45:00Z',excluded_staff_ids:[],staff_ids:['S1','S2'],resumed_staff_ids:['S1','S2']}
          ];
          window.__h2.h2Members=async()=>JSON.parse(JSON.stringify(members));
          window.__h2.sel2=async()=>JSON.parse(JSON.stringify(pauses));
        }""")
        page.evaluate("()=>c117ReportPage('C120')")
        page.locator(".c117Qty").wait_for()
        self.assertEqual(page.locator('[data-c117-member]').count(), 3)
        page.locator(".c117Qty").fill("5")
        page.evaluate("()=>c120Review();c120SaveDraft()")
        payload = page.evaluate("()=>__calls.find(x=>x[0]==='hq_prep_report_save_v1199c120')[1].p_report")
        self.assertEqual([(m['start_at'],m['end_at']) for m in payload['members']], [
            ('2026-11-12T09:00:05+09:00','2026-11-12T09:30:00+09:00'),
            ('2026-11-12T09:45:00+09:00','2026-11-12T11:00:07+09:00'),
            ('2026-11-12T09:00:05+09:00','2026-11-12T11:00:07+09:00'),
        ])
        self.assertEqual([(b['kind'],b['start_at'],b['end_at'],b['excluded_staff_ids']) for b in payload['breaks']], [
            ('休憩','2026-11-12T09:30:00+09:00','2026-11-12T10:00:00+09:00',[]),
            ('中断','2026-11-12T10:30:00+09:00','2026-11-12T10:45:00+09:00',[]),
        ])
        page.evaluate("()=>c117ReportPage('C120')")
        page.locator(".c117Qty").wait_for()
        self.assertEqual(page.locator('[data-c117-member]').count(), 3)
        self.assertEqual(page.locator('[data-c117-break]').count(), 2)

    def test_c120_review_shows_breaks_and_edit_clears_submit(self):
        page = self.open_app()
        self.open_new(page)
        page.evaluate("()=>c120Review()")
        self.assertIn("休憩・中断", page.locator("body").inner_text())
        page.evaluate("()=>c120SaveDraft()")
        page.locator("#c120Submit").wait_for()
        page.evaluate("()=>c120Edit()")
        self.assertEqual(page.locator("#c120Submit").count(), 0)


if __name__ == "__main__":
    unittest.main()
