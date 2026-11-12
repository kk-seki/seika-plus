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
            {id:'L2',qr_key:'HQ-L2',lot_no:'LOT-2',item_name:'キャベツ',unit:'kg',available_qty:12,origin:'群馬',supplier:'生産者',cooperative_name:'',details:''}
          ];
          const work={id:'W1',kind:'下処理',status:'完了',confirm_status:'未確定',updated_at:'2026-11-12T01:00:00Z',work_date:'2026-11-12',place:'作業台A',started_at:'2026-11-12T00:00:05Z',ended_at:'2026-11-12T02:00:07Z',outputs:[{master_id:'P1',name:'1/4芯',yield_kg:30}]};
          const members=[{id:'M1',work_id:'W1',staff_id:'S1',staff_name:'佐藤',phase:'作業',start_at:'2026-11-12T00:00:05Z',end_at:'2026-11-12T00:30:00Z'}, {id:'M2',work_id:'W1',staff_id:'S1',staff_name:'佐藤',phase:'作業',start_at:'2026-11-12T01:00:00Z',end_at:'2026-11-12T02:00:07Z'}];
          const mats=[{id:'WM1',work_id:'W1',lot_id:'L1',lot_no:'LOT-1',item_name:'キャベツ',unit:'case',pack_kg:10,qty:null}];
          window.__h2.num2=v=>{const s=String(v??'').trim();return s===''?NaN:Number(s)}; window.__h2.h2Loading=()=>'<div>読み込んでいます…</div>'; window.__h2.h2CanPrep=()=>['admin','hq_worker','hq_prep'].includes(db.role); window.__h2.h2CanBoss=()=>['admin','hq_worker'].includes(db.role); window.__h2.h2Err=e=>String(e?.message||e||'');
          window.__h2.h2UsedKg=mats=>{let kg=0,unknown=false;for(const m of mats){const q=Number(m.qty),v=m.unit==='kg'?q:q*Number(m.pack_kg);if(!Number.isFinite(v))unknown=true;else kg+=v}return {kg,unknown}};
          window.__h2.r2=async(name,args)=>{window.__calls.push([name,args]); if(name==='hq_prep_available_lots_v1199c117') return JSON.parse(JSON.stringify(lots)); if(name==='hq_prep_report_save_v1199c117') return window.__rpc ? window.__rpc(name,args) : {ok:true,id:args.p_work_id||'NEW',updated_at:'2026-11-12T03:00:00Z'}; throw new Error('unexpected rpc '+name)};
          window.__h2.h2Staff=async()=>JSON.parse(JSON.stringify(staff)); window.__h2.h2Places=async()=>[{name:'作業台A'},{name:'作業台B'}]; window.__h2.h2Masters=async()=>JSON.parse(JSON.stringify(masters));
          window.__h2.h2Works=async q=>q.includes('id=eq.W1')?[JSON.parse(JSON.stringify(work))]:[JSON.parse(JSON.stringify(work))];
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
        page.locator('input[name="c117Master"][value="P1"]').check()
        page.evaluate("()=>c117MasterToggle()")
        page.select_option("#c117LotSelect", "L1")
        page.evaluate("()=>c117AddMaterialFromSelect()")
        page.locator(".c117Qty").fill("5")
        page.locator('[data-c117-output="P1"] input').fill("40")
        page.select_option("#c117StaffSelect", "S1")
        page.evaluate("()=>c117AddMemberFromSelect()")

    def test_permissions_and_new_page_has_all_one_page_sections(self):
        page = self.open_app("viewer")
        page.evaluate("()=>c117ReportPage(null)")
        self.assertIn("権限", page.evaluate("()=>__alerts.at(-1)"))
        editor = self.open_app("hq_prep")
        self.open_new(editor)
        text = editor.locator("body").inner_text()
        for heading in ("作業の基本", "仕掛品", "原料", "出来高・廃棄", "作業者", "休憩・中断", "日本時間"):
            self.assertIn(heading, text)
        self.assertIn("産地：茨城", text)
        self.assertIn("仕入先：せき", text)
        self.assertIn("単協：JA", text)
        self.assertIn("ロット詳細：冷蔵", text)

    def test_all_only_auto_fills_and_live_totals_and_negative_waste_rejected(self):
        page = self.open_app()
        self.open_new(page)
        page.select_option(".c117Mode", "all")
        page.evaluate("()=>c117MaterialChange('L1')")
        self.assertEqual(page.locator(".c117Qty").input_value(), "5")
        self.assertIn("使用合計 50 kg", page.locator("#c117Totals").inner_text())
        self.assertIn("廃棄 10 kg", page.locator("#c117Totals").inner_text())
        page.locator('[data-c117-output="P1"] input').fill("51")
        page.evaluate("()=>c117Input()")
        self.assertIn("出来高合計は使用合計を超えられません", page.locator("#c117Totals").inner_text())
        page.evaluate("()=>c117ReportSave()")
        self.assertEqual(page.evaluate("()=>__calls.filter(x=>x[0]==='hq_prep_report_save_v1199c117').length"), 0)
        self.assertIn("超えられません", page.locator("#c117Error").inner_text())
        page.locator(".c117Mode").select_option("partial")
        page.evaluate("()=>c117MaterialChange('L1')")
        page.locator(".c117Qty").fill("")
        page.locator('[data-c117-output="P1"] input').fill("10")
        page.evaluate("()=>c117ReportSave()")
        self.assertIn("一部使用数", page.locator("#c117Error").inner_text())

    def test_staff_material_qr_do_not_mix_and_break_members_are_sent_preserved(self):
        page = self.open_app()
        self.open_new(page)
        page.evaluate("()=>c117OpenMaterialQr()")
        page.wait_for_function("()=>typeof __scanner==='function'")
        page.evaluate("()=>__scanner('HQST-S2')")
        page.wait_for_selector("#h2ScanNotice")
        self.assertIn("スタッフ", page.locator("#h2ScanNotice").inner_text())
        self.assertIn("原料の貼り紙のQR", page.locator("#h2ScanNotice").inner_text())
        page.evaluate("()=>c117OpenStaffQr()")
        page.wait_for_function("()=>typeof __scanner==='function'")
        page.evaluate("()=>__scanner('HQ-L2')")
        page.wait_for_selector("#h2ScanNotice")
        self.assertIn("原料の貼り紙のQRを読みました", page.locator("#h2ScanNotice").inner_text())
        page.evaluate("()=>c117OpenStaffQr()")
        page.evaluate("()=>__scanner('HQST-S2')")
        page.wait_for_function("()=>document.querySelectorAll('[data-c117-member]').length===2")
        page.evaluate("()=>c117AddBreak()")
        page.locator("[data-c117-break] .c117BreakStart").fill("2026-11-12T09:30")
        page.locator("[data-c117-break] .c117BreakEnd").fill("2026-11-12T09:45")
        page.locator("[data-c117-break] input[type=checkbox]").first.check()
        page.evaluate("()=>c117ReportSave()")
        page.wait_for_function("()=>__calls.filter(x=>x[0]==='hq_prep_report_save_v1199c117').length===1")
        payload = page.evaluate("()=>__calls.find(x=>x[0]==='hq_prep_report_save_v1199c117')[1].p_report")
        self.assertEqual(payload["members"][0]["start_at"], "2026-11-12T09:00:00+09:00")
        self.assertEqual(payload["breaks"][0]["excluded_staff_ids"], ["S1"])

    def test_edit_preserves_old_null_quantity_and_uses_updated_at(self):
        page = self.open_app()
        page.evaluate("()=>c117ReportPage('W1')")
        page.locator(".c117Qty").wait_for()
        self.assertEqual(page.locator(".c117Qty").input_value(), "")
        self.assertEqual(page.locator("[data-c117-member]").count(), 1)  # existing pause normalizes split work intervals
        self.assertEqual(page.locator("#c117Started").input_value(), "2026-11-12T09:00:05")
        self.assertEqual(page.locator("#c117Ended").input_value(), "2026-11-12T11:00:07")
        page.locator(".c117Qty").fill("5")
        page.evaluate("()=>c117ReportSave()")
        page.wait_for_function("()=>__calls.filter(x=>x[0]==='hq_prep_report_save_v1199c117').length===1")
        args = page.evaluate("()=>__calls.find(x=>x[0]==='hq_prep_report_save_v1199c117')[1]")
        self.assertEqual(args["p_work_id"], "W1")
        self.assertEqual(args["p_expected_updated_at"], "2026-11-12T01:00:00Z")
        self.assertEqual(len(args["p_report"]["members"]), 1)
        self.assertEqual(args["p_report"]["started_at"], "2026-11-12T09:00:05+09:00")
        self.assertEqual(args["p_report"]["ended_at"], "2026-11-12T11:00:07+09:00")

    def test_network_retry_preserves_operation_payload_and_restores_pending_form(self):
        page = self.open_app()
        self.open_new(page)
        page.evaluate("""()=>{let count=0;window.__rpc=async()=>{if(count++===0)throw new Error('late network');return {ok:true,id:'N'}}}""")
        page.evaluate("()=>c117ReportSave()")
        page.wait_for_function("()=>__calls.filter(x=>x[0]==='hq_prep_report_save_v1199c117').length===1")
        first = page.evaluate("()=>__calls.filter(x=>x[0]==='hq_prep_report_save_v1199c117')[0][1]")
        page.evaluate("()=>c117ReportSave()")
        page.wait_for_function("()=>__calls.filter(x=>x[0]==='hq_prep_report_save_v1199c117').length===2")
        second = page.evaluate("()=>__calls.filter(x=>x[0]==='hq_prep_report_save_v1199c117')[1][1]")
        self.assertEqual(first["p_operation_id"], second["p_operation_id"])
        changed = self.open_app()
        self.open_new(changed)
        changed.evaluate("""()=>{window.__rpc=async()=>{throw new Error('late network')}}""")
        changed.evaluate("()=>c117ReportSave()")
        changed.wait_for_function("()=>__calls.filter(x=>x[0]==='hq_prep_report_save_v1199c117').length===1")
        one = changed.evaluate("()=>__calls.filter(x=>x[0]==='hq_prep_report_save_v1199c117')[0][1]")
        changed.locator(".c117Qty").fill("4")
        changed.evaluate("()=>c117ReportSave()")
        changed.wait_for_function("()=>__calls.filter(x=>x[0]==='hq_prep_report_save_v1199c117').length===2")
        two = changed.evaluate("()=>__calls.filter(x=>x[0]==='hq_prep_report_save_v1199c117')[1][1]")
        self.assertEqual(one["p_operation_id"], two["p_operation_id"])
        self.assertEqual(two["p_report"]["materials"][0]["qty"], 5)
        changed.evaluate("()=>c117ReportList()")
        changed.evaluate("()=>c117ReportPage(null)")
        changed.locator(".c117Qty").wait_for()
        self.assertEqual(changed.locator(".c117Qty").input_value(), "5")
        self.assertEqual(changed.locator('[data-c117-output="P1"] input').input_value(), "40")
        self.assertEqual(changed.locator("#c117Place").input_value(), "作業台A")
        changed.evaluate("()=>c117ReportSave()")
        self.assertEqual(changed.evaluate("()=>__calls.filter(x=>x[0]==='hq_prep_report_save_v1199c117')[2][1]"), one)

    def test_known_database_rejection_allows_corrected_payload_with_new_operation(self):
        for rejection in ("result", "sql_error"):
            with self.subTest(rejection=rejection):
                page = self.open_app()
                self.open_new(page)
                page.evaluate("""kind=>{window.__rpc=async()=>{
                  if(kind==='sql_error')throw new Error(JSON.stringify({code:'P0001',message:'原料の在庫が不足しています'}));
                  return {ok:false,conflict:true,message:'他の操作で内容が変わりました'};
                }}""", rejection)
                page.evaluate("()=>c117ReportSave()")
                first = page.evaluate("()=>__calls.find(x=>x[0]==='hq_prep_report_save_v1199c117')[1]")
                self.assertEqual(page.locator(".c117Qty").input_value(), "5")
                page.locator(".c117Qty").fill("4")
                page.evaluate("()=>{window.__rpc=async()=>({ok:true,id:'NEW'})}")
                page.evaluate("()=>c117ReportSave()")
                second = page.evaluate("()=>__calls.filter(x=>x[0]==='hq_prep_report_save_v1199c117')[1][1]")
                self.assertNotEqual(first["p_operation_id"], second["p_operation_id"])
                self.assertEqual(second["p_report"]["materials"][0]["qty"], 4)

    def test_interleaved_staff_break_intervals_restore_before_break_change_or_removal(self):
        for action in ("keep", "change", "remove"):
            with self.subTest(action=action):
                page = self.open_app()
                page.evaluate("""()=>{
                  const row=(id,staff,start,end)=>({id,staff_id:staff,staff_name:staff,phase:'作業',start_at:`2026-11-12T${start}Z`,end_at:`2026-11-12T${end}Z`});
                  window.__h2.h2Members=async()=>[
                    row('A1','S1','00:00:05','00:30:00'),
                    row('B1','S2','00:00:05','00:30:00'),
                    row('A2','S1','00:45:00','02:00:07'),
                    row('B2','S2','01:00:00','02:00:07')
                  ];
                  window.__h2.sel2=async()=>[{kind:'休憩',start_at:'2026-11-12T00:30:00Z',end_at:'2026-11-12T01:00:00Z',excluded_staff_ids:[],resumed_staff_ids:['S1','S2']}];
                }""")
                page.evaluate("()=>c117ReportPage('W1')")
                page.locator(".c117Qty").wait_for()
                self.assertEqual(page.locator("[data-c117-member]").count(), 2)
                self.assertEqual(page.locator(".c117MemberStart").evaluate_all("els=>els.map(el=>el.value)"), ["2026-11-12T09:00:05"] * 2)
                self.assertEqual(page.locator(".c117MemberEnd").evaluate_all("els=>els.map(el=>el.value)"), ["2026-11-12T11:00:07"] * 2)
                if action == "remove":
                    page.evaluate("()=>c117RemoveBreak(0)")
                elif action == "change":
                    page.locator(".c117BreakStart").fill("2026-11-12T09:15")
                    page.locator(".c117BreakEnd").fill("2026-11-12T09:30")
                page.locator(".c117Qty").fill("5")
                page.evaluate("()=>c117ReportSave()")
                payload = page.evaluate("()=>__calls.find(x=>x[0]==='hq_prep_report_save_v1199c117')[1].p_report")
                self.assertEqual(len(payload["members"]), 2)
                self.assertEqual([m["start_at"] for m in payload["members"]], ["2026-11-12T09:00:05+09:00"] * 2)
                self.assertEqual([m["end_at"] for m in payload["members"]], ["2026-11-12T11:00:07+09:00"] * 2)
                if action == "remove":
                    self.assertEqual(payload["breaks"], [])
                else:
                    self.assertEqual(payload["breaks"][0]["start_at"], "2026-11-12T09:15:00+09:00" if action == "change" else "2026-11-12T09:30:00+09:00")

    def test_allowed_pair_duplicate_staff_rows_camera_stop_and_pause_load_failure(self):
        page = self.open_app()
        self.open_new(page)
        page.locator('input[name="c117Master"][value="P2"]').check()
        page.evaluate("()=>c117MasterToggle()")
        self.assertEqual(page.locator('[data-c117-output]').count(), 2)
        page.locator('input[name="c117Master"][value="P3"]').check()
        page.evaluate("()=>c117MasterToggle()")
        self.assertFalse(page.locator('input[name="c117Master"][value="P3"]').is_checked())
        page.select_option("#c117StaffSelect", "S1")
        page.evaluate("()=>c117AddMemberFromSelect()")
        self.assertEqual(page.locator('[data-c117-member][data-c117-member="S1"]').count(), 2)
        row_id = page.locator('[data-c117-member][data-c117-member="S1"]').nth(1).get_attribute("data-row-id")
        page.evaluate("id=>c117RemoveMember(id)", row_id)
        self.assertEqual(page.locator('[data-c117-member][data-c117-member="S1"]').count(), 1)
        page.evaluate("()=>c117OpenMaterialQr()")
        page.wait_for_function("()=>typeof __scanner==='function'")
        before = page.evaluate("()=>__stops||0")
        page.evaluate("()=>__scanner('HQ-L2')")
        page.wait_for_function("()=>document.querySelectorAll('[data-c117-material]').length===2")
        self.assertGreater(page.evaluate("()=>__stops||0"), before)
        page.evaluate("()=>c117StopQr('c117MaterialReader')")
        self.assertGreater(page.evaluate("()=>__stops||0"), before)
        broken = self.open_app()
        broken.evaluate("()=>{window.__h2.sel2=async()=>{throw new Error('pause unavailable')}}")
        broken.evaluate("()=>c117ReportPage('W1')")
        broken.locator("text=pause unavailable").wait_for()
        self.assertEqual(broken.locator("#c117Save").count(), 0)

    def test_save_returns_to_work_page_and_home_wrapper_uses_lexical_binding(self):
        page = self.open_app()
        page.evaluate("()=>hqPrepHome()")
        page.locator("#c117HomeLinks").wait_for()
        self.open_new(page)
        page.evaluate("()=>c117ReportSave()")
        page.wait_for_function("()=>currentScreen==='hqWorkPage'")
        self.assertGreater(page.locator("#c117WorkLink").count(), 0)


if __name__ == "__main__":
    unittest.main()
