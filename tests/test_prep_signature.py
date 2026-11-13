import functools
import threading
import unittest
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
MOCK = (ROOT / 'tests' / 'mock_hq.js').read_text(encoding='utf-8')


class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, *_args):
        pass


SETUP = r"""role=>{
window.db={role,user:'テスト'};window.__h2={};window.__calls=[];window.__alerts=[];window.alert=m=>__alerts.push(String(m));window.confirm=()=>true;
window.esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
window.seikaEventAttrs=(event,action,args=[])=>`data-seika-${event}-action="${esc(action)}" data-seika-${event}-args="${esc(encodeURIComponent(JSON.stringify(args)))}"`;
document.addEventListener('click',e=>{const el=e.target.closest('[data-seika-click-action]');if(!el||el.disabled)return;const fn=window[el.dataset.seikaClickAction];if(typeof fn==='function')fn(...JSON.parse(decodeURIComponent(el.dataset.seikaClickArgs||'%5B%5D')))});
window.currentScreen='';window.setScreen=(name,args=[])=>{currentScreen=name;window.currentArgs=args};window.pageShell=(title,sub,body)=>document.getElementById('app').innerHTML=`<main class="wrap"><h1>${title}</h1><div>${sub}</div>${body}</main>`;
let seq=0;window.newId=()=>`00000000-0000-4000-8000-${String(++seq).padStart(12,'0')}`;
const staff=[{id:'S1',name:'佐藤',team:'1班'},{id:'S2',name:'鈴木',team:'1班'},{id:'S3',name:'退職者',team:'1班',deleted_at:'2026-01-01'}];
const lots=[{id:'L1',lot_no:'LOT-1',item_name:'キャベツ',unit:'case',pack_weight:'10kg',available_qty:5,current_qty:5}];
const masters=[{id:'P1',name:'1/4芯',item_name:'キャベツ'}];
window.__h2.num2=v=>{const x=String(v??'').trim();return x===''?NaN:Number(x)};window.__h2.h2Loading=()=>'';window.__h2.h2CanPrep=()=>['admin','hq_worker','hq_prep'].includes(db.role);window.__h2.h2CanBoss=()=>['admin','hq_worker'].includes(db.role);window.__h2.h2Err=e=>String(e?.message||e||'');window.__h2.h2UsedKg=rows=>({kg:rows.reduce((n,x)=>n+Number(x.qty||0)*Number(x.pack_kg||10),0),unknown:false});
window.__h2.h2Staff=async()=>structuredClone(staff);window.__h2.h2Places=async()=>[{name:'作業台A'}];window.__h2.h2Masters=async()=>structuredClone(masters);window.__h2.h2StopReader=async()=>{};
window.__h2.r2=async(name,args)=>{__calls.push([name,structuredClone(args)]);if(name==='hq_prep_available_lots_v1199c120')return structuredClone(lots);if(name==='hq_prep_report_save_v1199c120')return {ok:true,id:'W1',updated_at:'2026-11-12T03:00:00Z',review_status:'draft'};if(name==='hq_prep_submit_v1199c120'||name==='hq_prep_submit_v1199c121')return window.__rpc?window.__rpc(name,args):{ok:true,updated_at:'2026-11-12T03:01:00Z',signer_name:args.p_signer_staff_id?'佐藤':null};throw new Error('unexpected rpc '+name)};window.r2=window.__h2.r2;
window.hqPrepHome=async()=>{};window.hqWorkPage=async()=>{};
}"""


class PrepSignatureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(QuietHandler, directory=str(ROOT)))
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()
        cls.url = f'http://127.0.0.1:{cls.server.server_port}'
        cls.local = urlparse(cls.url).netloc
        cls.pw = sync_playwright().start()
        cls.browser = cls.pw.chromium.launch()

    @classmethod
    def tearDownClass(cls):
        cls.browser.close(); cls.pw.stop(); cls.server.shutdown(); cls.server.server_close()

    def app(self, role='hq_prep', viewport={'width': 820, 'height': 1180}):
        context = self.browser.new_context(service_workers='block', timezone_id='Asia/Tokyo', viewport=viewport)
        self.addCleanup(context.close)
        context.route('**/*', lambda route: route.continue_() if urlparse(route.request.url).netloc == self.local else route.abort())
        page = context.new_page(); errors=[]; page.on('pageerror', lambda error: errors.append(str(error)))
        self.addCleanup(lambda: self.assertEqual(errors, [], 'browser errors'))
        page.set_content('<!doctype html><div id="app"></div>')
        page.evaluate(SETUP, role)
        page.add_script_tag(url=self.url + '/js/25-c117-prep-report.js')
        page.wait_for_function("()=>typeof c120NewReportPage==='function'")
        return page

    def ready_review(self, page):
        page.evaluate('()=>c120NewReportPage()'); page.locator('#c117Date').wait_for()
        page.locator('#c117Date').fill('2026-11-12'); page.locator('#c117Started').fill('2026-11-12T09:00'); page.locator('#c117Ended').fill('2026-11-12T11:00'); page.locator('#c117Place').select_option(label='作業台A')
        page.select_option('#c117LotSelect', 'L1'); page.evaluate('()=>c117AddMaterialFromSelect()')
        page.locator('input[name="c117Master"][value="P1"]').check(); page.evaluate('()=>c117MasterToggle()')
        page.locator('.c117Qty').fill('5'); page.locator('[data-c117-output="P1"] input').fill('40'); page.select_option('#c117StaffSelect', 'S1'); page.evaluate('()=>c117AddMemberFromSelect()'); page.locator('[data-c117-member="S1"]').wait_for(); page.evaluate('async()=>{await c120Review();await c120SaveDraft()}')
        page.locator('#c120Submit').wait_for()

    def signature_page(self, page):
        page.locator('#c120Submit').click(); page.locator('#c121SignatureCanvas').wait_for()

    @staticmethod
    def draw(page):
        box = page.locator('#c121SignatureCanvas').bounding_box()
        page.mouse.move(box['x'] + 25, box['y'] + 40); page.mouse.down(); page.mouse.move(box['x'] + 120, box['y'] + 90, steps=8); page.mouse.move(box['x'] + 215, box['y'] + 50, steps=8); page.mouse.up()

    def submit_calls(self, page):
        return page.evaluate("()=>__calls.filter(x=>x[0]==='hq_prep_submit_v1199c121'||x[0]==='hq_prep_submit_v1199c120')")

    def test_hqprep_requires_name_and_real_line(self):
        page=self.app(); self.ready_review(page); self.signature_page(page)
        self.assertTrue(page.locator('#c121SignatureSubmit').is_disabled()); self.assertIn('氏名', page.locator('#c121SignatureReason').inner_text())
        page.locator('button', has_text='佐藤').click(); self.assertTrue(page.locator('#c121SignatureSubmit').is_disabled())
        box=page.locator('#c121SignatureCanvas').bounding_box(); page.mouse.click(box['x']+20, box['y']+20)
        self.assertTrue(page.locator('#c121SignatureSubmit').is_disabled()); self.assertIn('線', page.locator('#c121SignatureReason').inner_text())
        self.assertEqual(self.submit_calls(page), [])

    def test_signature_screen_survives_screen_refresh_without_losing_strokes(self):
        page=self.app(); self.ready_review(page); self.signature_page(page); page.locator('button', has_text='佐藤').click(); self.draw(page)
        self.assertEqual(page.evaluate("()=>currentScreen"), 'c120SignaturePage')
        page.evaluate("()=>window[currentScreen](...currentArgs)"); page.locator('#c121SignatureCanvas').wait_for()
        self.assertFalse(page.locator('#c121SignatureSubmit').is_disabled())
        self.assertEqual(self.submit_calls(page), [])

    def test_every_report_screen_is_allowed_for_hq_only_accounts(self):
        import re
        report = (ROOT / 'js' / '25-c117-prep-report.js').read_text(encoding='utf-8')
        honsha = (ROOT / 'js' / '04-honsha.js').read_text(encoding='utf-8')
        allowed = re.search(r'const HQ_ONLY_ALLOWED=\[([^\]]*)\]', honsha).group(1)
        for screen in set(re.findall(r"setScreen\('([A-Za-z0-9_]+)'", report)):
            self.assertIn(f'"{screen}"', allowed, f'{screen} が本社アカウントで開いた直後にホームへ戻されます')

    def test_reason_message_changes_color_class_when_signature_is_ready(self):
        page=self.app(); self.ready_review(page); self.signature_page(page)
        self.assertEqual(page.locator('#c121SignatureReason').get_attribute('class'), 'err')
        page.locator('button', has_text='佐藤').click(); self.draw(page)
        self.assertEqual(page.locator('#c121SignatureReason').get_attribute('class'), 'ok')

    def test_signature_submit_uses_c121_once_with_png(self):
        page=self.app(); self.ready_review(page); self.signature_page(page); page.locator('button', has_text='佐藤').click(); self.draw(page)
        self.assertFalse(page.locator('#c121SignatureSubmit').is_disabled()); page.locator('#c121SignatureSubmit').click(); page.wait_for_function("()=>__calls.filter(x=>x[0]==='hq_prep_submit_v1199c121').length===1")
        calls=self.submit_calls(page); self.assertEqual(len(calls),1); self.assertEqual(calls[0][0],'hq_prep_submit_v1199c121'); self.assertEqual(calls[0][1]['p_signer_staff_id'],'S1'); self.assertTrue(calls[0][1]['p_signature_png'].startswith('data:image/png;base64,')); self.assertIn('佐藤さんがサインして提出しました',page.locator('body').inner_text())

    def test_unknown_result_retry_keeps_exact_signature_arguments(self):
        page=self.app(); self.ready_review(page); self.signature_page(page); page.locator('button', has_text='佐藤').click(); self.draw(page)
        page.evaluate("()=>window.__rpc=async()=>{throw new Error('network unknown')}"); page.locator('#c121SignatureSubmit').click(); page.wait_for_function("()=>__calls.filter(x=>x[0]==='hq_prep_submit_v1199c121').length===1")
        first=self.submit_calls(page)[0][1]; page.evaluate("()=>window.__rpc=async(_name,args)=>({ok:true,updated_at:'2026-11-12T03:01:00Z',signer_name:args.p_signer_staff_id==='S1'?'佐藤':''})"); page.locator('#c121SignatureSubmit').click(); page.wait_for_function("()=>__calls.filter(x=>x[0]==='hq_prep_submit_v1199c121').length===2")
        self.assertEqual(self.submit_calls(page)[1][1],first)

    def test_conflict_is_not_shown_as_success(self):
        page=self.app(); self.ready_review(page); self.signature_page(page); page.locator('button', has_text='佐藤').click(); self.draw(page); page.evaluate("()=>window.__rpc=async()=>({ok:false,conflict:true,message:'他の人が変更しました'})")
        page.locator('#c121SignatureSubmit').click(); page.wait_for_timeout(60)
        self.assertNotIn('社員の確認待ちにしました', page.locator('body').inner_text()); self.assertIn('他の人が変更しました', page.evaluate('()=>__alerts.at(-1)'))

    def test_admin_and_worker_keep_legacy_submit_without_signature(self):
        for role in ('admin','hq_worker'):
            page=self.app(role); self.ready_review(page); page.locator('#c120Submit').click(); page.wait_for_function("()=>__calls.filter(x=>x[0]==='hq_prep_submit_v1199c120').length===1")
            self.assertEqual(page.locator('#c121SignatureCanvas').count(),0); self.assertEqual(self.submit_calls(page)[0][0],'hq_prep_submit_v1199c120')

    def test_rewrite_clears_signature_and_back_preserves_input(self):
        page=self.app(); self.ready_review(page); self.signature_page(page); page.locator('button', has_text='佐藤').click(); self.draw(page); page.locator('button', has_text='書き直す').click(); page.locator('#c121SignatureCanvas').wait_for(); self.assertTrue(page.locator('#c121SignatureSubmit').is_disabled())
        page.locator('button', has_text='戻って直す').click(); page.locator('#c120Submit').wait_for(); page.locator('button', has_text='戻って編集する').click(); page.locator('.c117Qty').wait_for(); self.assertEqual(page.locator('.c117Qty').input_value(),'5')

    def test_tablet_signature_canvas_fits_viewport(self):
        page=self.app(viewport={'width':1024,'height':768}); self.ready_review(page); self.signature_page(page)
        box=page.locator('#c121SignatureCanvas').bounding_box(); self.assertLessEqual(box['height'],220); self.assertLessEqual(box['width'],1024); self.assertGreaterEqual(box['height'],150)


    def test_employee_review_screen_shows_signer_name_and_signature_image(self):
        context=self.browser.new_context(service_workers='block', timezone_id='Asia/Tokyo', viewport={'width':820,'height':1180})
        self.addCleanup(context.close)
        context.route('**/*', lambda route: route.continue_() if urlparse(route.request.url).netloc == self.local else route.abort())
        page=context.new_page(); errors=[]; page.on('pageerror', lambda error: errors.append(str(error))); self.addCleanup(lambda: self.assertEqual(errors, [], 'browser errors'))
        page.goto(self.url + '/index.html', wait_until='load'); page.wait_for_function("()=>typeof hqWorkPage==='function'"); page.wait_for_timeout(700); page.evaluate(MOCK, 'hq_worker'); page.evaluate("()=>{db.role='hq_worker';db.user='本社 一郎'}")
        page.evaluate("""()=>{
          const work=__T.hq_works_v1500.find(x=>x.id==='W5'); Object.assign(work,{c120_flow:true,review_status:'submitted',updated_at:'2026-11-12T03:01:00Z'});
          const rpc=callRpc; callRpc=async(name,args)=>name==='hq_prep_signatures_v1199c121'?[{signer_name:'佐藤 花子',signed_at:'2026-11-12T03:00:00Z',signature_png:'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9WlG0d8AAAAASUVORK5CYII='}]:rpc(name,args);
        }""")
        page.evaluate("()=>hqWorkPage('W5')"); page.get_by_text('入力者', exact=True).wait_for()
        self.assertIn('佐藤 花子', page.locator('body').inner_text()); self.assertEqual(page.locator('img[alt="入力者サイン"]').count(), 1)


if __name__ == '__main__':
    unittest.main()
