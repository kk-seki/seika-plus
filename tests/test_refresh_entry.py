import json
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HARNESS = r'''
const vm=require('node:vm');
const input=JSON.parse(require('node:fs').readFileSync(0,'utf8'));
async function run(){
 const events=[],failure=new Error(input.mode);
 let pending=['pending','conflict','save-error','remaining'].includes(input.mode)?1:0;
 let release;
 const context={
  v177ReloadRunning:input.mode==='running',
  syncState:input.mode==='conflict'?'競合':'未同期',
  v188StorageInit(){events.push('init');if(input.mode==='init-error')return Promise.reject(failure);return Promise.resolve()},
  v188IdbFlush(){
   events.push('flush');
   if(input.mode==='flush-error')return Promise.reject(failure);
   if(input.mode==='flush-pending')return new Promise(resolve=>{release=resolve});
   return Promise.resolve();
  },
  v161PendingCount(){return pending},
  async saveCloudNow(){events.push('save');if(input.mode==='save-error')throw failure;if(input.mode!=='remaining')pending=0},
  async v178ResolvePendingInventoryConflict(){events.push('merge');pending=0},
  async loadCloud(){events.push('load');if(input.mode==='load-error')throw failure},
  async renderCurrent(){events.push('render');if(input.mode==='render-error')throw failure},
  v161ShowProcessing(){events.push('show')},
  v161HideProcessing(){events.push('hide')},
  setSyncState(state,detail){context.syncState=state;events.push(['sync',state,detail||''])},
  updateSyncDisplay(){events.push('display')},
  v161IsConflictError(){return input.mode==='conflict-error'},
  v161ErrorText(error){return error.message},
  esc:value=>value,
  Date:class extends Date{constructor(){super('2026-11-07T07:00:00Z')}toLocaleTimeString(){return '16:00:00'}},
  document:{
   querySelectorAll(){return [{remove(){events.push('remove-notice')}}]},
   querySelector(){return {insertAdjacentHTML(position,html){events.push(['notice',position,html])}}}
  },
  console:{error(){events.push('error')}},
 };
 context.window=context;
 vm.createContext(context);vm.runInContext(input.code,context);
 let value=null,error=null,beforeRelease=null;
 const result=context.refreshData.call({id:'caller'},'ignored').then(
  returned=>{value=returned},caught=>{error=caught.message}
 );
 if(input.mode==='flush-pending'){
  while(!release)await Promise.resolve();
  beforeRelease=events.slice();release();
 }
 await result;
 return {events,value,error,beforeRelease,pending,running:context.v177ReloadRunning};
}
run().then(value=>console.log(JSON.stringify(value))).catch(error=>{console.error(error);process.exitCode=1});
'''


def refresh_blocks(source):
    markers = (
        'const v188RefreshDataProtected=async function(){if(v177ReloadRunning)return false;',
        'refreshData=async function(){if(v177ReloadRunning)return false;',
    )
    start = min(source.index(marker) for marker in markers if marker in source)
    end_marker = 'finally{v177ReloadRunning=false;v161HideProcessing()}}'
    end = source.index(end_marker, start) + len(end_marker)
    entry_start = source.index('refreshData=async function(){await v188StorageInit();')
    capture = 'const v188IdbRefreshBase=refreshData\n;'
    if source[:entry_start].endswith(capture):
        entry_start -= len(capture)
    entry_end = source.index('()};', entry_start) + len('()}')
    return source[start:end] + ';\n', source[entry_start:entry_end] + ';'


def evaluate_refresh(source, mode):
    body, entry = refresh_blocks(source)
    result = subprocess.run(
        ['node', '-e', HARNESS],
        input=json.dumps({'code': body + entry, 'mode': mode}),
        capture_output=True, text=True, timeout=15,
    )
    if result.returncode:
        raise AssertionError(result.stderr or result.stdout)
    return json.loads(result.stdout)


class RefreshEntryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = (ROOT / 'js/02-core.js').read_text(encoding='utf-8')

    def test_success_initializes_flushes_loads_and_renders(self):
        result = evaluate_refresh(self.source, 'success')
        self.assertEqual(result['events'][:5], ['init', 'flush', 'remove-notice', 'show', 'load'])
        self.assertLess(result['events'].index('load'), result['events'].index('render'))
        self.assertEqual(result['events'][-1], 'hide')
        self.assertTrue(result['value'])
        self.assertFalse(result['running'])
        self.assertIsNone(result['error'])

    def test_pending_save_precedes_load(self):
        result = evaluate_refresh(self.source, 'pending')
        self.assertLess(result['events'].index('save'), result['events'].index('load'))
        self.assertTrue(result['value'])
        self.assertEqual(result['pending'], 0)

    def test_conflict_merge_precedes_load_without_normal_save(self):
        result = evaluate_refresh(self.source, 'conflict')
        self.assertLess(result['events'].index('merge'), result['events'].index('load'))
        self.assertNotIn('save', result['events'])
        self.assertTrue(result['value'])

    def test_failed_save_and_remaining_input_prevent_load(self):
        for mode in ('save-error', 'remaining'):
            with self.subTest(mode=mode):
                result = evaluate_refresh(self.source, mode)
                self.assertNotIn('load', result['events'])
                self.assertFalse(result['value'])
                self.assertEqual(result['pending'], 1)
                self.assertFalse(result['running'])
                self.assertEqual(result['events'][-1], 'hide')

    def test_load_and_render_failure_reset_running_and_report_failure(self):
        for mode in ('load-error', 'render-error'):
            with self.subTest(mode=mode):
                result = evaluate_refresh(self.source, mode)
                self.assertFalse(result['value'])
                self.assertIsNone(result['error'])
                self.assertFalse(result['running'])
                self.assertEqual(result['events'][-1], 'hide')
                self.assertTrue(any(isinstance(e, list) and e[:2] == ['sync', '失敗'] for e in result['events']))

    def test_running_still_initializes_and_flushes_without_loading(self):
        result = evaluate_refresh(self.source, 'running')
        self.assertEqual(result['events'], ['init', 'flush'])
        self.assertFalse(result['value'])
        self.assertTrue(result['running'])

    def test_initialization_and_flush_errors_propagate_before_ui_changes(self):
        for mode, events in (('init-error', ['init']), ('flush-error', ['init', 'flush'])):
            with self.subTest(mode=mode):
                result = evaluate_refresh(self.source, mode)
                self.assertEqual(result['error'], mode)
                self.assertEqual(result['events'], events)
                self.assertFalse(result['running'])

    def test_entry_waits_until_flush_resolves(self):
        result = evaluate_refresh(self.source, 'flush-pending')
        self.assertEqual(result['beforeRelease'], ['init', 'flush'])
        self.assertTrue(result['value'])

    def test_entry_does_not_forward_arguments_or_this(self):
        _, entry = refresh_blocks(self.source)
        self.assertNotIn('.apply(', entry)
        self.assertNotIn('.call(', entry)
        self.assertNotIn('...args', entry)
        self.assertIn('await v188StorageInit();await v188IdbFlush();return ', entry)


if __name__ == '__main__':
    unittest.main()
