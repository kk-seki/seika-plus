
/* ===== v1.199-c86 埼玉・深谷へ大型容器を出庫するときは総重量（kg）を必ず入力／入数（量目と違うときだけ）を入力 =====
   入れた値は出庫の記録（operation_meta.slip）に残し、伝票だけに使う。石岡の在庫の重さには使わない。 */
(()=>{
const DESTS=["埼玉","深谷"],BIG=["網コンテナ","鉄コンテナ","パレテーナ"],KEY="seika_c86_slip_meta";
let pending=null;
function z2h(v){return String(v??"").trim().replace(/[０-９．]/g,c=>String.fromCharCode(c.charCodeAt(0)-0xFEE0))}
function kgOf(v){const t=z2h(v).replace(/\s*(kg|㎏|キロ)$/i,"");if(t==="")return null;const n=Number(t);return n>0&&n<100000?Math.round(n*10)/10:NaN}
function packOf(v){const t=z2h(v);if(!t)return"";const m=t.match(/^([0-9.]+)\s*(kg|㎏|ｋｇ|キロ)?$/i);return m?`${m[1]}kg`:t}
function store(){try{return JSON.parse(localStorage.getItem(KEY)||"{}")||{}}catch(e){return{}}}
function remember(id,v){const s=store();s[id]={...v,at:Date.now()};const k=Object.keys(s).sort((a,b)=>s[a].at-s[b].at);while(k.length>300)delete s[k.shift()];try{localStorage.setItem(KEY,JSON.stringify(s))}catch(e){}}
function ask(title,sub){return new Promise(res=>{
 const w=document.createElement("div");w.style.cssText="position:fixed;inset:0;background:rgba(15,23,42,.55);z-index:99999;display:flex;align-items:center;justify-content:center;padding:16px";
 w.innerHTML=`<div style="background:#fff;border-radius:16px;padding:18px;max-width:420px;width:100%"><b style="font-size:18px">総重量（kg）を入れてください</b><div class="small" style="margin:6px 0 10px">${esc(title)}<br>${esc(sub)}</div><input id="c86AskKg" class="input" inputmode="decimal" placeholder="例：808"><div id="c86AskErr" class="small" style="color:#b91c1c;min-height:18px"></div><div style="display:flex;gap:8px;margin-top:6px"><button type="button" class="btn btn2" style="flex:1" data-x="0">出庫しない</button><button type="button" class="btn green" style="flex:1" data-x="1">この重さで出庫</button></div></div>`;
 document.body.appendChild(w);const inp=w.querySelector("#c86AskKg");setTimeout(()=>inp.focus(),50);
 w.addEventListener("click",e=>{const b=e.target.closest("[data-x]");if(!b)return;if(b.dataset.x==="0"){w.remove();return res(null)}const n=kgOf(inp.value);if(!(n>0)){w.querySelector("#c86AskErr").textContent="0より大きい数字で入れてください。";return}w.remove();res(n)});
})}
async function lotInfo(q){try{return(await qrSelect("qr_lots",`select=item_name,container_type,unit,pack_weight&qr_key=eq.${encodeURIComponent(q)}&limit=1`))[0]||null}catch(e){return null}}
/* 単発のQR出庫画面 */
let pageLot=null;
function boxHtml(){const big=BIG.includes(String(pageLot?.container_type||""));
 return big?`<label class="label" style="margin-top:10px">総重量（kg） <span style="color:#dc2626">必須</span></label><input id="c86Kg" class="input" inputmode="decimal" placeholder="例：808"><div class="small">出庫する${esc(pageLot.container_type)}全部の重さです。伝票の数量に入ります（石岡の在庫の重さは変わりません）。</div>`
 :`<label class="label" style="margin-top:10px">入数（量目と違うときだけ）</label><input id="c86Pack" class="input" placeholder="例：12kg（ロットの量目：${esc(pageLot?.pack_weight||"なし")}）"><div class="small">伝票の入数に入ります。空欄ならロットの量目のままです。</div>`}
function toggle(){const b=document.getElementById("c86Box");if(!b)return;b.style.display=DESTS.includes(document.getElementById("qrMoveDestination")?.value||"")?"block":"none"}
const opBase=qrOperationLotPage;
qrOperationLotPage=async function(kind,q){
 const r=await opBase.apply(this,arguments);
 if(kind==="out"){try{pageLot=await qrFindLot(q).catch(()=>null);const after=document.getElementById("c50ShipBox")||document.getElementById("qrShipTimingBox");
  if(after&&pageLot&&!document.getElementById("c86Box")){after.insertAdjacentHTML("afterend",`<div id="c86Box" style="display:none">${boxHtml()}</div>`);toggle()}}catch(e){console.warn("[総重量]",e)}}
 return r;
};
window.qrOperationLotPage=qrOperationLotPage;
document.addEventListener("change",e=>{if(e.target?.id==="qrMoveDestination")toggle()},true);
const saveBase=qrSaveLotMovement;
qrSaveLotMovement=async function(kind,q){
 pending=null;
 if(kind==="out"&&DESTS.includes(document.getElementById("qrMoveDestination")?.value||"")&&document.getElementById("c86Box")){
  const kEl=document.getElementById("c86Kg"),pEl=document.getElementById("c86Pack");
  if(kEl){const n=kgOf(kEl.value);if(!(n>0)){typeof v161FocusField==="function"?v161FocusField("c86Kg","総重量（kg）を入れてください。"):alert("総重量（kg）を入れてください。");return}pending={kg:n}}
  else if(pEl&&pEl.value.trim())pending={pack:packOf(pEl.value)};
 }
 try{return await saveBase.apply(this,arguments)}finally{pending=null}
};
window.qrSaveLotMovement=qrSaveLotMovement;
/* すべての出庫（単発・連続・まとめ出庫）で、記録に総重量・入数を付ける */
const rpcBase=callRpc;
callRpc=async function(name,args){
 if(name==="apply_qr_lot_operation"&&args&&args.p_movement_type==="出庫"&&DESTS.includes(String(args.p_destination||""))){
  const id=String(args.p_operation_id||"");let v=id?store()[id]:null;
  if(!v&&pending)v=pending;
  if(!v){const l=await lotInfo(args.p_qr_key);
   if(l&&BIG.includes(String(l.container_type||""))){const n=await ask(`${l.item_name}　${args.p_qty}基 → ${args.p_destination}`,"埼玉・深谷へ大型容器を出庫するときは、総重量の入力が必要です。");
    if(n===null)return{ok:false,message:"総重量（kg）が未入力のため、出庫していません。"};v={kg:n}}}
  if(v&&(v.kg||v.pack)){if(id)remember(id,v);const m=args.p_operation_meta&&typeof args.p_operation_meta==="object"?args.p_operation_meta:{};args.p_operation_meta={...m,slip:v.kg?{kg:v.kg}:{pack:v.pack}}}
 }
 return rpcBase(name,args);
};
window.callRpc=callRpc;
})();
