
/* ===== v1.199-c89 適正在庫の変更履歴をサーバーに保存（仕入れ担当者の変更も残す） ===== */
(()=>{
const T="optimal_stock_change_logs_v1199c89";let loadedAt=0;
function fromRow(r){return{id:r.id,itemId:r.item_id,itemName:r.item_name,oldMin:r.old_min==null?null:Number(r.old_min),oldMax:r.old_max==null?null:Number(r.old_max),newMin:r.new_min==null?null:Number(r.new_min),newMax:r.new_max==null?null:Number(r.new_max),changedBy:r.changed_by,changedById:r.changed_by_id,role:r.role,memo:r.memo,changedAt:r.changed_at}}
async function loadLogs(){
 try{const rows=await qrSelect(T,"select=*&order=changed_at.desc&limit=3000");db.optimalStockChangeLogs=db.optimalStockChangeLogs||[];
  const have=new Set(db.optimalStockChangeLogs.map(x=>String(x.id)));let add=0;
  for(const r of rows||[])if(!have.has(String(r.id))){db.optimalStockChangeLogs.push(fromRow(r));add++}
  loadedAt=Date.now();return add}catch(e){console.warn("[適正在庫の変更履歴]",e);return 0}
}
async function pushLog(x){
 try{await callRpc("save_optimal_stock_change_log_v1199c89",{p_log:x})}
 catch(e){console.warn("[適正在庫の変更履歴]",e);const m=String(e?.message||e||"");
  if(/save_optimal_stock_change_log_v1199c89|schema cache|does not exist|404/.test(m))console.warn("SQL 038 未実行");}
}
const addBase=addOptimalStockChangeLog;
addOptimalStockChangeLog=function(...a){const n=(db.optimalStockChangeLogs||[]).length;const r=addBase.apply(this,a);const l=db.optimalStockChangeLogs||[];if(l.length>n&&["admin","buyer"].includes(db.role))pushLog(l[l.length-1]);return r};
window.addOptimalStockChangeLog=addOptimalStockChangeLog;
function reloadAfter(name,screen){const base=window[name];if(typeof base!=="function")return;
 const f=function(...a){const r=base.apply(this,a);if(Date.now()-loadedAt>60000)loadLogs().then(n=>{if(n&&currentScreen===screen)base.apply(this,a)});return r};
 window[name]=f;try{if(name==="settings")settings=f;if(name==="optimalStockLogsPage")optimalStockLogsPage=f}catch(e){}}
reloadAfter("settings","settings");reloadAfter("optimalStockLogsPage","optimalStockLogsPage");reloadAfter("optimalStockReviewPage","optimalStockReviewPage");
})();
