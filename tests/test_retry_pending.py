import json
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent

HARNESS = r'''
const vm=require('node:vm');
const input=JSON.parse(require('node:fs').readFileSync(0,'utf8'));
const barrier=()=>new Promise(resolve=>setImmediate(resolve));
async function run(){
  const events=[],alerts=[];
  let standard=Array.from({length:input.standard||0},(_,index)=>({id:`standard-${index}`}));
  let history=Boolean(input.history),qr=Number(input.qr||0),prices=(input.prices||[]).map(row=>({...row}));
  let saveRelease,idbRelease,callIndex=0;
  const button={disabled:false,textContent:'',remove(){events.push('remove-retry')}};
  const context={
    v161SyncRunning:Boolean(input.syncRunning),
    syncState:input.syncState||'未同期',
    v161ReadQueue(){return standard},
    v161PendingCount(){return standard.length},
    v188HistoryPending(){return history},
    v188SetHistoryPending(value){history=value;events.push(['history',value])},
    v193QrEditHistoryPendingCount(){return qr},
    v161IsConflictError(){return false},
    v161ShowProcessing(message){events.push(['show',message])},
    v161HideProcessing(){events.push('hide')},
    updateSyncDisplay(){events.push('display')},
    v1163UpdateSyncDisplay(){events.push('price-display')},
    setSyncState(state,detail){context.syncState=state;events.push(['sync',state,detail])},
    v161ErrorText(error){return error.message},
    alert(message){alerts.push(message);events.push(['alert',message])},
    async saveCloudNow(){
      events.push('save-start');
      if(input.save==='gate')await new Promise(resolve=>{saveRelease=resolve});
      if(input.save==='error')throw new Error('standard failed');
      standard=[];events.push('save-done');
    },
    async v178ResolvePendingInventoryConflict(){
      events.push('merge');
      if(input.merge==='error')throw new Error('conflict unresolved');
      standard=[];return {ok:true,merged:1};
    },
    async saveHistoryTablesNow(){events.push('history-save');if(input.historySave==='error')throw new Error('history failed')},
    async v193RetryQrEditHistories(){events.push('qr-retry');if(input.qrRetry==='error')throw new Error('qr failed');const count=qr;qr=0;return count},
    async v188IdbFlush(){
      events.push('idb-start');
      if(input.idb==='gate')await new Promise(resolve=>{idbRelease=resolve});
      if(input.idb==='error')throw new Error('idb failed');
      events.push('idb-done');
    },
    async renderCurrent(){events.push('render')},
    v1163ReadWastePriceQueue(){return prices.map(row=>({...row}))},
    v1163WriteWastePriceQueue(rows){
      events.push(['price-write',rows.map(row=>row.movementId)]);
      if(input.priceWrite==='error')throw new Error('price write failed');
      prices=rows;
    },
    async callRpc(name,params){
      events.push(['price-rpc',name,params.p_movement_id]);
      const result=(input.priceResults||[])[callIndex++]||{ok:true};
      if(result.throw)throw new Error(result.throw);
      return result;
    },
    document:{
      getElementById(id){return id==='syncRetryBtn'?button:null},
      querySelectorAll(){return [{remove(){events.push('remove-notice')}}]},
    },
  };
  context.window=context;
  vm.createContext(context);
  vm.runInContext(input.code,context);
  if(input.forceRetryFlag)vm.runInContext('v1111RetryPendingRunning=true',context);
  const retry=()=>context.retryPendingSync();
  const waitFor=async(event,label)=>{
    for(let index=0;index<40;index++){
      if(events.some(value=>Array.isArray(value)?value[0]===event:value===event))return;
      await barrier();
    }
    throw new Error(`gate missing: ${label}`);
  };
  let error=null,beforeRelease=null,settled=false,settledBeforeRelease=null;
  try{
    if(input.action==='direct-prices'){
      await context.__retryWastePrices();
    }else if(input.gate==='save'){
      const first=retry().finally(()=>{settled=true});await waitFor('save-start','save');
      if(input.secondCall)await retry();
      await barrier();beforeRelease=events.slice();settledBeforeRelease=settled;
      if(!saveRelease)throw new Error('gate missing: save release');
      saveRelease();await first;await barrier();
    }else if(input.gate==='idb'){
      const first=retry().finally(()=>{settled=true});await waitFor('idb-start','idb');
      if(input.addDuring==='standard')standard.push({id:'new-standard'});
      if(input.addDuring==='history')history=true;
      if(input.addDuring==='qr')qr+=1;
      await barrier();beforeRelease=events.slice();settledBeforeRelease=settled;
      if(!idbRelease)throw new Error('gate missing: idb release');
      idbRelease();await first;await barrier();
    }else{
      await retry();await barrier();
    }
  }catch(caught){error=caught.message}
  return {events,alerts,error,beforeRelease,settledBeforeRelease,standard:standard.length,history,qr,prices,running:vm.runInContext('v1111RetryPendingRunning',context)};
}
run().then(result=>console.log(JSON.stringify(result))).catch(error=>{console.error(error.stack||error);process.exitCode=1});
'''


