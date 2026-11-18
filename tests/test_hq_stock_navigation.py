"""本社・石岡閲覧の動線をローカルモックだけで検証する。"""
import functools
import threading
import unittest
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parent.parent
MOCK = (ROOT / 'tests/mock_hq.js').read_text(encoding='utf-8')


class HqStockNavigation(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        handler = type('Quiet', (SimpleHTTPRequestHandler,), {'log_message': lambda *args: None})
        cls.server = ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(handler, directory=str(ROOT)))
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()
        cls.origin = f'http://127.0.0.1:{cls.server.server_port}'
        cls.pw = sync_playwright().start()
        cls.browser = cls.pw.chromium.launch()

    @classmethod
    def tearDownClass(cls):
        cls.browser.close()
        cls.pw.stop()
        cls.server.shutdown()
        cls.server.server_close()

    def app(self, role='hq_worker'):
        context = self.browser.new_context(viewport={'width': 820, 'height': 1180}, service_workers='block')
        self.addCleanup(context.close)
        blocked = []

        def route_request(route):
            request = route.request
            url = urlparse(request.url)
            # 同一ポートの静的ファイルだけ。外部通信・API・書き込みはすべて遮断。
            allowed = (f'{url.scheme}://{url.netloc}' == self.origin and request.method == 'GET'
                       and (url.path == '/index.html' or url.path.startswith(('/js/', '/css/', '/vendor/', '/icons/'))
                            or url.path in ('/manifest.webmanifest', '/release-notes.json')))
            if allowed:
                route.continue_()
            else:
                blocked.append(request.url)
                route.abort()

        context.route('**/*', route_request)
        page = context.new_page()
        page.set_default_timeout(5000)
        errors = []
        page.on('pageerror', lambda error: errors.append(str(error)))
        self.addCleanup(lambda: self.assertEqual(errors, []))
        page.goto(self.origin + '/index.html', wait_until='load')
        page.wait_for_timeout(1000)
        page.evaluate(MOCK, role)
        page.evaluate('''() => {
          window.__blockedTestCalls=[];
          const t=window.__T;
          t.hq_lots_v1400.push(
            {...t.hq_lots_v1400[0],id:'L4',qr_key:'K4',lot_no:'H-04',item_name:'キャベツ大',current_qty:50},
            {...t.hq_lots_v1400[0],id:'L5',qr_key:'K5',lot_no:'H-05',item_name:'キャベツ',current_qty:3},
            {...t.hq_lots_v1400[0],id:'L6',qr_key:'K6',lot_no:'H-06',item_name:'キャベツ',status:'在庫なし',current_qty:0});
          t.qr_lots=[{id:'Q1',qr_key:'QK1',lot_no:'Q-01',item_name:'キャベツ',active:true,current_qty:4,unit:'case',pack_weight:'10kg',received_date:ymdKey(new Date()),supplier:'架空',origin:'茨城'}];
          const old=qrSelect;
          qrSelect=async (name,q)=>{window.__blockedTestCalls.push([name,q]);return old(name,q)};
          const rpc=callRpc;callRpc=async(name,args)=>{window.__blockedTestCalls.push(['rpc',name]);return rpc(name,args)};
        }''')
        page._blocked_for_test = blocked
        return page

    def click(self, page, action):
        page.locator(f'[data-seika-click-action="{action}"]').first.click()

    def screen(self, page, expected):
        page.wait_for_function('(name)=>currentScreen===name', arg=expected)

    def actions(self, page):
        return page.locator('.hqHomeGrid > button').evaluate_all("els=>els.map(e=>e.dataset.seikaClickAction)")

    def colors_unique(self, page):
        colors = page.locator('.hqHomeGrid > button').evaluate_all('els=>els.map(e=>getComputedStyle(e).backgroundImage)')
        self.assertEqual(len(colors), len(set(colors)), colors)
        self.assertNotIn('none', colors)

    def test_purpose_hubs_roles_and_colors(self):
        cases = {
            'admin': {'hqPrepCheckPage', 'hqPrepMasterPage', 'hqStaffPage', 'hqYieldPage'},
            'hq_worker': {'hqPrepCheckPage', 'hqPrepMasterPage', 'hqStaffPage', 'hqYieldPage'},
            'hq_clerk': {'hqYieldPage', 'hqWorkTimePage'},
            'hq_receiver': set(),
            'buyer': {'hqYieldPage', 'hqWorkTimePage'},
            'viewer': set(),
        }
        common = {'hqReceiveHub', 'hqStockHub', 'hqOperationsHub', 'hqRecordsHub'}
        for role, prep in cases.items():
            with self.subTest(role=role):
                page = self.app(role)
                page.evaluate("()=>hqSetSite('honsha')")
                self.screen(page, 'hqHome')
                self.assertEqual(set(self.actions(page)), common | prep)
                self.colors_unique(page)
                self.click(page, 'hqStockHub')
                self.screen(page, 'hqStockHub')
                self.assertEqual(self.actions(page), ['hqTablePage', 'hqStockPage'])
                self.colors_unique(page)
                page.evaluate('goBack()')
                self.screen(page, 'hqHome')
                self.click(page, 'hqReceiveHub')
                self.screen(page, 'hqReceiveHub')
                acts = self.actions(page)
                self.assertIn('hqPendingPage', acts)
                self.assertEqual('hqDirectPage' in acts, role in ('admin', 'hq_worker', 'hq_receiver'))
                self.assertEqual('hqScanPage' in acts, role in ('admin', 'hq_worker', 'hq_receiver'))
                self.colors_unique(page)
                page.evaluate('goBack()')
                self.click(page, 'hqOperationsHub')
                self.screen(page, 'hqOperationsHub')
                acts = self.actions(page)
                self.assertEqual('hqNormalPage' in acts, role in ('admin', 'hq_worker', 'hq_receiver'))
                self.assertEqual('hqOutPage' in acts, role in ('admin', 'hq_worker'))
                self.assertEqual('hqStocktakePage' in acts, role in ('admin', 'hq_worker'))
                self.colors_unique(page)
                page.evaluate('goBack()')
                self.click(page, 'hqRecordsHub')
                self.screen(page, 'hqRecordsHub')
                acts = self.actions(page)
                self.assertIn('hqHistoryPage', acts)
                self.assertIn('hqQualityPage', acts)
                self.assertIn('v195RoleGuidePage', acts)
                self.assertEqual('hqWastePage' in acts, role in ('admin', 'hq_worker', 'hq_clerk', 'buyer'))
                self.assertEqual('hqItemsPage' in acts, role in ('admin', 'hq_worker'))
                self.assertEqual('hqItemRulesPage' in acts, role in ('admin', 'hq_worker'))
                self.assertEqual('hqExcelPage' in acts, role in ('admin', 'hq_worker', 'hq_clerk', 'buyer'))
                self.colors_unique(page)

    def test_stock_select_exact_search_status_and_back(self):
        page = self.app()
        page.evaluate('hqHome()')
        self.click(page, 'hqStockHub')
        self.click(page, 'hqStockPage')
        page.wait_for_function("()=>document.querySelectorAll('#hqStockItem option').length>=4")
        self.assertEqual(page.locator('.hqLotCard').count(), 0)
        page.select_option('#hqStockItem', 'キャベツ')
        page.wait_for_function("()=>document.querySelectorAll('.hqLotCard').length===2")
        self.assertEqual(page.locator('.hqLotCard').count(), 2)
        self.assertNotIn('キャベツ大', page.locator('#hqList').inner_text())
        self.assertIn('11', page.locator('#hqList table').inner_text())
        page.fill('#hqStockFilter', 'H-05')
        page.locator('#hqStockFilter').press('Tab')
        page.wait_for_function("()=>document.querySelectorAll('.hqLotCard').length===1")
        self.assertIn('H-05', page.locator('#hqList').inner_text())
        self.assertEqual(page.locator('#hqStockItem').input_value(), 'キャベツ')
        self.click(page, 'hqStockOpenLot')
        self.screen(page, 'hqLotPage')
        page.wait_for_selector('.hqLotCard')
        page.evaluate('goBack()')
        self.screen(page, 'hqStockPage')
        page.wait_for_function("()=>document.querySelector('#hqStockItem').value==='キャベツ' && document.querySelectorAll('.hqLotCard').length===1")
        self.assertEqual(page.locator('#hqStockFilter').input_value(), 'H-05')
        page.fill('#hqStockFilter', '')
        page.locator('#hqStockFilter').press('Tab')
        page.wait_for_function("()=>document.querySelectorAll('.hqLotCard').length===2")
        page.get_by_role('button', name='在庫なし', exact=True).click()
        page.wait_for_function("()=>document.querySelectorAll('.hqLotCard').length===1")
        self.assertIn('H-06', page.locator('#hqList').inner_text())
        self.assertEqual(page.locator('#hqStockItem').input_value(), 'キャベツ')
        self.assertEqual(page.locator('#hqList table').count(), 0)
        page.select_option('#hqStockItem', '')
        page.fill('#hqStockFilter', 'さくら')
        page.locator('#hqStockFilter').press('Tab')
        page.wait_for_function("()=>document.querySelector('#hqList').textContent.includes('該当するロットはありません')")
        page.get_by_role('button', name='すべて', exact=True).click()
        page.wait_for_function("()=>document.querySelector('#hqList').textContent.includes('玉ねぎ')")
        self.assertNotIn('キャベツ大', page.locator('#hqList').inner_text())
        page.evaluate("()=>{__T.hq_lots_v1400=[]}")
        page.evaluate("()=>hqStockPage('', '在庫あり', '')")
        page.wait_for_function("()=>document.querySelector('#hqList').textContent.includes('該当するロットはありません')")

    def test_stage2_and_prep_home_unchanged(self):
        page = self.app('hq_worker')
        page.evaluate("()=>{__T.hq_settings_v1500[0].value=true; __h2.H2.s2=null;}")
        page.evaluate('hqHome()')
        self.click(page, 'hqOperationsHub')
        self.screen(page, 'hqOperationsHub')
        self.assertNotIn('hqOutPage', self.actions(page))
        self.assertIn('hqStocktakePage', self.actions(page))
        prep = self.app('hq_prep')
        prep.evaluate('hqHome()')
        self.screen(prep, 'hqPrepHome')
        prep.wait_for_selector('[data-seika-click-action="hqPrepNew"]')
        self.assertEqual(prep.locator('[data-seika-click-action="hqPrepNew"]').count(), 3)
        self.assertEqual(prep.locator('[data-seika-click-action="hqOutPage"]').count(), 1)
        self.click(prep, 'hqOutPage')
        self.screen(prep, 'hqOutPage')
        prep.evaluate('goBack()')
        self.screen(prep, 'hqPrepHome')

    def test_ishioka_two_entries_and_real_total_to_lot(self):
        page = self.app('hq_worker')
        page.evaluate("()=>hqSetSite('ishioka')")
        self.assertEqual(self.actions(page)[:2], ['weeklyData', 'qrTotalsPage'])
        self.assertNotIn('qrLotListPage', self.actions(page))
        self.colors_unique(page)
        self.click(page, 'qrTotalsPage')
        self.screen(page, 'qrTotalsPage')
        page.wait_for_selector('[data-seika-click-action="qrLotListPage"]')
        self.assertIn('キャベツ', page.locator('body').inner_text())
        item = page.locator('a[data-seika-click-action="qrLotListPage"]').filter(has_text='キャベツ')
        item.click()
        self.screen(page, 'qrLotListPage')
        page.wait_for_selector('#qrLotItemFilter')
        self.assertEqual(page.locator('#qrLotItemFilter').input_value(), 'キャベツ')
        self.assertIn('Q-01', page.locator('body').inner_text())
        self.assertEqual(page.locator('[data-seika-click-action="qrCreatePage"]').count(), 0)
        page.evaluate('goBack()')
        self.screen(page, 'qrTotalsPage')

    def test_existing_destinations_and_back_paths(self):
        page = self.app('hq_worker')
        page.evaluate("()=>hqSetSite('honsha')")
        for hub, target, screen in [
            ('hqReceiveHub', 'hqPendingPage', 'hqPendingPage'),
            ('hqReceiveHub', 'hqDirectPage', 'hqDirectPage'),
            ('hqStockHub', 'hqTablePage', 'hqTablePage'),
            ('hqOperationsHub', 'hqNormalPage', 'hqNormalPage'),
            ('hqOperationsHub', 'hqStocktakePage', 'hqStocktakePage'),
            ('hqRecordsHub', 'hqHistoryPage', 'hqHistoryPage'),
            ('hqRecordsHub', 'hqItemsPage', 'hqItemsPage'),
            ('hqRecordsHub', 'hqQualityPage', 'hqQualityPage'),
            ('hqRecordsHub', 'hqUsagePage', 'hqUsagePage'),
        ]:
            with self.subTest(target=target):
                page.evaluate("()=>hqSetSite('honsha')")
                self.click(page, hub)
                page.wait_for_selector(f'[data-seika-click-action="{target}"]')
                self.click(page, target)
                self.screen(page, screen)
                page.wait_for_timeout(100)
                page.evaluate('goBack()')
                self.screen(page, hub)
        for target in ['hqPrepCheckPage', 'hqPrepMasterPage', 'hqStaffPage', 'hqYieldPage']:
            page.evaluate("()=>hqSetSite('honsha')")
            self.click(page, target)
            self.screen(page, target)
            page.wait_for_timeout(100)
            page.evaluate('goBack()')
            self.screen(page, 'hqHome')

    def test_stock_race_and_view_only_lot(self):
        page = self.app('hq_clerk')
        page.evaluate("""()=>{
          const old=qrSelect;
          qrSelect=async(t,q)=>{if(t==='hq_lots_v1400' && q.includes('status=eq.在庫あり'))await new Promise(r=>setTimeout(r,350));return old(t,q)};
        }""")
        page.evaluate("()=>hqSetSite('honsha')")
        self.click(page, 'hqStockHub')
        self.click(page, 'hqStockPage')
        page.get_by_role('button', name='在庫なし', exact=True).click()
        page.wait_for_function("()=>document.querySelector('#hqStockItem option[value=キャベツ]')")
        page.wait_for_timeout(500)
        self.assertIn('在庫なし', page.locator('.filterBtn.on').inner_text())
        page.select_option('#hqStockItem', 'キャベツ')
        page.wait_for_function("()=>document.querySelectorAll('.hqLotCard').length===1")
        self.click(page, 'hqStockOpenLot')
        self.screen(page, 'hqLotPage')
        page.wait_for_selector('.hqLotCard')
        self.assertEqual(page.locator('[data-seika-click-action=hqDoOut]').count(), 0)
        self.assertEqual(page.locator('[data-seika-click-action=hqDoAdjust]').count(), 0)
        self.assertEqual(page.locator('[data-seika-click-action=hqDoReceive]').count(), 0)

    def test_guides_and_network_boundary(self):
        page = self.app('hq_worker')
        page.evaluate('hqHome()')
        self.click(page, 'hqRecordsHub')
        self.click(page, 'v195RoleGuidePage')
        self.screen(page, 'v195RoleGuidePage')
        guide = page.locator('body').text_content()
        self.assertIn('在庫を見る', guide)
        self.assertIn('品目別在庫・ロット', guide)
        self.assertIn('入荷・受け入れ', guide)
        self.assertIn('下処理の確認', guide)
        self.assertIn('スタッフQR', guide)
        ishioka = page.evaluate("()=>V195_ROLE_GUIDES.hq_worker.sections.find(s=>s.title==='本社のアカウントで石岡の情報を見る').steps.join(' ')")
        self.assertIn('品目名を押すとロット一覧', ishioka)
        # 静的リソース以外の通信は route_request が必ず遮断する。
        self.assertFalse(any(url.startswith(self.origin + '/rest/') for url in page._blocked_for_test))


if __name__ == '__main__':
    unittest.main()
