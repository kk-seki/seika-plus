import json
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HARNESS = r'''
const vm=require('node:vm');
const input=JSON.parse(require('node:fs').readFileSync(0,'utf8'));
async function run(){
 const events=[],failure=new Error(input.mode),timers=[];
 const clone=value=>JSON.parse(JSON.stringify(value));
 let queue=input.mode==='empty'?[]:[{
  id:'original',operationId:'original-operation',expectedVersion:5,baseVersion:5,
  basePayload:{records:[{id:'r1',value:'base'}]},
  payload:{records:[{id:'r1',value:'local'}]},
  localPayload:{records:[{id:'r1',value:'local'}]},lastError:''
 }];
 if(input.mode==='old-queue')delete queue[0].basePayload;
 let flushes=0;
 const context={
  stateVersion:5,historyTablesReady:true,
  db:{user:'user',userId:'user-1',role:'admin'},
  newId:()=>`new-${events.length}`,
  nowIso:()=>"2026-11-07T07:00:00.000Z",
  normalize:value=>value,
  v188Clone:clone,
  v161ReadQueue(){return queue},
  v161WriteQueue(next){queue=next;events.push(['write-queue',next.length,next[0]?.id||null])},
  v188RolePayload(payload){events.push('role-payload');return clone(payload)},
  async v188FetchRemoteState(){
   events.push('fetch-remote');
   if(input.mode==='remote-error')throw failure;
   return {payload:{records:[{id:'r1',value:'remote'}],serverOnly:true},version:8};
  },
  v188MergePayload(base,local,remote){
   events.push(['merge',base.records?.[0]?.value,local.records?.[0]?.value,remote.records?.[0]?.value]);
   if(input.mode==='merge-impossible')return {ok:false,conflicts:['records:r1']};
   return {ok:true,merged:{records:[{id:'r1',value:'merged'}]}};
  },
  async v188SendSyncItem(candidate,payload,version){
   events.push(['send',candidate.id,payload.records?.[0]?.value,version]);
   if(input.mode==='send-error')throw failure;
   if(input.mode==='send-conflict')return {conflict:true};
   if(input.mode==='send-rejected')return {ok:false,message:'rejected'};
   return {ok:true,version:9};
  },
  v188PersistDb(){events.push('persist-db')},
  v188WriteBase(payload,version){events.push(['write-base',payload.records?.[0]?.value,version])},
  markSync(){events.push('mark-sync')},
  setSyncState(state,detail){events.push(['sync',state,detail||''])},
  async saveHistoryTablesNow(){events.push('history');if(input.mode==='history-error')throw failure},
  v188SetHistoryPending(value){events.push(['history-pending',value])},
  v161ErrorText(error){return error.message},
  v188IdbFlush(){
   flushes++;events.push('flush');
   if(input.mode==='flush-error'&&flushes===1)return Promise.reject(failure);
   if(input.mode==='second-flush-error'&&flushes===2)return Promise.reject(failure);
   return Promise.resolve();
  },
  v188AssertPendingOwner(){events.push('owner');if(input.mode==='owner-error')throw failure},
  setTimeout(callback,ms){timers.push(callback);return timers.length},
  clearTimeout(){},console:{error(){}},
 };
 context.window=context;
 vm.createContext(context);
 vm.runInContext(input.code,context);
 let value=null,error=null;
 try{value=await context.v178ResolvePendingInventoryConflict()}catch(caught){error=caught.message}
 return {events,value,error,queue:clone(queue),stateVersion:context.stateVersion,db:clone(context.db)};
}
run().then(value=>console.log(JSON.stringify(value))).catch(error=>{console.error(error);process.exitCode=1});
'''


def conflict_blocks(source):
    old = "v178ResolvePendingInventoryConflict=async function(){const original=v161ReadQueue()[0];"
    protected = "const v188ResolveConflictProtected=async function(){const original=v161ReadQueue()[0];"
    body_start = source.index(protected if protected in source else old)
    body_end = source.index(
        "catch(e){original.lastError=v161ErrorText(e);v161WriteQueue([original]);throw e}}",
        body_start,
    ) + len("catch(e){original.lastError=v161ErrorText(e);v161WriteQueue([original]);throw e}}")
    entry_marker = "v178ResolvePendingInventoryConflict=async function(){await v188IdbFlush()"
    entry_function = source.index(entry_marker, body_end)
    entry_start = source.rfind("const v188IdbResolveConflictBase=", body_end, entry_function)
    if entry_start < body_end:
        entry_start = entry_function
    entry_end = source.index("return result}", entry_function) + len("return result}")
    return source[body_start:body_end] + ";\n", source[entry_start:entry_end] + ";"


def evaluate_conflict(source, mode):
    body, entry = conflict_blocks(source)
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


class ConflictEntryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = (ROOT / "js/02-core.js").read_text(encoding="utf-8")

    def test_entry_awaits_flush_owner_protected_conflict_then_flush_without_arguments_or_this(self):
        _, entry = conflict_blocks(self.source)
        self.assertIn("await v188IdbFlush()", entry)
        self.assertIn("v188AssertPendingOwner()", entry)
        self.assertIn("const result=await", entry)
        self.assertIn("await v188IdbFlush();return result", entry)
        self.assertNotIn(".call(", entry)
        self.assertNotIn(".apply(", entry)
        self.assertNotIn("...args", entry)

    def test_success_flushes_before_and_after_merging_and_returns_merged_result(self):
        result = evaluate_conflict(self.source, "success")
        self.assertEqual(result["value"], {"ok": True, "merged": 1})
        self.assertIsNone(result["error"])
        self.assertEqual(result["events"][0:3], ["flush", "owner", "fetch-remote"])
        self.assertEqual(result["events"][-1], "flush")
        self.assertEqual(result["events"].count("flush"), 2)
        self.assertTrue(any(isinstance(event, list) and event[0] == "send" and event[2:] == ["merged", 8] for event in result["events"]))
        self.assertIn(["write-queue", 0, None], result["events"])
        self.assertEqual((result["stateVersion"], result["queue"]), (9, []))

    def test_empty_queue_returns_without_fetch_or_send_but_keeps_entry_flushes(self):
        result = evaluate_conflict(self.source, "empty")
        self.assertEqual(result["value"], {"ok": True, "merged": 0})
        self.assertEqual(result["events"], ["flush", "owner", "flush"])
        self.assertEqual(result["queue"], [])

    def test_old_queue_is_rejected_without_reading_remote_or_clearing_the_queue(self):
        result = evaluate_conflict(self.source, "old-queue")
        self.assertIn("旧形式の未同期データ", result["error"])
        self.assertIn(["sync", "競合", "旧形式の未同期データを保護しています"], result["events"])
        self.assertNotIn("fetch-remote", result["events"])
        self.assertNotIn("send", [event[0] for event in result["events"] if isinstance(event, list)])
        self.assertEqual(result["events"].count("flush"), 1)
        self.assertEqual(len(result["queue"]), 1)

    def test_unmergeable_changes_are_retained_without_sending_or_second_flush(self):
        result = evaluate_conflict(self.source, "merge-impossible")
        self.assertIn("別端末でも変更", result["error"])
        self.assertIn(["sync", "競合", "自動統合できない項目があります"], result["events"])
        self.assertFalse(any(isinstance(event, list) and event[0] == "send" for event in result["events"]))
        self.assertEqual(result["events"].count("flush"), 1)
        self.assertEqual(len(result["queue"]), 1)

    def test_remote_read_failure_keeps_the_original_queue_and_skips_the_second_flush(self):
        result = evaluate_conflict(self.source, "remote-error")
        self.assertEqual(result["error"], "remote-error")
        self.assertEqual(result["events"], ["flush", "owner", "fetch-remote"])
        self.assertEqual(len(result["queue"]), 1)

    def test_send_failures_restore_original_queue_and_never_run_the_post_flush(self):
        for mode, text in [("send-error", "send-error"), ("send-conflict", "統合中に別の更新"), ("send-rejected", "rejected")]:
            with self.subTest(mode=mode):
                result = evaluate_conflict(self.source, mode)
                self.assertIn(text, result["error"])
                self.assertEqual(result["events"].count("flush"), 1)
                self.assertIn(["write-queue", 1, "original"], result["events"])
                self.assertEqual(result["queue"][0]["id"], "original")
                self.assertTrue(result["queue"][0]["lastError"])

    def test_history_failure_keeps_the_merged_app_data_and_marks_only_history_for_retry(self):
        result = evaluate_conflict(self.source, "history-error")
        self.assertEqual(result["value"], {"ok": True, "merged": 1})
        self.assertIn(["history-pending", True], result["events"])
        self.assertIn(["sync", "未同期", "統合済み履歴を再送待ち"], result["events"])
        self.assertEqual(result["queue"], [])
        self.assertEqual(result["events"][-1], "flush")

    def test_flush_and_owner_failures_do_not_start_remote_merge(self):
        cases = [("flush-error", ["flush"]), ("owner-error", ["flush", "owner"])]
        for mode, expected in cases:
            with self.subTest(mode=mode):
                result = evaluate_conflict(self.source, mode)
                self.assertEqual(result["error"], mode)
                self.assertEqual(result["events"], expected)
                self.assertEqual(len(result["queue"]), 1)

    def test_second_flush_failure_is_propagated_only_after_a_successful_merge(self):
        result = evaluate_conflict(self.source, "second-flush-error")
        self.assertEqual(result["error"], "second-flush-error")
        self.assertEqual(result["events"].count("flush"), 2)
        self.assertIn(["write-queue", 0, None], result["events"])
        self.assertEqual(result["queue"], [])


if __name__ == "__main__":
    unittest.main()
