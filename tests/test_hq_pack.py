import functools
import json
import os
import subprocess
import threading
import unittest
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

from playwright.sync_api import sync_playwright

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
MOCK = (HERE / "mock_hq.js").read_text(encoding="utf-8")
C86 = ROOT / "js" / "17-c86-container-weight.js"

NODE_HARNESS = r"""
const vm=require('vm'),fs=require('fs');
const input=JSON.parse(fs.readFileSync(0,'utf8'));
const src=fs.readFileSync(input.path,'utf8');
const els=new Map(),listeners=[],calls=[],alerts=[],focus=[];let created=0;
function mk(id,props){const e={id,value:'',style:{},textContent:'',dataset:{},closest(){return null},querySelector(){return null},remove(){els.delete(id)},insertAdjacentHTML(pos,html){
  if(/id="c86Box"/.test(html)){const b=mk('c86Box',{style:{display:'none'}});if(/id="c86Kg"/.test(html))mk('c86Kg',{value:input.kg||''});if(/id="c86Pack"/.test(html))mk('c86Pack',{value:input.pack||''})}}};
  Object.assign(e,props||{});els.set(id,e);return e}
mk('c50ShipBox');mk('qrMoveDestination',{value:input.dest});
const store=new Map();
const ctx={console,JSON,Promise,Number,String,Math,Date,Object,Array,
 setTimeout:()=>0,esc:s=>String(s??''),
 localStorage:{getItem:k=>store.has(k)?store.get(k):null,setItem:(k,v)=>store.set(k,String(v))},
 alert:m=>alerts.push(String(m)),v161FocusField:(id,m)=>focus.push([id,m]),
 qrSelect:async()=>[input.lot],qrFindLot:async()=>input.lot,
 qrOperationLotPage:async()=>'page',
 qrSaveLotMovement:async(kind,q)=>ctx.callRpc('apply_qr_lot_operation',{p_movement_type:'出庫',p_destination:els.get('qrMoveDestination').value,p_operation_id:input.opId||'op1',p_qr_key:q,p_qty:3,p_operation_meta:input.meta||{}}),
 callRpc:async(name,args)=>{calls.push(JSON.parse(JSON.stringify({name,args})));return{ok:true}},
 document:{getElementById:id=>els.get(id)||null,createElement:()=>{created++;return mk('ask'+created)},body:{appendChild(){created++}},addEventListener:(t,f)=>listeners.push(f)}};
vm.createContext(ctx);ctx.window=ctx;
vm.runInContext(src,ctx);
(async()=>{
 const out={};
 for(const step of input.steps){
  if(step==='page')await ctx.qrOperationLotPage('out','Q1');
  else if(step==='save')out.result=await ctx.qrSaveLotMovement('out','Q1');
  else if(step.startsWith('dest:')){els.get('qrMoveDestination').value=step.slice(5);listeners.forEach(f=>f({target:els.get('qrMoveDestination')}))}
  else if(step==='rpc')out.result=await ctx.callRpc('apply_qr_lot_operation',{p_movement_type:'出庫',p_destination:input.dest,p_operation_id:'batch1',p_qr_key:'Q1',p_qty:2});
  if(step==='page'||step.startsWith('dest:'))out.display=(els.get('c86Box')||{style:{}}).style.display;
 }
 out.calls=calls.filter(c=>c.name==='apply_qr_lot_operation');out.alerts=alerts;out.focus=focus;out.created=created;
 process.stdout.write(JSON.stringify(out));
})().catch(e=>{process.stdout.write(JSON.stringify({error:String(e&&e.stack||e)}))});
"""

PACK_LOT = {"item_name": "キャベツ", "container_type": "ダンボール", "unit": "ケース", "pack_weight": "10kg"}
BIG_LOT = {"item_name": "キャベツ", "container_type": "網コンテナ", "unit": "基", "pack_weight": ""}


