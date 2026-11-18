"""石岡分析：架空データのみ。ローカル以外の通信と Service Worker を遮断。"""
import functools
import threading
import unittest
import sys
sys.dont_write_bytecode = True
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

from playwright.sync_api import sync_playwright
from test_excel_output import read_xlsx

ROOT = Path(__file__).resolve().parent.parent
MOCK = (ROOT / 'tests' / 'mock_hq.js').read_text(encoding='utf-8')
CLOCK = """(()=>{const D=Date,t=D.parse('2026-11-06T03:00:00Z');
class Fixed extends D{constructor(...a){super(...(a.length?a:[t]))}static now(){return t}}window.Date=Fixed})()"""
FIXTURE = """()=>{
 db.items=[{id:'other',name:'他品目',active:true}]; db.records=[]; db.settings={};
 const lots=[{id:'l1',qr_key:'l1',item_name:'出庫のみ',lot_no:'L1',pack_weight:'10kg',received_qty:0,current_qty:0,unit:'ケース',received_date:'2026-10-01'},
  {id:'l2',qr_key:'l2',item_name:'網出庫',lot_no:'L2',container_type:'網コンテナ',received_qty:3,total_weight:300,current_qty:0,unit:'基',received_date:'2026-10-01'}];
 const move=(day,extra)=>({movement_type:'出庫',occurred_at:`2026-11-${day}T01:00:00+09:00`,item_name:'出庫のみ',destination:'本社',qty:1,unit:'ケース',...extra});
 const moves=[
  move('01',{qr_key:'l1',qty:2}),
  move('01',{qty:3,unit:'袋',slip_weight:999}),
  move('02',{weight:0}),
  move('03',{qty:2,unit:'基'}),
  move('05',{destination:'大阪',weight:99}),
  move('06',{item_name:'他品目',weight:11}),
  move('06',{item_name:'網出庫',qr_key:'l2',qty:2,unit:'基',slip_weight:444}),
  move('06',{item_name:'網出庫',qr_key:'l2',qty:1,unit:'基',weight:7,slip_weight:555}),
  move('01',{item_name:'他品目',weight:2,occurred_at:'2026-10-01T01:00:00+09:00'}),
  move('02',{weight:400,cancelled_at:'2026-11-03T00:00:00Z'}),
  move('02',{weight:500,destination:'廃棄'}),
  move('02',{weight:600,movement_type:'入庫'}),
  move('01',{weight:700,occurred_at:'2026-10-31T23:59:59+09:00'}),
 ];
 window.__analysisReads=[];window.__alerts=[];
 window.alert=m=>__alerts.push(String(m));
 window.v163SelectAll=async table=>{__analysisReads.push(table);return table==='qr_lots'?lots:moves};
}"""


class Quiet(SimpleHTTPRequestHandler):
    def log_message(self, *_):
        pass


class AnalysisDailyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(Quiet, directory=str(ROOT)))
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()
        cls.origin = f'127.0.0.1:{cls.server.server_port}'
        cls.pw = sync_playwright().start()
        cls.browser = cls.pw.chromium.launch()

    @classmethod
    def tearDownClass(cls):
        cls.browser.close()
        cls.pw.stop()
        cls.server.shutdown()
        cls.server.server_close()

    def open_app(self, role='admin'):
        ctx = self.browser.new_context(service_workers='block', timezone_id='Asia/Tokyo', locale='ja-JP', accept_downloads=True)
        self.addCleanup(ctx.close)
        ctx.add_init_script(CLOCK)
        ctx.route('**/*', lambda route: route.continue_() if urlparse(route.request.url).netloc == self.origin else route.abort())
        page = ctx.new_page()
        errors = []
        page.on('pageerror', lambda e: errors.append(str(e)))
        self.addCleanup(lambda: self.assertEqual(errors, []))
        page.goto('http://' + self.origin + '/index.html', wait_until='load')
        page.wait_for_function("()=>typeof c81AnalysisPage==='function' && typeof XLSX!=='undefined'")
        page.wait_for_timeout(500)
        page.evaluate(MOCK, role)
        page.evaluate(FIXTURE)
        return page

    def open_selected(self, page):
        page.evaluate("()=>c81AnalysisPage('out')")
        page.locator('#c81Item').wait_for()
        page.locator('#c81Item').select_option(label='出庫のみ')
        page.locator('#c81Daily').wait_for()
        page.locator('#c81Dest').select_option(label='本社')
        page.locator('#c81Daily').wait_for()

    def test_daily_zero_unknown_sum_averages_units_and_scope(self):
        page = self.open_app()
        self.open_selected(page)
        body = page.locator('#c81Daily').inner_text()
        for text in ('期間合計：20kg', '出庫日平均：6.7kg（3日）', '全日平均：3.3kg（6日）', '4件', 'kg不明 2件', '実際より少ない可能性'):
            self.assertIn(text, body)
        def row(day):
            return page.locator(f'[data-c81-day="2026-11-{day}"] td').all_inner_texts()
        self.assertEqual(row('01'), ['2026-11-01', '20kg', '2ケース・3袋', '2', '1'])
        self.assertEqual(row('02'), ['2026-11-02', '0kg', '1ケース', '1', '0'])
        self.assertEqual(row('03'), ['2026-11-03', '不明', '2基', '1', '1'])
        self.assertEqual(row('04'), ['2026-11-04', '0kg', '—', '0', '0'])
        self.assertEqual(row('05'), ['2026-11-05', '0kg', '—', '0', '0'])
        self.assertNotIn('999', body)
        # Candidate exists despite no inventory snapshot or active master item.
        self.assertEqual(page.locator('#c81Item').input_value(), '出庫のみ')
        self.assertIn('本社', page.locator('#c81Dest').input_value())

    def test_tabs_period_and_excel_follow_same_selection(self):
        page = self.open_app()
        self.open_selected(page)
        page.get_by_role('button', name='在庫推移', exact=True).click()
        page.locator('#c81Item').wait_for()
        self.assertEqual(page.locator('#c81Item').input_value(), '出庫のみ')
        self.assertEqual(page.locator('#c81Dest').input_value(), '本社')
        page.get_by_role('button', name='出庫数量', exact=True).click()
        page.locator('#c81Daily').wait_for()
        page.get_by_role('button', name='自由に指定', exact=True).click()
        page.locator('#c81From').wait_for()
        page.evaluate("""()=>{document.getElementById('c81From').value='2026-11-01';
            document.getElementById('c81To').value='2026-11-03';c81SetCustom()}""")
        page.wait_for_function("()=>document.querySelectorAll('[data-c81-day]').length===3")
        self.assertIn('全日平均：6.7kg（3日）', page.locator('#c81Daily').inner_text())
        with page.expect_download(timeout=30000) as event:
            page.get_by_role('button', name='選択条件をExcelにする').click()
        download = event.value
        self.assertIsNone(download.failure())
        sheets = read_xlsx(Path(download.path()).read_bytes())
        conditions = dict(sheets['選択条件'][1:])
        self.assertEqual(conditions['期間'], '2026-11-01〜2026-11-03')
        self.assertEqual(conditions['品目'], '出庫のみ')
        self.assertEqual(conditions['出庫先'], '本社')
        self.assertEqual(sheets['出庫日量'][1][:5], ['2026-11-01', 20, '2ケース・3袋', 2, 1])
        self.assertEqual(sheets['出庫日量'][2][:5], ['2026-11-02', 0, '1ケース', 1, 0])
        self.assertEqual(sheets['出庫日量'][3][:5], ['2026-11-03', '', '2基', 1, 1])
        self.assertEqual(sheets['出庫日量'][4][:5], ['期間合計', 20, '3ケース・3袋・2基', 4, 2])
        details = sheets['出庫明細'][1:]
        self.assertEqual(len(details), 4)
        self.assertTrue(all(r[1] == '本社' and r[2] == '出庫のみ' for r in details))
        self.assertEqual([r[6] for r in details], [20, '', 0, ''])
        self.assertEqual(page.evaluate('()=>__alerts'), [])

    def test_destination_and_item_can_be_changed_and_prior_period_compares_selection(self):
        page = self.open_app()
        self.open_selected(page)
        page.locator('#c81Dest').select_option(label='大阪')
        page.locator('#c81Daily').wait_for()
        body = page.locator('#c81Daily').inner_text()
        self.assertIn('期間合計：99kg', body)
        self.assertIn('出庫日平均：99kg（1日）', body)
        self.assertIn('全日平均：16.5kg（6日）', body)
        page.locator('#c81Dest').select_option(value='')
        page.locator('#c81Daily').wait_for()
        self.assertIn('期間合計：119kg', page.locator('#c81Daily').inner_text())
        page.locator('#c81Item').select_option(label='他品目')
        page.locator('#c81Daily').wait_for()
        self.assertIn('期間合計：11kg', page.locator('#c81Daily').inner_text())
        self.assertIn('↑450%', page.locator('#c81Body').inner_text())
        page.locator('#c81Item').select_option(label='網出庫')
        page.locator('#c81Daily').wait_for()
        self.assertIn('期間合計：207kg', page.locator('#c81Daily').inner_text())
        self.assertEqual(page.locator('[data-c81-day="2026-11-06"] td').all_inner_texts(),
                         ['2026-11-06', '207kg', '3基', '2', '0'])

    def test_guide_describes_scope_and_averages(self):
        page = self.open_app()
        guide = page.evaluate("()=>V198_GUIDE_SECTIONS.c81Analysis")
        text = ' '.join(guide['steps']) + guide['check']
        for phrase in ('出庫日平均', '全日平均', 'kg不明', '本社', '伝票重量', '選択条件をExcel'):
            self.assertIn(phrase, text)

    def test_unknown_only_and_no_outbound_days(self):
        page = self.open_app()
        self.open_selected(page)
        page.get_by_role('button', name='自由に指定', exact=True).click()
        page.locator('#c81From').wait_for()
        page.evaluate("""()=>{document.getElementById('c81From').value='2026-11-03';
           document.getElementById('c81To').value='2026-11-04';c81SetCustom()}""")
        page.wait_for_function("()=>document.querySelectorAll('[data-c81-day]').length===2")
        body = page.locator('#c81Daily').inner_text()
        for text in ('期間合計：不明', '出庫日平均：不明（1日）', '全日平均：不明（2日）'):
            self.assertIn(text, body)
        with page.expect_download(timeout=30000) as event:
            page.get_by_role('button', name='選択条件をExcelにする').click()
        sheets = read_xlsx(Path(event.value.path()).read_bytes())
        self.assertEqual(sheets['出庫日量'][1][1], '')
        self.assertEqual(sheets['出庫日量'][2][1], 0)
        self.assertEqual(sheets['出庫日量'][3][1], '')
        self.assertEqual(sheets['出庫_出庫先別'][1][2], '')
        page.locator('#c81Item').select_option(label='他品目')
        page.locator('#c81Daily').wait_for()
        body = page.locator('#c81Daily').inner_text()
        for text in ('期間合計：0kg', '出庫日平均：—（0日）', '全日平均：0kg（2日）'):
            self.assertIn(text, body)

    def test_denied_roles_cannot_load_or_export(self):
        for role in ('hq_prep', 'hq_receiver'):
            page = self.open_app(role)
            page.evaluate("""async()=>{window.__analysisDownloads=[];window.downloadWorkbookXlsx=(...a)=>__analysisDownloads.push(a);await c81AnalysisPage('out');await c81Excel()}""")
            self.assertEqual(page.evaluate('()=>__analysisReads'), [], role)
            self.assertEqual(page.evaluate('()=>__analysisDownloads'), [], role)
            self.assertNotEqual(page.evaluate('()=>currentScreen'), 'c81AnalysisPage', role)


if __name__ == '__main__':
    unittest.main()
