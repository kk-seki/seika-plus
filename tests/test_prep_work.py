"""c116下処理の訂正・休憩・同時製造をローカル通信だけで確認します。"""
import functools
import re
import threading
import unittest
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

from playwright.sync_api import sync_playwright

from test_excel_output import read_xlsx


ROOT = Path(__file__).resolve().parents[1]
MOCK = (ROOT / "tests" / "mock_hq.js").read_text(encoding="utf-8")

SETUP = r"""()=>{
  const iso=n=>new Date(Date.now()-n*60000).toISOString();
  const clone=x=>JSON.parse(JSON.stringify(x));
  const T=__T;
  const w=id=>T.hq_works_v1500.find(x=>x.id===id);
  const members=id=>T.hq_work_members_v1500.filter(x=>x.work_id===id);
  T.hq_works_v1500.forEach(x=>{x.pause_kind=x.pause_kind||'';x.updated_at=x.updated_at||iso(2)});
  Object.assign(w('W5'),{
    confirm_status:'確定',stock_applied:true,updated_at:iso(3),
    outputs:[{master_id:'PM4',name:'人参細切り',expiry_days:2,yield_kg:40}],
    history:[]
  });
  Object.assign(w('W3'),{
    status:'入力待ち',confirm_status:'未確定',updated_at:iso(3),
    outputs:[
      {master_id:'PM1',name:'キャベツ千切り',expiry_days:2,yield_kg:40},
      {master_id:'PM2',name:'キャベツざく切り',expiry_days:2,yield_kg:32}
    ]
  });
  T.hq_prep_masters_v1500.push(
    {id:'PM4',name:'人参細切り',item_name:'人参',default_pack_kg:5,expiry_days:2,active:true},
    {id:'PMC',name:'1/4芯',item_name:'キャベツ',default_pack_kg:5,expiry_days:2,active:true},
    {id:'PML',name:'1/4葉',item_name:'キャベツ',default_pack_kg:5,expiry_days:2,active:true}
  );
  T.hq_lots_v1400.find(x=>x.id==='L3').status='在庫あり';
  T.hq_work_pauses_v1199c116=[];
  window.__calls=[];window.__alerts=[];window.__confirms=[];
  window.alert=m=>__alerts.push(String(m));window.confirm=m=>(__confirms.push(String(m)),true);
  const selectBase=qrSelect;
  qrSelect=async(t,q)=>{
    if(t==='hq_work_pauses_v1199c116')return clone(T.hq_work_pauses_v1199c116.filter(p=>!q.includes('end_at=is.null')||!p.end_at));
    return selectBase(t,q);
  };
  const startWork=(a,modern)=>{
    const id='W'+(T.hq_works_v1500.length+1),now=new Date().toISOString();
    const masterIds=modern?a.p_master_ids:[a.p_master_id];
    const ms=masterIds.map(id=>T.hq_prep_masters_v1500.find(m=>m.id===id)).filter(Boolean);
    const row={id,kind:a.p_kind,status:'作業中',confirm_status:'未確定',work_date:ymdKey(new Date()),
      raw_item_name:ms[0]?.item_name||null,product_name:ms.map(m=>m.name).join('・'),prep_master_id:ms[0]?.id||null,
      outputs:ms.length>1?ms.map(m=>({master_id:m.id,name:m.name,expiry_days:m.expiry_days,yield_kg:0})):[],
      task_name:a.p_task_name||null,place:a.p_place,started_at:now,updated_at:now,pause_kind:''};
    T.hq_works_v1500.push(row);
    (a.p_lot_ids||[]).forEach((lotId,i)=>{const l=T.hq_lots_v1400.find(x=>x.id===lotId);T.hq_work_materials_v1500.push({id:'NM'+id+i,work_id:id,lot_id:lotId,lot_no:l.lot_no,item_name:l.item_name,unit:l.unit,pack_kg:10})});
    (a.p_staff_ids||[]).forEach((staffId,i)=>{const s=T.hq_staff_v1500.find(x=>x.id===staffId);T.hq_work_members_v1500.push({id:'NP'+id+i,work_id:id,staff_id:staffId,staff_name:s.name,team:s.team,phase:'作業',start_at:now})});
    return {id};
  };
  const base=callRpc;
  callRpc=async(n,a)=>{
    __calls.push({n,a:clone(a)});
    if(window.__rpcFailOnce){const fail=window.__rpcFailOnce;window.__rpcFailOnce=null;throw new Error(fail)}
    if(n==='hq_work_start_v1199c116')return startWork(a,true);
    if(n==='hq_work_start_v1500')return startWork(a,false);
    if(n==='hq_work_save_inputs_v1199c116'){
      const x=w(a.p_work_id);x.outputs=clone(a.p_outputs);x.yield_kg=a.p_outputs.reduce((s,o)=>s+Number(o.yield_kg),0);x.waste_kg=a.p_waste_kg;x.inputs_saved_at=new Date().toISOString();return {ok:true};
    }
    if(n==='hq_work_pause_v1199c116'){
      const x=w(a.p_work_id), paused=members(x.id).filter(m=>!m.end_at&&m.phase==='作業'&&!a.p_excluded_staff_ids.includes(m.staff_id));
      paused.forEach(m=>m.end_at=new Date().toISOString());x.pause_kind=a.p_kind;
      T.hq_work_pauses_v1199c116.push({id:'P'+T.hq_work_pauses_v1199c116.length,operation_id:a.p_operation_id,work_id:x.id,kind:a.p_kind,start_at:new Date().toISOString(),end_at:null,staff_ids:paused.map(m=>m.staff_id),resumed_staff_ids:[],excluded_staff_ids:clone(a.p_excluded_staff_ids)});return {ok:true};
    }
    if(n==='hq_work_resume_v1199c116'){
      const x=w(a.p_work_id), conflict=T.hq_work_members_v1500.some(m=>a.p_staff_ids.includes(m.staff_id)&&!m.end_at&&m.work_id!==x.id);
      if(conflict)throw new Error('別の作業中の人は再開できません');
      a.p_staff_ids.forEach((sid,i)=>{const s=T.hq_staff_v1500.find(q=>q.id===sid);T.hq_work_members_v1500.push({id:'R'+Date.now()+i,work_id:x.id,staff_id:sid,staff_name:s.name,team:s.team,phase:'作業',start_at:new Date().toISOString()})});
      const p=T.hq_work_pauses_v1199c116.filter(q=>q.work_id===x.id&&!q.end_at).at(-1);if(p){p.resumed_staff_ids=[...new Set([...p.resumed_staff_ids,...a.p_staff_ids])];if(p.staff_ids.every(sid=>p.resumed_staff_ids.includes(sid))){p.end_at=new Date().toISOString();x.pause_kind=''}}return {ok:true};
    }
    if(n==='hq_work_break_add_v1199c116'){
      T.hq_work_pauses_v1199c116.push({id:'B'+T.hq_work_pauses_v1199c116.length,operation_id:a.p_operation_id,work_id:a.p_work_id,kind:'休憩',start_at:a.p_start,end_at:a.p_end,staff_ids:members(a.p_work_id).filter(m=>m.phase==='作業'&&!a.p_excluded_staff_ids.includes(m.staff_id)).map(m=>m.staff_id),resumed_staff_ids:[],excluded_staff_ids:clone(a.p_excluded_staff_ids)});return {ok:true};
    }
    if(n==='hq_prep_correct_v1199c116'){
      const x=w(a.p_work_id);if(a.p_expected_updated_at!==x.updated_at)throw new Error('ほかの画面で更新されています');
      x.waste_kg=a.p_waste_kg;x.outputs=clone(a.p_outputs);x.yield_kg=a.p_outputs.reduce((s,o)=>s+Number(o.yield_kg),0);x.updated_at=new Date().toISOString();x.history.push({at:x.updated_at,by:'本社 一郎',action:'訂正',reason:a.p_reason,before:{},after:{}});return {ok:true};
    }
    return base(n,a);
  };
  window.__reader=null;
  window.Html5Qrcode=class{constructor(){}async start(_c,_cfg,fn){window.__reader=fn}async stop(){}clear(){}};
}"""


