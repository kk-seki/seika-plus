/* ===== v1.199-c152 動作の重さを測る（画面と動きは変えない） =====
   ・通信：Supabase とのやりとり1回ごとに、どの表・関数か、かかった時間（ミリ秒）、受け取った大きさ（バイト）。
   ・画面：主な画面（ホーム・在庫表など）を開いて、表示し終わるまでの時間。
   ・固まった時間：200ミリ秒以上かかった処理（対応している端末だけ）。
   ・起動：アプリを開いてからホームが出るまで。
   ・端末にためて、1分ごと・画面を閉じたときにまとめて送る（SQL 063 の log_app_perf_v1199c152）。
     SQL 063 がまだ・オフライン・送れなかったときは、端末の中で捨てる（アプリの動きには影響しない）。
   ・送るのは時間・大きさ・名前だけ。入力した中身（品目の数量など）は送らない。 */
(()=>{
const RPC="log_app_perf_v1199c152";
const MAX=400,BATCH=200,EVERY=60000;
const t0=(performance.timeOrigin||Date.now());
let q=[],sending=false,disabled=false,startedHome=false;
const scr=()=>{try{return String(currentScreen||"")}catch(_){return ""}};
const device=()=>{const u=navigator.userAgent||"";const m=u.match(/\(([^)]*)\)/);return (m?m[1]:u).slice(0,120)+` ${screen?.width||0}x${screen?.height||0}`};
function add(kind,name,ms,bytes,extra){
 if(disabled)return;
 q.push({at:new Date().toISOString(),kind,name:String(name||"").slice(0,200),ms:ms==null?null:Math.round(ms),bytes:bytes==null?null:Math.round(bytes),screen:scr(),extra:extra||{}});
 if(q.length>MAX)q.splice(0,q.length-MAX);
}
/* 通信：表の名前（/rest/v1/表）か関数の名前（/rest/v1/rpc/関数）だけを残す（中身や条件は残さない） */
function label(url){
 try{const u=new URL(url,location.href);if(!/\/(rest|auth|storage)\/v1\//.test(u.pathname))return null;
  const p=u.pathname.replace(/^.*\/(rest|auth|storage)\/v1\//,"$1:");return p.replace(/\/[0-9a-f-]{20,}.*/i,"/…")}catch(_){return null}
}
if(typeof window.fetch==="function"&&!window.fetch.__c152){
 const base=window.fetch;
 const wrapped=async function(input,init){
  const url=typeof input==="string"?input:input?.url||"",name=label(url);
  if(!name||name.endsWith(RPC))return base.apply(this,arguments);
  const s=performance.now();
  try{
   const res=await base.apply(this,arguments);
   const ms=performance.now()-s,len=Number(res.headers?.get?.("content-length"));
   if(Number.isFinite(len)&&len>0)add("net",name,ms,len,{status:res.status});
   else{try{res.clone().blob().then(b=>add("net",name,performance.now()-s,b.size,{status:res.status,wait:Math.round(ms)})).catch(()=>add("net",name,ms,null,{status:res.status}))}catch(_){add("net",name,ms,null,{status:res.status})}}
   return res;
  }catch(e){add("net",name,performance.now()-s,null,{error:String(e?.message||e).slice(0,80)});throw e}
 };
 wrapped.__c152=true;window.fetch=wrapped;
}
/* 画面：開いてから表示し終わる（関数が終わって、画面が描き直されるまで）までの時間 */
const PAGES=["home","qrHome","hqHome","hqPrepHome","weeklyData","refreshData","purchasePricesPage","c140ShipPlanPage","c81OpenItem","qrStockPage","orderCandidatePage","excessCandidatePage"];
function wrapPage(fn){
 const base=window[fn];if(typeof base!=="function"||base.__c152)return;
 const w=function(...a){const s=performance.now();let r;try{r=base.apply(this,a)}catch(e){add("page",fn,performance.now()-s,null,{error:1});throw e}
  const done=()=>{add("page",fn,performance.now()-s,null,{});if(fn==="home"&&!startedHome){startedHome=true;add("start","ホームが出るまで",performance.now(),null,{})}};
  Promise.resolve(r).then(()=>requestAnimationFrame(()=>setTimeout(done,0)),()=>add("page",fn,performance.now()-s,null,{error:1}));
  return r};
 w.__c152=true;window[fn]=w;
}
function wrapAll(){for(const fn of PAGES)wrapPage(fn)}
/* 固まった時間（対応している端末だけ） */
try{new PerformanceObserver(list=>{for(const e of list.getEntries())if(e.duration>=200)add("long","固まった時間",e.duration,null,{})}).observe({type:"longtask",buffered:true})}catch(_){}
/* まとめて送る */
async function flush(){
 if(sending||disabled||!q.length||!navigator.onLine||typeof callRpc!=="function")return;
 let role="";try{role=String(db?.role||"")}catch(_){}
 if(!role)return;
 const rows=q.splice(0,BATCH).map(r=>({...r,role,device:device(),app_version:String(window.APP_VERSION||"")+" "+(typeof CACHE_NAME!=="undefined"?CACHE_NAME:"")}));
 sending=true;
 try{await callRpc(RPC,{p_rows:rows})}
 catch(e){const s=String(e?.message||e);if(/Could not find the function|PGRST202|404/i.test(s)){disabled=true;q=[]}}  /* SQL 063 がまだ：測るのをやめる */
 finally{sending=false}
}
setInterval(flush,EVERY);
document.addEventListener("visibilitychange",()=>{if(document.visibilityState==="hidden")flush()});
/* 他のファイルが画面の関数を置き換えたあとに包む（最後に読み込まれるファイル） */
wrapAll();setTimeout(wrapAll,0);setTimeout(wrapAll,3000);
window.c152Perf={add,flush,queue:()=>q.slice(),label,wrapAll,PAGES,startMs:()=>performance.now(),origin:t0};
})();
