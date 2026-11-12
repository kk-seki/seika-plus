import functools
import threading
import unittest
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parent.parent
MOCK = (ROOT / 'tests/mock_hq.js').read_text()
SETUP = """()=>{
 window.__alerts=[];window.alert=m=>__alerts.push(String(m));
 window.__calls=[];
 __T.hq_lots_v1400.push({...__T.hq_lots_v1400[0],id:'L4',lot_no:'H261025-04',qr_key:'HQ-NEW'});
 __T.hq_works_v1500[0].history=[];
 const selectBase=qrSelect;
 qrSelect=async(t,q)=>{if(t==='hq_lots_v1400'&&q.includes('or=(')){const k=decodeURIComponent(q.match(/qr_key.eq.([^,]+)/)[1]);return __T.hq_lots_v1400.filter(l=>l.qr_key===k||l.lot_no===k)}return selectBase(t,q)};
 const base=callRpc;
 callRpc=async(n,a)=>{
  __calls.push({n,a});
  const w=__T.hq_works_v1500.find(x=>x.id===a?.p_work_id);
  if(n==='hq_prep_available_lots_v1199c117')return __T.hq_lots_v1400.map(l=>({...l,available_qty:window.__avail?.[l.id]??l.current_qty}));
  if(n==='hq_work_save_material_qty_v1199c112'){
   if(window.__fail)throw new Error('仮の通信エラー');
   __T.hq_work_materials_v1500.find(m=>m.id===a.p_material_id).qty=a.p_qty;return{ok:true};
  }
  if(n==='hq_work_add_material_v1199c112'){
   if(window.__fail)throw new Error('仮の通信エラー');
   if(w.status!=='作業中')throw new Error('作業中だけ');
   const l=__T.hq_lots_v1400.find(x=>x.id===a.p_lot_id);
   if(__T.hq_work_materials_v1500.some(m=>m.work_id===w.id&&m.lot_id===l.id))return{ok:true,already:true};
   __T.hq_work_materials_v1500.push({id:'M4',work_id:w.id,lot_id:l.id,lot_no:l.lot_no,item_name:l.item_name,unit:l.unit,pack_kg:10});return{ok:true};
  }
  if(n==='hq_work_end_v1500'){w.status='入力待ち';return{status:w.status}}
  if(n==='hq_work_save_inputs_v1500'){
   for(const m of a.p_materials)__T.hq_work_materials_v1500.find(x=>x.id===m.id).qty=m.qty;
   w.yield_kg=a.p_yield_kg;w.waste_kg=a.p_waste_kg;w.inputs_saved_at=new Date().toISOString();return{ok:true};
  }
  return base(n,a);
 };
 window.__reader=null;
 window.Html5Qrcode=class{constructor(id){} async start(c,cfg,fn){window.__reader=fn}async stop(){} clear(){}};
}"""

class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, *_):
        pass

class PrepMaterialTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server=ThreadingHTTPServer(('127.0.0.1',0),functools.partial(QuietHandler,directory=str(ROOT)))
        threading.Thread(target=cls.server.serve_forever,daemon=True).start()
        cls.url=f'http://127.0.0.1:{cls.server.server_port}/index.html'
        cls.local=urlparse(cls.url).netloc
        cls.pw=sync_playwright().start()
        cls.browser=cls.pw.chromium.launch()

    @classmethod
    def tearDownClass(cls):
        cls.browser.close();cls.pw.stop();cls.server.shutdown();cls.server.server_close()

    def app(self,role='hq_prep'):
        ctx=self.browser.new_context(service_workers='block')
        self.addCleanup(ctx.close)
        ctx.route('**/*',lambda r:r.continue_() if urlparse(r.request.url).netloc==self.local else r.abort())
        page=ctx.new_page()
        errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
        self.addCleanup(lambda:self.assertEqual(errors,[]))
        page.goto(self.url);page.wait_for_timeout(700)
        page.evaluate(MOCK,role);page.evaluate(SETUP)
        page.evaluate("()=>hqWorkPage('W1')")
        return page

    def test_save_then_add_keeps_time_people_and_stock(self):
        p=self.app()
        before=p.evaluate('()=>JSON.stringify({mem:__T.hq_work_members_v1500,lots:__T.hq_lots_v1400,start:__T.hq_works_v1500[0].started_at})')
        p.locator('#c112Qty_M1').fill('3.5')
        p.get_by_role('button',name='使用数を保存',exact=True).click()
        p.wait_for_function('()=>__T.hq_work_materials_v1500[0].qty===3.5')
        p.get_by_role('button',name='次の原料を追加（QR）',exact=True).click()
        p.select_option('#c112Lot','L4')
        p.get_by_role('button',name='選んだ原料を追加',exact=True).click()
        p.wait_for_selector('#c112Qty_M4')
        self.assertEqual(p.locator('#c112Qty_M1').input_value(),'3.5')
        self.assertEqual(p.evaluate('()=>JSON.stringify({mem:__T.hq_work_members_v1500,lots:__T.hq_lots_v1400,start:__T.hq_works_v1500[0].started_at})'),before)
        self.assertEqual(p.evaluate('()=>__T.hq_works_v1500[0].status'),'作業中')

    def test_qr_add_and_duplicate_do_not_duplicate_rows(self):
        p=self.app();p.evaluate("()=>h2AddMaterialOpen('W1')")
        p.evaluate("()=>{__reader('HQ-NEW')}")
        p.click('#h2CfYes')
        p.wait_for_selector('#c112Qty_M4')
        p.evaluate("()=>h2AddMaterial('W1','L4')")
        self.assertEqual(p.evaluate("()=>__T.hq_work_materials_v1500.filter(m=>m.work_id==='W1'&&m.lot_id==='L4').length"),1)

    def test_wrong_kind_qr_is_refused_and_unconfirmed_lot_is_not_added(self):
        p=self.app();p.evaluate("()=>h2AddMaterialOpen('W1')")
        self.assertIn('原料の貼り紙のQR',p.locator('#c112ReaderHint').inner_text())
        before=p.evaluate("()=>__T.hq_work_materials_v1500.length")
        p.evaluate("()=>{__reader('HQST-S1')}")
        p.wait_for_selector('#h2ScanNotice')
        self.assertIn('スタッフ（人の名前）のQRを読みました',p.locator('#h2ScanNotice').inner_text())
        p.click('#h2ScanClose')
        p.evaluate("()=>{__reader('HQ-NEW')}")
        p.click('#h2CfNo')
        self.assertEqual(p.evaluate("()=>__T.hq_work_materials_v1500.length"),before)

    def test_invalid_lot_and_expiry_are_blocked(self):
        p=self.app()
        p.evaluate("()=>h2AddMaterial('W1','L2')")
        p.evaluate("()=>{__T.hq_lots_v1400.find(l=>l.id==='L4').status='入荷待ち';return h2AddMaterial('W1','L4')}")
        p.evaluate("()=>{__T.hq_lots_v1400.find(l=>l.id==='L4').status='在庫あり';window.hqLimitGuard=()=>false;return h2AddMaterial('W1','L4')}")
        self.assertFalse(p.evaluate("()=>__calls.some(c=>c.n==='hq_work_add_material_v1199c112')"))

    def test_unsaved_input_is_not_lost_on_add_or_end(self):
        p=self.app();p.locator('#c112Qty_M1').fill('2')
        p.evaluate("()=>h2AddMaterialOpen('W1')")
        p.evaluate("()=>h2WorkEnd('W1')")
        self.assertEqual(p.locator('#c112Qty_M1').input_value(),'2')
        self.assertEqual(p.evaluate('()=>__T.hq_works_v1500[0].status'),'作業中')
        self.assertFalse(p.evaluate("()=>__calls.some(c=>c.n==='hq_work_end_v1500')"))

    def test_save_error_keeps_input_and_negative_is_not_sent(self):
        p=self.app();p.locator('#c112Qty_M1').fill('-1')
        p.evaluate("()=>h2SaveMaterialQty('W1','M1')")
        self.assertFalse(p.evaluate("()=>__calls.some(c=>c.n==='hq_work_save_material_qty_v1199c112')"))
        p.locator('#c112Qty_M1').fill('2');p.evaluate('()=>window.__fail=true')
        p.evaluate("()=>h2SaveMaterialQty('W1','M1')")
        self.assertEqual(p.locator('#c112Qty_M1').input_value(),'2')
        self.assertEqual(p.locator('#c112Materials').get_attribute('data-dirty'),'1')

    def test_end_shows_all_materials_and_aggregate_waste_yield(self):
        p=self.app();p.evaluate("()=>h2AddMaterial('W1','L4')")
        p.evaluate("()=>h2WorkEnd('W1')")
        self.assertEqual(p.locator('.h2MatQty').count(),2)
        p.locator('.h2MatQty').nth(0).fill('3');p.locator('.h2MatQty').nth(1).fill('2')
        p.locator('#h2Yield').fill('45');self.assertEqual(p.locator('#h2Waste').input_value(),'5')
        p.evaluate("()=>h2SaveInputs('W1')")
        self.assertEqual(p.evaluate('()=>[__T.hq_works_v1500[0].waste_kg,__T.hq_works_v1500[0].yield_kg]'),[5,45])

    def test_use_all_fills_remaining_cases_with_kg_and_saves_on_work_page(self):
        p=self.app();p.evaluate("()=>{window.__avail={L1:3};return hqWorkPage('W1')}")
        p.get_by_role('button',name='使い切った（残り全部・自動で入れて保存）').first.click()
        p.wait_for_function("()=>__calls.some(c=>c.n==='hq_work_save_material_qty_v1199c112')")
        self.assertEqual(p.locator('#c112Qty_M1').input_value(),'3')
        self.assertEqual(p.evaluate("()=>__T.hq_work_materials_v1500.find(m=>m.id==='M1').qty"),3)
        self.assertIn('＝ 30kg（量目 10kg × 3ケース）',p.locator('.c119Kg[data-for="c112Qty_M1"]').inner_text())

    def test_use_all_at_end_fills_kg_lot_and_blocks_when_nothing_left(self):
        p=self.app();p.evaluate("()=>{window.__avail={L1:4.5};__T.hq_work_materials_v1500.find(m=>m.id==='M1').unit='kg';return h2WorkEnd('W1')}")
        p.get_by_role('button',name='使い切った（残り全部・自動で入れる）').first.click()
        p.wait_for_function("()=>document.querySelector('.h2MatQty').value==='4.5'")
        self.assertIn('＝ 4.5kg',p.locator('.c119Kg[data-for-qty="M1"]').inner_text())
        p.locator('.h2MatQty').first.fill('')
        p.evaluate("()=>{window.__avail={L1:0};window.__msgs=[];window.alert=m=>__msgs.push(m)}")
        p.get_by_role('button',name='使い切った（残り全部・自動で入れる）').first.click()
        p.wait_for_function("()=>__msgs.length>0")
        self.assertEqual(p.locator('.h2MatQty').first.input_value(),'')

    def test_non_prep_role_and_closed_work_have_no_add(self):
        p=self.app('hq_receiver')
        self.assertEqual(p.locator('#c112Materials').count(),0)
        p.evaluate("()=>h2AddMaterial('W1','L4')")
        self.assertFalse(p.evaluate("()=>__calls.some(c=>c.n==='hq_work_add_material_v1199c112')"))
        p=self.app();p.evaluate("()=>{__T.hq_works_v1500[0].status='清掃中';return hqWorkPage('W1')}")
        self.assertEqual(p.locator('#c112Materials').count(),0)

    def test_guide_has_material_step(self):
        p=self.app()
        self.assertTrue(p.evaluate("()=>V195_ROLE_GUIDES.hq_prep.sections.some(s=>s.title.includes('次の原料を追加'))"))

if __name__=='__main__':
    unittest.main()
