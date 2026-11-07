import json
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HARNESS = """
const vm=require('node:vm');
const input=JSON.parse(require('node:fs').readFileSync(0,'utf8'));
async function run(){
 const mode=input.mode,events=[],failure={reason:mode},timers=[];
 let queue=[],resolveFlush;
 const item=()=>({id:'i1',payload:{a:1},localPayload:{a:1},expectedVersion:5,attempts:0,lastError:''});
 if(!['empty','require-rpc','history-pending'].includes(mode))queue=[item()];
 let flushCount=0;
 const context={
  v161SyncRunning:mode==='running',cloudReady:mode!=='not-ready',stateVersion:mode==='no-version'?null:5,
  historyTablesReady:true,saveTimer:null,queueMicrotask,
  v188Clone:x=>JSON.parse(JSON.stringify(x)),
  v188Equal:(a,b)=>JSON.stringify(a)===JSON.stringify(b),
  newId:()=>'new-id',
  v161ReadQueue(){return queue},
  v161WriteQueue(next){queue=next;events.push(['write-queue',next.length])},
  v188QueueLatest(){events.push('queue-latest');queue=[item()]},
  v188HistoryPending(){return mode==='history-pending'},
  v188SetHistoryPending(value){events.push(['history-pending',value])},
  async saveHistoryTablesNow(){events.push('history');if(mode==='history-error')throw failure},
  markSync(){events.push('mark')},
  setSyncState(state,detail){events.push(['sync',state,detail||''])},
  updateSyncDisplay(){events.push('display')},
  v161IsConflictError(error){return error&&error.message==='conflict-message'},
  v161ErrorText(error){return String((error&&error.message)||error&&error.reason||error)},
  v188WriteBase(payload,version){events.push(['base',JSON.stringify(payload),version])},
  async v188SendSyncItem(sentItem,sent,expected){
   events.push(['send',sent.a,expected]);
   if(mode==='conflict')return{conflict:true,message:'conflict-message'};
   if(mode==='rejected-ok')return{ok:false,message:'not ok'};
   if(mode==='send-error')throw failure;
   if(mode==='followup'&&queue[0])queue[0].localPayload={a:2};
   return{ok:true,version:6};
  },
  v188IdbFlush(){
   flushCount++;events.push('flush');
   if(mode==='flush-error'&&flushCount===1)return Promise.reject(failure);
   if(mode==='second-flush-error'&&flushCount===2)return Promise.reject(failure);
   if(mode==='flush-pending'&&flushCount===1)return new Promise(resolve=>{resolveFlush=resolve});
   return Promise.resolve();
  },
  v188AssertPendingOwner(){events.push('owner');if(mode==='owner-error')throw failure},
  setTimeout(callback,ms){timers.push(callback);events.push(['timer',ms]);return timers.length},
  clearTimeout(){events.push('clear-timer')},
  console:{error(){events.push('console-error')}},
  saveCloudNow(){events.push('v161-function');return Promise.resolve('v161')}
 };
 context.window=context;
 vm.createContext(context);vm.runInContext(input.code,context);
 const options=mode==='skip-history'?{skipHistory:true}:mode==='require-rpc'?{requireRpc:true}:{};
 const owner={id:'caller'};
 let returned='unresolved',rejected=false,beforeResolve=null,followup=null;
 const pending=context.saveCloudNow.call(owner,options).then(
  value=>{events.push('resolved');returned=value},
  error=>{events.push('rejected');rejected=error===failure||(error&&error.message)||true}
 );
 if(mode==='flush-pending'){
  while(!resolveFlush)await Promise.resolve();
  beforeResolve=events.slice();resolveFlush();
 }
 await pending;
 if(mode==='followup'&&timers.length){
  const mark=events.length;
  await timers[0]();
  followup=events.slice(mark);
 }
 return{events,returned,rejected,beforeResolve,followup,
  version:context.stateVersion,running:context.v161SyncRunning,queue:queue.length};
}
run().then(result=>console.log(JSON.stringify(result))).catch(error=>{console.error(error);process.exitCode=1});
"""


def save_blocks(source):
    body_marks = (
        "const v188SaveCloudNowProtected=async function(options={}){if(v161SyncRunning)return false;",
        "saveCloudNow=async function(options={}){if(v161SyncRunning)return false;",
    )
    body_start = min(source.index(mark) for mark in body_marks if mark in source)
    body_end_mark = "finally{v161SyncRunning=false;updateSyncDisplay()}}"
    body_end = source.index(body_end_mark, body_start) + len(body_end_mark)
    entry_start = source.index("saveCloudNow=async function(options={}){await v188IdbFlush();")
    capture = "const v188IdbSaveCloudBase=saveCloudNow;"
    if source[:entry_start].endswith(capture):
        entry_start -= len(capture)
    entry_end_mark = "return result}"
    entry_end = source.index(entry_end_mark, entry_start) + len(entry_end_mark)
    return source[body_start:body_end] + ";\n", source[entry_start:entry_end] + ";"


