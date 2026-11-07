import json
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HARNESS = """
const vm=require('node:vm');
const input=JSON.parse(require('node:fs').readFileSync(0,'utf8'));
async function run(){
 const events=[],failure={reason:input.mode},writes=[],owner={id:'caller'};
 let resolveStorage,resolveBase,beforeResolve=null;
 const pendingModes=['pending','conflict','attempts','invalid-version'];
 let queue=pendingModes.includes(input.mode)?[{attempts:input.mode==='attempts'?1:0,lastError:input.mode==='conflict'?'conflict':''}]:[];
 const context={
  stateVersion:99,cloudReady:false,queueMicrotask,
  v188StorageInit(){
   events.push('storage');
   if(input.mode==='storage-error')return Promise.reject(failure);
   if(input.mode==='storage-pending')return new Promise(resolve=>{resolveStorage=()=>{
    queue=[{attempts:0,lastError:''}];resolve();
   }});
   return Promise.resolve();
  },
  v188AssertPendingOwner(){events.push('owner');if(input.mode==='owner-error')throw failure},
  v161PendingCount(){events.push('pending');return queue.length},
  v188ReadBase(){events.push('read-base');return{version:input.mode==='invalid-version'?'invalid':37}},
  v161ReadQueue(){events.push('queue');return queue},
  v161IsConflictError(error){return error==='conflict'},
  setSyncState(state,detail){events.push(['sync',state,detail])},
  v161Snapshot(){events.push('snapshot');return{local:'fixture'}},
  v188WriteBase(payload,version){
   events.push('write');
   if(input.mode==='write-error')throw failure;
   writes.push({payload,version});
  },
  loadCloud(...args){
   events.push(['base',args.length,this===owner]);
   if(input.mode==='base-error')return Promise.reject(failure);
   if(input.mode==='base-pending')return new Promise(resolve=>{resolveBase=()=>{
    queue=[{attempts:0,lastError:''}];resolve({ignored:true});
   }});
   context.stateVersion=7;context.cloudReady=true;
   if(input.mode==='base-interleave')queueMicrotask(()=>events.push('base-callback'));
   return Promise.resolve({ignored:true});
  }
 };
 context.window=context;
 vm.createContext(context);vm.runInContext(input.protected,context);vm.runInContext(input.entry,context);
 let rejected=false,returned='unresolved';
 const pending=context.loadCloud.call(owner,'ignored-argument').then(
  value=>{events.push('resolved');returned=value===undefined?'undefined':value},
  error=>{events.push('rejected');rejected=error===failure}
 );
 if(input.mode==='storage-pending'){
  beforeResolve=events.slice();resolveStorage();
 }else if(input.mode==='base-pending'){
  while(!resolveBase)await Promise.resolve();
  beforeResolve=events.slice();resolveBase();
 }
 await pending;
 return{events,writes,rejected,returned,beforeResolve,version:context.stateVersion,cloudReady:context.cloudReady,queue:queue.length};
}
run().then(result=>console.log(JSON.stringify(result))).catch(error=>{console.error(error);process.exitCode=1});
"""


def core_blocks(source):
    start = source.index("const v188LoadCloudBase=loadCloud;")
    end = source.index(";const v188DeleteWasteRecordBase", start)
    protected = source[start:end] + ";"
    entry_start = source.index("loadCloud=async function(){await v188StorageInit();")
    capture = "const v188IdbLoadCloudBase=loadCloud\n;"
    if source[:entry_start].endswith(capture):
        entry_start -= len(capture)
    entry_end = source.index(";const v188IdbRefreshBase", entry_start)
    return protected, source[entry_start:entry_end] + ";"


def evaluate_core(source, mode):
    protected, entry = core_blocks(source)
    result = subprocess.run(
        ["node", "-e", HARNESS],
        input=json.dumps({"protected": protected, "entry": entry, "mode": mode}),
        capture_output=True,
        text=True,
        timeout=15,
    )
    if result.returncode:
        raise AssertionError(result.stderr or result.stdout)
    return json.loads(result.stdout)


class CoreLoadTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = (ROOT / "js/02-core.js").read_text(encoding="utf-8")

    def test_entry_returns_inner_promise_without_an_extra_await(self):
        _, entry = core_blocks(self.source)
        body = entry[entry.index("loadCloud=async function()") :]
        self.assertIn("await v188StorageInit();v188AssertPendingOwner();return v188", body)
        self.assertNotIn("return await", body)

    def test_loads_after_storage_and_owner_check_then_records_base(self):
        result = evaluate_core(self.source, "ok")
        self.assertEqual(result["events"], ["storage", "owner", "pending", ["base", 0, False], "pending", "snapshot", "write", "resolved"])
        self.assertEqual(result["writes"], [{"payload": {"local": "fixture"}, "version": 7}])
        self.assertEqual(result["returned"], "undefined")
        self.assertTrue(result["cloudReady"])

    def test_storage_is_awaited_before_checking_pending_queue(self):
        result = evaluate_core(self.source, "storage-pending")
        self.assertEqual(result["beforeResolve"], ["storage"])
        self.assertEqual(result["queue"], 1)
        self.assertEqual(result["writes"], [])
        self.assertEqual(result["version"], 37)
        self.assertFalse(any(isinstance(event, list) and event[0] == "base" for event in result["events"]))

    def test_pending_and_conflicting_input_skip_remote_and_preserve_version(self):
        for mode, expected in [("pending", "未同期"), ("conflict", "競合"), ("attempts", "競合"), ("invalid-version", "未同期")]:
            with self.subTest(mode=mode):
                result = evaluate_core(self.source, mode)
                self.assertEqual(result["writes"], [])
                self.assertEqual(result["queue"], 1)
                self.assertEqual(result["version"], 99 if mode == "invalid-version" else 37)
                self.assertEqual(result["events"][:5], ["storage", "owner", "pending", "read-base", "queue"])
                self.assertEqual(result["events"][5][0:2], ["sync", expected])
                self.assertTrue(result["cloudReady"])
                self.assertEqual(result["events"][6:], ["resolved"])

    def test_storage_and_owner_failures_do_not_read_or_write_cloud(self):
        for mode, expected in [("storage-error", ["storage", "rejected"]), ("owner-error", ["storage", "owner", "rejected"])]:
            with self.subTest(mode=mode):
                result = evaluate_core(self.source, mode)
                self.assertTrue(result["rejected"])
                self.assertEqual(result["events"], expected)
                self.assertEqual(result["writes"], [])

    def test_base_failure_propagates_without_updating_base(self):
        result = evaluate_core(self.source, "base-error")
        self.assertTrue(result["rejected"])
        self.assertEqual(result["events"], ["storage", "owner", "pending", ["base", 0, False], "rejected"])
        self.assertEqual(result["writes"], [])

    def test_pending_changes_arriving_during_load_are_not_acknowledged(self):
        result = evaluate_core(self.source, "base-pending")
        self.assertEqual(result["beforeResolve"], ["storage", "owner", "pending", ["base", 0, False]])
        self.assertEqual(result["queue"], 1)
        self.assertEqual(result["writes"], [])
        self.assertEqual(result["events"][-2:], ["pending", "resolved"])

    def test_base_promise_callback_precedes_snapshot_write(self):
        result = evaluate_core(self.source, "base-interleave")
        self.assertEqual(result["events"], ["storage", "owner", "pending", ["base", 0, False], "base-callback", "pending", "snapshot", "write", "resolved"])

    def test_write_failure_still_rejects(self):
        result = evaluate_core(self.source, "write-error")
        self.assertTrue(result["rejected"])
        self.assertEqual(result["writes"], [])
        self.assertEqual(result["events"][-2:], ["write", "rejected"])


if __name__ == "__main__":
    unittest.main()
