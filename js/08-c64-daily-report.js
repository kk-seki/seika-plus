
/* ===== v1.199-c64 日報登録：候補をすぐ表示・押して追加／日報の廃棄を廃棄一覧へ自動で反映（トリミング廃棄） ===== */
(function(){
const C64_LIST_MAX=30;
let c64Waste={kg:'',touched:false},c64PendingWaste=null,c64SkipTrimOnce=false,c64Timer=0;
function c64LotListHtml(){
 if(!v195TrimLotsLoaded)return '<select class="input" disabled><option>ロットを読み込み中です…</option></select>';
 const list=v195TrimLotCandidates(),first=v1115Trimming.lots[0],shown=list.slice(0,V195_TRIM_LIST_MAX);
 const opts=shown.map(l=>{
  const qty=v195TrimLotQty(l),unit=qrLotUnit(l),day=String(l.received_date||'').slice(0,10);
  const label=`${day?`${Number(day.slice(5,7))}/${Number(day.slice(8,10))}`:'日付なし'}｜${l.item_name||'（品名未設定）'}｜${l.lot_no||l.qr_key||''}｜${qty>0?`残 ${fmt(qty)}${unit}`:'在庫なし'}${l.supplier?`｜${l.supplier}`:''}`;
  return `<option value="${esc(String(l.qr_key||l.lot_no||''))}">${esc(label)}</option>`;
 }).join('');
 const head=list.length?`▼ 入荷日｜品名｜ロット｜在庫｜仕入先 から選ぶ（${list.length}件）`:'条件に合うロットがありません';
 return `<select id="trimLotPicker" class="input" ${seikaEventAttrs('change','c64PickLotSel',[])}><option value="">${esc(head)}</option>${opts}</select><div class="small" style="margin-top:4px">品名・ロット番号・入荷日・在庫を入れると、▼の中身がすぐ絞り込まれます。${list.length>shown.length?`（新しい順に${shown.length}件まで）`:''}${first?` ／ ${esc(first.itemName)}だけ表示中`:''}</div>`;
}
function c64PickLotSel(){const sel=document.getElementById('trimLotPicker'),key=sel?sel.value:'';if(key)c64PickLot(key)}
function c64RefreshList(){v195CaptureTrimFilter();const box=document.getElementById('trimLotList');if(box)box.innerHTML=c64LotListHtml()}
function c64PickLot(key){
 v195CaptureTrimFilter();
 const lot=(v195TrimLots||[]).find(l=>String(l.qr_key||'')===key||String(l.lot_no||'')===key)||null;
 try{v195AddTrimLotObject(lot);v1115RenderTrimming()}catch(e){alert(e.message||'ロットを追加できませんでした')}
}
function c64DefaultWaste(){const t=v1115TrimmingTotals();if(!(t.input>0))return '';return String(Math.max(0,Math.round(t.loss*100)/100))}
function c64SyncWaste(){
 const el=document.getElementById('trimWasteKg');if(!el)return;
 if(!c64Waste.touched){const v=c64DefaultWaste();if(el.value!==v&&document.activeElement!==el)el.value=v;c64Waste.kg=v}
 else if(el.value!==c64Waste.kg&&document.activeElement!==el)el.value=c64Waste.kg;
}
const c64RenderBase=v1115RenderTrimming;
v1115RenderTrimming=function(...args){
 for(const l of v1115Trimming.lots){if(l.mode!=='weight'){const a=Number(document.getElementById(`trimLotAmount_${l.id}`)?.value||l.amount||0);l.mode='weight';l.amount=a>0&&l.unitWeight>0?String(Math.round(a*l.unitWeight*100)/100):''}}
 if(!v1115Trimming.outputs.length)v1115Trimming.outputs.push({id:v1115Uuid(),name:'',itemId:'',itemName:'',mode:'weight',weight:''});
 for(const o of v1115Trimming.outputs)o.mode='weight';
 const r=c64RenderBase.apply(this,args);
 try{
  const name=document.getElementById('trimLotFilterName');
  if(name&&!name.dataset.c64){name.dataset.c64='1';name.addEventListener('input',()=>{clearTimeout(c64Timer);c64Timer=setTimeout(c64RefreshList,150)})}
  for(const id of ['trimLotFilterDate','trimLotFilterStock']){const el=document.getElementById(id);if(el&&!el.dataset.c64){el.dataset.c64='1';el.removeAttribute('data-seika-change-action');el.addEventListener('change',c64RefreshList)}}
  const w=document.getElementById('trimWasteKg');
  if(w&&!w.dataset.c64){w.dataset.c64='1';w.addEventListener('input',()=>{const v=w.value.trim();c64Waste=v===''?{kg:'',touched:false}:{kg:v,touched:true}});w.addEventListener('blur',c64SyncWaste)}
  c64SyncWaste();
 }catch(e){console.warn('[v1.199-c64]',e)}
 return r;
};
window.v1115RenderTrimming=v1115RenderTrimming;
const c64SummaryBase=v1115RefreshTrimmingSummary;
function c64YieldNoteHtml(){const t=v1115TrimmingTotals();return t.input<=0?'<div class="small" style="color:#b45309;margin-top:6px">使用原料が未入力のため歩留まりは計算できません。上で使用原料のロットを追加し、使用量を入力してください。</div>':(t.output>t.input+0.011?'<div class="small" style="color:#0f766e;margin-top:6px">歩留まりが100%を超えています。10kg入りの原料に10kg以上入っていた場合などに起こります。実測どおりの数字のまま登録できます。</div>':'')}
function c64SyncYieldNote(){const box=document.getElementById('trimYieldNote');if(box){const h=c64YieldNoteHtml();if(box.innerHTML!==h)box.innerHTML=h}}
v1115RefreshTrimmingSummary=function(...args){const r=c64SummaryBase.apply(this,args);try{c64SyncWaste();c64SyncYieldNote()}catch(e){}return r};
window.v1115RefreshTrimmingSummary=v1115RefreshTrimmingSummary;
document.addEventListener('input',e=>{const id=String(e.target&&e.target.id||'');if(/^trim(LotAmount|OutWeight|OutQty|OutUnit)_/.test(id))setTimeout(()=>{c64SyncWaste();c64SyncYieldNote()},0)});
document.addEventListener('change',e=>{const id=String(e.target&&e.target.id||'');if(/^trim(LotMode|OutMode)_/.test(id))setTimeout(c64SyncWaste,0)});
const c64ResetBase=v1115TrimmingReset;
v1115TrimmingReset=function(...args){c64Waste={kg:'',touched:false};return c64ResetBase.apply(this,args)};
window.v1115TrimmingReset=v1115TrimmingReset;

const c64SaveBase=v1115SaveTrimming;
v1115SaveTrimming=async function(...args){
 const el=document.getElementById('trimWasteKg'),raw=String(el?.value??'').trim(),kg=raw===''?0:Number(raw);
 if(!Number.isFinite(kg)||kg<0)return alert('④の「廃棄した重さ」は0以上の数字で入力してください（捨てていないときは0）');
 const t=v1115TrimmingTotals();
 if(t.input>0&&kg>t.input+0.001)return alert(`④の「廃棄した重さ」（${fmtRounded(kg)}kg）が使用原料（${fmtRounded(t.input)}kg）より多くなっています。数字を確かめてください。`);
 const confirmBase=window.confirm;
 window.confirm=function(msg){return confirmBase(`${String(msg||'')}\n\n廃棄：${fmtRounded(kg)}kg${kg>0?'（廃棄一覧に「トリミング廃棄」として入ります）':''}`)};
 c64PendingWaste=kg;
 try{return await c64SaveBase.apply(this,args)}
 finally{window.confirm=confirmBase;c64PendingWaste=null}
};
window.v1115SaveTrimming=v1115SaveTrimming;

const c64RpcBase=callRpc;
callRpc=async function(name,args){
 const ans=await c64RpcBase.apply(this,arguments);
 if((name==='create_trimming_job'||name==='replace_trimming_job_v1203')&&c64PendingWaste!==null&&ans&&ans.ok){
  const jobId=ans.job&&ans.job.id,kg=c64PendingWaste;
  let err='';
  if(!jobId)err='日報の番号が分かりませんでした';
  else for(let i=0;i<2;i++){try{const r=await c64RpcBase('set_trimming_waste_v1640',{p_job_id:jobId,p_waste_kg:kg});if(r&&r.ok){err='';break}err=r&&r.message||'保存できませんでした'}catch(e){err=e&&e.message||String(e)}}
  if(err)alert(`日報は登録しましたが、廃棄（${fmtRounded(kg)}kg）を記録できませんでした。\n製造日報でこの日報の「この日報を修正」を押し、そのまま保存し直してください。\n\n${err}`);
 }
 return ans;
};
window.callRpc=callRpc;

const c64EditBase=window.v1203EditJob;
if(typeof c64EditBase==='function'){
 window.v1203EditJob=async function(jobId,...rest){
  const r=await c64EditBase.call(this,jobId,...rest);
  try{
   if(!document.getElementById('trimWasteKg'))return r;
   const day=typeof v196TrimWorkDate!=='undefined'?v196TrimWorkDate:'';
   const rows=await callRpc('get_trimming_jobs',{p_from:day||null,p_to:day||null});
   const row=(Array.isArray(rows)?rows:[]).find(x=>String((x.job||x).id)===String(jobId));
   const kg=row&&(row.job||row).waste_weight_kg;
   c64Waste=kg===null||kg===undefined?{kg:'',touched:false}:{kg:String(Number(kg)),touched:true};
   const el=document.getElementById('trimWasteKg');if(el)el.value=c64Waste.touched?c64Waste.kg:c64DefaultWaste();
  }catch(e){console.warn('[v1.199-c64 修正読込]',e)}
  return r;
 };
}

function c64TrimRow(x){
 const weight=Number(x.weight||0),price=x.purchase_price_yen_per_kg===null||x.purchase_price_yen_per_kg===undefined?0:Number(x.purchase_price_yen_per_kg),amount=x.waste_amount_yen===null||x.waste_amount_yen===undefined?null:Number(x.waste_amount_yen);
 return {...x,id:`trim:${x.source_id}`,source:'trim',sourceId:String(x.source_id||''),source_id:String(x.source_id||''),jobId:String(x.job_id||''),date:x.date||'',itemName:x.item_name||'',qty:weight,weight,sourceQty:weight,unit:'kg',unitPrice:price,amount,origin:x.origin||'',supplier:x.supplier||'',reason:'トリミング',memo:['製造日報から自動',x.memo||''].filter(Boolean).join(' / '),user:x.user_name||'',lotNo:x.lot_no||'',qrKey:x.qr_key||'',priceMatchType:x.price_match_type||'未計算',priceMatchReason:x.price_match_reason||'',createdAt:x.occurred_at||'',isQrWaste:false};
}
const c64LoadBase=v1144LoadUnifiedWaste;
v1144LoadUnifiedWaste=async function(from,to){
 const skip=c64SkipTrimOnce;c64SkipTrimOnce=false;
 const r=await c64LoadBase.apply(this,arguments);
 if(skip)return r;
 const key=v1144DateRangeKey(from,to);
 try{
  const ans=await callRpc('list_trimming_waste_v1640',{p_from:from,p_to:to});
  if(v1144QrWasteCache.key!==key)return r;
  const add=(Array.isArray(ans&&ans.rows)?ans.rows:[]).map(c64TrimRow);
  v1144QrWasteCache={...v1144QrWasteCache,rows:v1144DedupeWasteRows([...(v1144QrWasteCache.rows||[]).filter(x=>x.source!=='trim'),...add])};
 }catch(e){console.warn('[トリミング廃棄の取得]',e)}
 return r;
};
window.v1144LoadUnifiedWaste=v1144LoadUnifiedWaste;
if(typeof v1162AutoApplyVisibleWastePrices==='function'){
 const c64AutoBase=v1162AutoApplyVisibleWastePrices;
 v1162AutoApplyVisibleWastePrices=async function(...args){c64SkipTrimOnce=true;try{return await c64AutoBase.apply(this,args)}finally{c64SkipTrimOnce=false}};
 window.v1162AutoApplyVisibleWastePrices=v1162AutoApplyVisibleWastePrices;
}

const c64WasteEntryBase=wasteEntryPage;
wasteEntryPage=function(...args){
 const r=c64WasteEntryBase.apply(this,args);
 try{if(currentScreen==='wasteEntryPage'&&!document.getElementById('c64TrimNotice')){const card=document.querySelector('#app .card, .card');if(card)card.insertAdjacentHTML('beforebegin','<div id="c64TrimNotice" class="notice" style="margin-bottom:10px"><b>トリミングで出た廃棄は、ここで入力しないでください。</b><div class="small">製造・歩留まりの「日報を登録」の「④ 廃棄」に入れると、廃棄一覧に「トリミング廃棄」として自動で入ります。ここでも入れると二重になります。</div></div>')}}catch(e){}
 return r;
};
window.wasteEntryPage=wasteEntryPage;

try{
 if(typeof V198_GUIDE_SECTIONS!=='undefined'&&V198_GUIDE_SECTIONS.trimming){
  const g=V198_GUIDE_SECTIONS.trimming;g.title='日報を登録する';
  g.steps=g.steps.map(x=>x.startsWith('「使用原料」でロットを追加します')?'「② 使用原料」の「候補から選ぶ」の▼からロットを選ぶと追加されます。品名・ロット番号・入荷日・在庫の有無を入れると、▼の中身がすぐ絞り込まれます（検索ボタンはありません）。':x.startsWith('使った数量または重量を入力します')?'使った原料の重さ（kg）を入力します。入力は重さだけです。':x.startsWith('「出来高」に入替品を追加し')?'「③ 出来高」は最初から1件出ています。▼の候補（製造・歩留まりの「入替品登録」で登録した品目）から選ぶか、候補に無いときは手入力し、重さ（kg）を入力します。2種類以上できたときは「＋ 出来高（入替品）を追加」で増やします。':x.startsWith('使用重量・ロス・歩留まりを確認し')?'重量集計で使用重量・ロス・歩留まりを確認します。':x);
  const i=g.steps.findIndex(x=>x.startsWith('重量集計で'));
  g.steps.splice(i<0?g.steps.length:i+1,0,'「④ 廃棄」の「廃棄した重さ」を確かめます。ロス（使用原料−出来高）の重さが入ります。','「⑤ 確認して登録」で、必要ならメモを入れて登録します。登録すると廃棄一覧（週次廃棄レポート・Excelも）に「トリミング廃棄」として入ります。単価は原料ロットの仕入先を仕入れ価格表と照らし合わせて決まります。');
  g.caution='通常在庫・QR在庫・QR操作履歴は変更されません。廃棄入力で同じ分を入れないでください（二重になります）。日報を修正・削除すると、トリミング廃棄も一緒に変わります。';
 }
}catch(e){}
let c68Cands=null,c68CandsLoading=null;
async function c68LoadCands(force){
 if(c68Cands&&!force)return c68Cands;
 if(!c68CandsLoading)c68CandsLoading=(async()=>{try{const a=await callRpc('list_trim_output_candidates_v1680',{p_include_hidden:false});c68Cands=Array.isArray(a&&a.rows)?a.rows:[]}catch(e){console.warn('[入替品の候補]',e);c68Cands=c68Cands||[]}finally{c68CandsLoading=null}return c68Cands})();
 return c68CandsLoading;
}
function c68RefreshOutputSelects(){for(const o of v1115Trimming.outputs){const sel=document.getElementById(`trimOutPick_${o.id}`);if(!sel)continue;const cur=document.getElementById(`trimOutNormal_${o.id}`)?.value||'';sel.innerHTML=c64OutputOptionsHtml({...o,itemName:cur})}}
function c64ExchangeNames(){
 if(!c68Cands){c68LoadCands().then(c68RefreshOutputSelects);return null}
 return [...new Set(c68Cands.filter(c=>c.active!==false).map(c=>String(c.name||'').trim()).filter(Boolean))];
}
function c64OutputOptionsHtml(line){
 const all=c64ExchangeNames(),cur=String(line&&(line.itemName||line.itemId)||'').trim();
 if(all===null)return '<option value="">候補を読み込み中です…</option>';
 if(!all.length)return '<option value="">（候補がありません。製造・歩留まりの「入替品登録」で登録してください）</option>';
 return `<option value="">▼ 候補から選ぶ（${all.length}件）</option>`+all.map(n=>`<option value="${esc(n)}" ${n===cur?'selected':''}>${esc(n)}</option>`).join('');
}
function c64PickOutputSel(id){
 const sel=document.getElementById(`trimOutPick_${id}`),name=sel?sel.value:'';if(!name)return;
 const el=document.getElementById(`trimOutNormal_${id}`);if(el)el.value=name;
 const line=v1115Trimming.outputs.find(x=>x.id===id);if(line){line.itemName=name;line.itemId=name}
 document.getElementById(`trimOutWeight_${id}`)?.focus();
}
document.addEventListener('input',e=>{const m=String(e.target&&e.target.id||'').match(/^trimOutNormal_(.+)$/);if(m){const sel=document.getElementById(`trimOutPick_${m[1]}`);if(sel&&sel.value!==e.target.value.trim())sel.value=[...sel.options].some(o=>o.value===e.target.value.trim())?e.target.value.trim():''}});
window.c64OutputOptionsHtml=c64OutputOptionsHtml;window.c68ResetCands=()=>{c68Cands=null};
Object.assign(window,{c64PickLot,c64PickLotSel,c64RefreshList,c64PickOutputSel,v1640LotListHtml:c64LotListHtml});
window.v1640LotListHtml=c64LotListHtml;
})();