class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, *_args):
        pass


class PrepWorkTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(QuietHandler, directory=str(ROOT)))
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()
        cls.url = f"http://127.0.0.1:{cls.server.server_port}/index.html"
        cls.local = urlparse(cls.url).netloc
        cls.pw = sync_playwright().start()
        cls.browser = cls.pw.chromium.launch()

    @classmethod
    def tearDownClass(cls):
        cls.browser.close()
        cls.pw.stop()
        cls.server.shutdown()
        cls.server.server_close()

    def app(self, role="admin"):
        context = self.browser.new_context(service_workers="block", timezone_id="Asia/Tokyo", viewport={"width": 820, "height": 1180})
        self.addCleanup(context.close)
        context.route("**/*", lambda route: route.continue_() if urlparse(route.request.url).netloc == self.local else route.abort())
        page = context.new_page()
        errors = []
        page.on("pageerror", lambda error: errors.append(str(error)))
        self.addCleanup(lambda: self.assertEqual(errors, [], "browser errors"))
        page.goto(self.url, wait_until="load")
        page.wait_for_function("()=>typeof hqWorkPage==='function' && typeof h2CorrectPrepPage==='function'")
        page.wait_for_timeout(700)
        page.evaluate(MOCK, role)
        page.evaluate(SETUP)
        return page

    @staticmethod
    def calls(page, name):
        return page.evaluate("name=>__calls.filter(c=>c.n===name)", name)

    def work_page(self, page, work_id):
        page.evaluate("id=>hqWorkPage(id)", work_id)
        page.wait_for_timeout(80)

    def test_correction_allowed_only_for_admin_and_hqworker_after_completion(self):
        for role in ("admin", "hq_worker"):
            page = self.app(role)
            self.work_page(page, "W5")
            page.get_by_role("button", name="使用原料・廃棄・出来高を訂正する", exact=True).click()
            page.locator("#c116CorrectWaste").wait_for()
            self.assertEqual(page.locator(".c116CorrectMaterial").count(), 1)
            self.assertEqual(page.locator(".c116CorrectOutput").count(), 1)
        page = self.app("hq_prep")
        self.work_page(page, "W5")
        self.assertEqual(page.get_by_role("button", name="使用原料・廃棄・出来高を訂正する", exact=True).count(), 0)
        page.evaluate("()=>h2CorrectPrepPage('W5')")
        self.assertEqual(page.locator("#c116CorrectWaste").count(), 0)

    def test_correction_validates_and_retries_same_operation_after_concurrency_error(self):
        page = self.app()
        self.work_page(page, "W5")
        page.get_by_role("button", name="使用原料・廃棄・出来高を訂正する", exact=True).click()
        page.locator("#c116CorrectReason").wait_for()
        page.get_by_role("button", name="訂正を保存する", exact=True).click()
        self.assertIn("理由", page.evaluate("()=>__alerts.at(-1)"))
        page.locator("#c116CorrectReason").fill("棚卸しで判明")
        page.get_by_role("button", name="使用原料の行を追加", exact=True).click()
        page.locator(".c116CorrectMaterial").nth(1).locator("select").select_option("L3")
        page.locator(".c116CorrectMaterial").nth(1).locator("input").fill("1")
        page.get_by_role("button", name="訂正を保存する", exact=True).click()
        self.assertIn("同じロット", page.evaluate("()=>__alerts.at(-1)"))
        page.locator(".c116CorrectMaterial").nth(1).get_by_role("button", name="この行を外す").click()
        page.locator(".c116CorrectOutput").fill("-1")
        page.get_by_role("button", name="訂正を保存する", exact=True).click()
        self.assertIn("0以上", page.evaluate("()=>__alerts.at(-1)"))
        page.locator(".c116CorrectOutput").fill("41.5")
        page.evaluate("()=>window.__rpcFailOnce='ほかの画面で更新されています'")
        page.get_by_role("button", name="訂正を保存する", exact=True).click()
        page.wait_for_function("()=>__calls.filter(c=>c.n==='hq_prep_correct_v1199c116').length===1")
        first = self.calls(page, "hq_prep_correct_v1199c116")[0]["a"]
        self.assertEqual(first["p_expected_updated_at"], page.evaluate("()=>__T.hq_works_v1500.find(w=>w.id==='W5').updated_at"))
        self.assertEqual(first["p_materials"], [{"lot_id": "L3", "qty": 5}])
        self.assertEqual(first["p_outputs"], [{"master_id": "PM4", "yield_kg": 41.5}])
        self.assertEqual(first["p_reason"], "棚卸しで判明")
        self.assertEqual(page.locator("#c116CorrectReason").input_value(), "棚卸しで判明")
        page.get_by_role("button", name="訂正を保存する", exact=True).click()
        page.wait_for_function("()=>__calls.filter(c=>c.n==='hq_prep_correct_v1199c116').length===2")
        second = self.calls(page, "hq_prep_correct_v1199c116")[1]["a"]
        self.assertEqual(second["p_operation_id"], first["p_operation_id"])
        self.assertIn("入力を訂正しました", page.locator("body").inner_text())

    def test_pause_excludes_only_checked_person_then_conflict_resume_keeps_form_for_retry(self):
        page = self.app("hq_prep")
        self.work_page(page, "W1")
        page.get_by_role("button", name="休憩", exact=True).click()
        page.locator(".c116PausePerson").first.wait_for()
        page.locator(".c116PausePerson[value='S1']").check()
        page.get_by_role("button", name="選んだ人を除いて休憩", exact=True).click()
        page.wait_for_function("()=>__calls.some(c=>c.n==='hq_work_pause_v1199c116')")
        pause = self.calls(page, "hq_work_pause_v1199c116")[0]["a"]
        self.assertEqual((pause["p_kind"], pause["p_excluded_staff_ids"]), ("休憩", ["S1"]))
        self.assertEqual(page.evaluate("()=>__T.hq_work_members_v1500.find(m=>m.work_id==='W1'&&m.staff_id==='S1').end_at"), None)
        self.assertIsNotNone(page.evaluate("()=>__T.hq_work_members_v1500.find(m=>m.work_id==='W1'&&m.staff_id==='S2').end_at"))
        page.evaluate("()=>{const m=__T.hq_work_members_v1500.find(x=>x.work_id==='W4');m.staff_id='S2';m.staff_name='鈴木 美咲'}")
        page.get_by_role("button", name="休憩から再開する", exact=True).click()
        page.locator(".c116PausePerson[value='S2']").wait_for()
        page.get_by_role("button", name="選んだ人で再開", exact=True).click()
        page.wait_for_function("()=>__calls.filter(c=>c.n==='hq_work_resume_v1199c116').length===1")
        self.assertEqual(page.locator(".c116PausePerson[value='S2']").is_checked(), True)
        self.assertIn("別の作業中", page.evaluate("()=>__alerts.at(-1)"))
        first = self.calls(page, "hq_work_resume_v1199c116")[0]["a"]
        page.evaluate("()=>__T.hq_work_members_v1500.find(x=>x.work_id==='W4').end_at=new Date().toISOString()")
        page.get_by_role("button", name="選んだ人で再開", exact=True).click()
        page.wait_for_function("()=>__calls.filter(c=>c.n==='hq_work_resume_v1199c116').length===2")
        self.assertEqual(self.calls(page, "hq_work_resume_v1199c116")[1]["a"]["p_operation_id"], first["p_operation_id"])

    def test_interruption_is_all_people_and_backdated_pause_sends_start_end_and_exclusions(self):
        page = self.app("hq_prep")
        self.work_page(page, "W1")
        page.get_by_role("button", name="中断（別の作業へ）", exact=True).click()
        self.assertEqual(page.locator(".c116PausePerson").count(), 0)
        page.get_by_role("button", name="全員の作業を中断", exact=True).click()
        page.wait_for_function("()=>__calls.some(c=>c.n==='hq_work_pause_v1199c116')")
        args = self.calls(page, "hq_work_pause_v1199c116")[0]["a"]
        self.assertEqual((args["p_kind"], args["p_excluded_staff_ids"]), ("中断", []))
        page.get_by_role("button", name="押し忘れた休憩を入力する", exact=True).click()
        page.locator("#c116BreakStart").fill("2026-11-10T10:00")
        page.locator("#c116BreakEnd").fill("2026-11-10T10:15")
        page.locator(".c116PausePerson[value='S1']").check()
        page.get_by_role("button", name="休憩時間を保存", exact=True).click()
        page.wait_for_function("()=>__calls.some(c=>c.n==='hq_work_break_add_v1199c116')")
        added = self.calls(page, "hq_work_break_add_v1199c116")[0]["a"]
        self.assertEqual(added["p_excluded_staff_ids"], ["S1"])
        self.assertLess(added["p_start"], added["p_end"])

    def test_pair_start_uses_new_rpc_and_single_start_keeps_old_rpc(self):
        page = self.app("hq_prep")
        page.evaluate("()=>hqPrepNew('下処理')")
        page.locator("#h2NwBody select").first.wait_for()
        page.locator("#h2NwBody select").first.select_option("L1")
        page.get_by_role("button", name="1/4芯・1/4葉を同時に作る", exact=True).click()
        page.get_by_role("button", name="作業台A", exact=True).click()
        page.evaluate("()=>h2NwAddStaff('S1')")
        page.get_by_role("button", name="作業開始", exact=True).click()
        page.wait_for_function("()=>__calls.some(c=>c.n==='hq_work_start_v1199c116')")
        paired = self.calls(page, "hq_work_start_v1199c116")[0]["a"]
        self.assertEqual(paired["p_master_ids"], ["PMC", "PML"])
        self.assertEqual(paired["p_lot_ids"], ["L1"])
        self.assertEqual(paired["p_staff_ids"], ["S1"])
        page.evaluate("()=>hqPrepNew('下処理')")
        page.locator("#h2NwBody select").first.wait_for()
        page.locator("#h2NwBody select").first.select_option("L1")
        page.get_by_role("button", name="キャベツ千切り", exact=True).click()
        page.get_by_role("button", name="作業台A", exact=True).click()
        page.evaluate("()=>h2NwAddStaff('S1')")
        page.get_by_role("button", name="作業開始", exact=True).click()
        page.wait_for_function("()=>__calls.some(c=>c.n==='hq_work_start_v1500')")
        self.assertEqual(self.calls(page, "hq_work_start_v1500")[0]["a"]["p_master_id"], "PM1")

    def test_multiple_output_input_uses_new_save_rpc_and_total_yield(self):
        page = self.app("hq_prep")
        self.work_page(page, "W3")
        fields = page.locator(".h2OutputQty")
        self.assertEqual(fields.count(), 2)
        fields.nth(0).fill("12.5")
        fields.nth(1).fill("7.5")
        page.locator(".h2MatQty").fill("8")
        self.assertEqual(page.locator("#h2Waste").input_value(), "60")
        page.get_by_role("button", name="保存して ⑨ 清掃へ", exact=True).click()
        page.wait_for_function("()=>__calls.some(c=>c.n==='hq_work_save_inputs_v1199c116')")
        args = self.calls(page, "hq_work_save_inputs_v1199c116")[0]["a"]
        self.assertEqual(args["p_outputs"], [{"master_id": "PM1", "yield_kg": 12.5}, {"master_id": "PM2", "yield_kg": 7.5}])
        self.assertEqual(page.evaluate("()=>__T.hq_works_v1500.find(w=>w.id==='W3').yield_kg"), 20)

    def test_time_reports_allocate_shared_work_by_output_yield(self):
        page = self.app()
        result = page.evaluate("""()=>{
          const works=[{id:'P',kind:'下処理',work_date:'2026-11-01',confirm_status:'確定',yield_kg:100,
            outputs:[{name:'芯',yield_kg:25},{name:'葉',yield_kg:75}]}];
          const mem=[{work_id:'P',staff_id:'S1',staff_name:'A',team:'1班',phase:'作業',start_at:'2026-11-01T00:00:00Z',end_at:'2026-11-01T01:00:00Z'}];
          const time=__h2.workTimeSummary(works,mem).perTask;
          const compare=__h2.workCompare(works,mem).prod;
          return {core:time.get('下処理（芯）').min,leaf:time.get('下処理（葉）').min,
            ccore:compare.get('芯').get('S1').min,cleaf:compare.get('葉').get('S1').min,
            kg:compare.get('葉').get('S1').kg};
        }""")
        self.assertEqual(result, {"core": 15, "leaf": 45, "ccore": 15, "cleaf": 45, "kg": 75})


    def test_partial_resume_keeps_remaining_people_available(self):
        page = self.app("hq_prep")
        self.work_page(page, "W1")
        page.get_by_role("button", name="休憩", exact=True).click()
        page.locator(".c116PausePerson").first.wait_for()
        page.get_by_role("button", name="選んだ人を除いて休憩", exact=True).click()
        page.get_by_role("button", name="休憩から再開する", exact=True).click()
        page.locator(".c116PausePerson[value='S2']").uncheck()
        page.get_by_role("button", name="選んだ人で再開", exact=True).click()
        page.get_by_role("button", name="休憩から再開する", exact=True).wait_for()
        self.assertEqual(page.get_by_role("button", name="作業終了", exact=True).count(), 0)
        page.get_by_role("button", name="休憩から再開する", exact=True).click()
        page.locator(".c116PausePerson[value='S2']").wait_for()
        self.assertEqual(page.locator(".c116PausePerson[value='S1']").count(), 0)
        page.get_by_role("button", name="選んだ人で再開", exact=True).click()
        page.get_by_role("button", name="作業終了", exact=True).wait_for()
        calls = self.calls(page, "hq_work_resume_v1199c116")
        self.assertEqual([c["a"]["p_staff_ids"] for c in calls], [["S1"], ["S2"]])
        self.assertNotEqual(calls[0]["a"]["p_operation_id"], calls[1]["a"]["p_operation_id"])

    def test_confirmed_work_still_has_cancel_and_guides_match_permissions(self):
        page = self.app("hq_worker")
        page.evaluate("()=>hqPrepConfirmPage('W5')")
        page.get_by_role("button", name="訂正を保存する", exact=True).wait_for()
        page.get_by_text("この下処理を取り消す", exact=True).click()
        self.assertEqual(page.get_by_role("button", name="取り消す", exact=True).count(), 1)
        guides = page.evaluate("""()=>Object.fromEntries(['admin','hq_worker','hq_prep'].map(r=>[
          r,V195_ROLE_GUIDES[r].sections.map(s=>s.title)]))""")
        for role, titles in guides.items():
            self.assertIn("下処理で休憩・中断・再開する", titles)
            self.assertIn("キャベツ1/4芯・1/4葉を同時に作る", titles)
            self.assertEqual("下処理の使用原料・廃棄・出来高を訂正する" in titles, role != "hq_prep")

    def test_pause_preserves_unsaved_materials_and_correction_rejects_unsuccessful_result(self):
        page = self.app("hq_prep")
        self.work_page(page, "W1")
        page.locator("#c112Materials input").first.fill("9")
        page.get_by_role("button", name="休憩", exact=True).click()
        page.wait_for_function("()=>__alerts.length>0")
        self.assertIn("先に", page.evaluate("()=>__alerts.at(-1)"))
        self.assertEqual(page.locator(".c116PausePerson").count(), 0)
        page = self.app("hq_worker")
        page.evaluate("()=>h2CorrectPrepPage('W5')")
        page.locator("#c116CorrectReason").fill("訂正")
        page.evaluate("""()=>{const base=callRpc;callRpc=async(n,a)=>n==='hq_prep_correct_v1199c116'?
          {ok:false,conflict:true,message:'内容が変わりました'}:base(n,a)}""")
        page.get_by_role("button", name="訂正を保存する", exact=True).click()
        page.wait_for_function("()=>__alerts.includes('内容が変わりました')")
        self.assertEqual(page.locator("#c116CorrectReason").input_value(), "訂正")
        self.assertNotIn("入力を訂正しました", page.locator("body").inner_text())

    def report_fixture(self, page):
        page.evaluate("""()=>{
          __T.hq_works_v1500=[{id:'PAIR',kind:'下処理',task_name:'下処理',work_date:'2026-11-01',
            status:'完了',confirm_status:'確定',raw_item_name:'キャベツ',product_name:'1/4芯・1/4葉',
            prep_master_id:'PMC',expiry_days:3,started_at:'2026-11-01T00:00:00Z',inputs_saved_at:'2026-11-01T01:00:00Z',
            waste_kg:10,yield_kg:100,outputs:[{master_id:'PMC',name:'1/4芯',expiry_days:1,yield_kg:25},
              {master_id:'PML',name:'1/4葉',expiry_days:3,yield_kg:75}]}];
          __T.hq_work_members_v1500=[{id:'PAIR1',work_id:'PAIR',staff_id:'S1',staff_name:'仮の作業者',
            phase:'作業',start_at:'2026-11-01T00:00:00Z',end_at:'2026-11-01T00:20:00Z'},
            {id:'PAIR2',work_id:'PAIR',staff_id:'S1',staff_name:'仮の作業者',phase:'作業',
              start_at:'2026-11-01T00:30:00Z',end_at:'2026-11-01T01:00:00Z'}];
          __T.hq_work_materials_v1500=[{id:'PAIR_M',work_id:'PAIR',lot_id:'L1',lot_no:'仮ロット',
            item_name:'キャベツ',unit:'kg',qty:110}];
          __T.hq_work_pauses_v1199c116=[];
        }""")

    def test_actual_excel_downloads_have_individual_products_and_no_double_count(self):
        page = self.app("hq_worker")
        self.report_fixture(page)
        with page.expect_download() as event:
            page.evaluate("()=>h2ExcelOut('yield','2026-11')")
        self.assertIsNone(event.value.failure())
        sheets = read_xlsx(Path(event.value.path()).read_bytes())
        self.assertEqual(event.value.suggested_filename, "本社_歩留まり_2026年11月.xlsx")
        report = sheets["製造日報"]
        self.assertEqual([row[2] for row in report[1:]], ["1/4芯", "1/4葉"])
        self.assertEqual([row[5] for row in report[1:]], [25, 75])
        self.assertEqual([row[6] for row in report[1:]], [2.5, 7.5])
        self.assertEqual([row[-1] for row in report[1:]], [12.5, 37.5])
        self.assertEqual(sum(row[4] for row in report[1:]), 110)
        self.assertEqual(sum(row[-1] for row in report[1:]), 50)
        self.assertIn("9月", next(v for k, v in sheets.items() if "年度の推移" in k)[0])
        with page.expect_download() as event:
            page.evaluate("()=>h2ExcelOut('worktime','2026-11')")
        self.assertIsNone(event.value.failure())
        sheets = read_xlsx(Path(event.value.path()).read_bytes())
        tasks = sheets["作業ごと"]
        self.assertEqual([row[-1] for row in tasks[1:]], [12.5, 37.5])
        comparison = sheets["個人の比較（下処理）"]
        self.assertEqual([row[0] for row in comparison[1:]], ["1/4芯", "1/4葉"])
        self.assertEqual([row[4] for row in comparison[1:]], [12.5, 37.5])
        self.assertEqual([row[5] for row in comparison[1:]], [25, 75])
        self.assertEqual(sheets["人ごと"][1][3], 50)
        self.assertEqual(page.evaluate("()=>__alerts"), [])

    def test_real_label_pdf_has_separate_product_names_and_expiries(self):
        page = self.app("hq_worker")
        self.report_fixture(page)
        self.work_page(page, "PAIR")
        page.evaluate("""()=>{const input=document.createElement('input');input.id='h2LabelN';input.value='2';
          document.body.appendChild(input);window.__labelPages=[];
          const original=html2canvas;window.html2canvas=async(el,opts)=>{
            __labelPages.push({names:[...el.querySelectorAll('.nm')].map(n=>n.textContent),
              dates:[...el.querySelectorAll('td.ex')].map(n=>n.textContent),
              fits:[...el.querySelectorAll('.lab')].every(n=>n.scrollHeight<=n.clientHeight)});
            return original(el,opts)};
        }""")
        page.evaluate("()=>h2PrintLabel('PAIR',false)")
        link = page.locator("#h2PdfStatus a[download]")
        link.wait_for(timeout=30000)
        with page.expect_download() as event:
            link.click()
        data = Path(event.value.path()).read_bytes()
        self.assertIsNone(event.value.failure())
        self.assertTrue(data.startswith(b"%PDF-"))
        self.assertEqual(len(re.findall(rb"/Type\s*/Page\b", data)), 2)
        pages = page.evaluate("()=>__labelPages")
        self.assertEqual([p["names"] for p in pages], [["1/4芯"] * 2, ["1/4葉"] * 2])
        self.assertTrue(all("11月2日" in d for d in pages[0]["dates"]))
        self.assertTrue(all("11月4日" in d for d in pages[1]["dates"]))
        self.assertTrue(all(p["fits"] for p in pages))
        self.assertEqual(page.evaluate("()=>__alerts"), [])


if __name__ == "__main__":
    unittest.main()
