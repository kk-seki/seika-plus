import json
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HARNESS = """
const vm=require('node:vm');
const input=JSON.parse(require('node:fs').readFileSync(0,'utf8'));
async function run(){
 const events=[],marker={saved:true},owner={id:'owner'},args=['a',2];
 let resolveBase,beforeResolve=null,atPrune=null;
 const context={
  db:{role:'admin',qrSupplierHidden:['会社（仮）','会社(仮)','別会社'],qrCooperativeHidden:['単協']},
  cloudPayloadBase:()=>({}),v188RolePayload:p=>({...p}),v188Clone:x=>JSON.parse(JSON.stringify(x)),
  qrNormalizeName:v=>String(v||'').replace(/[（）]/g,m=>m==='（'?'(':')').replace(/\\s+/g,'').trim(),
  pageShell:()=>{},setTimeout:()=>{},queueMicrotask,
  v124NormalizeSession:s=>s,v124DeriveStatus:s=>s,v188Home:()=>{},
  v177Session:()=>false,v188Session:()=>false,canAdmin:()=>false,
  countSessions(){
   events.push('prune');
   if(input.mode==='prune-error')throw new Error('prune-error');
   if(input.mode!=='restore-error')atPrune={suppliers:[...context.db.qrSupplierHidden],cooperatives:[...context.db.qrCooperativeHidden]};
   return[];
  },
  loadCloud(...received){
   events.push(['base',this===owner,received]);
   if(input.mode==='deferred')return new Promise(resolve=>{resolveBase=()=>{
    context.db={role:'admin',qrSupplierHidden:[],qrCooperativeHidden:[]};resolve(marker);
   }});
   if(input.mode==='reject')return Promise.reject(marker);
   if(input.mode==='capture-error')return Promise.resolve(marker);
   if(input.mode==='restore-error'){
    Object.defineProperty(context.db,'qrSupplierHidden',{get(){throw new Error('restore-error')},configurable:true});
    return Promise.resolve(marker);
   }
   context.db={role:'admin',qrSupplierHidden:input.mode==='remote'?['remote']:[],qrCooperativeHidden:[]};
   if(input.mode==='interleave'){
    let suppliers=[];
    Object.defineProperty(context.db,'qrSupplierHidden',{
     get(){return suppliers},set(value){suppliers=value;queueMicrotask(()=>events.push('interleave'))}
    });
   }
   return Promise.resolve(marker);
  }
 };
 context.window=context;
 if(input.mode==='capture-error')Object.defineProperty(context.db,'qrSupplierHidden',{get(){throw new Error('capture-error')}});
 vm.createContext(context);vm.runInContext(input.source,context);
 const alias=context.loadCloud===context.window.loadCloud;
 let returned=false,rejected=false,error='';
 try{
  const pending=context.loadCloud.apply(owner,args);
  if(input.mode==='deferred'){
   beforeResolve=events.slice();context.db.qrSupplierHidden.push('after-start');resolveBase();
  }
  returned=(await pending)===marker;
 }
 catch(e){rejected=e===marker;error=e.message||''}
 return {alias,returned,rejected,error,events,beforeResolve,atPrune,
  suppliers:input.mode==='capture-error'||input.mode==='restore-error'?null:context.db.qrSupplierHidden,
  cooperatives:context.db.qrCooperativeHidden};
}
run().then(r=>console.log(JSON.stringify(r))).catch(e=>{console.error(e);process.exitCode=1});
"""


def load_block(source):
    start = source.index("/* ===== v1.199-c18 ")
    end = source.index("/* v1.199-c21 ", start)
    return source[start:end]


def evaluate_block(source, mode):
    result = subprocess.run(
        ["node", "-e", HARNESS],
        input=json.dumps({"source": load_block(source), "mode": mode}, ensure_ascii=False),
        capture_output=True,
        text=True,
        timeout=15,
    )
    if result.returncode:
        raise AssertionError(result.stderr or result.stdout)
    return json.loads(result.stdout)


class LoadHookTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = (ROOT / "js/03-inventory.js").read_text(encoding="utf-8")

    def run_hook(self, mode):
        result = evaluate_block(self.source, mode)
        self.assertTrue(result["alias"])
        return result

    def test_restoration_runs_before_prune_and_preserves_result_this_and_arguments(self):
        result = self.run_hook("empty")
        self.assertTrue(result["returned"])
        self.assertFalse(result["rejected"])
        self.assertEqual(result["events"], [["base", True, ["a", 2]], "prune"])
        self.assertEqual(result["suppliers"], ["会社（仮）", "別会社"])
        self.assertEqual(result["cooperatives"], ["単協"])
        self.assertEqual(result["atPrune"], {"suppliers": ["会社（仮）", "別会社"], "cooperatives": ["単協"]})

    def test_base_promise_is_awaited_and_candidates_are_captured_at_start(self):
        result = self.run_hook("deferred")
        self.assertTrue(result["returned"])
        self.assertEqual(result["beforeResolve"], [["base", True, ["a", 2]]])
        self.assertEqual(result["suppliers"], ["会社（仮）", "別会社"])
        self.assertEqual(result["events"], [["base", True, ["a", 2]], "prune"])

    def test_promise_callbacks_between_restoration_and_prune_keep_their_order(self):
        result = self.run_hook("interleave")
        self.assertTrue(result["returned"])
        self.assertEqual(result["events"], [["base", True, ["a", 2]], "interleave", "prune"])

    def test_nonempty_remote_candidates_take_precedence(self):
        result = self.run_hook("remote")
        self.assertTrue(result["returned"])
        self.assertEqual(result["suppliers"], ["remote"])
        self.assertEqual(result["cooperatives"], ["単協"])

    def test_base_rejection_skips_restoration_and_prune(self):
        result = self.run_hook("reject")
        self.assertTrue(result["rejected"])
        self.assertFalse(result["returned"])
        self.assertEqual(result["events"], [["base", True, ["a", 2]]])
        self.assertEqual(result["suppliers"], ["会社（仮）", "会社(仮)", "別会社"])

    def test_restoration_failure_still_prunes_and_returns_base_result(self):
        result = self.run_hook("restore-error")
        self.assertTrue(result["returned"])
        self.assertEqual(result["events"], [["base", True, ["a", 2]], "prune"])
        self.assertEqual(result["error"], "")

    def test_prune_failure_keeps_restoration_and_base_result(self):
        result = self.run_hook("prune-error")
        self.assertTrue(result["returned"])
        self.assertEqual(result["suppliers"], ["会社（仮）", "別会社"])
        self.assertEqual(result["error"], "")

    def test_candidate_capture_failure_does_not_call_base_or_prune(self):
        result = self.run_hook("capture-error")
        self.assertFalse(result["returned"])
        self.assertEqual(result["error"], "capture-error")
        self.assertEqual(result["events"], [])


if __name__ == "__main__":
    unittest.main()