def extract_once(source, start, end, label):
    if source.count(start) != 1 or source.count(end) != 1:
        raise AssertionError(f'{label} marker missing or ambiguous')
    start_index = source.index(start)
    end_index = source.index(end, start_index)
    if end_index < start_index:
        raise AssertionError(f'{label} marker order is invalid')
    return source[start_index:end_index]


def retry_source(source):
    standard = extract_once(
        source,
        '/* v1.111 再送完了後のキュー・ボタン確実解除 */',
        'const v188LoadCloudBase=loadCloud;',
        'standard retry',
    )
    capture = 'const v1159RetryPendingSyncCore=retryPendingSync;'
    if source.count(capture) != 1:
        raise AssertionError('standard retry capture marker missing or ambiguous')
    price = extract_once(
        source,
        'async function v1163RetryWastePrices(){',
        'const v1163UpdateSyncDisplayCore=updateSyncDisplay;',
        'waste price retry',
    )
    final = extract_once(
        source,
        'retryPendingSync=async function(){\n  if(v161SyncRunning||v1111RetryPendingRunning)return;',
        "const V1162_VERSION='v1.179';",
        'final retry',
    )
    return standard + capture + '\n' + price + final + '\nglobalThis.__retryWastePrices=v1163RetryWastePrices;'


def evaluate_retry(source, **scenario):
    result = subprocess.run(
        ['node', '-e', HARNESS],
        input=json.dumps({'code': retry_source(source), **scenario}),
        capture_output=True,
        text=True,
        timeout=15,
    )
    if result.returncode:
        raise AssertionError(result.stderr or result.stdout)
    return json.loads(result.stdout)


def event_names(result):
    return [event[0] if isinstance(event, list) else event for event in result['events']]


class RetryPendingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = (ROOT / 'js/02-core.js').read_text(encoding='utf-8')
        retry_source(cls.source)

    def test_returns_while_either_running_flag_is_set(self):
        for scenario in ({'syncRunning': True}, {'forceRetryFlag': True}):
            with self.subTest(scenario=scenario):
                result = evaluate_retry(self.source, standard=1, prices=[{'movementId': 'p1'}], **scenario)
                self.assertIsNone(result['error'])
                self.assertEqual(event_names(result), [])
                self.assertEqual(result['alerts'], [])

    def test_reports_when_no_pending_data_exists(self):
        result = evaluate_retry(self.source)
        self.assertIsNone(result['error'])
        self.assertEqual(result['alerts'], ['再送する未同期データはありません。'])
        self.assertEqual(event_names(result), ['alert'])

    def test_standard_save_gate_blocks_price_and_second_standard_retry(self):
        result = evaluate_retry(
            self.source,
            standard=1,
            prices=[{'movementId': 'p1', 'price': 100, 'reason': 'test'}],
            save='gate', gate='save', secondCall=True,
        )
        self.assertFalse(result['settledBeforeRelease'])
        before = [event[0] if isinstance(event, list) else event for event in result['beforeRelease']]
        self.assertEqual(before.count('save-start'), 1)
        self.assertNotIn('price-rpc', before)
        self.assertNotIn('alert', before)
        self.assertEqual(event_names(result).count('price-rpc'), 1)
        self.assertIsNone(result['error'])
        self.assertFalse(result['running'])
        self.assertEqual(result['prices'], [])

    def test_idb_flush_gate_blocks_price_until_it_completes(self):
        result = evaluate_retry(
            self.source,
            standard=1,
            prices=[{'movementId': 'p1', 'price': 100, 'reason': 'test'}],
            idb='gate', gate='idb',
        )
        self.assertFalse(result['settledBeforeRelease'])
        before = [event[0] if isinstance(event, list) else event for event in result['beforeRelease']]
        self.assertIn('idb-start', before)
        self.assertNotIn('price-rpc', before)
        self.assertEqual(event_names(result).count('price-rpc'), 1)
        self.assertIsNone(result['error'])
        self.assertFalse(result['running'])
        self.assertEqual(result['prices'], [])

    def test_standard_history_and_qr_failures_keep_data_and_skip_price_retry(self):
        cases = (
            ({'standard': 1, 'save': 'error'}, 'standard'),
            ({'history': True, 'historySave': 'error'}, 'history'),
            ({'qr': 1, 'qrRetry': 'error'}, 'qr'),
        )
        for scenario, retained in cases:
            with self.subTest(retained=retained):
                result = evaluate_retry(self.source, prices=[{'movementId': 'p1'}], **scenario)
                self.assertIsNone(result['error'])
                self.assertFalse(result['running'])
                self.assertNotIn('price-rpc', event_names(result))
                self.assertEqual(len(result['prices']), 1)
                self.assertTrue(result[retained] if retained != 'standard' else result['standard'])
                self.assertTrue(any('未同期データを端末に保持しています' in str(event) for event in result['events']))

    def test_new_pending_data_added_while_idb_waits_skips_price_retry(self):
        for added in ('standard', 'history', 'qr'):
            with self.subTest(added=added):
                result = evaluate_retry(
                    self.source,
                    standard=1,
                    prices=[{'movementId': 'p1'}],
                    idb='gate', gate='idb', addDuring=added,
                )
                self.assertIsNone(result['error'])
                self.assertFalse(result['running'])
                self.assertNotIn('price-rpc', event_names(result))
                self.assertEqual(len(result['prices']), 1)
                self.assertTrue(result[added] if added != 'standard' else result['standard'])

    def test_standard_and_price_success_follow_standard_before_price(self):
        result = evaluate_retry(
            self.source,
            standard=1, history=True, qr=1,
            prices=[{'movementId': 'p1', 'price': 100, 'reason': 'test'}],
        )
        self.assertIsNone(result['error'])
        self.assertFalse(result['running'])
        names = event_names(result)
        self.assertLess(names.index('save-start'), names.index('history-save'))
        self.assertLess(names.index('history-save'), names.index('qr-retry'))
        self.assertLess(names.index('qr-retry'), names.index('idb-start'))
        self.assertLess(names.index('render'), names.index('price-rpc'))
        self.assertEqual((result['standard'], result['history'], result['qr'], result['prices']), (0, False, 0, []))
        self.assertIn('廃棄単価 1件の再送が完了しました。', result['alerts'])

    def test_price_only_success_does_not_start_standard_processing(self):
        result = evaluate_retry(self.source, prices=[{'movementId': 'p1', 'price': 100, 'reason': 'test'}])
        self.assertIsNone(result['error'])
        self.assertFalse(result['running'])
        names = event_names(result)
        self.assertEqual(names.count('price-rpc'), 1)
        self.assertNotIn('save-start', names)
        self.assertNotIn('idb-start', names)
        self.assertIsNone(result['error'])
        self.assertFalse(result['running'])
        self.assertEqual(result['prices'], [])
        self.assertEqual(result['alerts'], ['廃棄単価 1件の再送が完了しました。'])

    def test_price_rpc_exception_and_not_ok_keep_only_failures_with_attempts(self):
        result = evaluate_retry(
            self.source,
            action='direct-prices',
            prices=[
                {'movementId': 'ok', 'price': 100, 'reason': 'test'},
                {'movementId': 'throws', 'price': 200, 'reason': 'test', 'attempts': 2},
                {'movementId': 'not-ok', 'price': 300, 'reason': 'test'},
            ],
            priceResults=[{'ok': True}, {'throw': 'rpc unavailable'}, {'ok': False, 'message': 'rejected'}],
        )
        self.assertEqual(result['error'], '廃棄単価 2件を再送できませんでした。rpc unavailable')
        self.assertEqual([row['movementId'] for row in result['prices']], ['throws', 'not-ok'])
        self.assertEqual([row['attempts'] for row in result['prices']], [3, 1])
        self.assertEqual([row['lastError'] for row in result['prices']], ['rpc unavailable', 'rejected'])

    def test_source_markers_missing_or_duplicated_fail_instead_of_using_a_different_entry(self):
        markers = (
            '/* v1.111 再送完了後のキュー・ボタン確実解除 */',
            'const v1159RetryPendingSyncCore=retryPendingSync;',
            'async function v1163RetryWastePrices(){',
            'retryPendingSync=async function(){\n  if(v161SyncRunning||v1111RetryPendingRunning)return;',
        )
        for marker in markers:
            for source in (self.source.replace(marker, '', 1), self.source + marker):
                with self.subTest(marker=marker):
                    with self.assertRaises(AssertionError):
                        retry_source(source)

    def test_unresolved_conflict_keeps_both_queues_and_resets_the_retry_flag(self):
        result = evaluate_retry(
            self.source, standard=1, prices=[{'movementId': 'p1'}],
            syncState='競合', merge='error',
        )
        self.assertIsNone(result['error'])
        self.assertFalse(result['running'])
        self.assertIn('merge', event_names(result))
        self.assertNotIn('save-start', event_names(result))
        self.assertNotIn('price-rpc', event_names(result))
        self.assertEqual(result['standard'], 1)
        self.assertEqual([row['movementId'] for row in result['prices']], ['p1'])
        self.assertTrue(any('conflict unresolved' in message for message in result['alerts']))
        self.assertTrue(any(event[:2] == ['sync', '競合'] for event in result['events'] if isinstance(event, list)))

    def test_price_queue_write_failure_is_reported_without_removing_pending_data(self):
        result = evaluate_retry(
            self.source,
            prices=[{'movementId': 'p1', 'price': 100, 'reason': 'test'}],
            priceWrite='error',
        )
        self.assertIsNone(result['error'])
        self.assertFalse(result['running'])
        self.assertEqual(len(result['prices']), 1)
        self.assertEqual(event_names(result).count('price-rpc'), 1)
        self.assertTrue(any('price write failed' in message for message in result['alerts']))
        self.assertFalse(any('再送が完了しました。' in message for message in result['alerts']))


if __name__ == '__main__':
    unittest.main()