def run_c86(dest, lot, steps, **extra):
    payload = {"path": str(C86), "dest": dest, "lot": lot, "steps": steps, **extra}
    done = subprocess.run(["node", "-e", NODE_HARNESS], input=json.dumps(payload), capture_output=True, text=True, timeout=30)
    if done.returncode != 0:
        raise AssertionError(done.stderr)
    out = json.loads(done.stdout)
    if out.get("error"):
        raise AssertionError(out["error"])
    return out


def slip_of(out):
    return (out["calls"][0]["args"].get("p_operation_meta") or {}).get("slip")


class C86OutboundInputTests(unittest.TestCase):
    def test_hq_shows_pack_box_for_cartons_and_hides_it_for_large_containers(self):
        shown = run_c86("本社", PACK_LOT, ["page"])
        self.assertEqual(shown["display"], "block")
        hidden = run_c86("本社", BIG_LOT, ["page"])
        self.assertEqual(hidden["display"], "none")

    def test_box_follows_destination_changes(self):
        for lot, expected in ((PACK_LOT, ["block", "block", "none", "block"]), (BIG_LOT, ["none", "block", "none", "block"])):
            with self.subTest(lot=lot["container_type"]):
                out = run_c86("本社", lot, ["page"])
                states = [out["display"]]
                for dest in ("埼玉", "その他", "深谷"):
                    states.append(run_c86(dest, lot, ["page"])["display"])
                self.assertEqual(states, expected)

    def test_hq_pack_is_saved_in_the_outbound_record_as_normalized_kg(self):
        for typed, expected in (("12", "12kg"), ("12kg", "12kg"), ("１２ｋｇ", "12kg"), ("12.5", "12.5kg")):
            with self.subTest(typed=typed):
                out = run_c86("本社", PACK_LOT, ["page", "save"], pack=typed)
                self.assertEqual(len(out["calls"]), 1)
                self.assertEqual(slip_of(out), {"pack": expected})
                self.assertEqual(out["alerts"], [])

    def test_hq_blank_pack_adds_nothing_and_keeps_existing_meta(self):
        out = run_c86("本社", PACK_LOT, ["page", "save"], pack="  ", meta={"batchId": "b1"})
        self.assertEqual(out["calls"][0]["args"]["p_operation_meta"], {"batchId": "b1"})

    def test_hq_large_container_never_asks_for_weight_and_is_not_blocked(self):
        out = run_c86("本社", BIG_LOT, ["page", "save"], kg="")
        self.assertEqual(len(out["calls"]), 1)
        self.assertIsNone(slip_of(out))
        self.assertEqual(out["focus"], [])
        self.assertEqual(out["created"], 0)

    def test_hq_batch_outbound_does_not_open_weight_prompt(self):
        out = run_c86("本社", BIG_LOT, ["rpc"])
        self.assertEqual(len(out["calls"]), 1)
        self.assertIsNone(slip_of(out))
        self.assertEqual(out["created"], 0)

    def test_saitama_and_fukaya_behaviour_is_unchanged(self):
        for dest in ("埼玉", "深谷"):
            with self.subTest(dest=dest, case="large without weight"):
                out = run_c86(dest, BIG_LOT, ["page", "save"], kg="")
                self.assertEqual(out["calls"], [])
                self.assertEqual(out["focus"][0][0], "c86Kg")
            with self.subTest(dest=dest, case="large with weight"):
                out = run_c86(dest, BIG_LOT, ["page", "save"], kg="808")
                self.assertEqual(slip_of(out), {"kg": 808})
            with self.subTest(dest=dest, case="carton pack"):
                out = run_c86(dest, PACK_LOT, ["page", "save"], pack="12")
                self.assertEqual(slip_of(out), {"pack": "12kg"})

    def test_other_destinations_never_get_slip_meta(self):
        out = run_c86("その他", PACK_LOT, ["page", "save"], pack="12")
        self.assertIsNone(slip_of(out))

    def test_retry_with_same_operation_id_keeps_the_hq_pack(self):
        first = run_c86("本社", PACK_LOT, ["page", "save"], pack="12", opId="same")
        self.assertEqual(slip_of(first), {"pack": "12kg"})


