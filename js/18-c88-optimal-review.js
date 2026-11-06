
/* ===== v1.199-c88 適正在庫の見直し：担当者IDのずれを吸収／週次見直しに担当品目を全部表示／見直しの記録をサーバーに保存 ===== */
(()=>{
const EXTRA_ALIASES={saito_hiroaki:'saito_dai'};
const canonicalCore=v1151CanonicalBuyerId;
v1151CanonicalBuyerId=function(id){
  const raw=String(id||'').trim(),key=raw.toLowerCase();
  if(EXTRA_ALIASES[key])return EXTRA_ALIASES[key];
  const base=canonicalCore(raw);if(base!==raw)return base;
  const u=(db?.users||[]).find(x=>String(x?.id||'')===raw);
  if(u&&typeof v1179CanonicalStaffId==='function'){const c=v1179CanonicalStaffId(raw,u.name||'');if(c&&c!==raw)return c}
  return raw;
};
window.v1151CanonicalBuyerId=v1151CanonicalBuyerId;

function metaSnap(){return JSON.stringify(db.optimalStockMeta||{})}
function changedMeta(before){const b=JSON.parse(before||'{}'),now=db.optimalStockMeta||{},out={};for(const [k,v] of Object.entries(now))if(JSON.stringify(b[k])!==JSON.stringify(v))out[k]=v;return out}
async function pushMeta(changes){
  if(!Object.keys(changes).length||!['admin','buyer'].includes(db.role))return;
  try{const r=await callRpc('save_optimal_stock_meta_v1199c88',{p_meta:changes});
    if(r&&r.meta&&typeof r.meta==='object'){db.optimalStockMeta={...(db.optimalStockMeta||{}),...r.meta}}}
  catch(e){console.warn('[適正在庫の見直し記録]',e);const m=String(e?.message||e||'');
    alert(/save_optimal_stock_meta_v1199c88|schema cache|does not exist|404/.test(m)?'見直しの記録をサーバーに保存する仕組み（SQL 037）がまだ入っていません。この端末には記録しました。':'見直しの記録をサーバーに保存できませんでした。この端末には記録しました。\n'+m)}
}
function withPush(fn){return function(...a){const before=metaSnap();const r=fn.apply(this,a);pushMeta(changedMeta(before));return r}}
window.saveSettings=withPush(window.saveSettings);try{saveSettings=window.saveSettings}catch(e){}
v1151ContinueOptimalStock=withPush(v1151ContinueOptimalStock);window.v1151ContinueOptimalStock=v1151ContinueOptimalStock;

/* 週次見直し：担当品目を全部表示し、見直しが必要な品目を上に並べる */
function reviewRows(){
  if(db.role!=='buyer')return[];
  const rows=v1153BuyerOptimalItems(),stale=rows.filter(it=>v1144OptimalIsStale(it.id)),fresh=rows.filter(it=>!v1144OptimalIsStale(it.id));
  return [...stale,...fresh];
}
window.optimalStockReviewPage=function(){
  if(db.role!=='buyer')return alert('仕入れ担当者のみ確認できます');
  const rows=reviewRows();setScreen('optimalStockReviewPage');
  const staleCount=rows.filter(it=>v1144OptimalIsStale(it.id)).length;
  const cards=rows.map(it=>{const s=db.settings[it.id]||{},stale=v1144OptimalIsStale(it.id);
    return `<section class="card" data-review-item="${esc(it.id)}" style="${stale?'border:3px solid #f59e0b;background:#fff7ed':''}"><h2 style="margin:0 0 6px">${esc(it.name)}${stale?' <span style="font-size:14px;color:#9a3412;font-weight:800">見直しが必要</span>':''}${it.active===false?' <span class="small">（在庫表で停止中）</span>':''}</h2><div class="small">現在の設定：下限 ${fmt(s.min)}kg / 上限 ${fmt(s.max)}kg<br>${optimalStockLastText(it.id)}</div><label class="label" style="margin-top:12px">今回の確認</label><select id="reviewMode_${esc(it.id)}" class="input" ${seikaEventAttrs('change','v1146ReviewModeChanged',[it.id])}><option value="keep">変更しない（現在の数字を維持）</option><option value="change">数字を変更する</option></select><div id="reviewFields_${esc(it.id)}" class="grid" style="display:none;margin-top:10px"><div><label class="label">新しい下限kg</label><input id="reviewMin_${esc(it.id)}" class="input" inputmode="decimal" value="${esc(s.min)}"></div><div><label class="label">新しい上限kg</label><input id="reviewMax_${esc(it.id)}" class="input" inputmode="decimal" value="${esc(s.max)}"></div></div></section>`}).join('');
  pageShell('適正在庫の週次見直し',`担当品目ごとに「維持」または「変更」を選択してください。担当品目 ${rows.length}品目のうち、見直しが必要な ${staleCount}品目をオレンジの枠で上に表示しています。`,`${rows.length?cards:'<div class="card notice">担当品目がありません。管理者に担当品目の設定を確認してください。</div>'}${rows.length?'<button class="btn green bottom" data-seika-click-action="v1146SaveOptimalReview" data-seika-click-args="%5B%5D">選択内容を保存</button>':''}`);
};
window.v1146SaveOptimalReview=function(){
  if(db.role!=='buyer')return alert('保存できません');
  const rows=reviewRows();if(!rows.length)return home();
  const before=metaSnap(),changes=[];
  for(const it of rows){
    if(!isMyBuyerItem(it.id))return alert(`${it.name}は担当品目ではありません。`);
    const mode=document.getElementById(`reviewMode_${it.id}`)?.value||'keep',prev={...(db.settings[it.id]||{})};
    if(mode==='change'){
      const minText=String(document.getElementById(`reviewMin_${it.id}`)?.value||'').replace(/,/g,'').trim(),maxText=String(document.getElementById(`reviewMax_${it.id}`)?.value||'').replace(/,/g,'').trim();
      const min=Number(minText),max=Number(maxText);if(minText===''||maxText===''||!(min>=0)||!(max>=0)||min>max)return alert(`${it.name}の下限・上限を確認してください。`);
      const after={min:yen(min),max:yen(max)};if(Number(prev.min)!==after.min||Number(prev.max)!==after.max){db.settings[it.id]=after;addOptimalStockChangeLog(it,prev,after,'週次見直しで変更');changes.push(it.id)}
    }
  }
  const targets=rows.filter(it=>changes.includes(it.id)||v1144OptimalIsStale(it.id));
  db.optimalStockMeta=db.optimalStockMeta||{};const checkedAt=nowIso();
  targets.forEach(it=>{db.optimalStockMeta[it.id]={updatedAt:checkedAt,updatedBy:db.user||'',userId:v1151CanonicalBuyerId(db.userId),reviewResult:changes.includes(it.id)?'changed':'kept'}});
  save();pushMeta(changedMeta(before));
  alert(`週次見直しを保存しました（変更 ${changes.length}品目 / 維持 ${targets.length-changes.length}品目）`);home();
};
})();
