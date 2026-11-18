import functools
import threading
import unittest
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parent.parent
MOCK = (ROOT / 'tests/mock_hq.js').read_text(encoding='utf-8')


class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, *_args):
        pass


class MeshTypesTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(QuietHandler, directory=str(ROOT)))
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.url = f'http://127.0.0.1:{cls.server.server_port}/index.html'
        cls.netloc = urlparse(cls.url).netloc
        cls.playwright = sync_playwright().start()
        cls.browser = cls.playwright.chromium.launch()

    @classmethod
    def tearDownClass(cls):
        cls.browser.close()
        cls.playwright.stop()
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join(timeout=3)

    def open_app(self, role='worker'):
        context = self.browser.new_context(service_workers='block', timezone_id='Asia/Tokyo', viewport={'width': 900, 'height': 1200})
        self.addCleanup(context.close)
        context.route('**/*', lambda r: r.continue_() if urlparse(r.request.url).netloc == self.netloc else r.abort())
        page = context.new_page()
        errors = []
        page.on('pageerror', lambda e: errors.append(str(e)))
        self.addCleanup(lambda: self.assertEqual(errors, []))
        page.goto(self.url, wait_until='load')
        page.wait_for_function('()=>typeof meshContainerPage==="function"&&typeof v1234LoadHistoryTruth==="function"')
        page.wait_for_timeout(300)
        page.evaluate(MOCK, role)
        page.evaluate('''()=>{
          db.userId='test'; db.meshContainers={records:[{id:'old',checkedAt:new Date(Date.now()-60000).toISOString(),values:{bluePurple:'11',orange:'0',newContainer:'5',nikken:'4'},memo:'old memo',user:'test'}]};
          window.__alerts=[];window.alert=m=>__alerts.push(String(m));window.confirm=()=>true;
          window.save=()=>{window.__saves=(window.__saves||0)+1};
          meshContainerPage();
        }''')
        return page

    @staticmethod
    def click(page, action, parent=None):
        (parent or page).locator(f'[data-seika-click-action="{action}"]').click()

    def test_legacy_values_and_new_default_and_unknown_empty(self):
        page = self.open_app()
        for key, value in [('bluePurple', '11'), ('orange', '0'), ('newContainer', '5'), ('nikken', '4'), ('orangeFoot', '')]:
            self.assertEqual(page.locator('#mesh_' + key).input_value(), value)
        self.assertIn('新オレンジ足', page.locator('main').inner_text())
        before = page.evaluate('()=>JSON.stringify(db.meshContainers.records[0])')
        self.click(page, 'saveMeshContainer')
        self.assertEqual(page.evaluate('()=>JSON.stringify(db.meshContainers.records[0])'), before)
        self.assertEqual(page.evaluate('()=>meshContainerLatest().values.orangeFoot'), '')
        self.assertEqual(page.evaluate('()=>meshContainerLatest().values.orange'), '0')

    def test_manage_preserves_draft_and_stopped_values_and_reactivate(self):
        page = self.open_app('admin')
        page.locator('#mesh_bluePurple').fill('37')
        page.locator('#mesh_orange').fill('8')
        page.locator('#meshMemo').fill('未保存メモ')
        page.locator('#meshTypeManager summary').click()
        page.locator('#meshType_bluePurple').fill('青紫 改')
        self.click(page, 'meshRenameType', page.locator('#meshType_bluePurple').locator('xpath=..'))
        self.assertEqual(page.locator('#mesh_bluePurple').input_value(), '37')
        self.assertEqual(page.locator('#meshMemo').input_value(), '未保存メモ')
        self.assertEqual(page.evaluate('()=>db.meshContainers.records.length'), 1)
        page.locator('#meshTypeNew').fill('追加網')
        self.click(page, 'meshAddType')
        new_id = page.evaluate("()=>db.meshContainers.types.find(x=>x.name==='追加網').id")
        self.assertEqual(page.locator('#mesh_' + new_id).input_value(), '')
        self.assertEqual(page.locator('#mesh_orange').input_value(), '8')
        self.click(page, 'meshToggleType', page.locator('#meshType_orange').locator('xpath=..'))
        self.assertEqual(page.locator('#mesh_orange').count(), 0)
        self.assertEqual(page.locator('#mesh_bluePurple').input_value(), '37')
        self.click(page, 'saveMeshContainer')
        result = page.evaluate('()=>({records:db.meshContainers.records,types:db.meshContainers.types})')
        self.assertEqual(result['records'][-1]['values']['orange'], '8')
        self.assertEqual(result['records'][-1]['values']['bluePurple'], '37')
        self.assertEqual(result['records'][-1]['memo'], '未保存メモ')
        self.assertFalse(next(x for x in result['types'] if x['id'] == 'orange')['active'])
        page.locator('#meshTypeManager summary').click()
        self.click(page, 'meshToggleType', page.locator('#meshType_orange').locator('xpath=..'))
        self.assertEqual(page.locator('#mesh_orange').input_value(), '8')
        self.assertEqual(page.locator('#mesh_bluePurple').input_value(), '37')
        self.assertEqual(page.evaluate("()=>db.meshContainers.types.find(x=>x.id==='bluePurple').name"), '青紫 改')
        page.evaluate('()=>{db=normalize(JSON.parse(JSON.stringify(db)));meshContainerPage()}')
        self.assertEqual(page.locator('#mesh_orange').input_value(), '8')
        self.assertEqual(page.locator('#mesh_bluePurple').input_value(), '37')
        self.assertEqual(page.locator('#mesh_' + new_id).input_value(), '')

    def test_duplicate_empty_and_invalid_quantities_leave_data_unchanged(self):
        page = self.open_app()
        page.locator('#meshTypeManager summary').click()
        page.locator('#meshTypeNew').fill(' せき青紫 ')
        self.click(page, 'meshAddType')
        page.locator('#meshTypeNew').fill('   ')
        self.click(page, 'meshAddType')
        page.locator('#meshType_orange').fill('せき青紫')
        self.click(page, 'meshRenameType', page.locator('#meshType_orange').locator('xpath=..'))
        page.locator('#mesh_bluePurple').fill('-1')
        self.click(page, 'saveMeshContainer')
        self.assertEqual(page.evaluate('()=>db.meshContainers.records.length'), 1)
        self.assertEqual(page.evaluate('()=>window.__saves||0'), 0)
        self.assertEqual(len(page.evaluate('()=>window.__alerts')), 4)
        page.locator('#mesh_bluePurple').fill('1.5')
        self.click(page, 'saveMeshContainer')
        self.assertEqual(page.evaluate('()=>db.meshContainers.records.length'), 1)

    def test_roles_and_direct_calls(self):
        for role in ['buyer', 'clerk', 'sales', 'viewer', 'office_viewer']:
            with self.subTest(role=role):
                page = self.open_app(role)
                self.assertEqual(page.locator('#meshTypeManager').count(), 0)
                self.assertTrue(page.locator('#mesh_bluePurple').is_disabled())
                before = page.evaluate('()=>JSON.stringify(db.meshContainers)')
                page.evaluate("()=>{meshAddType();meshRenameType('orange');meshToggleType('orange');saveMeshContainer()}")
                self.assertEqual(page.evaluate('()=>JSON.stringify(db.meshContainers)'), before)
                self.assertFalse(page.evaluate('()=>window.__saves||0'))
                self.assertEqual(len(page.evaluate('()=>window.__alerts')), 4)

    def test_stopped_saved_quantity_survives_multiple_records_without_becoming_zero(self):
        page = self.open_app('worker')
        page.locator('#meshTypeManager summary').click()
        self.click(page, 'meshToggleType', page.locator('#meshType_orange').locator('xpath=..'))
        self.click(page, 'saveMeshContainer')
        page.locator('#mesh_bluePurple').fill('25')
        self.click(page, 'saveMeshContainer')
        result = page.evaluate('()=>db.meshContainers.records.map(r=>r.values)')
        self.assertTrue(all(r['orange'] == '0' for r in result))
        self.assertEqual(result[0], {'bluePurple': '11', 'orange': '0', 'newContainer': '5', 'nikken': '4'})
        self.assertEqual(result[-1]['orangeFoot'], '')
        page.locator('#meshTypeManager summary').click()
        self.click(page, 'meshToggleType', page.locator('#meshType_orange').locator('xpath=..'))
        self.assertEqual(page.locator('#mesh_orange').input_value(), '0')

    def test_guide_and_role_payload(self):
        page = self.open_app('worker')
        result = page.evaluate('''()=>{
          const payload=v161Snapshot();
          return {payload:payload.meshContainers,worker:v188RolePayload(payload,'worker').meshContainers,
            admin:v188RolePayload(payload,'admin').meshContainers,
            others:['buyer','clerk','viewer','sales','office_viewer'].map(r=>Object.hasOwn(v188RolePayload(payload,r),'meshContainers')),
            guides:['admin','worker'].map(r=>V195_ROLE_GUIDES[r].sections.find(x=>x.title.includes('網コンテナ')))}
        }''')
        self.assertEqual(result['payload'], result['worker'])
        self.assertEqual(result['payload'], result['admin'])
        self.assertFalse(any(result['others']))
        self.assertTrue(all('再開' in str(g) and '数量' in str(g) for g in result['guides']))

    def test_final_rpc_path_sends_mesh_changes_for_worker_and_admin(self):
        for role in ('worker', 'admin'):
            with self.subTest(role=role):
                page = self.open_app(role)
                result = page.evaluate('''async()=>{
                  const base=v161Snapshot();
                  db.meshContainers.types[0].name='新しい名前';
                  db.meshContainers.types[1].active=false;
                  db.meshContainers.types.push({id:'extra',name:'網追加',active:true});
                  const payload=v161Snapshot(),old=window.fetch;
                  try{
                    window.fetch=async(url,options)=>({ok:true,json:async()=>({name:String(url).split('/').pop(),args:JSON.parse(options.body)})});
                    return await v188SendSyncItem({id:'fake',basePayload:base,operationId:'fake'},payload,7);
                  } finally {window.fetch=old}
                }''')
                self.assertEqual(result['name'], 'update_app_state_partial_v188')
                mesh = result['args']['p_changes']['meshContainers']
                self.assertEqual(mesh['types'][0]['name'], '新しい名前')
                self.assertFalse(mesh['types'][1]['active'])
                self.assertEqual(mesh['types'][-1]['id'], 'extra')
                self.assertEqual(mesh['records'][0]['values']['bluePurple'], '11')

    def test_final_conflict_retry_path_keeps_settings_and_remote_history(self):
        page = self.open_app('worker')
        result = page.evaluate('''async()=>{
          const base=v161Snapshot(),local=structuredClone(base),remote=structuredClone(base);
          local.meshContainers.types[0].name='統合した種類';
          remote.meshContainers.records.push({id:'remote',checkedAt:new Date().toISOString(),values:{bluePurple:'22'}});
          const item={id:'test-queue',basePayload:base,localPayload:local,operationId:'test-op'};
          let sent=null,queue=[item];
          v188IdbFlush=async()=>{};v188AssertPendingOwner=()=>{};
          v161ReadQueue=()=>queue;v161WriteQueue=q=>{queue=q};
          v1234LoadHistoryTruth=async()=>({records:[],movements:[],wasteRecords:[]});
          v188FetchRemoteState=async()=>({payload:remote,version:9});
          v188SendSyncItem=async(candidate,payload,version)=>{sent={payload,version};return {ok:true,version:10}};
          v188PersistDb=()=>{};v188WriteBase=()=>{};markSync=()=>{};setSyncState=()=>{};
          historyTablesReady=false;
          const outcome=await v178ResolvePendingInventoryConflict();
          return {outcome,sent,queue,db:db.meshContainers};
        }''')
        self.assertTrue(result['outcome']['ok'])
        self.assertEqual(result['sent']['version'], 9)
        self.assertEqual(result['sent']['payload']['meshContainers']['types'][0]['name'], '統合した種類')
        self.assertEqual({r['id'] for r in result['db']['records']}, {'old', 'remote'})
        self.assertEqual(result['db']['types'][0]['name'], '統合した種類')
        self.assertEqual(result['queue'], [])

    def test_post_history_merge_and_conflict_never_drop_configuration(self):
        page = self.open_app('worker')
        result = page.evaluate('''()=>{
          const base={meshContainers:{records:[{id:'old',values:{orange:'4'},checkedAt:new Date().toISOString()}],types:[{id:'orange',name:'旧名',active:true}]}},
            local=structuredClone(base),remote=structuredClone(base);
          local.meshContainers.types[0].name='新名';
          remote.meshContainers.records.push({id:'remote',values:{orange:'2'},checkedAt:new Date().toISOString()});
          v1234History={records:[],movements:[],wasteRecords:[]};
          try {
            const combined=v121MergePayload(base,local,remote);
            remote.meshContainers.types[0].name='別名';
            const conflict=v121MergePayload(base,local,remote);
            return {combined,conflict};
          } finally {v1234History=null}
        }''')
        self.assertTrue(result['combined']['ok'], result)
        merged = result['combined']['merged']['meshContainers']
        self.assertEqual(merged['types'][0]['name'], '新名')
        self.assertEqual({r['id'] for r in merged['records']}, {'old', 'remote'})
        self.assertFalse(result['conflict']['ok'])
        self.assertTrue(any('meshContainers' in c for c in result['conflict']['conflicts']))


if __name__ == '__main__':
    unittest.main()