def start_server():
    handler = type("Quiet", (SimpleHTTPRequestHandler,), {"log_message": lambda *args: None})
    server = ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(handler, directory=str(ROOT)))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


SETUP = """()=>{
 const T=window.__T;window.__x={rpc:[],alerts:[],sel:[],fail:'',prompt:null};
 window.alert=m=>window.__x.alerts.push(String(m));window.confirm=()=>true;
 window.prompt=()=>window.__x.prompt;
 const base=qrSelect,inList=(q,k)=>{const m=String(q).match(new RegExp('(?:^|&)'+k+'=in\\\\.\\\\(([^)]*)\\\\)'));return m?decodeURIComponent(m[1]).split(',').map(x=>x.trim()):null};
 T.qr_slip_adjust_v1199c86=T.qr_slip_adjust_v1199c86||[];T.qr_lot_movements=T.qr_lot_movements||[];T.qr_lots=T.qr_lots||[];
 qrSelect=async(t,q)=>{
  window.__x.sel.push([t,String(q)]);
  if(window.__x.fail===t)throw new Error('通信に失敗しました');
  if(t==='qr_slip_adjust_v1199c86'){const ids=inList(q,'movement_id');return JSON.parse(JSON.stringify(T[t].filter(r=>!ids||ids.includes(String(r.movement_id)))))}
  if(t==='qr_lot_movements'||t==='qr_lots'){const ids=inList(q,'id');return JSON.parse(JSON.stringify(T[t].filter(r=>!ids||ids.includes(String(r.id)))))}
  return base(t,q)};
 callRpc=async(n,a)=>{window.__x.rpc.push([n,JSON.parse(JSON.stringify(a||{}))]);
  if(n==='qr_slip_adjust_save_v1199c86'){const r=T.qr_slip_adjust_v1199c86.filter(x=>x.movement_id!==a.p_movement_id);if(a.p_pack||a.p_total_kg)r.push({movement_id:a.p_movement_id,pack:a.p_pack,total_kg:a.p_total_kg});T.qr_slip_adjust_v1199c86=r;return{ok:true}}
  if(n==='list_qr_outbound_history_v1144')return{rows:window.__x.history||[],total_count:(window.__x.history||[]).length};
  if(n==='hq_save_sheet_v1400'||n==='hq_set_planned_date_v1400')return{ok:true};
  return[]};
 try{localStorage.setItem('seika_hq_site','honsha')}catch(e){}
}"""

MOVING = {
    "id": "LM1", "lot_no": "H20261108-0112", "qr_key": "HQ-M1", "item_name": "キャベツ", "status": "入荷待ち",
    "source_kind": "石岡から", "source_movement_id": "MV1", "source_lot_no": "Q-0001", "unit": "case",
    "planned_qty": 29, "planned_count": 29, "pack_weight": "10kg", "supplier": "水戸大同", "origin": "茨城県産",
    "planned_date": "2026-11-09", "ishioka_received_date": "2026-10-30", "container_type": "ダンボール",
    "created_by_name": "平田 祐希", "ship_run": "配送便", "ship_run_time": "11時",
}


class HqPackBrowserTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = start_server()
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

    def open_app(self, role, lots=None, adjust=None, movements=None):
        context = self.browser.new_context(viewport={"width": 820, "height": 1180}, service_workers="block")
        self.addCleanup(context.close)
        context.route("**/*", lambda route: route.continue_() if urlparse(route.request.url).netloc == self.local else route.abort())
        page = context.new_page()
        errors = []
        page.on("pageerror", lambda error: errors.append(str(error)))
        self.addCleanup(lambda: self.assertEqual(errors, []))
        page.goto(self.url, wait_until="load")
        page.wait_for_function("()=>typeof ymdKey==='function'")
        page.wait_for_timeout(800)
        page.evaluate(MOCK, role)
        page.evaluate("""([lots,adjust,movements])=>{window.__T.hq_lots_v1400=lots;window.__T.qr_slip_adjust_v1199c86=adjust;window.__T.qr_lot_movements=movements}""",
                      [lots or [dict(MOVING)], adjust or [], movements or []])
        page.evaluate(SETUP)
        return page

    def sheet(self, page):
        page.evaluate("()=>hqSheetPage('HQ-M1')")
        page.wait_for_selector("#hqSBtn", state="attached")
        return page.evaluate("()=>document.getElementById('app').innerText")

    def rpc(self, page, name):
        return page.evaluate("(n)=>window.__x.rpc.filter(x=>x[0]===n)", name)

    def print_label(self, page, qty="29"):
        page.evaluate("""(q)=>{window.__x.label='';window.__x.pdf=0;
          window.html2canvas=async pg=>{window.__x.label=pg.querySelector('.sheet table').innerText;window.__x.pdf++;const c=document.createElement('canvas');c.width=2;c.height=2;return c};
          const e=document.getElementById('hqSEach');e.value=q;e.dispatchEvent(new Event('input',{bubbles:true}));e.dispatchEvent(new Event('change',{bubbles:true}))}""", qty)
        page.evaluate("()=>document.getElementById('hqSBtn').click()")
        page.wait_for_function("()=>window.__x.pdf>0||window.__x.alerts.length>0")
        return page.evaluate("()=>window.__x.label")

    def test_label_uses_the_changed_pack_for_a_moving_lot(self):
        page = self.open_app("admin", adjust=[{"movement_id": "MV1", "pack": "12kg"}])
        text = self.sheet(page)
        self.assertIn("今の入数：12kg（ロットの量目 10kg から変更）", text)
        label = self.print_label(page)
        self.assertIn("12kg", label)
        self.assertNotIn("10kg", label)

    def test_label_uses_the_pack_entered_at_outbound_time(self):
        movement = {"id": "MV1", "operation_meta": {"slip": {"pack": "12kg"}, "hqShip": {"run": "配送便"}}}
        page = self.open_app("admin", movements=[movement])
        self.assertIn("今の入数：12kg", self.sheet(page))
        self.assertIn("12kg", self.print_label(page))

    def test_later_adjustment_wins_over_the_outbound_value(self):
        movement = {"id": "MV1", "operation_meta": {"slip": {"pack": "11kg"}}}
        page = self.open_app("admin", adjust=[{"movement_id": "MV1", "pack": "12kg"}], movements=[movement])
        self.assertIn("今の入数：12kg", self.sheet(page))

    def test_label_keeps_the_lot_pack_when_nothing_was_changed(self):
        page = self.open_app("admin")
        text = self.sheet(page)
        self.assertIn("今の入数：10kg", text)
        self.assertNotIn("から変更", text)
        self.assertIn("10kg", self.print_label(page))

    def test_admin_can_save_blank_and_normalized_pack_without_touching_stock(self):
        page = self.open_app("admin")
        self.sheet(page)
        for typed, expected in (("12", "12kg"), ("１２ｋｇ", "12kg")):
            page.fill("#hqSPackIn", typed)
            page.click("text=入数を保存")
            page.wait_for_function("()=>window.__x.rpc.length>=1&&document.body.innerText.includes('入数を')")
            calls = self.rpc(page, "qr_slip_adjust_save_v1199c86")
            self.assertEqual(calls[-1][1], {"p_movement_id": "MV1", "p_total_kg": None, "p_pack": expected})
            page.evaluate("()=>{window.__x.rpc=[]}")
            page.evaluate("()=>hqSheetPage('HQ-M1')")
            page.wait_for_selector("#hqSPackIn")
        page.fill("#hqSPackIn", "")
        page.click("text=入数を保存")
        page.wait_for_function("()=>window.__x.rpc.some(x=>x[0]==='qr_slip_adjust_save_v1199c86')")
        self.assertEqual(self.rpc(page, "qr_slip_adjust_save_v1199c86")[-1][1]["p_pack"], None)
        stock_calls = page.evaluate("()=>window.__x.rpc.filter(x=>/out|stock|qty|operation/i.test(x[0])&&x[0]!=='qr_slip_adjust_save_v1199c86')")
        self.assertEqual(stock_calls, [])

    def test_invalid_pack_is_rejected_without_saving(self):
        page = self.open_app("admin")
        self.sheet(page)
        for typed in ("0", "-5kg", "1000"):
            page.fill("#hqSPackIn", typed)
            page.click("text=入数を保存")
            page.wait_for_function("(n)=>window.__x.alerts.length>=n", arg=1)
            page.evaluate("()=>{window.__x.alerts=[]}")
        self.assertEqual(self.rpc(page, "qr_slip_adjust_save_v1199c86"), [])

    def test_headquarters_roles_see_the_pack_but_cannot_edit_it(self):
        for role in ("hq_worker", "hq_receiver"):
            with self.subTest(role=role):
                page = self.open_app(role, adjust=[{"movement_id": "MV1", "pack": "12kg"}])
                text = self.sheet(page)
                self.assertIn("今の入数：12kg", text)
                self.assertEqual(page.locator("#hqSPackIn").count(), 0)
                page.evaluate("()=>hqPackSave('HQ-M1')")
                self.assertEqual(self.rpc(page, "qr_slip_adjust_save_v1199c86"), [])

    def test_large_container_lot_has_no_pack_box(self):
        big = dict(MOVING, unit="kg", container_type="網コンテナ", planned_count=3, planned_qty=820, unit_weight_kg=273.3)
        page = self.open_app("admin", lots=[big])
        text = self.sheet(page)
        self.assertNotIn("入数（量目と違うとき）", text)
        self.assertEqual(page.locator("#hqSPackIn").count(), 0)

    def test_direct_arrival_lot_has_no_pack_box(self):
        direct = dict(MOVING, source_kind="本社直接入荷", source_movement_id=None, via_ishioka=False)
        page = self.open_app("admin", lots=[direct])
        self.assertNotIn("入数（量目と違うとき）", self.sheet(page))

    def test_read_failure_blocks_printing_instead_of_printing_the_old_pack(self):
        for failing in ("qr_lot_movements", "qr_slip_adjust_v1199c86"):
            with self.subTest(failing=failing):
                page = self.open_app("admin")
                page.evaluate("(t)=>{window.__x.fail=t}", failing)
                text = self.sheet(page)
                self.assertIn("入数の変更を読み込めませんでした", text)
                self.print_label(page)
                self.assertTrue(any("印刷できません" in m for m in page.evaluate("()=>window.__x.alerts")))
                self.assertEqual(self.rpc(page, "hq_save_sheet_v1400"), [])
                self.assertEqual(page.evaluate("()=>window.__x.pdf"), 0)

    def test_missing_slip_table_still_prints_with_the_outbound_pack(self):
        movement = {"id": "MV1", "operation_meta": {"slip": {"pack": "12kg"}}}
        page = self.open_app("admin", movements=[movement])
        page.evaluate("""()=>{const q=qrSelect;qrSelect=async(t,x)=>{if(t==='qr_slip_adjust_v1199c86')throw new Error('relation does not exist');return q(t,x)}}""")
        text = self.sheet(page)
        self.assertIn("今の入数：12kg", text)
        self.assertNotIn("読み込めませんでした", text)
        self.assertIn("12kg", self.print_label(page))

    def test_moving_list_shows_pack_and_reads_only_moving_ishioka_lots(self):
        lots = [dict(MOVING), dict(MOVING, id="LM2", qr_key="HQ-M2", source_movement_id="MV2", pack_weight="10kg"),
                dict(MOVING, id="LM3", qr_key="HQ-M3", source_movement_id="MV3", status="在庫あり", current_qty=5)]
        page = self.open_app("admin", lots=lots, adjust=[{"movement_id": "MV1", "pack": "12kg"}])
        page.evaluate("()=>{window.__x.sel=[]}")
        page.evaluate("()=>hqPendingPage()")
        page.wait_for_function("()=>document.body.innerText.includes('キャベツ')")
        requested = page.evaluate("()=>window.__x.sel.map(x=>x[0])")
        self.assertEqual(requested.count("qr_lot_movements"), 1)
        self.assertEqual(requested.count("qr_slip_adjust_v1199c86"), 1)
        movement_query = page.evaluate("()=>window.__x.sel.find(x=>x[0]==='qr_lot_movements')[1]")
        self.assertIn("MV1", movement_query)
        self.assertIn("MV2", movement_query)
        self.assertNotIn("MV3", movement_query)
        self.assertIn("12kg", page.evaluate("()=>document.getElementById('app').innerText"))
        page.evaluate("()=>{window.__x.sel=[]}")
        page.evaluate("()=>hqHome()")
        page.wait_for_timeout(500)
        self.assertNotIn("qr_lot_movements", page.evaluate("()=>window.__x.sel.map(x=>x[0])"))

    def test_every_moving_screen_shows_the_changed_pack(self):
        lots = [dict(MOVING), dict(MOVING, id="LM2", qr_key="HQ-M2", lot_no="H20261108-0111", source_movement_id="MV2")]
        adjust = [{"movement_id": "MV1", "pack": "12kg"}]
        screens = {
            "hqPendingPage": "()=>hqPendingPage()",
            "hqIshiokaPendingPage": "()=>hqIshiokaPendingPage()",
            "hqLotPage": "()=>hqLotPage('HQ-M1')",
            "hqSheetPage": "()=>hqSheetPage('HQ-M1')",
        }
        for name, call in screens.items():
            with self.subTest(screen=name):
                page = self.open_app("admin", lots=[dict(x) for x in lots], adjust=adjust)
                page.evaluate(call)
                page.wait_for_function("()=>document.body.innerText.includes('キャベツ')&&!document.body.innerText.includes('読み込んでいます')")
                cards = page.evaluate("""()=>[...document.querySelectorAll('.hqLotCard')].map(c=>({lot:c.innerText.match(/H\\d+-\\d+/)?.[0],meta:[...c.querySelectorAll('.hqLotMeta > div')].find(d=>d.innerText.includes('量目'))?.innerText.replace(/\\s+/g,'')}))""")
                by_lot = {c["lot"]: c["meta"] for c in cards}
                self.assertEqual(by_lot.get("H20261108-0112"), "量目12kg", cards)
                if name in ("hqPendingPage", "hqIshiokaPendingPage"):
                    self.assertEqual(by_lot.get("H20261108-0111"), "量目10kg", cards)

    def test_batch_print_list_after_outbound_shows_the_changed_pack(self):
        page = self.open_app("admin", adjust=[{"movement_id": "MV1", "pack": "12kg"}])
        page.evaluate("""()=>{window.__T.qr_lots=[{id:'SRC1',qr_key:'Q1'}];window.__T.hq_lots_v1400=window.__T.hq_lots_v1400.map(l=>({...l,source_lot_id:'SRC1',created_at:'2026-11-08T00:00:00Z'}));c50BatchPrintPage(['Q1'])}""")
        page.wait_for_function("()=>document.querySelector('#c50PrintList .hqLotCard')")
        self.assertIn("12kg", page.evaluate("()=>document.getElementById('c50PrintList').innerText"))

    def test_saving_the_pack_changes_the_pending_list_right_away(self):
        page = self.open_app("admin")
        self.sheet(page)
        page.fill("#hqSPackIn", "12")
        page.click("text=入数を保存")
        page.wait_for_function("()=>document.body.innerText.includes('入数を 12kg にしました')")
        self.assertIn("量目\n12kg", page.evaluate("()=>document.getElementById('app').innerText"))
        page.evaluate("()=>hqPendingPage()")
        page.wait_for_function("()=>document.querySelector('.hqLotCard')")
        self.assertIn("12kg", page.evaluate("()=>document.querySelector('.hqLotCard .hqLotMeta').innerText"))

    def history_row(self, **extra):
        row = {"id": "MV1", "destination": "本社", "qty": 29, "unit": "ケース", "item_name": "キャベツ", "lot_no": "Q-0001",
               "qr_key": "Q1", "container_type": "ダンボール", "pack_weight": "10kg", "memo": "", "is_cancelled": False}
        row.update(extra)
        return row

    def slip_page(self, adjust=None, role="admin", container="ダンボール", pack_meta=None):
        today = None
        page = self.open_app(role, lots=[])
        today = page.evaluate("()=>todayKey()")
        meta = {"hqShip": {"run": "配送便", "time": "11時", "day": "当日便"}}
        if pack_meta:
            meta["slip"] = {"pack": pack_meta}
        page.evaluate("""([today,adjust,meta,container,row])=>{
          window.__T.qr_lot_movements=[{id:'MV1',lot_id:'LT1',origin:'茨城県産',supplier:'水戸大同',cooperative_name:'',operation_meta:meta,weight:null}];
          window.__T.qr_lots=[{id:'LT1',qr_key:'Q1',received_date:'2026-10-30',origin:'茨城県産',supplier:'水戸大同',cooperative_name:'',total_weight:null,received_qty:112,pack_weight:'10kg'}];
          window.__T.hq_lots_v1400=[{id:'LM1',source_movement_id:'MV1',measured_total_kg:null,measured_count:null,planned_qty:29,planned_count:29,unit:'case',planned_date:today}];
          window.__T.qr_slip_adjust_v1199c86=adjust;window.__x.history=[{...row,container_type:container}]}""",
                      [today, adjust or [], meta, container, self.history_row()])
        page.evaluate("(d)=>c84SlipPage(d)", today)
        page.wait_for_function("()=>document.body.innerText.includes('本社工場')")
        return page

    def test_hq_slip_shows_the_changed_pack_and_can_edit_it(self):
        page = self.slip_page(adjust=[{"movement_id": "MV1", "pack": "12kg"}])
        body = page.evaluate("()=>document.getElementById('app').innerText")
        self.assertIn("12kg", body)
        self.assertIn("入数を直す", body)
        self.assertNotIn("10kg", page.evaluate("()=>document.querySelector('.c84Page').innerText"))
        page.evaluate("()=>{window.__x.prompt='15'}")
        page.evaluate("()=>c86EditPack(0,0)")
        page.wait_for_function("()=>window.__x.rpc.some(x=>x[0]==='qr_slip_adjust_save_v1199c86')")
        self.assertEqual(self.rpc(page, "qr_slip_adjust_save_v1199c86")[0][1], {"p_movement_id": "MV1", "p_total_kg": None, "p_pack": "15kg"})
        page.wait_for_function("()=>document.querySelector('.c84Page')&&document.querySelector('.c84Page').innerText.includes('15kg')")

    def test_hq_slip_uses_the_pack_entered_at_outbound_time_and_lot_pack_otherwise(self):
        page = self.slip_page(pack_meta="12kg")
        self.assertIn("12kg", page.evaluate("()=>document.querySelector('.c84Page').innerText"))
        page = self.slip_page()
        self.assertIn("10kg", page.evaluate("()=>document.querySelector('.c84Page').innerText"))

    def test_hq_slip_edit_is_limited_to_admin_and_worker_and_skips_large_containers(self):
        page = self.slip_page(role="clerk")
        self.assertNotIn("入数を直す", page.evaluate("()=>document.getElementById('app').innerText"))
        page = self.slip_page(container="網コンテナ")
        self.assertNotIn("入数を直す", page.evaluate("()=>document.getElementById('app').innerText"))

    def test_guides_describe_where_to_set_the_hq_pack(self):
        page = self.open_app("admin")
        text = page.evaluate("""()=>{const g=[];for(const r of Object.keys(V195_ROLE_GUIDES))for(const s of V195_ROLE_GUIDES[r].sections||[])g.push(s.title+'\\n'+(s.steps||[]).join('\\n'));
          for(const k of Object.keys(window.V198_GUIDE_SECTIONS||{})){const s=V198_GUIDE_SECTIONS[k];g.push(s.title+'\\n'+(s.steps||[]).join('\\n'))}return g.join('\\n')}""")
        for expected in ("出庫先「本社」を選ぶと出る「入数」欄", "入数を保存", "出庫したケース数で減ります", "本社工場の伝票は「入数を直す」"):
            self.assertIn(expected, text)


if __name__ == "__main__":
    unittest.main()
