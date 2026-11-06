
/* ===== v1.199-c52 QRロット一覧からチェックを入れてまとめて出庫・規格別ロットの全量まとめ出庫 ===== */
(function(){
const c52Selected=new Map();let c52ListMode=false,c52Pending=null;
function c52StockOf(v){return v==="outOfStock"?"outOfStock":v==="all"?"all":"inStock"}
const c52CardBase=qrLotCard;
qrLotCard=function(l){
 const html=c52CardBase.apply(this,arguments);
 if(!c52ListMode||!l||!l.qr_key||!(Number(l.current_qty??0)>0))return html;
 const i=html.indexOf(">");if(i<0)return html;
 const k=String(l.qr_key),on=c52Selected.has(k);
 const box=`<label class="c52Pick" style="display:flex;align-items:center;gap:8px;margin:-2px 0 8px;padding:6px 8px;border:2px dashed #0f766e;border-radius:10px;background:#f0fdfa;font-weight:800;cursor:pointer"><input type="checkbox" class="c52Chk" value="${esc(k)}" ${on?"checked":""} style="width:24px;height:24px" ${seikaEventAttrs("change","c52Toggle",[k,String(l.item_name||""),String(l.lot_no||"")])}>まとめて出庫に入れる</label>`;
 return html.slice(0,i+1)+box+html.slice(i+1);
};
window.qrLotCard=qrLotCard;
function c52BarHtml(){
 const n=c52Selected.size,names=[...new Set([...c52Selected.values()].map(v=>v.item))].join("・");
 return `<div class="small" style="font-weight:800">選んだロット：${n}件${n?`（${esc(names)}）`:""}</div><div class="row" style="margin-top:6px"><button class="btn green" ${n?"":"disabled"} ${seikaEventAttrs("click","c52StartBulk",[])}>選んだロットをまとめて出庫</button><button class="btn btn2" ${n?"":"disabled"} ${seikaEventAttrs("click","c52ClearPick",[])}>選択を外す</button></div>`;
}
function c52RefreshBar(){const b=document.getElementById("c52Bar");if(b)b.innerHTML=c52BarHtml()}
function c52Toggle(k,item,lotNo){const el=[...document.querySelectorAll(".c52Chk")].find(x=>x.value===k);if(el&&el.checked)c52Selected.set(k,{item,lotNo});else c52Selected.delete(k);c52RefreshBar()}
function c52ClearPick(){c52Selected.clear();document.querySelectorAll(".c52Chk").forEach(x=>x.checked=false);c52RefreshBar()}
const c52ListBase=qrLotListPage;
qrLotListPage=async function(...args){
 const mode=c52StockOf(args[2]??"inStock")==="inStock"&&typeof canQrOperate==="function"&&canQrOperate();
 c52ListMode=mode;
 let r;try{r=await c52ListBase.apply(this,args)}finally{c52ListMode=false}
 try{if(mode&&currentScreen==="qrLotListPage"&&!document.getElementById("c52Bar")){
  const host=document.querySelector(".c52Pick")?.closest(".card")?.parentElement;
  if(host)host.insertAdjacentHTML("beforeend",`<div id="c52Bar" class="card" style="position:sticky;bottom:0;z-index:5;border:2px solid #0f766e">${c52BarHtml()}</div>`);
 }}catch(e){console.warn("[まとめて出庫]",e)}
 return r;
};
window.qrLotListPage=qrLotListPage;
async function c52StartBulk(){
 if(!c52Selected.size)return alert("ロットを選んでください");
 if(!canQrOperate())return alert("QR在庫の更新権限がありません。");
 c52Pending={keys:[...c52Selected.keys()]};
 await v135BatchCreatePage("out");
 try{const t=document.querySelector("#v135Destination")?.closest(".card");if(t&&!document.getElementById("c52CreateNote"))t.insertAdjacentHTML("beforebegin",`<div id="c52CreateNote" class="card notice"><b>QRロット一覧で選んだ ${c52Pending.keys.length}件をまとめて出庫します</b><div class="small">出庫先・発注分（本社なら便も）を選んで進むと、数量の確認画面になります。数量は最初「ロット全て」が入っています。</div></div>`)}catch(e){}
}
const c52CreateBase=v135CreateBatch;
v135CreateBatch=async function(kind){
 const pend=kind==="out"?c52Pending:null;
 if(!pend)return c52CreateBase.apply(this,arguments);
 const before=new Set(v135ReadStore().batches.map(b=>b.id));
 await c52CreateBase.apply(this,arguments);
 const batch=v135ReadStore().batches.find(b=>b&&b.kind==="out"&&!before.has(b.id));
 if(!batch)return;
 c52Pending=null;
 await v135BatchStopCamera();
 v161ShowProcessing?.("選んだロットを追加しています");const errs=[];let n=0;
 try{for(const k of pend.keys){try{await v135AddKey(batch.id,k);n++}catch(e){errs.push(`${c52Selected.get(k)?.item||""} ${c52Selected.get(k)?.lotNo||k.slice(0,8)}：${e.message||e}`)}}
  const b=v135GetBatch(batch.id);for(const row of b?.rows||[])v135SetQty(batch.id,row.id,String(Number(row.snapshotQuantity||0)));
 }finally{v161HideProcessing?.()}
 c52Selected.clear();
 if(errs.length)alert(`追加できなかったロットがあります。\n${errs.join("\n")}`);
 await v135BatchReviewPage(batch.id,`${n}件を追加しました。数量を確認して登録してください`);
};
window.v135CreateBatch=v135CreateBatch;
async function c52GradedFull(qrKey){
 if(typeof v1310LoadGrades!=="function")return null;
 await v1310LoadGrades(true);
 const list=(typeof v1310GradeRows!=="undefined"?v1310GradeRows:[]).filter(r=>String(r.qr_key)===String(qrKey));
 return list.length?list:null;
}
const c52RpcBase=callRpc;
callRpc=async function(name,args){
 if(name==="apply_qr_lot_operation"&&args?.p_operation_meta?.batchId&&args?.p_movement_type==="出庫"&&!(typeof v1310PendingOp!=="undefined"&&v1310PendingOp)){
  let list=null;try{list=await c52GradedFull(args.p_qr_key)}catch(e){list=null}
  if(list){
   if(Number(args.p_after_quantity)!==0)return{ok:false,message:"規格別ロットは、まとめ出庫では「ロット全て」のときだけ出庫できます。一部だけ出すときは、通常の出庫画面で規格ごとの数を入れてください。"};
   const grades=list.filter(g=>Number(g.current_qty)>0).map(g=>({grade:g.grade,qty:Number(g.current_qty)}));
   const sum=grades.reduce((a,g)=>a+g.qty,0);
   if(Math.abs(sum-Number(args.p_qty))>1e-9)return{ok:false,conflict:true,message:"規格ごとの残りの合計がロットの残りと合いません。最新の在庫で再試行してください。"};
   const p={};for(const[k,v]of Object.entries(args))p[k.replace(/^p_/,"")]=v;
   const ans=await callRpc("apply_qr_lot_grade_operation_v1300",{p_args:p,p_grades:grades});
   try{v1310GradesAt=0}catch(e){}
   return ans;
  }
 }
 return c52RpcBase(name,args);
};
window.callRpc=callRpc;
const c52ReviewBase=v135BatchReviewPage;
v135BatchReviewPage=async function(batchId,msg=""){
 const r=await c52ReviewBase.apply(this,arguments);
 try{const b=v135GetBatch(batchId);if(b&&b.kind==="out"&&currentScreen==="v135BatchReviewPage"&&typeof v1310LoadGrades==="function"){
  await v1310LoadGrades();
  for(const row of b.rows||[]){const inp=document.getElementById(`v135Qty_${row.id}`);if(!inp||inp.dataset.c52)continue;const g=(typeof v1310GradeRows!=="undefined"?v1310GradeRows:[]).filter(x=>String(x.qr_key)===String(row.qrKey)&&Number(x.current_qty)>0);if(!g.length)continue;inp.dataset.c52="1";inp.insertAdjacentHTML("afterend",`<div class="small" style="color:#92400e;font-weight:800;margin-top:4px">規格別（${esc(v1310GradeText(g,true))}）：「ロット全て」のときだけ出庫できます</div>`)}
 }}catch(e){console.warn("[規格別まとめ出庫]",e)}
 return r;
};
window.v135BatchReviewPage=v135BatchReviewPage;
Object.assign(window,{c52Toggle,c52ClearPick,c52StartBulk});
})();