def evaluate_save(source, mode):
    body, entry = save_blocks(source)
    result = subprocess.run(
        ["node", "-e", HARNESS],
        input=json.dumps({"code": body + entry, "mode": mode}, ensure_ascii=False),
        capture_output=True,
        text=True,
        timeout=15,
    )
    if result.returncode:
        raise AssertionError(result.stderr or result.stdout)
    return json.loads(result.stdout)


SUCCESS = [
    "flush", "owner", ["sync", "保存中", ""], ["send", 1, 5], ["base", '{"a":1}', 6], ["write-queue", 0], "mark",
    ["sync", "保存済み", ""], "history", ["history-pending", False], "display", "flush", "resolved",
]


class SaveEntryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = (ROOT / "js/02-core.js").read_text(encoding="utf-8")

    def test_entry_does_not_forward_this_and_returns_the_inner_result(self):
        _, entry = save_blocks(self.source)
        self.assertIn("await v188IdbFlush();v188AssertPendingOwner()", entry)
        self.assertIn("const result=await v188", entry)
        self.assertIn("(options);await v188IdbFlush();return result}", entry)
        self.assertNotIn(".apply(", entry)
        self.assertNotIn(".call(", entry)

    def test_successful_save_flushes_before_and_after_the_cloud_save(self):
        result = evaluate_save(self.source, "ok")
        self.assertEqual(result["events"], SUCCESS)
        self.assertIs(result["returned"], True)
        self.assertFalse(result["running"])
        self.assertEqual((result["version"], result["queue"]), (6, 0))

    def test_options_reach_the_inner_save(self):
        result = evaluate_save(self.source, "skip-history")
        self.assertNotIn("history", result["events"])
        self.assertIs(result["returned"], True)
        result = evaluate_save(self.source, "require-rpc")
        self.assertEqual(result["events"][:5], ["flush", "owner", "queue-latest", ["sync", "保存中", ""], ["send", 1, 5]])

    def test_first_flush_is_awaited_before_owner_check_and_save(self):
        result = evaluate_save(self.source, "flush-pending")
        self.assertEqual(result["beforeResolve"], ["flush"])
        self.assertEqual(result["events"][:4], ["flush", "owner", ["sync", "保存中", ""], ["send", 1, 5]])

    def test_flush_or_owner_failure_never_reaches_the_cloud_save(self):
        for mode, expected in [("flush-error", ["flush", "rejected"]), ("owner-error", ["flush", "owner", "rejected"])]:
            with self.subTest(mode=mode):
                result = evaluate_save(self.source, mode)
                self.assertIs(result["rejected"], True)
                self.assertEqual(result["events"], expected)
                self.assertEqual(result["queue"], 1)

    def test_inner_failure_skips_the_second_flush_and_keeps_the_queue(self):
        for mode, state in [("send-error", "失敗"), ("conflict", "競合")]:
            with self.subTest(mode=mode):
                result = evaluate_save(self.source, mode)
                self.assertTrue(result["rejected"])
                self.assertEqual(result["events"].count("flush"), 1)
                self.assertIn(["sync", state, "入力は端末に保持されています" if state == "失敗" else "端末データを保持しています"], result["events"])
                self.assertEqual(result["queue"], 1)
                self.assertFalse(result["running"])

    def test_a_save_already_running_returns_false_and_still_flushes_after(self):
        result = evaluate_save(self.source, "running")
        self.assertIs(result["returned"], False)
        self.assertEqual(result["events"], ["flush", "owner", "flush", "resolved"])

    def test_empty_queue_and_pending_history_paths(self):
        result = evaluate_save(self.source, "empty")
        self.assertEqual(result["events"], ["flush", "owner", "flush", "resolved"])
        result = evaluate_save(self.source, "history-pending")
        self.assertEqual(
            result["events"],
            ["flush", "owner", "history", ["history-pending", False], "mark", ["sync", "保存済み", ""], "flush", "resolved"],
        )

    def test_cloud_not_ready_or_unprotected_version_never_sends(self):
        for mode, message in [("not-ready", "通信未接続"), ("no-version", "競合防止RPC")]:
            with self.subTest(mode=mode):
                result = evaluate_save(self.source, mode)
                self.assertIn(message, result["rejected"])
                self.assertFalse(any(isinstance(event, list) and event[0] == "send" for event in result["events"]))
                self.assertEqual(result["events"].count("flush"), 1)

    def test_changes_made_during_saving_are_retried_through_the_flushing_entry(self):
        result = evaluate_save(self.source, "followup")
        self.assertIn(["timer", 350], result["events"])
        self.assertEqual(result["followup"][:4], ["flush", "owner", ["sync", "保存中", ""], ["send", 2, 6]])
        self.assertEqual(result["followup"][-1], "flush")
        self.assertNotIn("v161-function", result["events"] + result["followup"])
        self.assertEqual(result["queue"], 0)

    def test_second_flush_failure_still_rejects_after_the_cloud_save(self):
        result = evaluate_save(self.source, "second-flush-error")
        self.assertIs(result["rejected"], True)
        self.assertEqual((result["version"], result["queue"]), (6, 0))

    def test_history_failure_keeps_the_saved_result(self):
        result = evaluate_save(self.source, "history-error")
        self.assertIs(result["returned"], True)
        self.assertIn(["history-pending", True], result["events"])


if __name__ == "__main__":
    unittest.main()
