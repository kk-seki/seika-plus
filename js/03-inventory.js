

/* ===== v1.179: inventory-reflecting stocktake ===== */
const V177_COUNT_MODE='inventory_apply_v177';
const V177_CREATE_RPC='v177_create_inventory_count_session';
const V177_SAVE_RPC='v177_save_inventory_count_section';
const V177_FINALIZE_RPC='v177_apply_inventory_count_session';
const v177QrItemState=new Map();
let v177CameraReader=null,v177CameraGeneration=0,v177CameraBusy=false;
function v177Allowed(){return db.role==='admin'||db.role==='worker'}
function v177Session(s){return Boolean(s&&s.inventoryCountMode===V177_COUNT_MODE)}
function v177SectionStatus(s,section){return String(s?.[section==='normal'?'normalStatus':'qrCountStatus']||'counting')}
function v177SectionRevision(s,section){return Number(s?.[section==='normal'?'normalRevision':'qrRevision']||0)}
function v177SectionDone(s,section){return v177SectionStatus(s,section)==='submitted'}
function v177Completed(s){return v177Session(s)&&Boolean(s?.v177Applied||s?.v177AppliedAt||s?.v177CompletedAt)}
function v177BeforeToday(value){if(!value)return false;try{return ymdKey(new Date(value))<ymdKey(new Date())}catch(error){return false}}
function v177LatestSpecialRecord(tableId,itemId){const rows=(db.specialRecords||[]).filter(row=>String(row?.tableId||'')===String(tableId)&&String(row?.itemId||'')===String(itemId)&&row?.createdAt);return rows.sort((a,b)=>new Date(a.createdAt||0)-new Date(b.createdAt||0)).at(-1)||null}
function v177NormalLines(room){
 const rows=[];
 for(const item of allSortedItems()){
  if(item?.active===false||coldRoomForNormalItem(item)!==room)continue;
  const record=latestRecord(item.id),qty=Number(record?.total||0);
  if(!(qty>0))continue;
  rows.push({lineId:newId(),type:'normal',itemId:item.id,itemName:item.name,unit:'kg',group:'通常在庫',room,systemQty:qty,snapshotPackKg:countSnapshotPackKg(item,record),snapshotCases:countSnapshotCases(item,record,'kg',qty),snapshotRecordId:record?.id||null,actualQty:null,memo:'',status:'unentered'});
 }
 for(const tableId of Object.keys(SPECIAL_STOCK_TABLES))for(const item of specialItems(tableId)){
  if(item?.active===false||coldRoomForSpecialItem(tableId,item)!==room)continue;
  const record=v177LatestSpecialRecord(tableId,item.id),qty=Number(record?.qty||0);
  if(!(qty>0))continue;
  rows.push({lineId:newId(),type:'special',tableId,itemId:item.id,itemName:item.name,unit:item.unit||'ケース',group:tableId==='kataoka'?'片岡在庫':'その他在庫',room,systemQty:qty,snapshotPackKg:countSnapshotPackKg(item,record),snapshotCases:countSnapshotCases(item,record,item.unit||'ケース',qty),snapshotRecordId:record?.id||null,actualQty:null,memo:'',status:'unentered'});
 }
 return rows;
}
async function v177QrSnapshot(room){
 const locations=qrCountLocations(room),lots=[];let offset=0;
 for(;;){const page=await qrSelect('qr_lots',`select=*&active=eq.true&current_qty=gt.0&order=qr_key.asc&limit=1000&offset=${offset}`);lots.push(...page);if(page.length<1000)break;offset+=1000}
 return qrCountLinesFromLots(room,lots.filter(lot=>locations.includes(lot.storage_location)));
}
function v177Entries(s,section){return v124DraftEntries(s,section)}
function v177EntryMap(s,section){return new Map(v177Entries(s,section).map(entry=>[String(entry.id),entry]))}
function v177Rows(s,section){return Array.isArray(s?.[section==='normal'?'lines':'qrLines'])?s[section==='normal'?'lines':'qrLines']:[]}
function v177LineId(line,section){return String(v124LineId(line,section)||line?.lineId||line?.qrKey||'')}
function v177QrManualWeightRequired(line){const total=Number(line?.snapshotTotalWeight),initial=Number(line?.snapshotInitialQty);return String(line?.unit||'')==='基'&&!(Number.isFinite(total)&&total>0&&Number.isFinite(initial)&&initial>0)}
function v177Missing(s,section){return v177Rows(s,section).filter(line=>{const entry=v177EntryMap(s,section).get(v177LineId(line,section));if(!entry)return true;if(section==='normal')return v119IsKgLine(line)?v124WeightTotal(entry.weightEntries,entry.remainderKg)===null:v119StrictDecimal(entry.actualQty)===null;const qty=v119StrictDecimal(entry.actualQty);if(qty===null)return true;if(v177QrManualWeightRequired(line)&&v119StrictDecimal(entry.actualWeightKg)===null)return true;const diff=qty-Number(line.systemQty||0);return diff<0&&(!String(entry.destination||'').trim()||!String(entry.shipTiming||'').trim())})}
function v177PersistDom(id,section){
 const s=countSession(id);if(!s)return;const map=v177EntryMap(s,section);
 for(const line of v177Rows(s,section)){const key=v177LineId(line,section),entry={...(map.get(key)||{id:key})};if(section==='normal'){
   if(v119IsKgLine(line)){entry.weightEntries=[...document.querySelectorAll(`[data-v124-weight="${CSS.escape(key)}"]`)].map(node=>({id:node.dataset.entryId,packKg:v171Value(`v124_pack_${key}_${node.dataset.entryId}`),caseCount:v171Value(`v124_case_${key}_${node.dataset.entryId}`)}));entry.remainderKg=v171Value(`v124_rem_${key}`);entry.actualQty=v124WeightTotal(entry.weightEntries,entry.remainderKg)}else{entry.actualQty=v171Value(`v124_qty_${key}`);entry.kgPerUnit=v171Value(`v124_kgper_${key}`)}
   entry.supplier=v171Value(`v124_supplier_${key}`);entry.memo=v171Value(`v124_memo_${key}`);
  }else{entry.actualQty=v171Value(`v177_qty_${key}`);entry.actualWeightKg=v177QrManualWeightRequired(line)?v171Value(`v177_weight_${key}`):'';const actual=v119StrictDecimal(entry.actualQty),diff=actual===null?null:actual-Number(line.systemQty||0);entry.outQty=diff===null?'':Math.max(0,-diff);entry.destination=diff!==null&&diff<0?v171Value(`v177_dest_${key}`):'';entry.shipTiming=diff!==null&&diff<0?v171Value(`v177_timing_${key}`):'';entry.memo=v171Value(`v177_memo_${key}`)}map.set(key,entry)}
 v124WriteDraft(id,section,[...map.values()]);
}
function v177QrLineHtml(s,line,editable,entry){
 const id=v177LineId(line,'qr'),actual=v119StrictDecimal(entry.actualQty),diff=actual===null?null:actual-Number(line.systemQty||0),decrease=diff!==null&&diff<0,manualWeight=v177QrManualWeightRequired(line);
 const weightInput=manualWeight?`<div style="margin-top:8px"><label class="label">棚卸し重量kg（必須）</label><input id="v177_weight_${esc(id)}" class="input v171Enter" inputmode="decimal" value="${esc(entry.actualWeightKg??'')}" placeholder="大型容器の開始時重量が不明なため入力" ${seikaEventAttrs('input','v177PersistDom',[s.id,'qr'])} ${editable?'':'disabled'}></div>`:'';
 return `<section class="card countLine ${actual===null?'v123Missing':''}"><div class="countMeta"><div><b>${esc(line.itemName||'QRロット')}</b><div class="small">ロット：${esc(line.lotNo||line.qrKey||id)} / ${esc(line.containerType||line.unit||'')} / 開始時：${fmt(line.systemQty)} ${esc(line.unit||'')}</div></div><span class="badge ${actual===null?'unset':diff===0?'normal':diff<0?'shortage':'excess'}">${actual===null?'未入力':`${diff>0?'+':''}${fmt(diff)} ${esc(line.unit||'')}`}</span></div><div class="row" style="margin-top:8px"><div><label class="label">棚卸し実数（${esc(line.unit||'単位')}）</label><input id="v177_qty_${esc(id)}" class="input v171Enter" inputmode="decimal" value="${esc(entry.actualQty??'')}" placeholder="空欄=未入力 / 0=在庫なし" ${seikaEventAttrs('input','v177PersistDom',[s.id,'qr'])} ${editable?'':'disabled'}></div><div><label class="label">備考</label><input id="v177_memo_${esc(id)}" class="input v171Enter" value="${esc(entry.memo||'')}" ${seikaEventAttrs('input','v177PersistDom',[s.id,'qr'])} ${editable?'':'disabled'}></div></div>${weightInput}<div class="row" style="margin-top:8px"><div><label class="label">出庫先${decrease?'（必須）':'（減少時に必須）'}</label><select id="v177_dest_${esc(id)}" class="input v171Enter" ${seikaEventAttrs('input','v177PersistDom',[s.id,'qr'])} ${editable?'':'disabled'}><option value="">選択してください</option>${QR_OUT_DESTINATIONS.filter(x=>x!=='廃棄').map(name=>`<option value="${esc(name)}" ${entry.destination===name?'selected':''}>${esc(name)}</option>`).join('')}</select></div><div><label class="label">出庫区分${decrease?'（必須）':'（減少時に必須）'}</label><select id="v177_timing_${esc(id)}" class="input v171Enter" ${seikaEventAttrs('input','v177PersistDom',[s.id,'qr'])} ${editable?'':'disabled'}><option value="">選択してください</option>${QR_SHIP_TIMINGS.map(name=>`<option value="${esc(name)}" ${entry.shipTiming===name?'selected':''}>${esc(name)}</option>`).join('')}</select></div></div>${decrease?'<div class="small" style="margin-top:7px;color:#b91c1c">開始時より減少したため、出庫先と出庫区分を選択してください。</div>':'<div class="small" style="margin-top:7px">増加は棚卸し調整増、同数は確認済みとして最終反映されます。</div>'}</section>`;
}
function v177QrItems(s){return [...new Set(v177Rows(s,'qr').map(line=>String(line.itemName||'品名未設定')))].sort((a,b)=>a.localeCompare(b,'ja'))}
function v177SectionPage(id,section,msg='',item=''){
 const s=countSession(id);if(!s||!v177Session(s))return inventoryCountHome(msg);const editable=v177Allowed()&&!v177SectionDone(s,section)&&!v177Completed(s),entries=v177EntryMap(s,section);let rows=v177Rows(s,section),selected='';
 if(section==='qr'){selected=item||v177QrItemState.get(id)||v177QrItems(s)[0]||'';v177QrItemState.set(id,selected);rows=rows.filter(line=>String(line.itemName||'品名未設定')===selected)}
 setScreen('v177SectionPage',[id,section,msg,selected]);
 const selector=section==='qr'?`<div class="card"><label class="label">QR品目を選択</label><select class="input" ${seikaEventAttrs('change','v177SetQrItem',[id,{__seikaValue:true}])}>${v177QrItems(s).map(name=>`<option value="${esc(name)}" ${name===selected?'selected':''}>${esc(name)}</option>`).join('')}</select><div class="grid" style="margin-top:10px"><button class="btn blue" ${seikaEventAttrs('click','v177CameraPage',[id,selected])}>QRカメラで選択</button><button class="btn btn2" ${seikaEventAttrs('click','v177ManualQrPage',[id,selected])}>QRコードを入力・一覧選択</button></div></div>`:'';
 const contents=section==='normal'?rows.map(line=>v171NormalLineHtml(s,line,'normal',editable,entries.get(v177LineId(line,'normal'))||{id:v177LineId(line,'normal'),weightEntries:[{id:'w-1',packKg:'',caseCount:''}]})).join(''):rows.map(line=>v177QrLineHtml(s,line,editable,entries.get(v177LineId(line,'qr'))||{id:v177LineId(line,'qr')})).join('');
 const print=section==='normal'?`<button class="btn btn2" ${seikaEventAttrs('click','v177PrintNormal',[id])}>通常在庫記入票を印刷</button>`:`<button class="btn btn2" ${seikaEventAttrs('click','v177PrintQrPages',[id])}>QR品目別記入票を印刷</button>`;
 pageShell(section==='normal'?'通常在庫 棚卸し入力':'QR在庫 棚卸し入力',`${esc(s.countNo)} / ${esc(s.roomLabel)}`,`${okHtml(msg)}<div class="card notice"><b>${section==='normal'?'通常在庫':'QR在庫'} ${v177SectionDone(s,section)?'完了済み':'入力中'}</b><div class="small">${section==='normal'?'量目kg×ケース数を複数行で入力できます。仕入先・備考は任意です。':'品目を切り替え、QR読取・コード入力・一覧選択で対象ロットを開けます。減少時は出庫先と当日/翌日を必ず選択します。'}</div><div class="mini" style="margin-top:8px">${print}</div></div>${selector}<div class="card">${contents||'<div class="small">対象はありません。</div>'}</div>${editable?`<div class="card"><div class="grid"><button class="btn blue" ${seikaEventAttrs('click','v177SaveSection',[id,section,'draft',selected])}>下書き保存</button><button class="btn green" data-v177-submit="1" ${seikaEventAttrs('click','v177SaveSection',[id,section,'submit',selected])}>${section==='normal'?'通常在庫を完了':'QR在庫を完了'}</button></div></div>`:''}`);
 v171AfterRender();
}
function v177SetQrItem(id,item){v177QrItemState.set(id,String(item||''));v177SectionPage(id,'qr','',''+item)}
async function v177SaveSection(id,section,action,item=''){
 const s=countSession(id);if(!s||!v177Session(s)||!v177Allowed())return alert('棚卸しを操作できるのは管理者・青果社員のみです。');v177PersistDom(id,section);const missing=v177Missing(s,section);if(action==='submit'&&missing.length)return alert(`未入力または必須項目不足が${missing.length}件あります。入力するか下書き保存してください。`);
 const operationId=qrInventoryUuid();v161ShowProcessing(`${section==='normal'?'通常在庫':'QR在庫'}を保存しています`);
 try{const answer=await callRpc(V177_SAVE_RPC,{p_id:STATE_ID,p_session_id:id,p_section:section,p_expected_section_revision:v177SectionRevision(s,section),p_entries:v177Entries(s,section),p_action:action,p_operation_id:operationId});if(answer?.conflict)throw new Error(answer.message||'別端末で更新されています。');if(!answer?.ok)throw new Error(answer?.message||'保存できませんでした。');v124ClearDraft(id,section);await loadCloud();return v177SectionPage(id,section,action==='submit'?`${section==='normal'?'通常在庫':'QR在庫'}を完了にしました。両方完了後に在庫へ反映します。`:'下書き保存しました。',item)}catch(error){alert(`${section==='normal'?'通常在庫':'QR在庫'}を保存できませんでした。\n${v161ErrorText(error)}\n\n入力内容はこの端末に保持しています。`);return v177SectionPage(id,section,'',item)}finally{v161HideProcessing()}
}
async function v177Finalize(id){
 let s=countSession(id);if(!s||!v177Session(s)||!v177Allowed())return alert('棚卸しを操作できるのは管理者・青果社員のみです。');if(v177Completed(s))return inventoryCountHome('この棚卸しはすでに在庫へ反映済みです。');if(!v177SectionDone(s,'normal')||!v177SectionDone(s,'qr'))return alert('通常在庫とQR在庫の両方を完了してください。');if(!confirm(`${s.roomLabel}の棚卸し結果を通常在庫・QR在庫へ反映します。\n\nQRの減少分は選択済みの出庫先・出庫区分で出庫履歴に記録されます。開始後にQR操作があったロットは競合として停止します。\n\n反映しますか？`))return;
 v161ShowProcessing('棚卸し結果を安全に反映しています');try{const answer=await callRpc(V177_FINALIZE_RPC,{p_id:STATE_ID,p_session_id:id,p_expected_session_revision:Number(s.revision)||0,p_operation_id:qrInventoryUuid(),p_device_meta:{deviceId:deviceId(),userAgent:navigator.userAgent||''},p_operation_meta:operationMeta('inventory_count_v177',{sessionId:id,countNo:s.countNo})});if(answer?.conflict)throw new Error(answer.message||'棚卸し開始後に在庫が変わったため反映を中断しました。');if(!answer?.ok)throw new Error(answer?.message||'在庫へ反映できませんでした。');await loadCloud();inventoryCountHome('通常在庫・QR在庫へ反映しました。Excelを出力できます。')}catch(error){alert(`棚卸しの在庫反映を中断しました。\n${v161ErrorText(error)}\n\n再入力や再保存は不要です。競合内容を確認してから再実行してください。`)}finally{v161HideProcessing()}
}
async function v177Start(room){
 if(!v177Allowed())return alert('棚卸しを操作できるのは管理者・青果社員のみです。');if(!validColdRoom(room))return alert('冷蔵庫を選択してください。');await loadCloud();const active=countSessions().find(s=>s?.room===room&&v177Session(s)&&!v177Completed(s)&&!['cancelled','reversed'].includes(String(s.status||'')));if(active){if(confirm(`${roomLabel(room)}の進行中棚卸しを開きますか？`))return v177SectionPage(active.id,'normal');return}
 v161ShowProcessing('棚卸し開始時点の最新在庫を固定しています');try{const [qrLines]=await Promise.all([v177QrSnapshot(room)]),lines=v177NormalLines(room),at=nowIso(),session={id:qrInventoryUuid(),inventoryCountMode:V177_COUNT_MODE,countNo:countNumber(room),room,roomLabel:roomLabel(room),status:'counting',startedAt:at,startedBy:db.user,startedById:db.userId,updatedAt:at,updatedBy:db.user,revision:1,normalStatus:'counting',qrCountStatus:'counting',normalSectionRevision:0,qrSectionRevision:0,lines,qrLines,inventoryApplied:false,qrApplied:false,v177SnapshotRule:'開始時点の最新在庫あり',v177QrSnapshotAt:at};const answer=await callRpc(V177_CREATE_RPC,{p_id:STATE_ID,p_session:session,p_operation_id:qrInventoryUuid()});if(answer?.conflict)throw new Error(answer.message||'別端末で更新されています。');if(!answer?.ok)throw new Error(answer?.message||'棚卸しを開始できませんでした。');await loadCloud();v177SectionPage(session.id,'normal','棚卸し開始時点で在庫がある通常品目とQRロットを固定しました。')}catch(error){alert(`棚卸しを開始できませんでした。\n${v161ErrorText(error)}`)}finally{v161HideProcessing()}
}
async function v177CameraPage(id,item){
 const s=countSession(id);if(!s||!v177Session(s)||!v177Allowed())return inventoryCountHome();await v177StopCamera();setScreen('v177CameraPage',[id,item]);pageShell('QR読取','棚卸しQRロットを選択',`<div class="card"><div id="v177Reader" style="width:100%;min-height:280px"></div><div id="v177CameraMsg" class="small" style="margin-top:10px">カメラの許可を求められたら許可してください。</div><button class="btn btn2" style="width:100%;margin-top:12px" ${seikaEventAttrs('click','v177StopCameraAndReturn',[id,item])}>戻る</button></div>`);setTimeout(()=>v177StartCamera(id,item),200)
}
async function v177StopCamera(){const reader=v177CameraReader;v177CameraReader=null;v177CameraGeneration++;if(reader)try{await reader.stop()}catch(error){}try{await reader.clear()}catch(error){}}
async function v177StopCameraAndReturn(id,item){await v177StopCamera();v177SectionPage(id,'qr','',item)}
function v177StartCamera(id,item){if(typeof Html5Qrcode==='undefined'){document.getElementById('v177CameraMsg').textContent='カメラ読取を開始できません。コード入力・一覧選択を使用してください。';return}const generation=++v177CameraGeneration,reader=new Html5Qrcode('v177Reader');v177CameraReader=reader;reader.start({facingMode:'environment'},{fps:8,qrbox:{width:250,height:250}},async raw=>{if(reader!==v177CameraReader||generation!==v177CameraGeneration||v177CameraBusy)return;v177CameraBusy=true;try{await v177SelectQrKey(id,item,raw)}catch(error){const box=document.getElementById('v177CameraMsg');if(box)box.textContent=error.message||String(error)}finally{v177CameraBusy=false}},()=>{}).catch(error=>{if(reader===v177CameraReader)v177CameraReader=null;const box=document.getElementById('v177CameraMsg');if(box)box.textContent=`カメラを開始できませんでした。${error.message||error}`})}
async function v177SelectQrKey(id,item,raw){const key=qrExtractKey(raw),s=countSession(id),line=v177Rows(s,'qr').find(row=>String(row.qrKey)===String(key)||String(row.lotNo)===String(key));if(!line)throw new Error('この棚卸し開始時の対象QRロットではありません。');await v177StopCamera();v177QrItemState.set(id,String(line.itemName||''));return v177SectionPage(id,'qr',`${line.itemName||'QRロット'}を選択しました。実数を入力してください。`,String(line.itemName||''))}
function v177ManualQrPage(id,item){const s=countSession(id);if(!s||!v177Session(s)||!v177Allowed())return inventoryCountHome();const selected=item||v177QrItemState.get(id)||v177QrItems(s)[0]||'',rows=v177Rows(s,'qr').filter(line=>String(line.itemName||'')===selected);setScreen('v177ManualQrPage',[id,selected]);pageShell('QRコード入力・一覧選択',`${esc(selected)} / 棚卸し開始時の対象のみ`, `<div class="card"><label class="label">QRキーまたはロット番号</label><input id="v177ManualKey" class="input" placeholder="QRを貼付またはロット番号を入力"><button class="btn blue" style="width:100%;margin-top:10px" ${seikaEventAttrs('click','v177ManualSelect',[id,selected])}>このQRを選択</button></div><div class="card"><b>${esc(selected)} のロット一覧</b>${rows.map(line=>`<div class="memo"><b>${esc(line.lotNo||line.qrKey)}</b><div class="small">開始時 ${fmt(line.systemQty)} ${esc(line.unit||'')} / ${esc(line.containerType||'')}</div><button class="btn btn2" style="margin-top:6px" ${seikaEventAttrs('click','v177SelectQrKey',[id,selected,line.qrKey])}>このロットを入力</button></div>`).join('')||'<div class="small">対象ロットはありません。</div>'}</div><button class="btn btn2" style="width:100%" ${seikaEventAttrs('click','v177SectionPage',[id,'qr','',selected])}>QR入力へ戻る</button>`)}
function v177ManualSelect(id,item){const key=document.getElementById('v177ManualKey')?.value||'';if(!String(key).trim())return alert('QRキーまたはロット番号を入力してください。');return v177SelectQrKey(id,item,key)}
function v177PrintHtml(title,meta,heads,rows){const scale=Math.max(.3,Math.min(1,16/Math.max(1,rows.length))).toFixed(3);return `<!doctype html><html lang="ja"><head><meta charset="utf-8"><title>${esc(title)}</title><style>@page{size:A4 landscape;margin:2mm 3mm}*{box-sizing:border-box}html,body{margin:0;background:#fff;color:#111;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif}.page{width:291mm;height:206mm;overflow:hidden;break-after:page}.page:last-child{break-after:auto}.content{width:calc(100% / var(--fit));transform:scale(var(--fit));transform-origin:top left}h1{margin:0 0 2mm;font-size:14pt}.meta{margin-bottom:2mm;font-size:8pt}table{width:100%;border-collapse:collapse;table-layout:fixed}th,td{border:.22mm solid #111;padding:1.1mm;font-size:9pt;vertical-align:middle;overflow-wrap:anywhere;word-break:break-word}th{background:#d9eaf7;text-align:center}.write{height:8mm}@media print{thead{display:table-header-group}tr{break-inside:avoid;page-break-inside:avoid}}</style></head><body><section class="page" style="--fit:${scale}"><div class="content"><h1>${esc(title)}</h1><div class="meta">${esc(meta)}　印刷：${esc(dt(nowIso()))}</div><table><thead><tr>${heads.map(head=>`<th>${esc(head)}</th>`).join('')}</tr></thead><tbody>${rows.join('')}</tbody></table></div></section></body></html>`}
function v177OpenPrint(html){const win=window.open('','_blank');if(!win)return alert('印刷画面を開けませんでした。ポップアップ許可を確認してください。');win.document.open();win.document.write(html);win.document.close();win.focus()}
function v177PrintNormal(id){const s=countSession(id);if(!s||!v177Session(s))return;const rows=v177Rows(s,'normal').map(line=>`<tr><td>${esc(line.group||'')}</td><td>${esc(line.itemName||'')}</td><td>${esc(line.unit||'')}</td><td class="write"></td><td class="write"></td><td class="write"></td></tr>`);v177OpenPrint(v177PrintHtml(`${s.roomLabel} 通常在庫 棚卸し記入票`,`${s.countNo} / 開始時点で在庫ありの品目`,['区分','品名','単位','実数','仕入先','備考'],rows))}
function v177PrintQrPages(id){const s=countSession(id);if(!s||!v177Session(s))return;const pages=v177QrItems(s).map(item=>{const rows=v177Rows(s,'qr').filter(line=>String(line.itemName||'')===item).map(line=>`<tr><td>${esc(line.lotNo||line.qrKey||'')}</td><td>${esc(line.containerType||'')}</td><td>${esc(line.unit||'')}</td><td>${fmt(line.systemQty)} ${esc(line.unit||'')}</td><td class="write"></td><td class="write"></td></tr>`);return v177PrintHtml(`${s.roomLabel} QR在庫 ${item} 棚卸し記入票`,`${s.countNo} / 品目別1ページ / 開始時点で在庫ありのロット`,['ロット','荷姿','単位','開始時帳簿','実数','備考'],rows).match(/<body>([\s\S]*)<\/body>/)?.[1]||''}).join('');const html=`<!doctype html><html lang="ja"><head><meta charset="utf-8"><title>${esc(s.roomLabel)} QR在庫 棚卸し記入票</title><style>@page{size:A4 landscape;margin:2mm 3mm}*{box-sizing:border-box}html,body{margin:0;background:#fff;color:#111;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif}.page{width:291mm;height:206mm;overflow:hidden;break-after:page}.page:last-child{break-after:auto}.content{width:calc(100% / var(--fit));transform:scale(var(--fit));transform-origin:top left}h1{margin:0 0 2mm;font-size:14pt}.meta{margin-bottom:2mm;font-size:8pt}table{width:100%;border-collapse:collapse;table-layout:fixed}th,td{border:.22mm solid #111;padding:1.1mm;font-size:9pt;vertical-align:middle;overflow-wrap:anywhere;word-break:break-word}th{background:#d9eaf7;text-align:center}.write{height:8mm}@media print{thead{display:table-header-group}tr{break-inside:avoid;page-break-inside:avoid}}</style></head><body>${pages}</body></html>`;v177OpenPrint(html)}
function v177ExcelDetailRows(s,section){const entries=v177EntryMap(s,section);return v177Rows(s,section).map(line=>{const entry=entries.get(v177LineId(line,section))||{},actual=section==='normal'?(v119IsKgLine(line)?v124WeightTotal(entry.weightEntries,entry.remainderKg):v119StrictDecimal(entry.actualQty)):v119StrictDecimal(entry.actualQty),weight=section==='normal'?(v119IsKgLine(line)?actual:(actual!==null&&v119StrictDecimal(entry.kgPerUnit)!==null?actual*v119StrictDecimal(entry.kgPerUnit):'')):((qrIsLargeContainer(line.containerType)&&qrCountLargePerWeight(line)!==null&&actual!==null)?actual*qrCountLargePerWeight(line):(line.actualWeightKg??''));return {group:line.group||'',item:line.itemName||'',lot:section==='qr'?(line.lotNo||line.qrKey||''):'',supplier:entry.supplier??line.supplier??'',spec:section==='qr'?(line.containerType||''):(line.unit||''),qty:actual??'',unit:line.unit||'',weight:weight??'',memo:entry.memo??'',destination:entry.destination??'',timing:entry.shipTiming??''}})}
function v177AddDetailSheet(wb,name,title,s,section){const heads=['区分','品名','ロット','仕入先','荷姿・規格','数量','単位','重量kg','出庫先','出庫区分','単価（円/単位）','金額（円）','備考'],rows=v177ExcelDetailRows(s,section),meta=[['棚卸し番号',s.countNo],['冷蔵庫',s.roomLabel],['在庫反映',s.v177AppliedAt||s.v177CompletedAt?'反映済み':'未反映'],['単価・金額','単価を入力すると金額と合計が計算されます']];const values=rows.map(row=>[row.group,row.item,row.lot,row.supplier,row.spec,row.qty,row.unit,row.weight,row.destination,row.timing,'','',row.memo].map(value=>typeof value==='string'?inventoryCountExcelSafeText(value):value));const ws=XLSX.utils.aoa_to_sheet([[title],[],...meta,[],heads,...values]);const header=meta.length+3,start=header+2,end=header+rows.length+1;for(let r=start;r<=end;r++){ws[`L${r}`]={t:'n',f:`IF(OR(F${r}="",K${r}=""),"",F${r}*K${r})`};}ws[`K${end+1}`]={t:'s',v:'明細合計'};ws[`L${end+1}`]={t:'n',f:`SUM(L${start}:L${end})`};ws['!ref']=XLSX.utils.encode_range({s:{r:0,c:0},e:{r:end,c:heads.length-1}});ws['!merges']=[{s:{r:0,c:0},e:{r:0,c:heads.length-1}}];ws['!autofilter']={ref:XLSX.utils.encode_range({s:{r:header,c:0},e:{r:Math.max(header,end-1),c:heads.length-1}})};ws['!cols']=[12,22,18,18,16,11,9,12,14,14,15,15,30].map(wch=>({wch}));inventoryCountExcelStyle(ws,'A1',{font:{name:'Yu Gothic',sz:15,bold:true,color:{rgb:'FFFFFF'}},fill:{patternType:'solid',fgColor:{rgb:'1D4ED8'}},alignment:{horizontal:'center'}});for(let c=0;c<heads.length;c++)inventoryCountExcelStyle(ws,XLSX.utils.encode_cell({r:header,c}),{font:{name:'Yu Gothic',sz:10,bold:true},fill:{patternType:'solid',fgColor:{rgb:'D9EAF7'}},alignment:{horizontal:'center',vertical:'center',wrapText:true}});for(let r=start;r<=end+1;r++)for(let c=0;c<heads.length;c++)inventoryCountExcelStyle(ws,XLSX.utils.encode_cell({r,c}),{font:{name:'Yu Gothic',sz:10},alignment:{vertical:'center',wrapText:true}});XLSX.utils.book_append_sheet(wb,ws,safeSheetName(name));return {name,rows,start,end}}
function v177AddSummarySheet(wb,s,normal,qr){const all=[...v177ExcelDetailRows(s,'normal').map(row=>({...row,source:normal.name})),...v177ExcelDetailRows(s,'qr').map(row=>({...row,source:qr.name}))],keys=[...new Map(all.map(row=>[`${row.group}|${row.item}|${row.unit}`,row])).values()],heads=['区分','品名','単位','合計数量','合計重量kg','合計金額（円）'],ws=XLSX.utils.aoa_to_sheet([[`${s.roomLabel} 棚卸し 品目集計`],[],['棚卸し番号',s.countNo],['冷蔵庫',s.roomLabel],['注記','明細シートの単価入力に連動します'],[],heads,...keys.map(row=>[row.group,row.item,row.unit,'','',''])]);const header=7,start=8,end=7+keys.length;for(let r=start;r<=end;r++){const group=`A${r}`,item=`B${r}`,unit=`C${r}`,n=normal.name.replace(/'/g,"''"),q=qr.name.replace(/'/g,"''");ws[`D${r}`]={t:'n',f:`SUMIFS('${n}'!$F$${normal.start}:$F$${normal.end},'${n}'!$A$${normal.start}:$A$${normal.end},${group},'${n}'!$B$${normal.start}:$B$${normal.end},${item},'${n}'!$G$${normal.start}:$G$${normal.end},${unit})+SUMIFS('${q}'!$F$${qr.start}:$F$${qr.end},'${q}'!$A$${qr.start}:$A$${qr.end},${group},'${q}'!$B$${qr.start}:$B$${qr.end},${item},'${q}'!$G$${qr.start}:$G$${qr.end},${unit})`};ws[`E${r}`]={t:'n',f:`SUMIFS('${n}'!$H$${normal.start}:$H$${normal.end},'${n}'!$A$${normal.start}:$A$${normal.end},${group},'${n}'!$B$${normal.start}:$B$${normal.end},${item},'${n}'!$G$${normal.start}:$G$${normal.end},${unit})+SUMIFS('${q}'!$H$${qr.start}:$H$${qr.end},'${q}'!$A$${qr.start}:$A$${qr.end},${group},'${q}'!$B$${qr.start}:$B$${qr.end},${item},'${q}'!$G$${qr.start}:$G$${qr.end},${unit})`};ws[`F${r}`]={t:'n',f:`SUMIFS('${n}'!$L$${normal.start}:$L$${normal.end},'${n}'!$A$${normal.start}:$A$${normal.end},${group},'${n}'!$B$${normal.start}:$B$${normal.end},${item},'${n}'!$G$${normal.start}:$G$${normal.end},${unit})+SUMIFS('${q}'!$L$${qr.start}:$L$${qr.end},'${q}'!$A$${qr.start}:$A$${qr.end},${group},'${q}'!$B$${qr.start}:$B$${qr.end},${item},'${q}'!$G$${qr.start}:$G$${qr.end},${unit})`}}ws[`E${end+1}`]={t:'s',v:'全合計金額'};ws[`F${end+1}`]={t:'n',f:`SUM(F${start}:F${end})`};ws['!ref']=XLSX.utils.encode_range({s:{r:0,c:0},e:{r:end,c:heads.length-1}});ws['!merges']=[{s:{r:0,c:0},e:{r:0,c:heads.length-1}}];ws['!autofilter']={ref:`A${header}:F${Math.max(header,end)}`};ws['!cols']=[14,24,10,15,15,16].map(wch=>({wch}));inventoryCountExcelStyle(ws,'A1',{font:{name:'Yu Gothic',sz:15,bold:true,color:{rgb:'FFFFFF'}},fill:{patternType:'solid',fgColor:{rgb:'1D4ED8'}},alignment:{horizontal:'center'}});for(let c=0;c<heads.length;c++)inventoryCountExcelStyle(ws,XLSX.utils.encode_cell({r:header-1,c}),{font:{name:'Yu Gothic',sz:10,bold:true},fill:{patternType:'solid',fgColor:{rgb:'D9EAF7'}},alignment:{horizontal:'center'}});XLSX.utils.book_append_sheet(wb,ws,safeSheetName(`${s.roomLabel} 品目集計`))}
function v177DownloadExcel(id){const s=countSession(id);if(!s||!v177Session(s))return v171DownloadExcel(id);if(!v177Completed(s))return alert('Excelは通常在庫・QR在庫を完了し、在庫反映後に出力できます。');if(!ensureXlsxReady())return;const wb=XLSX.utils.book_new(),normal=v177AddDetailSheet(wb,`${s.roomLabel} 通常在庫`,`${s.roomLabel} 通常在庫 棚卸し結果`,s,'normal'),qr=v177AddDetailSheet(wb,`${s.roomLabel} QR在庫`,`${s.roomLabel} QR在庫 棚卸し結果`,s,'qr');v177AddSummarySheet(wb,s,normal,qr);downloadWorkbookXlsx(wb,`棚卸し結果_在庫反映済み_${String(s.roomLabel||'冷蔵庫').replace(/[\\/:*?"<>|]/g,'_')}_${String(s.countNo||'棚卸し').replace(/[\\/:*?"<>|]/g,'_')}.xlsx`);inventoryCountHome('単価入力で金額・品目集計・総額が連動するExcelを出力しました。')}
function v177Home(msg=''){setScreen('inventoryCountHome',[msg]);if(!v177Allowed())return home();const sessions=countSessions().slice().sort((a,b)=>new Date(b.updatedAt||0)-new Date(a.updatedAt||0)),active=sessions.filter(v177Session).filter(s=>!v177Completed(s)),history=sessions.filter(s=>!active.includes(s));const card=s=>{if(!v177Session(s))return `<div class="card"><b>${esc(s.countNo||'')}</b><div class="small">${esc(s.roomLabel||'')} / 旧仕様（閲覧・旧Excelのみ）</div><button class="btn btn2" style="margin-top:8px" ${seikaEventAttrs('click','v171ReadOnlyView',[s.id])}>結果を閲覧</button><button class="btn orange" style="margin-top:8px" ${seikaEventAttrs('click','v171DownloadExcel',[s.id])}>旧Excelを出力</button></div>`;const normal=v177SectionDone(s,'normal'),qr=v177SectionDone(s,'qr'),applied=v177Completed(s);return `<div class="card"><div class="itemHead"><div><b>${esc(s.countNo||'')}</b><div class="small">${esc(s.roomLabel||'')} / 開始：${esc(s.startedAt?dt(s.startedAt):'－')}</div></div><span class="badge ${applied?'normal':normal&&qr?'excess':'unset'}">${applied?'反映済み':normal&&qr?'反映待ち':'入力中'}</span></div>${!applied?`<div class="mini" style="margin-top:9px"><button class="btn green" ${seikaEventAttrs('click','v177SectionPage',[s.id,'normal'])}>通常在庫 ${normal?'完了・確認':'入力'}</button><button class="btn blue" ${seikaEventAttrs('click','v177SectionPage',[s.id,'qr'])}>QR在庫 ${qr?'完了・確認':'入力'}</button>${normal&&qr?`<button class="btn orange" ${seikaEventAttrs('click','v177Finalize',[s.id])}>在庫へ反映</button>`:''}</div>`:`<div class="mini" style="margin-top:9px"><button class="btn orange" ${seikaEventAttrs('click','v177DownloadExcel',[s.id])}>Excelを出力</button><button class="btn btn2" ${seikaEventAttrs('click','v177PrintNormal',[s.id])}>通常記入票</button><button class="btn btn2" ${seikaEventAttrs('click','v177PrintQrPages',[s.id])}>QR品目別記入票</button></div>`}</div>`};pageShell('棚卸しモード',`${esc(v119RoleLabel())} / v1.185`,`${okHtml(msg)}<div class="card notice"><b>棚卸しの流れ</b><div class="small">①冷蔵庫を選択して開始時点で在庫がある通常品目・QRロットの記入票を印刷 → ②通常在庫・QR在庫を別々に完了 → ③両方完了後に在庫へ安全に反映 → ④Excelを出力</div></div><div class="card"><b>棚卸しを開始（管理者・青果社員）</b><div class="grid" style="margin-top:9px"><button class="btn orange" ${seikaEventAttrs('click','v177Start',['room2'])}>第2冷蔵庫を開始</button><button class="btn orange" ${seikaEventAttrs('click','v177Start',['room3'])}>第3冷蔵庫を開始</button></div></div><div class="card"><b>進行中・反映待ち</b>${active.map(card).join('')||'<div class="small">進行中の棚卸しはありません。</div>'}</div><div class="card"><b>反映済み・旧履歴</b>${history.map(card).join('')||'<div class="small">履歴はまだありません。</div>'}</div>`)}
async function refreshData(){if(v177ReloadRunning)return;const pending=v161PendingCount();if(pending){v161ShowProcessing('未同期データを再送しています');try{await retryPendingSync();if(v161PendingCount())throw new Error('未同期データが残っています。')}catch(error){alert(`未同期データを保護するため再読込を中断しました。\n${v161ErrorText(error)}`);return}finally{v161HideProcessing()}}v177ReloadRunning=true;v161ShowProcessing('クラウドの最新データを読み込んでいます');try{await loadCloud();await renderCurrent();setSyncState('保存済み',`再読込 ${new Date().toLocaleTimeString('ja-JP',{hour:'2-digit',minute:'2-digit',second:'2-digit'})}`);updateSyncDisplay();return true}catch(error){setSyncState('失敗');updateSyncDisplay();alert(`再読込できませんでした。\n${v161ErrorText(error)}`);return false}finally{v177ReloadRunning=false;v161HideProcessing()}}
startInventoryCount=v177Start;inventoryCountHome=v177Home;inventoryCountPage=(id,msg='')=>{const s=countSession(id);return v177Session(s)?v177SectionPage(id,'normal',msg):v171SectionPage(id,'normal',msg)};downloadInventoryCountExcel=v177DownloadExcel;window.APP_VERSION='v1.179';document.title='SEIKA＋ v1.193 週次廃棄レポート版';
function v177Guide(){setScreen('inventoryCountGuidePage');if(!v177Allowed())return home();pageShell('棚卸しモードの使い方','管理者・青果社員のみ / v1.185',`<div class="card notice"><b>1. 記入票を印刷</b><div class="small">冷蔵庫を選んで開始すると、棚卸し開始時点で在庫がある通常品目とQRロットを固定します。通常在庫は冷蔵庫別、QR在庫は品目別1ページで印刷できます。</div></div><div class="card"><b>2. 通常在庫・QR在庫を別々に完了</b><div class="small">通常在庫は量目kg×ケース数と端数、任意の仕入先・備考を入力します。QR在庫は品目切替、QR読取・コード入力・一覧選択で入力し、開始時より減った場合は出庫先と当日発注分／翌日発注分を必ず選択します。</div></div><div class="card"><b>3. 在庫へ反映・Excel出力</b><div class="small">通常在庫とQR在庫の両方を完了すると「在庫へ反映」が表示されます。反映済み後に、冷蔵庫別の通常在庫・QR在庫・品目集計を含むExcelを出力できます。</div></div><div class="card"><b>安全な再読込</b><div class="small">未同期データがある場合は先に再送します。再送できないときは、端末内の未同期データを残したまま再読込を中断します。</div></div>`)}
inventoryCountGuidePage=v177Guide;
for(const role of ['admin','worker']){const guide=V195_ROLE_GUIDES?.[role],index=guide?.sections?.findIndex(section=>String(section.title||'').includes('棚卸し'));if(index>=0)guide.sections[index]={title:'棚卸しモード',where:'ホーム → 棚卸しモード',steps:['冷蔵庫を選択して、開始時点で在庫がある記入票を印刷します。','通常在庫とQR在庫を別々に入力し、各完了ボタンで保存します。','両方完了後に在庫へ反映します。','反映済み後に単価入力対応のExcelを出力します。'],check:'QR減少時は出庫先と当日発注分／翌日発注分を確認します。',caution:'棚卸し開始後に同じQRロットが通常操作されていた場合は、反映を中断して確認します。'} }



/* ===== v1.179: A4 inventory fit, outbound kg, all active registered users ===== */
window.APP_VERSION='v1.179';
document.title='SEIKA＋ v1.179 印刷・QR重量・担当者修正版';
/* One fitting pass only: choose readable row/font bounds first, then measure the exact
   print DOM once and shrink only if the A4 printable rectangle requires it. */
function v1178PrintFitScale(probeHtml){
  const old=document.getElementById('seikaPrintProbe');if(old)old.remove();
  const host=document.createElement('div');host.innerHTML=probeHtml;const probe=host.firstElementChild;
  document.body.appendChild(probe);const r=probe.getBoundingClientRect();
  const mmPx=96/25.4,usableW=291*mmPx,usableH=206*mmPx;
  const scale=Math.min(1,usableW/Math.max(r.width,1),usableH/Math.max(r.height,1));probe.remove();
  return Math.max(.20,scale);
}
function v1178PrintPageHtml(title,days,body,rowCount,vars,forMeasure=false){
  const header=`<div class="printHead"><h1>${esc(title)}</h1><div class="meta">${days[0].toLocaleDateString('ja-JP')}〜${days[6].toLocaleDateString('ja-JP')}　${rowCount}行</div></div>`;
  const table=`<table><thead><tr><th class="name">品名</th><th class="spec">規格</th><th class="origin">産地</th>${days.map(d=>`<th class="day">${d.toLocaleDateString('ja-JP',{month:'numeric',day:'numeric'})}<br>${'日月火水木金土'[d.getDay()]}</th>`).join('')}</tr></thead><tbody>${body}</tbody></table>`;
  const css=`@page{size:A4 landscape;margin:2mm 3mm}*{box-sizing:border-box}html,body{margin:0;padding:0;background:#fff;color:#111;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif}.page{width:291mm;height:206mm;overflow:hidden;background:#fff}.pageContent{width:calc(100% / var(--fit-scale));transform:scale(var(--fit-scale));transform-origin:top left}.printHead{height:7mm;display:flex;justify-content:space-between;align-items:flex-end;gap:3mm;overflow:hidden}h1{font-size:11pt;line-height:1;margin:0;font-weight:900;white-space:nowrap}.meta{font-size:6.2pt;line-height:1;text-align:right;white-space:nowrap}table{width:100%;border-collapse:collapse;table-layout:fixed}th,td{border:.2mm solid #111;padding:var(--print-pad-y) .48mm;height:var(--data-row-mm);max-width:0;font-size:var(--print-font-pt);line-height:var(--print-line-height);vertical-align:middle;overflow:hidden;overflow-wrap:anywhere;word-break:break-all}th{height:5mm;background:#eaf3fb;font-weight:900;text-align:center}.name{width:22%;font-weight:700;font-size:calc(var(--print-font-pt)*1.03);white-space:normal;overflow-wrap:anywhere;word-break:break-word}.spec{width:7%;font-size:calc(var(--print-font-pt)*.9)}.origin{width:6%;font-size:calc(var(--print-font-pt)*.9)}.day{width:9.285714%;text-align:center;white-space:nowrap}.section td{height:var(--section-row-mm);background:#dfe7ef;font-size:calc(var(--print-font-pt)*.94);font-weight:900;text-align:left;padding:0 .55mm}@media print{html,body{width:291mm;height:206mm}.page{break-inside:avoid;page-break-inside:avoid;page-break-after:avoid}tr{break-inside:avoid;page-break-inside:avoid}}`;
  if(forMeasure)return `<div id="seikaPrintProbe" style="position:fixed;left:-100000px;top:0;width:291mm;visibility:hidden;pointer-events:none"><style>${css}</style><div class="page" style="height:auto;overflow:visible"><div class="pageContent" style="${vars};--fit-scale:1">${header}${table}</div></div></div>`;
  return `<!doctype html><html lang="ja"><head><meta charset="utf-8"><title>${esc(title)}</title><style>${css}</style></head><body><div class="page" style="${vars}"><div class="pageContent">${header}${table}</div></div></body></html>`;
}
window.printInventorySheet=async function(group){
  const title=group==='room3'?'第3冷蔵庫 在庫表':'第2冷蔵庫＋片岡在庫 在庫表',start=printWeekStartDate();
  const days=[...Array(7)].map((_,i)=>{const d=new Date(start);d.setDate(start.getDate()+i);return d}),dayKeys=days.map(ymdKey),rows=printInventoryRows(group,dayKeys),rowCount=rows.length;
  const sectionCount=new Set(rows.map(r=>r.group)).size;
  const visualRows=Math.max(rowCount,rows.reduce((n,r)=>n+Math.max(printInventoryTextUnits(r.name,25),printInventoryTextUnits(r.spec,10),printInventoryTextUnits(r.origin,9)),0))+sectionCount*.6;
  const usableDataMm=194-7-5, rowMm=Math.max(2.0,usableDataMm/Math.max(visualRows,1)),fontPt=Math.min(14,Math.max(5.2,rowMm*.45));
  const vars=`--data-row-mm:${rowMm.toFixed(3)}mm;--section-row-mm:${Math.max(1.5,rowMm*.60).toFixed(3)}mm;--print-font-pt:${fontPt.toFixed(2)}pt;--print-pad-y:${Math.min(.65,Math.max(.05,rowMm*.07)).toFixed(3)}mm;--print-line-height:1.05;`;
  const body=rows.map((r,i,a)=>`${i===0||r.group!==a[i-1].group?`<tr class="section"><td colspan="10">${esc(r.group)}</td></tr>`:''}<tr class="data"><td class="name">${esc(r.name)}</td><td class="spec">${esc(r.spec||'')}</td><td class="origin">${esc(r.origin||'')}</td>${days.map(d=>`<td class="day">${printDayValue(r,ymdKey(d))}</td>`).join('')}</tr>`).join('');
  const scale=v1178PrintFitScale(v1178PrintPageHtml(title,days,body,rowCount,vars,true));
  const html=v1178PrintPageHtml(title,days,body,rowCount,`${vars}--fit-scale:${scale.toFixed(6)};`,false);
  const w=window.open('','_blank');if(!w){alert('印刷画面を開けませんでした。ポップアップ許可を確認してください。');return}w.document.open();w.document.write(html);w.document.close();
};
function v1178OutboundKg(r){
  const direct=Number(r?.weight);if(r?.weight!==null&&r?.weight!==undefined&&r?.weight!==''&&Number.isFinite(direct))return direct;
  if(qrIsLargeContainer(r?.container_type))return null;
  const qty=Number(r?.qty);if(!Number.isFinite(qty))return null;
  if(qrStockIsKgUnit(r?.unit))return qty;
  const pack=qrStockPackWeightNumber(r?.pack_weight);return pack>0?pack*qty:null;
}
window.v1144OutboundSummary=function(rows,total,summaryRows=null){const groups=new Map;if(Array.isArray(summaryRows)&&summaryRows.length){for(const r of summaryRows){const kg=Number(r.weight_kg),normalMissing=Number(r.unconvertible_normal_count||0),largeMissing=Number(r.unconfirmed_large_count||0);groups.set(`${r.item_name||'-'}\u0000${r.unit||''}`,{item:r.item_name||'-',unit:r.unit||'',qty:Number(r.qty||0),weight:Number.isFinite(kg)?kg:0,largeMissing,normalMissing,count:null});}}else for(const r of rows||[]){const k=`${r.item_name||'-'}\u0000${r.unit||''}`,x=groups.get(k)||{item:r.item_name||'-',unit:r.unit||'',qty:0,weight:0,largeMissing:0,normalMissing:0,count:0};x.qty+=Number(r.qty||0);const kg=v1178OutboundKg(r);if(kg===null){if(qrIsLargeContainer(r?.container_type))x.largeMissing++;else x.normalMissing++;}else x.weight+=kg;x.count++;groups.set(k,x)}return `<div class="card"><b>日次集計</b><div class="small">明細 ${Number(total||rows.length).toLocaleString()}件${Array.isArray(summaryRows)?'（全件集計）':`（表示 ${rows.length.toLocaleString()}件）`}</div><div style="display:grid;gap:7px;margin-top:9px">${[...groups.values()].map(x=>`<div class="box"><b>${esc(x.item)}</b><span>${fmt(x.qty)} ${esc(x.unit)} / ${fmt(x.weight)}kg${x.largeMissing?`（大型容器 ${x.largeMissing}件：重量未確定）`:''}${x.normalMissing?`（通常容器 ${x.normalMissing}件：量目未設定）`:''}${x.count!==null?` / ${x.count}件`:''}</span></div>`).join('')}</div></div>`};
/* Registered active users are selectable regardless of role. Existing item assignment remains the automatic initial value. */
let v1178RegisteredUsers=[];
/* SQL適用後はprofilesの有効利用者一覧を正本にする。取得失敗時だけ既存の端末内候補を使う。 */
window.v1144PurchaseStaffCandidates=function(){const byId=new Map();const add=(id,name,active=true,profileId=null)=>{id=String(id||'').trim();if(!id||active===false)return;const formal=(V188_FULL_NAMES&&V188_FULL_NAMES[id])||String(name||'').trim();if(!formal)return;const prior=byId.get(id);if(!prior||profileId)byId.set(id,{legacy_user_id:id,display_name:formal,profile_id:profileId||prior?.profile_id||null});};for(const u of v1178RegisteredUsers||[])add(u.legacy_user_id,u.display_name,u.active,u.profile_id);for(const u of db?.users||[])add(u.id,u.name,u.active,u.profile_id||u.id_uuid||null);for(const [id,name] of (typeof v188LoginUsers==='function'?v188LoginUsers():[]))add(id,name,true);for(const u of v188AdminUsers||[])add(u.legacy_user_id,u.display_name,u.active,u.id);return [...byId.values()].sort((a,b)=>a.display_name.localeCompare(b.display_name,'ja'));};
async function v1178LoadRegisteredUsers(){try{const ans=await callRpc('list_active_registered_users_v1178',{});const rows=Array.isArray(ans?.users)?ans.users:[];v1178RegisteredUsers=rows.filter(x=>x&&x.active!==false&&x.legacy_user_id&&x.display_name);return rows.length}catch(_){return 0}}
window.v1144PurchaseStaffOptionHtml=function(selectedLegacy='',selectedName=''){const rows=v1144PurchaseStaffCandidates(),selected=v1144CandidateForReference(selectedLegacy,rows)||v1144CandidateForReference(selectedName,rows);return `<option value="">選択してください</option>${rows.map(x=>`<option value="${esc(x.legacy_user_id)}" ${x.legacy_user_id===selected?.legacy_user_id?'selected':''}>${esc(x.display_name)}</option>`).join('')}`;};
window.v1144ReplacePurchaseStaffControl=function(){const old=document.getElementById('qrPurchaseStaff');if(!old)return null;const prior=String(old.value||'').trim();const select=document.createElement('select');select.id='qrPurchaseStaff';select.className=old.className||'input';select.required=true;select.innerHTML=v1144PurchaseStaffOptionHtml('',prior);select.onchange=()=>{select.dataset.manual='1';const n=document.getElementById('qrStaffNote');if(n)n.textContent=select.value?'選択した担当者を入庫ロットと品質評価へ連携します。':'仕入れ担当者を選択してください。';};old.replaceWith(select);return select;};
window.qrAutoFillStaff=function(){const item=document.getElementById('qrItemName'),staff=document.getElementById('qrPurchaseStaff');if(!item||!staff)return;const name=String(item.value||'').trim();if(staff.dataset.itemName===name)return;const auto=typeof v1144AutoPurchaseStaffForItemName==='function'?v1144AutoPurchaseStaffForItemName(name):null;if(auto)staff.value=auto.legacy_user_id;else staff.value='';staff.dataset.itemName=name;staff.dataset.manual='';const n=document.getElementById('qrStaffNote');if(n)n.textContent=auto?'品目担当を自動設定しました。必要な場合のみ変更してください。':'この品目の仕入れ担当者が未設定です。登録ユーザーから選択してください。';const m=document.getElementById('qrManagedNotice');if(m)m.innerHTML=qrManagedNotice(name);};
const v1178CreateCore=window.qrCreatePage;window.qrCreatePage=async function(){const r=await v1178CreateCore();await v1178LoadRegisteredUsers();v1144ReplacePurchaseStaffControl();qrAutoFillStaff();return r;};

/* ===== v1.179: QR仕入れ担当者の正式氏名・canonical ID完全統一 =====
   profiles / db.users / AUTH_LOGIN_USERS / ローカルfallback の全ソースを同じ規則で正規化する。
   profiles の既存表示名は更新しない。候補・保存値だけを正式氏名に統一する。 */
const V1179_STAFF_FORMAL_NAMES=Object.freeze({
  seki_hiroshi:'関 宏世', saito_dai:'斎藤 大明', sakamoto:'坂本 美穂',
  yoshida:'吉田 智彦', araki:'荒木 貴裕'
});
const V1179_STAFF_ID_ALIASES=Object.freeze({
  seki_hiroshi:'seki_hiroshi', seki:'seki_hiroshi',
  saito_dai:'saito_dai', saito:'saito_dai',
  sakamoto:'sakamoto', yoshida:'yoshida', araki:'araki'
});
const V1179_STAFF_NAME_ALIASES=Object.freeze({
  '関(宏)':'seki_hiroshi', '関（宏）':'seki_hiroshi', '関宏世':'seki_hiroshi',
  '斎藤(大)':'saito_dai', '斎藤（大）':'saito_dai', '斎藤大明':'saito_dai',
  '坂本':'sakamoto', '坂本美穂':'sakamoto',
  '吉田':'yoshida', '吉田智彦':'yoshida',
  '荒木':'araki', '荒木貴裕':'araki'
});
function v1179StaffTextKey(value){
  return String(value||'').trim().replace(/[（）]/g,c=>c==='（'?'(':')').replace(/[\s　]/g,'').toLowerCase();
}
function v1179CanonicalStaffId(legacyUserId,displayName=''){
  const rawId=String(legacyUserId||'').trim(),idKey=rawId.toLowerCase();
  if(V1179_STAFF_ID_ALIASES[idKey])return V1179_STAFF_ID_ALIASES[idKey];
  const nameKey=v1179StaffTextKey(displayName||rawId);
  for(const [alias,id] of Object.entries(V1179_STAFF_NAME_ALIASES))if(v1179StaffTextKey(alias)===nameKey)return id;
  return rawId;
}
function v1179FormalStaffName(legacyUserId,displayName=''){
  const canonical=v1179CanonicalStaffId(legacyUserId,displayName);
  return V1179_STAFF_FORMAL_NAMES[canonical]||String(displayName||'').trim();
}
function v1179ReferenceCandidate(reference,candidates=v1144PurchaseStaffCandidates()){
  const raw=String(reference||'').trim();if(!raw)return null;
  /* IDと表示名のどちらで渡っても同じcanonical IDへ解決する。 */
  const canonical=v1179CanonicalStaffId(raw,raw);
  return candidates.find(x=>x.legacy_user_id===canonical)
    ||candidates.find(x=>v1179StaffTextKey(x.display_name)===v1179StaffTextKey(raw))
    ||null;
}
function v1179FormalizePurchaseStaffValue(value){
  const candidate=v1179ReferenceCandidate(value);
  return candidate?.display_name||v1179FormalStaffName('',value);
}
let v1179RegisteredUsers=[],v1179RegisteredUsersLoaded=false;
async function v1179LoadRegisteredUsers(){
  try{const ans=await callRpc('list_active_registered_users_v1179',{});const users=Array.isArray(ans?.users)?ans.users:[];v1179RegisteredUsers=users;v1179RegisteredUsersLoaded=true;return users.length;}
  catch(_){v1179RegisteredUsersLoaded=false;return 0;}
}
/* canonical IDで先に統合するため、同じ人物の旧ID/略称・正式プロフィールは1候補になる。 */
window.v1144PurchaseStaffCandidates=function(){
  const byCanonicalId=new Map();
  const add=(legacyUserId,displayName,active=true,profileId=null)=>{
    if(active===false)return;
    const canonical=v1179CanonicalStaffId(legacyUserId,displayName),name=v1179FormalStaffName(canonical,displayName);
    if(!canonical||!name)return;
    const old=byCanonicalId.get(canonical),isCanonical=String(legacyUserId||'').trim()===canonical;
    if(!old||(profileId&&!old.profile_id)||(isCanonical&&!old.isCanonical))byCanonicalId.set(canonical,{legacy_user_id:canonical,display_name:name,profile_id:profileId||old?.profile_id||null,isCanonical});
  };
  const profileSource=v1179RegisteredUsersLoaded?v1179RegisteredUsers:(typeof v1178RegisteredUsers!=='undefined'?v1178RegisteredUsers:[]);
  for(const u of profileSource||[])add(u?.legacy_user_id,u?.display_name,u?.active,u?.profile_id||u?.id||null);
  for(const u of (db?.users||[]))add(u?.id,u?.name,u?.active,u?.profile_id||u?.id_uuid||null);
  for(const row of (typeof v188LoginUsers==='function'?v188LoginUsers():[])){const [id,name]=row||[];add(id,name,true,null);}
  if(typeof AUTH_LOGIN_USERS!=='undefined')for(const row of AUTH_LOGIN_USERS||[]){const [id,name]=row||[];add(id,name,true,null);}
  for(const u of (typeof v188AdminUsers!=='undefined'?v188AdminUsers:[]))add(u?.legacy_user_id,u?.display_name,u?.active,u?.id||u?.profile_id||null);
  return [...byCanonicalId.values()].map(({isCanonical,...u})=>u).sort((a,b)=>a.display_name.localeCompare(b.display_name,'ja'));
};
window.v1144CandidateForReference=function(reference,candidates=v1144PurchaseStaffCandidates()){return v1179ReferenceCandidate(reference,candidates);};
window.v1144FormalPurchaseStaffName=function(value){const candidate=v1179ReferenceCandidate(value);return candidate?.display_name||v1179FormalStaffName('',value);};
window.v1144AutoPurchaseStaffForItemName=function(itemName){
  const candidates=v1144PurchaseStaffCandidates(),item=qrFindItemByName(itemName);
  const assigned=(item?assignedBuyerIds(item.id):[]).map(id=>v1179ReferenceCandidate(id,candidates)).filter(Boolean);
  const unique=[...new Map(assigned.map(x=>[x.legacy_user_id,x])).values()];if(unique.length===1)return unique[0];
  const master=typeof qrPurchaseStaffMaster==='function'?qrPurchaseStaffMaster():{},normalized=typeof qrNormalizeName==='function'?qrNormalizeName(itemName):String(itemName||'').trim();let reference='';
  for(const [name,value] of Object.entries(master||{})){const key=typeof qrNormalizeName==='function'?qrNormalizeName(name):String(name).trim();if(key===normalized){reference=value;break;}}
  if(!reference&&typeof qrIsPotatoVarietyName==='function'&&qrIsPotatoVarietyName(itemName))reference=master['じゃが芋']||ITEM_BUYER_MASTER?.['じゃが芋']||'';
  const fixed=v1179ReferenceCandidate(reference,candidates);return unique.length>1&&fixed&&unique.some(x=>x.legacy_user_id===fixed.legacy_user_id)?fixed:(fixed||null);
};
window.v1144PurchaseStaffOptionHtml=function(selectedLegacy='',selectedName=''){
  const rows=v1144PurchaseStaffCandidates(),selected=v1179ReferenceCandidate(selectedLegacy,rows)||v1179ReferenceCandidate(selectedName,rows);
  return `<option value="">選択してください</option>${rows.map(x=>`<option value="${esc(x.legacy_user_id)}" ${x.legacy_user_id===selected?.legacy_user_id?'selected':''}>${esc(x.display_name)}</option>`).join('')}`;
};
window.v1144ReadPurchaseStaffFrom=function(el){
  const candidate=v1179ReferenceCandidate(el?.value);
  if(candidate&&el)el.value=candidate.legacy_user_id;
  return candidate?{legacy_user_id:candidate.legacy_user_id,profile_id:candidate.profile_id||null,display_name:candidate.display_name}:{legacy_user_id:null,profile_id:null,display_name:null};
};
window.v1144ReadPurchaseStaff=function(){return v1144ReadPurchaseStaffFrom(document.getElementById('qrPurchaseStaff'));};
/* 最終保存経路も必ず正式氏名を使う。旧ラッパーの内部実装差異に依存しない。 */
const v1179QrSaveLotFinalCore=window.qrSaveLot;
window.qrSaveLot=async function(){
  const staff=document.getElementById('qrPurchaseStaff');
  const info=v1144ReadPurchaseStaffFrom(staff);
  if(!info.display_name){alert('仕入れ担当者を選択してください。');staff?.focus();return;}
  return v1179QrSaveLotFinalCore();
};
window.v1144ReplacePurchaseStaffControl=function(){
  const old=document.getElementById('qrPurchaseStaff');if(!old)return null;
  const previous=old.tagName==='SELECT'?(old.options?.[old.selectedIndex]?.value||old.value):old.value,selected=v1179ReferenceCandidate(previous);
  const select=document.createElement('select');select.id='qrPurchaseStaff';select.className=old.className||'input';select.required=true;select.innerHTML=v1144PurchaseStaffOptionHtml(selected?.legacy_user_id||'',previous);
  select.onchange=()=>{select.dataset.manual='1';const note=document.getElementById('qrStaffNote');if(note)note.textContent=select.value?'選択した担当者を入庫ロットと品質評価へ連携します。':'仕入れ担当者を選択してください。';};old.replaceWith(select);return select;
};
window.qrAutoFillStaff=function(){
  const item=document.getElementById('qrItemName'),staff=document.getElementById('qrPurchaseStaff');if(!item||!staff)return;const itemName=String(item.value||'').trim();if(staff.dataset.itemName===itemName)return;
  const candidate=v1144AutoPurchaseStaffForItemName(itemName);staff.value=candidate?.legacy_user_id||'';staff.dataset.itemName=itemName;staff.dataset.manual='';
  const note=document.getElementById('qrStaffNote');if(note)note.textContent=candidate?'品目担当を自動設定しました。必要な場合のみ変更してください。':'この品目の仕入れ担当者が未設定です。登録ユーザーから選択してください。';
  const managed=document.getElementById('qrManagedNotice');if(managed&&typeof qrManagedNotice==='function')managed.innerHTML=qrManagedNotice(itemName);
};
const v1179QrCreatePageCore=window.qrCreatePage;
window.qrCreatePage=async function(){const result=await v1179QrCreatePageCore();await v1179LoadRegisteredUsers();v1144ReplacePurchaseStaffControl();qrAutoFillStaff();return result;};

/* ===== v1.180: QR入庫仕入れ担当者の選択状態を保存経路まで固定 =====
   select表示、非同期候補更新、旧保存ラッパーを分離し、選択時の3値をDOM datasetに固定する。 */
const V1180_QR_STAFF_STATE_KEY='seika.qrPurchaseStaffState.v1180';
function v1180CanonicalStaffInfo(reference, fallbackName='', fallbackProfileId=null){
  const raw=String(reference||'').trim(), canonical=v1179CanonicalStaffId(raw, fallbackName||raw);
  const formal=v1179FormalStaffName(canonical, fallbackName||raw);
  if(!canonical||!formal)return {legacy_user_id:null,profile_id:null,display_name:null};
  return {legacy_user_id:canonical,profile_id:fallbackProfileId||null,display_name:formal};
}
function v1180ReadStoredStaffState(){
  try{const row=JSON.parse(sessionStorage.getItem(V1180_QR_STAFF_STATE_KEY)||'null');
    return row&&row.legacy_user_id&&row.display_name?v1180CanonicalStaffInfo(row.legacy_user_id,row.display_name,row.profile_id):null;
  }catch(_){return null;}
}
function v1180StoreStaffState(info){
  const stable=info?.legacy_user_id?v1180CanonicalStaffInfo(info.legacy_user_id,info.display_name,info.profile_id):null;
  try{if(stable)sessionStorage.setItem(V1180_QR_STAFF_STATE_KEY,JSON.stringify(stable));else sessionStorage.removeItem(V1180_QR_STAFF_STATE_KEY);}catch(_){}
  return stable;
}
function v1180ClearStaffState(){try{sessionStorage.removeItem(V1180_QR_STAFF_STATE_KEY);}catch(_){}
  const el=document.getElementById('qrPurchaseStaff');if(el){delete el.dataset.staffLegacyUserId;delete el.dataset.staffDisplayName;delete el.dataset.staffProfileId;}
}
function v1180OptionInfo(option){
  if(!option)return null;
  const legacy=String(option.dataset?.legacyUserId||option.value||'').trim();
  const name=String(option.dataset?.displayName||option.textContent||'').trim();
  const profile=String(option.dataset?.profileId||'').trim()||null;
  const info=v1180CanonicalStaffInfo(legacy,name,profile);
  return info.display_name?info:null;
}
function v1180ApplyStaffState(select, info, {manual=false,persist=true}={}){
  if(!select)return null;
  const stable=info?.legacy_user_id?v1180CanonicalStaffInfo(info.legacy_user_id,info.display_name,info.profile_id):null;
  if(!stable){select.value='';delete select.dataset.staffLegacyUserId;delete select.dataset.staffDisplayName;delete select.dataset.staffProfileId;if(persist)v1180StoreStaffState(null);return null;}
  select.value=stable.legacy_user_id;
  select.dataset.staffLegacyUserId=stable.legacy_user_id;
  select.dataset.staffDisplayName=stable.display_name;
  if(stable.profile_id)select.dataset.staffProfileId=stable.profile_id;else delete select.dataset.staffProfileId;
  if(manual)select.dataset.manual='1';
  if(persist)v1180StoreStaffState(stable);
  return stable;
}
function v1180SelectChanged(select,{manual=true}={}){
  const option=select?.options?.[select.selectedIndex];
  const info=v1180OptionInfo(option);
  const stable=v1180ApplyStaffState(select,info,{manual,persist:true});
  const note=document.getElementById('qrStaffNote');
  if(note)note.textContent=stable?'選択した担当者を入庫ロットと品質評価へ連携します。':'仕入れ担当者を選択してください。';
  return stable;
}
function v1180StaffOptionHtml(selectedInfo=null){
  const rows=v1144PurchaseStaffCandidates();
  const selectedId=selectedInfo?.legacy_user_id||'';
  return `<option value="">選択してください</option>${rows.map(row=>{const info=v1180CanonicalStaffInfo(row.legacy_user_id,row.display_name,row.profile_id);return `<option value="${esc(info.legacy_user_id)}" data-legacy-user-id="${esc(info.legacy_user_id)}" data-display-name="${esc(info.display_name)}" data-profile-id="${esc(info.profile_id||'')}" ${info.legacy_user_id===selectedId?'selected':''}>${esc(info.display_name)}</option>`;}).join('')}`;
}
/* 候補再取得には依存しない。option/datasetを第一優先、canonical辞書だけを最後の安全網にする。 */
window.v1144ReadPurchaseStaffFrom=function(el){
  if(!el)return {legacy_user_id:null,profile_id:null,display_name:null};
  const dataInfo=v1180CanonicalStaffInfo(el.dataset?.staffLegacyUserId,el.dataset?.staffDisplayName,el.dataset?.staffProfileId||null);
  if(dataInfo.display_name&&dataInfo.legacy_user_id===v1179CanonicalStaffId(el.value||dataInfo.legacy_user_id,dataInfo.display_name))return dataInfo;
  const optionInfo=v1180OptionInfo(el.options?.[el.selectedIndex]);
  if(optionInfo)return v1180ApplyStaffState(el,optionInfo,{persist:true})||{legacy_user_id:null,profile_id:null,display_name:null};
  const remembered=v1180ReadStoredStaffState();
  if(remembered&&String(el.value||'').trim()===remembered.legacy_user_id)return v1180ApplyStaffState(el,remembered,{persist:false})||remembered;
  const fallback=v1180CanonicalStaffInfo(el.value,el.value,null);
  return fallback.display_name?v1180ApplyStaffState(el,fallback,{persist:true}):{legacy_user_id:null,profile_id:null,display_name:null};
};
window.v1144ReadPurchaseStaff=function(){return v1144ReadPurchaseStaffFrom(document.getElementById('qrPurchaseStaff'));};
/* 置換時も前回の安定状態をcanonical IDで復元する。非同期候補取得後の再描画で選択が消えない。 */
window.v1144ReplacePurchaseStaffControl=function(){
  const old=document.getElementById('qrPurchaseStaff');if(!old)return null;
  const remembered=v1180ReadStoredStaffState();
  const before=v1144ReadPurchaseStaffFrom(old);
  const selected=before.display_name?before:(remembered||null);
  const select=document.createElement('select');select.id='qrPurchaseStaff';select.className=old.className||'input';select.required=true;
  select.innerHTML=v1180StaffOptionHtml(selected);old.replaceWith(select);
  if(selected?.legacy_user_id)v1180ApplyStaffState(select,selected,{manual:old.dataset?.manual==='1',persist:true});
  select.addEventListener('change',()=>v1180SelectChanged(select,{manual:true}));
  return select;
};
window.qrAutoFillStaff=function(){
  const item=document.getElementById('qrItemName'),staff=document.getElementById('qrPurchaseStaff');if(!item||!staff)return;
  const itemName=String(item.value||'').trim();if(staff.dataset.itemName===itemName)return;
  const candidate=v1144AutoPurchaseStaffForItemName(itemName);
  const stable=candidate?v1180ApplyStaffState(staff,candidate,{manual:false,persist:true}):v1180ApplyStaffState(staff,null,{manual:false,persist:true});
  staff.dataset.itemName=itemName;staff.dataset.manual='';
  const note=document.getElementById('qrStaffNote');if(note)note.textContent=stable?'品目担当を自動設定しました。必要な場合のみ変更してください。':'この品目の仕入れ担当者が未設定です。登録ユーザーから選択してください。';
  const managed=document.getElementById('qrManagedNotice');if(managed&&typeof qrManagedNotice==='function')managed.innerHTML=qrManagedNotice(itemName);
};
/* 最終入口で一度だけ確定し、baseには同じ安定状態を読ませる。成功したときだけ状態を消す。 */
const v1180QrSaveLotCore=window.qrSaveLot;
window.qrSaveLot=async function(){
  const staff=document.getElementById('qrPurchaseStaff');const info=v1144ReadPurchaseStaffFrom(staff);
  if(!info.display_name){alert('仕入れ担当者を選択してください。');staff?.focus();return;}
  v1180ApplyStaffState(staff,info,{manual:staff?.dataset?.manual==='1',persist:true});
  /* DBのcreate_qr_lot_v185がokを返すまで、入力状態は絶対に消さない。 */
  window.__v1181QrLotPersisted=false;
  const base=qrSaveLotBase;
  qrSaveLotBase=async function(){
    const current=v1144ReadPurchaseStaffFrom(document.getElementById('qrPurchaseStaff'));
    if(!current.display_name)throw new Error('仕入れ担当者を選択してください。');
    return base.apply(this,arguments);
  };
  try{return await v1180QrSaveLotCore();
  } finally{
    qrSaveLotBase=base;
    if(window.__v1181QrLotPersisted===true)v1180ClearStaffState();
    try{delete window.__v1181QrLotPersisted;}catch(_){window.__v1181QrLotPersisted=false;}
  }
};
const v1180QrCreatePageCore=window.qrCreatePage;
window.qrCreatePage=async function(){const result=await v1180QrCreatePageCore();await v1179LoadRegisteredUsers();const staff=v1144ReplacePurchaseStaffControl();const remembered=v1180ReadStoredStaffState();if(staff&&remembered)v1180ApplyStaffState(staff,remembered,{persist:true});qrAutoFillStaff();return result;};

/* ===== v1.183: QR入庫担当者の表示optionとcanonical IDを保存前に直接整合 ===== */
window.v1183ResolveQrPurchaseStaff=function(staff){
  if(!staff)return {legacy_user_id:null,profile_id:null,display_name:null};
  const selected=staff.options?.[staff.selectedIndex]||null;
  const optionName=String(selected?.dataset?.displayName||selected?.textContent||'').trim();
  const optionLegacy=String(selected?.dataset?.legacyUserId||selected?.value||'').trim();
  const dataName=String(staff.dataset?.staffDisplayName||'').trim();
  const dataLegacy=String(staff.dataset?.staffLegacyUserId||'').trim();
  const optionHasChoice=!!optionName&&optionName!=='選択してください';
  const optionByLegacy=typeof v1179ReferenceCandidate==='function'?v1179ReferenceCandidate(optionLegacy):null;
  const optionByName=typeof v1179ReferenceCandidate==='function'?v1179ReferenceCandidate(optionName):null;
  if(optionHasChoice&&optionByLegacy&&optionByName&&optionByLegacy.legacy_user_id!==optionByName.legacy_user_id)return {legacy_user_id:null,profile_id:null,display_name:null};
  const dataByLegacy=!optionHasChoice&&typeof v1179ReferenceCandidate==='function'?v1179ReferenceCandidate(dataLegacy):null;
  const dataByName=!optionHasChoice&&typeof v1179ReferenceCandidate==='function'?v1179ReferenceCandidate(dataName):null;
  if(!optionHasChoice&&dataByLegacy&&dataByName&&dataByLegacy.legacy_user_id!==dataByName.legacy_user_id)return {legacy_user_id:null,profile_id:null,display_name:null};
  const candidate=optionHasChoice?(optionByLegacy||optionByName):(dataByLegacy||dataByName);
  const info=candidate?{legacy_user_id:candidate.legacy_user_id,profile_id:candidate.profile_id||null,display_name:candidate.display_name}:null;
  if(!info?.display_name||!info?.legacy_user_id)return {legacy_user_id:null,profile_id:null,display_name:null};
  let option=[...(staff.options||[])].find(x=>String(x.value||'').trim()===info.legacy_user_id);
  if(!option&&selected&&optionName&&optionName!=='選択してください')option=selected;
  if(!option&&staff.tagName==='SELECT'){
    option=document.createElement('option');option.textContent=info.display_name;staff.appendChild(option);
  }
  if(option){option.value=info.legacy_user_id;option.dataset.legacyUserId=info.legacy_user_id;option.dataset.displayName=info.display_name;if(info.profile_id)option.dataset.profileId=info.profile_id;option.selected=true;staff.value=info.legacy_user_id;}
  if(typeof v1180ApplyStaffState==='function')v1180ApplyStaffState(staff,info,{manual:staff.dataset?.manual==='1',persist:true});
  return info;
};
const v1183QrSaveLotCore=window.qrSaveLot;
window.qrSaveLot=async function(){
  const staff=document.getElementById('qrPurchaseStaff');
  const info=v1183ResolveQrPurchaseStaff(staff);
  if(!info.display_name){alert('仕入れ担当者を選択してください。');staff?.focus();return;}
  return v1183QrSaveLotCore();
};
/* ===== v1.184: QR担当者自動反映・棚卸し開始遷移修正 ===== */
function v1184ApplyQrPurchaseStaffForItem({force=false}={}){
  const item=document.getElementById('qrItemName'),staff=document.getElementById('qrPurchaseStaff');
  if(!item||!staff)return null;
  const itemName=String(item.value||'').trim(),changed=String(staff.dataset?.itemName||'')!==itemName;
  if(!force&&!changed&&staff.dataset?.manual==='1')return v1183ResolveQrPurchaseStaff(staff);
  if(!force&&!changed)return v1183ResolveQrPurchaseStaff(staff);
  const candidate=itemName&&typeof v1144AutoPurchaseStaffForItemName==='function'?v1144AutoPurchaseStaffForItemName(itemName):null;
  if(staff.tagName==='SELECT'){
    let option=candidate?[...(staff.options||[])].find(row=>String(row.value||'')===String(candidate.legacy_user_id||'')):null;
    if(candidate&&!option){option=document.createElement('option');option.value=candidate.legacy_user_id;option.textContent=candidate.display_name;option.dataset.legacyUserId=candidate.legacy_user_id;option.dataset.displayName=candidate.display_name;if(candidate.profile_id)option.dataset.profileId=candidate.profile_id;staff.appendChild(option);}
    staff.value=option?.value||'';
  }else staff.value=candidate?.display_name||'';
  staff.dataset.itemName=itemName;staff.dataset.manual='';
  const stable=candidate&&typeof v1180ApplyStaffState==='function'?v1180ApplyStaffState(staff,candidate,{manual:false,persist:true}):null;
  const note=document.getElementById('qrStaffNote');if(note)note.textContent=stable?'品目に紐付く担当者を自動反映しました。必要な場合は変更できます。':'この品目の仕入れ担当者は未設定です。担当者を選択してください。';
  const managed=document.getElementById('qrManagedNotice');if(managed&&typeof qrManagedNotice==='function')managed.innerHTML=qrManagedNotice(itemName);
  return stable;
}
window.qrAutoFillStaff=function(){return v1184ApplyQrPurchaseStaffForItem()};
function v1184BindQrPurchaseStaff(){
  const staff=document.getElementById('qrPurchaseStaff');if(!staff)return;
  const markManual=()=>{staff.dataset.manual='1';const info=v1183ResolveQrPurchaseStaff(staff);const note=document.getElementById('qrStaffNote');if(note)note.textContent=info?.display_name?'選択した担当者を入庫ロットと品質評価へ連携します。':'仕入れ担当者を選択してください。';};
  staff.addEventListener('change',markManual);if(staff.tagName==='INPUT')staff.addEventListener('input',markManual);
}
const v1184QrCreatePageCore=window.qrCreatePage;
window.qrCreatePage=async function(){
  const result=await v1184QrCreatePageCore();
  v1184BindQrPurchaseStaff();
  v1184ApplyQrPurchaseStaffForItem({force:true});
  return result;
};
function v1184UpsertLocalCountSession(session){
  if(!session?.id)return null;
  db.inventoryCounts=db.inventoryCounts&&typeof db.inventoryCounts==='object'?db.inventoryCounts:{sessions:[]};
  const sessions=Array.isArray(db.inventoryCounts.sessions)?db.inventoryCounts.sessions:[];
  const normalized=v177Session(session)?session:(typeof v124NormalizeSession==='function'?v124NormalizeSession(session):session);
  const index=sessions.findIndex(row=>String(row?.id||'')===String(normalized.id));
  if(index>=0)sessions[index]={...sessions[index],...normalized};else sessions.push(normalized);
  db.inventoryCounts.sessions=sessions;
  if(typeof v188PersistDb==='function')v188PersistDb();
  return countSession(normalized.id);
}
async function v1184ProtectPendingBeforeCount(){
  if(!v161PendingCount())return true;
  await retryPendingSync();
  if(v161PendingCount())throw new Error('未同期データが残っています。画面上部の「再送」で保存を完了してから棚卸しを開始してください。');
  return true;
}
window.v1184StartInventoryCount=async function(room){
  if(!v177Allowed())return alert('棚卸しを操作できるのは管理者・青果社員のみです。');
  if(!validColdRoom(room))return alert('冷蔵庫を選択してください。');
  v161ShowProcessing('棚卸し開始前のデータを確認しています');
  try{
    await v1184ProtectPendingBeforeCount();
    await loadCloud();
    const active=countSessions().find(row=>row?.room===room&&v177Session(row)&&!v177Completed(row)&&!['cancelled','reversed'].includes(String(row.status||'')));
    if(active){v161HideProcessing();if(confirm(`${roomLabel(room)}の進行中棚卸しを開きますか？`))return v177SectionPage(active.id,'normal');return;}
    v161ShowProcessing('棚卸し開始時点の最新在庫を固定しています');
    const qrLines=await v177QrSnapshot(room),lines=v177NormalLines(room),at=nowIso();
    const session={id:qrInventoryUuid(),inventoryCountMode:V177_COUNT_MODE,countNo:countNumber(room),room,roomLabel:roomLabel(room),status:'counting',startedAt:at,startedBy:db.user,startedById:db.userId,updatedAt:at,updatedBy:db.user,revision:1,normalStatus:'counting',qrCountStatus:'counting',normalSectionRevision:0,qrSectionRevision:0,lines,qrLines,inventoryApplied:false,qrApplied:false,v177SnapshotRule:'開始時点の最新在庫あり',v177QrSnapshotAt:at};
    const answer=await callRpc(V177_CREATE_RPC,{p_id:STATE_ID,p_session:session,p_operation_id:qrInventoryUuid()});
    if(answer?.conflict)throw new Error(answer.message||'別端末で更新されています。');
    if(!answer?.ok)throw new Error(answer?.message||'棚卸しを開始できませんでした。');
    const createdId=String(answer?.sessionId||answer?.session_id||session.id);
    if(createdId!==session.id)session.id=createdId;
    v1184UpsertLocalCountSession(session);
    if(!v177Session(countSession(createdId)))throw new Error('作成した棚卸しを端末へ読み込めませんでした。再読込して進行中棚卸しを開いてください。');
    return v177SectionPage(createdId,'normal','棚卸し開始時点で在庫がある通常品目とQRロットを固定しました。');
  }catch(error){alert(`棚卸しを開始できませんでした。\n${v161ErrorText(error)}\n\n入力中・未同期データは削除していません。`);return inventoryCountHome();}
  finally{v161HideProcessing();}
};
window.v177Start=window.v1184StartInventoryCount;
startInventoryCount=window.v1184StartInventoryCount;
const v1184InventoryCountHomeCore=window.inventoryCountHome;
window.inventoryCountHome=function(msg=''){const result=v1184InventoryCountHomeCore(msg);const shell=[...document.querySelectorAll('.small')].find(node=>/v1\.179/.test(node.textContent||''));if(shell)shell.textContent=String(shell.textContent||'').replace(/v1\.179/g,'v1.184');return result;};
inventoryCountHome=window.inventoryCountHome;
const v1184InventoryCountGuideCore=window.inventoryCountGuidePage;
window.inventoryCountGuidePage=function(){const result=v1184InventoryCountGuideCore();document.querySelectorAll('.small').forEach(node=>{if(/v1\.179/.test(node.textContent||''))node.textContent=String(node.textContent||'').replace(/v1\.179/g,'v1.184')});return result;};
inventoryCountGuidePage=window.inventoryCountGuidePage;
/* ===== v1.186: 簡単棚卸し・A4記入票 ===== */
const V186_COUNT_MODE='live_snapshot_v186';
const V186_CONFIRM_RPC='v186_confirm_live_inventory_count';
function v186Session(session){return Boolean(session&&v177Session(session)&&session.liveSnapshotMode===V186_COUNT_MODE)}
function v186Confirmed(session){return v186Session(session)&&Boolean(session.v186ConfirmedAt||session.v186LiveSnapshotConfirmed)}
function v186CompletedForRouting(session){return v186Confirmed(session)||(v177Session(session)&&Boolean(session?.v177Applied||session?.v177AppliedAt||session?.v177CompletedAt))}
v177Completed=v186CompletedForRouting
function v186PendingCount(){return Number(v161PendingCount?.()||0)+Number(v193QrEditHistoryPendingCount?.()||0)+Number(v1163ReadWastePriceQueue?.().length||0)}
async function v186ProtectPending(){
  if(!v186PendingCount())return;
  await retryPendingSync();
  if(v186PendingCount())throw new Error('未同期データが残っています。画面上部の「再送」で保存を完了してから実行してください。');
}
function v186SnapshotNormal(room){
  return v177NormalLines(room).map(line=>{const qty=Number(line.systemQty||0);return {...line,actualQty:qty,status:'entered',weightEntries:v119IsKgLine(line)?[{id:'snapshot-1',packKg:qty>0?qty:1,caseCount:qty>0?1:0}]:undefined,remainderKg:v119IsKgLine(line)?0:undefined,memo:line.memo||'',supplier:line.supplier||''}});
}
async function v186SnapshotQr(room){return (await v177QrSnapshot(room)).map(line=>({...line,actualQty:Number(line.systemQty||0),status:'entered',memo:line.memo||''}))}
function v186Chunk(rows,size=15){const pages=[];for(let i=0;i<rows.length;i+=size)pages.push(rows.slice(i,i+size));return pages.length?pages:[[]]}
function v186PrintCss(){return `@page{size:A4 landscape;margin:5mm}*{box-sizing:border-box}html,body{margin:0;padding:0;background:#fff;color:#111;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI','Yu Gothic',sans-serif}.printPage{width:287mm;height:200mm;overflow:hidden;break-after:page;page-break-after:always}.printPage:last-child{break-after:auto;page-break-after:auto}h1{margin:0 0 1.5mm;font-size:14pt;line-height:1.2;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.meta{height:6mm;margin:0 0 1.5mm;font-size:8.5pt;line-height:1.3}table{width:100%;border-collapse:collapse;table-layout:fixed}th,td{border:.25mm solid #111;padding:.65mm .8mm;font-size:9pt;line-height:1.15;vertical-align:middle;overflow-wrap:anywhere;word-break:break-word}th{height:8mm;background:#d9eaf7;text-align:center;font-weight:700}.dataRow td{height:10mm}.write{background:#fff}.pageNo{float:right;font-size:8pt;font-weight:400}@media print{thead{display:table-header-group}tr{break-inside:avoid;page-break-inside:avoid}}`}
function v186PrintPage(title,meta,heads,widths,rows,pageNo,total){return `<section class="printPage"><h1>${esc(title)} <span class="pageNo">${pageNo}/${total}</span></h1><div class="meta">${esc(meta)}　作成：${esc(dt(nowIso()))}</div><table><colgroup>${widths.map(width=>`<col style="width:${width}%">`).join('')}</colgroup><thead><tr>${heads.map(head=>`<th>${esc(head)}</th>`).join('')}</tr></thead><tbody>${rows.join('')}</tbody></table></section>`}
function v186NormalPages(session,lines){const chunks=v186Chunk(lines,15);return chunks.map((chunk,index)=>v186PrintPage(`${session.roomLabel} 通常在庫 棚卸し記入票`,`${session.countNo} / 印刷時点の最新在庫`,['区分','品名','単位','帳簿在庫','実数','仕入先','備考'],[11,24,8,12,12,15,18],chunk.map(line=>`<tr class="dataRow"><td>${esc(line.group||'')}</td><td>${esc(line.itemName||'')}</td><td>${esc(line.unit||'')}</td><td>${fmt(line.systemQty)} ${esc(line.unit||'')}</td><td class="write"></td><td class="write"></td><td class="write"></td></tr>`),index+1,chunks.length)).join('')}
function v186QrPages(session,lines){const items=[...new Set(lines.map(line=>String(line.itemName||'品名未設定')))].sort((a,b)=>a.localeCompare(b,'ja'));return items.map(item=>{const chunks=v186Chunk(lines.filter(line=>String(line.itemName||'品名未設定')===item),15);return chunks.map((chunk,index)=>v186PrintPage(`${session.roomLabel} QR在庫 ${item} 記入票`,`${session.countNo} / 印刷時点の最新在庫 / 品目別`,['ロット','入荷日','荷姿','単位','帳簿在庫','実数','備考'],[24,12,16,8,13,12,15],chunk.map(line=>`<tr class="dataRow"><td>${esc(line.lotNo||line.qrKey||'')}</td><td>${esc(line.receivedDate||line.received_date||'')}</td><td>${esc(line.containerType||'')}</td><td>${esc(line.unit||'')}</td><td>${fmt(line.systemQty)} ${esc(line.unit||'')}</td><td class="write"></td><td class="write"></td></tr>`),index+1,chunks.length)).join('')}).join('')}
function v186PrintDocument(session,normal,qr,mode='all'){const body=(mode==='all'||mode==='normal'?v186NormalPages(session,normal):'')+(mode==='all'||mode==='qr'?v186QrPages(session,qr):'');return `<!doctype html><html lang="ja"><head><meta charset="utf-8"><title>${esc(session.roomLabel)} 棚卸し記入票</title><style>${v186PrintCss()}</style></head><body>${body||'<section class="printPage"><h1>対象在庫はありません</h1></section>'}</body></html>`}
async function v186PrintLatest(id,mode='all'){
  const session=countSession(id);if(!session||!v186Session(session))return alert('棚卸しが見つかりません。');
  const win=window.open('','_blank');if(!win)return alert('印刷画面を開けませんでした。ポップアップ許可を確認してください。');
  win.document.write('<!doctype html><meta charset="utf-8"><title>記入票を準備中</title><p style="font-family:sans-serif;padding:24px">最新在庫の記入票を準備しています。</p>');
  try{await v186ProtectPending();await loadCloud();const current=countSession(id)||session;const normal=v186SnapshotNormal(current.room),qr=await v186SnapshotQr(current.room);win.document.open();win.document.write(v186PrintDocument(current,normal,qr,mode));win.document.close();win.focus();}
  catch(error){win.close();alert(`記入票を作成できませんでした。\n${v161ErrorText(error)}\n\n未同期データは削除していません。`)}
}
function v186OpenNormal(room){inventory('',room)}
function v186OpenQrOut(){qrOperationSelectPage('out')}
function v186OpenQrAdjust(){qrOperationSelectPage('adjust')}
async function v186Start(room){
  if(!v177Allowed())return alert('棚卸しを操作できるのは管理者・青果社員のみです。');if(!validColdRoom(room))return alert('冷蔵庫を選択してください。');
  v161ShowProcessing('最新在庫を確認しています');
  try{await v186ProtectPending();await loadCloud();const existing=countSessions().find(session=>session?.room===room&&!['completed','confirmed','test_confirmed','reversed','cancelled'].includes(String(session.status||'')));if(existing){if(v186Session(existing))return inventoryCountHome(`${roomLabel(room)}の棚卸しは進行中です。`);return alert('この冷蔵庫には旧仕様の進行中棚卸しがあります。旧棚卸しを完了してから開始してください。');}
    const at=nowIso(),session={id:qrInventoryUuid(),inventoryCountMode:V177_COUNT_MODE,liveSnapshotMode:V186_COUNT_MODE,countNo:countNumber(room),room,roomLabel:roomLabel(room),status:'counting',startedAt:at,startedBy:db.user,startedById:db.userId,updatedAt:at,updatedBy:db.user,revision:1,normalStatus:'counting',qrCountStatus:'counting',normalSectionRevision:0,qrSectionRevision:0,lines:v186SnapshotNormal(room),qrLines:await v186SnapshotQr(room),inventoryApplied:false,qrApplied:false,v177SnapshotRule:'記入票作成時点の最新在庫',v177QrSnapshotAt:at};
    const answer=await callRpc(V177_CREATE_RPC,{p_id:STATE_ID,p_session:session,p_operation_id:qrInventoryUuid()});if(answer?.conflict)throw new Error(answer.message||'別端末で更新されています。');if(!answer?.ok)throw new Error(answer?.message||'棚卸しを開始できませんでした。');const id=String(answer.sessionId||session.id);session.id=id;await loadCloud();if(!countSession(id))v1184UpsertLocalCountSession({...session,revision:Number(session.revision||0)+1});return inventoryCountHome(`${roomLabel(room)}の棚卸しを開始しました。最初に記入票を印刷してください。`);
  }catch(error){alert(`棚卸しを開始できませんでした。\n${v161ErrorText(error)}\n\n入力中・未同期データは削除していません。`);return inventoryCountHome()}finally{v161HideProcessing()}
}
async function v186Confirm(id){
  let session=countSession(id);if(!session||!v186Session(session)||!v177Allowed())return alert('確定できる棚卸しが見つかりません。');if(v186Confirmed(session))return inventoryCountHome('この棚卸しは確定済みです。');if(!confirm(`${session.roomLabel}の現在の通常在庫・QR在庫を棚卸し結果として確定します。\n\n通常在庫入力とQR出庫・調整がすべて保存済みであることを確認してください。\n確定後は棚卸し結果を変更できません。よろしいですか？`))return;
  v161ShowProcessing('未同期データと最新在庫を確認しています');
  try{await v186ProtectPending();await loadCloud();session=countSession(id);if(!session||v186Confirmed(session))return inventoryCountHome('この棚卸しは確定済みです。');const lines=v186SnapshotNormal(session.room),qrLines=await v186SnapshotQr(session.room),answer=await callRpc(V186_CONFIRM_RPC,{p_id:STATE_ID,p_session_id:id,p_expected_session_revision:Number(session.revision)||0,p_expected_state_version:stateVersion,p_lines:lines,p_qr_lines:qrLines,p_operation_id:qrInventoryUuid()});if(answer?.conflict)throw new Error(answer.message||'別端末で棚卸しが更新されています。');if(!answer?.ok)throw new Error(answer?.message||'棚卸しを確定できませんでした。');if(answer.session)v1184UpsertLocalCountSession(answer.session);else await loadCloud();return inventoryCountHome('確定時点の最新在庫を棚卸し結果として保存しました。Excelを出力できます。')}
  catch(error){alert(`棚卸しを確定できませんでした。\n${v161ErrorText(error)}\n\n通常在庫・QR在庫と未同期データは変更・削除していません。`)}finally{v161HideProcessing()}
}
function v186DownloadExcel(id){const session=countSession(id);if(!session||!v186Session(session))return v177DownloadExcel(id);if(!v186Confirmed(session))return alert('Excelは棚卸し確定後に出力できます。');if(!ensureXlsxReady())return;const originalAppliedAt=session.v177AppliedAt,originalCompletedAt=session.v177CompletedAt;session.v177AppliedAt=null;session.v177CompletedAt=null;const wb=XLSX.utils.book_new(),normal=v177AddDetailSheet(wb,`${session.roomLabel} 通常在庫`,`${session.roomLabel} 通常在庫 棚卸し確定結果`,session,'normal'),qr=v177AddDetailSheet(wb,`${session.roomLabel} QR在庫`,`${session.roomLabel} QR在庫 棚卸し確定結果`,session,'qr');v177AddSummarySheet(wb,session,normal,qr);const normalSheet=wb.Sheets[normal.name],qrSheet=wb.Sheets[qr.name];if(normalSheet?.B5)normalSheet.B5.v='確定時点の在庫を保存（在庫操作なし）';if(qrSheet?.B5)qrSheet.B5.v='確定時点の在庫を保存（在庫操作なし）';session.v177AppliedAt=originalAppliedAt;session.v177CompletedAt=originalCompletedAt;downloadWorkbookXlsx(wb,`棚卸し確定結果_${String(session.roomLabel||'冷蔵庫').replace(/[\\/:*?"<>|]/g,'_')}_${String(session.countNo||'棚卸し').replace(/[\\/:*?"<>|]/g,'_')}.xlsx`);inventoryCountHome('確定時点の棚卸しExcelを出力しました。')}
function v186LegacyCard(session){const isV177=v177Session(session),done=isV177&&v177Completed(session),legacyConfirmed=['confirmed','test_confirmed'].includes(String(session?.status||''));return `<div class="card"><div class="itemHead"><div><b>${esc(session.countNo||'旧棚卸し')}</b><div class="small">${esc(session.roomLabel||'')} / 旧仕様（データ保持）</div></div><span class="badge ${done||legacyConfirmed?'normal':'unset'}">${done||legacyConfirmed?'完了済み':'旧仕様'}</span></div><div class="mini" style="margin-top:8px">${isV177&&!done?`<button class="btn btn2" ${seikaEventAttrs('click','v177SectionPage',[session.id,'normal'])}>旧棚卸しを開く</button>`:`<button class="btn btn2" ${seikaEventAttrs('click','v186OpenLegacy',[session.id])}>結果を閲覧</button>`}${done?`<button class="btn orange" ${seikaEventAttrs('click','v177DownloadExcel',[session.id])}>旧Excelを出力</button>`:''}</div></div>`}
function v186Home(msg=''){
  setScreen('inventoryCountHome',[msg]);if(!v177Allowed())return home();v124AllSessions();const sessions=countSessions().slice().sort((a,b)=>new Date(b.updatedAt||b.startedAt||0)-new Date(a.updatedAt||a.startedAt||0)),active=sessions.filter(session=>v186Session(session)&&!v186Confirmed(session)),history=sessions.filter(session=>v186Session(session)&&v186Confirmed(session)),legacy=sessions.filter(session=>!v186Session(session));
  const activeCard=session=>`<div class="card"><div class="itemHead"><div><b>${esc(session.countNo)}</b><div class="small">${esc(session.roomLabel)} / 開始：${esc(session.startedAt?dt(session.startedAt):'－')}</div></div><span class="badge unset">確認・訂正中</span></div><div class="notice" style="margin-top:10px"><b>1. 記入票</b><div class="small">ボタンを押した時点の最新在庫で作成します。</div><div class="mini" style="margin-top:8px"><button class="btn orange" ${seikaEventAttrs('click','v186PrintLatest',[session.id,'all'])}>通常・QR記入票を印刷</button><button class="btn btn2" ${seikaEventAttrs('click','v186PrintLatest',[session.id,'normal'])}>通常だけ印刷</button><button class="btn btn2" ${seikaEventAttrs('click','v186PrintLatest',[session.id,'qr'])}>QRだけ印刷</button></div></div><div class="notice" style="margin-top:10px"><b>2. 在庫を入力・訂正</b><div class="small">棚卸し専用入力はありません。いつもの画面で入力します。</div><div class="mini" style="margin-top:8px"><button class="btn green" ${seikaEventAttrs('click','v186OpenNormal',[session.room])}>通常在庫入力を開く</button><button class="btn blue" ${seikaEventAttrs('click','v186OpenQrOut',[])}>QR出庫を開く</button><button class="btn btn2" ${seikaEventAttrs('click','v186OpenQrAdjust',[])}>QR在庫調整を開く</button></div></div><div class="notice" style="margin-top:10px"><b>3. 棚卸しを確定</b><div class="small">すべての入力・訂正後、確定時点の最新在庫を保存します。</div><button class="btn orange" style="width:100%;margin-top:8px" ${seikaEventAttrs('click','v186Confirm',[session.id])}>現在の在庫で棚卸しを確定</button></div></div>`;
  const historyCard=session=>`<div class="card"><div class="itemHead"><div><b>${esc(session.countNo)}</b><div class="small">${esc(session.roomLabel)} / 確定：${esc(session.v186ConfirmedAt?dt(session.v186ConfirmedAt):'－')}</div></div><span class="badge normal">確定済み</span></div><div class="mini" style="margin-top:8px"><button class="btn orange" ${seikaEventAttrs('click','v186DownloadExcel',[session.id])}>Excelを出力</button><button class="btn btn2" ${seikaEventAttrs('click','v186PrintLatest',[session.id,'all'])}>現在の記入票を再印刷</button></div></div>`;
  pageShell('棚卸しモード',`${esc(v119RoleLabel())} / v1.187`,`${okHtml(msg)}<div class="card notice"><b>かんたん3ステップ</b><div class="small">①最新在庫の記入票を印刷　②いつもの通常在庫・QR画面で入力や訂正　③棚卸しモードに戻って確定・Excel出力<br>棚卸し専用の入力画面は使用しません。</div></div><div class="card"><b>新しい棚卸しを開始</b><div class="grid" style="margin-top:9px"><button class="btn orange" ${seikaEventAttrs('click','v186Start',['room2'])}>第2冷蔵庫</button><button class="btn orange" ${seikaEventAttrs('click','v186Start',['room3'])}>第3冷蔵庫</button></div></div><div class="card"><b>進行中</b>${active.map(activeCard).join('')||'<div class="small">進行中の棚卸しはありません。</div>'}</div><div class="card"><b>確定済み</b>${history.map(historyCard).join('')||'<div class="small">確定済みの棚卸しはありません。</div>'}</div>${legacy.length?`<details class="card"><summary><b>旧棚卸し履歴（${legacy.length}件）</b></summary><div style="margin-top:10px">${legacy.map(v186LegacyCard).join('')}</div></details>`:''}`)
}
function v186Guide(){setScreen('inventoryCountGuidePage');if(!v177Allowed())return home();pageShell('棚卸しモードの使い方','管理者・青果社員のみ / v1.187',`<div class="card notice"><b>1. 記入票を印刷</b><div class="small">第2・第3冷蔵庫を選び、「通常・QR記入票を印刷」を押します。ボタンを押した時点の最新在庫が記載されます。</div></div><div class="card"><b>2. いつもの画面で入力・訂正</b><div class="small">通常在庫は「通常在庫入力」、QRは「QR出庫」または「QR在庫調整」を使用します。棚卸し専用入力画面はありません。</div></div><div class="card"><b>3. 確定・Excel</b><div class="small">入力・訂正が終わったら棚卸しモードへ戻り、「現在の在庫で棚卸しを確定」を押します。確定時点の最新在庫が保存され、Excelを出力できます。</div></div><div class="card"><b>データ保護</b><div class="small">未同期データが残る場合は確定を停止します。旧棚卸し履歴も削除せず、画面下部から確認できます。</div></div>`)}
function v186OpenLegacy(id){const session=countSession(id);if(!session)return inventoryCountHome('旧棚卸しが見つかりません。');if(v177Session(session))return v177Completed(session)?v171ReadOnlyView(id):v177SectionPage(id,'normal');if(typeof v124NormalizeSession==='function')v124NormalizeSession(session);return v186InventoryCountPageLegacy(id,'旧棚卸しデータを保持したまま表示しています。')}
window.v186Start=v186Start;window.v186PrintLatest=v186PrintLatest;window.v186Confirm=v186Confirm;window.v186DownloadExcel=v186DownloadExcel;window.v186OpenNormal=v186OpenNormal;window.v186OpenQrOut=v186OpenQrOut;window.v186OpenQrAdjust=v186OpenQrAdjust;window.v186OpenLegacy=v186OpenLegacy;
window.inventoryCountHome=v186Home;inventoryCountHome=v186Home;startInventoryCount=v186Start;downloadInventoryCountExcel=v186DownloadExcel;inventoryCountGuidePage=v186Guide;
const v186InventoryCountPageLegacy=inventoryCountPage;inventoryCountPage=function(id,msg=''){const session=countSession(id);return v186Session(session)?v186Home(msg):v186InventoryCountPageLegacy(id,msg)};
window.APP_VERSION='v1.186';document.title='SEIKA＋ v1.186 簡単棚卸し・印刷調整版';

/* ===== v1.187: 記入票の量目・仕入先表示 / 低評価のホーム表示復旧 / QR出庫の連続操作 ===== */
/* 1. 棚卸し記入票：現物確認しやすいよう、量目（入数）と仕入先を印字します。 */
function v187NormalPackText(line){
  if(line&&line.type==='normal'){
    const record=latestRecord(line.itemId),text=record?inventoryLineText(record):'';
    if(text)return text;
  }
  const pack=Number(line&&line.snapshotPackKg),cases=Number(line&&line.snapshotCases),unit=String((line&&line.unit)||'');
  if(Number.isFinite(pack)&&pack>0&&Number.isFinite(cases)&&cases>0)return `${fmt(pack)}kg×${fmt(cases)}${unit&&unit!=='kg'?unit:'ケース'}`;
  if(Number.isFinite(pack)&&pack>0)return `${fmt(pack)}kg入`;
  return '';
}
function v187NormalSupplierText(line){return String((line&&line.supplier)||'').trim()}
function v187QrPackText(line){
  const pack=Number(line&&line.packWeight);
  if(Number.isFinite(pack)&&pack>0)return `${fmt(pack)}kg`;
  const total=Number(line&&line.snapshotTotalWeight),initial=Number(line&&line.snapshotInitialQty);
  if(Number.isFinite(total)&&total>0&&Number.isFinite(initial)&&initial>0)return `${fmt(total/initial)}kg/${String((line&&line.unit)||'基')}`;
  return '';
}
v186NormalPages=function(session,lines){
  const chunks=v186Chunk(lines,15);
  return chunks.map((chunk,index)=>v186PrintPage(`${session.roomLabel} 通常在庫 棚卸し記入票`,`${session.countNo} / 印刷時点の最新在庫`,
    ['区分','品名','量目・入数','仕入先','帳簿在庫','実数','備考'],[9,20,21,14,11,11,14],
    chunk.map(line=>{const supplier=v187NormalSupplierText(line);
      return `<tr class="dataRow"><td>${esc(line.group||'')}</td><td>${esc(line.itemName||'')}</td><td>${esc(v187NormalPackText(line))}</td><td class="${supplier?'':'write'}">${esc(supplier)}</td><td>${fmt(line.systemQty)} ${esc(line.unit||'')}</td><td class="write"></td><td class="write"></td></tr>`}),
    index+1,chunks.length)).join('');
};
v186QrPages=function(session,lines){
  const items=[...new Set(lines.map(line=>String(line.itemName||'品名未設定')))].sort((a,b)=>a.localeCompare(b,'ja'));
  return items.map(item=>{
    const chunks=v186Chunk(lines.filter(line=>String(line.itemName||'品名未設定')===item),15);
    return chunks.map((chunk,index)=>v186PrintPage(`${session.roomLabel} QR在庫 ${item} 記入票`,`${session.countNo} / 印刷時点の最新在庫 / 品目別`,
      ['ロット','入荷日','荷姿','量目','仕入先','帳簿在庫','実数','備考'],[20,10,11,9,15,12,12,11],
      chunk.map(line=>`<tr class="dataRow"><td>${esc(line.lotNo||line.qrKey||'')}</td><td>${esc(line.receivedDate||line.received_date||'')}</td><td>${esc(line.containerType||'')}</td><td>${esc(v187QrPackText(line))}</td><td>${esc(line.supplier||'')}</td><td>${fmt(line.systemQty)} ${esc(line.unit||'')}</td><td class="write"></td><td class="write"></td></tr>`),
      index+1,chunks.length)).join('');
  }).join('');
};

/* 2. 仕入れ担当者ホームの未確認低評価表示を復旧します。
      v1.171 で「今日の作業」から品質評価の表示枠（#v1143QualityTask）が外れ、
      v1143LoadQualityTask が描画先を見つけられず何も表示されない状態でした。 */
v1143TodayTaskHtml=function(){
  if(['viewer','office_viewer'].includes(db.role))return '';
  const role=db.role,rows=[],add=(label,count,action,labelGo)=>{if(Number(count)>0)rows.push(v1143TaskRow(label,count,action,labelGo))},personal=v1143PersonalPendingCount();
  if(role==='admin'){add('本日未入力',todayMissingItems().length,'inventory','在庫入力を開く');add('月次Excel作成待ち',monthlyExportTasks().length,'monthlyArchive','月次Excelを開く');add('この端末の保留・下書き',personal,'personalWork','保留作業を開く')}
  else if(role==='worker'){add('本日未入力',todayMissingItems().length,'inventory','在庫入力を開く');add('棚卸しの入力・下書き',v1143ActiveCount(),'inventoryCount','棚卸しを開く');add('この端末の保留・下書き',personal,'personalWork','保留作業を開く');v1143RequiredQualityKey=String(localStorage.getItem(V1111_REQUIRED_QUALITY_KEY)||'');if(v1143RequiredQualityKey)rows.push(v1143TaskRow('QR入庫後の品質評価',1,'requiredQuality','品質評価一覧を開く'))}
  else if(role==='buyer'){add('発注候補',orderCandidatesForBuyer(db.userId).length,'orderCandidates','発注候補を開く');add('過多品目',excessCandidatesForBuyer(db.userId).length,'excessCandidates','過多品目を開く')}
  else if(role==='clerk'){add('月次Excel作成待ち',monthlyExportTasks().length,'monthlyArchive','月次Excelを開く');add('この端末の保留・下書き',personal,'personalWork','保留作業を開く')}
  const waitsForQuality=['admin','buyer','worker'].includes(role);
  if(!rows.length&&!waitsForQuality)return '';
  const empty=`<div id="v1143TodayTaskEmpty" class="small">${esc(v1143TaskText('現在、対応が必要な項目はありません'))}</div>`;
  return `<section id="v1143TodayTasks" class="card v1143TodayTasks"><h2 style="margin:0">${esc(v1143TaskText('今日の作業'))}</h2><div id="v1143TodayTaskRows" class="v1143TaskRows">${rows.join('')||(waitsForQuality?'':empty)}</div>${waitsForQuality?`<div id="v1143QualityTask" class="small" style="margin-top:10px">${esc(v1143TaskText('未確認の低評価'))}：${esc(v1143TaskText('確認中'))}</div>`:''}</section>`;
};

/* 3. QR出庫後は、同じ品目のロット一覧（出庫モード）へ直接戻します。 */
let v187LastOutItemName='',v187LastOutQrKey='';
const v187QrSaveLotMovementCore=(typeof v1156QrSaveLotMovementCore==='function')?v1156QrSaveLotMovementCore:qrSaveLotMovement;
qrSaveLotMovement=async function(kind,q){
  if(kind==='out'){
    const lot=await qrFindLot(q).catch(()=>null);
    v187LastOutItemName=String(lot?.item_name||'').trim();
    v187LastOutQrKey=String(lot?.qr_key||q||'');
    if(typeof v1156QrSearchState==='object'&&v1156QrSearchState)v1156QrSearchState.returnEnabled=false;
  }
  return await v187QrSaveLotMovementCore(kind,q);
};
function v187ContinueCardHtml(item,qrKey){
  return `<div id="v187ContinueCard" class="card notice"><b>続けて処理できます</b><div class="small" style="margin-top:6px">上の一覧から同じ品目の別ロットを選ぶと、そのまま出庫入力へ進みます。</div><div class="mini" style="margin-top:9px">${qrKey?`<button class="btn green" ${seikaEventAttrs('click','qrOperationLotPage',['out',qrKey])}>同じロットを続けて出庫</button>`:''}<button class="btn blue" ${seikaEventAttrs('click','qrCameraPage',['out'])}>別のQRを読む</button><button class="btn btn2" data-seika-click-action="qrHome" data-seika-click-args="%5B%5D">QR在庫管理へ戻る</button></div>${qrKey?`<button class="btn orange" style="width:100%;margin-top:9px" ${seikaEventAttrs('click','cancelLatestQrOperation',[qrKey])}>直前のQR操作を取消</button>`:''}</div>`;
}
function v187AfterOutPage(item,qrKey){
  qrManualSearchPage('out',item,true,`${item}の出庫を保存しました。同じ品目の別ロットを続けて出庫できます。`);
  const wrap=document.querySelector('.wrap');
  if(!wrap||document.getElementById('v187ContinueCard'))return;
  const results=document.getElementById('qrManualResults');
  if(results)results.insertAdjacentHTML('beforebegin',v187ContinueCardHtml(item,qrKey));
  else wrap.insertAdjacentHTML('beforeend',v187ContinueCardHtml(item,qrKey));
}
const v187QrOperationCompletePageCore=qrOperationCompletePage;
qrOperationCompletePage=function(kind,q,rpc,wastePriceResult){
  const item=v187LastOutItemName,qrKey=String(q||v187LastOutQrKey||'');
  v187LastOutItemName='';
  if(kind==='out'&&item&&canQrOperate())return v187AfterOutPage(item,qrKey);
  return v187QrOperationCompletePageCore(kind,q,rpc,wastePriceResult);
};
window.v187AfterOutPage=v187AfterOutPage;
window.APP_VERSION='v1.187';document.title='SEIKA＋ v1.187 記入票詳細・低評価表示・QR連続出庫版';

/* ===== 月末棚卸し（月末スナップショット固定・確定前後編集・差異のみ月末反映） ===== */
const V188_COUNT_MODE='month_end_v188';
const V188_QR_RPC='v188_apply_month_end_qr_adjustment';
let v188QrLiveMap={};
const V188_REASONS=['数え間違い','伝票未入力','入力漏れ','入力誤り','廃棄未登録','出庫未登録','荷傷み・目減り','移動先違い','その他'];

function v188Session(session){return Boolean(session&&session.monthEndMode===V188_COUNT_MODE)}
function v188Confirmed(session){return v188Session(session)&&Boolean(session.v188ConfirmedAt)}
function v188CanEdit(){return canAdmin()}
function v188CanCount(){return v177Allowed()}
function v188MonthValue(){return monthInputValue(new Date)}
function v188AsOfKey(monthValue){const range=monthRangeFromMonthValue(monthValue),today=todayKey();return range.end>today?today:range.end}
function v188AsOfIso(asOfKey){return `${asOfKey}T23:59:59.000+09:00`}
function v188MonthLabel(monthValue){const range=monthRangeFromMonthValue(monthValue);return `${range.year}年${range.month}月`}
function v188MonthOptions(selected){
  const rows=[],now=new Date();
  for(let i=0;i<12;i++){const d=new Date(now.getFullYear(),now.getMonth()-i,1),value=monthInputValue(d);rows.push(`<option value="${esc(value)}" ${value===selected?'selected':''}>${esc(v188MonthLabel(value))}</option>`)}
  return rows.join('');
}

/* 月末時点の帳簿在庫。基準日23:59:59以前の最新記録だけを採用します。 */
function v188RecordsUntil(asOfKey){return (db.records||[]).filter(record=>record?.createdAt&&ymdKey(new Date(record.createdAt))<=asOfKey)}
function v188LatestUntil(asOfKey){return latestMap(v188RecordsUntil(asOfKey))}
function v188SpecialLatestUntil(tableId,asOfKey){
  const latest={};
  (db.specialRecords||[]).filter(row=>row?.tableId===tableId&&row?.createdAt&&ymdKey(new Date(row.createdAt))<=asOfKey)
    .sort((a,b)=>new Date(a.createdAt||0)-new Date(b.createdAt||0)).forEach(row=>latest[row.itemId]=row);
  return latest;
}
function v188NormalLines(room,asOfKey){
  const rows=[],latest=v188LatestUntil(asOfKey);
  for(const item of allSortedItems()){
    if(coldRoomForNormalItem(item)!==room)continue;
    const record=latest[item.id]||null,qty=yen(Number(record?.total||0));
    if(!(qty>0))continue;
    rows.push({lineId:newId(),type:'normal',itemId:item.id,itemName:item.name,unit:'kg',group:'通常在庫',room,systemQty:qty,snapshotPackKg:countSnapshotPackKg(item,record),snapshotCases:countSnapshotCases(item,record,'kg',qty),snapshotRecordId:record?.id||null,supplier:'',memo:'',status:'unentered'});
  }
  for(const tableId of Object.keys(SPECIAL_STOCK_TABLES)){
    const latestSpecial=v188SpecialLatestUntil(tableId,asOfKey);
    for(const item of specialItems(tableId)){
      if(coldRoomForSpecialItem(tableId,item)!==room)continue;
      const record=latestSpecial[item.id]||null,qty=yen(Number(record?.qty||0));
      if(!(qty>0))continue;
      rows.push({lineId:newId(),type:'special',tableId,itemId:item.id,itemName:item.name,unit:item.unit||'ケース',group:tableId==='kataoka'?'片岡在庫':'その他在庫',room,systemQty:qty,snapshotPackKg:countSnapshotPackKg(item,record),snapshotCases:countSnapshotCases(item,record,item.unit||'ケース',qty),snapshotRecordId:record?.id||null,supplier:'',memo:'',status:'unentered'});
    }
  }
  return rows;
}
async function v188QrLines(room,asOfKey){
  const locations=qrCountLocations(room),{lots,moves}=await v199LoadQrExcelData(),rows=[];
  for(const lot of lots||[]){
    const snapshot=v1101LotSnapshotAtDayEnd(lot,v199QrLotMoves(lot,moves),asOfKey);
    if(!snapshot||!(Number(snapshot.qty)>0))continue;
    const location=String(snapshot.location||lot.storage_location||'').trim();
    if(!locations.includes(location))continue;
    rows.push({lineId:newId(),type:'qr',qrKey:String(lot.qr_key||'').trim(),lotId:lot.id||null,lotNo:lot.lot_no||'',itemName:lot.item_name||'（品名未設定）',containerType:lot.container_type||'',packWeight:lot.pack_weight??'',origin:lot.origin||'',supplier:lot.supplier||'',receivedDate:lot.received_date||'',storageLocation:location,unit:qrCountUnit(lot),systemQty:yen(Number(snapshot.qty)),snapshotTotalWeight:lot.total_weight??null,snapshotInitialQty:lot.received_qty??lot.initial_quantity??null,weightStatus:lot.weight_status||'',memo:'',status:'unentered'});
  }
  return rows.sort((a,b)=>String(a.itemName).localeCompare(String(b.itemName),'ja')||String(a.receivedDate).localeCompare(String(b.receivedDate)));
}

/* 実数・差異理由・対象品目・QR確認状態は編集値として保持し、変更はすべて履歴に残します。 */
function v188SectionLines(session,section){const rows=section==='qr'?session?.qrLines:session?.lines;return Array.isArray(rows)?rows:[]}
function v188Entries(session){return session&&typeof session.v188Entries==='object'&&session.v188Entries?session.v188Entries:{}}
function v188Entry(session,lineId){const entry=v188Entries(session)[String(lineId)];return entry&&typeof entry==='object'?entry:{actualQty:'',reason:'',memo:'',included:true,checked:false}}
function v188Included(session,lineId){return v188Entry(session,lineId).included!==false}
function v188Actual(session,lineId){return v119StrictDecimal(v188Entry(session,lineId).actualQty)}
function v188Applied(session,lineId){const map=session?.v188AppliedActual||{},value=map[String(lineId)];return value===undefined||value===null?null:Number(value)}
function v188BookQty(session,line){const applied=v188Applied(session,line.lineId);return applied===null?yen(Number(line.systemQty||0)):yen(applied)}
function v188Diff(session,line){const actual=v188Actual(session,line.lineId);return actual===null?null:yen(actual-v188BookQty(session,line))}
function v188LiveQty(line){
  if(line.type==='qr'){const lot=v188QrLiveMap[String(line.qrKey||'')];return lot===undefined?null:yen(Number(lot))}
  if(line.type==='special'){const record=(specialLatestMap(line.tableId)||{})[line.itemId];return record?yen(Number(record.qty||0)):0}
  const record=latestRecord(line.itemId);return record?yen(Number(record.total||0)):0;
}
function v188PushHistory(session,line,field,before,after){
  session.v188History=Array.isArray(session.v188History)?session.v188History:[];
  if(String(before??'')===String(after??''))return;
  session.v188History.push({id:newId(),at:nowIso(),by:db.user||'',byId:db.userId||'',phase:v188Confirmed(session)?'確定後':'確定前',lineId:String(line.lineId),itemName:line.itemName||'',lot:line.lotNo||line.qrKey||'',field,before:String(before??''),after:String(after??'')});
  if(session.v188History.length>2000)session.v188History=session.v188History.slice(-2000);
}
function v188SetEntry(session,line,patch){
  session.v188Entries=session.v188Entries&&typeof session.v188Entries==='object'?session.v188Entries:{};
  const key=String(line.lineId),current=v188Entry(session,key),labels={actualQty:'実数',reason:'差異理由',memo:'備考',included:'対象品目',checked:'QRロット確認'};
  const next={...current};
  for(const field of Object.keys(patch)){
    const before=field==='included'?(current.included!==false?'対象':'対象外'):field==='checked'?(current.checked?'確認済み':'未確認'):(current[field]??'');
    const after=field==='included'?(patch[field]!==false?'対象':'対象外'):field==='checked'?(patch[field]?'確認済み':'未確認'):(patch[field]??'');
    v188PushHistory(session,line,labels[field]||field,before,after);
    next[field]=patch[field];
  }
  session.v188Entries[key]=next;
}
function v188Stats(session,section){
  const lines=v188SectionLines(session,section);let entered=0,diff=0,excluded=0,unchecked=0;
  for(const line of lines){
    if(!v188Included(session,line.lineId)){excluded++;continue}
    const actual=v188Actual(session,line.lineId);
    if(actual===null)continue;
    entered++;
    if(v188Diff(session,line))diff++;
    if(section==='qr'&&!v188Entry(session,line.lineId).checked)unchecked++;
  }
  return {total:lines.length,entered,diff,excluded,unchecked,missing:lines.length-excluded-entered};
}

/* Excel・記入票は既存関数をそのまま使うため、v1.192の編集値を既存のエントリ形式へ橋渡しします。 */
const v188EntryMapCore=v177EntryMap;
v177EntryMap=function(session,section){
  if(!v188Session(session))return v188EntryMapCore(session,section);
  return new Map(v188SectionLines(session,section).map(line=>{
    const key=v177LineId(line,section),entry=v188Entry(session,key),actual=v188Actual(session,key),included=entry.included!==false;
    const perWeight=line.type==='qr'&&qrIsLargeContainer(line.containerType)?qrCountLargePerWeight(line):null;
    return [key,{id:key,actualQty:included&&actual!==null?actual:'',supplier:line.supplier||'',memo:[entry.reason?`差異理由：${entry.reason}`:'',entry.memo||'',included?'':'対象外',section==='qr'&&entry.checked?'確認済み':''].filter(Boolean).join(' / '),destination:'',shipTiming:'',actualWeightKg:perWeight!==null&&actual!==null?yen(perWeight*actual):'',weightEntries:undefined,remainderKg:undefined,kgPerUnit:undefined}];
  }));
};

function v188CopySession(value){return value?JSON.parse(JSON.stringify(value)):null}
function v188Resolve(id,fallback){
  const found=countSession(id);
  if(found)return found;
  if(!fallback)return null;
  return v1184UpsertLocalCountSession(v188CopySession(fallback))||countSession(id);
}
async function v188SaveSession(session){
  if(!session?.id)return null;
  session.updatedAt=nowIso();session.updatedBy=db.user;
  v1184UpsertLocalCountSession(session);
  const before=v123AllowInventoryCountGenericWrite;
  v123AllowInventoryCountGenericWrite=true;
  try{await saveCloudNow({skipHistory:true,requireRpc:true})}finally{v123AllowInventoryCountGenericWrite=before}
  const saved=countSession(session.id);
  if(!saved)throw new Error('棚卸しの保存を確認できませんでした。もう一度お試しください。');
  return saved;

}
async function v188LoadQrLive(session){
  const map={};
  try{const lots=await qrSelect('qr_lots','select=qr_key,current_qty&active=eq.true&limit=5000');for(const lot of lots||[])map[String(lot.qr_key||'')]=Number(lot.current_qty||0)}
  catch(error){return null}
  v188QrLiveMap=map;return map;
}

function v188TargetMonthValue(){
  const raw=document.getElementById('v188TargetMonth')?.value||v188MonthValue();
  return /^\d{4}-\d{2}$/.test(raw)?raw:'';
}
const V188_CLOSED_STATUS=['completed','confirmed','test_confirmed','reversed','cancelled'];
function v188BlockingSession(room){
  return countSessions().find(session=>String(session?.room||'')===room&&!v188Session(session)&&!V188_CLOSED_STATUS.includes(String(session?.status||'')))||null;
}
async function v188StartOne(room,monthValue){
  const asOfKey=v188AsOfKey(monthValue);
  await v186ProtectPending();await loadCloud();
  const duplicate=countSessions().find(session=>v188Session(session)&&session.room===room&&session.targetMonth===monthValue&&!['cancelled'].includes(String(session.status||'')));
  if(duplicate)return {room,skipped:true,message:`${roomLabel(room)}の${v188MonthLabel(monthValue)}の棚卸しは既にあります。`};
  const blocking=v188BlockingSession(room);
  if(blocking)throw new Error(`${roomLabel(room)}に進行中の旧棚卸し（${blocking.countNo||blocking.id}）が残っているため開始できません。棚卸しモード下部の「旧棚卸し履歴」でその棚卸しを破棄または取消してから、もう一度開始してください。`);
  const others=countSessions().map(v188CopySession).filter(Boolean);
  const lines=v188NormalLines(room,asOfKey),qrLines=await v188QrLines(room,asOfKey),at=nowIso();
  await v188LoadQrLive();
  const session={id:qrInventoryUuid(),inventoryCountMode:V177_COUNT_MODE,monthEndMode:V188_COUNT_MODE,targetMonth:monthValue,asOfKey,countNo:`${monthValue.replace('-','')}-${room==='room2'?'R2':'R3'}-${String(countSessions().filter(s=>s.room===room).length+1).padStart(3,'0')}`,room,roomLabel:roomLabel(room),status:'counting',startedAt:at,startedBy:db.user,startedById:db.userId,updatedAt:at,updatedBy:db.user,revision:1,normalStatus:'counting',qrCountStatus:'counting',lines,qrLines,v188Entries:{},v188History:[],v188AppliedActual:{},v188Confirmations:[],v177SnapshotRule:`${v188MonthLabel(monthValue)}末（基準日${asOfKey}）時点の在庫`,v177QrSnapshotAt:at,inventoryApplied:false,qrApplied:false};
  for(const line of [...lines,...qrLines]){const live=v188LiveQty(line);session.v188Entries[String(line.lineId)]={actualQty:live===null?'':String(live),reason:'',memo:'',included:true,checked:false}}
  session.v188ImportedAt=at;
  const answer=await callRpc(V177_CREATE_RPC,{p_id:STATE_ID,p_session:session,p_operation_id:qrInventoryUuid()});
  if(answer?.conflict)throw new Error(answer.message||'別端末で更新されています。');
  if(!answer?.ok)throw new Error(answer?.message||'棚卸しを開始できませんでした。');
  const id=String(answer.sessionId||session.id);session.id=id;
  const local={...session,revision:Number(session.revision||0)+1};
  await loadCloud();
  /* 他の冷蔵庫の棚卸しが消えていないか確認し、消えていれば戻してから保存する。 */
  let repaired=0;
  for(const backup of others){if(backup?.id&&!countSession(backup.id)){v1184UpsertLocalCountSession(backup);repaired++}}
  if(!countSession(id)){v1184UpsertLocalCountSession(local);repaired++}
  if(repaired)await v188SaveSession(countSession(id)||local);
  /* サーバーに本当に残ったかを読み直して確認する。消えていれば一度だけ保存し直す。 */
  await loadCloud();
  if(!countSession(id)){
    v1184UpsertLocalCountSession(local);
    await v188SaveSession(countSession(id)||local);
    await loadCloud();
    if(!countSession(id))throw new Error(`${roomLabel(room)}の棚卸しをサーバーに保存できませんでした。通信状態を確認してもう一度お試しください。`);
  }
  return {room,id,lines:lines.length,qrLines:qrLines.length,repaired,message:`${roomLabel(room)}の${v188MonthLabel(monthValue)}末棚卸しを開始しました（通常 ${lines.length}件 / QR ${qrLines.length}件）。`};
}
async function v188Start(room){
  if(!v188CanCount())return alert('棚卸しを操作できるのは管理者・青果社員のみです。');
  if(!validColdRoom(room))return alert('冷蔵庫を選択してください。');
  const monthValue=v188TargetMonthValue();
  if(!monthValue)return alert('対象月を選択してください。');
  if(monthRangeFromMonthValue(monthValue).start>todayKey())return alert('未来の月は棚卸しできません。');
  v161ShowProcessing(`${v188MonthLabel(monthValue)}末時点の在庫を固定しています`);
  try{
    const result=await v188StartOne(room,monthValue);
    return inventoryCountHome(result.message);
  }catch(error){alert(`棚卸しを開始できませんでした。\n${v161ErrorText(error)}\n\n入力中・未同期データは削除していません。`);return inventoryCountHome()}
  finally{v161HideProcessing()}
}
async function v188StartBoth(){
  if(!v188CanCount())return alert('棚卸しを操作できるのは管理者・青果社員のみです。');
  const monthValue=v188TargetMonthValue();
  if(!monthValue)return alert('対象月を選択してください。');
  if(monthRangeFromMonthValue(monthValue).start>todayKey())return alert('未来の月は棚卸しできません。');
  if(!confirm(`第2冷蔵庫と第3冷蔵庫の${v188MonthLabel(monthValue)}末棚卸しをまとめて開始します。\n\n2件は別々の棚卸しとして進行し、片方を確定しても もう片方はそのまま残ります。\n実行しますか？`))return;
  const messages=[],failed=[];
  try{
    for(const room of ['room2','room3']){
      v161ShowProcessing(`${roomLabel(room)}の${v188MonthLabel(monthValue)}末在庫を固定しています`);
      try{const result=await v188StartOne(room,monthValue);messages.push(result.message)}
      catch(error){failed.push(`${roomLabel(room)}：${v161ErrorText(error)}`)}
    }
  }finally{v161HideProcessing()}
  if(failed.length)alert(`開始できなかった冷蔵庫があります。\n\n${failed.join('\n\n')}\n\n開始できた分と、入力中・未同期データは削除していません。`);
  const summary=[...messages,...failed.map(text=>`開始できませんでした → ${text}`)].join(' / ');
  return inventoryCountHome(summary||'棚卸しを開始できませんでした。');
}
const V188_PRINT_BAR=`<style>.v188Bar{position:sticky;top:0;left:0;right:0;z-index:99;display:flex;gap:10px;padding:10px 12px;background:#0f2747;box-shadow:0 2px 8px rgba(0,0,0,.25)}.v188Bar button{flex:1;min-height:44px;border:0;border-radius:999px;font-size:16px;font-weight:700;color:#0f2747;background:#dbe6f5}.v188Bar button.pr{background:#ea8b1f;color:#fff}@media print{.v188Bar{display:none!important}}</style>
<div class="v188Bar"><button type="button" onclick="v188BarClose()">閉じる</button><button type="button" class="pr" onclick="window.print()">印刷</button></div>
<script>function v188BarClose(){try{window.close()}catch(e){}setTimeout(function(){if(!window.closed){try{history.back()}catch(e){}}},150)}<\/script>`;
function v188PrintHtml(target,normal,qr,mode){
  const html=v186PrintDocument(target,normal,qr,mode);
  return html.includes('<body>')?html.replace('<body>','<body>'+V188_PRINT_BAR):html;
}
function v188Print(id,mode='all'){
  const session=countSession(id);if(!session||!v188Session(session))return alert('棚卸しが見つかりません。');
  const normal=v188SectionLines(session,'normal'),qr=v188SectionLines(session,'qr');
  if(!normal.length&&!qr.length)return alert('記入票の明細がありません。棚卸しカードの「月末明細を再作成」を押してから印刷してください。');
  const win=window.open('','_blank');if(!win)return alert('印刷画面を開けませんでした。ポップアップ許可を確認してください。');
  const target={...session,countNo:`${session.countNo} / ${v188MonthLabel(session.targetMonth)}末（基準日${session.asOfKey}）`};
  win.document.open();win.document.write(v188PrintHtml(target,normal,qr,mode));win.document.close();win.focus();
}
async function v188Repair(id){
  const session=countSession(id);if(!session||!v188Session(session))return inventoryCountHome('棚卸しが見つかりません。');
  if(!v188CanCount())return alert('操作できるのは管理者・青果社員のみです。');
  if(!confirm(`${v188MonthLabel(session.targetMonth)}末（基準日${session.asOfKey}）の明細を作り直します。\n\n入力済みの実数・差異理由は、同じ品目・同じロットに引き継ぎます。\n実行しますか？`))return;
  v161ShowProcessing('月末時点の明細を作り直しています');
  try{
    const backup=v188CopySession(session);
    await loadCloud();
    const target=v188Resolve(id,backup)||session,asOfKey=target.asOfKey||v188AsOfKey(target.targetMonth);
    const oldEntries=v188Entries(target),keyOf=line=>line.type==='qr'?`qr:${line.qrKey}${line.grade?':'+line.grade:''}`:line.type==='special'?`sp:${line.tableId}:${line.itemId}`:`nm:${line.itemId}`;
    const carry={};for(const line of [...v188SectionLines(target,'normal'),...v188SectionLines(target,'qr')]){const entry=oldEntries[String(line.lineId)];if(entry)carry[keyOf(line)]=entry}
    const lines=v188NormalLines(target.room,asOfKey),qrLines=await v188QrLines(target.room,asOfKey);
    if(!lines.length&&!qrLines.length)throw new Error(`${v188MonthLabel(target.targetMonth)}末時点の在庫が見つかりませんでした。`);
    await v188LoadQrLive();
    const entries={};
    for(const line of [...lines,...qrLines]){const prev=carry[keyOf(line)],live=v188LiveQty(line);entries[String(line.lineId)]=prev?{...prev}:{actualQty:live===null?'':String(live),reason:'',memo:'',included:true,checked:false}}
    target.lines=lines;target.qrLines=qrLines;target.v188Entries=entries;target.v188ImportedAt=nowIso();
    await v188SaveSession(target);
    return inventoryCountHome(`月末明細を作り直しました（通常 ${lines.length}件 / QR ${qrLines.length}件）。記入票を印刷できます。`);
  }catch(error){alert(`明細を作り直せませんでした。\n${v161ErrorText(error)}`);return inventoryCountHome()}
  finally{v161HideProcessing()}
}

async function v188ImportLive(id,section){
  const session=countSession(id);if(!session||!v188Session(session))return;
  if(!v188CanCount())return alert('取り込みできるのは管理者・青果社員のみです。');
  v161ShowProcessing('現在の在庫を取り込んでいます');
  try{
    const backup=v188CopySession(session);
    await loadCloud();if(section==='qr'&&!await v188LoadQrLive())throw new Error('QR在庫を取得できませんでした。');
    const target=v188Resolve(id,backup);
    if(!target)throw new Error('棚卸しを読み込めませんでした。');
    let changed=0;
    for(const line of v188SectionLines(target,section)){
      const live=v188LiveQty(line);if(live===null)continue;
      if(String(v188Entry(target,line.lineId).actualQty??'')===String(live))continue;
      v188SetEntry(target,line,{actualQty:String(live)});changed++;
    }
    target.v188ImportedAt=nowIso();
    await v188SaveSession(target);
    return v188CountPage(id,section,`現在の在庫を実数へ取り込みました（${changed}件更新）。`);
  }catch(error){alert(`取り込みできませんでした。\n${v161ErrorText(error)}`);return v188CountPage(id,section)}
  finally{v161HideProcessing()}
}

function v188ReadDom(session,section){
  for(const line of v188SectionLines(session,section)){
    const key=String(line.lineId),patch={actualQty:v171Value(`v188_qty_${key}`),reason:v171Value(`v188_reason_${key}`),memo:v171Value(`v188_memo_${key}`),included:!!document.getElementById(`v188_inc_${key}`)?.checked};
    if(section==='qr')patch.checked=!!document.getElementById(`v188_chk_${key}`)?.checked;
    v188SetEntry(session,line,patch);
  }
}
async function v188Save(id,section){
  const session=countSession(id);if(!session||!v188Session(session))return;
  if(v188Confirmed(session)&&!v188CanEdit())return alert('確定後に編集できるのは管理者のみです。');
  if(!v188CanCount())return alert('編集できるのは管理者・青果社員のみです。');
  v161ShowProcessing('棚卸しの入力を保存しています');
  try{
    v188ReadDom(session,section);
    if(!countSession(id))v1184UpsertLocalCountSession(v188CopySession(session));
    session[section==='qr'?'qrCountStatus':'normalStatus']='entered';
    await v188SaveSession(session);
    return v188CountPage(id,section,'保存しました。');
  }catch(error){alert(`保存できませんでした。\n${v161ErrorText(error)}\n\n入力内容は端末に保持しています。`);return v188CountPage(id,section)}
  finally{v161HideProcessing()}
}

function v188RowHtml(session,line,section,editable){
  const key=String(line.lineId),entry=v188Entry(session,key),actual=v188Actual(session,key),diff=v188Diff(session,line),book=v188BookQty(session,line),included=entry.included!==false;
  const unit=esc(line.unit||''),diffText=diff===null?'未入力':`${diff>0?'+':''}${fmt(diff)} ${unit}`;
  const diffColor=diff===null?'#6b7280':diff<0?'#dc2626':diff>0?'#ea580c':'#16a34a';
  const pack=section==='qr'?v187QrPackText(line):v187NormalPackText(line);
  return `<div class="box" style="margin:9px 0;${included?'':'opacity:.55'}"><div class="itemHead"><div><b>${esc(line.itemName||'')}</b><div class="small">${esc(line.group||line.lotNo||line.qrKey||'')}${pack?` / ${esc(pack)}`:''}${line.receivedDate?` / 入荷 ${esc(line.receivedDate)}`:''}</div></div><span class="badge ${diff===null?'unset':diff?'excess':'normal'}" style="color:${diffColor}">${esc(diffText)}</span></div>${section==='qr'&&!v188Confirmed(session)?'<div class="small" style="margin-top:6px">確定のときに、最新の出庫を含めて帳簿を計算し直します。最後に入力した実数が月末の在庫になります。</div>':''}
<div class="row" style="margin-top:8px"><div><label class="label">${section==='qr'?'月末帳簿（開始時）':'月末帳簿（固定）'}</label><div class="input" style="background:#f3f4f6">${fmt(book)} ${unit}</div></div><div><label class="label">実数</label><input id="v188_qty_${esc(key)}" class="input" inputmode="decimal" value="${esc(entry.actualQty??'')}" ${editable?'':'disabled'}></div></div>
<label class="label" style="margin-top:8px">差異理由</label><input id="v188_reason_${esc(key)}" class="input" list="v188ReasonList" maxlength="120" value="${esc(entry.reason||'')}" placeholder="${diff?'差異がある場合は理由を入力':'任意'}" ${editable?'':'disabled'}>
<label class="label" style="margin-top:8px">備考</label><input id="v188_memo_${esc(key)}" class="input" maxlength="200" value="${esc(entry.memo||'')}" ${editable?'':'disabled'}>
<div class="mini" style="margin-top:8px"><label class="switch"><input id="v188_inc_${esc(key)}" type="checkbox" ${included?'checked':''} ${editable?'':'disabled'}> 棚卸し対象</label>${section==='qr'?`<label class="switch"><input id="v188_chk_${esc(key)}" type="checkbox" ${entry.checked?'checked':''} ${editable?'':'disabled'}> ロット確認済み</label>`:''}</div></div>`;
}
function v188CountPage(id,section='normal',msg=''){
  const session=countSession(id);if(!session||!v188Session(session))return inventoryCountHome('棚卸しが見つかりません。');
  if(!v188CanCount())return home();
  setScreen('v188CountPage',[id,section,msg]);
  const confirmed=v188Confirmed(session),editable=confirmed?v188CanEdit():v188CanCount(),stats=v188Stats(session,section);
  const lines=v188SectionLines(session,section);
  const filter=`<div class="card"><div class="countStatGrid"><div class="countStat"><span class="small">対象</span><b>${stats.total-stats.excluded}</b></div><div class="countStat"><span class="small">入力済み</span><b>${stats.entered}</b></div><div class="countStat"><span class="small">未入力</span><b>${stats.missing}</b></div><div class="countStat"><span class="small">差異あり</span><b>${stats.diff}</b></div>${section==='qr'?`<div class="countStat"><span class="small">未確認ロット</span><b>${stats.unchecked}</b></div>`:''}</div></div>`;
  const notice=confirmed?`<div class="warn"><b>確定済みの棚卸しです</b><div class="small">${v188CanEdit()?'管理者は実数・差異理由・対象品目・確認状態を編集できます。保存後に「差異を追加反映」を押すと、変更分だけを対象月末日の棚卸し調整として追加します。':'確定後の編集は管理者のみです。'}</div></div>`:'';
  pageShell(`${section==='qr'?'QR在庫':'通常在庫'}の棚卸し`,`${esc(session.countNo)} / ${esc(v188MonthLabel(session.targetMonth))}末（基準日${esc(session.asOfKey)}）`,
    `${okHtml(msg)}${notice}<datalist id="v188ReasonList">${V188_REASONS.map(reason=>`<option value="${esc(reason)}">`).join('')}</datalist>${filter}
<div class="card"><b>現在の在庫から実数を取り込む</b><div class="small" style="margin-top:6px">通常在庫入力・QR出庫で入力・訂正した内容を実数欄へ反映します。手入力した値も上書きされるため、必要な行だけ入力し直してください。</div><div class="small" style="margin-top:6px">前回取込：${esc(session.v188ImportedAt?dt(session.v188ImportedAt):'－')}</div>${editable?`<button class="btn blue" style="width:100%;margin-top:9px" ${seikaEventAttrs('click','v188ImportLive',[id,section])}>現在の在庫を実数へ取り込む</button>`:''}</div>
<div class="card">${lines.map(line=>v188RowHtml(session,line,section,editable)).join('')||'<div class="small">対象在庫はありません。</div>'}</div>
${editable?`<button class="btn green" style="width:100%;margin-top:10px" ${seikaEventAttrs('click','v188Save',[id,section])}>入力内容を保存</button>`:''}
<button class="btn btn2" style="width:100%;margin-top:10px" ${seikaEventAttrs('click','inventoryCountHome',[])}>棚卸しモードへ戻る</button>`);
}

function v188HistoryPage(id){
  const session=countSession(id);if(!session||!v188Session(session))return inventoryCountHome('棚卸しが見つかりません。');
  if(!v188CanCount())return home();
  setScreen('v188HistoryPage',[id]);
  const rows=(Array.isArray(session.v188History)?session.v188History:[]).slice().reverse();
  pageShell('棚卸しの編集履歴',`${esc(session.countNo)} / ${esc(v188MonthLabel(session.targetMonth))}末`,
    `<div class="card"><b>編集履歴 ${rows.length}件</b><div class="small" style="margin-top:6px">実数・差異理由・対象品目・QRロット確認状態の変更をすべて記録しています。</div></div>
<div class="card"><div class="weeklyWrap"><table class="table"><thead><tr><th>日時</th><th>操作者</th><th>時点</th><th>品名・ロット</th><th>項目</th><th>変更前</th><th>変更後</th></tr></thead><tbody>${rows.map(row=>`<tr><td>${esc(dt(row.at))}</td><td>${esc(row.by||'')}</td><td>${esc(row.phase||'')}</td><td>${esc(row.itemName||'')}${row.lot?`<br><span class="small">${esc(row.lot)}</span>`:''}</td><td>${esc(row.field||'')}</td><td>${esc(row.before||'（空欄）')}</td><td>${esc(row.after||'（空欄）')}</td></tr>`).join('')||'<tr><td colspan="7">編集履歴はまだありません。</td></tr>'}</tbody></table></div></div>
<button class="btn btn2" style="width:100%;margin-top:10px" ${seikaEventAttrs('click','inventoryCountHome',[])}>棚卸しモードへ戻る</button>`);
}

/* 確定：差異がある行だけを、対象月末日の「棚卸し調整」として在庫履歴へ反映します。 */
async function v188QrBooksNow(session){
  const lines=v188SectionLines(session,'qr'),books={};if(!lines.length)return books;
  const {lots,moves}=await v199LoadQrExcelData(),byKey=new Map((lots||[]).map(lot=>[String(lot.qr_key||'').trim(),lot])),graded=[];
  for(const line of lines){
    const lot=byKey.get(String(line.qrKey||'').trim());if(!lot)continue;
    if(line.grade){graded.push({line,lot});continue}
    const snapshot=v1101LotSnapshotAtDayEnd(lot,v199QrLotMoves(lot,moves),session.asOfKey);
    books[String(line.lineId)]=yen(Number(snapshot?.qty||0));
  }
  if(graded.length){
    await v1310LoadGrades(true);
    const gradeMoves=await v1310GradeMovesAfter([...new Set(graded.map(row=>String(row.lot.id)))],session.asOfKey);
    for(const {line,lot} of graded){
      const list=v1310GradeMap.get(String(lot.id));
      if(!list)throw new Error(`QRロット ${line.lotNo||line.qrKey} の規格を読み込めませんでした。通信状況を確認してから、もう一度確定してください。`);
      books[String(line.lineId)]=yen(Number(v1310GradeQtyAt(list,gradeMoves,lot.id)[line.grade]||0));
    }
  }
  return books;
}
function v188PendingRows(session,qrBooks=null){
  const rows=[];
  for(const section of ['normal','qr'])for(const line of v188SectionLines(session,section)){
    if(!v188Included(session,line.lineId))continue;
    const actual=v188Actual(session,line.lineId);if(actual===null)continue;
    const fresh=section==='qr'&&qrBooks?qrBooks[String(line.lineId)]:undefined;
    const book=fresh===undefined?v188BookQty(session,line):fresh,diff=yen(actual-book);if(!diff)continue;
    rows.push({section,line,actual,book,diff,entry:v188Entry(session,line.lineId)});
  }
  return rows;
}
async function v188Confirm(id){
  let session=countSession(id);
  if(!session||!v188Session(session))return alert('棚卸しが見つかりません。');
  if(!v188CanCount())return alert('確定できるのは管理者・青果社員のみです。');
  if(v188Confirmed(session)&&!v188CanEdit())return alert('確定後の追加反映は管理者のみです。');
  if(stateVersion===null)return alert('棚卸し確定には競合防止RPCが必要です。同期状態を確認してください。');
  const stats=v188Stats(session,'qr');
  if(stats.unchecked&&!confirm(`QRロットに未確認が ${stats.unchecked}件あります。\nこのまま確定しますか？`))return;
  let qrBooks;
  v161ShowProcessing('最新の出庫を含めて、QRロットの月末の帳簿を計算しています');
  try{qrBooks=await v188QrBooksNow(session)}catch(error){return alert(`QRロットの帳簿を計算できませんでした。\n${v161ErrorText(error)}`)}finally{v161HideProcessing()}
  const qrRecalc=v188SectionLines(session,'qr').filter(line=>qrBooks[String(line.lineId)]!==undefined&&qrBooks[String(line.lineId)]!==v188BookQty(session,line)).length;
  const qrNote=v188SectionLines(session,'qr').length?`\n\nQRロットは、最新の出庫を含めて月末の帳簿を計算し直し、最後に入力した実数を月末の在庫にします。${qrRecalc?`\n（開始時の帳簿から変わった行：${qrRecalc}件）`:''}`:'';
  const alreadyConfirmed=v188Confirmed(session),rows=v188PendingRows(session,qrBooks);
  if(!rows.length&&alreadyConfirmed)return alert('追加で反映する差異はありません。');
  const missing=v188Stats(session,'normal').missing+v188Stats(session,'qr').missing;
  if(missing&&!confirm(`実数が未入力の行が ${missing}件あります。\nこのまま確定しますか？`))return;
  const noReason=rows.filter(row=>!String(row.entry.reason||'').trim()).length;
  if(noReason&&!confirm(`差異理由が未入力の行が ${noReason}件あります。\nこのまま確定しますか？`))return;
  if(!confirm(rows.length
    ?`${v188MonthLabel(session.targetMonth)}末（基準日${session.asOfKey}）の棚卸しを確定します。\n\n差異 ${rows.length}件を、対象月末日の「棚卸し調整」として在庫履歴へ反映します。\n差異がない品目・対象外の品目は履歴を作りません。${qrNote}\n\n実行しますか？`
    :`${v188MonthLabel(session.targetMonth)}末（基準日${session.asOfKey}）の棚卸しを、差異なしで確定します。\n\n帳簿と実数が一致しているため、在庫履歴は作りません。\n棚卸しの実施記録として確定し、Excelを出力できるようになります。\n\n実行しますか？`))return;
  v161ShowProcessing('未同期データを確認し、差異を反映しています');
  const beforeDb=JSON.parse(JSON.stringify(db)),beforeVersion=stateVersion;
  try{
    const backup=v188CopySession(session);
    await v186ProtectPending();await loadCloud();
    session=v188Resolve(id,backup);if(!session||!v188Session(session))throw new Error('棚卸しが見つかりません。');
    const targets=v188PendingRows(session,await v188QrBooksNow(session));
    if(!targets.length&&v188Confirmed(session))throw new Error('追加で反映する差異はありません。');
    const at=v188AsOfIso(session.asOfKey),operation=`v188_${session.id}_${newId()}`,sequence=(Array.isArray(session.v188Confirmations)?session.v188Confirmations.length:0)+1;
    let qrApplied=0;
    for(const row of targets.filter(target=>target.section==='qr')){
      const answer=await callRpc(V188_QR_RPC,{p_qr_key:row.line.qrKey,p_operation_id:qrInventoryStableUuid(`${session.id}:${row.line.lineId}:${sequence}`,'v188_qr_adjust'),p_target_month:session.targetMonth,p_as_of_date:session.asOfKey,p_book_qty:row.book,p_actual_qty:row.actual,p_reason:String(row.entry.reason||'')||null,p_memo:String(row.entry.memo||'')||null,p_session_id:session.id,p_count_no:session.countNo});
      if(!answer?.ok)throw new Error(answer?.message||`QRロット ${row.line.lotNo||row.line.qrKey} の調整に失敗しました。`);
      if(!answer.skipped&&!answer.idempotent)qrApplied++;
    }
    const latestNormal=v188LatestUntil(session.asOfKey),latestSpecial={};
    for(const tableId of Object.keys(SPECIAL_STOCK_TABLES))latestSpecial[tableId]=v188SpecialLatestUntil(tableId,session.asOfKey);
    let normalApplied=0,specialApplied=0;
    for(const row of targets.filter(target=>target.section==='normal')){
      const line=row.line,memo=`${v188MonthLabel(session.targetMonth)}末棚卸し ${session.countNo}${row.entry.reason?` / 理由：${row.entry.reason}`:''}${row.entry.memo?` / ${row.entry.memo}`:''}`;
      if(line.type==='normal'){
        const previous=latestNormal[line.itemId]||null,setting=db.settings[line.itemId]||{};
        const record={id:newId(),kind:'棚卸し調整',itemId:line.itemId,itemName:line.itemName,total:row.actual,setting:{...setting},status:judge(row.actual,setting),lines:countLinesWithAdjustment(previous,row.actual,line.itemId),user:db.user,role:db.role,createdAt:at,stocktakeSessionId:session.id,stocktakeLineId:line.lineId,operationId:operation,v188TargetMonth:session.targetMonth,v188AsOfKey:session.asOfKey};
        db.records.push(record);
        db.movements.push({id:newId(),recordId:record.id,itemId:line.itemId,itemName:line.itemName,type:'棚卸し調整',beforeTotal:row.book,afterTotal:row.actual,diffKg:row.diff,pack:null,cases:null,memo,user:db.user,role:db.role,createdAt:at,stocktakeSessionId:session.id,stocktakeLineId:line.lineId,operationId:operation});
        latestNormal[line.itemId]=record;normalApplied++;
      }else{
        db.specialRecords=db.specialRecords||[];
        const record={id:newId(),tableId:line.tableId,itemId:line.itemId,itemName:line.itemName,qty:row.actual,unit:line.unit,memo,kind:'棚卸し調整',user:db.user,role:db.role,createdAt:at,stocktakeSessionId:session.id,stocktakeLineId:line.lineId,operationId:operation,beforeQty:row.book,applyDifference:row.diff,v188TargetMonth:session.targetMonth,v188AsOfKey:session.asOfKey};
        db.specialRecords.push(record);latestSpecial[line.tableId][line.itemId]=record;specialApplied++;
      }
    }
    session.v188AppliedActual=session.v188AppliedActual&&typeof session.v188AppliedActual==='object'?session.v188AppliedActual:{};
    for(const row of targets)session.v188AppliedActual[String(row.line.lineId)]=row.actual;
    session.v188Confirmations=Array.isArray(session.v188Confirmations)?session.v188Confirmations:[];
    session.v188Confirmations.push({at:nowIso(),by:db.user||'',byId:db.userId||'',sequence,normalApplied,specialApplied,qrApplied,operationId:operation,recordedAt:at});
    session.v188ConfirmedAt=session.v188ConfirmedAt||nowIso();
    session.v188ConfirmedBy=session.v188ConfirmedBy||db.user||'';
    session.status='completed';session.normalStatus='submitted';session.qrCountStatus='submitted';
    session.updatedAt=nowIso();session.updatedBy=db.user;
    await v188SaveSession(session);v188PersistDb();
    return inventoryCountHome(targets.length
      ?`${v188MonthLabel(session.targetMonth)}末の棚卸しを確定しました。通常 ${normalApplied}件 / その他・片岡 ${specialApplied}件 / QR ${qrApplied}件を対象月末日で反映しました。`
      :`${v188MonthLabel(session.targetMonth)}末の棚卸しを差異なしで確定しました。在庫履歴は作成していません。Excelを出力できます。`);
  }catch(error){
    db=beforeDb;stateVersion=beforeVersion;v188PersistDb();setSyncState('失敗');
    alert(`棚卸しを確定できませんでした。\n${v161ErrorText(error)}\n\n通常在庫の反映は取り消しました。QR在庫は反映済みの分だけ残ることがあるため、QRロット一覧で確認してください。`);
    return inventoryCountHome();
  }finally{v161HideProcessing()}
}

function v188DownloadExcel(id){
  const session=countSession(id);if(!session||!v188Session(session))return v186DownloadExcel(id);
  if(!ensureXlsxReady())return;
  const target={...session,countNo:`${session.countNo}（${v188MonthLabel(session.targetMonth)}末 基準日${session.asOfKey}）`,v177AppliedAt:session.v188ConfirmedAt||null,v177CompletedAt:session.v188ConfirmedAt||null};
  const wb=XLSX.utils.book_new(),normal=v177AddDetailSheet(wb,`${session.roomLabel} 通常在庫`,`${session.roomLabel} 通常在庫 ${v188MonthLabel(session.targetMonth)}末棚卸し`,target,'normal'),qr=v177AddDetailSheet(wb,`${session.roomLabel} QR在庫`,`${session.roomLabel} QR在庫 ${v188MonthLabel(session.targetMonth)}末棚卸し`,target,'qr');
  v177AddSummarySheet(wb,target,normal,qr);
  const note=`${v188MonthLabel(session.targetMonth)}末時点（基準日${session.asOfKey}）／差異のみ月末日で在庫反映`;
  for(const sheetName of [normal.name,qr.name]){const sheet=wb.Sheets[sheetName];if(sheet?.B5)sheet.B5.v=note}
  downloadWorkbookXlsx(wb,`棚卸し_${String(session.targetMonth||'').replace('-','')}_${String(session.roomLabel||'冷蔵庫').replace(/[\\/:*?"<>|]/g,'_')}_${String(session.countNo||'').replace(/[\\/:*?"<>|]/g,'_')}.xlsx`);
  return inventoryCountHome('棚卸しExcelを出力しました。単価欄へ入力すると金額と合計が計算されます。');
}

function v188SessionCard(session){
  const confirmed=v188Confirmed(session),normal=v188Stats(session,'normal'),qr=v188Stats(session,'qr'),pending=v188PendingRows(session).length;
  return `<div class="card"><div class="itemHead"><div><b>${esc(session.countNo)}</b><div class="small">${esc(session.roomLabel)} / ${esc(v188MonthLabel(session.targetMonth))}末（基準日${esc(session.asOfKey)}）<br>開始：${esc(session.startedAt?dt(session.startedAt):'－')}${confirmed?` / 確定：${esc(dt(session.v188ConfirmedAt))}`:''}</div></div><span class="badge ${confirmed?'normal':'unset'}">${confirmed?'確定済み':'確認・入力中'}</span></div>
<div class="notice" style="margin-top:10px"><b>1. 記入票を印刷</b><div class="small">${esc(v188MonthLabel(session.targetMonth))}末時点の帳簿在庫で作成します（量目・仕入先入り）。</div><div class="mini" style="margin-top:8px"><button class="btn orange" ${seikaEventAttrs('click','v188Print',[session.id,'all'])}>通常・QR記入票を印刷</button><button class="btn btn2" ${seikaEventAttrs('click','v188Print',[session.id,'normal'])}>通常だけ</button><button class="btn btn2" ${seikaEventAttrs('click','v188Print',[session.id,'qr'])}>QRだけ</button></div></div>
<div class="notice" style="margin-top:10px"><b>2. 実数・差異理由を確認</b><div class="small">通常 ${normal.entered}/${normal.total-normal.excluded}入力・差異${normal.diff} / QR ${qr.entered}/${qr.total-qr.excluded}入力・差異${qr.diff}・未確認${qr.unchecked}</div><div class="mini" style="margin-top:8px"><button class="btn green" ${seikaEventAttrs('click','v188CountPage',[session.id,'normal'])}>通常在庫を確認・編集</button><button class="btn blue" ${seikaEventAttrs('click','v188CountPage',[session.id,'qr'])}>QR在庫を確認・編集</button></div><div class="mini" style="margin-top:8px"><button class="btn btn2" ${seikaEventAttrs('click','v186OpenNormal',[session.room])}>通常在庫入力を開く</button><button class="btn btn2" ${seikaEventAttrs('click','v186OpenQrOut',[])}>QR出庫を開く</button><button class="btn btn2" ${seikaEventAttrs('click','v186OpenQrAdjust',[])}>QR在庫調整を開く</button></div></div>
<div class="notice" style="margin-top:10px"><b>3. 差異を対象月末で確定</b><div class="small">未反映の差異 ${pending}件。差異がある品目だけを${esc(session.asOfKey)}付の棚卸し調整として反映します。</div>${v188CanCount()&&(!confirmed||v188CanEdit())?`<button class="btn orange" style="width:100%;margin-top:8px" ${seikaEventAttrs('click','v188Confirm',[session.id])} ${confirmed&&!pending?'disabled':''}>${confirmed?'差異を追加反映':pending?'棚卸しを確定して差異を反映':'差異なしで棚卸しを確定'}</button>`:''}${confirmed||pending?'':'<div class="small" style="margin-top:6px">帳簿と実数が一致しています。このまま確定すると在庫履歴は作らず、棚卸しの実施記録として残ります。</div>'}</div>
<div class="mini" style="margin-top:10px">${confirmed?`<button class="btn orange" ${seikaEventAttrs('click','v188DownloadExcel',[session.id])}>Excelを出力</button>`:''}<button class="btn btn2" ${seikaEventAttrs('click','v188HistoryPage',[session.id])}>編集履歴（${(session.v188History||[]).length}）</button>${confirmed?'':`<button class="btn btn2" ${seikaEventAttrs('click','v188Repair',[session.id])}>月末明細を再作成</button>`}</div>${(!normal.total&&!qr.total)?'<div class="warn" style="margin-top:10px"><b>明細がありません</b><div class="small">「月末明細を再作成」を押すと、対象月末時点の在庫から作り直します。</div></div>':''}</div>`;
}
function v188Home(msg=''){
  setScreen('inventoryCountHome',[msg]);if(!v177Allowed())return home();
  const sessions=countSessions().slice().sort((a,b)=>new Date(b.updatedAt||b.startedAt||0)-new Date(a.updatedAt||a.startedAt||0));
  const active=sessions.filter(session=>v188Session(session)&&!v188Confirmed(session)),history=sessions.filter(session=>v188Session(session)&&v188Confirmed(session)),legacy=sessions.filter(session=>!v188Session(session));
  const month=v188MonthValue();
  pageShell('棚卸しモード',`${esc(v119RoleLabel())} / v1.199`,
    `${okHtml(msg)}<div class="card notice"><b>月末棚卸しの流れ</b><div class="small">①対象月と冷蔵庫を選んで開始（その時点で対象月末の在庫が固定されます）　②記入票を印刷して現物確認　③通常在庫入力・QR画面で入力／棚卸し画面で実数・差異理由を編集　④確定すると差異分だけを対象月末日の棚卸し調整として反映　⑤Excel出力（単価欄あり）<br>開始後は、翌日以降の入庫・出庫・調整があっても対象月末の帳簿在庫は変わりません。</div></div>
${['room2','room3'].map(room=>{const blocking=v188BlockingSession(room);return blocking?`<div class="card warn"><b>${esc(roomLabel(room))}は今のままでは開始できません</b><div class="small" style="margin-top:6px">進行中の旧棚卸し（${esc(blocking.countNo||blocking.id)} / 状態：${esc(countStatusLabel(blocking))}）が残っています。「棚卸し履歴」を開き、旧棚卸しの中からその棚卸しを破棄または取消すると開始できます。</div></div>`:''}).join('')}
<div class="card"><b>新しい棚卸しを開始</b><label class="label" style="margin-top:8px">対象月</label><select id="v188TargetMonth" class="input">${v188MonthOptions(month)}</select><button class="btn orange" style="width:100%;margin-top:10px" ${seikaEventAttrs('click','v188StartBoth',[])}>第2・第3をまとめて開始</button><div class="grid" style="margin-top:10px"><button class="btn btn2" ${seikaEventAttrs('click','v188Start',['room2'])}>第2冷蔵庫だけ</button><button class="btn btn2" ${seikaEventAttrs('click','v188Start',['room3'])}>第3冷蔵庫だけ</button></div><div class="small" style="margin-top:8px">第2・第3は同時に進行できます。片方を確定しても もう片方は残ります。</div></div>
<div class="card"><b>進行中</b>${active.map(v188SessionCard).join('')||'<div class="small">進行中の棚卸しはありません。</div>'}</div>
<div class="card"><b>棚卸し履歴</b><div class="small" style="margin-top:6px">確定済み ${history.length}件${legacy.length?` / 旧棚卸し ${legacy.length}件`:''}。確定から3か月を過ぎた棚卸しは自動で削除されます。</div><button class="btn btn2" style="width:100%;margin-top:10px" ${seikaEventAttrs('click','v1205CountArchivePage',[])}>棚卸し履歴を開く</button></div>`);
}
function v188Guide(){
  setScreen('inventoryCountGuidePage');if(!v177Allowed())return home();
  pageShell('月末棚卸しの使い方','管理者・青果社員のみ / v1.199',
    `<div class="card notice"><b>1. 対象月を選んで開始</b><div class="small">対象月と冷蔵庫を選ぶと、その月の月末時点（当月は本日時点）の通常・片岡・その他・QR在庫が帳簿在庫として固定されます。開始後の入庫・出庫・調整では変わりません（QRロットだけは、確定のときに最新の出庫を含めて計算し直します）。</div></div>
<div class="card"><b>2. 記入票を印刷して現物確認</b><div class="small">記入票には月末時点の帳簿在庫、量目・入数、仕入先が入ります。A4横です。</div></div>
<div class="card"><b>3. 実数を入れる</b><div class="small">いつもの通常在庫入力・QR出庫・QR在庫調整で入力し、棚卸し画面の「現在の在庫を実数へ取り込む」で反映します。行ごとの手入力・修正もできます。</div></div>
<div class="card"><b>4. 差異理由・対象品目・QR確認状態</b><div class="small">差異がある行には理由を入力します。棚卸し対象から外す品目はチェックを外します。QRはロットごとに確認済みにできます。変更はすべて編集履歴に残ります。</div></div>
<div class="card"><b>5. 確定</b><div class="small">差異がある行だけを、対象月末日付の「棚卸し調整」として在庫履歴へ反映します。QRロットは、確定のときに最新の出庫を含めて月末の帳簿を計算し直すため、開始したあとに出庫した分は二重に引かれず、最後に入力した実数がそのまま月末の在庫になります。差異なし・対象外は履歴を作りません。帳簿と実数が全部一致している場合も「差異なしで棚卸しを確定」で確定でき、その場合は在庫履歴を作らず実施記録として残ります。確定後も管理者は編集でき、「差異を追加反映」で変更分だけを追加します。</div></div>
<div class="card"><b>6. Excel</b><div class="small">確定後にExcelを出力できます。単価欄へ入力すると金額と合計が自動計算されます。</div></div>
<button class="btn btn2" style="width:100%;margin-top:10px" ${seikaEventAttrs('click','inventoryCountHome',[])}>棚卸しモードへ戻る</button>`);
}

/* 同期キュー経路が inventoryCounts を落とすため、棚卸しを操作できる権限のときは必ず含める。
   これを外すと、開始した棚卸しがサーバー側の app_state 上書きで消える。 */
const v188RolePayloadKeepCounts=v188RolePayload;
v188RolePayload=function(payload,role=db?.role){
  const out=v188RolePayloadKeepCounts(payload,role);
  if(!out||!payload||typeof payload!=='object')return out;
  if(!['admin','worker'].includes(String(role||'')))return out;
  if(Object.prototype.hasOwnProperty.call(payload,'inventoryCounts'))out.inventoryCounts=payload.inventoryCounts;
  return out;
};
/* QR出庫履歴のサーバー関数 list_qr_outbound_history_v1144 が失敗する環境向けの代替取得。
   qr_lot_movements を直接読み、同じ形（rows / destinations / total_count）に整えて返す。 */
function v192MovementQty(move){
  for(const value of [move?.qty,move?.quantity]){const n=Number(value);if(Number.isFinite(n)&&n!==0)return Math.abs(n)}
  return 0;
}
function v192MovementWeight(move){
  for(const value of [move?.weight,move?.out_weight,move?.weight_kg]){const n=Number(value);if(Number.isFinite(n)&&n!==0)return Math.abs(n)}
  return null;
}
function v192MovementDestination(move){return String(move?.destination||move?.ship_to||move?.destination_name||'').trim()}
function v192IsCancelledMovement(move){
  if(move?.cancelled_at||move?.canceled_at)return true;
  return /取消|取り消し|キャンセル/.test(String(move?.movement_type||''));
}
function v192IsOutboundMovement(move){
  const type=String(move?.movement_type||'');
  if(/削除|棚卸し調整/.test(type))return false;
  if(/出庫|出荷/.test(type))return true;
  return !!v192MovementDestination(move);
}
async function v192OutboundHistoryFallback(args){
  const date=String(args?.p_work_date||'').slice(0,10)||todayKey();
  const wanted=String(args?.p_destination||'').trim();
  const include=!!args?.p_include_cancelled;
  const limit=Number(args?.p_limit||100),offset=Number(args?.p_offset||0);
  const day=new Date(`${date}T00:00:00+09:00`);
  const from=new Date(day.getTime()-24*60*60*1000).toISOString();
  const to=new Date(day.getTime()+2*24*60*60*1000).toISOString();
  let moves=[];
  try{moves=await v163SelectAll('qr_lot_movements',`select=*&created_at=gte.${encodeURIComponent(from)}&created_at=lt.${encodeURIComponent(to)}&order=created_at.desc`)}
  catch(error){moves=await v163SelectAll('qr_lot_movements','select=*&order=created_at.desc',1000)}
  const outbound=(moves||[]).filter(v192IsOutboundMovement);
  const destinations=[...new Set(outbound.map(v192MovementDestination).filter(Boolean))].sort((a,b)=>a.localeCompare(b,'ja'));
  let target=outbound.filter(move=>ymdKey(new Date(v163MovementAt(move)))===date);
  if(wanted)target=target.filter(move=>v192MovementDestination(move)===wanted);
  if(!include)target=target.filter(move=>!v192IsCancelledMovement(move));
  target.sort((a,b)=>v163MovementTime(a)-v163MovementTime(b));
  let lotMap=null;
  if(target.some(move=>!move?.item_name||!move?.lot_no)){
    try{
      const lots=await v163SelectAll('qr_lots','select=qr_key,lot_no,item_name,unit,container_type&order=qr_key.asc');
      lotMap=new Map((lots||[]).map(lot=>[String(lot.qr_key||''),lot]));
    }catch(error){lotMap=null}
  }
  const rows=target.slice(offset,offset+limit).map(move=>{
    const lot=lotMap?lotMap.get(String(move?.qr_key||'')):null;
    return {
      qr_key:move?.qr_key||null,
      lot_no:move?.lot_no||lot?.lot_no||'',
      item_name:move?.item_name||lot?.item_name||'',
      unit:move?.unit||lot?.unit||'',
      qty:v192MovementQty(move),
      weight:v192MovementWeight(move),
      occurred_at:v163MovementAt(move),
      user_name:move?.user_name||move?.user||'',
      memo:move?.memo||'',
      destination:v192MovementDestination(move),
      is_cancelled:v192IsCancelledMovement(move)
    };
  });
  return {ok:true,rows,destinations,total_count:target.length,summary_rows:null,fallback:true};
}
const v192CallRpcCore=callRpc;
callRpc=async function(name,args){
  if(name!=='list_qr_outbound_history_v1144')return v192CallRpcCore(name,args);
  try{return await v192CallRpcCore(name,args)}
  catch(error){return await v192OutboundHistoryFallback(args)}
};
window.v188Start=v188Start;window.v188StartBoth=v188StartBoth;window.v188Repair=v188Repair;window.v188Print=v188Print;window.v188CountPage=v188CountPage;window.v188Save=v188Save;window.v188ImportLive=v188ImportLive;window.v188Confirm=v188Confirm;window.v188DownloadExcel=v188DownloadExcel;window.v188HistoryPage=v188HistoryPage;window.v188Home=v188Home;
window.inventoryCountHome=v188Home;inventoryCountHome=v188Home;startInventoryCount=v188Start;downloadInventoryCountExcel=v188DownloadExcel;inventoryCountGuidePage=v188Guide;
/* ===== v1.192 月末棚卸しExcel：QR数量の欠落修正・入荷日の列追加・出庫先/出庫区分の廃止 ===== */
const V192_SECTION_COLS={
  normal:{
    heads:['区分','品名','単位','帳簿数量','棚卸し実数','差異','重量kg','差異理由','対象','備考','単価（円/単位）','金額（円）'],
    pick:row=>[row.group,row.item,row.unit,row.book,row.qty,row.diff,row.weight,row.reason,row.included,row.memo,'',''],
    widths:[10,26,8,12,12,10,11,18,8,26,15,15],
    right:[3,4,5,6,10,11],
    accent:[],
    cols:{unit:'C',qty:'E',weight:'G',price:'K',amount:'L'}
  },
  qr:{
    heads:['区分','品名','入荷日','仕入先','ロット','荷姿・規格','単位','帳簿数量','棚卸し実数','差異','重量kg','差異理由','対象','QR確認','備考','単価（円/単位）','金額（円）'],
    pick:row=>[row.group,row.item,row.received,row.supplier,row.lot,row.spec,row.unit,row.book,row.qty,row.diff,row.weight,row.reason,row.included,row.checked,row.memo,'',''],
    widths:[10,24,13,18,22,14,8,12,12,10,11,16,8,10,24,15,15],
    right:[7,8,9,10,15,16],
    accent:[2,3],
    cols:{unit:'G',qty:'I',weight:'K',price:'P',amount:'Q'}
  }
};
function v192PackKg(line){const raw=String(line?.packWeight??'').replace(/[^0-9.]/g,'');if(raw==='')return null;const n=Number(raw);return Number.isFinite(n)&&n>0?n:null}
function v192QrWeight(line,actual){
  const manual=v119StrictDecimal(line?.actualWeightKg);
  if(qrIsLargeContainer(line?.containerType)){
    const per=qrCountLargePerWeight(line);
    if(per!==null&&per!==undefined&&actual!==null)return yen(actual*per);
    return manual===null?'':manual;
  }
  if(manual!==null)return manual;
  const pack=v192PackKg(line);
  return pack!==null&&actual!==null?yen(actual*pack):'';
}
function v192ExcelRows(session,section){
  return v188SectionLines(session,section).map(line=>{
    const entry=v188Entry(session,line.lineId),actual=v188Actual(session,line.lineId),book=v188BookQty(session,line),diff=v188Diff(session,line);
    const weight=section==='qr'
      ?v192QrWeight(line,actual)
      :(String(line.unit||'')==='kg'&&actual!==null?actual:'');
    return {
      group:line.group||(section==='qr'?'QR':line.type==='special'?'その他':'通常'),
      item:line.itemName||'',
      lot:section==='qr'?(line.lotNo||line.qrKey||''):'',
      received:section==='qr'?(line.receivedDate||''):'',
      supplier:section==='qr'?(line.supplier||''):'',
      spec:section==='qr'?(line.containerType||''):(line.unit||''),
      unit:line.unit||'',
      book:book===null||book===undefined?'':book,
      qty:actual===null?'':actual,
      diff:diff===null?'':diff,
      weight:weight===null||weight===undefined?'':weight,
      reason:entry.reason||'',
      included:entry.included===false?'対象外':'対象',
      checked:section==='qr'?(entry.checked?'確認済み':'未確認'):'',
      memo:entry.memo||''
    };
  });
}
function v192AddDetailSheet(wb,name,title,session,section){
  const spec=V192_SECTION_COLS[section],rows=v192ExcelRows(session,section),heads=spec.heads;
  const meta=[['棚卸し番号',session.countNo||''],['冷蔵庫',session.roomLabel||''],['対象月',`${v188MonthLabel(session.targetMonth)}末`],['基準日',session.asOfKey||''],['状態',v188Confirmed(session)?'確定済み（差異のみ対象月末日で在庫反映）':'未確定（在庫へ未反映）']];
  const values=rows.map(row=>spec.pick(row).map(value=>typeof value==='string'?inventoryCountExcelSafeText(value):value));
  const ws=XLSX.utils.aoa_to_sheet([[title],[],...meta,[],heads,...values]);
  const header=meta.length+3,start=header+2,end=header+rows.length+1;
  const {qty,price,amount}=spec.cols;
  for(let r=start;r<=end;r++)ws[`${amount}${r}`]={t:'n',f:`IF(OR(${qty}${r}="",${price}${r}=""),"",${qty}${r}*${price}${r})`};
  ws[`${price}${end+1}`]={t:'s',v:'明細合計'};
  ws[`${amount}${end+1}`]={t:'n',f:`SUM(${amount}${start}:${amount}${end})`};
  ws['!ref']=XLSX.utils.encode_range({s:{r:0,c:0},e:{r:end,c:heads.length-1}});
  ws['!merges']=[{s:{r:0,c:0},e:{r:0,c:heads.length-1}}];
  ws['!autofilter']={ref:XLSX.utils.encode_range({s:{r:header,c:0},e:{r:Math.max(header,end-1),c:heads.length-1}})};
  ws['!cols']=spec.widths.map(wch=>({wch}));
  ws['!freeze']={xSplit:2,ySplit:header+1};
  inventoryCountExcelStyle(ws,'A1',{font:{name:'Yu Gothic',sz:15,bold:true,color:{rgb:'FFFFFF'}},fill:{patternType:'solid',fgColor:{rgb:'1D4ED8'}},alignment:{horizontal:'center'}});
  for(let c=0;c<heads.length;c++)inventoryCountExcelStyle(ws,XLSX.utils.encode_cell({r:header,c}),{font:{name:'Yu Gothic',sz:10,bold:true,color:{rgb:spec.accent.includes(c)?'FFFFFF':'000000'}},fill:{patternType:'solid',fgColor:{rgb:spec.accent.includes(c)?'0F766E':'D9EAF7'}},alignment:{horizontal:'center',vertical:'center',wrapText:true}});
  for(let r=start;r<=end+1;r++)for(let c=0;c<heads.length;c++)inventoryCountExcelStyle(ws,XLSX.utils.encode_cell({r:r-1,c}),{font:{name:'Yu Gothic',sz:10,bold:spec.accent.includes(c)},fill:spec.accent.includes(c)&&r<=end?{patternType:'solid',fgColor:{rgb:'F0FDFA'}}:undefined,alignment:{vertical:'center',wrapText:true,horizontal:spec.right.includes(c)?'right':spec.accent.includes(c)?'center':'left'}});
  XLSX.utils.book_append_sheet(wb,ws,safeSheetName(name));
  return {name,rows,start,end,cols:spec.cols};
}
function v192AddSummarySheet(wb,session,normal,qr){
  const all=[...v192ExcelRows(session,'normal'),...v192ExcelRows(session,'qr')];
  const keys=[...new Map(all.map(row=>[`${row.group}|${row.item}|${row.unit}`,row])).values()];
  const heads=['区分','品名','単位','合計数量','合計重量kg','合計金額（円）'];
  const ws=XLSX.utils.aoa_to_sheet([[`${session.roomLabel||''} 月末棚卸し 品目集計`],[],['棚卸し番号',session.countNo||''],['対象月',`${v188MonthLabel(session.targetMonth)}末`],['注記','明細シートの単価入力に連動します'],[],heads,...keys.map(row=>[row.group,row.item,row.unit,'','',''])]);
  const header=7,start=8,end=7+keys.length;
  const n=String(normal.name).replace(/'/g,"''"),q=String(qr.name).replace(/'/g,"''");
  for(let r=start;r<=end;r++){
    const g=`A${r}`,it=`B${r}`,u=`C${r}`;
    const part=(sheet,meta,col)=>`SUMIFS('${sheet}'!$${col}$${meta.start}:$${col}$${meta.end},'${sheet}'!$A$${meta.start}:$A$${meta.end},${g},'${sheet}'!$B$${meta.start}:$B$${meta.end},${it},'${sheet}'!$${meta.cols.unit}$${meta.start}:$${meta.cols.unit}$${meta.end},${u})`;
    const sum=key=>`${part(n,normal,normal.cols[key])}+${part(q,qr,qr.cols[key])}`;
    ws[`D${r}`]={t:'n',f:sum('qty')};ws[`E${r}`]={t:'n',f:sum('weight')};ws[`F${r}`]={t:'n',f:sum('amount')};
  }
  ws['!ref']=XLSX.utils.encode_range({s:{r:0,c:0},e:{r:Math.max(end,header),c:heads.length-1}});
  ws['!merges']=[{s:{r:0,c:0},e:{r:0,c:heads.length-1}}];
  ws['!cols']=[10,24,10,14,14,16].map(wch=>({wch}));
  inventoryCountExcelStyle(ws,'A1',{font:{name:'Yu Gothic',sz:15,bold:true,color:{rgb:'FFFFFF'}},fill:{patternType:'solid',fgColor:{rgb:'0F766E'}},alignment:{horizontal:'center'}});
  for(let c=0;c<heads.length;c++)inventoryCountExcelStyle(ws,XLSX.utils.encode_cell({r:header-1,c}),{font:{name:'Yu Gothic',sz:10,bold:true},fill:{patternType:'solid',fgColor:{rgb:'CCFBF1'}},alignment:{horizontal:'center',vertical:'center',wrapText:true}});
  XLSX.utils.book_append_sheet(wb,ws,safeSheetName(`${session.roomLabel||'冷蔵庫'} 品目集計`));
}
function v192DownloadExcel(id){
  const session=countSession(id);if(!session||!v188Session(session))return v186DownloadExcel(id);
  if(!ensureXlsxReady())return;
  const label=v188MonthLabel(session.targetMonth),wb=XLSX.utils.book_new();
  const normal=v192AddDetailSheet(wb,`${session.roomLabel} 通常在庫`,`${session.roomLabel} 通常在庫 ${label}末棚卸し`,session,'normal');
  const qr=v192AddDetailSheet(wb,`${session.roomLabel} QR在庫`,`${session.roomLabel} QR在庫 ${label}末棚卸し`,session,'qr');
  v192AddSummarySheet(wb,session,normal,qr);
  downloadWorkbookXlsx(wb,`棚卸し_${String(session.targetMonth||'').replace('-','')}_${String(session.roomLabel||'冷蔵庫').replace(/[\\/:*?"<>|]/g,'_')}_${String(session.countNo||'').replace(/[\\/:*?"<>|]/g,'_')}.xlsx`);
  return inventoryCountHome('棚卸しExcelを出力しました。単価欄へ入力すると金額と合計が計算されます。');
}
downloadInventoryCountExcel=v192DownloadExcel;window.downloadInventoryCountExcel=v192DownloadExcel;v188DownloadExcel=v192DownloadExcel;window.v188DownloadExcel=v192DownloadExcel;
/* ===== v1.192 QR品質評価Excel：仕入先を追加 ===== */
let V192_QUALITY_LOTS=new Map();
async function v192LoadQualityLots(rows){
  const map=new Map();
  if(!(rows||[]).some(row=>!row?.supplier))return map;
  try{
    const lots=await v163SelectAll('qr_lots','select=qr_key,supplier,received_date&order=qr_key.asc');
    for(const lot of lots||[]){const key=String(lot?.qr_key||'').trim();if(key&&!map.has(key))map.set(key,lot)}
  }catch(error){}
  return map;
}
function v192QualityReceived(x){
  if(x&&x.received_date)return String(x.received_date).slice(0,10);
  const lot=V192_QUALITY_LOTS.get(String(x?.qr_key||'').trim());
  return lot&&lot.received_date?String(lot.received_date).slice(0,10):'';
}
function v192QualitySupplier(x){
  if(x&&x.supplier)return String(x.supplier);
  const lot=V192_QUALITY_LOTS.get(String(x?.qr_key||'').trim());
  return lot&&lot.supplier?String(lot.supplier):'';
}

const v188InventoryCountPageLegacy=inventoryCountPage;
inventoryCountPage=function(id,msg=''){const session=countSession(id);return v188Session(session)?v188CountPage(id,'normal',msg):v188InventoryCountPageLegacy(id,msg)};
const v188PrintLatestCore=v186PrintLatest;
v186PrintLatest=async function(id,mode='all'){const session=countSession(id);if(v188Session(session))return v188Print(id,mode);return v188PrintLatestCore(id,mode)};
window.APP_VERSION='v1.193';document.title='SEIKA＋ v1.193 週次廃棄レポート版';





/* ===== v1.193 週次廃棄レポート ===== */
const V193_THEMES=[
{t:'剥きすぎない',a:['傷んだところだけ剥く。きれいな葉は残す。','迷ったら自分で判断せず社員に聞く。','お客様にクレームにならないレベルまででよい。']},
{t:'原料は古いものから使う',a:['社員の指示がない限り、古い原料から順番に使う。','新しい箱を先に開けない。','どれが古いか分からないときは社員に聞く。']},
{t:'原料を出すとき',a:['出すときも古いものから。奥や下にあるものを見落とさない。','その日に使う分だけ出す。まとめて出しすぎない。','冷蔵庫の扉を長く開けたままにしない。']},
{t:'傷みの見分け方',a:['変色と汚れは別物。汚れは社員に確認をして対応。','押して柔らかいものは傷み始め。','迷うものは避けてあとから社員に見せる。']},
{t:'大きさ・規格ではじきすぎない',a:['規格から少し外れても社内や他客先で使える場合がある。','自分ではじかず、置き場所を分けて残す。','捨てるかどうかは社員が決める。']},
{t:'箱・袋の扱い',a:['落とさない、放らない。','積み上げは決めた段数まで。','濡れた箱は早めに入れ替える。']},
{t:'作業前の段取り',a:['始める前に道具とコンテナをそろえる。','今日やる順番を確認する。','足りないものは始まる前に用意する。']},
{t:'動く回数を減らす',a:['使うものを近くに集めてから始める。','取りに行く(動く)回数を減らす。','ゴミはまとめて運ぶ。']},
{t:'数え間違い・記録漏れ',a:['数えたらその場で書く。','あとでまとめて書かない。','分からなくなったら止めて確認する。『あとからは』危険。']},
{t:'作業が終わったら',a:['残った原料と製品は自分でしまわず、社員に聞く。','どれがどれだけ残ったかを伝えてから終わる。','使った原料と道具を戻し、作業台と床を片付ける。']},
{t:'日報の書き方',a:['使用原料、出来高、廃棄の3つは必ず書く。','その日のうちに書く。あとでまとめて書かない。','分からない数字は空欄にしない。廃棄がない場合は斜線などで記入漏れと見分けられるようにする。']},
{t:'報告・連絡',a:['おかしいと思ったらすぐ言う。','勝手に判断しない。','社員の判断で進める。']},
{t:'規格を守る',a:['決められた規格の範囲で使用する。','原料出しは原体が基本の為、大きく切り落としすぎない。','迷ったら社員に聞く。']},
{t:'使える部分を残す',a:['外葉や芯でも使える部分は分けて残す。','捨てる前に社員に見せる。','捨てる箱と残す箱を分ける。']},
{t:'床に落とさない',a:['落としたものは使えなくなる。','作業台からはみ出して置かない。','コンテナは計量器や台の上に置く。']},
{t:'冷蔵庫の扉と製品',a:['扉を開けたらすぐ閉める。','出した原料、製品を常温に長く置かない。','社員が運べない場合は、冷蔵庫前に運ぶ。']},
{t:'葉物の扱い',a:['葉物は傷みやすいので先に作業する。','重ねて押しつぶさない。','しおれたものは社員に見せる。']},
{t:'包丁・道具の手入れ',a:['よく切れる包丁を使う（切り口が傷みにくい）。','切れにくいときは社員に言う。','使った道具は洗って戻す。']},
{t:'製造の過不足',a:['言われた数だけ作る。','多く作れそうなら社員に相談する。','やりきれない場合は都度相談をする。']},
{t:'袋詰め・重さ',a:['決められた重さで詰める（入れすぎない）。','袋を無駄にしない。','計量器の重さが狂っているときは、使用せず社員に連絡。']},
{t:'衛生・異物',a:['手洗い・手袋を守る。','髪の毛や異物が入らないようにする。','異物を見つけたら止めて社員に知らせる。']},
{t:'時間内に終わらせる',a:['区切りごとに時間を見る。','遅れそうなら早めに言う。','手が空いたら次の作業を聞く。']},
{t:'捨てるときのルール',a:['黙って捨てない。','捨てる前に品目と量を社員に伝える。','廃棄は控えておいてあとから分かるようにする。']}
];
function v193Money(n){return Math.round(Number(n||0)).toLocaleString('ja-JP')}
function v193Date(key){return new Date(`${key}T00:00:00`)}
function v193Shift(key,days){const d=v193Date(key);d.setDate(d.getDate()+days);return ymdKey(d)}
function v193WeekEndOf(key){const d=v193Date(key),w=d.getDay();return v193Shift(key,w===0?0:7-w)}
function v193DefaultEnd(){const t=todayKey(),d=v193Date(t),w=d.getDay();return v193Shift(t,w===0?-7:-w)}
function v193FiscalStart(key){const d=v193Date(key),y=d.getFullYear();return `${d.getMonth()+1>=9?y:y-1}-09-01`}
function v193Amount(r){const a=r&&r.amount;if(a!==undefined&&a!==null&&a!=='')return Number(a)||0;return Number(r&&r.qty||0)*Number(r&&r.unitPrice||0)}
function v193Label(key){const d=v193Date(key);return `${d.getMonth()+1}/${d.getDate()}`}
async function v193Rows(from,to){
  await v1144LoadUnifiedWaste(from,to);
  return (v1144QrWasteCache.rows||[]).filter(r=>{const d=String(r&&r.date||'');return d>=from&&d<=to});
}
function v193Sum(rows,from,to){return rows.filter(r=>String(r.date||'')>=from&&String(r.date||'')<=to).reduce((a,r)=>a+v193Amount(r),0)}
function v193AutoThemeIndex(end){const n=V193_THEMES.length,w=Math.round((v193Date(end)-v193Date('2026-11-01'))/6048e5);return ((w%n)+n)%n}
function v193Themes(pick=0){return V193_THEMES.map((x,i)=>`<option value="${i}"${i===pick?' selected':''}>${esc(x.t)}</option>`).join('')}
function v193FillTheme(){
  const sel=document.getElementById('v193Theme');if(!sel)return;
  const item=V193_THEMES[Number(sel.value)];if(!item)return;
  for(let i=0;i<3;i++){const box=document.getElementById(`v193Action${i}`);if(box)box.value=item.a[i]||''}
}
function v193WeeklyReportPage(msg=''){
  setScreen('v193WeeklyReportPage',[msg]);
  if(!canWasteExport()){alert('週次廃棄レポートは管理者・青果社員・営業担当者・事務員のみです');return wasteManagementPage()}
  const end=v193DefaultEnd(),start=v193Shift(end,-6),pick=v193AutoThemeIndex(end),first=V193_THEMES[pick];
  pageShell('週次廃棄レポート','パートさんへ配る1枚を作ります。対象週とテーマを確認して印刷してください。',
  `${okHtml(msg)}<div class="card">
  <label class="label" for="v193End">対象週の最終日（日曜）</label>
  <input id="v193End" class="input" type="date" value="${esc(end)}" ${seikaEventAttrs('change','v193SyncRange',[])}>
  <div class="small" id="v193Range" style="margin-top:6px">${esc(start)} 〜 ${esc(end)} の7日間を集計します。</div>
  </div>
  <div class="card">
  <label class="label" for="v193Theme">今週のテーマ</label>
  <select id="v193Theme" class="input" ${seikaEventAttrs('change','v193FillTheme',[])}>${v193Themes(pick)}</select>
  <div class="small" style="margin-top:6px">テーマは対象の週ごとに自動で次のものに変わります。必要なら選び直せます。</div>
  <label class="label" style="margin-top:10px">伝えること（3つまで／その場で書き換えできます）</label>
  ${[0,1,2].map(i=>`<input id="v193Action${i}" class="input" style="margin-top:6px" value="${esc(first.a[i]||'')}">`).join('')}
  </div>
  <div class="card">
  <button class="btn" style="width:100%" ${seikaEventAttrs('click','v193MakeReport',[])}>レポートを作って印刷する</button>
  <button class="btn btn2" style="width:100%;margin-top:8px" ${seikaEventAttrs('click','wasteManagementPage',[])}>戻る</button>
  </div>`);
}
function v193SyncRange(){
  const input=document.getElementById('v193End');if(!input||!input.value)return;
  const end=v193WeekEndOf(input.value);input.value=end;
  const box=document.getElementById('v193Range');
  if(box)box.textContent=`${v193Shift(end,-6)} 〜 ${end} の7日間を集計します。`;
  const sel=document.getElementById('v193Theme');if(sel){sel.value=String(v193AutoThemeIndex(end));v193FillTheme()}
}
function v193BarRow(label,value,max,color){
  const width=max>0?Math.max(2,Math.round(value/max*100)):0;
  return `<div class="v193Bar"><div class="v193BarLabel">${esc(label)}</div><div class="v193BarTrack"><svg width="100%" height="16" viewBox="0 0 100 16" preserveAspectRatio="none"><rect x="0" y="0" width="100" height="16" fill="#e4e7ea"></rect><rect x="0" y="0" width="${width}" height="16" fill="${color}"></rect></svg></div><div class="v193BarValue">${v193Money(value)}円</div></div>`;
}
function v193ReportHtml(d){
  const diffText=d.prev>0?`${d.diff>=0?'+':''}${Math.round(d.diff/d.prev*100)}%`:'—',
  diffSub=d.prev>0?`その前の週 ${v193Money(d.prev)}円`:'その前の週のデータなし',
  diffColor=d.prev>0&&d.diff<0?'#1b5e20':'#c62828',
  topMax=d.top.length?d.top[0].amount:0,
  weekMax=d.weeks.reduce((a,w)=>Math.max(a,w.amount),0),
  head=d.top[0];
  return `<!doctype html><html lang="ja"><head><meta charset="utf-8"><title>先週の廃棄レポート</title>
<style>
@page{size:A4 portrait;margin:12mm}
*{box-sizing:border-box}
html,body{-webkit-print-color-adjust:exact;print-color-adjust:exact}
body{margin:0;font-family:"Hiragino Kaku Gothic ProN","Yu Gothic",Meiryo,sans-serif;color:#111;background:#fff}
.sheet{padding:0;width:100%;max-width:100%;overflow:hidden}
.hd{border-bottom:3px solid #14471a;padding:0 0 8px;display:flex;justify-content:space-between;align-items:flex-end;gap:10px}
.hd h1{margin:0;font-size:22px;color:#14471a;font-weight:700}
.hd .sub{color:#222;font-size:12.5px;margin-top:4px;font-weight:700}
.hd .goal{color:#14471a;font-size:11px;text-align:right;line-height:1.5;font-weight:700;flex:none}
.kpis{display:flex;gap:8px;margin-top:12px}
.kpi{flex:1;min-width:0;border:2px solid #888;border-radius:6px;overflow:hidden;text-align:center}
.kpi .cap{font-size:12px;font-weight:700;padding:5px 4px;border-bottom:1.5px solid currentColor}
.kpi .big{font-size:23px;font-weight:700;padding:8px 4px 2px}
.kpi .sub{font-size:9.5px;color:#222;padding:0 3px 8px;font-weight:700}
.panel{border:1.5px solid #777;border-radius:6px;padding:10px 12px;margin-top:12px}
.panel h2{margin:0 0 8px;font-size:13px;color:#0b2e57;font-weight:700}
.v193Bar{display:flex;align-items:center;gap:8px;margin:5px 0}
.v193BarLabel{width:100px;font-size:11.5px;text-align:right;flex:none;color:#111;font-weight:700;overflow:hidden;white-space:nowrap}
.v193BarTrack{flex:1;min-width:0;height:16px;line-height:0}
.v193BarValue{width:84px;font-size:11.5px;text-align:right;flex:none;color:#111;font-weight:700}
.lead{margin-top:12px;border:1.5px solid #e65100;background:#fff8e1;border-radius:6px;padding:9px;text-align:center;font-size:13.5px;font-weight:700;color:#e65100}
.theme{margin-top:12px;border:1.5px solid #1b5e20;background:#e8f5e9;border-radius:6px;padding:10px 14px}
.theme .cap{font-size:12px;font-weight:700;color:#1b5e20}
.theme .name{font-size:18px;font-weight:700;margin:4px 0 8px;color:#111}
.theme li{font-size:13px;margin:4px 0;color:#111}
.memo{margin-top:12px;border:1px solid #bdbdbd;border-radius:6px;padding:10px 12px}
.memo h2{margin:0 0 6px;font-size:12.5px;color:#0b2e57;font-weight:700}
.memo .ln{border-bottom:1px solid #9aa0a6;height:22px}
.ft{margin-top:12px;text-align:center;font-size:12.5px;font-weight:700;color:#14471a}
.ft .org{font-size:9.5px;color:#333;font-weight:400;margin-top:4px}
</style></head><body>${V188_PRINT_BAR}
<div class="sheet">
<div class="hd"><div><h1>先週の廃棄レポート</h1><div class="sub">${esc(d.startLabel)} 〜 ${esc(d.endLabel)}</div></div>
<div class="goal">今期の目標<br>残業を減らす／廃棄を減らす</div></div>
<div class="kpis">
<div class="kpi" style="border-color:#c62828"><div class="cap" style="color:#b71c1c">先週の廃棄金額</div><div class="big" style="color:#c62828">${v193Money(d.cur)}円</div><div class="sub">${d.count}件</div></div>
<div class="kpi" style="border-color:${diffColor}"><div class="cap" style="color:${diffColor}">その前の週とくらべて</div><div class="big" style="color:${diffColor}">${esc(diffText)}</div><div class="sub">${esc(diffSub)}</div></div>
<div class="kpi" style="border-color:#0f3d6e"><div class="cap" style="color:#0b2e57">期首からの累計</div><div class="big" style="color:#0f3d6e">${v193Money(d.cum)}円</div><div class="sub">${esc(d.fiscalFull)}〜${esc(d.endLabel)}</div></div>
</div>
<div class="panel"><h2>先週の多い品目（金額）</h2>${d.top.length?d.top.map(x=>v193BarRow(x.name,x.amount,topMax,'#c62828')).join(''):'<div class="sub">この週の廃棄はありません。</div>'}</div>
<div class="panel"><h2>週ごとの推移（金額）</h2>${d.weeks.length?d.weeks.map(w=>v193BarRow(w.label+'の週',w.amount,weekMax,'#1b5e20')).join(''):''}</div>
${head?`<div class="lead">先週いちばん多かったのは ${esc(head.name)}。${v193Money(head.amount)}円${head.qty>0?`（${head.qty.toFixed(1)}kg）`:''}を捨てています。</div>`:''}
<div class="theme"><div class="cap">今週のテーマ</div><div class="name">${esc(d.theme)}</div><ul>${d.actions.map(a=>`<li>${esc(a)}</li>`).join('')}</ul></div>
<div class="memo"><h2>気づいたこと・やりにくいこと（記入欄）</h2><div class="ln"></div><div class="ln"></div><div class="ln"></div><div class="ln"></div></div>
<div class="ft">気づいたこと・やりにくいことがあれば、社員に伝えてください。<div class="org">石岡青果センター</div></div>
</div></body></html>`;
}
async function v193MakeReport(){
  if(!canWasteExport())return alert('週次廃棄レポートは管理者・青果社員・営業担当者・事務員のみです');
  const input=document.getElementById('v193End');
  if(!input||!input.value)return alert('対象週の最終日を選んでください。');
  const end=v193WeekEndOf(input.value),start=v193Shift(end,-6),fiscal=v193FiscalStart(end);
  const sel=document.getElementById('v193Theme'),picked=V193_THEMES[Number(sel&&sel.value)]||V193_THEMES[0];
  const actions=[0,1,2].map(i=>String(document.getElementById(`v193Action${i}`)?.value||'').trim()).filter(Boolean);
  const win=window.open('','_blank');
  if(!win)return alert('印刷画面を開けませんでした。ポップアップ許可を確認してください。');
  try{
    v161ShowProcessing('廃棄の集計をしています');
    const rows=await v193Rows(fiscal<=start?fiscal:start,end);
    const cur=v193Sum(rows,start,end),prev=v193Sum(rows,v193Shift(start,-7),v193Shift(start,-1));
    const items=new Map();
    for(const r of rows.filter(x=>String(x.date||'')>=start&&String(x.date||'')<=end)){
      const name=String(r.itemName||r.item_name||'(品名なし)'),cell=items.get(name)||{name,amount:0,qty:0};
      cell.amount+=v193Amount(r);cell.qty+=Number(r.qty||0);items.set(name,cell);
    }
    const top=[...items.values()].sort((a,b)=>b.amount-a.amount).slice(0,5);
    const weeks=[];
    for(let i=5;i>=0;i--){
      const ws=v193Shift(start,-7*i),we=v193Shift(ws,6);
      if(ws<fiscal&&i>0)continue;
      weeks.push({label:v193Label(ws),amount:v193Sum(rows,ws,we)});
    }
    const html=v193ReportHtml({
      cur,prev,diff:cur-prev,cum:v193Sum(rows,fiscal,end),
      count:rows.filter(x=>String(x.date||'')>=start&&String(x.date||'')<=end).length,
      startLabel:start,endLabel:end,fiscalLabel:v193Label(fiscal),fiscalFull:fiscal,
      top,weeks,theme:picked.t,actions:actions.length?actions:picked.a
    });
    win.document.open();win.document.write(html);win.document.close();win.focus();
  }catch(e){
    try{win.close()}catch(err){}
    alert(`集計に失敗しました。\n\n${String(e&&e.message||e)}`);
  }finally{v161HideProcessing()}
}


/* ===== v1.194 納品先マスタ・認証区分 ===== */
const V194_INTERNAL_DESTS=["本社","埼玉","深谷","社外","荻沼","石岡冷凍","現場作業","その他","廃棄"];
const V194_DEST_PRESET_VERSION=3;
const V194_EXTERNAL_SEED=[
 ["美野里D・デリカシェフ",[
   ["美野里デリカ","美野里デリカ株式会社"],
   ["デリカシェフ 久喜工場","株式会社デリカシェフ 久喜工場"],
   ["麺の杜","麺の杜株式会社"]]],
 ["虎昭・タマムラ",[
   ["虎昭産業 館林工場","虎昭産業株式会社 館林工場"],
   ["虎昭産業 茨城工場","虎昭産業株式会社 茨城工場"],
   ["虎昭産業 もおか工場","虎昭産業株式会社 もおか工場"],
   ["タマムラデリカ 佐野田沼工場","タマムラデリカ株式会社 佐野田沼工場"],
   ["東部アシード","株式会社東部アシード"],
   ["ティキューシー","株式会社ティキューシー"]]],
 ["プライム",[
   ["プライムデリカ 相模原工場","プライムデリカ株式会社 相模原工場",true],
   ["プライムデリカ 相模原第二工場","プライムデリカ株式会社 相模原第二工場",true],
   ["プライムデリカ 龍ケ崎工場","プライムデリカ株式会社 龍ケ崎工場",true]]],
 ["フジ・日本デリカ・成城",[
   ["フジフーズ 千葉工場","フジフーズ株式会社 千葉工場"],
   ["日本デリカサービス 八千代工場","株式会社日本デリカサービス 八千代工場"],
   ["成城石井","株式会社成城石井"],
   ["武蔵野 千葉工場","株式会社武蔵野 千葉工場"],
   ["わらべや日洋食品 吉川工場","わらべや日洋食品株式会社 吉川工場"],
   ["わらべや日洋食品 浦和工場","わらべや日洋食品株式会社 浦和工場"],
   ["わらべや日洋食品 茨城工場","わらべや日洋食品株式会社 茨城工場"],
   ["ファーストフーズつくば","株式会社ファーストフーズつくば"]]]
];
const V194_RETIRED_DESTS=["麺の杜 株式会社","日本デリカサービス","成城石井 第三CK","成城石井 NCK","武蔵野 千葉工場（食堂用）"];
const V194_CERTS=["JGAP","GGAP","ASIAGAP","その他"];
function v194DefaultDestinations(){
  const rows=V194_INTERNAL_DESTS.map(name=>({name,formal:"",kind:"内",group:"社内",outbound:true,weight:false,active:true}));
  for(const [group,list] of V194_EXTERNAL_SEED)for(const [name,formal,weight] of list)
    rows.push({name,formal:formal||"",kind:"外",group,outbound:false,weight:!!weight,active:true});
  return rows;
}
function v194MigrateDestinations(){
  if(!db||typeof db!=="object")return;
  if(Number(db.v194DestPresetVersion||0)>=V194_DEST_PRESET_VERSION)return;
  const rows=db.v194Destinations,seed=v194DefaultDestinations().filter(r=>r.kind==="外");
  for(let i=rows.length-1;i>=0;i--)if(rows[i].kind==="外"&&V194_RETIRED_DESTS.includes(rows[i].name))rows.splice(i,1);
  for(const sd of seed){
    const cur=rows.find(r=>r.name===sd.name);
    if(cur){cur.formal=cur.formal||sd.formal;cur.group=sd.group;cur.weight=sd.weight}
    else rows.push({...sd});
  }
  db.v194DestPresetVersion=V194_DEST_PRESET_VERSION;
}
function v194EnsureDestinations(){
  if(!db||typeof db!=="object")return [];
  if(!Array.isArray(db.v194Destinations)||!db.v194Destinations.length){db.v194Destinations=v194DefaultDestinations();db.v194DestPresetVersion=V194_DEST_PRESET_VERSION;}
  const rows=db.v194Destinations.filter(r=>r&&r.name);
  for(const r of rows){
    r.name=String(r.name);
    r.formal=String(r.formal||"");
    r.kind=r.kind==="外"?"外":"内";
    r.group=String(r.group||(r.kind==="外"?"未分類":"社内"));
    r.outbound=r.outbound===undefined?r.kind!=="外":!!r.outbound;
    r.weight=!!r.weight;
    r.active=r.active!==false;
  }
  if(rows.length!==db.v194Destinations.length)db.v194Destinations=rows;
  v194MigrateDestinations();
  return db.v194Destinations;
}
function v194OutboundNames(){return v194EnsureDestinations().filter(r=>r.active&&r.outbound).map(r=>r.name)}
function v194SyncOutDestinations(){
  const names=v194OutboundNames();
  if(!names.length)return;
  QR_OUT_DESTINATIONS.length=0;
  for(const n of names)QR_OUT_DESTINATIONS.push(n);
}
function v194DestinationsPage(msg=""){
  setScreen("v194DestinationsPage",[msg]);
  if(!canAdmin()){alert("納品先マスタは管理者のみです");return qrHome()}
  const rows=v194EnsureDestinations(),groups=[...new Set(rows.map(r=>r.group))];
  const form=`<div class="card"><b>納品先を追加</b>
<label class="label">納品先名</label><input id="v194DestName" class="input" placeholder="例：プライムデリカ 龍ケ崎工場">
<label class="label">区分</label><select id="v194DestKind" class="input"><option value="内">社内</option><option value="外">社外</option></select>
<label class="label">グループ（産地報告のシート）</label><input id="v194DestGroup" class="input" list="v194DestGroupList" placeholder="例：プライム"><datalist id="v194DestGroupList">${groups.map(g=>`<option value="${esc(g)}">`).join("")}</datalist>
<label class="label">正式名称（任意）</label><input id="v194DestFormal" class="input" placeholder="例：株式会社日本デリカサービス 八千代工場">
<label class="label"><input type="checkbox" id="v194DestOutbound"> 出庫先の選択肢に表示する</label>
<label class="label"><input type="checkbox" id="v194DestWeight"> レタス類を実重量(kg)で納品する</label>
<button class="btn" style="width:100%;margin-top:12px" ${seikaEventAttrs('click','v194AddDest',[])}>納品先を追加</button></div>`;
  const body=groups.map(g=>{
    const items=rows.map((r,i)=>[r,i]).filter(([r])=>r.group===g);
    return `<div class="card"><b>${esc(g)}</b>${items.map(([r,i])=>`<div class="itemHead" style="margin-top:8px"><div><b>${esc(r.name)}</b><div class="small">${r.formal?esc(r.formal)+"<br>":""}${r.kind==="外"?"社外":"社内"} ／ 出庫先に表示：${r.outbound?"する":"しない"}${r.weight?" ／ <b>レタス類は実重量(kg)で納品</b>":""}</div></div><div class="row" style="gap:6px"><button class="btn btn2" ${seikaEventAttrs('click','v194ToggleDestOutbound',[i])}>${r.outbound?"表示をやめる":"出庫先に出す"}</button><button class="btn red" ${seikaEventAttrs('click','v194RemoveDest',[i])}>削除</button></div></div>`).join("")}</div>`;
  }).join("");
  pageShell("納品先マスタ","社内の納品先と社外の客先を登録します。出庫先の選択肢に出すかどうかは1件ずつ切り替えられます。",`${okHtml(msg)}${form}${body}`);
}
function v194AddDest(){
  if(!canAdmin())return alert("納品先マスタは管理者のみです");
  const name=document.getElementById("v194DestName")?.value.trim()||"";
  if(!name)return alert("納品先名を入力してください");
  const kind=document.getElementById("v194DestKind")?.value==="外"?"外":"内";
  const group=document.getElementById("v194DestGroup")?.value.trim()||(kind==="外"?"未分類":"社内");
  const outbound=!!document.getElementById("v194DestOutbound")?.checked;
  const rows=v194EnsureDestinations();
  if(rows.some(r=>r.name===name))return alert("同じ名前の納品先がすでにあります");
  const formal=document.getElementById("v194DestFormal")?.value.trim()||"";
  const weight=!!document.getElementById("v194DestWeight")?.checked;
  rows.push({name,formal,kind,group,outbound,weight,active:true});
  save();v194SyncOutDestinations();
  v194DestinationsPage("納品先を追加しました");
}
function v194ToggleDestOutbound(i){
  if(!canAdmin())return alert("納品先マスタは管理者のみです");
  const rows=v194EnsureDestinations(),row=rows[i];
  if(!row)return v194DestinationsPage("対象が見つかりません");
  row.outbound=!row.outbound;
  save();v194SyncOutDestinations();
  v194DestinationsPage(`${row.name} を出庫先に${row.outbound?"表示":"非表示に"}しました`);
}
function v194RemoveDest(i){
  if(!canAdmin())return alert("納品先マスタは管理者のみです");
  const rows=v194EnsureDestinations(),row=rows[i];
  if(!row)return v194DestinationsPage("対象が見つかりません");
  if(!confirm(`${row.name} を削除しますか？\n過去の出庫履歴は残ります。`))return;
  rows.splice(i,1);
  save();v194SyncOutDestinations();
  v194DestinationsPage("削除しました");
}
function v194CertOptions(v=""){
  return ['<option value="">なし</option>'].concat(V194_CERTS.map(c=>`<option value="${esc(c)}" ${c===v?"selected":""}>${esc(c)}</option>`)).join("");
}
function v194CertField(id="qrCertification",v=""){
  return `<label class="label">認証（任意）</label><select id="${id}" class="input">${v194CertOptions(v)}</select>`;
}
function v194CertValue(id){
  const el=document.getElementById(id);
  return el?String(el.value||"").trim()||null:null;
}
function v194CertLabel(v){return v?`（${v}）`:""}
async function v194ApplyCertOnCreate(qrKey){
  const v=v194CertValue("qrCertification");
  if(!v||!qrKey)return;
  try{await qrPatch("qr_lots",`qr_key=eq.${encodeURIComponent(qrKey)}`,{certification:v})}
  catch(e){alert("ロットは登録できましたが、認証区分だけ保存できませんでした。\nSupabaseのSQL（認証欄の追加）が未適用の可能性があります。")}
}
let v194SilentApplied=false;
async function v194SilentUpdate(){
  if(v194SilentApplied)return;
  if(canAdmin())return;
  if(!v133HasNewVersion()||!v133CanApplyUpdate())return;
  if(currentScreen!=='home')return;
  try{await v188IdbFlush?.()}catch(e){return}
  v194SilentApplied=true;
  v133ReloadForUpdate=true;
  v133WaitingWorker.postMessage({type:'SKIP_WAITING'});
}
v194SyncOutDestinations();

/* ============================================================
   v1.195 トリミング登録の分かりやすさ改善
   - 使用原料をロット検索（品名・入荷日・在庫有無）から選べるようにした
   - 在庫が無いロットもあとからまとめて登録できるようにした
   - 量目（例：10kg）しか無いロットも追加できるようにした
   - 「出力」表記を「出来高」に統一し、歩留まり0%の理由を表示
   ============================================================ */
var v195TrimLots=[],v195TrimLotsLoaded=false;
var v195TrimFilter={name:'',date:'',stock:'all'};
const V195_TRIM_LIST_MAX=300;

function v195TrimUnitWeight(lot){
  const u=v1115LotUnitWeight(lot);
  if(u>0)return u;
  const p=v1162ParsePackWeight(lot?.pack_weight);
  return p>0?p:null;
}

async function v195LoadTrimLots(){
  try{
    v195TrimLots=await qrSelect('qr_lots','select=*&order=received_date.desc&limit=1000')||[];
  }catch(e){
    try{ v195TrimLots=await qrSelect('qr_lots','select=*&limit=1000')||[]; }
    catch(e2){ v195TrimLots=[]; }
  }
  v195TrimLotsLoaded=true;
}
window.v195LoadTrimLots=v195LoadTrimLots;

function v195TrimLotQty(l){ return Number(l?.current_qty??l?.current_quantity??0)||0; }

function v195TrimLotCandidates(){
  const f=v195TrimFilter;
  const used=new Set(v1115Trimming.lots.map(x=>x.qrKey));
  const firstKey=v1115Trimming.lots[0]?.itemKey||'';
  const name=String(f.name||'').trim();
  return (v195TrimLots||[]).filter(l=>{
    if(used.has(l.qr_key))return false;
    if(firstKey&&String(l.item_id??l.item_name??'')!==firstKey)return false;
    if(name&&!(String(l.item_name||'').includes(name)||String(l.lot_no||'').includes(name)))return false;
    if(f.date&&String(l.received_date||'').slice(0,10)!==f.date)return false;
    const qty=v195TrimLotQty(l);
    if(f.stock==='in'&&!(qty>0))return false;
    if(f.stock==='out'&&qty>0)return false;
    return true;
  }).sort((a,b)=>String(b.received_date||'').localeCompare(String(a.received_date||''))
    ||String(a.item_name||'').localeCompare(String(b.item_name||''),'ja'));
}

function v195TrimLotOptionsHtml(){
  return v195TrimLotCandidates().slice(0,V195_TRIM_LIST_MAX).map(l=>{
    const qty=v195TrimLotQty(l),unit=qrLotUnit(l),pack=String(l.pack_weight||'').trim();
    const day=String(l.received_date||'').slice(0,10)||'入荷日なし';
    const stock=qty>0?`残 ${fmt(qty)}${unit}`:'在庫なし';
    const label=`${day}｜${l.item_name||'（品名未設定）'}｜${l.lot_no||l.qr_key}｜${stock}${pack?`（量目 ${pack}）`:''}`;
    return `<option value="${esc(l.qr_key||l.lot_no||'')}">${esc(label)}</option>`;
  }).join('');
}

function v195CaptureTrimFilter(){
  const n=document.getElementById('trimLotFilterName');
  const d=document.getElementById('trimLotFilterDate');
  const s=document.getElementById('trimLotFilterStock');
  if(n)v195TrimFilter.name=n.value;
  if(d)v195TrimFilter.date=d.value;
  if(s)v195TrimFilter.stock=s.value;
}
function v195ApplyTrimFilter(){ v195CaptureTrimFilter(); v1115RenderTrimming(); }
window.v195ApplyTrimFilter=v195ApplyTrimFilter;
function v195ClearTrimFilter(){ v195TrimFilter={name:'',date:'',stock:'all'}; v1115RenderTrimming(); }
window.v195ClearTrimFilter=v195ClearTrimFilter;

function v195AddTrimLotObject(lot){
  if(!lot)throw new Error('QRロットが見つかりません。検索して一覧から選ぶか、ロット番号を正確に入力してください。');
  if(v1115Trimming.lots.some(x=>x.qrKey===lot.qr_key))throw new Error('このQRロットは追加済みです');
  const itemKey=String(lot.item_id??lot.item_name??'');
  if(v1115Trimming.lots.length&&v1115Trimming.lots[0].itemKey!==itemKey)
    throw new Error(`同一品目のみ追加できます（現在：${v1115Trimming.lots[0].itemName}）`);
  const unitWeight=v195TrimUnitWeight(lot);
  v1115Trimming.lots.push({id:v1115Uuid(),qrKey:lot.qr_key,lotNo:lot.lot_no,itemName:lot.item_name,itemKey,
    currentQty:v195TrimLotQty(lot),currentKg:qrLotCurrentKg(lot),
    unitWeight:unitWeight>0?unitWeight:null,unit:qrLotUnit(lot),mode:unitWeight>0?'qty':'weight'});
}

async function v195PickTrimLot(){
  v195CaptureTrimFilter();
  const sel=document.getElementById('trimLotPicker'),key=sel?.value||'';
  if(!key)return;
  if(sel)sel.value='';
  const lot=(v195TrimLots||[]).find(l=>String(l.qr_key||'')===key||String(l.lot_no||'')===key)||null;
  try{ v195AddTrimLotObject(lot); v1115RenderTrimming(); }
  catch(e){ alert(e.message||'ロットを追加できませんでした'); }
}
window.v195PickTrimLot=v195PickTrimLot;

async function v195ReloadTrimLots(){
  v195CaptureTrimFilter();
  v195TrimLotsLoaded=false;
  v1115RenderTrimming();
  await v195LoadTrimLots();
  v1115RenderTrimming();
}
window.v195ReloadTrimLots=v195ReloadTrimLots;

v1115AddTrimLot=async function(){
  v195CaptureTrimFilter();
  const key=document.getElementById('trimQrKey')?.value.trim();
  if(!key)return alert('使用原料を検索して選ぶか、QRキー／ロット番号を入力してください');
  let lot=null;
  try{ lot=await qrFindLot(key); }catch(e){ lot=null; }
  if(!lot)lot=(v195TrimLots||[]).find(l=>String(l.qr_key||'')===key||String(l.lot_no||'')===key)||null;
  try{
    v195AddTrimLotObject(lot);
    const input=document.getElementById('trimQrKey');if(input)input.value='';
    v1115RenderTrimming();
  }catch(e){ alert(e.message||'ロットを追加できませんでした'); }
};
window.v1115AddTrimLot=v1115AddTrimLot;

v1115TrimmingTotals=function(){
  let input=0,output=0;
  for(const line of v1115Trimming.lots){
    const amount=v1115Num(document.getElementById(`trimLotAmount_${line.id}`)?.value);
    if(!(amount>0))continue;
    if(line.mode==='qty'){ if(line.unitWeight>0)input+=amount*line.unitWeight; }
    else input+=amount;
  }
  for(const line of v1115Trimming.outputs){
    const mode=document.getElementById(`trimOutMode_${line.id}`)?.value||'weight';
    const weight=v1115Num(document.getElementById(`trimOutWeight_${line.id}`)?.value);
    const qty=v1115Num(document.getElementById(`trimOutQty_${line.id}`)?.value);
    const unit=v1115Num(document.getElementById(`trimOutUnit_${line.id}`)?.value);
    output+=mode==='weight'?(weight>0?weight:0):(qty>0&&unit>0?qty*unit:0);
  }
  return{input:yen(input),output:yen(output),loss:yen(input-output),yield:input>0?yen(output/input*100):0};
};
window.v1115TrimmingTotals=v1115TrimmingTotals;

v1115RenderTrimming=function(){
  v1115CaptureTrimmingForm();
  const first=v1115Trimming.lots[0],totals=v1115TrimmingTotals();
  const lotCards=v1115Trimming.lots.map(line=>`<div class="card" style="margin:9px 0"><div class="row"><b>${esc(line.itemName)}</b><button class="btn danger" style="padding:6px 9px" ${seikaEventAttrs('click','v1115RemoveTrimLot',[line.id])}>削除</button></div><div class="small">ロット ${esc(line.lotNo||line.qrKey)}（日報の参照用。QR在庫は変更しません）</div><input type="hidden" id="trimLotMode_${line.id}" value="weight"><label class="label" style="margin-top:7px">使用原料 重量kg</label><input id="trimLotAmount_${line.id}" class="input" type="number" step="0.01" inputmode="decimal" min="0" value="${esc(line.amount||'')}" data-seika-input-action="v1115RefreshTrimmingSummary" data-seika-input-args="%5B%5D" placeholder="例：30">${line.unitWeight>0?`<div class="small">参考：1${esc(line.unit)} = ${fmtRounded(line.unitWeight)}kg</div>`:''}</div>`).join('');
  const itemOpts=specialItems('exchange').map(it=>`<option value="${esc(it.name)}"></option>`).join('');
  const outputCards=v1115Trimming.outputs.map((line,index)=>`<div class="card" style="margin:9px 0"><div class="row"><b>出来高 ${index+1}</b><button class="btn danger" style="padding:6px 9px" ${seikaEventAttrs('click','v1115RemoveTrimOutput',[line.id])}>削除</button></div><label class="label">日報に記録する入替品</label><select id="trimOutPick_${line.id}" class="input" ${seikaEventAttrs('change','c64PickOutputSel',[line.id])}>${typeof c64OutputOptionsHtml==='function'?c64OutputOptionsHtml(line):''}</select><input id="trimOutNormal_${line.id}" class="input" style="margin-top:6px" list="trimOutCandidates_${line.id}" value="${esc(specialItems('exchange').find(it=>String(it.id)===String(line.itemId||''))?.name||line.itemName||line.itemId||'')}" placeholder="候補に無いときはここに手入力" autocomplete="off"><div class="small">▼から選ぶと下の欄に入ります（候補は「入替品登録」で登録した品目）。候補に無いときは下の欄に手入力してください。</div><input type="hidden" id="trimOutMode_${line.id}" value="weight"><label class="label" style="margin-top:9px">出来高 重量kg</label><input id="trimOutWeight_${line.id}" class="input" type="number" step="0.01" min="0" inputmode="decimal" value="${esc(line.weight||'')}" placeholder="例：21" data-seika-input-action="v1115RefreshTrimmingSummary" data-seika-input-args="%5B%5D"></div>`).join('');
  const candidates=v195TrimLotCandidates();
  const shown=Math.min(candidates.length,V195_TRIM_LIST_MAX);
  const pickerNote=!v195TrimLotsLoaded?'ロットを読み込み中です…'
    :(candidates.length?`該当 ${candidates.length}件${candidates.length>shown?`（先頭${shown}件を表示）`:''}${first?` ／ ${esc(first.itemName)}のみ表示中`:''}`
    :'条件に合うロットがありません。品名や入荷日を変えるか、在庫の条件を「すべて」にしてください。');
  const f=v195TrimFilter;
  const yieldNote=totals.input<=0
    ?'<div class="small" style="color:#b45309;margin-top:6px">使用原料が未入力のため歩留まりは計算できません。上で使用原料のロットを追加し、使用量を入力してください。</div>'
    :(totals.output>totals.input+0.011
      ?'<div class="small" style="color:#0f766e;margin-top:6px">歩留まりが100%を超えています。10kg入りの原料に10kg以上入っていた場合などに起こります。実測どおりの数字のまま登録できます。</div>'
      :'');
  pageShell('日報登録',first?`${esc(first.itemName)} / ${v1115Trimming.lots.length}ロット`:'使用原料のロットを選んで追加してください',
`<div class="notice"><b>日報実績のみを保存します。</b><div class="small">通常在庫・QR在庫・QR操作履歴は変更せず、日報実績だけを保存します。事前に合わせた在庫はそのままです。<br>④の「廃棄した重さ」は、廃棄一覧に「トリミング廃棄」として自動で入ります。</div></div>
<div class="card"><b>① 作業日</b><label class="label">作業日</label><input id="trimWorkDate" type="date" class="input" value="${todayKey()}">
<div style="margin-top:10px;padding-top:10px;border-top:1px solid #e2e8f0"><b>② 使用原料</b>
<div class="row" style="margin-top:7px"><div><label class="label">品名・ロット番号</label><input id="trimLotFilterName" class="input" value="${esc(f.name||'')}" placeholder="例：キャベツ（入れるとすぐ下に候補が出ます）" autocomplete="off"></div><div><label class="label">入荷日</label><input id="trimLotFilterDate" type="date" class="input" value="${esc(f.date||'')}" ${seikaEventAttrs('change','v195ApplyTrimFilter',[])}></div></div>
<label class="label" style="margin-top:7px">在庫</label><select id="trimLotFilterStock" class="input" ${seikaEventAttrs('change','v195ApplyTrimFilter',[])}><option value="all" ${f.stock==='all'?'selected':''}>すべて</option><option value="in" ${f.stock==='in'?'selected':''}>在庫ありのみ</option><option value="out" ${f.stock==='out'?'selected':''}>在庫なしのみ</option></select>
<label class="label" style="margin-top:9px">候補から選ぶ（選ぶと使用原料に追加）</label>
<div id="trimLotList">${typeof v1640LotListHtml==='function'?v1640LotListHtml():''}</div></div>
<label class="label" style="margin-top:10px">QRキーまたはロット番号で追加（読取用）</label><div class="row"><input id="trimQrKey" class="input" placeholder="読取／入力"><button class="btn blue" data-seika-click-action="v1115AddTrimLot" data-seika-click-args="%5B%5D">ロット追加</button></div></div>
<div id="trimLotCards">${lotCards||'<div class="notice">まだ使用原料がありません。上の候補から押して選んでください。</div>'}</div>
<div class="card" style="margin:9px 0 0;padding:10px 14px"><b>③ 出来高</b></div>
<button class="btn btn2" style="width:100%" data-seika-click-action="v1115AddTrimOutput" data-seika-click-args="%5B%5D">＋ 出来高（入替品）を追加</button>
<div id="trimOutputCards">${outputCards||'<div class="notice">出来高を1件以上追加してください。</div>'}</div>
<div class="card"><b>重量集計</b><div id="trimTotals" class="grid" style="margin-top:8px"><div class="box">使用原料<b>${fmtRounded(totals.input)}kg</b></div><div class="box">出来高 合計<b>${fmtRounded(totals.output)}kg</b></div><div class="box">ロス<b>${fmtRounded(totals.loss)}kg</b></div><div class="box">歩留まり<b>${fmtRounded(totals.yield)}%</b></div></div><div id="trimYieldNote">${yieldNote}</div>
<div style="margin-top:12px;padding-top:10px;border-top:1px solid #e2e8f0"><b>④ 廃棄</b>
<label class="label" style="margin-top:6px" for="trimWasteKg">廃棄した重さ（kg）</label><input id="trimWasteKg" type="number" inputmode="decimal" step="0.01" min="0" class="input" placeholder="例：3.5">
<div class="small" id="trimWasteNote" style="margin-top:4px">ロス（使用原料−出来高）の重さが入ります。<br>登録すると廃棄一覧に「トリミング廃棄」として入ります。<br>廃棄入力で同じ分を入れないでください。</div></div>
<div style="margin-top:12px;padding-top:10px;border-top:1px solid #e2e8f0"><b>⑤ 確認して登録</b></div>
<label class="label" style="margin-top:6px">メモ（任意）</label><textarea id="trimNote" class="textarea" placeholder="作業内容・特記事項"></textarea>
<button class="btn green" style="width:100%;margin-top:12px" data-seika-click-action="v1115SaveTrimming" data-seika-click-args="%5B%5D">確認して日報を登録</button></div>`);
};
window.v1115RenderTrimming=v1115RenderTrimming;

const v195TrimmingPageBase=trimmingPage;
trimmingPage=async function(...args){
  const result=await v195TrimmingPageBase(...args);
  await v195LoadTrimLots();
  v1115RenderTrimming();
  return result;
};
window.trimmingPage=trimmingPage;


/* ===== v1.196 作業日の保持 / 作業日別の歩留まり原価 ===== */
let v196TrimWorkDate=todayKey();
let v196TrimNote='';
const v196RenderTrimmingBase=v1115RenderTrimming;
v1115RenderTrimming=function(...args){
  const r=v196RenderTrimmingBase.apply(this,args);
  const d=document.getElementById('trimWorkDate');
  if(d){
    d.value=v196TrimWorkDate||todayKey();
    d.addEventListener('change',()=>{v196TrimWorkDate=d.value||todayKey();});
  }
  const n=document.getElementById('trimNote');
  if(n){
    n.value=v196TrimNote||'';
    n.addEventListener('input',()=>{v196TrimNote=n.value;});
  }
  return r;
};
window.v1115RenderTrimming=v1115RenderTrimming;

const v196SaveTrimmingBase=v1115SaveTrimming;
v1115SaveTrimming=async function(...args){
  const r=await v196SaveTrimmingBase.apply(this,args);
  v196TrimNote='';
  return r;
};
window.v1115SaveTrimming=v1115SaveTrimming;

function v196DailyYieldHtml(rows){
  const map=new Map();
  for(const row of rows){
    const j=row.job||row;
    const date=j.work_date||'（作業日なし）';
    const item=j.source_item_name||'（品目未設定）';
    const key=date+'\u0001'+item;
    const a=map.get(key)||{date,item,input:0,out:0,cost:0,count:0,priced:true};
    a.input+=Number(j.input_weight_kg||0);
    a.out+=Number(j.output_weight_kg||0);
    a.count++;
    if(j.input_cost_yen===null||j.input_cost_yen===undefined)a.priced=false;
    else a.cost+=Number(j.input_cost_yen);
    map.set(key,a);
  }
  const list=[...map.values()].sort((x,y)=>x.date===y.date?x.item.localeCompare(y.item,'ja'):(x.date<y.date?1:-1));
  if(!list.length)return '<tr><td colspan="7" class="small">該当なし</td></tr>';
  let html='',prev=null;
  for(const a of list){
    if(a.date!==prev){
      const day=list.filter(x=>x.date===a.date);
      const dIn=day.reduce((s,x)=>s+x.input,0),dOut=day.reduce((s,x)=>s+x.out,0);
      const dPriced=day.every(x=>x.priced),dCost=day.reduce((s,x)=>s+x.cost,0);
      html+=`<tr style="background:#eef2f7"><td colspan="2"><b>${esc(a.date)}</b></td>`
        +`<td><b>${fmtRounded(dIn)}kg</b></td><td><b>${fmtRounded(dOut)}kg</b></td>`
        +`<td><b>${dIn?fmtRounded(dOut/dIn*100):'-'}%</b></td>`
        +`<td><b>${dPriced?money(dCost)+'円':'未計算'}</b></td>`
        +`<td><b>${dOut&&dPriced?money(dCost/dOut)+'円/kg':'未計算'}</b></td></tr>`;
      prev=a.date;
    }
    html+=`<tr><td></td><td>${esc(a.item)}<div class="small">${a.count}件</div></td>`
      +`<td>${fmtRounded(a.input)}kg</td><td>${fmtRounded(a.out)}kg</td>`
      +`<td>${a.input?fmtRounded(a.out/a.input*100):'-'}%</td>`
      +`<td>${a.priced?money(a.cost)+'円':'未計算'}</td>`
      +`<td>${a.out&&a.priced?money(a.cost/a.out)+'円/kg':'未計算'}</td></tr>`;
  }
  return html;
}

const v196RenderYieldBase=v1115RenderYieldReport;
v1115RenderYieldReport=function(rows,from,to){
  const r=v196RenderYieldBase.call(this,rows,from,to);
  try{
    const cards=document.querySelectorAll('.card');
    if(cards.length){
      const host=cards[cards.length-1].parentNode;
      const div=document.createElement('div');
      div.className='card';
      div.innerHTML='<b>作業日別（品目ごとの平均歩留まり原価）</b>'
        +'<div class="small" style="margin-top:4px">その作業日時点で採用された単価にもとづく平均です。</div>'
        +'<table class="table"><thead><tr><th>作業日</th><th>品目</th><th>使用</th><th>出来高</th>'
        +'<th>歩留まり</th><th>原料費</th><th>歩留まり原価<br>税抜円/kg</th></tr></thead><tbody>'
        +v196DailyYieldHtml(rows)+'</tbody></table>';
      host.appendChild(div);
    }
  }catch(e){}
  return r;
};
window.v1115RenderYieldReport=v1115RenderYieldReport;


/* ===== v1.197 作業日をアプリ内で修正 ===== */
function v197LotLabel(lots){
  if(!lots||!lots.length)return '<span class="small">ロット情報なし</span>';
  return lots.map(l=>{
    const no=l.lot_no||l.qr_key||'';
    const kg=Number(l.used_weight_kg||0);
    return `<div class="small">${esc(l.item_name||'')}｜${esc(no)}｜${fmtRounded(kg)}kg`
      +`${l.origin?'｜'+esc(l.origin):''}${l.supplier?'｜'+esc(l.supplier):''}</div>`;
  }).join('');
}

async function v197SaveWorkDate(jobId){
  const el=document.getElementById('v197date_'+jobId);
  if(!el||!el.value){alert('作業日を選んでください。');return;}
  if(!confirm(`この日報の作業日を ${el.value} に変更します。\n単価も作業日にあわせて計算し直します。`))return;
  try{
    const ans=await callRpc('update_trimming_job_work_date_v1197',{p_job_id:jobId,p_work_date:el.value});
    if(ans&&ans.ok===false){alert(ans.message||'変更できませんでした。');return;}
    if(typeof seikaYieldRange==='function')await seikaYieldRange();
    else location.reload();
  }catch(e){alert('変更できませんでした。\n'+(e&&e.message?e.message:e));}
}
window.v197SaveWorkDate=v197SaveWorkDate;

function v197EditHtml(rows){
  if(!rows||!rows.length)return '<div class="small">該当する日報がありません。</div>';
  return rows.map(row=>{
    const j=row.job||row, lots=row.lots||[];
    const id=j.id;
    return `<div style="padding:9px 0;border-top:1px solid #e2e8f0">
<div><b>${esc(j.source_item_name||'（品目未設定）')}</b>`
      +`<span class="small"> 使用${fmtRounded(j.input_weight_kg)}kg ／ 出来高${fmtRounded(j.output_weight_kg)}kg</span></div>
${v197LotLabel(lots)}
<div class="row" style="margin-top:6px;align-items:flex-end">
<div><label class="label">作業日</label>`
      +`<input id="v197date_${esc(id)}" type="date" class="input" value="${esc(j.work_date||'')}"></div>`
      +`<button class="btn blue" style="padding:8px 12px" ${seikaEventAttrs('click','v197SaveWorkDate',[id])}>この日報を保存</button>`
      +`</div></div>`;
  }).join('');
}

const v197RenderYieldBase=v1115RenderYieldReport;
v1115RenderYieldReport=function(rows,from,to){
  const r=v197RenderYieldBase.call(this,rows,from,to);
  try{
    const cards=document.querySelectorAll('.card');
    if(cards.length){
      const host=cards[cards.length-1].parentNode;
      const div=document.createElement('div');
      div.className='card';
      div.innerHTML='<b>作業日の修正</b>'
        +'<div class="small" style="margin-top:4px">使用したロットで日報を見分けて、正しい作業日に直してください。保存すると単価も計算し直します。</div>'
        +v197EditHtml(rows);
      host.appendChild(div);
    }
  }catch(e){}
  return r;
};
window.v1115RenderYieldReport=v1115RenderYieldReport;


/* ===== v1.198 操作ガイドに未掲載の機能を追加 ===== */
const V198_GUIDE_SECTIONS={
 trimming:{title:"日報を登録する",where:"ホーム → 製造・歩留まり → 日報を登録",
  steps:["作業日を選びます。前の日の分を入力するときは、必ずここを実際の作業日に変えてください。",
   "「使用原料」でロットを追加します。品名・ロット番号・入荷日・在庫の有無で絞り込めます。",
   "使った数量または重量を入力します。ケース品は量目から自動で重量に換算されます。",
   "「出来高」に入替品を追加し、重量kgを入力します。数量と1個あたりの重量からでも計算できます。",
   "使用重量・ロス・歩留まりを確認し、必要ならメモを入れて登録します。"],
  check:"登録後は「製造日報」で使用原料・出来高・歩留まりを、「歩留まり価格」で採用単価を確認できます。",
  caution:"通常在庫・QR在庫・QR操作履歴は変更されません。日報の実績だけを保存します。歩留まりが0%になるときは使用原料が入っていません。"},
 dailyReport:{title:"製造日報を見る",where:"ホーム → 製造・歩留まり → 製造日報",
  steps:["作業日を選んで「表示」を押します。前日・翌日のボタンでも移動できます。",
   "登録ごとにカードが並びます。使用原料はロット番号・入荷日・産地・仕入先つきで確認できます。",
   "出来高は入替品ごとの重量が出ます。数量と1個あたりの重量から登録した場合はその内訳も表示されます。",
   "廃棄（ロス）と歩留まりを確認します。"],
  check:"上部の「この日の合計」で、その日の使用原料・出来高・廃棄・歩留まりをまとめて確認できます。",
  caution:"ここでいう廃棄は、使用原料から出来高を引いた計算上のロスです。廃棄一覧に登録した数量は含みません。価格は表示しません。単価は「歩留まり価格」で確認してください。"},
 yield:{title:"歩留まり価格を見る・作業日を直す",where:"ホーム → 製造・歩留まり → 歩留まり価格",
  steps:["開始日と終了日を選び「絞り込む」を押します。",
   "「品目別集計」で、品目ごとの使用・出来高・歩留まり・原料費・歩留まり原価を確認します。",
   "「作業日別」で、その作業日時点の品目ごとの平均歩留まり原価を確認します。",
   "「明細」で1件ずつの採用単価と採用区分を確認します。区分は色付きのバッジで、詳しい理由は「根拠」を開くと読めます。",
   "「未計算の日報」がある場合は、仕入価格を登録してから「価格を再計算」を押します。",
   "使用原料や出来高の内訳は「製造日報」で確認します。",

   "作業日を間違えた日報は「作業日の修正」で直します。使ったロットが品名・ロット番号・産地・仕入先つきで出るので、それで日報を見分けて日付を直し保存します。"],
  check:"作業日を保存すると、その日付にあわせて単価も計算し直されます。",
  caution:"「未計算（価格未登録）」は、その品目の仕入価格が無いか、入荷日の週より後にしか価格が無い場合です。仕入れ価格表を確認してください。"},
 price:{title:"仕入れ価格を登録する",where:"ホーム → 仕入れ価格表",
  steps:["対象の週を選びます。価格は週単位で管理します。",
   "市場4社（水戸大同・水戸中央・東一・シティ）は「市場価格」として登録します。産地は空欄のままにします。",
   "契約産地は、品目・産地・仕入先をそろえて「契約価格」として登録します。",
   "税抜の円/kgで入力し、変更した行を保存します。"],
  check:"廃棄単価とトリミングの原料費は、この価格を①市場価格 ②契約価格 ③同一品目の平均 の順で採用します。市場価格は、廃棄した日の週（トリミングは原料の入荷日の週）の価格だけを使います。価格を保存・変更・持ち越しすると、その週の廃棄とトリミング日報の金額が自動で計算し直されます（手で直した単価・Excel出力済みも含む）。",
  caution:"その週の市場価格が未入力だと「未入力」になり、金額が出ません。「前の週」「次の週」ボタンや日付で週を選び、さかのぼって・先の週も登録できます。うまく反映されないときは「この週の価格を廃棄・トリミングに反映」を押します。"},
 weekly:{title:"週次廃棄レポートを作る",where:"ホーム → 週次廃棄レポート",
  steps:["対象の週を選びます。最初は先週（月〜日曜）が入っています。翌週の月曜日に先週分を印刷して現場へ共有します。",
   "テーマは対象の週ごとに自動で次のものに変わり、朝礼で伝える3つの行動も自動で入ります。必要ならテーマを選び直したり、書き換えたりできます。",
   "廃棄の金額・数量と、期首からの累計を確認します。",
   "「印刷」を押してA4で出力し、朝礼で配ります。"],
  check:"印刷プレビューでグラフと見出しの色が出ているか確認します。",
  caution:"iPadで色が出ないときは、印刷設定の「背景のグラフィック」を有効にしてください。"},
 dest:{title:"納品先マスタを管理する",where:"ホーム → QR在庫管理 → 納品先マスタ",
  steps:["社内・社外を切り替えて一覧を確認します。",
   "納品先を追加・編集します。社外は取引先ごとにまとまっています。",
   "QRロットの登録・編集では、認証区分（JGAP/GGAP）もあわせて設定します。"],
  check:"登録した納品先は、QR出庫の出庫先の候補に出ます。",
  caution:"プライムデリカ3工場（相模原・相模原第二・龍ケ崎）のレタスは、ケース数ではなく実重量kgで納品します。"},
 outbound:{title:"QRの出庫履歴を確認する",where:"ホーム → QR出庫履歴",
  steps:["期間・品名・出庫先で絞り込みます。",
   "一覧で、いつ・どのロットを・どこへ・何ケース出したかを確認します。",
   "件数が多いときは「さらに読み込む」を押します。"],
  check:"数量が合わないときは、ロット詳細の履歴とあわせて確認します。",
  caution:"出庫の取り消しはこの画面ではできません。実数調整で正しい残数に直します。"},
 batch:{title:"QRを連続で出庫する・作業を保留する",where:"QR在庫管理 → QR連続出庫／保留して終了",
  steps:["「QR連続出庫」で出庫先を決めてから、QRを続けて読み取ります。出庫先が「本社」のときは、本社への便と当日便／翌日便も選びます。",
   "QRを読まずに、「在庫一覧からまとめて選ぶ（全てのQRロット）」でチェックを入れて追加することもできます。",
   "QRロット一覧（在庫あり）でも、ロットごとの「まとめて出庫に入れる」にチェックを入れ、画面下の「選んだロットをまとめて出庫」を押すと、同じ流れで出庫できます。数量は最初から「ロット全て」が入ります。",
   "胡瓜などの規格別ロットは、まとめ出庫では「ロット全て」のときだけ出庫できます（全規格をまとめて出庫します）。一部だけ出すときは、通常の出庫画面で規格ごとの数を入れます。",
   "確認画面では、ロットごとに「ロット全て」を押すと残りの数が入ります。「全てのロットを『ロット全て』にする」で一度に入れられます。",
   "出庫先が「本社」のときは、全部登録したあとに貼り紙の印刷画面へまとめて切り替わります。1件ずつ「本社移動用の貼り紙を印刷」を押します。",
   "同じロットから別の出庫先へ続けるときは「同じQRを続けて出庫」を使います。",
   "途中で抜けるときは「保留して終了」で作業を残し、戻ってから続きを処理します。"],
  check:"保留した作業は自分のホームに残ります。処理し切ってから終業してください。",
  caution:"保留は個人ごとの作業です。他の人の画面には出ません。"},
 count:{title:"月末棚卸しをする",where:"ホーム → 棚卸しモード",
  steps:["対象の月を選んで開始します。第2・第3冷蔵庫はまとめて開始できます。",
   "開始した時点で、その月末時点の在庫が固定されます。あとから入出庫しても棚卸しの数字は動きません。",
   "実数を入力します。QRロットは読み取ると実数に加算されます。",
   "差異がある行は理由を選びます。",
   "内容を確認して確定します。差異が無くても確定できます。",
   "確定後にExcelを出力します。"],
  check:"確定すると、差異の分だけが月末日付の「棚卸し調整」として在庫履歴に入ります。",
  caution:"確定後の修正は管理者のみです。前の月の棚卸しが終わっていないと新しく開始できないことがあります。"},
 analysis:{title:"分析・判断支援を見る",where:"ホーム → 分析・判断支援",
  steps:["「在庫ロス分析」で、期間ごとの廃棄と在庫ロスの傾向を確認します。",
   "「品質レポート」で、仕入先ごとの品質評価の傾向を確認します。",
   "「判断支援」で、確認したほうがよい品目の候補を表示します。"],
  check:"数字の元になっているのは、廃棄入力・品質評価・QR操作の履歴です。",
  caution:"入力が漏れている期間は正しく集計されません。"},
 adminops:{title:"お知らせを出す・診断情報を確認する",where:"メニュー → 管理者お知らせ／管理者診断",
  steps:["「管理者お知らせ」で、全員のホームに出るお知らせを追加します。",
   "「管理者診断」で、同期状態やバージョンなどの診断情報を確認し、必要ならコピーして共有します。"],
  check:"お知らせは、追加後に自分のホームで表示を確認します。",
  caution:"不具合の連絡が届いたときは「連絡内容を確認」から対応状況を更新してください。"},
 pwa:{title:"アプリとして追加する・通知を受け取る",where:"メニュー → アプリ追加・PWA案内",
  steps:["案内にしたがって、この端末のホーム画面にアプリを追加します。",
   "通知を使う端末では「この端末で通知を受け取る」を押します。",
   "止めるときは「この端末の通知を停止」を押します。"],
  check:"追加後はブラウザではなくアプリのアイコンから開いてください。",
  caution:"通知の設定は端末ごとです。端末を替えたら設定し直しになります。"},
 qritems:{title:"QR対象品目を設定する",where:"QR在庫管理 → QR対象品目設定",
  steps:["QRで管理する品目を選んで追加します。",
   "対象から外すときは一覧から削除します。"],
  check:"対象にした品目は、通常の在庫入力ではなくQR在庫管理で入出庫します。",
  caution:"運用中の品目を外すと、通常在庫との二重管理になります。変更前に確認してください。"}
};
const V198_ROLE_ADD={
 admin:["trimming","dailyReport","yield","price","weekly","dest","outbound","batch","count","analysis","adminops","pwa","qritems"],
 worker:["trimming","dailyReport","yield","weekly","outbound","batch","count","analysis","pwa","qritems"],
 buyer:["dailyReport","yield","price","outbound","analysis","pwa"],
 sales:["dailyReport","yield","price","weekly","outbound","analysis","pwa"],
 clerk:["dailyReport","yield","price","weekly","outbound","pwa"],
 viewer:["dailyReport","yield","outbound","pwa"],
 office_viewer:["dailyReport","yield","outbound","pwa"]
};
(function v198ApplyGuides(){
  for(const [role,keys] of Object.entries(V198_ROLE_ADD)){
    const g=V195_ROLE_GUIDES[role];
    if(!g||!Array.isArray(g.sections))continue;
    for(const key of keys){
      const sec=V198_GUIDE_SECTIONS[key];
      if(!sec)continue;
      if(g.sections.some(x=>x.title===sec.title))continue;
      g.sections.push(sec);
    }
  }
})();


/* ===== v1.199 第1段階：APIをログイン中のユーザートークンで呼ぶ =====
   これまで Authorization に公開キーを入れていたため、全ての通信が
   未ログイン(anon)権限で実行されていた。ログイン済みならユーザーの
   アクセストークンを使う。トークンが無い場合は従来どおり公開キーに
   落ちるため、この段階では動作は止まらない。 */
function v199ApiHeaders(extra={}){
  let token='';
  try{ token=(typeof authToken==='function'&&authToken())||''; }catch(e){ token=''; }
  return {apikey:SUPABASE_KEY,
          Authorization:`Bearer ${token||SUPABASE_KEY}`,
          "Content-Type":"application/json", ...extra};
}
qrApiHeaders=v199ApiHeaders;
window.qrApiHeaders=v199ApiHeaders;

async function v199EnsureAuth(){
  try{ if(typeof authEnsure==='function') return await authEnsure(); }catch(e){}
  return false;
}
function v199IsAuthError(e){
  const m=String((e&&e.message)||e||'');
  return /401|403|JWT|jwt|PGRST301|token is expired|invalid claim/i.test(m);
}
async function v199RetryOnAuth(run){
  await v199EnsureAuth();
  try{ return await run(); }
  catch(e){
    if(!v199IsAuthError(e))throw e;
    let ok=false;
    try{ ok=(typeof v188RefreshAuthOnce==='function')?await v188RefreshAuthOnce():false; }catch(_){}
    if(!ok)throw e;
    return await run();
  }
}
window.v199RetryOnAuth=v199RetryOnAuth;

const v199CallRpcBase=callRpc;
callRpc=async function(name,args){
  return await v199RetryOnAuth(()=>v199CallRpcBase(name,args));
};
window.callRpc=callRpc;

const v199SelectBase=qrSelect;
qrSelect=async function(...a){ return await v199RetryOnAuth(()=>v199SelectBase.apply(this,a)); };
window.qrSelect=qrSelect;

const v199InsertBase=qrInsert;
qrInsert=async function(...a){ return await v199RetryOnAuth(()=>v199InsertBase.apply(this,a)); };
window.qrInsert=qrInsert;

const v199PatchBase=qrPatch;
qrPatch=async function(...a){ return await v199RetryOnAuth(()=>v199PatchBase.apply(this,a)); };
window.qrPatch=qrPatch;

const v199DeleteBase=qrDelete;
qrDelete=async function(...a){ return await v199RetryOnAuth(()=>v199DeleteBase.apply(this,a)); };
window.qrDelete=qrDelete;

/* 管理者診断で、いま何の権限で通信しているかを確認できるようにする */
window.v199AuthDiag=function(){
  let token='';
  try{ token=(typeof authToken==='function'&&authToken())||''; }catch(e){}
  const mode=token?'authenticated（ユーザートークン）':'anon（公開キー）';
  let exp='-';
  try{ if(typeof authExpiryMs==='function'&&authExpiryMs()>0) exp=new Date(authExpiryMs()).toLocaleString('ja-JP'); }catch(e){}
  return {mode,tokenLength:token.length,expiresAt:exp,version:window.APP_VERSION};
};

const v1200GoBackBase=goBack;
goBack=function(){
  const s=currentScreen;
  if(s==="v1200DailyReport"||s==="yieldReport"||s==="v1200Trimming")return v1200ProductionHome();
  return v1200GoBackBase();
};
window.goBack=goBack;
const v1200TrimmingBase=trimmingPage;
trimmingPage=function(...a){const r=v1200TrimmingBase(...a);try{setScreen("v1200Trimming",[])}catch(e){}return r};
window.trimmingPage=trimmingPage;


/* ===== 多言語ユーザー（フレンキ：インドネシア語 ／ ヒェップ：ベトナム語） ===== */
const V200_VI={"ログイン":"Đăng nhập","安全なログイン":"Đăng nhập an toàn","名前を選択してください":"Vui lòng chọn tên của bạn","パスワード":"Mật khẩu","確認中...":"Đang kiểm tra...","名前を選んで、パスワードを入力してください。":"Hãy chọn tên của bạn, sau đó nhập mật khẩu.","現場オペレーション管理":"Quản lý vận hành tại hiện trường","入庫から在庫、廃棄、出庫まで。":"Từ nhập hàng, tồn kho, loại bỏ đến xuất hàng.","青果センターの毎日をひとつに。":"Gộp mọi công việc hằng ngày của trung tâm rau quả vào một hệ thống.","戻る":"Quay lại","ホーム":"Trang chủ","再読込":"Tải lại","メニュー":"Menu","閉じる":"Đóng","次へ":"Tiếp theo","保存":"Lưu","登録":"Lưu","保存中...":"Đang lưu...","登録中...":"Đang lưu...","読み込み中...":"Đang tải...","エラー":"Đã xảy ra lỗi","権限がありません":"Bạn không có quyền.","在庫管理":"Quản lý tồn kho","QR在庫管理":"Quản lý tồn kho QR","在庫報告コピー":"Sao chép báo cáo tồn kho","品目設定":"Cài đặt mặt hàng","適正在庫設定":"Cài đặt tồn kho hợp lý","産地状況・市場動向メモ":"Ghi chú tình hình vùng trồng và thị trường","網コンテナ在庫":"Tồn kho thùng lưới","廃棄管理":"Quản lý hàng loại bỏ","分析・判断支援":"Phân tích và hỗ trợ quyết định","本日入力済み":"Đã nhập hôm nay","本日未入力":"Chưa nhập hôm nay","発注候補":"Mặt hàng nên đặt thêm","過多品目":"Mặt hàng tồn nhiều","担当品目":"Mặt hàng phụ trách","最終入力":"Lần nhập gần nhất","記録なし":"Chưa có dữ liệu","最新の情報を確認する場合は、再読込を押してください。":"Nhấn “Tải lại” để xem thông tin mới nhất.","QR入庫":"Nhập hàng QR","品目と数量を入力して登録します":"Nhập tên mặt hàng và số lượng rồi lưu.","入庫する品目":"Mặt hàng nhập vào","入庫日":"Ngày nhập hàng","品目":"Tên mặt hàng","マスターから選択してください":"Chọn từ danh sách","通常品目の後に、じゃがいも品種をまとめて表示します。":"Tên mặt hàng hiển thị bằng tiếng Nhật.","担当者":"Người phụ trách","仕入れ担当者":"Người phụ trách thu mua","荷受け担当者":"Người nhận hàng","品目から自動入力":"Tự động điền theo mặt hàng","品目選択後に自動入力":"Tự động điền sau khi chọn mặt hàng","荷姿と数量":"Quy cách đóng gói và số lượng","荷姿":"Quy cách đóng gói","仕入先・保管場所":"Nhà cung cấp và nơi bảo quản","仕入先":"Nhà cung cấp","産地":"Vùng sản xuất","規格など（任意）":"Quy cách và thông tin khác (không bắt buộc)","保管場所":"Nơi bảo quản","登録してQR貼り紙PDFへ":"Lưu và mở PDF nhãn QR","PDFを開く・印刷":"Mở và in PDF","必須":"Bắt buộc","任意":"Không bắt buộc","未設定":"Chưa thiết lập","未確定":"Chưa xác định","確定":"Đã xác định","品質評価":"Đánh giá chất lượng","QR品質評価":"Đánh giá chất lượng QR","品質評価を訂正":"Sửa đánh giá chất lượng","在庫数量は変わりません":"Số lượng tồn kho không thay đổi","品質状態だけをロットへ記録します。不良品を在庫から減らす場合は、評価後にQR廃棄を登録してください。":"Chỉ tình trạng chất lượng được ghi vào lô hàng. Nếu muốn trừ hàng hỏng khỏi tồn kho, hãy đăng ký loại bỏ QR sau khi đánh giá.","総合判定":"Kết quả tổng thể","良好":"Tốt","要確認":"Cần kiểm tra","不良":"Không đạt","確認された状態（複数選択可）":"Tình trạng phát hiện (có thể chọn nhiều)","写真（任意・最大3枚）":"Ảnh (không bắt buộc, tối đa 3 ảnh)","問題時のみ登録します。長辺1280px、1枚350KB以下へ自動圧縮します。":"Chỉ thêm ảnh khi có vấn đề.","写真ライブラリから選択":"Chọn từ thư viện ảnh","メモ（任意）":"Ghi chú (không bắt buộc)","訂正理由":"Lý do sửa","品質評価を登録":"Lưu đánh giá chất lượng","品質評価を保存しています":"Đang lưu đánh giá chất lượng","品質評価の確認":"Xác nhận đánh giá chất lượng","訂正した評価を登録":"Lưu đánh giá đã sửa","傷み":"Hư hỏng","変色":"Đổi màu","腐敗":"Thối","カビ":"Mốc","打撲・傷":"Dập hoặc trầy xước","しおれ":"Héo","異臭":"Mùi lạ","規格外":"Không đạt quy cách","温度異常":"Nhiệt độ bất thường","その他":"Khác","仕入先を入力":"Nhập nhà cung cấp","例：茨城 → 茨城県産":"Ví dụ: Ibaraki","例：3L、秀品、フジ用":"Ví dụ: 3L, hàng loại tốt, dùng cho Fuji","品質状態や確認内容":"Tình trạng chất lượng hoặc nội dung kiểm tra","例：判定項目の選択間違い":"Ví dụ: chọn sai mục đánh giá","パスワードを入力してください。":"Vui lòng nhập mật khẩu.","再ログインしてください。":"Vui lòng đăng nhập lại.","通信状況を確認してください。":"Vui lòng kiểm tra kết nối mạng.","登録後も在庫数量は変わりません。":"Sau khi lưu, số lượng tồn kho vẫn không thay đổi.","なし":"Không có","写真":"Ảnh","状態":"Tình trạng","判定":"Kết quả","品質評価一覧":"Danh sách đánh giá chất lượng","評価済みロット・写真を確認":"Xem lô đã đánh giá và ảnh","QRロットごとの最新評価を検索・確認":"Tìm và xem đánh giá mới nhất của từng lô QR","評価月":"Tháng đánh giá","すべて":"Tất cả","品名の一部":"Một phần tên mặt hàng","未確認の評価だけ表示":"Chỉ hiển thị đánh giá chưa xác nhận","検索":"Tìm kiếm","条件をクリア":"Xóa điều kiện","評価を読み込んでいます...":"Đang tải đánh giá...","表示中":"Đang hiển thị","全":"Tổng","件":"mục","不良を先頭に、要確認・良好の順で表示します。訂正前の評価は除外し、最新評価だけを表示しています。":"Thứ tự hiển thị: Không đạt, Cần kiểm tra, rồi Tốt. Chỉ hiển thị đánh giá mới nhất.","条件に一致する品質評価はありません。":"Không có đánh giá chất lượng phù hợp.","さらに50件読み込む":"Tải thêm 50 mục","状態：":"Tình trạng:","メモ：":"Ghi chú:","評価者：":"Người đánh giá:","写真：":"Ảnh:","確認不要":"Không cần xác nhận","確認済み":"Đã xác nhận","未確認":"Chưa xác nhận","QRロット詳細":"Chi tiết lô QR","写真を見る":"Xem ảnh","確認済みにする":"Đánh dấu đã xác nhận","担当未設定":"Chưa có người phụ trách","読み込みに失敗しました。通信状況を確認して再度検索してください。":"Tải thất bại. Vui lòng kiểm tra kết nối rồi tìm lại.","表示順":"Thứ tự hiển thị","評価順（不良・要確認・良好）":"Theo kết quả đánh giá (Không đạt, Cần kiểm tra, Tốt)","入荷日が新しい順":"Ngày nhập mới nhất trước","入荷日が古い順":"Ngày nhập cũ nhất trước","入荷日：":"Ngày nhập:","評価順で表示しています。訂正前の評価は除外し、最新評価だけを表示しています。":"Đang hiển thị theo kết quả đánh giá. Chỉ hiển thị đánh giá mới nhất.","入荷日が新しい順で表示しています。訂正前の評価は除外し、最新評価だけを表示しています。":"Đang hiển thị từ ngày nhập mới nhất. Chỉ hiển thị đánh giá mới nhất.","入荷日が古い順で表示しています。訂正前の評価は除外し、最新評価だけを表示しています。":"Đang hiển thị từ ngày nhập cũ nhất. Chỉ hiển thị đánh giá mới nhất.","品目担当（旧データ）":"Người phụ trách mặt hàng (dữ liệu cũ)","訂正履歴再送エラー":"Lỗi gửi lại lịch sử sửa"};
const V200_USER_LANGS={furenki:"id",hiep:"vi"};
const V200_DICTS={id:V138_ID,vi:V200_VI};
const V200_LANG_LABELS={ja:"日本語",id:"Bahasa Indonesia",vi:"Tiếng Việt"};
const V200_MEMO_NOTE={id:"Tulis dalam bahasa Jepang (jika perlu, tanyakan kepada petugas Jepang).",vi:"Vui lòng viết bằng tiếng Nhật (nếu cần, hãy hỏi nhân viên người Nhật)."};
function v200LoginSelected(){return currentScreen==="login"?(document.getElementById("loginUser")?.value||""):""}
function v200WorkerLang(){return db?.role==="worker"?(V200_USER_LANGS[db?.userId]||""):""}
function v200SelectedLang(){return V200_USER_LANGS[v200LoginSelected()]||""}
function v200Lang(){return v200WorkerLang()||v200SelectedLang()}
function v200CurrentUserId(){if(v200WorkerLang())return db.userId;const sel=v200LoginSelected();return V200_USER_LANGS[sel]?sel:""}
function v200Key(id){return V138_I18N_USER_PREFIX+id}
function v200Read(){const id=v200CurrentUserId();if(!id)return"ja";try{const v=localStorage.getItem(v200Key(id));return v===V200_USER_LANGS[id]?v:"ja"}catch(_){return"ja"}}
function v200Dict(){return V200_DICTS[v138Language]||null}
v139IsFurenkiWorker=function(){return!!v200WorkerLang()};
v139IsFurenkiSelected=function(){return!!v200SelectedLang()};
v139CanUseLanguage=function(){return!!v200Lang()};
v139ReadFurenkiLanguage=function(){return v200Read()};
v138T=function(value){const text=String(value??"");if(!v139CanUseLanguage())return text;const d=v200Dict();return d?(d[text]||text):text};
v138LanguageKey=function(){const id=v200CurrentUserId();return id?v200Key(id):""};
v138ApplyLanguage=function(language){const allow=v200Lang();if(!allow){v139ForceJapanese();return}v138Language=language===allow?allow:"ja";document.documentElement.lang=v138Language;const id=v200CurrentUserId();if(id){try{localStorage.setItem(v200Key(id),v138Language)}catch(_){}}};
v138RestoreLanguage=function(){if(!v200WorkerLang()){v139ForceJapanese();return}v138Language=v200Read();document.documentElement.lang=v138Language};
v138LanguageSwitchHtml=function(){const allow=v200Lang();if(!allow)return"";const btn=(code,label)=>`<button type="button" class="${v138Language===code?"on":""}" data-seika-click-action="v138SetLanguage" data-seika-click-args="${encodeURIComponent(JSON.stringify([code]))}">${label}</button>`;return`<div class="v138LangSwitch" role="group" aria-label="Language">${btn("ja",V200_LANG_LABELS.ja)}${btn(allow,V200_LANG_LABELS[allow])}</div>`};
v138SetLanguage=function(language){const allow=v200Lang();if(!allow){v139ForceJapanese();return}const id=v200CurrentUserId();v138ApplyLanguage(language);if(db?.user){renderCurrent();return}login();const select=document.getElementById("loginUser");if(select&&id)select.value=id;v139RefreshLoginLanguageSwitch()};
v138TextNode=function(node){if(!v139CanUseLanguage())return;const d=v200Dict();if(!d)return;const source=node.nodeValue,trimmed=source.trim();if(!trimmed||!d[trimmed])return;node.nodeValue=source.replace(trimmed,d[trimmed])};
v138TranslateElement=function(el){if(!el||!v139CanUseLanguage()||!v200Dict())return;const walker=document.createTreeWalker(el,NodeFilter.SHOW_TEXT),nodes=[];while(walker.nextNode())nodes.push(walker.currentNode);nodes.forEach(v138TextNode)};
v138TranslateScreen=function(){if(!v139CanUseLanguage()){v139ForceJapanese();return}document.documentElement.lang=v138Language;const dict=v200Dict();const common=[...document.querySelectorAll(".headAction,.title,.head .sub,#syncInfo")];common.forEach(v138TranslateElement);const screens=["login","home","qrHome","qrCreatePage","v1102QualityPage"];if(!screens.includes(currentScreen))return;const selectors=".opsLoginScreen h1,.opsLoginScreen h2,.opsLoginScreen .small,.opsLoginScreen .opsLogoSub,.homeSummary .summaryLabel,.homePrimary button,.qrCreateForm h2,.qrCreateForm .label,.qrCreateForm .small,.qrCreateForm button,.qrCreateForm .qrReadOnlyField,.qrCreateForm .notice,#v1102ProblemFields,.wrap > .notice,.wrap > .card > .label,.wrap > .card > .small,.wrap > .card > button,.wrap > .card > .grid label,.wrap > .card > .grid .box";document.querySelectorAll(selectors).forEach(v138TranslateElement);document.querySelectorAll(".qrCreateForm input[placeholder],.qrCreateForm textarea[placeholder],#v1102QualityMemo,#v1102CorrectionReason").forEach(el=>{const placeholder=el.getAttribute("placeholder");if(dict&&dict[placeholder])el.setAttribute("placeholder",dict[placeholder])});if(currentScreen==="v1102QualityPage"){const memo=document.getElementById("v1102QualityMemo"),note=V200_MEMO_NOTE[v138Language];if(memo&&note){memo.setAttribute("placeholder",note);let hint=document.getElementById("v138JapaneseMemoNote");if(!hint){hint=document.createElement("div");hint.id="v138JapaneseMemoNote";hint.className="small";hint.textContent=note;memo.insertAdjacentElement("beforebegin",hint)}else hint.textContent=note}}};
v139RefreshLoginLanguageSwitch=function(){const holder=document.querySelector(".v138LoginLanguage");if(!holder)return;if(!v200SelectedLang()){holder.hidden=true;holder.innerHTML="";return}holder.hidden=false;v138Language=v200Read();document.documentElement.lang=v138Language;holder.innerHTML=v138LanguageSwitchHtml();v138TranslateScreen()};
v139HandleLoginUserChange=function(){const selected=document.getElementById("loginUser")?.value||"";if(V200_USER_LANGS[selected]){v139RefreshLoginLanguageSwitch();return}v139ForceJapanese();login();const replacement=document.getElementById("loginUser");if(replacement)replacement.value=selected};
const v200LoginUsersCore=v188LoginUsers;
v188LoginUsers=function(){const rows=v200LoginUsersCore();if(!rows.some(row=>row[0]==="hiep"))rows.push(["hiep","ヒェップ","青果社員"]);return rows};
v138RestoreLanguage();


/* ===== 外国人スタッフ向け自動翻訳＋ふりがな（フレンキ：インドネシア語／ヒェップ：ベトナム語） ===== */
const V201_LEX={"ui":{"QR入庫":{"vi":"Nhập hàng QR","id":"Penerimaan Barang QR"},"QR在庫管理":{"vi":"Quản lý tồn kho QR","id":"Pengelolaan stok QR"},"QRキーまたはロット番号で追加（読取用）":{"vi":"Thêm bằng mã QR hoặc số lô (để quét)","id":"Tambah dengan kunci QR atau nomor lot (untuk pemindaian)"},"QR廃棄の取得に失敗しました。通常廃棄は表示を継続しています。":{"vi":"Không lấy được dữ liệu loại bỏ QR. Dữ liệu loại bỏ thường vẫn được hiển thị.","id":"Gagal mengambil data pembuangan QR. Pembuangan biasa tetap ditampilkan."},"QR管理対象外のため登録できません。":{"vi":"Không thể lưu vì mặt hàng này không thuộc diện quản lý QR.","id":"Tidak bisa disimpan karena barang ini bukan objek pengelolaan QR."},"Excel出力と履歴の確認・整理":{"vi":"Xuất Excel và kiểm tra, sắp xếp lịch sử","id":"Ekspor Excel serta periksa dan rapikan riwayat"},"SEIKA＋をホーム画面へ追加できます":{"vi":"Có thể thêm SEIKA＋ vào màn hình chính","id":"SEIKA＋ dapat ditambahkan ke layar utama"},"▼ 入荷日｜品名｜ロット番号｜在庫 から選ぶ":{"vi":"▼ Chọn theo Ngày hàng về｜Tên hàng｜Số lô｜Tồn kho","id":"▼ Pilih dari Tanggal kedatangan｜Nama barang｜Nomor lot｜Stok"},"● オンライン":{"vi":"● Trực tuyến","id":"● Online"},"⚠ 確認が必要です":{"vi":"⚠ Cần kiểm tra","id":"⚠ Perlu diperiksa"},"この品目の仕入れ担当者は未設定です。担当者を選択してください。":{"vi":"Mặt hàng này chưa có người phụ trách thu mua. Hãy chọn người phụ trách.","id":"Barang ini belum ada penanggung jawab pembelian. Silakan pilih penanggung jawab."},"すべて":{"vi":"Tất cả","id":"Semua"},"その他":{"vi":"Khác","id":"Lainnya"},"なし":{"vi":"Không có","id":"Tidak ada"},"まだ使用原料がありません。上の候補から押して選んでください。":{"vi":"Chưa có nguyên liệu sử dụng. Hãy tìm và chọn ở phía trên.","id":"Belum ada bahan yang dipakai. Silakan cari dan pilih di atas."},"アイコンから直接起動し、広い画面で利用できます。":{"vi":"Có thể mở trực tiếp từ biểu tượng và dùng trên màn hình rộng.","id":"Bisa dibuka langsung dari ikon dan digunakan pada layar lebar."},"アプリ追加・PWA案内":{"vi":"Thêm ứng dụng / Hướng dẫn PWA","id":"Tambah aplikasi / Panduan PWA"},"エラー":{"vi":"Lỗi","id":"Kesalahan"},"サポート":{"vi":"Hỗ trợ","id":"Dukungan"},"ダンボール・コンテナ・紙袋は量目の入力が必須です。":{"vi":"Với thùng giấy, thùng nhựa và túi giấy, bắt buộc phải nhập trọng lượng đóng gói.","id":"Untuk kardus, kontainer, dan kantong kertas, berat kemasan wajib diisi."},"トリミング登録":{"vi":"Đăng ký sơ chế (gọt tỉa)","id":"Pendaftaran trimming"},"日報登録":{"vi":"Đăng ký báo cáo ngày","id":"Pendaftaran laporan harian"},"パレット別貼り紙":{"vi":"Giấy dán theo từng pallet","id":"Label per palet"},"パレット別貼り紙数量":{"vi":"Số lượng giấy dán theo từng pallet","id":"Jumlah label per palet"},"パレット枚数（自動）":{"vi":"Số pallet (tự động)","id":"Jumlah palet (otomatis)"},"ホームへ":{"vi":"Về trang chủ","id":"Ke beranda"},"マスターから選択してください":{"vi":"Hãy chọn từ danh sách","id":"Silakan pilih dari daftar"},"メニュー":{"vi":"Menu","id":"Menu"},"メモ（任意）":{"vi":"Ghi chú (không bắt buộc)","id":"Catatan (opsional)"},"ログアウト":{"vi":"Đăng xuất","id":"Keluar"},"ログイン期限が切れました。入力内容は端末に保持されています。再ログインしてください。":{"vi":"Phiên đăng nhập đã hết hạn. Nội dung bạn nhập vẫn được lưu trên thiết bị. Hãy đăng nhập lại.","id":"Sesi login sudah berakhir. Isian Anda masih tersimpan di perangkat. Silakan masuk kembali."},"ロス":{"vi":"Hao hụt","id":"Kerugian"},"ロット追加":{"vi":"Thêm lô hàng","id":"Tambah lot"},"今は表示しない":{"vi":"Hiện không hiển thị","id":"Jangan tampilkan sekarang"},"今日の作業":{"vi":"Công việc hôm nay","id":"Pekerjaan hari ini"},"仕入れ価格表":{"vi":"Bảng giá thu mua","id":"Tabel harga pembelian"},"仕入れ担当者":{"vi":"Người phụ trách thu mua","id":"Penanggung jawab pembelian"},"仕入先":{"vi":"Nhà cung cấp","id":"Pemasok"},"仕入先を入力":{"vi":"Nhập nhà cung cấp","id":"Masukkan pemasok"},"仕入先・保管場所":{"vi":"Nhà cung cấp và nơi bảo quản","id":"Pemasok dan lokasi penyimpanan"},"作業内容・特記事項":{"vi":"Nội dung công việc và ghi chú đặc biệt","id":"Isi pekerjaan dan catatan khusus"},"作業日":{"vi":"Ngày làm việc","id":"Tanggal kerja"},"使い方の確認と連絡":{"vi":"Xem hướng dẫn và liên hệ","id":"Lihat cara pakai dan kontak"},"使用原料":{"vi":"Nguyên liệu sử dụng","id":"Bahan yang dipakai"},"使用原料が未入力のため歩留まりは計算できません。上で使用原料のロットを追加し、使用量を入力してください。":{"vi":"Chưa nhập nguyên liệu sử dụng nên không tính được tỷ lệ thành phẩm. Hãy thêm lô nguyên liệu ở trên và nhập lượng sử dụng.","id":"Bahan yang dipakai belum diisi sehingga rendemen tidak bisa dihitung. Tambahkan lot bahan di atas lalu isi jumlah pemakaian."},"使用原料のロットを検索して追加してください":{"vi":"Hãy tìm và thêm lô nguyên liệu sử dụng","id":"Silakan cari dan tambahkan lot bahan yang dipakai"},"使用原料をさがす":{"vi":"Tìm nguyên liệu sử dụng","id":"Cari bahan yang dipakai"},"使用原料・出来高を入力":{"vi":"Nhập nguyên liệu sử dụng và sản lượng","id":"Isi bahan yang dipakai dan hasil produksi"},"使用原料・出来高・廃棄・歩留まり":{"vi":"Nguyên liệu sử dụng / Sản lượng / Loại bỏ / Tỷ lệ thành phẩm","id":"Bahan dipakai / Hasil produksi / Pembuangan / Rendemen"},"例：15（自動でkg）":{"vi":"Ví dụ: 15 (tự động tính kg)","id":"Contoh: 15 (otomatis kg)"},"例：200":{"vi":"Ví dụ: 200","id":"Contoh: 200"},"例：30":{"vi":"Ví dụ: 30","id":"Contoh: 30"},"例：3L、秀品、フジ用":{"vi":"Ví dụ: 3L, hàng loại tốt, dùng cho Fuji","id":"Contoh: 3L, kelas bagus, untuk Fuji"},"例：キャベツ":{"vi":"Ví dụ: bắp cải","id":"Contoh: kubis"},"例：茨城 → 茨城県産":{"vi":"Ví dụ: Ibaraki → sản xuất tại tỉnh Ibaraki","id":"Contoh: Ibaraki → produksi Prefektur Ibaraki"},"保管場所":{"vi":"Nơi bảo quản","id":"Lokasi penyimpanan"},"入庫する品目":{"vi":"Mặt hàng nhập vào","id":"Barang yang diterima"},"入庫日":{"vi":"Ngày nhập hàng","id":"Tanggal penerimaan"},"入荷日":{"vi":"Ngày hàng về","id":"Tanggal kedatangan"},"再読み込み":{"vi":"Tải lại","id":"Muat ulang"},"再読込":{"vi":"Tải lại","id":"Muat ulang"},"出来高 合計":{"vi":"Tổng sản lượng","id":"Total hasil produksi"},"出来高を1件以上追加してください。":{"vi":"Hãy thêm ít nhất một dòng sản lượng.","id":"Tambahkan minimal satu data hasil produksi."},"単位は自動で「ケース」になります。空白や複数の数字は入力できません（例：100 1 は不可）。":{"vi":"Đơn vị tự động là “thùng”. Không được để trống hoặc nhập nhiều số (ví dụ: 100 1 là không được).","id":"Satuan otomatis menjadi “kotak”. Tidak boleh kosong atau berisi beberapa angka (contoh: 100 1 tidak boleh)."},"単協名を入力（部分一致候補）":{"vi":"Nhập tên hợp tác xã (gợi ý khớp một phần)","id":"Masukkan nama koperasi (saran kecocokan sebagian)"},"単協名（任意）":{"vi":"Tên hợp tác xã (không bắt buộc)","id":"Nama koperasi (opsional)"},"同一品目の直近ロットを候補として反映":{"vi":"Áp dụng lô gần nhất của cùng mặt hàng làm gợi ý","id":"Terapkan lot terbaru dari barang yang sama sebagai saran"},"品名・ロット番号":{"vi":"Tên hàng / Số lô","id":"Nama barang / Nomor lot"},"品目":{"vi":"Mặt hàng","id":"Barang"},"品目と数量を入力して登録します":{"vi":"Nhập tên mặt hàng và số lượng rồi lưu","id":"Isi nama barang dan jumlah lalu simpan"},"品目設定":{"vi":"Cài đặt mặt hàng","id":"Pengaturan barang"},"在庫":{"vi":"Tồn kho","id":"Stok"},"在庫ありのみ":{"vi":"Chỉ hàng còn tồn","id":"Hanya yang ada stok"},"在庫なしのみ":{"vi":"Chỉ hàng đã hết","id":"Hanya yang stok habis"},"在庫入力を開く":{"vi":"Mở nhập tồn kho","id":"Buka input stok"},"在庫報告コピー":{"vi":"Sao chép báo cáo tồn kho","id":"Salin laporan stok"},"在庫管理":{"vi":"Quản lý tồn kho","id":"Pengelolaan stok"},"年月":{"vi":"Năm / tháng","id":"Tahun / bulan"},"廃棄を入力する":{"vi":"Nhập hàng loại bỏ","id":"Input pembuangan"},"廃棄一覧":{"vi":"Danh sách hàng loại bỏ","id":"Daftar pembuangan"},"廃棄管理":{"vi":"Quản lý hàng loại bỏ","id":"Pengelolaan pembuangan"},"必須":{"vi":"Bắt buộc","id":"Wajib"},"戻る":{"vi":"Quay lại","id":"Kembali"},"担当者":{"vi":"Người phụ trách","id":"Penanggung jawab"},"採用単価・歩留まり原価":{"vi":"Đơn giá áp dụng và giá vốn theo tỷ lệ thành phẩm","id":"Harga satuan yang dipakai dan harga pokok rendemen"},"数量（ケース・必須・数字のみ）":{"vi":"Số lượng (thùng, bắt buộc, chỉ nhập số)","id":"Jumlah (kotak, wajib, hanya angka)"},"数量＋量目で管理します。":{"vi":"Quản lý bằng số lượng và trọng lượng đóng gói.","id":"Dikelola dengan jumlah dan berat kemasan."},"日報の登録と実績・原価の確認":{"vi":"Đăng ký báo cáo ngày và xem kết quả, giá vốn","id":"Simpan laporan harian dan lihat hasil serta harga pokok"},"日報を登録":{"vi":"Đăng ký báo cáo ngày","id":"Simpan laporan harian"},"日報実績のみを保存します。":{"vi":"Chỉ lưu kết quả của báo cáo ngày.","id":"Hanya menyimpan hasil laporan harian."},"日本語":{"vi":"Tiếng Nhật","id":"Bahasa Jepang"},"最新に更新":{"vi":"Cập nhật mới nhất","id":"Perbarui ke terbaru"},"最終入力":{"vi":"Lần nhập gần nhất","id":"Input terakhir"},"最終取得：未取得":{"vi":"Lần lấy dữ liệu gần nhất: chưa có","id":"Pengambilan terakhir: belum ada"},"月を選択":{"vi":"Chọn tháng","id":"Pilih bulan"},"本日入力済み":{"vi":"Đã nhập hôm nay","id":"Sudah diisi hari ini"},"本日未入力":{"vi":"Chưa nhập hôm nay","id":"Belum diisi hari ini"},"条件に合うロットがありません。品名や入荷日を変えるか、在庫の条件を「すべて」にしてください。":{"vi":"Không có lô nào phù hợp. Hãy đổi tên hàng hoặc ngày hàng về, hoặc đặt điều kiện tồn kho thành “Tất cả”.","id":"Tidak ada lot yang sesuai. Ubah nama barang atau tanggal kedatangan, atau atur kondisi stok menjadi “Semua”."},"条件クリア":{"vi":"Xóa điều kiện","id":"Hapus kondisi"},"棚卸しモード":{"vi":"Chế độ kiểm kê","id":"Mode stok opname"},"検索":{"vi":"Tìm kiếm","id":"Cari"},"検索結果から選ぶ":{"vi":"Chọn từ kết quả tìm kiếm","id":"Pilih dari hasil pencarian"},"業務・履歴":{"vi":"Công việc và lịch sử","id":"Pekerjaan dan riwayat"},"歩留まり":{"vi":"Tỷ lệ thành phẩm","id":"Rendemen"},"歩留まり価格":{"vi":"Giá theo tỷ lệ thành phẩm","id":"Harga rendemen"},"産地":{"vi":"Vùng sản xuất","id":"Daerah asal"},"産地状況・市場動向メモ":{"vi":"Ghi chú tình hình vùng trồng và thị trường","id":"Catatan kondisi daerah asal dan pasar"},"発注候補":{"vi":"Mặt hàng nên đặt thêm","id":"Kandidat pemesanan"},"登録してQR貼り紙PDFへ":{"vi":"Lưu và mở PDF giấy dán QR","id":"Simpan dan buka PDF label QR"},"確認して日報を登録":{"vi":"Kiểm tra rồi lưu báo cáo ngày","id":"Periksa lalu simpan laporan harian"},"端末保存済み・クラウド未同期 1件":{"vi":"Đã lưu trên thiết bị, chưa đồng bộ lên đám mây: 1 mục","id":"Tersimpan di perangkat, belum tersinkron ke cloud: 1 data"},"管理・設定":{"vi":"Quản lý và cài đặt","id":"Pengelolaan dan pengaturan"},"網コンテナ在庫":{"vi":"Tồn kho thùng lưới","id":"Stok kontainer jaring"},"自動計算":{"vi":"Tính tự động","id":"Hitung otomatis"},"荷受け担当者":{"vi":"Người nhận hàng","id":"Petugas penerimaan"},"荷姿":{"vi":"Quy cách đóng gói","id":"Jenis kemasan"},"荷姿と数量":{"vi":"Quy cách đóng gói và số lượng","id":"Jenis kemasan dan jumlah"},"表示する月":{"vi":"Tháng hiển thị","id":"Bulan yang ditampilkan"},"表示・アカウント・データ保全":{"vi":"Hiển thị / Tài khoản / Bảo toàn dữ liệu","id":"Tampilan / Akun / Perlindungan data"},"製造・歩留まり":{"vi":"Sản xuất và tỷ lệ thành phẩm","id":"Produksi dan rendemen"},"製造日報":{"vi":"Báo cáo sản xuất hằng ngày","id":"Laporan produksi harian"},"規格など（任意）":{"vi":"Quy cách và thông tin khác (không bắt buộc)","id":"Spesifikasi dan lainnya (opsional)"},"認証（任意）":{"vi":"Chứng nhận (không bắt buộc)","id":"Sertifikasi (opsional)"},"読み込みに失敗しました。":{"vi":"Tải dữ liệu thất bại.","id":"Gagal memuat data."},"読み込みエラー":{"vi":"Lỗi khi tải","id":"Kesalahan saat memuat"},"読取／入力":{"vi":"Quét / Nhập","id":"Pindai / Input"},"追加方法を見る":{"vi":"Xem cách thêm","id":"Lihat cara menambahkan"},"通常ロット":{"vi":"Lô thường","id":"Lot biasa"},"通常品目の後に、じゃがいも品種をまとめて表示します。":{"vi":"Sau các mặt hàng thường sẽ hiển thị chung các giống khoai tây.","id":"Setelah barang biasa, varietas kentang ditampilkan bersama."},"通常在庫・QR在庫・QR操作履歴は変更せず、日報実績だけを保存します。事前に合わせた在庫はそのままです。":{"vi":"Tồn kho thường, tồn kho QR và lịch sử thao tác QR không thay đổi; chỉ lưu kết quả báo cáo ngày. Tồn kho đã khớp trước đó vẫn giữ nguyên.","id":"Stok biasa, stok QR, dan riwayat operasi QR tidak diubah; hanya hasil laporan harian yang disimpan. Stok yang sudah disesuaikan tetap sama."},"過多品目":{"vi":"Mặt hàng tồn nhiều","id":"Barang berlebih"},"適正在庫設定":{"vi":"Cài đặt tồn kho hợp lý","id":"Pengaturan stok ideal"},"選択":{"vi":"Chọn","id":"Pilih"},"選択してください":{"vi":"Hãy chọn","id":"Silakan pilih"},"選択月の廃棄記録はありません。":{"vi":"Không có dữ liệu loại bỏ trong tháng đã chọn.","id":"Tidak ada catatan pembuangan pada bulan yang dipilih."},"選択月の廃棄金額":{"vi":"Số tiền hàng loại bỏ của tháng đã chọn","id":"Nilai pembuangan bulan yang dipilih"},"選択月の確定重量合計(kg)":{"vi":"Tổng trọng lượng đã xác định của tháng đã chọn (kg)","id":"Total berat yang ditetapkan bulan terpilih (kg)"},"選択月をExcel出力":{"vi":"Xuất Excel tháng đã chọn","id":"Ekspor Excel bulan terpilih"},"重量集計":{"vi":"Tổng hợp trọng lượng","id":"Rekap berat"},"量目（必須）":{"vi":"Trọng lượng đóng gói (bắt buộc)","id":"Berat kemasan (wajib)"},"閲覧者":{"vi":"Người xem","id":"Penonton"},"青果社員":{"vi":"Nhân viên rau quả","id":"Staf sayur dan buah"},"＋ 出来高（入替品）を追加":{"vi":"＋ Thêm sản lượng (hàng thay thế)","id":"＋ Tambah hasil produksi (barang pengganti)"},"：20件":{"vi":": 20 mục","id":": 20 data"},"本日未入力：20品":{"vi":"Chưa nhập hôm nay: 20 mặt hàng","id":"Belum diisi hari ini: 20 barang"},"0円":{"vi":"0 yên","id":"0 yen"},"1パレット/ケース数":{"vi":"Số thùng trên 1 pallet","id":"Jumlah kotak per palet"},"ログイン":{"vi":"Đăng nhập","id":"Masuk"},"安全なログイン":{"vi":"Đăng nhập an toàn","id":"Masuk"},"名前を選択してください":{"vi":"Vui lòng chọn tên của bạn","id":"Pilih nama Anda"},"パスワード":{"vi":"Mật khẩu","id":"Kata sandi"},"確認中...":{"vi":"Đang kiểm tra...","id":"Sedang memeriksa..."},"名前を選んで、パスワードを入力してください。":{"vi":"Hãy chọn tên của bạn, sau đó nhập mật khẩu.","id":"Pilih nama Anda, lalu masukkan kata sandi."},"現場オペレーション管理":{"vi":"Quản lý vận hành tại hiện trường","id":"Pengelolaan Operasional Lapangan"},"入庫から在庫、廃棄、出庫まで。":{"vi":"Từ nhập hàng, tồn kho, loại bỏ đến xuất hàng.","id":"Dari penerimaan, stok, pembuangan, hingga barang keluar."},"青果センターの毎日をひとつに。":{"vi":"Gộp mọi công việc hằng ngày của trung tâm rau quả vào một hệ thống.","id":"Semua pekerjaan harian pusat sayur dan buah dalam satu sistem."},"ホーム":{"vi":"Trang chủ","id":"Beranda"},"閉じる":{"vi":"Đóng","id":"Tutup"},"次へ":{"vi":"Tiếp theo","id":"Berikutnya"},"保存":{"vi":"Lưu","id":"Simpan"},"登録":{"vi":"Lưu","id":"Simpan"},"保存中...":{"vi":"Đang lưu...","id":"Sedang menyimpan..."},"登録中...":{"vi":"Đang lưu...","id":"Sedang menyimpan..."},"読み込み中...":{"vi":"Đang tải...","id":"Sedang memuat..."},"権限がありません":{"vi":"Bạn không có quyền.","id":"Anda tidak memiliki izin."},"分析・判断支援":{"vi":"Phân tích và hỗ trợ quyết định","id":"Analisis dan bantuan keputusan"},"担当品目":{"vi":"Mặt hàng phụ trách","id":"Barang tanggung jawab"},"記録なし":{"vi":"Chưa có dữ liệu","id":"Belum ada catatan"},"最新の情報を確認する場合は、再読込を押してください。":{"vi":"Nhấn “Tải lại” để xem thông tin mới nhất.","id":"Tekan “Muat ulang” untuk melihat informasi terbaru."},"品目から自動入力":{"vi":"Tự động điền theo mặt hàng","id":"Terisi otomatis dari nama barang"},"品目選択後に自動入力":{"vi":"Tự động điền sau khi chọn mặt hàng","id":"Terisi otomatis setelah memilih barang"},"PDFを開く・印刷":{"vi":"Mở và in PDF","id":"Buka dan cetak PDF"},"任意":{"vi":"Không bắt buộc","id":"Opsional"},"未設定":{"vi":"Chưa thiết lập","id":"Belum diatur"},"未確定":{"vi":"Chưa xác định","id":"Belum ditetapkan"},"確定":{"vi":"Đã xác định","id":"Sudah ditetapkan"},"品質評価":{"vi":"Đánh giá chất lượng","id":"Penilaian kualitas"},"QR品質評価":{"vi":"Đánh giá chất lượng QR","id":"Penilaian Kualitas QR"},"品質評価を訂正":{"vi":"Sửa đánh giá chất lượng","id":"Koreksi penilaian kualitas"},"在庫数量は変わりません":{"vi":"Số lượng tồn kho không thay đổi","id":"Jumlah stok tidak berubah"},"品質状態だけをロットへ記録します。不良品を在庫から減らす場合は、評価後にQR廃棄を登録してください。":{"vi":"Chỉ tình trạng chất lượng được ghi vào lô hàng. Nếu muốn trừ hàng hỏng khỏi tồn kho, hãy đăng ký loại bỏ QR sau khi đánh giá.","id":"Hanya kondisi kualitas yang dicatat pada lot. Untuk mengurangi barang bermasalah dari stok, simpan pembuangan QR setelah penilaian."},"総合判定":{"vi":"Kết quả tổng thể","id":"Hasil keseluruhan"},"良好":{"vi":"Tốt","id":"Baik"},"要確認":{"vi":"Cần kiểm tra","id":"Perlu diperiksa"},"不良":{"vi":"Không đạt","id":"Buruk"},"確認された状態（複数選択可）":{"vi":"Tình trạng phát hiện (có thể chọn nhiều)","id":"Kondisi yang ditemukan (boleh pilih lebih dari satu)"},"写真（任意・最大3枚）":{"vi":"Ảnh (không bắt buộc, tối đa 3 ảnh)","id":"Foto (opsional, maksimal 3)"},"問題時のみ登録します。長辺1280px、1枚350KB以下へ自動圧縮します。":{"vi":"Chỉ thêm ảnh khi có vấn đề.","id":"Tambahkan foto hanya jika ada masalah."},"写真ライブラリから選択":{"vi":"Chọn từ thư viện ảnh","id":"Pilih dari galeri foto"},"訂正理由":{"vi":"Lý do sửa","id":"Alasan koreksi"},"品質評価を登録":{"vi":"Lưu đánh giá chất lượng","id":"Simpan penilaian kualitas"},"品質評価を保存しています":{"vi":"Đang lưu đánh giá chất lượng","id":"Sedang menyimpan penilaian kualitas"},"品質評価の確認":{"vi":"Xác nhận đánh giá chất lượng","id":"Konfirmasi Penilaian Kualitas"},"訂正した評価を登録":{"vi":"Lưu đánh giá đã sửa","id":"Simpan hasil koreksi"},"傷み":{"vi":"Hư hỏng","id":"Rusak"},"変色":{"vi":"Đổi màu","id":"Perubahan warna"},"腐敗":{"vi":"Thối","id":"Busuk"},"カビ":{"vi":"Mốc","id":"Berjamur"},"打撲・傷":{"vi":"Dập hoặc trầy xước","id":"Memar atau luka"},"しおれ":{"vi":"Héo","id":"Layu"},"異臭":{"vi":"Mùi lạ","id":"Bau tidak normal"},"規格外":{"vi":"Không đạt quy cách","id":"Tidak sesuai standar"},"温度異常":{"vi":"Nhiệt độ bất thường","id":"Suhu tidak normal"},"品質状態や確認内容":{"vi":"Tình trạng chất lượng hoặc nội dung kiểm tra","id":"Kondisi kualitas atau hasil pemeriksaan"},"例：判定項目の選択間違い":{"vi":"Ví dụ: chọn sai mục đánh giá","id":"Contoh: salah memilih item penilaian"},"パスワードを入力してください。":{"vi":"Vui lòng nhập mật khẩu.","id":"Masukkan kata sandi."},"再ログインしてください。":{"vi":"Vui lòng đăng nhập lại.","id":"Silakan masuk kembali."},"通信状況を確認してください。":{"vi":"Vui lòng kiểm tra kết nối mạng.","id":"Periksa koneksi internet."},"登録後も在庫数量は変わりません。":{"vi":"Sau khi lưu, số lượng tồn kho vẫn không thay đổi.","id":"Jumlah stok tidak berubah setelah disimpan."},"写真":{"vi":"Ảnh","id":"Foto"},"状態":{"vi":"Tình trạng","id":"Kondisi"},"判定":{"vi":"Kết quả","id":"Hasil"},"品質評価一覧":{"vi":"Danh sách đánh giá chất lượng","id":"Danh sách đánh giá chất lượng"},"評価済みロット・写真を確認":{"vi":"Xem lô đã đánh giá và ảnh","id":"Xem lô đã đánh giá và ảnh"},"QRロットごとの最新評価を検索・確認":{"vi":"Tìm và xem đánh giá mới nhất của từng lô QR","id":"Tìm và xem đánh giá mới nhất của từng lô QR"},"評価月":{"vi":"Tháng đánh giá","id":"Tháng đánh giá"},"品名の一部":{"vi":"Một phần tên mặt hàng","id":"Một phần tên mặt hàng"},"未確認の評価だけ表示":{"vi":"Chỉ hiển thị đánh giá chưa xác nhận","id":"Chỉ hiển thị đánh giá chưa xác nhận"},"条件をクリア":{"vi":"Xóa điều kiện","id":"Xóa điều kiện"},"評価を読み込んでいます...":{"vi":"Đang tải đánh giá...","id":"Đang tải đánh giá..."},"表示中":{"vi":"Đang hiển thị","id":"Đang hiển thị"},"全":{"vi":"Tổng","id":"Tổng"},"件":{"vi":"mục","id":"mục"},"不良を先頭に、要確認・良好の順で表示します。訂正前の評価は除外し、最新評価だけを表示しています。":{"vi":"Thứ tự hiển thị: Không đạt, Cần kiểm tra, rồi Tốt. Chỉ hiển thị đánh giá mới nhất.","id":"Thứ tự hiển thị: Không đạt, Cần kiểm tra, rồi Tốt. Chỉ hiển thị đánh giá mới nhất."},"条件に一致する品質評価はありません。":{"vi":"Không có đánh giá chất lượng phù hợp.","id":"Không có đánh giá chất lượng phù hợp."},"さらに50件読み込む":{"vi":"Tải thêm 50 mục","id":"Tải thêm 50 mục"},"状態：":{"vi":"Tình trạng:","id":"Tình trạng:"},"メモ：":{"vi":"Ghi chú:","id":"Ghi chú:"},"評価者：":{"vi":"Người đánh giá:","id":"Người đánh giá:"},"写真：":{"vi":"Ảnh:","id":"Ảnh:"},"確認不要":{"vi":"Không cần xác nhận","id":"Không cần xác nhận"},"確認済み":{"vi":"Đã xác nhận","id":"Đã xác nhận"},"未確認":{"vi":"Chưa xác nhận","id":"Chưa xác nhận"},"QRロット詳細":{"vi":"Chi tiết lô QR","id":"Chi tiết lô QR"},"写真を見る":{"vi":"Xem ảnh","id":"Xem ảnh"},"確認済みにする":{"vi":"Đánh dấu đã xác nhận","id":"Đánh dấu đã xác nhận"},"担当未設定":{"vi":"Chưa có người phụ trách","id":"Chưa có người phụ trách"},"読み込みに失敗しました。通信状況を確認して再度検索してください。":{"vi":"Tải thất bại. Vui lòng kiểm tra kết nối rồi tìm lại.","id":"Tải thất bại. Vui lòng kiểm tra kết nối rồi tìm lại."},"表示順":{"vi":"Thứ tự hiển thị","id":"Thứ tự hiển thị"},"評価順（不良・要確認・良好）":{"vi":"Theo kết quả đánh giá (Không đạt, Cần kiểm tra, Tốt)","id":"Theo kết quả đánh giá (Không đạt, Cần kiểm tra, Tốt)"},"入荷日が新しい順":{"vi":"Ngày nhập mới nhất trước","id":"Ngày nhập mới nhất trước"},"入荷日が古い順":{"vi":"Ngày nhập cũ nhất trước","id":"Ngày nhập cũ nhất trước"},"入荷日：":{"vi":"Ngày nhập:","id":"Ngày nhập:"},"評価順で表示しています。訂正前の評価は除外し、最新評価だけを表示しています。":{"vi":"Đang hiển thị theo kết quả đánh giá. Chỉ hiển thị đánh giá mới nhất.","id":"Đang hiển thị theo kết quả đánh giá. Chỉ hiển thị đánh giá mới nhất."},"入荷日が新しい順で表示しています。訂正前の評価は除外し、最新評価だけを表示しています。":{"vi":"Đang hiển thị từ ngày nhập mới nhất. Chỉ hiển thị đánh giá mới nhất.","id":"Đang hiển thị từ ngày nhập mới nhất. Chỉ hiển thị đánh giá mới nhất."},"入荷日が古い順で表示しています。訂正前の評価は除外し、最新評価だけを表示しています。":{"vi":"Đang hiển thị từ ngày nhập cũ nhất. Chỉ hiển thị đánh giá mới nhất.","id":"Đang hiển thị từ ngày nhập cũ nhất. Chỉ hiển thị đánh giá mới nhất."},"品目担当（旧データ）":{"vi":"Người phụ trách mặt hàng (dữ liệu cũ)","id":"Người phụ trách mặt hàng (dữ liệu cũ)"},"訂正履歴再送エラー":{"vi":"Lỗi gửi lại lịch sử sửa","id":"Lỗi gửi lại lịch sử sửa"},"SEIKA＋でできること":{"vi":"SEIKA＋ có thể làm gì","id":"Apa yang bisa dilakukan SEIKA＋"},"ふりがな ON":{"vi":"Furigana ON","id":"Furigana ON"},"ふりがな OFF":{"vi":"Furigana OFF","id":"Furigana OFF"}},"names":{"キャベツ":{"vi":"Bắp cải","id":"Kubis","r":""},"白菜":{"vi":"Cải thảo","id":"Sawi putih","r":"はくさい"},"人参":{"vi":"Cà rốt","id":"Wortel","r":"にんじん"},"人参（国産）":{"vi":"Cà rốt (trong nước)","id":"Wortel (dalam negeri)","r":"にんじん（こくさん）"},"国産人参":{"vi":"Cà rốt trong nước","id":"Wortel dalam negeri","r":"こくさんにんじん"},"玉ねぎ":{"vi":"Hành tây","id":"Bawang bombay","r":"たまねぎ"},"玉葱":{"vi":"Hành tây","id":"Bawang bombay","r":"たまねぎ"},"小松菜":{"vi":"Cải komatsuna","id":"Komatsuna","r":"こまつな"},"小葱":{"vi":"Hành lá nhỏ","id":"Bawang kucai","r":"こねぎ"},"レタス":{"vi":"Xà lách","id":"Selada","r":""},"リーフ":{"vi":"Xà lách lá","id":"Selada daun","r":""},"リーフレタス":{"vi":"Xà lách lá","id":"Selada daun","r":""},"グリーンリーフ":{"vi":"Xà lách lá xanh","id":"Selada hijau","r":""},"グリーンカール":{"vi":"Xà lách xoăn xanh","id":"Selada keriting hijau","r":""},"サニー":{"vi":"Xà lách tím","id":"Selada merah","r":""},"サニーレタス":{"vi":"Xà lách tím","id":"Selada merah","r":""},"ロメイン":{"vi":"Xà lách romaine","id":"Selada romaine","r":""},"ロメインレタス":{"vi":"Xà lách romaine","id":"Selada romaine","r":""},"カット大根":{"vi":"Củ cải trắng đã cắt","id":"Lobak potong","r":"カットだいこん"},"葉付き大根":{"vi":"Củ cải trắng còn lá","id":"Lobak berdaun","r":"はつきだいこん"},"葉付大根":{"vi":"Củ cải trắng còn lá","id":"Lobak berdaun","r":"はつきだいこん"},"ダンボール":{"vi":"Thùng giấy","id":"Kardus","r":""},"コンテナ":{"vi":"Thùng nhựa","id":"Kontainer","r":""},"網コンテナ":{"vi":"Thùng lưới","id":"Kontainer jaring","r":"あみコンテナ"},"鉄コンテナ":{"vi":"Thùng sắt","id":"Kontainer besi","r":"てつコンテナ"},"パレテーナ":{"vi":"Paretena (thùng lớn)","id":"Paretena (wadah besar)","r":""},"紙袋":{"vi":"Túi giấy","id":"Kantong kertas","r":"かみぶくろ"},"片岡冷蔵庫":{"vi":"Kho lạnh Kataoka","id":"Ruang pendingin Kataoka","r":"かたおかれいぞうこ"},"第2冷蔵庫":{"vi":"Kho lạnh số 2","id":"Ruang pendingin ke-2","r":"だい2れいぞうこ"},"第3冷蔵庫":{"vi":"Kho lạnh số 3","id":"Ruang pendingin ke-3","r":"だい3れいぞうこ"}},"potato":{"さやか":{"r":""},"とうや":{"r":""},"ながさき黄金":{"r":"ながさきおうごん"},"はるか":{"r":""},"アイユタカ":{"r":""},"インカのひとみ":{"r":""},"インカのめざめ":{"r":""},"オホーツクチップ":{"r":""},"キタアカリ":{"r":""},"キタカムイ":{"r":""},"キタムラサキ":{"r":""},"シャドークイーン":{"r":""},"スノーマーチ":{"r":""},"デジマ":{"r":""},"トヨシロ":{"r":""},"ニシユタカ":{"r":""},"ピルカ":{"r":""},"メークイン":{"r":""},"男爵":{"r":"だんしゃく"},"北海黄金":{"r":"ほっかいおうごん"},"十勝こがね":{"r":"とかちこがね"}}};
const V201_USER_LANGS={furenki:"id",hiep:"vi"};
const V201_RUBY_KEY="seika_v201_ruby";
let v201Busy=false,v201Timer=null,v201Observer=null;
function v201Lang(){const id=(db&&db.role==="worker")?db.userId:"";const a=V201_USER_LANGS[id];if(a)return a;
 if(currentScreen==="login"){const sel=document.getElementById("loginUser")?.value||"";return V201_USER_LANGS[sel]||""}return""}
function v201RubyOn(){try{return localStorage.getItem(V201_RUBY_KEY)!=="0"}catch(_){return true}}
function v201ToggleRuby(){try{localStorage.setItem(V201_RUBY_KEY,v201RubyOn()?"0":"1")}catch(_){}
 if(db&&db.user)renderCurrent();else login()}
window.v201ToggleRuby=v201ToggleRuby;
function v201Name(ja,lang){const n=V201_LEX.names[ja];if(n){const r=(v201RubyOn()&&n.r)?"（"+n.r+"）":"";return n[lang]+" / "+ja+r}
 const p=V201_LEX.potato[ja];if(p)return ja+((v201RubyOn()&&p.r)?"（"+p.r+"）":"");return null}
function v201Text(ja,lang){const t=String(ja==null?"":ja);const u=V201_LEX.ui[t];if(u&&u[lang])return u[lang];
 const n=v201Name(t,lang);if(n)return n;
 if(t.includes(" / ")){const ps=t.split(" / "),out=ps.map(x=>{const h=v201Text(x.trim(),lang);return h||x.trim()});if(out.join(" / ")!==t)return out.join(" / ")}
 return null}
function v201Apply(){const lang=v201Lang();document.documentElement.lang=lang||"ja";if(!lang||v201Busy)return;
 v201Busy=true;
 try{
  const walker=document.createTreeWalker(document.body,NodeFilter.SHOW_TEXT),nodes=[];
  while(walker.nextNode())nodes.push(walker.currentNode);
  nodes.forEach(node=>{const p=node.parentNode;if(!p)return;
   const tag=p.nodeName;if(tag==="SCRIPT"||tag==="STYLE"||tag==="TEXTAREA")return;
   const src=node.nodeValue,trimmed=src.trim();if(!trimmed)return;
   const hit=v201Text(trimmed,lang);if(hit&&hit!==trimmed)node.nodeValue=src.replace(trimmed,hit)});
  document.querySelectorAll("[placeholder]").forEach(el=>{const ph=el.getAttribute("placeholder");
   const hit=v201Text(ph,lang);if(hit&&hit!==ph)el.setAttribute("placeholder",hit)});
  document.querySelectorAll("[title]").forEach(el=>{const tt=el.getAttribute("title");
   const hit=v201Text(tt,lang);if(hit&&hit!==tt)el.setAttribute("title",hit)});
 }catch(e){}
 v201Busy=false}
window.v201Apply=v201Apply;
function v201Schedule(){if(v201Timer)clearTimeout(v201Timer);v201Timer=setTimeout(()=>{v201Timer=null;v201Apply()},60)}
function v201Watch(){if(v201Observer)return;try{v201Observer=new MutationObserver(()=>{if(!v201Busy)v201Schedule()});
 v201Observer.observe(document.body,{childList:true,subtree:true,characterData:true})}catch(e){}}
const v201ShellBase=pageShell;
pageShell=function(title,sub,body,opts={}){const r=v201ShellBase(title,sub,body,opts);
 if(opts&&opts.login){const select=document.getElementById("loginUser");if(select)select.onchange=function(){const s=this.value;
  if(V201_USER_LANGS[s]){v201Apply();return}login();const rep=document.getElementById("loginUser");if(rep)rep.value=s}}
 if(v201Lang()){v201RubyBar();v201Apply();v201Watch()}else{document.querySelector(".v201RubyBar")?.remove()}
 return r};
window.pageShell=pageShell;
function v201RubyBar(){if(!v201Lang())return;const head=document.querySelector(".topBtns")||document.querySelector(".head");
 if(!head)return;let bar=document.querySelector(".v201RubyBar");if(!bar){bar=document.createElement("button");
  bar.type="button";bar.className="v201RubyBar headAction";bar.setAttribute("data-seika-click-action","v201ToggleRuby");
  bar.setAttribute("data-seika-click-args","%5B%5D");head.appendChild(bar)}
 bar.textContent=v201RubyOn()?"ふりがな ON":"ふりがな OFF"}
const v201LoginUsersBase=v188LoginUsers;
v188LoginUsers=function(){const rows=v201LoginUsersBase();if(!rows.some(r=>r[0]==="hiep"))rows.push(["hiep","ヒェップ","青果社員"]);return rows};
/* v1.138/v1.139 の切替UIは無効化し、担当者ごとに自動で言語を決める */
v138LanguageSwitchHtml=function(){return""};
v138SetLanguage=function(){};
v138TranslateScreen=function(){v201Apply()};
v138T=function(value){const lang=v201Lang();const t=String(value==null?"":value);if(!lang)return t;return v201Text(t,lang)||t};
v138RestoreLanguage=function(){document.documentElement.lang=v201Lang()||"ja"};
v138RestoreLanguage();


/* ===== v1.199-c2 翻訳を「一部翻訳」へ戻す（QR入庫のフリーズ対策） =====
   全文置換方式は品名を「訳 / 和名」へ展開するが、その結果が MutationObserver で
   再び翻訳対象になり「訳 / 訳 / 和名」と際限なく伸び続けるため画面が固まる。
   適用範囲を v1.138 相当の限定セレクタへ戻し、ふりがなと品名の併記は行わない。
   ヒェップ（ベトナム語）もフレンキ（インドネシア語）と同じ範囲にそろえる。 */
const V202_VI={"ログイン": "Đăng nhập", "安全なログイン": "Đăng nhập an toàn", "名前を選択してください": "Vui lòng chọn tên của bạn", "パスワード": "Mật khẩu", "確認中...": "Đang kiểm tra...", "名前を選んで、パスワードを入力してください。": "Hãy chọn tên của bạn, sau đó nhập mật khẩu.", "現場オペレーション管理": "Quản lý vận hành tại hiện trường", "入庫から在庫、廃棄、出庫まで。": "Từ nhập hàng, tồn kho, loại bỏ đến xuất hàng.", "青果センターの毎日をひとつに。": "Gộp mọi công việc hằng ngày của trung tâm rau quả vào một hệ thống.", "戻る": "Quay lại", "ホーム": "Trang chủ", "再読込": "Tải lại", "メニュー": "Menu", "閉じる": "Đóng", "次へ": "Tiếp theo", "保存": "Lưu", "登録": "Lưu", "保存中...": "Đang lưu...", "登録中...": "Đang lưu...", "読み込み中...": "Đang tải...", "エラー": "Lỗi", "権限がありません": "Bạn không có quyền.", "在庫管理": "Quản lý tồn kho", "QR在庫管理": "Quản lý tồn kho QR", "在庫報告コピー": "Sao chép báo cáo tồn kho", "品目設定": "Cài đặt mặt hàng", "適正在庫設定": "Cài đặt tồn kho hợp lý", "産地状況・市場動向メモ": "Ghi chú tình hình vùng trồng và thị trường", "網コンテナ在庫": "Tồn kho thùng lưới", "廃棄管理": "Quản lý hàng loại bỏ", "分析・判断支援": "Phân tích và hỗ trợ quyết định", "本日入力済み": "Đã nhập hôm nay", "本日未入力": "Chưa nhập hôm nay", "発注候補": "Mặt hàng nên đặt thêm", "過多品目": "Mặt hàng tồn nhiều", "担当品目": "Mặt hàng phụ trách", "最終入力": "Lần nhập gần nhất", "記録なし": "Chưa có dữ liệu", "最新の情報を確認する場合は、再読込を押してください。": "Nhấn “Tải lại” để xem thông tin mới nhất.", "QR入庫": "Nhập hàng QR", "品目と数量を入力して登録します": "Nhập tên mặt hàng và số lượng rồi lưu", "入庫する品目": "Mặt hàng nhập vào", "入庫日": "Ngày nhập hàng", "品目": "Mặt hàng", "マスターから選択してください": "Hãy chọn từ danh sách", "通常品目の後に、じゃがいも品種をまとめて表示します。": "Sau các mặt hàng thường sẽ hiển thị chung các giống khoai tây.", "担当者": "Người phụ trách", "仕入れ担当者": "Người phụ trách thu mua", "荷受け担当者": "Người nhận hàng", "品目から自動入力": "Tự động điền theo mặt hàng", "品目選択後に自動入力": "Tự động điền sau khi chọn mặt hàng", "荷姿と数量": "Quy cách đóng gói và số lượng", "荷姿": "Quy cách đóng gói", "仕入先・保管場所": "Nhà cung cấp và nơi bảo quản", "仕入先": "Nhà cung cấp", "産地": "Vùng sản xuất", "規格など（任意）": "Quy cách và thông tin khác (không bắt buộc)", "保管場所": "Nơi bảo quản", "登録してQR貼り紙PDFへ": "Lưu và mở PDF giấy dán QR", "PDFを開く・印刷": "Mở và in PDF", "必須": "Bắt buộc", "任意": "Không bắt buộc", "未設定": "Chưa thiết lập", "未確定": "Chưa xác định", "確定": "Đã xác định", "品質評価": "Đánh giá chất lượng", "QR品質評価": "Đánh giá chất lượng QR", "品質評価を訂正": "Sửa đánh giá chất lượng", "在庫数量は変わりません": "Số lượng tồn kho không thay đổi", "品質状態だけをロットへ記録します。不良品を在庫から減らす場合は、評価後にQR廃棄を登録してください。": "Chỉ tình trạng chất lượng được ghi vào lô hàng. Nếu muốn trừ hàng hỏng khỏi tồn kho, hãy đăng ký loại bỏ QR sau khi đánh giá.", "総合判定": "Kết quả tổng thể", "良好": "Tốt", "要確認": "Cần kiểm tra", "不良": "Không đạt", "確認された状態（複数選択可）": "Tình trạng phát hiện (có thể chọn nhiều)", "写真（任意・最大3枚）": "Ảnh (không bắt buộc, tối đa 3 ảnh)", "問題時のみ登録します。長辺1280px、1枚350KB以下へ自動圧縮します。": "Chỉ thêm ảnh khi có vấn đề.", "写真ライブラリから選択": "Chọn từ thư viện ảnh", "メモ（任意）": "Ghi chú (không bắt buộc)", "訂正理由": "Lý do sửa", "品質評価を登録": "Lưu đánh giá chất lượng", "品質評価を保存しています": "Đang lưu đánh giá chất lượng", "品質評価の確認": "Xác nhận đánh giá chất lượng", "訂正した評価を登録": "Lưu đánh giá đã sửa", "傷み": "Hư hỏng", "変色": "Đổi màu", "腐敗": "Thối", "カビ": "Mốc", "打撲・傷": "Dập hoặc trầy xước", "しおれ": "Héo", "異臭": "Mùi lạ", "規格外": "Không đạt quy cách", "温度異常": "Nhiệt độ bất thường", "その他": "Khác", "仕入先を入力": "Nhập nhà cung cấp", "例：茨城 → 茨城県産": "Ví dụ: Ibaraki → sản xuất tại tỉnh Ibaraki", "例：3L、秀品、フジ用": "Ví dụ: 3L, hàng loại tốt, dùng cho Fuji", "品質状態や確認内容": "Tình trạng chất lượng hoặc nội dung kiểm tra", "例：判定項目の選択間違い": "Ví dụ: chọn sai mục đánh giá", "パスワードを入力してください。": "Vui lòng nhập mật khẩu.", "再ログインしてください。": "Vui lòng đăng nhập lại.", "通信状況を確認してください。": "Vui lòng kiểm tra kết nối mạng.", "登録後も在庫数量は変わりません。": "Sau khi lưu, số lượng tồn kho vẫn không thay đổi.", "なし": "Không có", "写真": "Ảnh", "状態": "Tình trạng", "判定": "Kết quả"};
const V202_MSG={"入庫日を入力してください。": {"id": "Pilih tanggal penerimaan.", "vi": "Hãy chọn ngày nhập hàng."}, "品目を選択してください。": {"id": "Pilih nama barang.", "vi": "Hãy chọn mặt hàng."}, "仕入れ担当者を入力してください。": {"id": "Masukkan petugas pembelian.", "vi": "Hãy nhập người phụ trách thu mua."}, "荷姿を選択してください。": {"id": "Pilih jenis kemasan.", "vi": "Hãy chọn quy cách đóng gói."}, "数量を入力してください。": {"id": "Masukkan jumlah.", "vi": "Hãy nhập số lượng."}, "仕入先を入力してください。": {"id": "Masukkan pemasok.", "vi": "Hãy nhập nhà cung cấp."}, "産地を入力してください。": {"id": "Masukkan daerah asal.", "vi": "Hãy nhập vùng sản xuất."}, "保管場所を選択してください。": {"id": "Pilih lokasi penyimpanan.", "vi": "Hãy chọn nơi bảo quản."}, "総合判定を選択してください。": {"id": "Pilih hasil keseluruhan.", "vi": "Hãy chọn kết quả tổng thể."}, "「良好」のときは状態と写真を登録できません。": {"id": "Jika hasilnya “Baik”, kondisi masalah dan foto tidak dapat ditambahkan.", "vi": "Khi kết quả là “Tốt” thì không thể thêm tình trạng và ảnh."}, "「要確認」「不良」のときは状態を1つ以上選んでください。": {"id": "Untuk “Perlu diperiksa” atau “Buruk”, pilih minimal satu kondisi.", "vi": "Với “Cần kiểm tra” hoặc “Không đạt”, hãy chọn ít nhất một tình trạng."}, "「その他」の内容をメモに入力してください。": {"id": "Masukkan rincian “Lainnya” pada catatan.", "vi": "Hãy ghi nội dung của “Khác” vào phần ghi chú."}, "訂正理由を入力してください。": {"id": "Masukkan alasan koreksi.", "vi": "Hãy nhập lý do sửa."}, "メモは日本語で入力してください（必要なら日本人スタッフに聞いてください）。": {"id": "Tulis dalam bahasa Jepang (jika perlu, tanyakan kepada petugas Jepang).", "vi": "Hãy ghi bằng tiếng Nhật (nếu cần, hãy hỏi nhân viên người Nhật)."}};
const V202_DICTS={id:V138_ID,vi:V202_VI};
const V202_USER_LANGS={furenki:"id",hiep:"vi"};
const V202_SCREENS=["login","home","qrHome","qrCreatePage","v1102QualityPage"];
const V202_SELECTORS=".opsLoginScreen h1,.opsLoginScreen h2,.opsLoginScreen .small,.opsLoginScreen .opsLogoSub,.homeSummary .summaryLabel,.homePrimary button,.qrCreateForm h2,.qrCreateForm .label,.qrCreateForm .small,.qrCreateForm button,.qrCreateForm .qrReadOnlyField,.qrCreateForm .notice,#v1102ProblemFields,.wrap > .notice,.wrap > .card > .label,.wrap > .card > .small,.wrap > .card > button,.wrap > .card > .grid label,.wrap > .card > .grid .box";
let v202Busy=false,v202Timer=null,v202Observer=null;
function v202Lang(){const uid=(db&&db.role==="worker")?db.userId:"";const a=V202_USER_LANGS[uid];if(a)return a;
 if(currentScreen==="login"){const s=document.getElementById("loginUser")?.value||"";return V202_USER_LANGS[s]||""}return""}
function v202Dict(){return V202_DICTS[v202Lang()]||null}
function v202T(value){const d=v202Dict(),t=String(value==null?"":value);return(d&&d[t])||t}
function v202Msg(ja){const lang=v202Lang(),m=V202_MSG[ja];return(lang&&m&&m[lang])||ja}
function v202Element(el,dict){if(!el)return;const w=document.createTreeWalker(el,NodeFilter.SHOW_TEXT),ns=[];
 while(w.nextNode())ns.push(w.currentNode);
 ns.forEach(n=>{const parent=n.parentNode;if(!parent)return;const tag=parent.nodeName;
  if(tag==="SCRIPT"||tag==="STYLE"||tag==="TEXTAREA")return;
  const src=n.nodeValue,trimmed=src.trim();if(!trimmed)return;
  const hit=dict[trimmed];if(hit&&hit!==trimmed)n.nodeValue=src.replace(trimmed,hit)})}
function v202TranslateScreen(){const dict=v202Dict();document.documentElement.lang=v202Lang()||"ja";
 if(!dict||v202Busy)return;v202Busy=true;
 try{document.querySelectorAll(".headAction,.title,.head .sub,#syncInfo").forEach(el=>v202Element(el,dict));
  if(V202_SCREENS.includes(currentScreen)){
   document.querySelectorAll(V202_SELECTORS).forEach(el=>v202Element(el,dict));
   document.querySelectorAll(".qrCreateForm input[placeholder],.qrCreateForm textarea[placeholder],#v1102QualityMemo,#v1102CorrectionReason").forEach(el=>{
    const ph=el.getAttribute("placeholder"),hit=ph&&dict[ph];if(hit)el.setAttribute("placeholder",hit)});
   if(currentScreen==="v1102QualityPage"){const memo=document.getElementById("v1102QualityMemo");
    if(memo){const note=v202Msg("メモは日本語で入力してください（必要なら日本人スタッフに聞いてください）。");
     memo.setAttribute("placeholder",note);let box=document.getElementById("v202JapaneseMemoNote");
     if(!box){box=document.createElement("div");box.id="v202JapaneseMemoNote";box.className="small";
      memo.insertAdjacentElement("beforebegin",box)}box.textContent=note}}}}catch(e){}
 v202Busy=false}
function v202Watch(){if(v202Observer)return;const host=document.getElementById("app")||document.body;if(!host)return;
 try{v202Observer=new MutationObserver(()=>{if(v202Busy||!v202Dict())return;
  if(v202Timer)clearTimeout(v202Timer);v202Timer=setTimeout(()=>{v202Timer=null;v202TranslateScreen()},80)});
  v202Observer.observe(host,{childList:true,subtree:true})}catch(e){}}
/* v1.201 の全文置換・ふりがなを停止する */
try{if(v201Observer)v201Observer.disconnect()}catch(e){}
v201Observer=null;
v201Apply=function(){document.documentElement.lang=v202Lang()||"ja"};
v201Watch=function(){};
v201Text=function(){return null};
v201RubyBar=function(){document.querySelector(".v201RubyBar")?.remove()};
window.v201Apply=v201Apply;
document.querySelector(".v201RubyBar")?.remove();
/* v1.138/v1.139 の言語切替UIと全文走査は使わず、担当者ごとに自動で言語を決める */
v138Language="ja";
v138T=function(value){return v202T(value)};
v138TextNode=function(){};
v138TranslateElement=function(){};
v138TranslateScreen=function(){v202TranslateScreen()};
v138RestoreLanguage=function(){document.documentElement.lang=v202Lang()||"ja"};
v138LanguageSwitchHtml=function(){return""};
v138SetLanguage=function(){};
const v202ShellBase=pageShell;
pageShell=function(title,sub,body,opts={}){const r=v202ShellBase(title,sub,body,opts);
 document.querySelector(".v201RubyBar")?.remove();
 if(opts&&opts.login){const select=document.getElementById("loginUser");
  if(select)select.onchange=function(){const s=this.value;login();
   const rep=document.getElementById("loginUser");if(rep)rep.value=s;v202TranslateScreen()}}
 v202TranslateScreen();v202Watch();return r};
window.pageShell=pageShell;
const v202QrSaveLotBase=qrSaveLot;
qrSaveLot=async function(){if(v202Dict()){
  const checks=[["qrReceivedDate","入庫日を入力してください。"],["qrItemName","品目を選択してください。"],
   ["qrPurchaseStaff","仕入れ担当者を入力してください。"],["qrContainerType","荷姿を選択してください。"],
   ["qrQty","数量を入力してください。"],["qrSupplier","仕入先を入力してください。"],
   ["qrOrigin","産地を入力してください。"],["qrLoc","保管場所を選択してください。"]];
  for(const [id,message] of checks){const el=document.getElementById(id);
   if(el&&!String(el.value||"").trim()){alert(v202Msg(message));el.focus();return}}}
 return v202QrSaveLotBase()};
const v202SaveQualityBase=v1102SaveQuality;
v1102SaveQuality=async function(q,supersedesId=""){if(v202Dict()){
  const grade=document.querySelector('input[name="v1102Grade"]:checked')?.value||"",
   issues=[...document.querySelectorAll('input[name="v1102Issue"]:checked')],
   memo=document.getElementById("v1102QualityMemo")?.value.trim()||"",
   correction=document.getElementById("v1102CorrectionReason")?.value.trim()||"";
  if(!grade)return alert(v202Msg("総合判定を選択してください。"));
  if(grade==="good"&&(issues.length||v1102QualityPhotos.length))return alert(v202Msg("「良好」のときは状態と写真を登録できません。"));
  if((grade==="review"||grade==="bad")&&!issues.length)return alert(v202Msg("「要確認」「不良」のときは状態を1つ以上選んでください。"));
  if(issues.some(x=>x.value==="その他")&&!memo)return alert(v202Msg("「その他」の内容をメモに入力してください。"));
  if(supersedesId&&!correction)return alert(v202Msg("訂正理由を入力してください。"))}
 return v202SaveQualityBase(q,supersedesId)};
v202Watch();v202TranslateScreen();


/* ===== v1.199-c3 廃棄記録の削除：クラウド未登録の記録にも対応 ===== */
v1113DeleteWasteHistoryRow=async function(id){
 const key=encodeURIComponent(String(id)),base=`${SUPABASE_URL}/rest/v1/${HISTORY_TABLES.wasteRecords}`
 ;const response=await fetch(`${base}?id=eq.${key}&select=id`,{method:"DELETE",headers:historyApiHeaders({Prefer:"return=representation"})})
 ;if(!response.ok)throw new Error(await response.text()||"廃棄履歴を削除できませんでした")
 ;const deleted=await response.json()
 ;if(Array.isArray(deleted)&&deleted.some(row=>String(row?.id||"")===String(id)))return
 ;const check=await fetch(`${base}?id=eq.${key}&select=id`,{headers:historyApiHeaders()})
 ;if(!check.ok)throw new Error("クラウド上の廃棄記録を削除できませんでした。権限を確認してください")
 ;const rows=await check.json()
 ;if(Array.isArray(rows)&&rows.length)throw new Error("クラウド上の廃棄記録を削除できませんでした。権限を確認してください")};


/* ===== v1.199-c4 履歴テーブル同期の自己修復 =====
   historyTablesReady は起動時に一度失敗すると再読み込みまで false のままで、
   保存処理が丸ごと飛ばされ続ける。しかも画面には何も出ない。
   定期的に復旧を試み、駄目なら管理者に見えるようにする。        */
(function(){
 let v1204Busy=false,v1204Warned=false;
 async function v1204HealHistorySync(){
  if(v1204Busy)return;
  if(typeof cloudReady==="undefined"||!cloudReady)return;
  if(historyTablesReady)return;
  v1204Busy=true;
  try{
   await loadHistoryTablesToDb();
   if(historyTablesReady){
    v1204Warned=false;
    setSyncState("保存済み","履歴テーブルの同期を復旧しました");
   }else if(!v1204Warned&&db&&db.role==="admin"){
    v1204Warned=true;
    setSyncState("失敗","履歴テーブルへ保存できていません");
   }
  }catch(e){console.warn("history sync heal failed",e)}
  finally{v1204Busy=false}
 }
 setTimeout(v1204HealHistorySync,5000);
 setInterval(v1204HealHistorySync,60000);
 window.v1204HealHistorySync=v1204HealHistorySync;
})();


/* ===== v1.199-c5 履歴テーブル保存の認証対応とエラーの可視化 =====
   v1.199の認証改修は callRpc / qrSelect / qrInsert / qrApiHeaders だけを
   JWT対応にしており、履歴テーブル(inventory_records / waste_records /
   inventory_movements)の経路が漏れていた。加えて upsertHistoryTable の
   失敗は呼び出し側で握りつぶされるため、画面は「保存済み」のまま
   サーバーには1行も入らない状態になっていた。                     */
(function(){
 if(typeof v199ApiHeaders==="function"){
   historyApiHeaders=v199ApiHeaders;
   window.historyApiHeaders=v199ApiHeaders;
 }
 window.v1205LastHistoryError="";
 let v1205Alerted=false;
 function v1205Report(where,e){
   const msg=String((e&&e.message)||e||"");
   window.v1205LastHistoryError=where+" / "+msg;
   console.error("[履歴テーブル]",where,msg);
   try{ setSyncState("失敗","履歴テーブル："+msg.slice(0,120)); }catch(_){}
   if(!v1205Alerted&&db&&db.role==="admin"){
     v1205Alerted=true;
     try{ alert("履歴テーブルへの保存に失敗しました。\n\n【場所】"+where+"\n\n【サーバーの応答】\n"+msg); }catch(_){}
   }
 }
 window.v1205Report=v1205Report;

 const v1205UpsertBase=upsertHistoryTable;
 upsertHistoryTable=async function(table,rows,mapper){
   try{
     return await v199RetryOnAuth(()=>v1205UpsertBase(table,rows,mapper));
   }catch(e){ v1205Report("保存 "+table,e); throw e; }
 };
 window.upsertHistoryTable=upsertHistoryTable;

 const v1205FetchBase=fetchHistoryTable;
 fetchHistoryTable=async function(table){
   try{
     return await v199RetryOnAuth(()=>v1205FetchBase(table));
   }catch(e){ v1205Report("読み込み "+table,e); throw e; }
 };
 window.fetchHistoryTable=fetchHistoryTable;

 const v1205DeleteBase=deleteHistoryRows;
 deleteHistoryRows=async function(table,ids){
   return await v199RetryOnAuth(()=>v1205DeleteBase(table,ids));
 };
 window.deleteHistoryRows=deleteHistoryRows;
})();


/* ===== v1.199-c6 同期診断パネル =====
   端末側の実際の認証状態とサーバー応答を画面に出す。
   iPadでは開発者コンソールが見られないため、失敗時に自動表示する。 */
(function(){
 function v1206Mask(t){ if(!t)return "(なし)"; return t.slice(0,12)+"…"+t.slice(-8)+"（長さ"+t.length+"）"; }
 function v1206Jwt(t){
   try{
     const b=t.split(".")[1].replace(/-/g,"+").replace(/_/g,"/");
     const j=JSON.parse(decodeURIComponent(escape(atob(b+"===".slice((b.length+3)%4)))));
     return j;
   }catch(e){ return null; }
 }
 async function v1206Http(label,url,opt){
   try{
     const res=await fetch(url,opt);
     const body=await res.text();
     return label+" → HTTP "+res.status+" "+(res.ok?"OK":"NG")+"\n    "+(body?body.slice(0,300):"(本文なし)");
   }catch(e){ return label+" → 通信エラー: "+String(e&&e.message||e); }
 }
 async function v1206Diag(){
   const L=[];
   const now=Date.now();
   L.push("■ 利用者");
   L.push("  名前 / 役割 : "+((db&&db.user)||"?")+" / "+((db&&db.role)||"?"));
   L.push("");
   L.push("■ ログインセッション");
   let sess=null;
   try{ sess=authReadSession(); }catch(e){}
   L.push("  セッション : "+(sess?"あり":"なし"));
   const tok=(typeof authToken==="function"&&authToken())||"";
   L.push("  トークン   : "+v1206Mask(tok));
   let expMs=0;
   try{ expMs=authExpiryMs(); }catch(e){}
   if(expMs){
     const min=Math.round((expMs-now)/60000);
     L.push("  有効期限   : "+new Date(expMs).toLocaleString("ja-JP")+"（残り "+min+" 分）"+(expMs<=now?" ★期限切れ":""));
   }else{ L.push("  有効期限   : 不明"); }
   const pay=tok?v1206Jwt(tok):null;
   if(pay){
     L.push("  JWTのrole  : "+(pay.role||"(なし)"));
     L.push("  JWTのemail : "+(pay.email||"(なし)"));
     L.push("  JWTのsub   : "+(pay.sub||"(なし)"));
   }else if(tok){ L.push("  JWT解析    : 失敗（形式が不正）"); }
   L.push("");
   L.push("■ セッション更新");
   let ens=null;
   try{ ens=await authEnsure(); }catch(e){ ens="例外: "+String(e&&e.message||e); }
   L.push("  authEnsure : "+ens);
   const tok2=(typeof authToken==="function"&&authToken())||"";
   L.push("  更新後token: "+v1206Mask(tok2));
   L.push("");
   L.push("■ サーバー応答");
   const H={apikey:SUPABASE_KEY,Authorization:"Bearer "+(tok2||SUPABASE_KEY),"Content-Type":"application/json"};
   L.push(await v1206Http("  RPC current_app_role", SUPABASE_URL+"/rest/v1/rpc/current_app_role",{method:"POST",headers:H,body:"{}"}));
   L.push(await v1206Http("  GET waste_records", SUPABASE_URL+"/rest/v1/waste_records?select=id&limit=1",{headers:H}));
   const wr=(db&&db.wasteRecords&&db.wasteRecords.length)?db.wasteRecords[db.wasteRecords.length-1]:null;
   if(wr&&typeof wasteRecordTableRow==="function"){
     L.push(await v1206Http("  POST waste_records（1件）", SUPABASE_URL+"/rest/v1/waste_records",
       {method:"POST",headers:{...H,Prefer:"resolution=merge-duplicates,return=minimal"},body:JSON.stringify([wasteRecordTableRow(wr)])}));
   }else{ L.push("  POST waste_records → 端末に廃棄記録がないため未実施"); }
   L.push("");
   L.push("■ 直近の履歴テーブルエラー");
   L.push("  REST側 : "+(window.v1205LastHistoryError||"(記録なし)"));
   L.push("  RPC側  : "+(window.v1207LastRpcError||"(記録なし)"));
   v1206Show(L.join("\n"));
 }
 function v1206Show(text){
   let o=document.getElementById("v1206Panel");
   if(o)o.remove();
   o=document.createElement("div");
   o.id="v1206Panel";
   o.setAttribute("style","position:fixed;inset:0;z-index:99999;background:#fff;color:#111;overflow:auto;padding:12px;font:12px/1.5 ui-monospace,Menlo,monospace;-webkit-user-select:text;user-select:text");
   const b=document.createElement("button");
   b.textContent="閉じる";
   b.setAttribute("style","position:sticky;top:0;float:right;padding:8px 16px;font-size:14px;border:0;border-radius:8px;background:#334155;color:#fff");
   b.onclick=()=>o.remove();
   const h=document.createElement("div");
   h.textContent="同期診断（この画面を撮影して送ってください）";
   h.setAttribute("style","font-size:14px;font-weight:700;margin-bottom:8px");
   const pre=document.createElement("pre");
   pre.textContent=text;
   pre.setAttribute("style","white-space:pre-wrap;word-break:break-all;margin:0");
   o.appendChild(b); o.appendChild(h); o.appendChild(pre);
   document.body.appendChild(o);
 }
 window.v1206Diag=v1206Diag;

 let v1206Auto=false;
 const v1206Timer=setInterval(()=>{
   if(v1206Auto)return;
   const bad=(typeof historyTablesReady!=="undefined"&&!historyTablesReady)||!!window.v1205LastHistoryError;
   if(false&&bad&&db&&db.role==="admin"&&document.body){
     v1206Auto=true; clearInterval(v1206Timer);
     setTimeout(()=>{ v1206Diag().catch(e=>v1206Show("診断中にエラー: "+String(e&&e.message||e))); },1500);
   }
 },3000);
})();


/* ===== v1.199-c7 履歴保存をRPC失敗時にREST直書きへ退避 =====
   真の保存経路は RPC save_history_records_v188。これが失敗すると
   loadHistoryTablesToDb の同じ try の中で例外になり、直前に true にした
   historyTablesReady が false へ戻る。その結果、以後の保存が丸ごと
   スキップされ続けていた。読み込み成功と保存を切り離し、RPCが駄目なら
   実地検証で 201 を確認済みの REST 直書きへ退避する。            */
(function(){
 window.v1207LastRpcError="";
 const v1207RpcSave=saveHistoryTablesNow;

 async function v1207RestSave(){
   const role=db&&db.role;
   if(["admin","worker"].includes(role)){
     await upsertHistoryTable(HISTORY_TABLES.records,db.records||[],inventoryRecordTableRow);
     await upsertHistoryTable(HISTORY_TABLES.movements,db.movements||[],movementTableRow);
   }
   if(["admin","worker","sales","clerk"].includes(role)){
     await upsertHistoryTable(HISTORY_TABLES.wasteRecords,db.wasteRecords||[],wasteRecordTableRow);
   }
 }

 saveHistoryTablesNow=async function(){
   try{
     await v1207RpcSave();
     window.v1207LastRpcError="";
     return;
   }catch(e){
     const msg=String((e&&e.message)||e||"");
     window.v1207LastRpcError=msg;
     console.error("[履歴RPC失敗→REST退避]",msg);
     await v1207RestSave();
     try{ setSyncState("保存済み","履歴を直接保存（RPCは失敗）"); }catch(_){}
   }
 };
 window.saveHistoryTablesNow=saveHistoryTablesNow;

 loadHistoryTablesToDb=async function(){
   try{
     const [records,wasteRecords,movements]=await Promise.all([
       fetchHistoryTable(HISTORY_TABLES.records),
       fetchHistoryTable(HISTORY_TABLES.wasteRecords),
       fetchHistoryTable(HISTORY_TABLES.movements)]);
     db.records=mergeHistoryById(db.records,records).sort((a,b)=>new Date(a.createdAt||0)-new Date(b.createdAt||0));
     db.wasteRecords=mergeHistoryById(db.wasteRecords,wasteRecords).sort((a,b)=>new Date(a.date||a.createdAt||0)-new Date(b.date||b.createdAt||0));
     db.movements=mergeHistoryById(db.movements,movements).sort((a,b)=>new Date(a.createdAt||0)-new Date(b.createdAt||0));
     historyTablesReady=true;
   }catch(e){
     historyTablesReady=false;
     if(typeof v1205Report==="function")v1205Report("履歴の読み込み",e);
     return;
   }
   try{ await saveHistoryTablesNow(); }
   catch(e){ if(typeof v1205Report==="function")v1205Report("履歴の保存",e); }
   try{ v188PersistDb(); }catch(e){}
 };
 window.loadHistoryTablesToDb=loadHistoryTablesToDb;
})();


/* ===== v1.199-c8 =====
   ① 同期診断の自動表示を停止（調査用の足場だったため）
   ② Android IMEで仕入先の1文字目が確定してしまう不具合の修正
   ③ 仕入先・単協名の候補を編集できるようにする
   ④ 戻るボタンを1つ前の画面へ戻す（履歴スタック）        */
(function(){

 /* ---------- ② IME中はdatalistを書き換えない ---------- */
 let v1208Composing=false, v1208Timer=null;
 document.addEventListener("compositionstart",()=>{v1208Composing=true},true);
 document.addEventListener("compositionend",e=>{
   v1208Composing=false;
   const id=e&&e.target&&e.target.id;
   if(id==="qrSupplier")v1208Later(v1208SupplierBase);
   else if(id==="qrCooperativeName"||id==="qrEditCooperativeName")v1208Later(v1208CoopBase);
 },true);
 function v1208Later(fn){
   if(!fn)return;
   clearTimeout(v1208Timer);
   v1208Timer=setTimeout(()=>{try{fn()}catch(e){}},220);
 }
 const v1208SupplierBase=typeof qrFillSupplierDatalist==="function"?qrFillSupplierDatalist:null;
 const v1208CoopBase=typeof qrUpdateCooperativeSuggestions==="function"?qrUpdateCooperativeSuggestions:null;
 if(v1208SupplierBase){
   qrFillSupplierDatalist=function(){ if(v1208Composing)return; return v1208Later(v1208SupplierBase); };
   window.qrFillSupplierDatalist=qrFillSupplierDatalist;
 }
 if(v1208CoopBase){
   qrUpdateCooperativeSuggestions=function(){ if(v1208Composing)return; return v1208Later(v1208CoopBase); };
   window.qrUpdateCooperativeSuggestions=qrUpdateCooperativeSuggestions;
 }

 /* ---------- ③ 候補の非表示リスト ---------- */
 const v1208MastersBase=qrEnsureMasters;
 qrEnsureMasters=function(){
   v1208MastersBase();
   db.qrSupplierHidden=Array.isArray(db.qrSupplierHidden)?db.qrSupplierHidden:[];
   db.qrCooperativeHidden=Array.isArray(db.qrCooperativeHidden)?db.qrCooperativeHidden:[];
 };
 window.qrEnsureMasters=qrEnsureMasters;

 function v1208Hidden(kind){
   qrEnsureMasters();
   const a=kind==="supplier"?db.qrSupplierHidden:db.qrCooperativeHidden;
   return new Set(a.map(v=>qrNormalizeName(v)));
 }
 window.v1208IsHidden=(kind,name)=>v1208Hidden(kind).has(qrNormalizeName(name));

 const v1208SupListBase=qrSupplierList;
 qrSupplierList=async function(){
   const arr=await v1208SupListBase();
   const h=v1208Hidden("supplier");
   return arr.filter(n=>!h.has(qrNormalizeName(n)));
 };
 window.qrSupplierList=qrSupplierList;

 const v1208CoopListBase=qrCooperativeList;
 qrCooperativeList=async function(){
   const arr=await v1208CoopListBase();
   const h=v1208Hidden("cooperative");
   return arr.filter(n=>!h.has(qrNormalizeName(n)));
 };
 window.qrCooperativeList=qrCooperativeList;
})();


/* ===== v1.199-c8 後半：候補の編集画面と「戻る」の履歴スタック ===== */
async function v1208CandidatePage(kind="supplier",msg=""){
  setScreen("v1208CandidatePage",[kind,msg]);
  if(!canQrOperate()){alert("仕入先・単協名の候補を編集できる権限がありません");return qrHome()}
  qrEnsureMasters();
  const isSup=kind!=="cooperative";
  const label=isSup?"仕入先":"単協名";
  const master=isSup?db.qrSuppliers:db.qrCooperatives;
  const hidden=isSup?db.qrSupplierHidden:db.qrCooperativeHidden;
  let all=[];
  try{ all=isSup?await v1208AllSuppliers():await v1208AllCooperatives(); }catch(e){ all=[...master]; }
  const hset=new Set(hidden.map(v=>qrNormalizeName(v)));
  const mset=new Set(master.map(v=>qrNormalizeName(v)));
  const shown=all.filter(n=>!hset.has(qrNormalizeName(n)));
  const hid=all.filter(n=>hset.has(qrNormalizeName(n)));

  const tabs=`<div class="card"><div class="row">
    <button class="btn ${isSup?"":"gray"}" ${seikaEventAttrs('click','v1208CandidatePage',["supplier",""])}>仕入先</button>
    <button class="btn ${isSup?"gray":""}" ${seikaEventAttrs('click','v1208CandidatePage',["cooperative",""])}>単協名</button>
  </div></div>`;

  const add=`<div class="card"><b>${label}を追加</b>
    <div class="small">正しい名称を登録すると、入力時の候補に必ず出るようになります。</div>
    <input id="v1208AddName" class="input" placeholder="例：${isSup?"中央園芸":"茨城中央"}" autocomplete="off">
    <button class="btn" style="width:100%;margin-top:10px" ${seikaEventAttrs('click','v1208AddCandidate',[kind])}>追加する</button></div>`;

  const list=`<div class="card"><b>候補に出る${label}（${shown.length}件）</b>
    <div class="small">誤入力されたものは「非表示」にすると候補から消えます。過去の記録自体は消えません。</div>
    ${shown.length?shown.map(n=>`<div class="qrRow" style="display:flex;align-items:center;gap:8px;padding:6px 0;border-bottom:1px solid #eee">
        <div style="flex:1">${esc(n)}${mset.has(qrNormalizeName(n))?' <span class="small">（マスタ登録）</span>':' <span class="small">（過去の入力）</span>'}</div>
        <button class="btn gray" style="padding:6px 12px" ${seikaEventAttrs('click','v1208HideCandidate',[kind,n])}>非表示</button>
        <button class="btn" style="padding:6px 12px" ${seikaEventAttrs('click','v1208RenameCandidate',[kind,n])}>名称修正</button>
      </div>`).join(""):'<div class="small">候補がありません。</div>'}</div>`;

  const hiddenBox=`<div class="card"><b>非表示にした${label}（${hid.length}件）</b>
    ${hid.length?hid.map(n=>`<div style="display:flex;align-items:center;gap:8px;padding:6px 0;border-bottom:1px solid #eee">
        <div style="flex:1">${esc(n)}</div>
        <button class="btn" style="padding:6px 12px" ${seikaEventAttrs('click','v1208ShowCandidate',[kind,n])}>戻す</button>
      </div>`).join(""):'<div class="small">ありません。</div>'}</div>`;

  pageShell(`${label}の候補を編集`,"誤入力された候補を非表示にできます",okHtml(msg)+tabs+add+list+hiddenBox);
}
window.v1208CandidatePage=v1208CandidatePage;

async function v1208AllSuppliers(){
  qrEnsureMasters();let arr=[...db.qrSuppliers];
  try{const rows=await qrSelect("qr_lots","select=supplier&supplier=not.is.null&order=created_at.desc&limit=300");
      arr=arr.concat(rows.map(r=>r.supplier).filter(Boolean))}catch(e){}
  const seen=new Set;
  return arr.map(v=>String(v||"").trim()).filter(v=>{const k=qrNormalizeName(v);if(!k||seen.has(k))return false;seen.add(k);return true});
}
async function v1208AllCooperatives(){
  qrEnsureMasters();let arr=[...db.qrCooperatives];
  try{const rows=await qrSelect("qr_lots","select=cooperative_name&cooperative_name=not.is.null&order=created_at.desc&limit=300");
      arr=arr.concat(rows.map(r=>r.cooperative_name).filter(Boolean))}catch(e){}
  const seen=new Set;
  return arr.map(v=>String(v||"").trim()).filter(v=>{const k=qrNormalizeName(v);if(!k||seen.has(k))return false;seen.add(k);return true});
}
window.v1208AllSuppliers=v1208AllSuppliers;window.v1208AllCooperatives=v1208AllCooperatives;

function v1208Lists(kind){
  qrEnsureMasters();
  return kind!=="cooperative"
    ?{master:db.qrSuppliers,hidden:db.qrSupplierHidden}
    :{master:db.qrCooperatives,hidden:db.qrCooperativeHidden};
}
function v1208AddCandidate(kind){
  const el=document.getElementById("v1208AddName");
  const name=String(el&&el.value||"").trim();
  if(!name)return alert("名称を入力してください");
  const{master,hidden}=v1208Lists(kind);
  const k=qrNormalizeName(name);
  const i=hidden.findIndex(v=>qrNormalizeName(v)===k);
  if(i>=0)hidden.splice(i,1);
  if(!master.some(v=>qrNormalizeName(v)===k))master.push(name);
  save();v1208CandidatePage(kind,`「${name}」を追加しました`);
}
function v1208HideCandidate(kind,name){
  if(!confirm(`「${name}」を候補から非表示にします。\n過去の記録は消えません。よろしいですか？`))return;
  const{master,hidden}=v1208Lists(kind);
  const k=qrNormalizeName(name);
  const i=master.findIndex(v=>qrNormalizeName(v)===k);
  if(i>=0)master.splice(i,1);
  if(!hidden.some(v=>qrNormalizeName(v)===k))hidden.push(name);
  save();v1208CandidatePage(kind,`「${name}」を非表示にしました`);
}
function v1208ShowCandidate(kind,name){
  const{hidden}=v1208Lists(kind);
  const k=qrNormalizeName(name);
  const i=hidden.findIndex(v=>qrNormalizeName(v)===k);
  if(i>=0)hidden.splice(i,1);
  save();v1208CandidatePage(kind,`「${name}」を候補に戻しました`);
}
function v1208RenameCandidate(kind,name){
  const next=prompt(`「${name}」の正しい名称を入力してください。\n元の名称は候補から非表示になります。`,name);
  if(next===null)return;
  const fixed=String(next).trim();
  if(!fixed)return alert("名称が空です");
  const{master,hidden}=v1208Lists(kind);
  const ok=qrNormalizeName(name),nk=qrNormalizeName(fixed);
  if(ok!==nk){
    const i=master.findIndex(v=>qrNormalizeName(v)===ok);
    if(i>=0)master.splice(i,1);
    if(!hidden.some(v=>qrNormalizeName(v)===ok))hidden.push(name);
  }
  const j=hidden.findIndex(v=>qrNormalizeName(v)===nk);
  if(j>=0)hidden.splice(j,1);
  if(!master.some(v=>qrNormalizeName(v)===nk))master.push(fixed);
  save();v1208CandidatePage(kind,`「${name}」を「${fixed}」に修正しました`);
}
window.v1208AddCandidate=v1208AddCandidate;window.v1208HideCandidate=v1208HideCandidate;
window.v1208ShowCandidate=v1208ShowCandidate;window.v1208RenameCandidate=v1208RenameCandidate;

/* ---------- QRホームに入口を追加 ---------- */
(function(){
 const base=qrHome;
 qrHome=async function(msg=""){
   await base(msg);
   if(!canQrOperate())return;
   if(document.getElementById("v1208CandEntry"))return;
   const wrap=document.querySelector(".wrap");
   if(!wrap)return;
   wrap.insertAdjacentHTML("beforeend",
     `<div class="card" id="v1208CandEntry"><b>仕入先・単協名の候補を編集</b>
      <div class="small">誤入力された候補を非表示にできます。</div>
      <button class="btn" style="width:100%;margin-top:10px" ${seikaEventAttrs('click','v1208CandidatePage',["supplier",""])}>候補を編集する</button></div>`);
 };
 window.qrHome=qrHome;
})();

/* ===== v1.199-c8 ④ 戻るボタンを1つ前の画面へ =====
   従来の goBack は画面名の分岐で、該当しないものは全部 home() だった。
   setScreen が呼ばれるたびに履歴を積み、goBack は1つ前を再描画する。
   renderCurrent が window[画面名](...引数) で解決できる作りなので、
   同じ方法で前の画面を復元できる。                              */
(function(){
 const V1208_MAX=40;
 let v1208Nav=[];            // [{name,args}]
 let v1208Restoring=false;   // 復元中はスタックを積まない

 const v1208SetScreenBase=setScreen;
 setScreen=function(name,args=[]){
   v1208SetScreenBase(name,args);
   if(v1208Restoring)return;
   if(name==="login"){v1208Nav=[];return}
   const last=v1208Nav[v1208Nav.length-1];
   const same=last&&last.name===name&&JSON.stringify(last.args)===JSON.stringify(args);
   if(same)return;
   if(last&&last.name===name)v1208Nav[v1208Nav.length-1]={name,args};
   else v1208Nav.push({name,args});
   if(v1208Nav.length>V1208_MAX)v1208Nav.splice(0,v1208Nav.length-V1208_MAX);
 };
 window.setScreen=setScreen;

 function v1208IsHome(n){
   return !n||n==="home"||n==="login"||n==="qrHome";
 }

 const v1208GoBackBase=goBack;
 goBack=function(){
   const s=currentScreen;
   // カメラ画面は停止処理が必要なので従来処理へ
   if(s==="qrCameraPage"||s==="qrCountCameraPage")return v1208GoBackBase();
   // 出庫履歴・品質一覧からの復帰も従来処理を優先
   if(s==="qrLotDetail"&&(typeof v1144OutboundDetailReturn!=="undefined"&&v1144OutboundDetailReturn))return v1208GoBackBase();
   if(s==="qrLotDetail"&&(typeof v1140QualityDetailReturn!=="undefined"&&v1140QualityDetailReturn))return v1208GoBackBase();

   // 現在の画面をスタックから外し、1つ前へ
   if(v1208Nav.length&&v1208Nav[v1208Nav.length-1].name===s)v1208Nav.pop();
   let prev=null;
   const skip=window.V1209_SKIP||new Set();
   while(v1208Nav.length){
     const cand=v1208Nav[v1208Nav.length-1];
     if(cand.name===s||skip.has(cand.name)){v1208Nav.pop();continue}
     prev=cand;break;
   }
   // 戻り先が無い場合、QR系の画面からはQR管理ホームへ
   if(!prev){
     if(String(s||"").startsWith("qr")&&typeof qrHome==="function")return qrHome();
     return v1208GoBackBase();
   }
   const fn=window[prev.name];
   if(typeof fn!=="function")return v1208GoBackBase();
   v1208Restoring=true;
   let r;
   try{ r=fn(...(prev.args||[])); }
   catch(e){ v1208Restoring=false; return v1208GoBackBase(); }
   if(r&&typeof r.finally==="function")return r.finally(()=>{v1208Restoring=false});
   setTimeout(()=>{v1208Restoring=false},0);
   return r;
 };
 window.goBack=goBack;
 window.v1208NavDepth=()=>v1208Nav.length;
})();

/* ===== v1.199-c9 =====
   ① 戻るで品質評価の登録画面へ復帰しないようにする
   ② 在庫入力・在庫表の重さ（全ロット／全移動履歴の再取得）を解消
   ③ ホーム画面でボタン位置が後からズレるのを抑える           */
(function(){

 /* ---------- ① 復元してはいけない画面 ----------
    v1102QualityPage は v1114OpenNewQualityEvaluation に差し替えられており、
    開くと「登録済みです」の確認が再発火して qrLotDetail へ飛ばされる。
    履歴の戻り先としては使わず、1つ前へ読み飛ばす。            */
 const V1209_SKIP=new Set(["v1102QualityPage","qrCameraPage","qrCountCameraPage"]);
 window.V1209_SKIP=V1209_SKIP;

 /* ---------- ② 重いQR取得のキャッシュ ---------- */
 const V1209_TTL=60000;
 const v1209Cache=new Map();
 function v1209Get(key){
   const hit=v1209Cache.get(key);
   if(hit&&Date.now()-hit.at<V1209_TTL)return hit.value;
   return undefined;
 }
 function v1209Set(key,value){v1209Cache.set(key,{at:Date.now(),value});return value}
 window.v1209ClearQrCache=function(){v1209Cache.clear()};

 if(typeof v163SelectAll==="function"){
   const base=v163SelectAll;
   const heavy=["qr_lots","qr_lot_movements","qr_lot_monthly_snapshots"];
   v163SelectAll=async function(table,baseQuery,pageSize=1000){
     if(!heavy.includes(table))return base(table,baseQuery,pageSize);
     const key="all|"+table+"|"+baseQuery;
     const hit=v1209Get(key);
     if(hit)return hit.slice();
     const rows=await base(table,baseQuery,pageSize);
     v1209Set(key,rows);
     return rows.slice();
   };
   window.v163SelectAll=v163SelectAll;
 }

 if(typeof qrInventoryKgByItemForRoom==="function"){
   const base=qrInventoryKgByItemForRoom;
   qrInventoryKgByItemForRoom=async function(room){
     const key="room|"+String(room);
     const hit=v1209Get(key);
     if(hit)return hit;
     return v1209Set(key,await base(room));
   };
   window.qrInventoryKgByItemForRoom=qrInventoryKgByItemForRoom;
 }
 if(typeof qrInventoryKgByItemForRoomByDay==="function"){
   const base=qrInventoryKgByItemForRoomByDay;
   qrInventoryKgByItemForRoomByDay=async function(room,dayKeys){
     const key="roomday|"+String(room)+"|"+(dayKeys||[]).join(",");
     const hit=v1209Get(key);
     if(hit)return hit;
     return v1209Set(key,await base(room,dayKeys));
   };
   window.qrInventoryKgByItemForRoomByDay=qrInventoryKgByItemForRoomByDay;
 }

 /* 書き込みが起きたらキャッシュを捨てる */
 if(typeof callRpc==="function"){
   const base=callRpc;
   callRpc=async function(name,args){
     const r=await base(name,args);
     if(/^(create|update|delete|save|apply|adjust|move|register|confirm|v\d+)/.test(String(name||"")))
       v1209Cache.clear();
     return r;
   };
   window.callRpc=callRpc;
 }
})();

/* ---------- ② 在庫表の白画面を減らす ---------- */
(function(){
 if(typeof weeklyData!=="function")return;
 const base=weeklyData;
 weeklyData=async function(...a){
   try{
     if(typeof pageShell==="function")
       pageShell("在庫表","集計中",
         '<div class="card"><b>読み込み中です</b><div class="small">QR在庫と通常在庫を集計しています。</div></div>');
   }catch(e){}
   return base(...a);
 };
 window.weeklyData=weeklyData;
})();

/* ---------- ③ ホームのレイアウトずれ対策 ---------- */
(function(){
 const css=document.createElement("style");
 css.textContent=
  "#v1143QualityTask{min-height:64px}"+
  "#v1103BuyerQualityAlerts{min-height:40px}"+
  "#v1143TodayTasks{min-height:96px}"+
  ".homePrimary{scroll-margin-top:0}";
 document.head.appendChild(css);

 /* 同じ画面を描き直すときはスクロール位置を戻す（画面が飛ぶのを防ぐ） */
 if(typeof pageShell==="function"){
   const base=pageShell;
   let last="";
   pageShell=function(title,sub,body,opts={}){
     const same=(last===String(title));
     const y=same?(window.scrollY||0):0;
     const r=base(title,sub,body,opts);
     last=String(title);
     if(same&&y>0){try{window.scrollTo(0,y)}catch(e){}}
     return r;
   };
   window.pageShell=pageShell;
 }
})();

/* ===== v1.199-c10 在庫表の冷蔵庫切り替えを速くする =====
   qrInventoryKgByItemForRoomByDay は
     for(ロット) × for(98日) で v1101LotSnapshotAtDayEnd を呼び、
     そのたびに移動履歴を先頭から再生していた。
   この計算は「どの冷蔵庫を見ているか」に一切依存しない。
   冷蔵庫の切り替えごとに全ロット×98日分を作り直していたのが
   待ち時間と表の描画崩れの原因。結果を記憶して使い回す。      */
(function(){
 if(typeof v1101LotSnapshotAtDayEnd!=="function")return;
 const base=v1101LotSnapshotAtDayEnd;
 let memo=new Map();
 v1101LotSnapshotAtDayEnd=function(lot,lotMoves,dayKey){
   const id=String((lot&&(lot.id||lot.qr_key||lot.lot_no))||"");
   if(!id)return base(lot,lotMoves,dayKey);
   const key=id+"|"+String(dayKey);
   if(memo.has(key))return memo.get(key);
   const v=base(lot,lotMoves,dayKey);
   memo.set(key,v);
   return v;
 };
 window.v1101LotSnapshotAtDayEnd=v1101LotSnapshotAtDayEnd;

 /* 取得キャッシュを捨てるときは、この記憶も一緒に捨てる */
 const clearBase=window.v1209ClearQrCache;
 window.v1209ClearQrCache=function(){
   memo=new Map();
   if(typeof clearBase==="function")clearBase();
 };
 window.v1210ClearSnapshotMemo=function(){memo=new Map()};
 window.v1210SnapshotMemoSize=function(){return memo.size};
})();

/* 書き込みRPCのあとは記憶も破棄する */
(function(){
 if(typeof callRpc!=="function")return;
 const base=callRpc;
 callRpc=async function(name,args){
   const r=await base(name,args);
   if(/^(create|update|delete|save|apply|adjust|move|register|confirm)/.test(String(name||"")))
     { if(typeof window.v1210ClearSnapshotMemo==="function")window.v1210ClearSnapshotMemo(); }
   return r;
 };
 window.callRpc=callRpc;
})();

/* ===== v1.199-c11 在庫表の集計をサーバー側RPCへ =====
   RPC qr_lot_daily_state_v1211 が「日ごとの在庫数と保管場所」を
   変化した日だけ返す。端末側は移動履歴をダウンロードせず、
   品目解決・kg換算・大型容器などの業務判定は従来処理をそのまま使う。
   RPCが使えない場合は従来の端末側計算へ自動で戻る。        */
(function(){
 if(typeof qrInventoryKgByItemForRoomByDay!=="function")return;

 let v1211States=null;      // Map(lotId -> {from, ch:[[day,qty,loc,del]]})
 let v1211Active=false;
 let v1211CacheKey="";
 let v1211CacheAt=0;
 const V1211_TTL=60000;
 window.v1211LastError="";

 function v1211Lookup(lot,dayKey){
   if(!v1211States)return null;
   const rec=v1211States.get(String(lot&&lot.id||""));
   if(!rec)return null;
   if(dayKey<rec.from)return null;
   const ch=rec.ch;
   let lo=0,hi=ch.length-1,found=-1;
   while(lo<=hi){
     const mid=(lo+hi)>>1;
     if(ch[mid][0]<=dayKey){found=mid;lo=mid+1}else hi=mid-1;
   }
   if(found<0)return null;
   const c=ch[found];
   return{qty:Number(c[1])||0,location:String(c[2]||""),deleted:c[3]===true};
 }

 async function v1211Load(dayKeys){
   const days=[...new Set(dayKeys||[])].sort();
   if(!days.length)return false;
   const from=days[0],to=days[days.length-1],key=from+"|"+to;
   if(v1211States&&v1211CacheKey===key&&Date.now()-v1211CacheAt<V1211_TTL)return true;
   let ans;const v1216T0=performance.now();
   try{ ans=await callRpc("qr_lot_daily_state_v1211",{p_from:from,p_to:to}); }
   catch(e){ await new Promise(r=>setTimeout(r,800)); ans=await callRpc("qr_lot_daily_state_v1211",{p_from:from,p_to:to}); }
   if(!ans||ans.ok!==true||!Array.isArray(ans.lots))
     throw new Error((ans&&ans.message)||"日別在庫の取得に失敗しました");
   const map=new Map();
   for(const row of ans.lots)
     map.set(String(row.id||""),{from:String(row.from||from),ch:Array.isArray(row.ch)?row.ch:[]});
   window.v1216RpcSec=((performance.now()-v1216T0)/1000).toFixed(1);
   v1211States=map;v1211CacheKey=key;v1211CacheAt=Date.now();
   return true;
 }

 /* RPC使用中は移動履歴と月次スナップショットを取りに行かない */
 const v1211SelectAllBase=v163SelectAll;
 v163SelectAll=async function(table,baseQuery,pageSize=1000){
   if(v1211Active&&(table==="qr_lot_movements"||table==="qr_lot_monthly_snapshots"))return[];
   return v1211SelectAllBase(table,baseQuery,pageSize);
 };
 window.v163SelectAll=v163SelectAll;

 /* 日ごとの状態はRPCの結果を引く */
 const v1211SnapBase=v1101LotSnapshotAtDayEnd;
 v1101LotSnapshotAtDayEnd=function(lot,movements,dayKey){
   if(v1211Active)return v1211Lookup(lot,dayKey);
   return v1211SnapBase(lot,movements,dayKey);
 };
 window.v1101LotSnapshotAtDayEnd=v1101LotSnapshotAtDayEnd;

 const v1211ByDayBase=qrInventoryKgByItemForRoomByDay;
 qrInventoryKgByItemForRoomByDay=async function(room,dayKeys){
   let ready=false;
   try{ ready=await v1211Load(dayKeys); }
   catch(e){
     window.v1211LastError=String(e&&e.message||e);
     console.warn("[在庫表] サーバー側集計を使えないため端末側で計算します:",window.v1211LastError);
     ready=false;
   }
   if(!ready){
     if(window.v1216AllowClient)return v1211ByDayBase(room,dayKeys);
     window.v1216ServerFail=window.v1211LastError||"不明なエラー";
     throw new Error("サーバー集計を使えませんでした（"+window.v1216ServerFail+"）");
   }
   window.v1211LastError="";window.v1216ServerFail="";
   v1211Active=true;
   try{ return await v1211ByDayBase(room,dayKeys); }
   finally{ v1211Active=false; }
 };
 window.qrInventoryKgByItemForRoomByDay=qrInventoryKgByItemForRoomByDay;

 /* キャッシュ破棄に連動 */
 const clearBase=window.v1209ClearQrCache;
 window.v1209ClearQrCache=function(){
   v1211States=null;v1211CacheKey="";v1211CacheAt=0;
   if(typeof clearBase==="function")clearBase();
 };

 /* 数字が従来と一致するか確認する（管理者が任意に実行） */
 window.v1211Verify=async function(room=(typeof weeklyRoom!=="undefined"?weeklyRoom:"第2冷蔵庫")){
   const days=v163DayKeys(98);
   v1211States=null;v1211CacheKey="";
   const srv=await qrInventoryKgByItemForRoomByDay(room,days);
   v1211Active=false;
   if(typeof window.v1210ClearSnapshotMemo==="function")window.v1210ClearSnapshotMemo();
   const cli=await v1211ByDayBase(room,days);
   const diff=[];
   const walk=(a,b,label)=>{
     const keys=new Set([...Object.keys(a||{}),...Object.keys(b||{})]);
     for(const k of keys){
       const da=(a||{})[k]||{},dbb=(b||{})[k]||{};
       const dk=new Set([...Object.keys(da),...Object.keys(dbb)]);
       for(const d of dk){
         const x=JSON.stringify(da[d]||null),y=JSON.stringify(dbb[d]||null);
         if(x!==y)diff.push(`${label} ${k} ${d}: サーバー=${x} 端末=${y}`);
       }
     }
   };
   walk(srv.totals,cli.totals,"品目");
   walk(srv.normalTotals,cli.normalTotals,"通常");
   walk(srv.largeTotals,cli.largeTotals,"大型");
   const msg=diff.length
     ?`差異 ${diff.length} 件\n\n`+diff.slice(0,30).join("\n")
     :"差異はありません。サーバー側集計と端末側計算の数字は一致しています。";
   alert(msg);
   return diff;
 };
})();

/* ===== v1.203 登録済み日報の修正・削除 ===== */
(function(){
  let v1203EditId='';
  const v1203Jobs=new Map();

  function v1203CanEdit(){return typeof v1115CanTrimmingEdit==='function'?v1115CanTrimmingEdit():false}
  function v1203Num(x){const n=Number(x);return Number.isFinite(n)?n:0}

  /* 製造日報の下に「日報の修正・削除」カードを追加 */
  const v1203RenderDailyBase=v1200RenderDailyReport;
  v1200RenderDailyReport=function(rows,day,recv){
    v1203Jobs.clear();
    for(const row of rows||[]){const j=row.job||row;if(j&&j.id!=null)v1203Jobs.set(String(j.id),row)}
    const r=v1203RenderDailyBase.call(this,rows,day,recv);
    if(!v1203CanEdit()||!(rows||[]).length)return r;
    try{
      const cards=document.querySelectorAll('.card');
      if(!cards.length)return r;
      const host=cards[cards.length-1].parentNode;
      const div=document.createElement('div');
      div.className='card';
      div.innerHTML='<b>日報の修正・削除</b>'
        +'<div class="small" style="margin-top:4px">入力を間違えた日報を直せます。修正では作業日・使用原料・使用量・出来高・メモをすべて直し、単価も計算し直します。在庫は変わりません。</div>'
        +v1203EditListHtml(rows);
      host.appendChild(div);
    }catch(e){}
    return r;
  };
  window.v1200RenderDailyReport=v1200RenderDailyReport;

  function v1203EditListHtml(rows){
    return (rows||[]).map(row=>{
      const j=row.job||row,lots=row.lots||[],id=String(j.id);
      const lotText=lots.map(l=>`${l.item_name||''}｜${l.lot_no||l.qr_key||''}｜${fmtRounded(l.used_weight_kg)}kg`).join('　/　')||'使用原料の記録なし';
      return `<div style="padding:9px 0;border-top:1px solid #e2e8f0">
<div><b>${esc(j.source_item_name||'（品目未設定）')}</b><span class="small"> ${esc(j.work_date||'')}　使用${fmtRounded(j.input_weight_kg)}kg ／ 出来高${fmtRounded(j.output_weight_kg)}kg</span></div>
<div class="small">${esc(lotText)}</div>
<div class="row" style="margin-top:6px">
<button class="btn blue" style="padding:8px 12px" ${seikaEventAttrs('click','v1203EditJob',[id])}>この日報を修正</button>
<button class="btn danger" style="padding:8px 12px" ${seikaEventAttrs('click','v1203DeleteJob',[id])}>削除</button>
</div></div>`;
    }).join('');
  }

  /* 登録画面に既存の日報を読み込む */
  async function v1203EditJob(jobId){
    if(!v1203CanEdit())return alert('日報の修正は管理者・青果社員のみです');
    const row=v1203Jobs.get(String(jobId));
    if(!row)return alert('この日報を読み込めませんでした。画面を再読み込みしてください。');
    const j=row.job||row,lots=row.lots||[],outputs=row.outputs||[];
    if(!lots.length)return alert('使用原料の記録がない日報は修正できません。削除してから登録し直してください。');
    v1203EditId=String(jobId);
    await trimmingPage();
    v1115Trimming.lots=lots.map(l=>{
      const key=String(l.qr_key||l.lot_no||'');
      const full=(typeof v195TrimLots!=='undefined'&&Array.isArray(v195TrimLots))
        ?v195TrimLots.find(x=>String(x.qr_key||'')===key||String(x.lot_no||'')===String(l.lot_no||''))||null:null;
      const unitWeight=full&&typeof v195TrimUnitWeight==='function'?v195TrimUnitWeight(full):null;
      return {id:v1115Uuid(),qrKey:l.qr_key||key,lotNo:l.lot_no||'',itemName:l.item_name||j.source_item_name||'',
        itemKey:String(l.item_id??l.item_name??''),
        currentQty:full&&typeof v195TrimLotQty==='function'?v195TrimLotQty(full):0,
        currentKg:full&&typeof qrLotCurrentKg==='function'?qrLotCurrentKg(full):0,
        unitWeight:unitWeight>0?unitWeight:null,
        unit:full&&typeof qrLotUnit==='function'?qrLotUnit(full):'ケース',
        mode:'weight',amount:String(v1203Num(l.used_weight_kg)||'')};
    });
    v1115Trimming.outputs=outputs.map(o=>{
      return {id:v1115Uuid(),itemId:'',itemName:o.item_name||'',mode:'weight',
        weight:String(v1203Num(o.output_weight_kg)||''),qty:'',unitWeight:''};
    });
    if(typeof v196TrimWorkDate!=='undefined')v196TrimWorkDate=j.work_date||todayKey();
    if(typeof v196TrimNote!=='undefined')v196TrimNote=j.note||'';
    v1115RenderTrimming();
  }
  window.v1203EditJob=v1203EditJob;

  /* 修正中の見た目（案内と保存ボタンの文言、修正をやめる） */
  const v1203RenderTrimBase=v1115RenderTrimming;
  v1115RenderTrimming=function(...args){
    const r=v1203RenderTrimBase.apply(this,args);
    if(!v1203EditId)return r;
    try{
      const btn=document.querySelector('[data-seika-click-action="v1115SaveTrimming"]');
      if(btn)btn.textContent='確認して日報を修正';
      const first=document.querySelector('.notice');
      if(first){
        const box=document.createElement('div');
        box.className='notice';
        box.style.background='#fdf1dc';
        box.innerHTML='<b>登録済みの日報を修正しています。</b>'
          +'<div class="small">保存すると、いまの内容でこの日報が置き換わります。単価も作業日にあわせて計算し直します。在庫は変わりません。</div>'
          +`<button class="btn btn2" style="width:100%;margin-top:8px" ${seikaEventAttrs('click','v1203CancelEdit',[])}>修正をやめる</button>`;
        first.parentNode.insertBefore(box,first);
      }
    }catch(e){}
    return r;
  };
  window.v1115RenderTrimming=v1115RenderTrimming;

  function v1203CancelEdit(){
    const day=(v1203Jobs.get(v1203EditId)?.job||v1203Jobs.get(v1203EditId)||{}).work_date||todayKey();
    v1203EditId='';
    v1115TrimmingReset();
    if(typeof v196TrimNote!=='undefined')v196TrimNote='';
    v1200DailyReportPage(day);
  }
  window.v1203CancelEdit=v1203CancelEdit;

  /* 保存：修正中は create_trimming_job を replace_trimming_job_v1203 に差し替える */
  const v1203SaveBase=v1115SaveTrimming;
  v1115SaveTrimming=async function(...args){
    if(!v1203EditId)return v1203SaveBase.apply(this,args);
    const jobId=v1203EditId;
    const row=v1203Jobs.get(jobId),job=row&&(row.job||row)||{};
    const rpcBase=window.callRpc,confirmBase=window.confirm;
    let sent=false,ok=false;
    window.callRpc=async function(name,params){
      if(name!=='create_trimming_job')return rpcBase.apply(this,arguments);
      sent=true;
      const ans=await rpcBase('replace_trimming_job_v1203',{p_job_id:jobId,
        p_operation_id:params?.p_operation_id||'',p_work_date:params?.p_work_date||'',
        p_lots:params?.p_lots||[],p_outputs:params?.p_outputs||[],
        p_note:params?.p_note||'',p_user_name:params?.p_user_name||''});
      ok=!!(ans&&ans.ok);
      return ans;
    };
    window.confirm=function(msg){
      return confirmBase(String(msg||'').replace('日報を登録します。','登録済みの日報を修正します。')
        .replace('日報実績だけを保存します。','この日報を、いまの内容に置き換えます。'));
    };
    try{
      await v1203SaveBase.apply(this,args);
    }finally{
      window.callRpc=rpcBase;window.confirm=confirmBase;
    }
    if(!sent||!ok)return;
    const day=job.work_date||todayKey();
    v1203EditId='';
    v1115TrimmingReset();
    if(typeof v196TrimNote!=='undefined')v196TrimNote='';
    pageShell('日報の修正完了','修正内容を保存しました',
      '<div class="ok">日報を修正しました。単価も計算し直しています。在庫は変更していません。</div>'
      +`<button class="btn blue" style="width:100%" ${seikaEventAttrs('click','v1200DailyReportPage',[day])}>製造日報を見る</button>`
      +`<button class="btn btn2" style="width:100%;margin-top:8px" ${seikaEventAttrs('click','v1200ProductionHome',[])}>製造・歩留まりへ</button>`);
  };
  window.v1115SaveTrimming=v1115SaveTrimming;

  /* 削除 */
  async function v1203DeleteJob(jobId){
    if(!v1203CanEdit())return alert('日報の削除は管理者・青果社員のみです');
    const row=v1203Jobs.get(String(jobId)),j=row&&(row.job||row)||{};
    const day=j.work_date||todayKey();
    if(!confirm(`この日報を削除します。\n\n作業日：${day}\n品目：${j.source_item_name||''}\n使用原料：${fmtRounded(j.input_weight_kg)}kg\n出来高：${fmtRounded(j.output_weight_kg)}kg\n\n削除すると歩留まり・原価の集計から外れます。在庫は変わりません。`))return;
    try{
      const ans=await callRpc('delete_trimming_job_v1203',{p_job_id:String(jobId)});
      if(!ans||ans.ok===false)return alert(ans&&ans.message?ans.message:'削除できませんでした。');
      await v1200DailyReportPage(day);
    }catch(e){alert('削除できませんでした。\n'+(e&&e.message?e.message:e))}
  }
  window.v1203DeleteJob=v1203DeleteJob;

  /* 操作ガイドに追記 */
  try{
    if(typeof V198_GUIDE_SECTIONS!=='undefined'&&V198_GUIDE_SECTIONS.trimming){
      V198_GUIDE_SECTIONS.trimming.steps.push(
        '入力を間違えたときは、製造日報でその日を表示し、いちばん下の「日報の修正・削除」から直します。「この日報を修正」を押すと登録画面に内容が読み込まれるので、作業日・使用原料・使用量・出来高・メモを直して保存します。',
        '内容ごと不要になった日報は同じ場所の「削除」で消します。修正・削除しても通常在庫・QR在庫は変わりません。');
    }
  }catch(e){}
})();


/* ===== v1.204 QR在庫の合計kg表示 ===== */
(function(){
  function v1204Kg(lot){const v=qrLotCurrentKg(lot);return Number.isFinite(v)&&v>0?v:null}
  function v1204Room(lot){return String(lot&&lot.storage_location||'').trim()||'保管場所なし'}
  function v1204KgText(n){return fmtRounded(Math.round(Number(n||0)*10)/10)+'kg'}

  async function v1204FetchLots(selected){
    const q=typeof v1200QrItemQuery==='function'?v1200QrItemQuery(selected||''):'';
    const rows=await qrSelect('qr_lots',`select=*&active=eq.true&current_qty=gt.0${q}&limit=5000`);
    const list=Array.isArray(rows)?rows:[];
    return (selected&&typeof v1200QrFilterByGroup==='function')?v1200QrFilterByGroup(list,selected):list;
  }
  function v1204Sum(lots){
    const r={kg:0,lots:(lots||[]).length,unknown:0,rooms:new Map()};
    for(const l of lots||[]){
      const kg=v1204Kg(l);
      if(kg==null){r.unknown++;continue}
      r.kg+=kg;const k=v1204Room(l);r.rooms.set(k,(r.rooms.get(k)||0)+kg);
    }
    return r;
  }
  function v1204RoomHtml(rooms){
    const list=[...rooms.entries()].sort((a,b)=>b[1]-a[1]);
    if(!list.length)return '';
    return `<div class="grid" style="margin-top:8px">`
      +list.map(([name,kg])=>`<div class="box">${esc(name)}<b>${v1204KgText(kg)}</b></div>`).join('')+`</div>`;
  }

  /* ① QRロット一覧に合計kgカードを差し込む */
  const v1204ListBase=qrLotListPage;
  qrLotListPage=async function(...args){
    const r=await v1204ListBase.apply(this,args);
    const selected=String((typeof qrLotListState!=='undefined'&&qrLotListState.selectedItem)||args[0]||'').trim();
    try{
      const host=document.querySelector('.card');
      if(!host)return r;
      const box=document.createElement('div');
      box.className='card';
      box.id='v1204TotalCard';
      box.innerHTML='<b>在庫合計（kg）</b><div class="small" style="margin-top:4px">集計中…</div>';
      host.parentNode.insertBefore(box,host);
      const lots=await v1204FetchLots(selected);
      if(!document.getElementById('v1204TotalCard'))return r;
      const s=v1204Sum(lots);
      const label=selected?esc(v1200QrCanonName(selected)||selected):'QR在庫すべて';
      box.innerHTML=`<b>在庫合計（kg）</b>`
        +`<div class="small" style="margin-top:4px">${label}／在庫ありのロットを集計しています。表示件数の絞り込みには影響されません。</div>`
        +`<div class="grid" style="margin-top:8px"><div class="box" style="grid-column:1/-1">合計<b style="font-size:22px">${v1204KgText(s.kg)}</b></div></div>`
        +v1204RoomHtml(s.rooms)
        +`<div class="small" style="margin-top:6px">在庫ありロット ${s.lots}件`
        +(s.unknown?` ／ <span style="color:#b45309">量目未設定でkg換算できないロット ${s.unknown}件</span>`:'')+`</div>`
        +`<button class="btn homeBtnQrTotals" style="width:100%;margin-top:9px" ${seikaEventAttrs('click','qrTotalsPage',[])}>QR品目ごとの合計kgを見る</button>`;
    }catch(e){
      const box=document.getElementById('v1204TotalCard');
      if(box)box.innerHTML='<b>在庫合計（kg）</b><div class="small" style="margin-top:4px">合計を計算できませんでした。再読込してください。</div>';
    }
    return r;
  };
  window.qrLotListPage=qrLotListPage;

  /* ② QR品目ごとの合計kg一覧（別画面） */
  async function qrTotalsPage(){
    setScreen('qrTotalsPage',[]);
    pageShell('品目別在庫量','品目ごとの現在庫','<div class="card"><div class="notice">在庫を集計しています。</div></div>');
    try{
      const lots=await v1204FetchLots('');
      const groups=new Map();
      for(const l of lots){
        const name=(typeof v1200QrCanonName==='function'?v1200QrCanonName(l.item_name):String(l.item_name||''))||'（品名なし）';
        const g=groups.get(name)||{kg:0,lots:0,unknown:0,rooms:new Map()};
        g.lots++;
        const kg=v1204Kg(l);
        if(kg==null)g.unknown++;
        else{g.kg+=kg;const rm=v1204Room(l);g.rooms.set(rm,(g.rooms.get(rm)||0)+kg)}
        groups.set(name,g);
      }
      const rows=[...groups.entries()].sort((a,b)=>b[1].kg-a[1].kg);
      const roomNames=[...new Set(lots.map(v1204Room))].sort((a,b)=>a.localeCompare(b,'ja'));
      const total=v1204Sum(lots);
      const head=`<tr><th>品目</th><th style="text-align:right">合計kg</th>`
        +roomNames.map(n=>`<th style="text-align:right">${esc(n)}</th>`).join('')
        +`<th style="text-align:right">ロット</th></tr>`;
      const body=rows.map(([name,g])=>`<tr>`
        +`<td><a href="#" ${seikaEventAttrs('click','qrLotListPage',[name])}>${esc(name)}</a></td>`
        +`<td style="text-align:right"><b>${v1204KgText(g.kg)}</b></td>`
        +roomNames.map(n=>`<td style="text-align:right">${g.rooms.get(n)?v1204KgText(g.rooms.get(n)):'-'}</td>`).join('')
        +`<td style="text-align:right">${g.lots}件${g.unknown?`<br><span class="small" style="color:#b45309">kg不明${g.unknown}</span>`:''}</td></tr>`).join('')
        ||`<tr><td colspan="${roomNames.length+3}" class="small">在庫ありのQRロットはありません。</td></tr>`;
      const totalRow=rows.length?`<tr><td><b>合計</b></td><td style="text-align:right"><b>${v1204KgText(total.kg)}</b></td>`
        +roomNames.map(n=>`<td style="text-align:right">${total.rooms.get(n)?v1204KgText(total.rooms.get(n)):'-'}</td>`).join('')
        +`<td style="text-align:right">${total.lots}件</td></tr>`:'';
      pageShell('品目別在庫量',`${rows.length}品目 ／ 合計 ${v1204KgText(total.kg)}`,
        `<div class="card"><b>品目ごとの現在庫（在庫ありロットの合計）</b>`
        +`<div class="small" style="margin-top:4px">量目と現在残数からkg換算しています。量目が未設定のロットは「kg不明」として件数だけ表示します。</div>`
        +`<div class="row" style="margin-top:8px"><button class="btn blue" ${seikaEventAttrs('click','qrTotalsPage',[])}>最新に更新</button>`
        +`<button class="btn btn2" ${seikaEventAttrs('click','qrLotListPage',[])}>QRロット一覧へ</button></div></div>`
        +`<div class="card"><table class="table"><thead>${head}</thead><tbody>${body}${totalRow}</tbody></table>`
        +(total.unknown?`<div class="small" style="margin-top:6px;color:#b45309">kg換算できないロットが ${total.unknown}件あります。ロット編集で量目を入力すると合計に含まれます。</div>`:'')
        +`</div>`);
    }catch(e){
      pageShell('品目別在庫量','読み込みエラー',
        `<div class="err">${esc(typeof v161ErrorText==='function'?v161ErrorText(e):(e&&e.message||e))}</div>`
        +`<button class="btn blue" ${seikaEventAttrs('click','qrTotalsPage',[])}>再読み込み</button>`);
    }
  }
  window.qrTotalsPage=qrTotalsPage;

  /* ③ QR在庫管理ホームにボタンを追加 */
  const v1204HomeBase=qrHome;
  qrHome=async function(...args){
    const r=await v1204HomeBase.apply(this,args);
    try{
      const box=document.querySelector('.homePrimary');
      if(box&&!document.getElementById('v1204TotalsBtn')){
        const b=document.createElement('button');
        b.id='v1204TotalsBtn';
        b.type='button';
        b.className='btn homeBtnQrTotals';
        b.setAttribute('data-seika-click-action','qrTotalsPage');
        b.setAttribute('data-seika-click-args','%5B%5D');
        b.innerHTML='品目別在庫量<br><span style="font-size:15px;font-weight:800">QR品目の在庫をkgで一覧</span>';
        const list=box.querySelector('[data-seika-click-action="qrLotListPage"]');
        if(list&&list.parentNode)list.parentNode.insertBefore(b,list.nextSibling); else box.appendChild(b);
      }
    }catch(e){}
    return r;
  };
  window.qrHome=qrHome;

  /* ボタン色 */
  try{
    const st=document.createElement('style');
    st.textContent='.homeBtnQrTotals{background:linear-gradient(90deg,#b45309 0%,#f59e0b 52%,#fcd34d 100%) !important;color:#fff !important;text-shadow:0 1px 2px rgba(0,0,0,.25) !important;border-color:transparent !important;}';
    document.head.appendChild(st);
  }catch(e){}

  /* 操作ガイドに追記 */
  try{
    if(typeof V198_GUIDE_SECTIONS!=='undefined'){
      V198_GUIDE_SECTIONS.v1204QrTotals={title:'QR在庫の合計kgを確認する',where:'ホーム → QR在庫管理 → 品目別在庫量',
        steps:['QRロット一覧を開くと、いちばん上に選んだ品目の在庫合計kgと冷蔵庫別の内訳が出ます。',
               '「品目別在庫量」を開くと、QR品目すべての現在庫kgを一覧で比べられます。品名を押すとその品目のロット一覧へ移ります。',
               '量目が未設定のロットはkg換算できないため「kg不明」として件数だけ表示します。ロット編集で量目を入れると合計に入ります。'],
        check:'冷蔵庫別の内訳と現物が合っているか確認します。',
        caution:'在庫ありのロットだけを集計します。在庫なしのロットは含みません。'};
      if(typeof V198_ROLE_ADD!=='undefined'){
        for(const k of Object.keys(V198_ROLE_ADD)){
          if(Array.isArray(V198_ROLE_ADD[k])&&!V198_ROLE_ADD[k].includes('v1204QrTotals'))V198_ROLE_ADD[k].push('v1204QrTotals');
        }
      }
    }
  }catch(e){}
})();

/* ===== v1.199-c14 =====
   ① フレンキ・ヒェップの翻訳表示を日本語へ切り替えられるようにする（担当者ごとに端末へ記憶）
   ② 「戻る」の横に「ホーム」ボタンを常に出し、出庫などの後にすぐホームへ戻れるようにする */
(function(){
 const V1214_KEY=uid=>"seika_lang_ja_"+uid;
 const V1214_NAME={id:"Bahasa Indonesia",vi:"Tiếng Việt"};
 function v1214UserLang(){const uid=(db&&db.role==="worker")?db.userId:"";return(uid&&V202_USER_LANGS[uid])||""}
 function v1214JaOn(){try{return!!(db&&db.userId)&&localStorage.getItem(V1214_KEY(db.userId))==="1"}catch(e){return false}}
 const v1214LangBase=v202Lang;
 v202Lang=function(){if(currentScreen!=="login"&&v1214UserLang()&&v1214JaOn())return"";return v1214LangBase()};
 window.v1214ToggleLang=function(){if(!db||!db.userId||!v1214UserLang())return;
  try{if(v1214JaOn())localStorage.removeItem(V1214_KEY(db.userId));else localStorage.setItem(V1214_KEY(db.userId),"1")}catch(e){}
  document.documentElement.lang=v202Lang()||"ja";
  try{const r=renderCurrent();if(r&&typeof r.catch==="function")r.catch(()=>home())}catch(e){home()}};
 window.v1214GoHome=function(){const s=currentScreen;
  if((s==="qrCameraPage"||s==="qrCountCameraPage")&&typeof qrStopActiveCamera==="function")return qrStopActiveCamera().finally(()=>home());
  return home()};
 function v1214Button(action,label,cls){const b=document.createElement("button");b.type="button";b.className="headAction "+(cls||"");
  b.setAttribute("data-seika-click-action",action);b.setAttribute("data-seika-click-args","%5B%5D");b.textContent=label;return b}
 function v1214Decorate(){const bar=document.querySelector(".topBtns");if(!bar||!db||!db.user)return;
  const back=bar.querySelector('[data-seika-click-action="goBack"]');
  if(back&&!bar.querySelector('[data-seika-click-action="v1214GoHome"],[data-seika-click-action="home"]')){
   back.insertAdjacentElement("afterend",v1214Button("v1214GoHome","ホーム","primary v1214Home"))}
  bar.querySelector(".v1214Lang")?.remove();
  const lang=v1214UserLang();
  if(lang){const label=v1214JaOn()?V1214_NAME[lang]:"日本語";
   const b=v1214Button("v1214ToggleLang",label,"v1214Lang");bar.insertAdjacentElement("afterbegin",b)}}
 const v1214ShellBase=pageShell;
 pageShell=function(title,sub,body,opts={}){const r=v1214ShellBase(title,sub,body,opts);try{v1214Decorate()}catch(e){}return r};
 window.pageShell=pageShell;
 try{const st=document.createElement("style");
  st.textContent=".v1214Lang{background:#fff7e6 !important;color:#8a4b00 !important;border:1px solid #f0b75e !important;font-weight:700}"+
   ":root[data-theme=\"dark\"] .v1214Lang{background:#3a2a10 !important;color:#ffd08a !important}";
  document.head.appendChild(st)}catch(e){}
 try{if(typeof V198_GUIDE_SECTIONS!=="undefined"){
  V198_GUIDE_SECTIONS.v1214Nav={title:"ホームへ戻る・表示言語を切り替える",where:"画面右上のボタン",
   steps:["「戻る」は1つ前の画面へ、「ホーム」はいつでもホーム画面へ戻ります。出庫などを続けて終えたあとは「ホーム」を使うと早く戻れます。",
          "フレンキ・ヒェップでログインすると、右上に「日本語」ボタンが出ます。押すと日本語表示になり、もう一度押すと母国語の表示に戻ります。",
          "選んだ表示はその端末に記憶され、次回ログインしても同じ表示になります。"],
   check:"切り替え後に画面の文字が変わったか確認します。",
   caution:"カメラ画面から「ホーム」を押すと、カメラを止めてからホームへ戻ります。"};
  if(typeof V198_ROLE_ADD!=="undefined"){for(const k of Object.keys(V198_ROLE_ADD)){
   if(Array.isArray(V198_ROLE_ADD[k])&&!V198_ROLE_ADD[k].includes("v1214Nav"))V198_ROLE_ADD[k].push("v1214Nav")}}}}catch(e){}
})();

/* ===== v1.199-c15 =====
   ① 在庫入力：入力途中を端末へ自動保存し、白画面・再起動後も復元できるようにする
      登録直後の在庫報告コピーは、クラウド保存が終わってから開く（同時の重い処理を避ける）
   ② 在庫入力：1項目入力するたびの画面全体の再描画をやめ、その品目だけ更新する
   ③ QR関連の画面では「ホーム」をQR在庫管理のホームへ戻す
   ⑤ 在庫表：QRロットの取得を並行化・重複取得を抑止し、集計方式と所要時間を表示する */
(function(){
 /* ---------- ③ QRホーム ---------- */
 const V1215_QR_SCREENS=new Set(["v1102QualityPage","v1103QualityListPage","v1144QrOutboundHistoryPage","v123QrPage","v136SupplierQualityPage","v177ManualQrPage","v199QrExcelPage"]);
 function v1215IsQrScreen(n){n=String(n||"");return n!=="qrHome"&&(n.startsWith("qr")||V1215_QR_SCREENS.has(n))}
 window.v1214GoHome=function(){const s=currentScreen,go=()=>v1215IsQrScreen(s)&&typeof qrHome==="function"?qrHome():home();
  if((s==="qrCameraPage"||s==="qrCountCameraPage")&&typeof qrStopActiveCamera==="function")return qrStopActiveCamera().finally(go);
  return go()};
 try{if(typeof V138_ID==="object")V138_ID["QRホーム"]="Beranda QR";if(typeof V202_VI==="object")V202_VI["QRホーム"]="Trang chủ QR"}catch(e){}

 /* ---------- ① 下書きの自動保存 ---------- */
 const V1215_DRAFT_KEY=()=>"seika_inv_draft_v1215_"+(db&&db.userId||"");
 function v1215ReadDrafts(){try{return JSON.parse(localStorage.getItem(V1215_DRAFT_KEY())||"{}")||{}}catch(e){return{}}}
 function v1215WriteDrafts(o){try{localStorage.setItem(V1215_DRAFT_KEY(),JSON.stringify(o))}catch(e){}}
 function v1215ClearDraft(room){const o=v1215ReadDrafts();delete o[String(room)];v1215WriteDrafts(o)}
 let v1215DraftTimer=null,v1215Restoring=false,v1215Committing=false;
 function v1215CollectDraft(){if(currentScreen!=="inventory"||!Array.isArray(formState))return;
  const rows=[];for(const r of formState){const it=db.items.find(x=>x.id===r.itemId);
   if(!it||coldRoomForNormalItem(it)!==inventoryRoom||!inventoryStateHasInput(r))continue;
   rows.push({itemId:r.itemId,lines:JSON.parse(JSON.stringify(r.lines||[]))})}
  const sp={};document.querySelectorAll('input[id^="sp_"],input[id^="spmemo_"],textarea[id^="spmemo_"]').forEach(el=>{if(String(el.value||"").trim()!=="")sp[el.id]=el.value});
  const o=v1215ReadDrafts(),room=String(inventoryRoom);
  if(!rows.length&&!Object.keys(sp).length){delete o[room]}else o[room]={day:todayKey(),at:Date.now(),rows,sp};
  v1215WriteDrafts(o)}
 function v1215QueueDraft(){if(v1215Restoring||v1215Committing)return;clearTimeout(v1215DraftTimer);v1215DraftTimer=setTimeout(()=>{try{v1215CollectDraft()}catch(e){}},400)}
 window.v1215QueueDraft=v1215QueueDraft;
 document.addEventListener("input",e=>{const t=e.target;if(currentScreen==="inventory"&&t&&t.id&&/^sp(memo)?_/.test(t.id))v1215QueueDraft()},true);
 function v1215ApplySp(sp){for(const[id,v]of Object.entries(sp||{})){const el=document.getElementById(id);if(el&&String(el.value||"")==="")el.value=v}}
 function v1215TryRestore(){const d=v1215ReadDrafts()[String(inventoryRoom)];
  if(!d)return;if(d.day!==todayKey()){v1215ClearDraft(inventoryRoom);return}
  let n=0;v1215Restoring=true;
  try{for(const row of d.rows||[]){const r=formState.find(x=>x.itemId===row.itemId);if(!r)continue;
    if(!inventoryStateHasInput(r)){r.lines=row.lines;n++}}
   const sp=Object.keys(d.sp||{}).length;
   if(!n&&!sp)return;
   renderInventory(`登録前の入力（${n+sp}件）を復元しました。内容を確認して「まとめて登録」を押してください。`);
   v1215ApplySp(d.sp);
   const host=document.querySelector("main.wrap");
   if(host&&!document.getElementById("v1215DraftBar")){const bar=document.createElement("div");bar.id="v1215DraftBar";bar.className="card notice";
    bar.innerHTML='この冷蔵庫の登録前の入力を端末から復元しました。<button class="btn btn2" style="margin-left:8px;padding:6px 10px" data-seika-click-action="v1215DiscardDraft" data-seika-click-args="%5B%5D">復元した入力を消す</button>';
    host.insertAdjacentElement("afterbegin",bar)}}
  finally{v1215Restoring=false}}
 window.v1215DiscardDraft=function(){if(!confirm("復元した入力を消して、入力前の状態に戻しますか？"))return;v1215ClearDraft(inventoryRoom);inventory("",inventoryRoom)};
 const v1215InventoryBase=inventory;
 inventory=function(msg="",room=inventoryRoom){const r=v1215InventoryBase(msg,room);try{if(currentScreen==="inventory"&&!v1215Committing)v1215TryRestore()}catch(e){}return r};
 window.inventory=inventory;

 /* ---------- ② 1品目だけ更新 ---------- */
 function v1215CardTotal(r){return yen((r.lines||[]).reduce((a,l)=>inventoryLineHasInput(l)?a+(l.detail?detailSubtotal(l):Number(l.pack)*Number(l.cases)):a,0))}
 function v1215UpdateCard(index,lineIndex,field){
  const args=encodeURIComponent(JSON.stringify([index,lineIndex,field,{__seikaValue:true}]));
  const el=document.querySelector('[data-seika-change-args="'+CSS.escape(args)+'"]');if(!el)return false;
  const card=el.closest("section.card"),r=formState[index],it=r&&db.items.find(x=>x.id===r.itemId);if(!card||!r||!it)return false;
  const l=r.lines[lineIndex],kg=el.closest(".line")?.querySelector(".kg");
  if(kg&&l){const first=kg.firstChild;const txt="小計 "+(inventoryLineHasInput(l)?fmt(l.detail?detailSubtotal(l):Number(l.pack)*Number(l.cases))+"kg":"-")+" ";
   if(first&&first.nodeType===3)first.nodeValue=txt;else kg.insertAdjacentText("afterbegin",txt)}
  const hasInput=inventoryStateHasInput(r),total=v1215CardTotal(r),s=db.settings[it.id]||{min:null,max:null},st=hasInput?judge(total,s):"unset";
  const tot=card.querySelector(".total span:last-child");if(tot)tot.textContent=hasInput?fmt(total)+"kg":"- kg";
  const badge=card.querySelector(".itemHead > .badge");
  if(badge&&!r.fromToday){badge.className="badge "+(hasInput?st:"unset");badge.textContent=hasInput&&total===0?"在庫なし":hasInput?label(st):"未入力"}
  card.classList.toggle("entered",!!(r.fromToday||hasInput));return true}
 seikaInventoryField=function(index,lineIndex,field,value){const line=formState[index]?.lines?.[lineIndex];if(!line)return;line[field]=value;
  let ok=false;try{ok=v1215UpdateCard(index,lineIndex,field)}catch(e){ok=false}
  if(!ok)renderInventory(lastMessage);v1215QueueDraft()};
 window.seikaInventoryField=seikaInventoryField;
 for(const name of["seikaInventoryAddLine","seikaInventoryRemoveLine","moveInventoryItem"]){
  const base=window[name];if(typeof base!=="function")continue;
  const wrapped=function(...a){const r=base.apply(this,a);v1215QueueDraft();return r};
  window[name]=wrapped;try{if(name==="seikaInventoryAddLine")seikaInventoryAddLine=wrapped;if(name==="seikaInventoryRemoveLine")seikaInventoryRemoveLine=wrapped;if(name==="moveInventoryItem")moveInventoryItem=wrapped}catch(e){}}
 try{const st=document.createElement("style");
  st.textContent="";document.head.appendChild(st)}catch(e){}

 /* ---------- ① 登録後はクラウド保存を待ってから重い画面へ ---------- */
 let v1215CommitAt=0;
 const v1215CommitBase=submitInventoryCommit;
 submitInventoryCommit=async function(...a){const room=inventoryRoom,nr=(db.records||[]).length,ns=(db.specialRecords||[]).length;
  v1215CommitAt=Date.now();clearTimeout(v1215DraftTimer);v1215Committing=true;let r;
  try{r=await v1215CommitBase.apply(this,a)}finally{v1215Committing=false}
  if((db.records||[]).length>nr||(db.specialRecords||[]).length>ns)v1215ClearDraft(room);return r};
 window.submitInventoryCommit=submitInventoryCommit;
 async function v1215WaitSync(maxMs=20000){const t0=Date.now();await new Promise(r=>setTimeout(r,500));
  while(Date.now()-t0<maxMs){let busy=false;try{busy=v161SyncRunning||v161PendingCount()>0}catch(e){busy=false}if(!busy)return true;await new Promise(r=>setTimeout(r,400))}return false}
 for(const name of["lineCopyPage","orderCandidatePage"]){const base=window[name]||(name==="lineCopyPage"?lineCopyPage:orderCandidatePage);if(typeof base!=="function")continue;
  const wrapped=async function(...a){if(Date.now()-v1215CommitAt<8000){v1215CommitAt=0;
    pageShell("保存中","クラウドへ保存しています",'<div class="card"><b>登録した在庫をクラウドへ保存しています。</b><div class="small">保存が終わると自動で次の画面を開きます。</div></div>');
    await v1215WaitSync()}return base.apply(this,a)};
  window[name]=wrapped;if(name==="lineCopyPage")lineCopyPage=wrapped;else orderCandidatePage=wrapped}

 /* 異常値確認の文面が長くなりすぎないようにする */
 window.v1215Cap=function(lines,max=15){lines=lines||[];return lines.length<=max?lines.join("\n"):lines.slice(0,max).join("\n")+`\n…ほか ${lines.length-max}品`};
 v161ConfirmAnomaly=function(lines,title="入力値が大きく変化しています"){return!lines.length||confirm(`【要確認】${title}\n\n${v1215Cap(lines)}\n\n桁・単位・品目に間違いがないことを確認しましたか？`)};

 /* ---------- ⑤ 在庫表 ---------- */
 const V1215_TTL=45000,v1215Sel=new Map();
 const v1215SelBase=v163SelectAll;
 v163SelectAll=function(table,baseQuery,pageSize=1000){if(table!=="qr_lots")return v1215SelBase(table,baseQuery,pageSize);
  const k=table+"|"+baseQuery+"|"+pageSize,hit=v1215Sel.get(k);if(hit&&Date.now()-hit.at<V1215_TTL)return hit.p;
  const p=v1215SelBase(table,baseQuery,pageSize).catch(e=>{v1215Sel.delete(k);throw e});v1215Sel.set(k,{at:Date.now(),p});return p};
 window.v163SelectAll=v163SelectAll;
 const v1215RpcBase=callRpc;
 callRpc=async function(name,args){const r=await v1215RpcBase(name,args);if(!/^(list|get|qr_lot_daily_state|calculate|resolve)/.test(String(name||"")))v1215Sel.clear();return r};
 window.callRpc=callRpc;
 const v1215WeeklyBase=weeklyData;
 weeklyData=async function(...a){const t0=performance.now();try{v163SelectAll("qr_lots","select=*&order=qr_key.asc").catch(()=>{})}catch(e){}
  const r=await v1215WeeklyBase.apply(this,a);
  try{const sec=((performance.now()-t0)/1000).toFixed(1),mode=window.v1211LastError?"端末計算（サーバー集計が使えません）":"サーバー集計";
   const host=document.querySelector("main.wrap");if(host&&currentScreen==="weeklyData"&&!document.getElementById("v1215WeeklyInfo")){
    const d=document.createElement("div");d.id="v1215WeeklyInfo";d.className="small";d.style.cssText="margin:0 0 8px;color:#667";
    d.textContent=`集計方式：${mode} ／ 読み込み ${sec}秒`;host.insertAdjacentElement("afterbegin",d)}}catch(e){}
  return r};
 window.weeklyData=weeklyData;

 /* 画面ごとのクラス付け・ホームボタン名 */
 const v1215ShellBase=pageShell;
 pageShell=function(title,sub,body,opts={}){const r=v1215ShellBase(title,sub,body,opts);
  try{document.querySelector(".appShell")?.classList.toggle("v1215Inv",title==="在庫入力");
   const hb=document.querySelector('.topBtns [data-seika-click-action="v1214GoHome"]');
   if(hb)hb.textContent=v1215IsQrScreen(currentScreen)?(typeof v202T==="function"?v202T("QRホーム"):"QRホーム"):(typeof v202T==="function"?v202T("ホーム"):"ホーム")}catch(e){}
  return r};
 window.pageShell=pageShell;

 try{if(typeof V198_GUIDE_SECTIONS!=="undefined"&&V198_GUIDE_SECTIONS.v1214Nav){
  V198_GUIDE_SECTIONS.v1214Nav.steps.splice(1,0,"QR入庫・出庫・品質評価などQR関連の画面では「QRホーム」になり、QR在庫管理の画面へ戻ります。");
  V198_GUIDE_SECTIONS.v1215Draft={title:"在庫入力の途中保存",where:"ホーム → 在庫入力",
   steps:["在庫入力は入力するたびに端末へ自動で下書き保存されます。","途中で画面が白くなったり閉じたりしても、同じ日に同じ冷蔵庫を開くと入力が復元されます。","「まとめて登録」が終わると下書きは消えます。"],
   check:"復元のお知らせが出たら、数字を確認してから登録します。",caution:"下書きはその端末にだけ保存されます。別の端末には引き継がれません。"};
  if(typeof V198_ROLE_ADD!=="undefined")for(const k of Object.keys(V198_ROLE_ADD)){const a=V198_ROLE_ADD[k];if(Array.isArray(a)&&a.includes("v1214Nav")&&!a.includes("v1215Draft"))a.push("v1215Draft")}}}catch(e){}
})();


/* ===== v1.199-c16 在庫入力の白画面・在庫表のサーバー集計 =====
   ① 在庫入力：最新記録・前回入力の検索を1回の描画で1回だけにする
      （品目ごとに全記録を並べ替えていたため、記録が増えるほど遅くなっていた）
   ② 在庫表：サーバー集計に失敗しても端末計算へ自動で切り替えない。
      理由を表示し、「もう一度読み込む」と「この端末で計算する」を選べるようにする。 */
(function(){

 /* 日付キー（日本時間の YYYY-MM-DD）を計算で求める。
    toLocaleDateString(timeZone指定) は iPhone で非常に遅く、在庫表の大半の時間を占めていた。 */
 if(typeof ymdKey==="function"){
   const v1216YmdBase=ymdKey;
   const pad=n=>(n<10?"0":"")+n;
   ymdKey=function(d){
     const ms=(d instanceof Date)?d.getTime():new Date(d).getTime();
     if(!isFinite(ms))return v1216YmdBase(d);
     const j=new Date(ms+32400000),y=j.getUTCFullYear();
     if(y<1000||y>9999)return v1216YmdBase(d);
     return y+"-"+pad(j.getUTCMonth()+1)+"-"+pad(j.getUTCDate());
   };
   window.ymdKey=ymdKey;
   window.v1216YmdBase=v1216YmdBase;
 }
 let v1216Idx=null;
 function v1216Index(){
   const src=db.records||[];
   if(v1216Idx&&v1216Idx.src===src&&v1216Idx.len===src.length)return v1216Idx;
   const today=todayKey();
   const sorted=src.slice().sort((a,b)=>new Date(a.createdAt||0)-new Date(b.createdAt||0));
   const all={},tod={},prev={};
   for(const r of sorted){
     all[r.itemId]=r;
     if(r.createdAt){ if(ymdKey(new Date(r.createdAt))===today)tod[r.itemId]=r; else prev[r.itemId]=r; }
   }
   v1216Idx={src,len:src.length,all,tod,prev};
   setTimeout(()=>{v1216Idx=null},0);
   return v1216Idx;
 }
 if(typeof todayLatestMap==="function"){
   todayLatestMap=function(){return Object.assign({},v1216Index().tod)};
   window.todayLatestMap=todayLatestMap;
 }
 if(typeof previousRecordBeforeToday==="function"){
   previousRecordBeforeToday=function(itemId){return v1216Index().prev[itemId]||null};
   window.previousRecordBeforeToday=previousRecordBeforeToday;
 }
 if(typeof latestRecord==="function"){
   latestRecord=function(itemId){return v1216Index().all[itemId]||null};
   window.latestRecord=latestRecord;
 }

 window.v1216ServerFail="";
 window.v1216AllowClient=false;
 window.v1216RetryWeekly=function(){
   if(typeof window.v1209ClearQrCache==="function")window.v1209ClearQrCache();
   window.v1216ServerFail="";window.v1211LastError="";
   weeklyData();
 };
 window.v1216ClientWeekly=async function(){
   if(!confirm("この端末で在庫表を計算します。\n履歴が多いため、表示まで時間がかかります。よろしいですか？"))return;
   window.v1216AllowClient=true;
   try{ await weeklyData(); }finally{ window.v1216AllowClient=false; }
 };
 const v1216WeeklyBase=weeklyData;
 weeklyData=async function(...a){
   window.v1216ServerFail="";
   const client=window.v1216AllowClient;
   const r=await v1216WeeklyBase.apply(this,a);
   try{
     if(currentScreen!=="weeklyData")return r;
     const info=document.getElementById("v1215WeeklyInfo");
     if(info&&client&&window.v1211LastError)info.textContent=info.textContent.replace("端末計算（サーバー集計が使えません）","端末計算（手動で選択）");
     if(info&&!client&&!window.v1211LastError&&window.v1216RpcSec&&!info.textContent.includes("サーバー応答"))
       info.textContent+=` （うちサーバー応答 ${window.v1216RpcSec}秒）`;
     window.v1216RpcSec="";
     if(!window.v1216ServerFail)return r;
     info?.remove();
     const box=document.querySelector("main.wrap .err");
     if(box){
       box.className="card";
       box.style.cssText="border:2px solid #d97706;background:#fff7e6";
       box.innerHTML='<b>在庫表のQR在庫をサーバーで集計できませんでした。</b>'
         +'<div class="small" style="margin:6px 0">理由：'+esc(window.v1216ServerFail)+'</div>'
         +'<div class="small">通信が不安定なときは「もう一度読み込む」を押してください。続く場合は管理者へ連絡してください。</div>'
         +'<button class="btn" style="width:100%;margin-top:10px" '+seikaEventAttrs("click","v1216RetryWeekly",[])+'>もう一度読み込む</button>'
         +'<button class="btn btn2" style="width:100%;margin-top:8px" '+seikaEventAttrs("click","v1216ClientWeekly",[])+'>この端末で計算する（時間がかかります）</button>';
     }
   }catch(e){}
   return r;
 };
 window.weeklyData=weeklyData;
})();


/* ===== v1.199-c18 仕入先・単協名の「非表示」をクラウドへ保存 =====
   c8 の非表示リストは端末内にしか保存されず、クラウド読込で消える・他の端末に反映されない状態だった。
   保存データに含め、入庫画面の入力欄の下から候補の編集画面を開けるようにする。 */
(function(){
 const V1218_KEYS=["qrSupplierHidden","qrCooperativeHidden"];
 if(typeof cloudPayloadBase==="function"){
   const base=cloudPayloadBase;
   cloudPayloadBase=function(...a){
     const out=base.apply(this,a);
     for(const k of V1218_KEYS)out[k]=Array.isArray(db[k])?db[k]:[];
     return out;
   };
   window.cloudPayloadBase=cloudPayloadBase;
 }
 if(typeof window.v188RolePayload==="function"){
   const base=window.v188RolePayload;
   const wrapped=function(payload,role=db?.role){
     const out=base(payload,role);
     if(role==="admin"||role==="worker")
       for(const k of V1218_KEYS)if(Object.prototype.hasOwnProperty.call(payload||{},k))out[k]=v188Clone(payload[k]);
     return out;
   };
   window.v188RolePayload=wrapped;
   try{v188RolePayload=wrapped}catch(e){}
 }
 function v1218Merge(local,remote){
   const seen=new Set,out=[];
   for(const v of [...(Array.isArray(remote)?remote:[]),...(Array.isArray(local)?local:[])]){
     const k=qrNormalizeName(v);if(!k||seen.has(k))continue;seen.add(k);out.push(v);
   }
   return out;
 }
 const shell=pageShell;
 pageShell=function(...a){
   const r=shell.apply(this,a);
   setTimeout(()=>{try{
     if(!canQrOperate()||document.getElementById("v1218CandLink"))return;
     const sup=document.getElementById("qrSupplier"),coop=document.getElementById("qrCooperativeName");
     if(!sup||!coop)return;
     const anchor=document.getElementById("qrCooperativeSuggestions")||coop;
     anchor.insertAdjacentHTML("afterend",
       `<div id="v1218CandLink" class="small" style="margin:6px 0 10px">間違った仕入先・単協名が候補に出るときは
        <button type="button" class="btn btn2" style="padding:6px 12px;margin-left:4px" ${seikaEventAttrs("click","v1208CandidatePage",["supplier",""])}>候補を編集</button></div>`);
   }catch(e){}},0);
   return r;
 };
 window.pageShell=pageShell;


/* v1.199-c19 月末棚卸しの状態保護・棚卸し履歴・3か月経過分の削除 */
 const V1205_CLOSED=new Set(['completed','confirmed','test_confirmed','reversed','cancelled']);
 const V1205_PURGE_RPC='seika_purge_old_inventory_counts_v1205';
 function v1205Repair(s){
  if(!s||typeof s!=='object')return false;
  const st=String(s.status||'');
  if(v188Session(s)&&s.v188ConfirmedAt&&st!=='completed'){s.status='completed';return true}
  if(v177Session(s)&&!v188Session(s)&&v177Completed(s)&&!V1205_CLOSED.has(st)){s.status='completed';return true}
  return false;
 }
 const normalizeBase=v124NormalizeSession;
 v124NormalizeSession=function(s){if(v177Session(s)){v1205Repair(s);return s}return normalizeBase(s)};
 window.v124NormalizeSession=v124NormalizeSession;
 const deriveBase=v124DeriveStatus;
 v124DeriveStatus=function(s){if(v177Session(s)){v1205Repair(s);return s}return deriveBase(s)};
 window.v124DeriveStatus=v124DeriveStatus;

 function v1205ClosedAt(s){
  if(!s)return null;
  if(v188Session(s))return s.v188ConfirmedAt||null;
  if(v177Session(s)&&v177Completed(s))return s.v177CompletedAt||s.v177AppliedAt||s.updatedAt||null;
  if(V1205_CLOSED.has(String(s.status||'')))return s.v186ConfirmedAt||s.confirmedAt||s.updatedAt||s.startedAt||null;
  return null;
 }
 function v1205ExpireAt(s){
  const at=v1205ClosedAt(s);if(!at)return null;
  const d=new Date(at);if(isNaN(d))return null;
  d.setMonth(d.getMonth()+3);return d;
 }
 function v1205Expired(s){const d=v1205ExpireAt(s);return Boolean(d&&d.getTime()<=Date.now())}
 function v1205PruneLocal(){
  const list=countSessions();let changed=false;
  list.forEach(s=>{if(v1205Repair(s))changed=true});
  const keep=list.filter(s=>!v1205Expired(s));
  if(keep.length!==list.length){db.inventoryCounts.sessions=keep;changed=true}
  if(changed&&typeof v188PersistDb==='function')v188PersistDb();
  return changed;
 }
 let v1205Purged=false;
 async function v1205PurgeServer(){
  if(v1205Purged||!canAdmin())return;
  if(!countSessions().some(v1205Expired))return;
  v1205Purged=true;
  try{const r=await callRpc(V1205_PURGE_RPC,{p_id:STATE_ID});if(r?.deleted>0)await loadCloud()}catch(e){}
 }
 const loadBase=loadCloud;
 async function v1218LoadCandidates(...a){
  const keep={};for(const k of V1218_KEYS)keep[k]=Array.isArray(db?.[k])?db[k].slice():[];
  const r=await loadBase.apply(this,a);
  try{for(const k of V1218_KEYS){const remote=Array.isArray(db[k])?db[k]:[];db[k]=remote.length?remote:v1218Merge(keep[k],[])}}catch(e){}
  return r;
 }
 loadCloud=async function(...a){
  const r=await v1218LoadCandidates.apply(this,a);
  try{v1205PruneLocal()}catch(e){}
  return r;
 };
 window.loadCloud=loadCloud;

 const homeBase=v188Home;
 function v1205Home(msg=''){
  try{v1205PruneLocal()}catch(e){}
  const r=homeBase(msg);
  v1205PurgeServer();
  return r;
 }
 window.v188Home=v1205Home;window.inventoryCountHome=v1205Home;inventoryCountHome=v1205Home;

 function v1205Ymd(d){return d?`${d.getFullYear()}/${d.getMonth()+1}/${d.getDate()}`:'－'}
 window.v1205CountArchivePage=function(msg=''){
  setScreen('v1205CountArchivePage',[msg]);if(!v177Allowed())return home();
  v1205PruneLocal();
  const sessions=countSessions();
  const done=sessions.filter(s=>v188Session(s)&&v188Confirmed(s)).sort((a,b)=>String(b.targetMonth||'').localeCompare(String(a.targetMonth||''))||String(a.room||'').localeCompare(String(b.room||'')));
  const legacy=sessions.filter(s=>!v188Session(s)).sort((a,b)=>new Date(b.updatedAt||b.startedAt||0)-new Date(a.updatedAt||a.startedAt||0));
  const row=s=>`<div class="card"><div class="itemHead"><div><b>${esc(s.countNo||'')}</b><div class="small">${esc(s.roomLabel||'')} / ${esc(v188MonthLabel(s.targetMonth))}末<br>確定：${esc(s.v188ConfirmedAt?dt(s.v188ConfirmedAt):'－')} / 削除予定：${esc(v1205Ymd(v1205ExpireAt(s)))}</div></div><span class="badge normal">確定済み</span></div><div class="mini" style="margin-top:8px"><button class="btn btn2" ${seikaEventAttrs('click','v1205CountArchiveDetail',[s.id])}>開く</button><button class="btn orange" ${seikaEventAttrs('click','v188DownloadExcel',[s.id])}>Excelを出力</button></div></div>`;
  pageShell('棚卸し履歴',`${esc(v119RoleLabel())} / v1.199`,
   `${okHtml(msg)}<div class="card notice"><b>確定済みの棚卸し</b><div class="small">確定日から3か月を過ぎると自動で削除されます。残しておきたい場合は、削除予定日より前にExcelを出力して文書管理へ保存してください。在庫へ反映済みの棚卸し調整は、削除後も在庫履歴に残ります。</div></div>
${done.map(row).join('')||'<div class="card"><div class="small">確定済みの棚卸しはありません。</div></div>'}
${legacy.length?`<details class="card"><summary><b>旧棚卸し（${legacy.length}件）</b></summary><div style="margin-top:10px">${legacy.map(v186LegacyCard).join('')}</div></details>`:''}
<button class="btn btn2" style="width:100%;margin-top:10px" ${seikaEventAttrs('click','inventoryCountHome',[])}>棚卸しモードへ戻る</button>`);
 };
 window.v1205CountArchiveDetail=function(id){
  const s=countSession(id);if(!s)return window.v1205CountArchivePage('棚卸しが見つかりません。');
  setScreen('v1205CountArchiveDetail',[id]);
  pageShell(esc(s.countNo||'棚卸し'),`${esc(v119RoleLabel())} / v1.199`,`${v188SessionCard(s)}<div class="small" style="margin-top:6px">削除予定：${esc(v1205Ymd(v1205ExpireAt(s)))}</div><button class="btn btn2" style="width:100%;margin-top:10px" ${seikaEventAttrs('click','v1205CountArchivePage',[])}>棚卸し履歴へ戻る</button>`);
 };
})();


/* v1.199-c21 月末棚卸しExcel「棚卸表」：ExcelJSで直接作成・単位と重量の算出を修正 */
(function(){
 const FONT='Yu Gothic';
 const thin={style:'thin',color:{argb:'FF000000'}};
 const ALL={top:thin,bottom:thin,left:thin,right:thin};
 const INPUT={type:'pattern',pattern:'solid',fgColor:{argb:'FFFFF7CC'}};
 const GRAY={type:'pattern',pattern:'solid',fgColor:{argb:'FFC0C0C0'}};
 const num=v=>{if(v===null||v===undefined||v==='')return null;const n=Number(v);return Number.isFinite(n)?n:null};
 const r2=n=>Math.round(n*100)/100;
 const fmtN=n=>Number(n).toLocaleString('ja-JP',{maximumFractionDigits:2});
 function mdLabel(key){const m=/^(\d{4})-(\d{2})-(\d{2})$/.exec(String(key||''));return m?`${Number(m[2])}/${m[3]}`:''}
 function asOfLabel(key){const m=/^(\d{4})-(\d{2})-(\d{2})$/.exec(String(key||''));return m?`${Number(m[2])}月${Number(m[3])}日時点`:''}
 function packFromName(name){const m=/(\d+(?:\.\d+)?)\s*(?:kg|ｋｇ|㎏|KG)/i.exec(String(name||''));return m?Number(m[1]):null}
 function gradeText(memo){const t=String(memo||'').replace(/\[[^\]]*\]?/g,'').replace(/【[^】]*】?/g,'').replace(/\s+/g,' ').trim();return t||'ー'}
 async function lotInfo(session){
  const map=new Map();
  if(!(session.qrLines||[]).length)return map;
  try{const lots=await v163SelectAll('qr_lots','select=qr_key,cooperative_name,memo,pack_weight,container_type,unit,total_weight,received_qty&order=qr_key.asc');for(const lot of lots||[]){const k=String(lot?.qr_key||'').trim();if(k&&!map.has(k))map.set(k,lot)}}catch(e){}
  return map;
 }
 function qrRows(session,lots){
  const rows=[];
  for(const line of v188SectionLines(session,'qr')){
   const entry=v188Entry(session,line.lineId);if(entry.included===false)continue;
   const actual=v188Actual(session,line.lineId);if(actual===null||actual<=0)continue;
   const lot=lots.get(String(line.qrKey||'').trim())||{};
   const container=String(line.containerType||lot.container_type||'').trim();
   const large=qrIsLargeContainer(container);
   const unit=large?'基':'ケース';
   const pack=v192PackKg({packWeight:(line.packWeight!==''&&line.packWeight!==null&&line.packWeight!==undefined)?line.packWeight:lot.pack_weight});
   let weight=null;
   if(large){
    const tw=num(line.snapshotTotalWeight)??num(lot.total_weight),rq=num(line.snapshotInitialQty)??num(lot.received_qty);
    if(tw!==null&&rq)weight=r2(actual*tw/rq);
    else{const m=num(line.actualWeightKg);if(m!==null)weight=m}
   }else if(pack){weight=r2(actual*pack)}
   else{const m=num(line.actualWeightKg);if(m!==null)weight=m}
   const spec=`${container}${pack?` ${fmtN(pack)}kg`:''} (${unit}) / ${gradeText(lot.memo)}`.trim();
   rows.push({item:line.itemName||'',date:line.receivedDate||'',received:mdLabel(line.receivedDate),origin:line.origin||'',supplier:line.supplier||'',coop:lot.cooperative_name||'',spec,qty:actual,unit,weight});
  }
  const order=[],groups=new Map();
  for(const r of rows){if(!groups.has(r.item)){groups.set(r.item,[]);order.push(r.item)}groups.get(r.item).push(r)}
  return order.map(item=>({item,rows:groups.get(item).sort((a,b)=>String(a.date).localeCompare(String(b.date)))}));
 }
 function caseText(lines){
  const parts=[];
  for(const l of lines||[]){
   if(!l||l.stocktakeAdjustment||l.adjustment)continue;
   if(l.detail){const s=num(l.subtotal)??num(detailSubtotal(l));if(s)parts.push(`${l.spec||''}${l.origin?'/'+l.origin:''} ${fmtN(s)}kg`.trim());continue}
   const p=num(l.pack),c=num(l.cases);
   if(p&&c)parts.push(p===1?`${fmtN(c)}kg`:`${fmtN(p)}kg ${fmtN(c)}ケース`);
  }
  return parts.join('、');
 }
 function sumLines(lines){let t=0;for(const l of lines||[]){if(!l||l.stocktakeAdjustment||l.adjustment)continue;t+=l.detail?(num(l.subtotal)??num(detailSubtotal(l))??0):((num(l.pack)||0)*(num(l.cases)||0))}return r2(t)}
 function normalQtyText(session,line,actual){
  const recs=v188RecordsUntil(session.asOfKey).filter(r=>r&&r.itemId===line.itemId&&r.kind!=='棚卸し調整').sort((a,b)=>new Date(b.createdAt||0)-new Date(a.createdAt||0));
  const rec=recs[0];
  if(rec){const text=caseText(rec.lines);if(text&&Math.abs(sumLines(rec.lines)-actual)<0.01)return text}
  return `${fmtN(actual)}kg`;
 }
 function normalRows(session){
  const rows=[];
  for(const line of v188SectionLines(session,'normal')){
   const entry=v188Entry(session,line.lineId);if(entry.included===false)continue;
   const actual=v188Actual(session,line.lineId);if(actual===null||actual<=0)continue;
   if(line.type==='normal'){
    rows.push({item:line.itemName||'',spec:'kg',qtyText:normalQtyText(session,line,actual),weight:r2(actual)});
   }else{
    const unit=line.unit||'ケース';
    const pack=num(line.snapshotPackKg)||packFromName(line.itemName);
    const isKg=String(unit).toLowerCase()==='kg';
    rows.push({item:line.itemName||'',spec:isKg?'kg':`${unit}${pack?` ${fmtN(pack)}kg`:''}`,qtyText:isKg?`${fmtN(actual)}kg`:(pack?`${fmtN(pack)}kg ${fmtN(actual)}${unit}`:`${fmtN(actual)}${unit}`),weight:isKg?r2(actual):(pack?r2(actual*pack):null)});
   }
  }
  return rows;
 }
 function buildSheet(wb,session,groups,normals){
  const ws=wb.addWorksheet('棚卸表',{pageSetup:{paperSize:9,orientation:'landscape',fitToPage:true,fitToWidth:1,fitToHeight:0,horizontalCentered:true,printTitlesRow:'5:5',margins:{left:0.4,right:0.4,top:0.5,bottom:0.5,header:0.3,footer:0.3}},headerFooter:{oddFooter:'&C&P / &N'}});
  [33,10,15,26,24,38,14,14,11,15,13].forEach((w,i)=>{ws.getColumn(i+1).width=w});
  const f=(sz=11,bold=false)=>({name:FONT,size:sz,bold});
  const set=(addr,value,o={})=>{const c=ws.getCell(addr);c.value=value;c.font=o.font||f();if(o.border)c.border=o.border;if(o.fill)c.fill=o.fill;if(o.numFmt)c.numFmt=o.numFmt;c.alignment={vertical:'middle',horizontal:o.h||'center',...(o.wrap?{wrapText:true}:{})};return c};
  ws.mergeCells('A1:D1');ws.mergeCells('H1:J1');ws.mergeCells('A2:D2');ws.mergeCells('A3:D3');
  set('A1','棚卸表（原料/副原料/加工品/製品/資材）',{font:f(16,true)});
  set('H1','石岡センター',{font:f(12),border:{bottom:thin}});
  set('A2',asOfLabel(session.asOfKey),{font:f(12)});
  set('A3',`石岡青果 ${session.roomLabel||''}在庫`,{font:f(12)});
  set('I2','氏名',{border:{top:thin,bottom:thin}});set('J2','',{border:{top:thin,bottom:thin}});set('K2','',{border:{top:thin,bottom:thin}});
  set('I3','氏名',{border:{bottom:thin}});set('J3','',{border:{bottom:thin}});set('K3','',{border:{bottom:thin}});
  ['品名','仕入日','産地','仕入先','単協名','荷姿・規格','数量','重量','単価','配送費','合計額'].forEach((h,i)=>set(`${String.fromCharCode(65+i)}5`,h,{font:f(11,true),border:ALL}));
  for(let i=1;i<=5;i++)ws.getRow(i).height=20.1;
  const subtotals=[];let r=6;
  const money=()=>{set(`I${r}`,0,{border:ALL,h:'right',numFmt:'#,##0.00',fill:INPUT});set(`J${r}`,0,{border:ALL,h:'right',numFmt:'#,##0',fill:INPUT});set(`K${r}`,{formula:`IF(H${r}="",0,H${r}*I${r})+J${r}`},{border:ALL,h:'right',numFmt:'#,##0'})};
  const row=(o,first,isNormal)=>{
   set(`A${r}`,first?o.item:'',{border:{left:thin,right:thin,...(first?{top:thin}:{})}});
   set(`B${r}`,isNormal?'':o.received,{border:ALL});
   set(`C${r}`,o.origin||'',{border:ALL,...(isNormal?{fill:INPUT}:{})});
   set(`D${r}`,o.supplier||'',{border:ALL,...(isNormal?{fill:INPUT}:{})});
   set(`E${r}`,o.coop||'',{border:ALL});
   set(`F${r}`,o.spec||'',{border:ALL,h:'left'});
   if(isNormal)set(`G${r}`,o.qtyText||'',{border:ALL,h:'right'});
   else set(`G${r}`,o.qty,{border:ALL,h:'right',numFmt:`#,##0.##"${o.unit}"`});
   if(o.weight===null||o.weight===undefined)set(`H${r}`,null,{border:ALL,h:'right'});
   else set(`H${r}`,o.weight,{border:ALL,h:'right',numFmt:'#,##0.00"kg"'});
   money();ws.getRow(r).height=20.1;r++;
  };
  const subtotal=(start,label)=>{
   ws.getCell(`A${r}`).border={left:thin,right:thin,bottom:thin};
   set(`J${r}`,label,{border:ALL,fill:GRAY});
   set(`K${r}`,{formula:`SUM(K${start}:K${r-1})`},{border:ALL,fill:GRAY,h:'right',numFmt:'#,##0'});
   ws.getRow(r).height=20.1;subtotals.push(`K${r}`);r+=2;
  };
  for(const g of groups){const start=r;g.rows.forEach((o,i)=>row(o,i===0,false));subtotal(start,'小計')}
  if(normals.length){
   set(`A${r}`,'【通常在庫】',{font:f(11,true),h:'left'});r++;
   const start=r;for(const o of normals)row(o,true,true);subtotal(start,'通常在庫 小計');
  }
  r--;
  set(`J${r}`,'総合計',{font:f(11,true),border:ALL});
  set(`K${r}`,{formula:subtotals.length?subtotals.join('+'):'0'},{font:f(11,true),border:ALL,h:'right',numFmt:'#,##0'});
  return ws;
 }
 async function v1207DownloadExcel(id){
  const session=countSession(id);if(!session||!v188Session(session))return v186DownloadExcel(id);
  if(typeof ExcelJS==='undefined')return alert('Excel作成ライブラリを読み込めませんでした。再読込してからもう一度お試しください。');
  v161ShowProcessing('棚卸表を作成しています');
  try{
   const lots=await lotInfo(session);
   const wb=new ExcelJS.Workbook();
   buildSheet(wb,session,qrRows(session,lots),normalRows(session));
   const fileName=`棚卸表_${String(session.targetMonth||'').replace('-','')}_${String(session.roomLabel||'冷蔵庫').replace(/[\\/:*?"<>|]/g,'_')}.xlsx`;
   const buffer=await wb.xlsx.writeBuffer(),blob=new Blob([buffer],{type:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'}),url=URL.createObjectURL(blob),a=document.createElement('a');
   a.href=url;a.download=fileName;document.body.appendChild(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),2000);
  }catch(error){alert(`棚卸表を作成できませんでした。\n${v161ErrorText(error)}`);return}
  finally{v161HideProcessing()}
  const msg='棚卸表を出力しました。単価（円/kg）と配送費を入力すると、合計額・小計・総合計が計算されます。';
  return currentScreen==='v1205CountArchivePage'?window.v1205CountArchivePage(msg):inventoryCountHome(msg);
 }
 window.v1207DownloadExcel=v1207DownloadExcel;window.v1206DownloadExcel=v1207DownloadExcel;
 downloadInventoryCountExcel=v1207DownloadExcel;window.downloadInventoryCountExcel=v1207DownloadExcel;
 v188DownloadExcel=v1207DownloadExcel;window.v188DownloadExcel=v1207DownloadExcel;
 v192DownloadExcel=v1207DownloadExcel;window.v192DownloadExcel=v1207DownloadExcel;
})();

/* ===== v1.199-c22 保存エラーの常時表示・エラー記録・履歴保存漏れの点検 ===== */
(function(){
 const LOG_KEY='seika_error_log_v1',CHECK_KEY='seika_history_check_v1',MAX=80;
 const TABLES=[['records','inventory_records','在庫入力'],['wasteRecords','waste_records','廃棄'],['movements','inventory_movements','在庫修正']];
 const bar={sync:'',hist:'',missing:null};
 let pendingTimer=null;
 const jstDay=()=>new Date().toLocaleDateString('sv-SE',{timeZone:'Asia/Tokyo'});
 const errText=e=>String((e&&e.message)||e||'');

 function readLog(){try{return JSON.parse(localStorage.getItem(LOG_KEY)||'[]')}catch(e){return[]}}
 function logError(kind,detail){
  const list=readLog();
  list.unshift({at:new Date().toISOString(),kind:String(kind),detail:errText(detail).slice(0,800),
   screen:typeof currentScreen!=='undefined'?String(currentScreen||''):'',user:(db&&db.user)||''});
  try{localStorage.setItem(LOG_KEY,JSON.stringify(list.slice(0,MAX)))}catch(e){}
 }
 window.seikaLogError=logError;
 window.addEventListener('error',e=>logError('画面エラー',`${e.message||''} (行${e.lineno||'-'})`));
 window.addEventListener('unhandledrejection',e=>logError('処理エラー',e.reason));

 function ensureStyle(){
  if(document.getElementById('c22Style'))return;
  const s=document.createElement('style');s.id='c22Style';
  s.textContent='#c22Bar{position:fixed;left:8px;right:8px;bottom:calc(8px + env(safe-area-inset-bottom));z-index:9999;background:#b91c1c;color:#fff;border-radius:14px;padding:12px 14px;box-shadow:0 6px 20px rgba(0,0,0,.28);font-weight:700;font-size:.95rem;display:flex;gap:10px;align-items:center}#c22Bar .c22Msg{flex:1;line-height:1.45}#c22Bar button{background:#fff;color:#991b1b;border:0;border-radius:10px;padding:9px 14px;font-weight:800;font-size:.95rem}#c22Bar.ok{background:#15803d}';
  document.head.appendChild(s);
 }
 function renderBar(){
  if(!document.body)return;
  ensureStyle();
  const parts=[bar.hist,bar.sync].filter(Boolean);
  if(bar.missing&&bar.missing.total>0)parts.push(`クラウドの履歴に未保存が${bar.missing.total}件あります（${bar.missing.text}）`);
  let el=document.getElementById('c22Bar');
  if(!parts.length){el&&el.remove();return}
  if(!el){el=document.createElement('div');el.id='c22Bar';document.body.appendChild(el)}
  el.className='';
  el.innerHTML=`<div class="c22Msg">${esc(parts.join('／'))}</div><button type="button" data-seika-click-action="c22Resend" data-seika-click-args="%5B%5D">再送</button>`;
 }
 function flashOk(msg){
  ensureStyle();
  let el=document.getElementById('c22Bar');
  if(!el){el=document.createElement('div');el.id='c22Bar';document.body.appendChild(el)}
  el.className='ok';el.innerHTML=`<div class="c22Msg">${esc(msg)}</div>`;
  setTimeout(()=>{if(el.className==='ok')renderBar()},3000);
 }

 const baseSet=setSyncState;
 setSyncState=function(state,detail=''){
  baseSet(state,detail);
  if(state==='失敗'){
   clearTimeout(pendingTimer);pendingTimer=null;
   bar.sync='保存に失敗しました'+(detail?`：${detail}`:'');logError('保存失敗',detail);renderBar();
  }else if(state==='保存済み'){
   clearTimeout(pendingTimer);pendingTimer=null;
   if(bar.sync){bar.sync='';renderBar()}
  }else if(state==='未同期'&&!pendingTimer){
   pendingTimer=setTimeout(()=>{
    pendingTimer=null;
    if(typeof syncState!=='undefined'&&syncState!=='未同期')return;
    bar.sync=navigator.onLine?'未同期のデータが5分以上送れていません':'オフラインのため未同期です（通信が戻ると送ります）';
    renderBar();
   },5*60*1000);
  }
 };
 window.setSyncState=setSyncState;

 const baseHist=saveHistoryTablesNow;
 saveHistoryTablesNow=async function(...args){
  try{
   const r=await baseHist.apply(this,args);
   if(bar.hist){bar.hist='';renderBar()}
   return r;
  }catch(e){
   bar.hist='廃棄・在庫の履歴をクラウドへ保存できていません：'+errText(e).slice(0,120);
   logError('履歴保存失敗',e);renderBar();throw e;
  }
 };
 window.saveHistoryTablesNow=saveHistoryTablesNow;

 async function serverIds(table,ids){
  const found=new Set();
  for(let i=0;i<ids.length;i+=80){
   const q=ids.slice(i,i+80).map(x=>`"${String(x).replace(/["\\]/g,'')}"`).join(',');
   const run=async()=>{
    const res=await fetch(`${SUPABASE_URL}/rest/v1/${table}?select=id&id=in.(${encodeURIComponent(q)})`,{headers:historyApiHeaders()});
    if(!res.ok)throw new Error(`${table} ${res.status} ${(await res.text()).slice(0,200)}`);
    return res.json();
   };
   const rows=typeof v199RetryOnAuth==='function'?await v199RetryOnAuth(run):await run();
   rows.forEach(r=>found.add(String(r.id)));
  }
  return found;
 }
 async function c22CheckHistory(force=false){
  if(!db||!db.user||db.role!=='admin')return null;
  if(!force&&localStorage.getItem(CHECK_KEY)===jstDay())return null;
  const since=Date.now()-14*86400000,grace=Date.now()-10*60000;
  const result={at:new Date().toISOString(),total:0,parts:[],details:[]};
  for(const[key,table,label]of TABLES){
   const rows=(db[key]||[]).filter(r=>{if(!r||r.id==null)return false;const t=new Date(r.createdAt||r.date||0).getTime();return t>=since&&t<=grace});
   if(!rows.length)continue;
   const found=await serverIds(table,rows.map(r=>String(r.id)));
   const miss=rows.filter(r=>!found.has(String(r.id)));
   if(miss.length){result.total+=miss.length;result.parts.push(`${label}${miss.length}件`);result.details.push({label,ids:miss.slice(0,20).map(r=>String(r.id))})}
  }
  localStorage.setItem(CHECK_KEY,jstDay());
  localStorage.setItem(CHECK_KEY+'_result',JSON.stringify(result));
  bar.missing=result.total?{total:result.total,text:result.parts.join('・')}:null;
  if(result.total)logError('履歴保存漏れ',result.parts.join('・'));
  renderBar();
  return result;
 }
 window.c22CheckHistory=c22CheckHistory;

 window.c22Resend=async function(){
  if(typeof v161ShowProcessing==='function')v161ShowProcessing('再送しています');
  try{
   if(typeof saveCloudNow==='function')await saveCloudNow().catch(e=>logError('再送（通常データ）',e));
   await loadHistoryTablesToDb();
   if(db&&db.role==='admin')await c22CheckHistory(true);
  }catch(e){logError('再送失敗',e);bar.sync='再送できませんでした：'+errText(e).slice(0,120)}
  finally{if(typeof v161HideProcessing==='function')v161HideProcessing()}
  if(!bar.sync&&!bar.hist&&!bar.missing)flashOk('クラウドへの保存を確認しました');else renderBar();
  if(typeof currentScreen!=='undefined'&&currentScreen==='c22ErrorLogPage')c22ErrorLogPage();
 };

 function c22ErrorLogPage(){
  if(!canAdmin()){alert('管理者のみ表示できます');return home()}
  setScreen('c22ErrorLogPage',[]);
  let last=null;try{last=JSON.parse(localStorage.getItem(CHECK_KEY+'_result')||'null')}catch(e){}
  const list=readLog();
  const check=last?`<div class="${last.total?'err':'ok'}" style="margin-top:10px">${last.total?`未保存 ${last.total}件（${esc(last.parts.join('・'))}）`:'直近14日分はすべてクラウドに保存されています'}<div class="small">点検日時：${esc(dt(last.at))}</div></div>`:'<div class="notice" style="margin-top:10px">まだ点検していません。</div>';
  const rows=list.length?`<table class="table"><tr><th>日時</th><th>種類</th><th>内容</th><th>画面・利用者</th></tr>${list.map(x=>`<tr><td>${esc(dt(x.at))}</td><td>${esc(x.kind)}</td><td style="word-break:break-all">${esc(x.detail)}</td><td>${esc(x.screen)}<br>${esc(x.user)}</td></tr>`).join('')}</table>`:'<div class="notice">エラーの記録はありません。</div>';
  pageShell('エラー記録・保存点検','保存の失敗と、クラウドへの保存漏れを確認します',`<section class="card"><h2 style="margin-top:0">履歴の保存点検</h2><div class="small">この端末にある直近14日分の在庫入力・廃棄・在庫修正が、クラウドの履歴テーブルにすべて保存されているかを照合します。管理者のログイン時に1日1回自動で行います。</div>${check}<button class="btn blue" style="width:100%;margin-top:10px" data-seika-click-action="c22CheckNow" data-seika-click-args="%5B%5D">今すぐ点検</button></section><section class="card"><h2 style="margin-top:0">この端末のエラー記録（最新${MAX}件まで）</h2><div class="row" style="margin-bottom:10px"><div><button class="btn btn2" data-seika-click-action="c22CopyLog" data-seika-click-args="%5B%5D">記録をコピー</button></div><div><button class="btn btn2" data-seika-click-action="c22ClearLog" data-seika-click-args="%5B%5D">記録を消去</button></div></div>${rows}</section>`);
 }
 window.c22ErrorLogPage=c22ErrorLogPage;
 window.c22CheckNow=async function(){
  if(typeof v161ShowProcessing==='function')v161ShowProcessing('照合しています');
  try{await c22CheckHistory(true)}catch(e){logError('点検失敗',e);alert('点検できませんでした。\n'+errText(e))}
  finally{if(typeof v161HideProcessing==='function')v161HideProcessing()}
  c22ErrorLogPage();
 };
 window.c22CopyLog=async function(){
  const text=readLog().map(x=>`${x.at}\t${x.kind}\t${x.screen}\t${x.user}\t${x.detail}`).join('\n')||'記録なし';
  try{await navigator.clipboard.writeText(text);flashOk('エラー記録をコピーしました')}catch(e){alert(text.slice(0,3000))}
 };
 window.c22ClearLog=function(){if(!confirm('この端末のエラー記録を消去します。'))return;localStorage.removeItem(LOG_KEY);c22ErrorLogPage()};

 if(typeof V1105_MENU_GROUPS!=='undefined'&&V1105_MENU_GROUPS.support&&!V1105_MENU_GROUPS.support.items.some(x=>x.fn==='c22ErrorLogPage()'))
  V1105_MENU_GROUPS.support.items.push({label:'エラー記録・保存点検',fn:'c22ErrorLogPage()',roles:['admin']});

 try{
  const last=JSON.parse(localStorage.getItem(CHECK_KEY+'_result')||'null');
  if(last&&last.total&&localStorage.getItem(CHECK_KEY)===jstDay())bar.missing={total:last.total,text:last.parts.join('・')};
 }catch(e){}
 const baseHome=home;
 home=function(...args){
  const r=baseHome.apply(this,args);
  renderBar();
  setTimeout(()=>c22CheckHistory(false).catch(e=>logError('点検失敗',e)),4000);
  return r;
 };
 window.home=home;
})();

window.APP_VERSION='v1.199';document.title='SEIKA＋ v1.199 現場運用';
/* ===== v1.199-c23 QRロット詳細から最新の操作を取消 ===== */
const V1231_CANCELABLE=["出庫","廃棄","出庫・調整減","入庫・調整増","調整","差分なし"];
let v1231Busy=false;
function v1231IsCancelled(m){return !!(m&&(m.reversed_operation_id||m.cancelled_at))}
function v1231Label(m){return `${m.movement_type} ${fmt(m.qty??m.quantity??0)}${m.unit||""}（${dt(m.occurred_at||m.created_at)}）`}
async function v1231CancelLatest(q,expectedId){
  if(v1231Busy)return;
  if(!canQrOperate())return alert("QR操作の取消は管理者・青果社員のみです");
  v1231Busy=true;
  try{
    const rows=await qrSelect("qr_lot_movements",`select=*&qr_key=eq.${encodeURIComponent(q)}&order=created_at.desc&limit=1`);
    const m=rows[0];
    if(!m||String(m.id)!==String(expectedId))throw new Error("このロットに新しい操作が登録されました。画面を開き直してから取り消してください。");
    if(v1231IsCancelled(m))throw new Error("この操作はすでに取り消されています");
    if(!confirm(`次の操作を取り消します。\n\n${v1231Label(m)}\n\n在庫数は操作前に戻ります。履歴には「取消」として残ります。`))return;
    const meta=operationMeta("qr_cancel",{qrKey:q});
    const ans=await callRpc("cancel_qr_lot_operation",{p_cancel_operation_id:meta.operationId,p_original_operation_id:m.operation_id,p_user_id:db.userId||null,p_user_name:db.user||null,p_device_meta:{deviceId:meta.deviceId,userAgent:navigator.userAgent||""},p_operation_meta:meta,p_memo:`画面から${m.movement_type}を取消`});
    if(!ans?.ok)throw new Error(ans?.message||"取消に失敗しました");
    addOperationLog("qr_cancel",{operationId:m.operation_id,movementType:m.movement_type},{cancelled:true},meta);
    await qrLotDetail(q,`${m.movement_type}を取り消しました。在庫数は${fmt(ans.after_quantity??0)}に戻りました。`);
  }catch(e){
    const s=String(e&&e.message||e);
    alert(/check constraint|23514/.test(s)?"取消の準備（SQL 002）がまだ実行されていません。管理者に連絡してください。":s);
  }finally{v1231Busy=false}
}
window.v1231CancelLatest=v1231CancelLatest;
async function v1232CancelWasteRecordOnly(q,m){
  if(v1231Busy)return;
  if(!(typeof canAdmin==="function"&&canAdmin()))return alert("廃棄記録だけの取消は管理者のみです");
  if(!confirm(`廃棄記録だけを取り消します。\n\n${v1231Label(m)}\n\n在庫数は変わりません（実数調整などで直した数のまま）。\nこの廃棄は廃棄一覧・週次レポートから外れます。`))return;
  v1231Busy=true;
  try{
    const meta=operationMeta("qr_cancel_waste_record",{qrKey:q});
    const ans=await callRpc("cancel_qr_waste_record_only_v1232",{p_cancel_operation_id:meta.operationId,p_original_operation_id:m.operation_id,p_user_id:db.userId||null,p_user_name:db.user||null,p_device_meta:{deviceId:meta.deviceId,userAgent:navigator.userAgent||""},p_operation_meta:meta,p_memo:"廃棄記録のみ取消（在庫数は変更なし）"});
    if(!ans?.ok)throw new Error(ans?.message||"取消に失敗しました");
    addOperationLog("qr_cancel_waste_record",{operationId:m.operation_id},{cancelled:true,recordOnly:true},meta);
    await qrLotDetail(q,"廃棄記録を取り消しました。在庫数は変わっていません。");
  }catch(e){
    const s=String(e&&e.message||e);
    alert(/cancel_qr_waste_record_only_v1232|PGRST202|404/.test(s)?"準備（SQL 003）がまだ実行されていません。管理者に連絡してください。":s);
  }finally{v1231Busy=false}
}
window.v1232CancelWasteRecordOnly=v1232CancelWasteRecordOnly;
async function v1233CancelQrWasteFromList(operationId,qrKey){
  if(v1231Busy)return;
  if(!canQrOperate())return alert("QR廃棄の取消は管理者・青果社員のみです");
  v1231Busy=true;
  try{
    const w=(await qrSelect("qr_lot_movements",`select=*&operation_id=eq.${encodeURIComponent(operationId)}&limit=1`))[0];
    if(!w)throw new Error("取消対象の廃棄が見つかりません");
    if(v1231IsCancelled(w))throw new Error("この廃棄はすでに取り消されています");
    const key=w.qr_key||qrKey;
    const latest=(await qrSelect("qr_lot_movements",`select=*&qr_key=eq.${encodeURIComponent(key)}&order=created_at.desc&limit=1`))[0];
    const isLatest=latest&&String(latest.id)===String(w.id);
    const label=`${w.item_name||""} ${v1231Label(w)}`;
    let ans,msg;
    if(isLatest){
      if(!confirm(`次の廃棄を取り消します。\n\n${label}\n\n在庫数は廃棄前の${fmt(w.before_quantity??0)}${w.unit||""}に戻ります。\n廃棄一覧・週次レポートから外れ、履歴には「取消」として残ります。`))return;
      const meta=operationMeta("qr_cancel",{qrKey:key});
      ans=await callRpc("cancel_qr_lot_operation",{p_cancel_operation_id:meta.operationId,p_original_operation_id:w.operation_id,p_user_id:db.userId||null,p_user_name:db.user||null,p_device_meta:{deviceId:meta.deviceId,userAgent:navigator.userAgent||""},p_operation_meta:meta,p_memo:"廃棄一覧から廃棄を取消"});
      if(!ans?.ok)throw new Error(ans?.message||"取消に失敗しました");
      addOperationLog("qr_cancel",{operationId:w.operation_id,movementType:"廃棄"},{cancelled:true},meta);
      msg=`${w.item_name||"QR廃棄"}の廃棄を取り消しました。在庫数は${fmt(ans.after_quantity??0)}${w.unit||""}に戻りました。`;
    }else{
      if(!(typeof canAdmin==="function"&&canAdmin()))throw new Error("この廃棄のあとに別の操作（実数調整など）があるため、取り消せるのは管理者だけです。");
      if(!confirm(`この廃棄のあとに別の操作（${latest?v1231Label(latest):"不明"}）があります。\n廃棄記録だけを取り消します。\n\n${label}\n\n在庫数は変わりません（今の${fmt(latest?.after_quantity??0)}${w.unit||""}のまま）。\n廃棄一覧・週次レポートから外れます。`))return;
      const meta=operationMeta("qr_cancel_waste_record",{qrKey:key});
      ans=await callRpc("cancel_qr_waste_record_only_v1232",{p_cancel_operation_id:meta.operationId,p_original_operation_id:w.operation_id,p_user_id:db.userId||null,p_user_name:db.user||null,p_device_meta:{deviceId:meta.deviceId,userAgent:navigator.userAgent||""},p_operation_meta:meta,p_memo:"廃棄一覧から廃棄記録のみ取消（在庫数は変更なし）"});
      if(!ans?.ok)throw new Error(ans?.message||"取消に失敗しました");
      addOperationLog("qr_cancel_waste_record",{operationId:w.operation_id},{cancelled:true,recordOnly:true},meta);
      msg=`${w.item_name||"QR廃棄"}の廃棄記録を取り消しました。在庫数は変わっていません。`;
    }
    await wasteListPage(msg);
  }catch(e){
    const s=String(e&&e.message||e);
    alert(/check constraint|23514/.test(s)?"準備（SQL 002）がまだ実行されていません。":/cancel_qr_waste_record_only_v1232|PGRST202/.test(s)?"準備（SQL 003）がまだ実行されていません。":s);
  }finally{v1231Busy=false}
}
window.v1233CancelQrWasteFromList=v1233CancelQrWasteFromList;
async function v1231DecorateHistory(q){
  const card=[...document.querySelectorAll(".wrap .card")].find(c=>{const b=c.querySelector(":scope > b");return b&&b.textContent.trim()==="履歴"});
  if(!card||card.dataset.v1231)return;
  card.dataset.v1231="1";
  const shown=await qrSelect("qr_lot_movements",`select=*&qr_key=eq.${encodeURIComponent(q)}&order=occurred_at.desc&limit=30`).catch(()=>[]);
  const trs=[...card.querySelectorAll("table tr")].slice(1);
  shown.forEach((m,i)=>{
    const tr=trs[i];if(!tr||!v1231IsCancelled(m))return;
    tr.style.opacity="0.55";
    const td=tr.children[1];
    if(td)td.insertAdjacentHTML("beforeend",`<div class="small" style="color:#b45309;font-weight:700">取消済み</div>`);
  });
  if(!canQrOperate())return;
  const latest=(await qrSelect("qr_lot_movements",`select=*&qr_key=eq.${encodeURIComponent(q)}&order=created_at.desc&limit=1`).catch(()=>[]))[0];
  if(typeof canAdmin==="function"&&canAdmin())shown.forEach((m,i)=>{
    const tr=trs[i];
    if(!tr||v1231IsCancelled(m)||!m.operation_id||String(m.movement_type||"")!=="廃棄"||(latest&&String(latest.id)===String(m.id)))return;
    const td=tr.children[1];if(!td)return;
    const b=document.createElement("button");
    b.className="btn btn2";b.style.cssText="margin-top:6px;padding:6px 8px;font-size:12px";
    b.textContent="廃棄記録のみ取消";
    b.addEventListener("click",()=>v1232CancelWasteRecordOnly(q,m));
    td.appendChild(b);
  });
  if(!latest||!latest.operation_id||v1231IsCancelled(latest)||!V1231_CANCELABLE.includes(String(latest.movement_type||"")))return;
  const box=document.createElement("div");
  box.style.margin="10px 0";
  box.innerHTML=`<button class="btn orange" style="width:100%">最新の操作を取消：${esc(v1231Label(latest))}</button><div class="small" style="margin-top:6px">取り消すと在庫数が操作前に戻り、廃棄の場合は廃棄一覧・週次レポートからも外れます。取り消せるのは一番新しい操作だけです。</div>`;
  box.querySelector("button").addEventListener("click",()=>v1231CancelLatest(q,latest.id));
  card.querySelector(":scope > b").insertAdjacentElement("afterend",box);
}
const v1231QrLotDetailBase=qrLotDetail;
qrLotDetail=async function(q,msg=""){
  await v1231QrLotDetailBase(q,msg);
  try{await v1231DecorateHistory(q)}catch(e){console.warn("[QR取消]",e)}
};
window.qrLotDetail=qrLotDetail;

/* ===== v1.199-c26 段階1：競合時の自動統合から在庫入力・廃棄・在庫修正を外し、履歴テーブルを正とする ===== */
const V1234_HISTORY_KEYS=["records","movements","wasteRecords"];
let v1234History=null;
function v1234TableRole(role){return role==="admin"||role==="worker"?["records","movements","wasteRecords"]:(role==="clerk"||role==="sales")?["wasteRecords"]:[]}
async function v1234LoadHistoryTruth(){
  const keys=v1234TableRole(db?.role);if(!keys.length)return null;
  try{await saveHistoryTablesNow();v188SetHistoryPending(false)}
  catch(e){v188SetHistoryPending(true);setSyncState("競合","履歴をクラウドへ保存できないため統合を中止しました。入力は端末に保持しています");throw new Error("在庫入力・廃棄の履歴をクラウドへ保存できないため、統合を中止しました。入力は端末に保持しています。通信を確認して、もう一度再送してください。\n"+v161ErrorText(e))}
  const out={};
  for(const k of keys){
    const rows=await fetchHistoryTable(HISTORY_TABLES[k]);
    const sortKey=k==="wasteRecords"?r=>new Date(r.date||r.createdAt||0):r=>new Date(r.createdAt||0);
    out[k]=mergeHistoryById(db[k]||[],rows).sort((a,b)=>sortKey(a)-sortKey(b));
  }
  return out;
}
const v1234MergePayloadBase=v121MergePayload;
v121MergePayload=function(base,local,remote){
  if(!v1234History)return v1234MergePayloadBase(base,local,remote);
  const strip=x=>{const c=v121Clone(x||{});for(const k of V1234_HISTORY_KEYS)delete c[k];return c};
  const result=v1234MergePayloadBase(strip(base),strip(local),strip(remote));
  const merged={...(result.merged||{})};
  for(const k of V1234_HISTORY_KEYS){
    const present=[base,local,remote].some(x=>x&&Object.prototype.hasOwnProperty.call(x,k));
    if(present&&Array.isArray(v1234History[k]))merged[k]=v121Clone(v1234History[k]);
  }
  return{...result,merged};
};
window.v121MergePayload=v121MergePayload;
const v1234ResolveBase=v178ResolvePendingInventoryConflict;
v178ResolvePendingInventoryConflict=async function(...args){
  if(!v161ReadQueue()[0])return v1234ResolveBase.apply(this,args);
  const truth=await v1234LoadHistoryTruth();
  v1234History=truth;
  try{return await v1234ResolveBase.apply(this,args)}
  finally{v1234History=null}
};
window.v178ResolvePendingInventoryConflict=v178ResolvePendingInventoryConflict;

/* ===== v1.199-c27 棚卸し確定・取消の直後に履歴テーブルへ保存 ===== */
async function v1235SaveHistoryAfterCount(){
  if(!historyTablesReady||!["admin","worker"].includes(db?.role))return;
  try{v188SetHistoryPending(true);await saveHistoryTablesNow();v188SetHistoryPending(false)}
  catch(e){v188SetHistoryPending(true);setSyncState("未同期","棚卸しの在庫履歴をクラウドへ保存できていません。通信を確認して再送してください");console.error("[棚卸し履歴保存]",e)}
}
for(const name of ["v188Confirm","confirmInventoryCount","reverseInventoryCount"]){
  const base=window[name];if(typeof base!=="function")continue;
  const wrapped=async function(...args){const r=await base.apply(this,args);await v1235SaveHistoryAfterCount();return r};
  window[name]=wrapped;
}
v188Confirm=window.v188Confirm;confirmInventoryCount=window.confirmInventoryCount;reverseInventoryCount=window.reverseInventoryCount;
/* ===== v1.199-c27 QRロット一覧：品目の絞り込みを常にサーバー側で行う ===== */
function v1235QuoteLike(s){return '"*'+String(s||"").replace(/["\\]/g,"").replace(/[*%,()]/g,"")+'*"'}
function v1235QrWords(raw){
  const rule=v1200QrRuleFor(raw);
  const list=[raw,...v1200QrNameGroup(raw)];
  if(rule&&typeof rule!=="string")list.push(rule.name||rule.item_name||"",...(rule.aliases||[]));
  return{rule,words:[...new Set(list.map(x=>String(x||"").replace(/\s+/g,"").replace(/[（）()]/g,"").trim()).filter(Boolean))]};
}
v1200QrItemQuery=function(selected){
  const raw=String(selected||"").trim();if(!raw)return"";
  if(v1200QrIsPotatoName(raw)){const list=v1200QrNameGroup(raw).map(n=>'"'+n.replace(/"/g,"")+'"').join(",");return`&item_name=in.(${encodeURIComponent(list)})`}
  const{rule,words}=v1235QrWords(raw);
  if(rule&&typeof rule!=="string"&&(v1200QrRuleMode(rule)==="all"||rule.all===true))return"";
  if(!words.length)return"";
  const conds=words.map(w=>`item_name.ilike.${v1235QuoteLike(w)}`).join(",");
  return`&or=(${encodeURIComponent(conds)})`;
};
v1200QrFilterByGroup=function(lots,selected){
  const raw=String(selected||"").trim();if(!raw)return lots||[];
  if(v1200QrIsPotatoName(raw))return lots||[];
  const rule=v1200QrRuleFor(raw),names=new Set(v1200QrNameGroup(raw).concat(raw).map(qrNormalizeName));
  return(lots||[]).filter(l=>{const n=l&&l.item_name;return names.has(qrNormalizeName(n))||(rule?qrManagedItemMatches(rule,n):false)});
};
window.v1200QrItemQuery=v1200QrItemQuery;window.v1200QrFilterByGroup=v1200QrFilterByGroup;

/* ===== v1.199-c28 ログイン画面の名前一覧をサーバーから取得 ===== */
let v1241LoginFetching=false;
async function v1241FetchLoginUsers(){
  const res=await v188NativeFetch(`${SUPABASE_URL}/rest/v1/rpc/list_login_users_v1241`,{method:"POST",headers:{apikey:SUPABASE_KEY,Authorization:`Bearer ${SUPABASE_KEY}`,"Content-Type":"application/json"},body:"{}"});
  if(!res.ok)throw new Error(await res.text());
  const rows=await res.json();
  return Array.isArray(rows)?rows.filter(r=>r&&r.legacy_user_id):[];
}
async function v1241RefreshLoginUsers(render){
  if(v1241LoginFetching)return;v1241LoginFetching=true;
  try{
    const rows=await v1241FetchLoginUsers();if(!rows.length)return;
    const before=localStorage.getItem(STORE+"_login_users_v188")||"";
    v188SaveLoginUsers(rows.map(r=>({legacy_user_id:r.legacy_user_id,display_name:r.display_name,role:r.role,active:true})));
    const after=localStorage.getItem(STORE+"_login_users_v188")||"";
    if(before===after||currentScreen!=="login"||db?.user)return;
    const sel=document.getElementById("loginUser"),pass=document.getElementById("loginPass");
    const uid=sel?.value||"",pw=pass?.value||"",focused=document.activeElement?.id||"";
    render();
    const sel2=document.getElementById("loginUser"),pass2=document.getElementById("loginPass");
    if(sel2&&uid&&[...sel2.options].some(o=>o.value===uid))sel2.value=uid;
    if(pass2&&pw)pass2.value=pw;
    if(focused)document.getElementById(focused)?.focus();
  }catch(e){console.warn("[ログイン名一覧]",e)}
  finally{v1241LoginFetching=false}
}
(function(){
  const baseLogin=login,baseSetScreen=setScreen;
  setScreen=function(name,args){const r=baseSetScreen.apply(this,arguments);if(name==="login")setTimeout(()=>v1241RefreshLoginUsers(()=>baseLogin()),0);return r};
  window.setScreen=setScreen;
  if(typeof currentScreen!=="undefined"&&currentScreen==="login")v1241RefreshLoginUsers(()=>baseLogin());
})();

/* ===== v1.199-c29 保管期間アラート（品目別の使用期限・5段階） ===== */
const V1250_DEFAULT_LIMITS=[
  [30,["じゃがいも","牛蒡"]],[20,["玉葱","さつまいも"]],[14,["南瓜","レモン"]],
  [7,["長葱","人参","大根","カット大根","葉付き大根","かぶ","レンコン","キャベツ","紫キャベツ","白菜","長芋","里芋","ぶなしめじ","まいたけ","しいたけ","エリンギ","ピーマン","とんがりピーマン","赤ピーマン","赤パプリカ","黄パプリカ","ししとう","ズッキーニ","ゴーヤ"]],
  [5,["胡瓜","ミニトマト","トマト","レタス","ロメインレタス","グリーンリーフ","サニーレタス","ほうれん草","小松菜","わさび菜","水菜","春菊","なす","セロリ","ニラ","青梗菜"]],
  [4,["小葱","青葱"]],[3,["みつ葉","大葉","もやし","皮むき玉葱","皮むき牛蒡"]]
].flatMap(([d,names])=>names.map(n=>({item_name:n,limit_days:d})));
const V1250_ALIASES={"じゃがいも":["じゃが芋","ジャガイモ","馬鈴薯","ばれいしょ"],"牛蒡":["ごぼう","ゴボウ"],"玉葱":["玉ねぎ","たまねぎ","タマネギ"],"さつまいも":["さつま芋","サツマイモ","薩摩芋"],"南瓜":["かぼちゃ","カボチャ"],"長葱":["長ねぎ","長ネギ"],"人参":["にんじん","ニンジン"],"葉付き大根":["葉付大根"],"かぶ":["カブ","蕪"],"レンコン":["れんこん","蓮根"],"長芋":["長いも"],"里芋":["さといも"],"ぶなしめじ":["しめじ"],"まいたけ":["舞茸"],"しいたけ":["椎茸"],"赤パプリカ":["パプリカ"],"胡瓜":["きゅうり","キュウリ"],"ロメインレタス":["ロメイン"],"グリーンリーフ":["リーフ","グリーンカール","リーフレタス"],"サニーレタス":["サニー"],"ほうれん草":["ほうれんそう"],"なす":["茄子","長茄子"],"ニラ":["にら"],"青梗菜":["チンゲン菜","チンゲンサイ"],"青葱":["青ねぎ","青ネギ"],"みつ葉":["三つ葉"]};
let v1250LimitRows=V1250_DEFAULT_LIMITS.slice(),v1250LimitSource="default",v1250LimitsAt=0;
let V1250_LIMIT_MAP=new Map(),V1250_LIMIT_KEYS=[],v1250PotatoName="じゃがいも";
function v1250BuildLimitMap(){
  const m=new Map(),own=new Set();
  for(const r of v1250LimitRows){const k=qrNormalizeName(r.item_name);if(k){m.set(k,Number(r.limit_days));own.add(k)}}
  for(const[canon,aliases]of Object.entries(V1250_ALIASES)){
    const d=m.get(qrNormalizeName(canon));if(d==null)continue;
    for(const a of aliases){const k=qrNormalizeName(a);if(!own.has(k))m.set(k,d)}
  }
  V1250_LIMIT_MAP=m;V1250_LIMIT_KEYS=[...m.keys()].sort((a,b)=>b.length-a.length);
}
v1250BuildLimitMap();
async function v1250LoadLimits(force=false){
  if(!force&&Date.now()-v1250LimitsAt<300000)return v1250LimitRows;
  try{
    const rows=await qrSelect("qr_storage_limits_v1250","select=item_name,limit_days,sort_order,updated_by_name,updated_at&order=sort_order.asc,item_name.asc");
    if(Array.isArray(rows)&&rows.length){v1250LimitRows=rows;v1250LimitSource="db"}
    else{v1250LimitRows=V1250_DEFAULT_LIMITS.slice();v1250LimitSource="default"}
    v1250LimitsAt=Date.now();v1250BuildLimitMap();
  }catch(e){console.warn("[保管目安] 読み込めないため初期値で判定します",e);v1250LimitSource="default"}
  return v1250LimitRows;
}
function v1250LimitDays(name){
  const raw=String(name||"").trim();if(!raw)return null;
  const n=qrNormalizeName(raw),plain=qrNormalizeName(raw.replace(/[（(][^）)]*[）)]/g,""));
  for(const k of[n,plain])if(V1250_LIMIT_MAP.has(k))return V1250_LIMIT_MAP.get(k);
  if(typeof v1200QrIsPotatoName==="function"&&v1200QrIsPotatoName(raw)){const d=V1250_LIMIT_MAP.get(qrNormalizeName(v1250PotatoName));if(d!=null)return d}
  const hit=V1250_LIMIT_KEYS.find(k=>plain.includes(k)||n.includes(k));
  return hit?V1250_LIMIT_MAP.get(hit):null;
}
const V1250_LEVELS={
  1:{label:"良好",card:"v1250L1",badge:"v1250B1"},
  2:{label:"要観察",card:"v1250L2",badge:"v1250B2"},
  3:{label:"優先使用",card:"v1250L3",badge:"v1250B3"},
  4:{label:"要品質確認",card:"v1250L4",badge:"v1250B4"},
  5:{label:"使用不可/保留",card:"v1250L5",badge:"v1250B5"}
};
function v1250LevelOf(elapsed,limit){
  if(elapsed>=limit+2)return 5;
  if(elapsed>=limit)return 4;
  if(elapsed===limit-1)return 3;
  if(elapsed>=limit*0.5)return 2;
  return 1;
}
let v1250Checks=new Map(),v1250ChecksDate="",v1250ChecksAt=0;
async function v1250LoadChecks(force=false){
  const today=todayKey();
  if(!force&&v1250ChecksDate===today&&Date.now()-v1250ChecksAt<60000)return v1250Checks;
  try{
    const rows=await qrSelect("qr_lot_storage_checks_v1250",`select=lot_id,checked_by_name,created_at&check_date=eq.${today}`);
    v1250Checks=new Map((rows||[]).map(r=>[String(r.lot_id),r]));v1250ChecksDate=today;v1250ChecksAt=Date.now();
  }catch(e){console.warn("[保管期間アラート] 品質確認の記録を読み込めません",e)}
  return v1250Checks;
}
function v1250Info(lot){
  if(!lot||Number(lot.current_qty??0)<=0)return null;
  const limit=v1250LimitDays(lot.item_name);if(!limit)return null;
  const elapsed=qrLotAgeDays(lot),level=v1250LevelOf(elapsed,limit);
  const check=level===4&&v1250ChecksDate===todayKey()?v1250Checks.get(String(lot.id))||null:null;
  return{level,effective:check?3:level,elapsed,limit,check};
}
function v1250CanConfirm(){return["admin","worker"].includes(db?.role)}
const v1250AgeInfoBase=qrLotAgeInfo;
qrLotAgeInfo=function(l){
  const info=v1250Info(l);
  if(!info){
    if(l&&Number(l.current_qty??0)>0&&v1250LimitDays(l.item_name)==null)return v1250AgeInfoBase(l);
    return{card:"",badge:"",text:""};
  }
  const lv=V1250_LEVELS[info.effective],head=info.check?"品質確認済み・優先使用":lv.label;
  return{card:lv.card,badge:lv.badge,text:`${head}｜入荷から${info.elapsed}日（目安${info.limit}日）`};
};
window.qrLotAgeInfo=qrLotAgeInfo;
function v1250ExtraHtml(l){
  const info=v1250Info(l);if(!info||info.level<4)return"";
  if(info.level===5)return`<div class="v1250Stop">使用不可/保留：目安を2日以上超えています。${v1250CanConfirm()?"使う場合は実物を確認してから出庫・使用してください（確認した人を記録します）。":"出庫・使用はできません。青果社員に相談してください。"}</div>`;
  if(info.check)return`<div class="v1250Checked">本日 品質確認済み（${esc(info.check.checked_by_name||"")}）</div>`;
  return`<div class="v1250Need">要品質確認：実物を確認してください。${v1250CanConfirm()?`<button class="btn red" style="width:100%;margin-top:8px" ${seikaEventAttrs('click','v1250ConfirmQuality',[String(l.id),String(l.qr_key||"")])}>品質確認済みにする</button>`:""}</div>`;
}
const v1250LotCardBase=qrLotCard;
qrLotCard=function(l,showDetail=true,showAge=false){
  const html=v1250LotCardBase.apply(this,arguments);
  if(!showAge)return html;
  const extra=v1250ExtraHtml(l);if(!extra)return html;
  const i=html.lastIndexOf("</div>");
  return i<0?html+extra:html.slice(0,i)+extra+html.slice(i);
};
window.qrLotCard=qrLotCard;
let v1250LastCounts=null;
function v1250ApplyList(lots,sort,alertOnly){
  const rows=(lots||[]).map(l=>({l,info:v1250Info(l)}));
  const counts={1:0,2:0,3:0,4:0,5:0,checked:0};
  for(const r of rows)if(r.info){counts[r.info.effective]++;if(r.info.check)counts.checked++}
  v1250LastCounts=counts;
  let out=alertOnly?rows.filter(r=>r.info&&r.info.effective>=4):rows;
  if(sort==="alert"){
    const recv=l=>String(l.received_date||l.created_at||"");
    out=out.slice().sort((a,b)=>(b.info?.effective||0)-(a.info?.effective||0)
      ||((b.info?b.info.elapsed-b.info.limit:-999)-(a.info?a.info.elapsed-a.info.limit:-999))
      ||recv(a.l).localeCompare(recv(b.l)));
  }
  return out.map(r=>r.l);
}
function v1250ListBar(sort,alertOnly,full){
  const c=v1250LastCounts||{1:0,2:0,3:0,4:0,5:0,checked:0};
  const counts=full?`<div class="v1250Counts"><span class="v1250B5">使用不可 ${c[5]}</span><span class="v1250B4">要品質確認 ${c[4]}</span><span class="v1250B3">優先使用 ${c[3]}${c.checked?`（確認済み ${c.checked}）`:""}</span><span class="v1250B2">要観察 ${c[2]}</span></div>`:`<div class="small" style="margin-top:4px">「アラートが高い順」または絞り込みを押すと、在庫のあるロットをすべて読み込んで判定します。</div>`;
  return`<div class="card"><b>保管期間アラート</b>${counts}<div class="row" style="margin-top:8px"><button class="btn ${alertOnly?"red":"btn2"}" ${seikaEventAttrs('click','v1250ToggleAlertOnly',[])}>${alertOnly?"絞り込み中：要品質確認以上（解除）":"要品質確認以上だけ表示"}</button><button class="btn ${sort==="alert"?"orange":"btn2"}" ${seikaEventAttrs('click','v1250SortAlert',[])}>アラートが高い順</button></div></div>`;
}
function v1250ToggleAlertOnly(){const s=qrLotListState;return qrLotListPage(s.selectedItem,s.sortOrder,s.stockFilter,s.displayLimit,!s.alertOnly)}
function v1250SortAlert(){const s=qrLotListState;return qrLotListPage(s.selectedItem,"alert",s.stockFilter,s.displayLimit,!!s.alertOnly)}
async function v1250ConfirmQuality(lotId,qrKey){
  if(!v1250CanConfirm())return alert("品質確認は管理者・青果社員が行います。");
  if(!confirm("実物を確認し、品質に問題がないことを確認しましたか？\n確認済みにすると、本日中は「優先使用」として扱います。"))return;
  try{
    const ans=await callRpc("confirm_qr_lot_storage_check_v1250",{p_lot_id:lotId,p_note:""});
    if(!ans?.ok)throw new Error(ans?.message||"品質確認を保存できませんでした");
    await v1250LoadChecks(true);
    if(currentScreen==="qrLotListPage")return qrReturnToLotList();
    if(currentScreen==="qrOperationLotPage"&&qrKey)return qrOperationLotPage("out",qrKey);
    alert("品質確認済みにしました。");
  }catch(e){alert(/PGRST202|Could not find the function|qr_lot_storage_checks_v1250/.test(String(e.message||e))?"品質確認の保存先がまだ準備されていません（SQL 007 の実行が必要です）。":(e.message||e))}
}
const v1250ListPageBase=qrLotListPage;
qrLotListPage=async function(...args){await v1250LoadChecks();return v1250ListPageBase.apply(this,args)};
window.qrLotListPage=qrLotListPage;
const v1250OpPageBase=qrOperationLotPage;
qrOperationLotPage=async function(kind,q){
  if(kind==="out")await v1250LoadChecks();
  const r=await v1250OpPageBase.apply(this,arguments);
  if(kind!=="out")return r;
  try{
    const lot=await qrFindLot(q),info=v1250Info(lot),main=document.querySelector(".wrap");
    if(info&&info.effective>=3&&main&&!main.querySelector(".v1250OpBanner")){
      const lv=V1250_LEVELS[info.effective];
      main.insertAdjacentHTML("afterbegin",`<div class="card v1250OpBanner ${lv.card}"><span class="qrAgeBadge ${lv.badge}">${esc(info.check?"品質確認済み・優先使用":lv.label)}｜入荷から${info.elapsed}日（目安${info.limit}日）</span>${v1250ExtraHtml(lot)}</div>`);
    }
  }catch(e){console.warn("[保管期間アラート]",e)}
  return r;
};
window.qrOperationLotPage=qrOperationLotPage;
function v1250GuardUse(lot,what){
  const info=v1250Info(lot);
  if(!info||info.effective<5)return true;
  const msg=`このロットは「使用不可/保留」です。\n${lot.item_name||""}：入荷から${info.elapsed}日（目安${info.limit}日）`;
  if(!v1250CanConfirm()){alert(`${msg}\n\n${what}できません。青果社員に相談してください。`);return false}
  if(!confirm(`${msg}\n\n実物を確認し、使える品質であることを確認しましたか？\n「OK」で${what}します（確認した人を記録します）。`))return false;
  callRpc("confirm_qr_lot_storage_check_v1250",{p_lot_id:String(lot.id),p_note:`使用不可/保留を確認して${what}`}).catch(e=>console.warn("[保管期間アラート] 確認記録を保存できません",e));
  return true;
}
const v1250SaveMoveBase=qrSaveLotMovement;
qrSaveLotMovement=async function(kind,q){
  if(kind==="out"){
    const lot=await qrFindLot(q).catch(()=>null);
    if(lot&&!v1250GuardUse(lot,"出庫"))return;
  }
  return v1250SaveMoveBase.apply(this,arguments);
};
window.qrSaveLotMovement=qrSaveLotMovement;
const v1250AddTrimBase=v195AddTrimLotObject;
v195AddTrimLotObject=function(lot){
  if(lot&&!v1250GuardUse(lot,"使用原料に追加"))throw new Error("使用不可/保留のロットのため追加しませんでした");
  return v1250AddTrimBase.apply(this,arguments);
};
window.v195AddTrimLotObject=v195AddTrimLotObject;
(function(){
  const css=`.v1250L1{border-left:6px solid #16a34a}
.v1250L2{background:#fefce8;border:2px solid #facc15}
.v1250L3{background:#ffedd5;border:2px solid #f97316}
.v1250L4{background:#fef2f2;border:3px solid #dc2626;box-shadow:0 0 0 2px #fecaca}
.v1250L5{background:#ffe4e6;border:3px solid #881337}
.v1250B1{background:#dcfce7;color:#166534}
.v1250B2{background:#fef08a;color:#854d0e}
.v1250B2::before{content:"▲ "}
.v1250B3{background:#f97316;color:#fff}
.v1250B4{background:#dc2626;color:#fff}
.v1250B5{background:#881337;color:#fff}
.v1250Counts{display:flex;flex-wrap:wrap;gap:6px;margin-top:6px}
.v1250Counts span{border-radius:999px;padding:4px 10px;font-size:12px;font-weight:900}
.v1250Stop{margin-top:10px;padding:10px;border-radius:12px;background:#881337;color:#fff;font-weight:900}
.v1250Need{margin-top:10px;padding:10px;border-radius:12px;background:#fee2e2;color:#991b1b;font-weight:900}
.v1250Checked{margin-top:10px;padding:10px;border-radius:12px;background:#ffedd5;color:#9a3412;font-weight:900}`;
  const st=document.createElement("style");st.id="v1250Style";st.textContent=css;document.head.appendChild(st);
})();

/* ===== v1.199-c31 保管期限マスタ画面（QR在庫管理ホームから変更） ===== */
function v1250CanEditLimits(){return["admin","worker"].includes(db?.role)}
function v1250LevelGuide(d){
  d=Number(d);const watch=Math.ceil(d*0.5),parts=[];
  if(watch<d-1)parts.push(`要観察 ${watch}〜${d-2}日`);
  if(d-1>=0)parts.push(`優先使用 ${d-1}日`);
  parts.push(`要品質確認 ${d}〜${d+1}日`,`使用不可 ${d+2}日〜`);
  return parts.join(" ／ ");
}
async function qrStorageLimitsPage(msg=""){
  setScreen("qrStorageLimitsPage",[msg]);
  pageShell("保管期限マスタ","品目ごとの保管期間（日数）",'<div class="card"><div class="notice">読み込んでいます。</div></div>');
  await v1250LoadLimits(true);
  const edit=v1250CanEditLimits()&&v1250LimitSource==="db";
  const rows=v1250LimitRows.map((r,i)=>({...r,i}));
  const days=[...new Set(rows.map(r=>Number(r.limit_days)))].sort((a,b)=>b-a);
  const info=`<div class="card"><b>保管目安とは</b><div class="small" style="margin-top:4px">入荷日からの日数と保管目安を比べて、QRロット一覧に5段階のアラートを出します。品目名はQRロットの品名と同じ名前にしてください。ロメイン・サニー・しめじなどの別名や、じゃがいもの品種（男爵など）は自動で同じ目安になります。</div>${v1250LimitSource==="db"?"":`<div class="err" style="margin-top:8px">保管目安の保存先がまだ準備されていないため、初期値で判定しています（SQL 008 の実行が必要です）。</div>`}${!v1250CanEditLimits()?`<div class="small" style="margin-top:8px">変更できるのは管理者・青果社員です。</div>`:""}</div>`;
  const add=edit?`<div class="card"><b>品目を追加</b><div class="row" style="margin-top:8px"><div><label class="label" for="v1250NewName">品目名</label><input id="v1250NewName" class="input" placeholder="例：ブロッコリー"></div><div><label class="label" for="v1250NewDays">保管目安（日）</label><input id="v1250NewDays" class="input" type="number" inputmode="numeric" min="1" max="365" step="1"></div></div><button class="btn green" style="width:100%;margin-top:8px" ${seikaEventAttrs('click','v1250AddLimit',[])}>追加する</button></div>`:"";
  const groups=days.map(d=>{
    const list=rows.filter(r=>Number(r.limit_days)===d).map(r=>edit
      ?`<div class="v1250LimitRow"><input id="v1250Name_${r.i}" class="input" value="${esc(r.item_name)}" aria-label="品目名"><input id="v1250Days_${r.i}" class="input" type="number" inputmode="numeric" min="1" max="365" step="1" value="${esc(r.limit_days)}" aria-label="保管目安（日）"><button class="btn blue" ${seikaEventAttrs('click','v1250SaveLimit',[r.i])}>保存</button><button class="btn danger" ${seikaEventAttrs('click','v1250DeleteLimit',[r.i])}>削除</button></div>`
      :`<div class="v1250LimitRow v1250LimitView"><b>${esc(r.item_name)}</b><span>${esc(r.limit_days)}日</span></div>`).join("");
    return`<div class="card"><b>${d}日（${rows.filter(r=>Number(r.limit_days)===d).length}品目）</b><div class="small" style="margin:4px 0 8px">${esc(v1250LevelGuide(d))}（入荷日からの日数）</div>${list}</div>`;
  }).join("");
  pageShell("保管期限マスタ",`${rows.length}品目`,`${msg?`<div class="ok">${esc(msg)}</div>`:""}${info}${add}${groups}`);
}
async function v1250LimitRpc(name,args){
  const ans=await callRpc(name,args);
  if(!ans?.ok)throw new Error(ans?.message||"保存できませんでした");
  return ans;
}
function v1250ReadDays(id){
  const v=String(document.getElementById(id)?.value||"").trim(),n=Number(v);
  if(!/^\d+$/.test(v)||n<1||n>365)throw new Error("保管目安は1〜365の整数（日）で入力してください");
  return n;
}
async function v1250SaveLimit(i){
  const r=v1250LimitRows[i];if(!r)return qrStorageLimitsPage();
  try{
    const name=String(document.getElementById(`v1250Name_${i}`)?.value||"").trim();
    if(!name)throw new Error("品目名を入力してください");
    const d=v1250ReadDays(`v1250Days_${i}`);
    if(name===r.item_name&&d===Number(r.limit_days))return;
    await v1250LimitRpc("save_qr_storage_limit_v1250",{p_item_name:name,p_limit_days:d,p_old_name:r.item_name});
    return qrStorageLimitsPage(`${name}を${d}日にしました`);
  }catch(e){alert(e.message||e)}
}
async function v1250AddLimit(){
  try{
    const name=String(document.getElementById("v1250NewName")?.value||"").trim();
    if(!name)throw new Error("品目名を入力してください");
    if(v1250LimitRows.some(r=>qrNormalizeName(r.item_name)===qrNormalizeName(name)))throw new Error("同じ品目名がすでに登録されています。一覧の日数を変更してください");
    const d=v1250ReadDays("v1250NewDays");
    await v1250LimitRpc("save_qr_storage_limit_v1250",{p_item_name:name,p_limit_days:d,p_old_name:null});
    return qrStorageLimitsPage(`${name}（${d}日）を追加しました`);
  }catch(e){alert(e.message||e)}
}
async function v1250DeleteLimit(i){
  const r=v1250LimitRows[i];if(!r)return;
  if(!confirm(`「${r.item_name}」の保管目安を削除しますか？\n削除すると、この品目は保管期間アラートの対象外になります。`))return;
  try{await v1250LimitRpc("delete_qr_storage_limit_v1250",{p_item_name:r.item_name});return qrStorageLimitsPage(`${r.item_name}を削除しました`)}
  catch(e){alert(e.message||e)}
}
function v1250HomeButton(id,cls,action,html){
  const b=document.createElement("button");b.id=id;b.type="button";b.className="btn "+cls;
  b.setAttribute("data-seika-click-action",action);b.setAttribute("data-seika-click-args","%5B%5D");b.innerHTML=html;return b;
}
function v1250InjectHomeButtons(tries=0){
  if(currentScreen!=="qrHome")return;
  const box=document.querySelector(".homePrimary"),list=box&&box.querySelector('[data-seika-click-action="qrLotListPage"]');
  if(!box||!list){if(tries<40)setTimeout(()=>v1250InjectHomeButtons(tries+1),100);return}
  let totals=document.getElementById("v1204TotalsBtn");
  if(!totals&&typeof qrTotalsPage==="function"){
    totals=v1250HomeButton("v1204TotalsBtn","homeBtnQrTotals","qrTotalsPage",'品目別在庫量<br><span style="font-size:15px;font-weight:800">QR品目の在庫をkgで一覧</span>');
    list.parentNode.insertBefore(totals,list.nextSibling);
  }
  if(!document.getElementById("v1250LimitsBtn")){
    const b=v1250HomeButton("v1250LimitsBtn","homeBtnStorageLimit","qrStorageLimitsPage",'保管期限マスタ<br><span style="font-size:15px;font-weight:800">品目ごとの保管日数を確認・変更</span>');
    const after=totals||list;after.parentNode.insertBefore(b,after.nextSibling);
  }
}
const v1250HomeBase=qrHome;
qrHome=async function(...args){
  const r=await v1250HomeBase.apply(this,args);
  v1250InjectHomeButtons();
  v1250LoadLimits();
  return r;
};
window.qrHome=qrHome;
const v1250ListLimitsBase=qrLotListPage;
qrLotListPage=async function(...args){await v1250LoadLimits();return v1250ListLimitsBase.apply(this,args)};
window.qrLotListPage=qrLotListPage;
const v1250OpLimitsBase=qrOperationLotPage;
qrOperationLotPage=async function(...args){if(args[0]==="out")await v1250LoadLimits();return v1250OpLimitsBase.apply(this,args)};
window.qrOperationLotPage=qrOperationLotPage;
if(typeof v195LoadTrimLots==="function"){
  const v1250TrimLoadBase=v195LoadTrimLots;
  v195LoadTrimLots=async function(...args){await v1250LoadLimits();return v1250TrimLoadBase.apply(this,args)};
  window.v195LoadTrimLots=v195LoadTrimLots;
}
(function(){
  const st=document.createElement("style");
  st.textContent=`.homeBtnStorageLimit{background:linear-gradient(90deg,#9f1239 0%,#e11d48 52%,#fda4af 100%) !important;color:#fff !important;text-shadow:0 1px 2px rgba(0,0,0,.25) !important;border-color:transparent !important;}
.v1250LimitRow{display:grid;grid-template-columns:1fr 84px auto auto;gap:6px;align-items:center;margin-top:6px}
.v1250LimitRow .btn{margin:0;padding:10px 12px}
.v1250LimitView{grid-template-columns:1fr auto;padding:6px 2px;border-bottom:1px solid #e5e7eb}`;
  document.head.appendChild(st);
  try{
    if(typeof V198_GUIDE_SECTIONS!=="undefined"){
      V198_GUIDE_SECTIONS.v1250StorageLimits={title:"保管目安と保管期間アラート",where:"ホーム → QR在庫管理 → 保管期限マスタ ／ QRロット一覧",
        steps:["QRロット一覧では、入荷日からの日数と品目ごとの保管目安を比べて「要観察」「優先使用」「要品質確認」「使用不可/保留」を色とバッジで表示します。",
               "「アラートが高い順」で危ないロットから並べ、「要品質確認以上だけ表示」で対象を絞り込めます。",
               "要品質確認のロットは、実物を確認して「品質確認済みにする」を押すと、その日のあいだは優先使用として扱います。",
               "使用不可/保留のロットは、管理者・青果社員が実物を確認して「OK」を押したときだけ出庫・使用できます（確認した人を記録します）。",
               "保管目安の日数は「保管期限マスタ」で変更・追加・削除できます（管理者・青果社員）。"],
        check:"アラートの出たロットから先に使い、要品質確認は毎日確認します。",
        caution:"品目名はQRロットの品名と同じにしてください。保管目安に無い品目はアラートの対象外です。"};
      if(typeof V198_ROLE_ADD!=="undefined")for(const k of Object.keys(V198_ROLE_ADD))if(Array.isArray(V198_ROLE_ADD[k])&&!V198_ROLE_ADD[k].includes("v1250StorageLimits"))V198_ROLE_ADD[k].push("v1250StorageLimits");
    }
  }catch(e){}
})();

/* ===== v1.199-c32 ①仕入先・単協名で検索 ②保管場所の移動 ③品質評価の確認は担当の仕入れ担当者 ④品質レポートの作り替え ===== */
function v1260Norm(s){return String(s||"").normalize("NFKC").replace(/[\s　]+/g,"").toLowerCase()}
/* ① QRロット一覧・検索：仕入先・単協名 */
let v1260Party={supplier:"",coop:""},v1260PartyNames=null,v1260PartyNamesAt=0;
function v1260PgLike(v){return encodeURIComponent(`*${String(v).replace(/[*%,()]/g," ").trim()}*`)}
function v1260PartyQuery(){
  let q="";
  if(v1260Party.supplier)q+=`&supplier=ilike.${v1260PgLike(v1260Party.supplier)}`;
  if(v1260Party.coop)q+=`&cooperative_name=ilike.${v1260PgLike(v1260Party.coop)}`;
  return q;
}
async function v1260LoadPartyNames(){
  if(v1260PartyNames&&Date.now()-v1260PartyNamesAt<300000)return v1260PartyNames;
  try{
    const rows=await qrSelect("qr_lots","select=supplier,cooperative_name&active=eq.true&limit=5000");
    const uniq=k=>[...new Set((rows||[]).map(r=>String(r[k]||"").trim()).filter(Boolean))].sort((a,b)=>a.localeCompare(b,"ja"));
    v1260PartyNames={supplier:uniq("supplier"),coop:uniq("cooperative_name")};v1260PartyNamesAt=Date.now();
  }catch(e){v1260PartyNames={supplier:[],coop:[]}}
  return v1260PartyNames;
}
function v1260PartyInputs(prefix,values){
  const n=v1260PartyNames||{supplier:[],coop:[]},opts=a=>a.map(x=>`<option value="${esc(x)}"></option>`).join("");
  return`<div class="row" style="margin-top:10px"><div><label class="label" for="${prefix}Supplier">仕入先（一部でも可）</label><input id="${prefix}Supplier" class="input" list="${prefix}SupplierList" value="${esc(values.supplier||"")}" placeholder="例：○○農協" autocomplete="off"><datalist id="${prefix}SupplierList">${opts(n.supplier)}</datalist></div><div><label class="label" for="${prefix}Coop">単協名（一部でも可）</label><input id="${prefix}Coop" class="input" list="${prefix}CoopList" value="${esc(values.coop||"")}" placeholder="例：○○支所" autocomplete="off"><datalist id="${prefix}CoopList">${opts(n.coop)}</datalist></div></div>`;
}
function v1260PartyBar(){
  const on=v1260Party.supplier||v1260Party.coop;
  return`<div class="card"><b>仕入先・単協名で検索</b>${v1260PartyInputs("v1260List",v1260Party)}<div class="row" style="margin-top:8px"><button class="btn blue" ${seikaEventAttrs('click','v1260ApplyListParty',[])}>この条件で検索</button>${on?`<button class="btn btn2" ${seikaEventAttrs('click','v1260ClearListParty',[])}>条件を解除</button>`:""}</div>${on?`<div class="small" style="margin-top:6px">検索中：${esc([v1260Party.supplier&&`仕入先「${v1260Party.supplier}」`,v1260Party.coop&&`単協名「${v1260Party.coop}」`].filter(Boolean).join("・"))}</div>`:""}</div>`;
}
function v1260ApplyListParty(){
  v1260Party={supplier:String(document.getElementById("v1260ListSupplier")?.value||"").trim(),coop:String(document.getElementById("v1260ListCoop")?.value||"").trim()};
  const s=qrLotListState;return qrLotListPage(s.selectedItem,s.sortOrder,s.stockFilter,100,!!s.alertOnly);
}
function v1260ClearListParty(){v1260Party={supplier:"",coop:""};const s=qrLotListState;return qrLotListPage(s.selectedItem,s.sortOrder,s.stockFilter,100,!!s.alertOnly)}
const v1260ListPartyBase=qrLotListPage;
qrLotListPage=async function(...args){await v1260LoadPartyNames();return v1260ListPartyBase.apply(this,args)};
window.qrLotListPage=qrLotListPage;
const v1260ManualPageBase=qrManualSearchPage;
qrManualSearchPage=function(...args){
  const r=v1260ManualPageBase.apply(this,args);
  const fill=()=>{
    const loc=document.getElementById("qrManualLoc"),row=loc&&loc.closest(".row");
    if(row&&!document.getElementById("qrManualSupplier"))row.insertAdjacentHTML("afterend",v1260PartyInputs("qrManual",{}));
  };
  fill();
  v1260LoadPartyNames().then(()=>{if(currentScreen!=="qrManualSearchPage")return;const s=document.getElementById("qrManualSupplier");if(s){const sv=s.value,cv=document.getElementById("qrManualCoop")?.value||"";s.closest(".row").outerHTML=v1260PartyInputs("qrManual",{supplier:sv,coop:cv})}else fill()});
  return r;
};
window.qrManualSearchPage=qrManualSearchPage;
qrRunManualSearch=async function(kind='detail'){
  if(!canQrOperate())kind='detail';
  const box=document.getElementById('qrManualResults'),itemName=document.getElementById('qrManualItem')?.value||'',q=String(document.getElementById('qrManualQuery')?.value||'').trim(),d=document.getElementById('qrManualDate')?.value||'',loc=document.getElementById('qrManualLoc')?.value||'';
  const sup=v1260Norm(document.getElementById('qrManualSupplier')?.value),coop=v1260Norm(document.getElementById('qrManualCoop')?.value);
  if(q&&/^QR\d|^\{/.test(q)){const key=qrExtractKey(q);return kind==='detail'?qrScannedLotActionPage(key):qrOperationLotPage(kind,key)}
  if(!itemName&&!q&&!sup&&!coop)return box.innerHTML='<div class="notice">品目を選ぶか、仕入先・単協名を入力してください。</div>';
  box.innerHTML='<div class="notice">検索中...</div>';
  try{
    let lots=await qrSelect('qr_lots','select=*&active=eq.true&current_qty=gt.0&order=received_date.asc&limit=2000');
    const low=q.toLowerCase();
    lots=lots.filter(l=>(!itemName||v1156QrItemName(l)===itemName)&&(!d||l.received_date===d)&&(!loc||l.storage_location===loc)&&(!q||[l.lot_no,l.qr_key].some(v=>String(v||'').toLowerCase().includes(low)))&&(!sup||v1260Norm(l.supplier).includes(sup))&&(!coop||v1260Norm(l.cooperative_name).includes(coop)));
    v1156QrSearchState={kind,itemName:itemName||v1156QrSearchState.itemName,returnEnabled:!!itemName};
    const title=itemName||[document.getElementById('qrManualSupplier')?.value,document.getElementById('qrManualCoop')?.value].map(x=>String(x||'').trim()).filter(Boolean).join('・')||'検索結果';
    box.innerHTML=lots.length?`<div class="notice"><b>${esc(title)} ${lots.length}件</b><div class="small">入荷日が古い順です。ロット・残数・保管場所を確認して選んでください。</div></div>${lots.map(l=>qrSelectableLotHtml(l,kind)).join('')}`:'<div class="notice">該当ロットがありません。</div>';
  }catch(e){box.innerHTML=`<div class="err">検索に失敗しました。${esc(e.message||e)}</div>`}
};
window.qrRunManualSearch=qrRunManualSearch;

/* ② 保管場所の移動 */
const v1260SecondaryBase=qrSecondaryActions;
qrSecondaryActions=function(lot,...rest){
  const html=v1260SecondaryBase.call(this,lot,...rest);
  if(!canQrOperate()||!lot||lot.active===false)return html;
  return`<button class="btn homeBtnQrMove" style="width:100%;margin-top:10px" ${seikaEventAttrs('click','qrMoveLocationPage',[String(lot.qr_key||"")])}>保管場所を移動（いま：${esc(lot.storage_location||"未設定")}）</button>`+html;
};
window.qrSecondaryActions=qrSecondaryActions;
async function qrMoveLocationPage(q,msg=""){
  if(!canQrOperate()){alert("保管場所を移動できるのは管理者・青果社員です。");return qrLotDetail(q)}
  setScreen("qrMoveLocationPage",[q,msg]);
  pageShell("保管場所を移動","読み込み中",'<div class="card"><div class="notice">読み込んでいます。</div></div>');
  try{
    const lot=await qrFindLot(q);if(!lot)throw new Error("対象ロットが見つかりません");
    const cur=String(lot.storage_location||"").trim();
    const opts=QR_STORAGE_LOCATIONS.filter(n=>n!==cur).map(n=>`<option value="${esc(n)}">${esc(n)}</option>`).join("");
    pageShell("保管場所を移動",`${esc(lot.item_name||"")} / ${esc(lot.lot_no||"")}`,`${msg?`<div class="err">${esc(msg)}</div>`:""}${qrLotCard(lot,false)}<div class="card"><div><b>いまの保管場所：</b>${esc(cur||"未設定")}</div><label class="label" for="v1260MoveTo" style="margin-top:10px">移動先</label><select id="v1260MoveTo" class="input"><option value="">選択してください</option>${opts}</select><label class="label" for="v1260MoveMemo" style="margin-top:10px">メモ（任意）</label><input id="v1260MoveMemo" class="input" placeholder="例：第2冷蔵庫の空きへ"><div class="small" style="margin-top:8px">ロットまるごと移動します。数量は変わりません。移動は「場所移動」として履歴に残ります。</div><button class="btn blue" style="width:100%;margin-top:10px" ${seikaEventAttrs('click','v1260MoveLot',[String(lot.id),String(lot.qr_key||"")])}>移動する</button><button class="btn btn2" style="width:100%;margin-top:8px" ${seikaEventAttrs('click','qrLotDetail',[String(lot.qr_key||"")])}>やめる</button></div>`);
  }catch(e){pageShell("保管場所を移動","エラー",`<div class="err">${esc(e.message||e)}</div>`)}
}
async function v1260MoveLot(lotId,q){
  const to=String(document.getElementById("v1260MoveTo")?.value||""),memo=String(document.getElementById("v1260MoveMemo")?.value||"").trim();
  if(!to)return alert("移動先を選んでください。");
  if(!confirm(`保管場所を「${to}」へ移動しますか？`))return;
  try{
    v161ShowProcessing?.("保管場所を移動しています");
    const ans=await callRpc("move_qr_lot_location_v1260",{p_lot_id:lotId,p_to_location:to,p_memo:memo});
    if(!ans?.ok)throw new Error(ans?.message||"移動できませんでした");
    if(typeof v1204CacheReset==="function")v1204CacheReset();
    return qrLotDetail(q,`保管場所を「${ans.from_location||"未設定"}」から「${ans.to_location}」へ移動しました。`);
  }catch(e){
    const raw=String(e?.message||e);
    alert(/PGRST202|move_qr_lot_location_v1260/.test(raw)?"保管場所の移動がまだ準備されていません（SQL 009 の実行が必要です）。":raw);
  }finally{try{v161HideProcessing?.()}catch(_){}}
}

/* ③ 品質評価の確認：確認済みは担当の仕入れ担当者。管理者・青果社員は「確認しました」で自分の通知だけ消す */
let v1260MyReads=new Set();
async function v1260LoadMyReads(){
  if(!["admin","worker"].includes(db?.role)){v1260MyReads=new Set();return}
  try{const rows=await qrSelect("qr_quality_alert_reads_v1260","select=evaluation_id&limit=5000");v1260MyReads=new Set((rows||[]).map(r=>String(r.evaluation_id)))}catch(e){}
}
function v1260HasAssignedBuyer(x){return(x.buyers||[]).some(b=>b.can_acknowledge===true)}
function v1260ReadButton(x){
  if(!["admin","worker"].includes(db?.role)||x.acknowledged_at||!["review","bad"].includes(x.grade))return"";
  const id=String(x.id||"");
  if(v1260MyReads.has(id))return`<div class="small" style="grid-column:1/-1">あなたは確認しました（担当の仕入れ担当者の確認待ち）</div>`;
  return`<button type="button" class="btn btn2" ${seikaEventAttrs('click','v1260MarkRead',[id])}>確認しました（自分の通知を消す）</button>`;
}
const v1260QualityCardBase=v1140QualityCard;
v1140QualityCard=function(x){
  let html=v1260QualityCardBase.call(this,x);
  const extra=v1260ReadButton(x);
  if(extra){const i=html.lastIndexOf('</div><div id="v1103Photos_');if(i>=0)html=html.slice(0,i)+extra+html.slice(i)}
  if(!x.acknowledged_at&&["review","bad"].includes(x.grade)&&v1260HasAssignedBuyer(x))html=html.replace(`>${esc(v138T("未確認"))}</span>`,`>${esc(v138T("未確認"))}</span><span class="small" style="margin-left:6px">担当の仕入れ担当者が確認します</span>`);
  return html;
};
window.v1140QualityCard=v1140QualityCard;
const v1260LoadQualityListBase=v1103LoadQualityList;
v1103LoadQualityList=async function(...args){await v1260LoadMyReads();return v1260LoadQualityListBase.apply(this,args)};
window.v1103LoadQualityList=v1103LoadQualityList;
async function v1260MarkRead(id){
  try{
    const ans=await callRpc("mark_qr_quality_alert_read_v1260",{p_evaluation_id:id});
    if(!ans?.ok)throw new Error(ans?.message||"記録できませんでした");
    v1260MyReads.add(String(id));
    if(currentScreen==="v1103QualityListPage"&&typeof v1140RenderQualityList==="function")v1140RenderQualityList();
    else if(currentScreen==="home")home();
  }catch(e){const raw=String(e?.message||e);alert(/PGRST202|mark_qr_quality_alert_read_v1260/.test(raw)?"「確認しました」の保存先がまだ準備されていません（SQL 009 の実行が必要です）。":raw)}
}
v1143LoadQualityTask=async function(generation){
  if(!["admin","buyer","worker"].includes(db?.role))return;
  const render=html=>{if(generation!==v1143TodayTaskGeneration||currentScreen!=="home")return null;return document.getElementById("v1143QualityTask")};
  try{
    const ans=await callRpc("list_my_unacknowledged_low_quality_evaluations_v1103",{p_limit:100});
    if(!ans?.ok||!Array.isArray(ans.evaluations))throw new Error(ans?.message||"品質評価データの形式が不正です");
    const box=render(),taskRows=document.getElementById("v1143TodayTaskRows");if(!box||!taskRows)return;
    const rows=ans.evaluations;
    if(rows.length){
      document.getElementById("v1143TodayTaskEmpty")?.remove();
      const mine=rows.filter(r=>r.can_acknowledge).length;
      const label=db.role==="buyer"?"未確認の低評価（担当分）":"未確認の低評価";
      box.innerHTML=v1143TaskRow(label,rows.length,"qualityList","品質評価一覧を開く")+(db.role==="admin"&&mine?`<div class="small" style="margin-top:4px">うち担当未設定で管理者の確認が必要：${mine}件</div>`:"");
      return;
    }
    box.innerHTML="";if(!taskRows.querySelector("[data-v1143-task-action]"))taskRows.innerHTML=`<div id="v1143TodayTaskEmpty" class="small">${esc(v1143TaskText("現在、対応が必要な項目はありません"))}</div>`;
  }catch(e){
    const box=render();if(!box)return;
    box.innerHTML=`<div class="small err">品質評価情報を取得できません：${esc(typeof v161ErrorText==="function"?v161ErrorText(e):(e?.message||e))}</div><button class="btn blue" style="width:100%;margin-top:10px" data-seika-click-action="v1143RetryQualityTask" data-seika-click-args="%5B%5D">品質評価を再読み込み</button>`;
  }
};
window.v1143LoadQualityTask=v1143LoadQualityTask;

/* ④ 品質レポート（作り替え）：仕入先別・品目別・月別。ログインしている全員が閲覧可 */
let v1260QaState={period:"current",from:"",to:"",filter:"",data:null};
function v1260FiscalRange(offset=0){
  const t=todayKey(),y=Number(t.slice(0,4)),m=Number(t.slice(5,7)),fy=(m>=9?y:y-1)+offset;
  return{from:`${fy}-09-01`,to:`${fy+1}-08-31`,label:`${fy}年9月〜${fy+1}年8月`};
}
function v1260Pct(n,d){return d?Math.round(n/d*1000)/10:0}
function v1260PctText(n,d){return d?`${v1260Pct(n,d).toFixed(1)}%`:"—"}
function v1260ItemKey(name){try{return v1200QrCanonName(name)||name}catch(e){return name}}
function v1260Sum(rows){const s={good:0,review:0,bad:0};for(const r of rows){s.good+=Number(r.good||0);s.review+=Number(r.review||0);s.bad+=Number(r.bad||0)}s.n=s.good+s.review+s.bad;return s}
function v1260GroupBy(rows,keyFn){const m=new Map();for(const r of rows){const k=keyFn(r);if(!m.has(k))m.set(k,[]);m.get(k).push(r)}return m}
function v1260MonthLabel(m){return`${Number(m.slice(5,7))}月`}
function v1260MonthFull(m){return`${m.slice(0,4)}年${Number(m.slice(5,7))}月`}
function v1260Bar(s){
  if(!s.n)return"";
  const w=k=>v1260Pct(s[k],s.n);
  return`<div class="v1260Bar"><span style="width:${w("good")}%;background:#16a34a"></span><span style="width:${w("review")}%;background:#f59e0b"></span><span style="width:${w("bad")}%;background:#dc2626"></span></div>`;
}
function v1260Ratios(s){return`<div class="v1260Ratios"><span>良好 <b>${v1260PctText(s.good,s.n)}</b></span><span>要確認 <b>${v1260PctText(s.review,s.n)}</b></span><span>不良 <b>${v1260PctText(s.bad,s.n)}</b></span></div>`}
function v1260CautionMonths(rows,overallBad){
  const out=[];
  for(const[m,list]of v1260GroupBy(rows,r=>r.month)){const s=v1260Sum(list);if(s.n>=5&&s.bad>=1&&v1260Pct(s.bad,s.n)>=overallBad*2)out.push({month:m,...s})}
  return out.sort((a,b)=>a.month.localeCompare(b.month));
}
function v1260MonthLines(rows,caution){
  const set=new Set(caution.map(c=>c.month));
  return[...v1260GroupBy(rows,r=>r.month)].sort((a,b)=>a[0].localeCompare(b[0])).map(([m,list])=>{const s=v1260Sum(list);return`<div class="v1260MonthLine${set.has(m)?" v1260Warn":""}">${v1260MonthFull(m)} → 不良 <b>${v1260PctText(s.bad,s.n)}</b> <span class="small">（要確認＋不良 ${v1260PctText(s.review+s.bad,s.n)}・${s.n}件）</span>${set.has(m)?' <span class="v1260WarnBadge">要注意</span>':""}</div>`}).join("");
}
function v1260GroupCards(rows,keyFn,overallBad,sub){
  const groups=[...v1260GroupBy(rows,keyFn)].map(([k,list])=>({k,list,s:v1260Sum(list)})).sort((a,b)=>b.s.n-a.s.n||a.k.localeCompare(b.k,"ja"));
  const f=v1260Norm(v1260QaState.filter);
  return groups.filter(g=>!f||v1260Norm(g.k).includes(f)||g.list.some(r=>v1260Norm(r.supplier+r.cooperative_name+r.item_name).includes(f))).map(g=>{
    const caution=v1260CautionMonths(g.list,overallBad);
    const subHtml=sub?[...v1260GroupBy(g.list,sub.key)].map(([sk,sl])=>({sk,s:v1260Sum(sl)})).sort((a,b)=>b.s.n-a.s.n).map(x=>`<div class="v1260SubLine"><b>${esc(x.sk)}</b> <span class="small">${x.s.n}件</span> 良好 ${v1260PctText(x.s.good,x.s.n)} ／ 要確認 ${v1260PctText(x.s.review,x.s.n)} ／ 不良 ${v1260PctText(x.s.bad,x.s.n)}</div>`).join(""):"";
    return`<div class="card v1260Group${caution.length?" v1260GroupWarn":""}"><div class="itemHead"><div><b style="font-size:17px">${esc(g.k)}</b><div class="small">評価 ${g.s.n}件</div></div>${caution.length?`<span class="v1260WarnBadge">要注意 ${caution.map(c=>v1260MonthLabel(c.month)).join("・")}</span>`:""}</div>${v1260Ratios(g.s)}${v1260Bar(g.s)}<details style="margin-top:8px"><summary class="small" style="cursor:pointer">月別${sub?`・${sub.label}`:""}を見る</summary><div style="margin-top:6px">${v1260MonthLines(g.list,caution)}</div>${subHtml?`<div style="margin-top:8px"><b class="small">${sub.label}</b>${subHtml}</div>`:""}</details></div>`;
  }).join("")||'<div class="card"><div class="notice">該当するデータがありません。</div></div>';
}
function v1260RenderQa(tab){
  const host=document.getElementById("v1260QaResult");if(!host)return;
  const d=v1260QaState.data;if(!d)return;
  tab=tab||v1260QaState.tab||"supplier";v1260QaState.tab=tab;
  const rows=(d.rows||[]).map(r=>({...r,item_name:v1260ItemKey(r.item_name)}));
  const all=v1260Sum(rows),overallBad=v1260Pct(all.bad,all.n);
  if(!all.n){host.innerHTML='<div class="card"><div class="notice">この期間の品質評価はまだありません。</div></div>';return}
  const cautions=[];
  for(const[sup,list]of v1260GroupBy(rows,r=>r.supplier))for(const c of v1260CautionMonths(list,overallBad))cautions.push({...c,supplier:sup});
  cautions.sort((a,b)=>b.month.localeCompare(a.month)||v1260Pct(b.bad,b.n)-v1260Pct(a.bad,a.n));
  const monthly=[...v1260GroupBy(rows,r=>r.month)].sort((a,b)=>a[0].localeCompare(b[0])).map(([m,list])=>{const s=v1260Sum(list),p=v1260Pct(s.bad,s.n);return`<div class="v1260MonthRow"><span class="v1260MonthName">${v1260MonthFull(m)}</span><span class="v1260MonthTrack"><span style="width:${Math.min(100,p*4)}%"></span></span><b>${v1260PctText(s.bad,s.n)}</b><span class="small">要確認＋不良 ${v1260PctText(s.review+s.bad,s.n)}・${s.n}件</span></div>`}).join("");
  const tabs=[["supplier","仕入先別"],["item","品目別"],["month","月別"]].map(([k,l])=>`<button class="btn ${tab===k?"blue":"btn2"}" ${seikaEventAttrs('click','v1260RenderQa',[k])}>${l}</button>`).join("");
  const body=tab==="month"?`<div class="card"><b>月別の不良率</b><div class="small" style="margin:4px 0 8px">入荷日の月で集計。棒は不良率（25%で満杯）。</div>${monthly}</div>`
    :tab==="item"?v1260GroupCards(rows,r=>r.item_name,overallBad,{key:r=>r.supplier,label:"仕入先ごと"})
    :v1260GroupCards(rows,r=>r.supplier,overallBad,{key:r=>r.cooperative_name,label:"単協名ごと"});
  host.innerHTML=`<div class="card"><b>全体（${esc(d.label||"")}）</b><div class="small">評価 ${all.n}件</div>${v1260Ratios(all)}${v1260Bar(all)}</div>`
    +`<div class="card"><b>要注意（仕入先×月）</b><div class="small" style="margin:4px 0 8px">その月の不良率が全体平均（${overallBad.toFixed(1)}%）の2倍以上、かつ評価5件以上</div>${cautions.length?cautions.map(c=>`<div class="v1260MonthLine v1260Warn">${v1260MonthFull(c.month)}　<b>${esc(c.supplier)}</b>　不良 ${v1260PctText(c.bad,c.n)}（${c.n}件中${c.bad}件）</div>`).join(""):'<div class="small">いまは該当がありません。</div>'}</div>`
    +`<div class="row" style="margin:6px 0">${tabs}</div>`
    +(tab!=="month"?`<div class="card"><label class="label" for="v1260QaFilter">仕入先・単協名・品目で絞り込み</label><input id="v1260QaFilter" class="input" value="${esc(v1260QaState.filter)}" placeholder="例：レタス"><button class="btn btn2" style="width:100%;margin-top:8px" ${seikaEventAttrs('click','v1260QaApplyFilter',[])}>絞り込む</button></div>`:"")
    +body;
}
function v1260QaApplyFilter(){v1260QaState.filter=String(document.getElementById("v1260QaFilter")?.value||"").trim();v1260RenderQa()}
async function v1260RunQa(){
  const host=document.getElementById("v1260QaResult");if(!host)return;
  const period=document.getElementById("v1260QaPeriod")?.value||"current";v1260QaState.period=period;
  let from,to,label;
  if(period==="custom"){from=document.getElementById("v1260QaFrom")?.value;to=document.getElementById("v1260QaTo")?.value;label=`${from}〜${to}`;if(!from||!to||from>to)return alert("開始日と終了日を正しく入れてください。")}
  else{const r=v1260FiscalRange(period==="previous"?-1:0);from=r.from;to=r.to;label=(period==="previous"?"前年度 ":"今年度 ")+r.label}
  v1260QaState.from=from;v1260QaState.to=to;
  host.innerHTML='<div class="card"><div class="notice">集計中</div></div>';
  try{
    const ans=await callRpc("get_quality_improvement_analysis_v1260",{p_from:from,p_to:to});
    if(!ans?.ok)throw new Error(ans?.message||"集計できませんでした");
    v1260QaState.data={...ans,label};v1260RenderQa();
  }catch(e){const raw=String(e?.message||e);host.innerHTML=`<div class="err">${esc(/PGRST202|get_quality_improvement_analysis_v1260/.test(raw)?"品質レポートの集計がまだ準備されていません（SQL 009 の実行が必要です）。":raw)}</div>`}
}
function v1260QaPeriodChanged(){const c=document.getElementById("v1260QaCustom");if(c)c.style.display=document.getElementById("v1260QaPeriod")?.value==="custom"?"":"none"}
v136SupplierQualityPage=function(){
  setScreen("v136SupplierQualityPage");
  if(!db?.user)return home();
  const p=v1260QaState.period,cur=v1260FiscalRange(0),prev=v1260FiscalRange(-1);
  pageShell("品質レポート","品質評価を仕入れ改善に使う（仕入先別・品目別・月別）",`<div class="card"><label class="label" for="v1260QaPeriod">期間</label><select id="v1260QaPeriod" class="input" ${seikaEventAttrs('change','v1260QaPeriodChanged',[])}><option value="current" ${p==="current"?"selected":""}>今年度（${cur.label}）</option><option value="previous" ${p==="previous"?"selected":""}>前年度（${prev.label}）</option><option value="custom" ${p==="custom"?"selected":""}>期間を指定</option></select><div id="v1260QaCustom" class="row" style="margin-top:8px;${p==="custom"?"":"display:none"}"><div><label class="label" for="v1260QaFrom">開始日</label><input id="v1260QaFrom" type="date" class="input" value="${esc(v1260QaState.from||cur.from)}"></div><div><label class="label" for="v1260QaTo">終了日</label><input id="v1260QaTo" type="date" class="input" value="${esc(v1260QaState.to||todayKey())}"></div></div><button class="btn blue" style="width:100%;margin-top:10px" ${seikaEventAttrs('click','v1260RunQa',[])}>集計する</button><div class="small" style="margin-top:8px">ロット1つにつき最新の評価1件で数えます（訂正した評価は訂正後）。月は入荷日で分けます。</div></div><div id="v1260QaResult"></div>`);
  v1260RunQa();
};
window.v136SupplierQualityPage=v136SupplierQualityPage;
function v1260InjectQualityButtons(tries=0){
  if(currentScreen!=="qrHome")return;
  const box=document.querySelector(".homePrimary"),ql=box&&box.querySelector('[data-seika-click-action="v1103QualityListPage"]');
  if(!box||!ql){if(tries<40)setTimeout(()=>v1260InjectQualityButtons(tries+1),100);return}
  if(document.getElementById("v1260QaBtn"))return;
  const b=document.createElement("button");b.id="v1260QaBtn";b.type="button";b.className="btn homeBtnQualityReport";
  b.setAttribute("data-seika-click-action","v136SupplierQualityPage");b.setAttribute("data-seika-click-args","%5B%5D");
  b.innerHTML='品質レポート<br><span style="font-size:15px;font-weight:800">仕入先・品目・月ごとの良品率</span>';
  ql.parentNode.insertBefore(b,ql.nextSibling);
}
const v1260QrHomeBase=qrHome;
qrHome=async function(...args){const r=await v1260QrHomeBase.apply(this,args);v1260InjectQualityButtons();return r};
window.qrHome=qrHome;
const v1260QualityListPageBase=v1103QualityListPage;
v1103QualityListPage=async function(...args){
  const r=await v1260QualityListPageBase.apply(this,args);
  const s=document.getElementById("v1103QualitySummary");
  if(s&&!document.getElementById("v1260QaFromList"))(document.querySelector("main.wrap")||s).insertAdjacentHTML("afterbegin",`<button id="v1260QaFromList" class="btn homeBtnQualityReport" style="width:100%;margin-bottom:10px" ${seikaEventAttrs('click','v136SupplierQualityPage',[])}>品質レポート（仕入先・品目・月ごとの良品率）</button>`);
  return r;
};
window.v1103QualityListPage=v1103QualityListPage;
(function(){
  const st=document.createElement("style");
  st.textContent=`.homeBtnQrMove{background:linear-gradient(90deg,#334155 0%,#475569 52%,#94a3b8 100%) !important;color:#fff !important;border-color:transparent !important;}
.v1260Bar{display:flex;height:12px;border-radius:999px;overflow:hidden;background:#e5e7eb;margin-top:6px}
.v1260Bar span{display:block;height:100%}
.v1260Ratios{display:flex;flex-wrap:wrap;gap:12px;margin-top:6px}
.v1260Ratios span:nth-child(1) b{color:#15803d}.v1260Ratios span:nth-child(2) b{color:#b45309}.v1260Ratios span:nth-child(3) b{color:#b91c1c}
.v1260MonthLine{padding:5px 0;border-bottom:1px dashed #e5e7eb}
.v1260Warn{color:#991b1b;font-weight:800}
.v1260WarnBadge{background:#dc2626;color:#fff;border-radius:999px;padding:3px 9px;font-size:12px;font-weight:900;white-space:nowrap}
.v1260GroupWarn{border:2px solid #fca5a5}
.v1260SubLine{padding:4px 0;font-size:13px;border-bottom:1px solid #f1f5f9}
.v1260MonthRow{display:grid;grid-template-columns:96px 1fr 56px;gap:8px;align-items:center;padding:6px 0;border-bottom:1px solid #f1f5f9}
.v1260MonthRow .small{grid-column:1/-1;margin-top:-4px}
.v1260MonthTrack{height:12px;background:#f1f5f9;border-radius:999px;overflow:hidden}
.v1260MonthTrack span{display:block;height:100%;background:#dc2626}`;
  document.head.appendChild(st);
  try{
    if(typeof V198_GUIDE_SECTIONS!=="undefined"){
      V198_GUIDE_SECTIONS.v1260QualityAnalysis={title:"品質レポート・保管場所の移動",where:"ホーム → QR在庫管理 → 品質レポート ／ QRロット詳細 → 保管場所を移動",
        steps:["品質レポートでは、品質評価を仕入先別・品目別・月別に「良好・要確認・不良」の割合で確認できます。月は入荷日で分けます。",
               "その月の不良率が全体平均の2倍以上（評価5件以上）の仕入先は「要注意」と表示します。",
               "品質評価の「確認済み」は担当の仕入れ担当者が付けます。管理者・青果社員は「確認しました」を押すと自分の通知だけ消えます。",
               "片岡冷蔵庫から第2・第3冷蔵庫などへ移したときは、QRロットの「保管場所を移動」で移動先を選びます（ロットまるごと・履歴に残ります）。",
               "QRロット一覧・検索では、仕入先・単協名の一部を入れて探せます。"],
        check:"要注意の仕入先は、仕入れ担当者が産地・時期を確認します。",
        caution:"保管場所の移動は数量を変えません。一部だけ移す場合は対応していません。"};
      if(typeof V198_ROLE_ADD!=="undefined")for(const k of Object.keys(V198_ROLE_ADD))if(Array.isArray(V198_ROLE_ADD[k])&&!V198_ROLE_ADD[k].includes("v1260QualityAnalysis"))V198_ROLE_ADD[k].push("v1260QualityAnalysis");
    }
  }catch(e){}
})();


/* ===== v1.199-c33 QRホームの整理・品質レポートの配色・月次Excelの作成済み記録の再試行 ===== */
function v1270IsNetErr(e){return/Load failed|Failed to fetch|NetworkError|network connection was lost/i.test(String(e?.message||e))}
async function v1270Retry(fn,waits=[800,1500,3000,5000]){
  for(let i=0;;i++){
    try{return await fn()}catch(e){if(!v1270IsNetErr(e)||i>=waits.length)throw e;await new Promise(r=>setTimeout(r,waits[i]))}
  }
}
const v1270RecordCreatedBase=v1101RecordCreated;
v1101RecordCreated=async function(...args){await new Promise(r=>setTimeout(r,600));return v1270Retry(()=>v1270RecordCreatedBase.apply(this,args))};
window.v1101RecordCreated=v1101RecordCreated;
const v1270LoadArchivesBase=v1101LoadArchives;
v1101LoadArchives=function(...args){return v1270Retry(()=>v1270LoadArchivesBase.apply(this,args))};
window.v1101LoadArchives=v1101LoadArchives;
const v1270QrHomeBase=qrHome;
qrHome=async function(...args){
  const r=await v1270QrHomeBase.apply(this,args);
  const rm=()=>document.getElementById("v199QrExcelButtonHome")?.remove();
  rm();setTimeout(rm,300);setTimeout(rm,1200);
  return r;
};
window.qrHome=qrHome;
(function(){const st=document.createElement("style");st.textContent=`.homeBtnQualityReport{background:linear-gradient(90deg,#065f46 0%,#059669 52%,#6ee7b7 100%) !important;color:#fff !important;border-color:transparent !important;}`;document.head.appendChild(st)})();

/* ===== v1.199-c34 仕入先・単協名の候補を全員で共有（追加・非表示・削除・名称修正）／QRホームとメニューに入口 ===== */
let v1280Cache=null,v1280CacheAt=0;
async function v1280Load(force=false){
  if(!force&&v1280Cache&&Date.now()-v1280CacheAt<20000)return v1280Cache;
  try{
    const rows=await qrSelect("qr_party_names_v1280","select=kind,norm,name,status&limit=5000");
    const c={supplier:new Map(),cooperative:new Map()};
    for(const r of rows||[])if(c[r.kind])c[r.kind].set(qrNormalizeName(r.name),{name:r.name,status:r.status});
    v1280Cache=c;v1280CacheAt=Date.now();
  }catch(e){if(force||!v1280Cache)v1280Cache=null}
  return v1280Cache;
}
async function v1280Candidates(kind,limit=300){
  qrEnsureMasters();
  const isSup=kind!=="cooperative",col=isSup?"supplier":"cooperative_name";
  const t=await v1280Load(),map=t?t[isSup?"supplier":"cooperative"]:null;
  const legacyHidden=new Set((isSup?db.qrSupplierHidden:db.qrCooperativeHidden).map(qrNormalizeName));
  let arr=[];
  if(map)for(const v of map.values())if(v.status==="active")arr.push(v.name);
  arr=arr.concat(isSup?db.qrSuppliers:db.qrCooperatives);
  try{const rows=await qrSelect("qr_lots",`select=${col}&${col}=not.is.null&order=created_at.desc&limit=${limit}`);arr=arr.concat(rows.map(r=>r[col]).filter(Boolean))}catch(e){}
  const seen=new Set,out=[];
  for(const raw of arr){
    const v=String(raw||"").trim(),k=qrNormalizeName(v);
    if(!k||seen.has(k))continue;seen.add(k);
    const rec=map&&map.get(k);
    if(rec?rec.status!=="active":legacyHidden.has(k))continue;
    out.push(rec?rec.name:v);
  }
  return out;
}
async function v1280HiddenNames(kind){
  const t=await v1280Load(),map=t?t[kind!=="cooperative"?"supplier":"cooperative"]:null;
  if(!map){qrEnsureMasters();return[...(kind!=="cooperative"?db.qrSupplierHidden:db.qrCooperativeHidden)]}
  return[...map.values()].filter(v=>v.status==="hidden").map(v=>v.name).sort((a,b)=>a.localeCompare(b,"ja"));
}
qrSupplierList=async function(){return(await v1280Candidates("supplier")).slice(0,200)};
window.qrSupplierList=qrSupplierList;
qrCooperativeList=async function(){return(await v1280Candidates("cooperative")).slice(0,200)};
window.qrCooperativeList=qrCooperativeList;
window.v1208IsHidden=(kind,name)=>{const m=v1280Cache&&v1280Cache[kind!=="cooperative"?"supplier":"cooperative"],r=m&&m.get(qrNormalizeName(name));return r?r.status!=="active":false};

async function v1280Set(kind,name,status,renamedTo=null){
  const ans=await callRpc("set_qr_party_name_v1280",{p_kind:kind!=="cooperative"?"supplier":"cooperative",p_name:name,p_status:status,p_renamed_to:renamedTo});
  if(!ans?.ok)throw new Error(ans?.message||"保存できませんでした");
  await v1280Load(true);
}
async function v1280Do(kind,fn,doneMsg){
  try{v161ShowProcessing?.("保存しています");await fn();v1208CandidatePage(kind,doneMsg)}
  catch(e){const raw=String(e?.message||e);alert(/PGRST202|PGRST205|set_qr_party_name_v1280|qr_party_names_v1280/.test(raw)?"候補の共有がまだ準備されていません（SQL 010 の実行が必要です）。":raw)}
  finally{try{v161HideProcessing?.()}catch(_){}}
}
v1208CandidatePage=async function(kind="supplier",msg=""){
  setScreen("v1208CandidatePage",[kind,msg]);
  if(!canQrOperate()){alert("仕入先・単協名の候補を編集できるのは管理者・青果社員です");return qrHome()}
  const isSup=kind!=="cooperative",label=isSup?"仕入先":"単協名";
  pageShell("仕入先・単協マスタ","読み込み中",'<div class="card"><div class="notice">読み込んでいます。</div></div>');
  const t=await v1280Load(true);
  const shown=await v1280Candidates(kind,1000),hid=await v1280HiddenNames(kind);
  const map=t?t[isSup?"supplier":"cooperative"]:null;
  const btn=(cls,action,args,text)=>`<button class="btn ${cls}" style="padding:6px 12px" ${seikaEventAttrs('click',action,args)}>${text}</button>`;
  const tabs=`<div class="card"><div class="row"><button class="btn ${isSup?"blue":"btn2"}" ${seikaEventAttrs('click','v1208CandidatePage',["supplier",""])}>仕入先</button><button class="btn ${isSup?"btn2":"blue"}" ${seikaEventAttrs('click','v1208CandidatePage',["cooperative",""])}>単協名</button></div>${t?"":'<div class="err" style="margin-top:8px">共有の準備がまだです（SQL 010 の実行が必要です）。いまは表示のみです。</div>'}</div>`;
  const add=`<div class="card"><b>${label}を追加</b><div class="small">登録すると、全員の入力候補に出ます。</div><input id="v1208AddName" class="input" placeholder="例：${isSup?"中央園芸":"茨城中央"}" autocomplete="off"><button class="btn blue" style="width:100%;margin-top:10px" ${seikaEventAttrs('click','v1208AddCandidate',[kind])}>追加する</button></div>`;
  const row=(n,btns,note="")=>`<div style="display:flex;align-items:center;gap:6px;padding:7px 0;border-bottom:1px solid #eee;flex-wrap:wrap"><div style="flex:1;min-width:120px">${esc(n)}${note}</div>${btns}</div>`;
  const list=`<div class="card"><b>候補に出る${label}（${shown.length}件）</b><div class="small">「削除」は候補から完全に消します（また出てくることはありません）。「非表示」はあとで戻せます。どちらも過去の記録は消えません。</div>${shown.length?shown.map(n=>row(n,btn("btn2","v1208HideCandidate",[kind,n],"非表示")+btn("btn2","v1208RenameCandidate",[kind,n],"名称修正")+btn("danger","v1280DeleteCandidate",[kind,n],"削除"),map&&map.get(qrNormalizeName(n))?.status==="active"?' <span class="small">（登録済み）</span>':' <span class="small">（過去の入力）</span>')).join(""):'<div class="small">候補がありません。</div>'}</div>`;
  const hiddenBox=`<div class="card"><b>非表示にした${label}（${hid.length}件）</b>${hid.length?hid.map(n=>row(n,btn("btn2","v1208ShowCandidate",[kind,n],"戻す")+btn("danger","v1280DeleteCandidate",[kind,n],"削除"))).join(""):'<div class="small">ありません。</div>'}</div>`;
  pageShell("仕入先・単協マスタ","入力候補の追加・非表示・削除・名称修正（全員の端末に反映）",okHtml(msg)+tabs+add+list+hiddenBox);
};
window.v1208CandidatePage=v1208CandidatePage;
v1208AddCandidate=function(kind){
  const name=String(document.getElementById("v1208AddName")?.value||"").trim();
  if(!name)return alert("名称を入力してください");
  return v1280Do(kind,()=>v1280Set(kind,name,"active"),`「${name}」を追加しました`);
};
v1208HideCandidate=function(kind,name){
  if(!confirm(`「${name}」を候補から非表示にします。\nあとで戻せます。過去の記録は消えません。`))return;
  return v1280Do(kind,()=>v1280Set(kind,name,"hidden"),`「${name}」を非表示にしました`);
};
v1208ShowCandidate=function(kind,name){return v1280Do(kind,()=>v1280Set(kind,name,"active"),`「${name}」を候補に戻しました`)};
function v1280DeleteCandidate(kind,name){
  if(!confirm(`「${name}」を候補から削除します。\n全員の端末で候補に出なくなります。過去のQRロットの記録は消えません。\nよろしいですか？`))return;
  return v1280Do(kind,()=>v1280Set(kind,name,"deleted"),`「${name}」を削除しました`);
}
v1208RenameCandidate=function(kind,name){
  const next=prompt(`「${name}」の正しい名称を入力してください。\n元の名称は候補から削除され、正しい名称が候補に出ます。`,name);
  if(next===null)return;
  const fixed=String(next).trim();if(!fixed)return alert("名称が空です");
  if(qrNormalizeName(fixed)===qrNormalizeName(name))return v1280Do(kind,()=>v1280Set(kind,fixed,"active"),`「${fixed}」に修正しました`);
  return v1280Do(kind,()=>v1280Set(kind,name,"deleted",fixed),`「${name}」を「${fixed}」に修正しました`);
};
window.v1208AddCandidate=v1208AddCandidate;window.v1208HideCandidate=v1208HideCandidate;window.v1208ShowCandidate=v1208ShowCandidate;window.v1208RenameCandidate=v1208RenameCandidate;window.v1280DeleteCandidate=v1280DeleteCandidate;

function v1280InjectHome(tries=0){
  if(currentScreen!=="qrHome")return;
  document.getElementById("v1208CandEntry")?.remove();
  if(!canQrOperate())return;
  const box=document.querySelector(".homePrimary"),dest=box&&box.querySelector('[data-seika-click-action="v194DestinationsPage"]');
  if(!box){if(tries<40)setTimeout(()=>v1280InjectHome(tries+1),100);return}
  if(document.getElementById("v1280PartyBtn"))return;
  const b=document.createElement("button");b.id="v1280PartyBtn";b.type="button";b.className="btn homeBtnParty";
  b.setAttribute("data-seika-click-action","v1208CandidatePage");b.setAttribute("data-seika-click-args",encodeURIComponent(JSON.stringify(["supplier",""])));
  b.innerHTML='仕入先・単協マスタ<br><span style="font-size:15px;font-weight:800">入力候補の追加・削除・名称修正</span>';
  if(dest)dest.parentNode.insertBefore(b,dest.nextSibling);else box.appendChild(b);
}
const v1280QrHomeBase=qrHome;
qrHome=async function(...args){const r=await v1280QrHomeBase.apply(this,args);v1280InjectHome();setTimeout(()=>document.getElementById("v1208CandEntry")?.remove(),300);return r};
window.qrHome=qrHome;
const v1280MenuBase=accountMenu;
accountMenu=function(...args){
  const r=v1280MenuBase.apply(this,args);
  const add=()=>{const m=document.querySelector(".menu");if(!m||!canQrOperate()||document.getElementById("v1280MenuParty"))return;
    m.insertAdjacentHTML("afterbegin",`<button id="v1280MenuParty" class="btn btn2" ${seikaEventAttrs('click','v1208CandidatePage',["supplier",""])}>仕入先・単協マスタ（入力候補）</button>`)};
  add();setTimeout(add,300);
  return r;
};
window.accountMenu=accountMenu;
(function(){const st=document.createElement("style");st.textContent=`.homeBtnParty{background:linear-gradient(90deg,#3f6212 0%,#65a30d 52%,#bef264 100%) !important;color:#fff !important;border-color:transparent !important;}`;document.head.appendChild(st)})();

/* ===== v1.199-c35 残り0のまま90日を過ぎたQRロットを一覧・検索の通常表示から外す（過去のロットも含める切替） ===== */
const V1290_OLD_DAYS=90;
let v1290IncludeOld=false;
function v1290Cutoff(){return new Date(Date.now()-V1290_OLD_DAYS*86400000).toISOString()}
function v1290OldQuery(stock){
  if(stock==="inStock"||v1290IncludeOld)return"";
  return`&and=${encodeURIComponent(`(or(current_qty.gt.0,updated_at.gte.${v1290Cutoff()}))`)}`;
}
function v1290OldBar(){
  const s=qrLotListState||{};
  if(s.stockFilter==="inStock")return"";
  return`<div class="card"><label style="display:flex;align-items:center;gap:10px;font-weight:800"><input type="checkbox" id="v1290IncludeOld" style="width:22px;height:22px" ${v1290IncludeOld?"checked":""} ${seikaEventAttrs('change','v1290ToggleOld',[])}>過去のロットも含める</label><div class="small" style="margin-top:4px">${v1290IncludeOld?"在庫0のまま90日以上たったロットも表示しています。":"在庫0のまま90日以上動きのないロットは表示していません（記録は消えていません）。"}</div></div>`;
}
function v1290ToggleOld(){
  v1290IncludeOld=!!document.getElementById("v1290IncludeOld")?.checked;
  const s=qrLotListState;return qrLotListPage(s.selectedItem,s.sortOrder,s.stockFilter,100,!!s.alertOnly);
}
window.v1290ToggleOld=v1290ToggleOld;
try{
  if(typeof V198_GUIDE_SECTIONS!=="undefined"&&V198_GUIDE_SECTIONS.v1260QualityAnalysis){
    V198_GUIDE_SECTIONS.v1260QualityAnalysis.steps.push("QRロット一覧・検索で「在庫なし」「すべて」を選んだとき、在庫0のまま90日以上動きのないロットは表示しません。見たいときは「過去のロットも含める」にチェックを入れます。");
  }
}catch(e){}



/* ===== v1.199-c36 ①保管期限超過の強い確認・時期による特別期間 ②品目一覧の全件表示・1000件上限の点検 ===== */

/* --- ② サーバーは1回に1000件までしか返さないため、1000件を超える読み込みは分けて全部読む --- */
const V1300_PAGE=1000;
const v1300SelectBase=qrSelect;
qrSelect=async function(table,query="select=*"){
  const q=String(query||"");
  const m=q.match(/(?:^|&)limit=(\d+)(?:&|$)/);
  const want=m?Number(m[1]):0;
  let rows;
  if(want>V1300_PAGE&&!/(?:^|&)offset=/.test(q)){
    let base=q.replace(/(^|&)limit=\d+(?=&|$)/,"$1").replace(/&&+/g,"&").replace(/^&|&$/g,"");
    if(!/(?:^|&)order=/.test(base)&&/^(qr_lots|qr_lot_movements)$/.test(table))base+=(base?"&":"")+"order=id.asc";
    rows=[];
    for(let off=0;off<want;off+=V1300_PAGE){
      const n=Math.min(V1300_PAGE,want-off);
      const page=await v1300SelectBase(table,`${base}&limit=${n}&offset=${off}`);
      if(!Array.isArray(page))break;
      rows.push(...page);
      if(page.length<n)break;
    }
  }else rows=await v1300SelectBase(table,query);
  return rows;
};
window.qrSelect=qrSelect;

/* QR在庫処理の品目一覧：在庫のあるロットだけをサーバーに頼み、全部の品目を出す */
v1156LoadQrSearchItems=async function(selectedItem='',autoSearch=false){
  const select=document.getElementById('qrManualItem');
  if(!select)return;
  try{
    const lots=await qrSelect('qr_lots','select=item_name,current_qty&active=eq.true&current_qty=gt.0&order=item_name.asc&limit=20000');
    const names=[...new Set(lots.filter(l=>Number(l.current_qty||0)>0).map(v1156QrItemName).filter(Boolean))].sort((a,b)=>a.localeCompare(b,'ja'));
    select.innerHTML=`<option value="">品目を選択してください</option>${names.map(name=>`<option value="${esc(name)}" ${name===selectedItem?'selected':''}>${esc(name)}</option>`).join('')}`;
    select.disabled=false;
    if(selectedItem&&!names.includes(selectedItem))select.insertAdjacentHTML('beforeend',`<option value="${esc(selectedItem)}" selected>${esc(selectedItem)}</option>`);
    if(autoSearch&&selectedItem)await qrRunManualSearch(v1156QrSearchState.kind);
  }catch(e){
    select.innerHTML='<option value="">品目を取得できませんでした</option>';
    const box=document.getElementById('qrManualResults');if(box)box.innerHTML=`<div class="err">品目一覧を取得できませんでした。${esc(e.message||e)}</div>`;
  }
};
window.v1156LoadQrSearchItems=v1156LoadQrSearchItems;

/* --- ① 保管期限を過ぎたものを使うときの、画面いっぱいの確認 --- */
let v1300GuardBypass=false;
function v1300StrongConfirm(lot,info,what,opt={}){
  return new Promise(resolve=>{
    document.getElementById("v1300Guard")?.remove();
    const can=v1250CanConfirm(),over=Math.max(0,info.elapsed-info.limit);
    const d=String(lot.received_date||"").replaceAll("-","/");
    const box=document.createElement("div");
    box.id="v1300Guard";box.className="v1300Guard";box.setAttribute("role","alertdialog");box.setAttribute("aria-modal","true");
    box.innerHTML=`<div class="v1300GuardIn"><div class="v1300GuardHead">${esc(opt.head||"保管期限を過ぎています")}</div>
<div class="v1300GuardItem">${esc(lot.item_name||"")}</div>
<div class="v1300GuardNum">入荷から <b>${esc(info.elapsed)}日</b>（目安 ${esc(info.limit)}日）<br><span>${over>0?`目安より ${esc(over)}日 超過`:"今日が保管目安の日数です"}</span></div>
<div class="v1300GuardSub">ロット ${esc(lot.lot_no||lot.qr_key||"")}${d?` ／ 入荷日 ${esc(d)}`:""}</div>
${can?`<div class="v1300GuardAsk">${esc(opt.ask||"実物を見て、使える品質か確認してください。")}<br>確認した人の名前が記録されます。</div>
<label class="v1300GuardChk"><input type="checkbox" id="v1300GuardChk"> 実物を確認し、使える品質であることを確認しました</label>
<div class="v1300GuardBtns"><button type="button" class="btn v1300GuardNo" id="v1300GuardNo">やめる</button><button type="button" class="btn v1300GuardYes" id="v1300GuardYes" disabled>${esc(opt.yes||`確認して${what}する`)}</button></div>`
:`<div class="v1300GuardAsk">${esc(what)}できません。青果社員に相談してください。</div><div class="v1300GuardBtns"><button type="button" class="btn v1300GuardNo" id="v1300GuardNo" style="grid-column:1/-1">閉じる</button></div>`}</div>`;
    document.body.appendChild(box);
    const done=v=>{box.remove();resolve(v)};
    box.querySelector("#v1300GuardNo").addEventListener("click",()=>done(false));
    const chk=box.querySelector("#v1300GuardChk"),yes=box.querySelector("#v1300GuardYes");
    if(chk&&yes){chk.addEventListener("change",()=>{yes.disabled=!chk.checked});yes.addEventListener("click",()=>{if(chk.checked)done(true)})}
    setTimeout(()=>box.querySelector("#v1300GuardNo")?.focus(),50);
  });
}
async function v1300GuardUseAsync(lot,what){
  const info=v1250Info(lot);
  if(!info||info.effective<5)return true;
  const ok=await v1300StrongConfirm(lot,info,what);
  if(!ok)return false;
  callRpc("confirm_qr_lot_storage_check_v1250",{p_lot_id:String(lot.id),p_note:`使用不可/保留を確認して${what}`}).catch(e=>console.warn("[保管期間アラート] 確認記録を保存できません",e));
  return true;
}
const v1300GuardSyncBase=v1250GuardUse;
v1250GuardUse=function(lot,what){if(v1300GuardBypass)return true;return v1300GuardSyncBase(lot,what)};
window.v1250GuardUse=v1250GuardUse;
const v1300AddTrimBase=v195AddTrimLotObject;
v195AddTrimLotObject=function(lot){
  if(v1300GuardBypass||!lot)return v1300AddTrimBase.apply(this,arguments);
  const info=v1250Info(lot);
  if(!info||info.effective<5)return v1300AddTrimBase.apply(this,arguments);
  if(v1115Trimming.lots.some(x=>x.qrKey===lot.qr_key))throw new Error('このQRロットは追加済みです');
  v1300GuardUseAsync(lot,"使用原料に追加").then(ok=>{
    if(!ok)return;
    v1300GuardBypass=true;
    try{v1300AddTrimBase(lot);v1115RenderTrimming()}catch(e){alert(e.message||'ロットを追加できませんでした')}
    finally{v1300GuardBypass=false}
  });
};
window.v195AddTrimLotObject=v195AddTrimLotObject;

/* --- ① 時期による特別期間（毎年くり返す・入荷日で判定） --- */
let v1300Seasons=[],v1300SeasonsAt=0,v1300SeasonSource="none";
async function v1300LoadSeasons(force=false){
  if(!force&&Date.now()-v1300SeasonsAt<300000)return v1300Seasons;
  try{
    const rows=await qrSelect("qr_storage_limit_seasons_v1300","select=id,item_name,start_md,end_md,limit_days,note,updated_by_name,updated_at&order=item_name.asc,start_md.asc");
    v1300Seasons=Array.isArray(rows)?rows:[];v1300SeasonSource="db";
  }catch(e){v1300Seasons=[];v1300SeasonSource="none"}
  v1300SeasonsAt=Date.now();
  return v1300Seasons;
}
function v1300CanonKey(name){
  const raw=String(name||"").trim();if(!raw)return"";
  const n=qrNormalizeName(raw),plain=qrNormalizeName(raw.replace(/[（(][^）)]*[）)]/g,""));
  const alias={};
  for(const[canon,list]of Object.entries(V1250_ALIASES))for(const a of list)alias[qrNormalizeName(a)]=qrNormalizeName(canon);
  if(typeof v1200QrIsPotatoName==="function"&&v1200QrIsPotatoName(raw))return qrNormalizeName(v1250PotatoName);
  for(const k of[n,plain]){if(alias[k])return alias[k];if(V1250_LIMIT_MAP.has(k))return k}
  const hit=V1250_LIMIT_KEYS.find(k=>plain.includes(k)||n.includes(k));
  return hit?(alias[hit]||hit):plain;
}
function v1300InSeason(md,s){
  if(!md)return false;
  return s.start_md<=s.end_md?(md>=s.start_md&&md<=s.end_md):(md>=s.start_md||md<=s.end_md);
}
function v1300SeasonFor(lot){
  if(!v1300Seasons.length||!lot)return null;
  const md=String(lot.received_date||"").slice(5,10);if(!/^\d\d-\d\d$/.test(md))return null;
  const key=v1300CanonKey(lot.item_name);
  return v1300Seasons.find(s=>v1300CanonKey(s.item_name)===key&&v1300InSeason(md,s))||null;
}
const v1300InfoBase=v1250Info;
v1250Info=function(lot){
  const season=v1300SeasonFor(lot);
  if(!season)return v1300InfoBase(lot);
  if(!lot||Number(lot.current_qty??0)<=0)return null;
  const limit=Number(season.limit_days),elapsed=qrLotAgeDays(lot),level=v1250LevelOf(elapsed,limit);
  const check=level===4&&v1250ChecksDate===todayKey()?v1250Checks.get(String(lot.id))||null:null;
  return{level,effective:check?3:level,elapsed,limit,check,season};
};
window.v1250Info=v1250Info;
const v1300LoadLimitsBase=v1250LoadLimits;
v1250LoadLimits=async function(force=false){const r=await v1300LoadLimitsBase(force);await v1300LoadSeasons(force);return r};
window.v1250LoadLimits=v1250LoadLimits;
v1250CanEditLimits=function(){return["admin","worker","buyer"].includes(db?.role)};
window.v1250CanEditLimits=v1250CanEditLimits;
function v1300MdText(md){const[m,d]=String(md||"").split("-");return m&&d?`${Number(m)}月${Number(d)}日`:"-"}
function v1300MdSelects(prefix,md){
  const[m,d]=String(md||"").split("-").map(Number);
  const ms=Array.from({length:12},(_,i)=>i+1).map(i=>`<option value="${i}" ${i===m?"selected":""}>${i}月</option>`).join("");
  const ds=Array.from({length:31},(_,i)=>i+1).map(i=>`<option value="${i}" ${i===d?"selected":""}>${i}日</option>`).join("");
  return`<select id="${prefix}M" class="input" aria-label="月">${ms}</select><select id="${prefix}D" class="input" aria-label="日">${ds}</select>`;
}
function v1300ReadMd(prefix){
  const m=Number(document.getElementById(prefix+"M")?.value),d=Number(document.getElementById(prefix+"D")?.value);
  const max=[31,29,31,30,31,30,31,31,30,31,30,31][m-1];
  if(!m||!d||d>max)throw new Error("期間の日付を確認してください");
  return`${String(m).padStart(2,"0")}-${String(d).padStart(2,"0")}`;
}
function v1300SeasonCardHtml(){
  const edit=v1250CanEditLimits()&&v1300SeasonSource==="db";
  const names=[...new Set(v1250LimitRows.map(r=>r.item_name))];
  const opts=sel=>names.map(n=>`<option value="${esc(n)}" ${n===sel?"selected":""}>${esc(n)}</option>`).join("");
  const rows=v1300Seasons.map((s,i)=>edit
    ?`<div class="v1300SeasonRow"><select id="v1300SN_${i}" class="input" aria-label="品目">${opts(s.item_name)}</select><div class="v1300Md">${v1300MdSelects(`v1300SS_${i}`,s.start_md)}<span>〜</span>${v1300MdSelects(`v1300SE_${i}`,s.end_md)}</div><div class="v1300SeasonDays"><input id="v1300SD_${i}" class="input" type="number" inputmode="numeric" min="1" max="365" value="${esc(s.limit_days)}" aria-label="日数"><span>日</span></div><input id="v1300SM_${i}" class="input" value="${esc(s.note||"")}" placeholder="メモ（例：端境期）" aria-label="メモ"><div class="v1300SeasonBtns"><button class="btn blue" ${seikaEventAttrs('click','v1300SaveSeason',[i])}>保存</button><button class="btn danger" ${seikaEventAttrs('click','v1300DeleteSeason',[i])}>削除</button></div></div>`
    :`<div class="v1250LimitRow v1250LimitView"><b>${esc(s.item_name)}</b><span>${esc(v1300MdText(s.start_md))}〜${esc(v1300MdText(s.end_md))}は ${esc(s.limit_days)}日${s.note?`（${esc(s.note)}）`:""}</span></div>`).join("");
  const add=edit?`<div class="v1300SeasonRow v1300SeasonNew"><b>特別期間を追加</b><select id="v1300SN_new" class="input" aria-label="品目"><option value="">品目を選ぶ</option>${opts("")}</select><div class="v1300Md">${v1300MdSelects("v1300SS_new","")}<span>〜</span>${v1300MdSelects("v1300SE_new","")}</div><div class="v1300SeasonDays"><input id="v1300SD_new" class="input" type="number" inputmode="numeric" min="1" max="365" placeholder="日数" aria-label="日数"><span>日</span></div><input id="v1300SM_new" class="input" placeholder="メモ（例：端境期・相場高）" aria-label="メモ"><button class="btn green" ${seikaEventAttrs('click','v1300AddSeason',[])}>追加</button></div>`:"";
  const note=v1300SeasonSource==="db"?"":`<div class="err" style="margin-top:8px">特別期間の保存先がまだ準備されていません（SQL 012 の実行が必要です）。</div>`;
  return`<div class="card" id="v1300SeasonCard"><b>時期による特別期間</b><div class="small" style="margin:4px 0 8px">端境期や相場が高い時期など、決まった期間だけ保管目安を変えられます。毎年くり返し使えます。ロットの<b>入荷日</b>が期間に入っていれば、その日数で判定します（年をまたぐ期間も登録できます。例：12月1日〜2月28日）。</div>${note}${rows||'<div class="small">登録されている特別期間はありません。</div>'}${add}</div>`;
}
const v1300LimitsPageBase=qrStorageLimitsPage;
qrStorageLimitsPage=async function(...args){
  await v1300LoadSeasons(true);
  const r=await v1300LimitsPageBase.apply(this,args);
  if(currentScreen==="qrStorageLimitsPage"){
    const wrap=document.querySelector(".wrap")||document.body;
    const cards=[...wrap.querySelectorAll(".card")];
    const anchor=cards[1]||cards[0];
    if(anchor&&!document.getElementById("v1300SeasonCard"))anchor.insertAdjacentHTML("afterend",v1300SeasonCardHtml());
    wrap.querySelectorAll(".small").forEach(el=>{if(el.textContent.trim()==="変更できるのは管理者・青果社員です。")el.textContent="変更できるのは管理者・青果社員・仕入れ担当者です。"});
  }
  return r;
};
window.qrStorageLimitsPage=qrStorageLimitsPage;
function v1300ReadSeason(k){
  const name=String(document.getElementById(`v1300SN_${k}`)?.value||"").trim();
  if(!name)throw new Error("品目を選んでください");
  const start=v1300ReadMd(`v1300SS_${k}`),end=v1300ReadMd(`v1300SE_${k}`);
  const days=v1250ReadDays(`v1300SD_${k}`);
  return{p_item_name:name,p_start_md:start,p_end_md:end,p_limit_days:days,p_note:String(document.getElementById(`v1300SM_${k}`)?.value||"").trim()};
}
async function v1300SaveSeason(i){
  const s=v1300Seasons[i];if(!s)return qrStorageLimitsPage();
  try{const a=v1300ReadSeason(i);await v1250LimitRpc("save_qr_storage_season_v1300",{p_id:s.id,...a});return qrStorageLimitsPage(`${a.p_item_name}の特別期間を保存しました`)}
  catch(e){alert(e.message||e)}
}
async function v1300AddSeason(){
  try{const a=v1300ReadSeason("new");await v1250LimitRpc("save_qr_storage_season_v1300",{p_id:null,...a});return qrStorageLimitsPage(`${a.p_item_name}の特別期間（${v1300MdText(a.p_start_md)}〜${v1300MdText(a.p_end_md)}：${a.p_limit_days}日）を追加しました`)}
  catch(e){alert(e.message||e)}
}
async function v1300DeleteSeason(i){
  const s=v1300Seasons[i];if(!s)return;
  if(!confirm(`${s.item_name}の特別期間（${v1300MdText(s.start_md)}〜${v1300MdText(s.end_md)}）を削除しますか？`))return;
  try{await v1250LimitRpc("delete_qr_storage_season_v1300",{p_id:s.id});return qrStorageLimitsPage("特別期間を削除しました")}
  catch(e){alert(e.message||e)}
}
Object.assign(window,{v1300SaveSeason,v1300AddSeason,v1300DeleteSeason});
const v1300AgeInfoBase=qrLotAgeInfo;
qrLotAgeInfo=function(l){
  const r=v1300AgeInfoBase(l);
  const info=v1250Info(l);
  if(info&&info.season&&r&&r.text)r.text=r.text.replace(/（目安(\d+)日）/,"（目安$1日・特別期間）");
  return r;
};
window.qrLotAgeInfo=qrLotAgeInfo;

/* 出庫：使用不可/保留のロットは画面いっぱいの確認 */
const v1300SaveMoveBase=qrSaveLotMovement;
qrSaveLotMovement=async function(kind,q){
  if(kind==="out"){
    let lot=null;try{lot=await qrFindLot(q)}catch(e){}
    if(lot&&!(await v1300GuardUseAsync(lot,"出庫")))return;
  }
  v1300GuardBypass=true;
  try{return await v1300SaveMoveBase.apply(this,arguments)}
  finally{v1300GuardBypass=false}
};
window.qrSaveLotMovement=qrSaveLotMovement;

/* 要品質確認の「品質確認済みにする」も同じ強い確認にする */
v1250ConfirmQuality=async function(lotId,qrKey){
  if(!v1250CanConfirm())return alert("品質確認は管理者・青果社員が行います。");
  let lot=null;try{lot=qrKey?await qrFindLot(qrKey):null}catch(e){}
  const info=lot?v1250Info(lot):null;
  if(lot&&info){
    const ok=await v1300StrongConfirm(lot,info,"品質確認",{head:"要品質確認のロットです",ask:"実物を見て、品質に問題がないか確認してください。確認済みにすると、本日中は「優先使用」として扱います。",yes:"品質確認済みにする"});
    if(!ok)return;
  }else if(!confirm("実物を確認し、品質に問題がないことを確認しましたか？\n確認済みにすると、本日中は「優先使用」として扱います。"))return;
  try{
    const ans=await callRpc("confirm_qr_lot_storage_check_v1250",{p_lot_id:lotId,p_note:""});
    if(!ans?.ok)throw new Error(ans?.message||"品質確認を保存できませんでした");
    await v1250LoadChecks(true);
    if(currentScreen==="qrLotListPage")return qrReturnToLotList();
    if(currentScreen==="qrOperationLotPage"&&qrKey)return qrOperationLotPage("out",qrKey);
    alert("品質確認済みにしました。");
  }catch(e){alert(/PGRST202|Could not find the function|qr_lot_storage_checks_v1250/.test(String(e.message||e))?"品質確認の保存先がまだ準備されていません（SQL 007 の実行が必要です）。":(e.message||e))}
};
window.v1250ConfirmQuality=v1250ConfirmQuality;

(function(){
  const st=document.createElement("style");
  st.textContent=`.v1300Guard{position:fixed;inset:0;z-index:99999;background:rgba(127,29,29,.92);display:flex;align-items:center;justify-content:center;padding:16px;overflow:auto}
.v1300GuardIn{background:#fff;border:6px solid #b91c1c;border-radius:20px;max-width:560px;width:100%;padding:20px;text-align:center;box-shadow:0 20px 60px rgba(0,0,0,.4)}
.v1300GuardHead{background:#b91c1c;color:#fff;font-size:26px;font-weight:900;border-radius:12px;padding:12px 8px;letter-spacing:.05em}
.v1300GuardItem{font-size:30px;font-weight:900;margin-top:14px;color:#111}
.v1300GuardNum{font-size:22px;font-weight:800;margin-top:8px;color:#111;line-height:1.5}
.v1300GuardNum b{font-size:30px;color:#b91c1c}
.v1300GuardNum span{display:inline-block;margin-top:6px;background:#fee2e2;color:#991b1b;border-radius:999px;padding:4px 14px;font-size:20px;font-weight:900}
.v1300GuardSub{font-size:14px;color:#374151;margin-top:8px}
.v1300GuardAsk{font-size:18px;font-weight:800;color:#7f1d1d;margin-top:14px;line-height:1.5}
.v1300GuardChk{display:flex;gap:12px;align-items:center;text-align:left;margin-top:14px;padding:14px;border:3px solid #b91c1c;border-radius:14px;background:#fef2f2;font-size:18px;font-weight:900;color:#7f1d1d}
.v1300GuardChk input{width:32px;height:32px;flex:0 0 auto}
.v1300GuardBtns{display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-top:16px}
.v1300GuardBtns .btn{font-size:18px;font-weight:900;padding:16px 8px;margin:0}
.v1300GuardNo{background:#e5e7eb !important;color:#111 !important}
.v1300GuardYes{background:#b91c1c !important;color:#fff !important}
.v1300GuardYes:disabled{background:#fca5a5 !important;color:#fff !important;opacity:1}
.v1300SeasonRow{display:grid;gap:6px;padding:10px 0;border-bottom:1px solid #e5e7eb}
.v1300SeasonNew{border-bottom:0}
.v1300Md{display:grid;grid-template-columns:1fr 1fr auto 1fr 1fr;gap:4px;align-items:center}
.v1300Md .input{padding-left:6px;padding-right:6px}
.v1300SeasonDays{display:grid;grid-template-columns:1fr auto;gap:6px;align-items:center}
.v1300SeasonBtns{display:grid;grid-template-columns:1fr 1fr;gap:6px;margin-top:6px}
.v1300SeasonBtns .btn{margin:0}`;
  document.head.appendChild(st);
  try{
    if(typeof V198_GUIDE_SECTIONS!=="undefined"){
      const s=V198_GUIDE_SECTIONS.v1250StorageLimits;
      if(s){
        s.steps=s.steps.map(t=>t.startsWith("要品質確認のロットは")?"要品質確認のロットは、「品質確認済みにする」を押すと赤い確認画面が出ます。実物を確認し「実物を確認しました」にチェックを入れて押すと、その日のあいだは優先使用として扱います。":t.startsWith("使用不可/保留のロットは")?"使用不可/保留のロットを出庫・使用しようとすると、赤い画面いっぱいの確認が出ます。管理者・青果社員が実物を確認し、「実物を確認しました」にチェックを入れたときだけ「確認して出庫する」を押せます（確認した人を記録します）。":t.startsWith("保管目安の日数は")?"保管目安の日数は「保管期限マスタ」で変更・追加・削除できます（管理者・青果社員・仕入れ担当者）。":t);
        s.steps.push("端境期や相場が高い時期など、決まった期間だけ日数を変えたいときは、保管期限マスタの「時期による特別期間」で品目・期間（◯月◯日〜◯月◯日）・日数を登録します。毎年くり返し使え、ロットの入荷日が期間に入っていればその日数で判定します（バッジに「特別期間」と出ます）。");
      }
    }
  }catch(e){}
})();


/* ===== v1.199-c37 規格別ロット（胡瓜など：1ロットに複数の規格） ===== */
/* --- ③ 規格別ロット --- */
let v1310GradeSettings=[],v1310GradeSettingsAt=0,v1310GradeSource="none";
let v1310GradeRows=[],v1310GradesAt=0,v1310GradeMap=new Map(),v1310GradeLoading=null;
async function v1310LoadGradeSettings(force=false){
  if(!force&&Date.now()-v1310GradeSettingsAt<300000)return v1310GradeSettings;
  try{
    const rows=await v1300SelectBase("qr_item_grade_settings_v1300","select=item_name,enabled,grades,updated_by_name,updated_at&order=item_name.asc");
    v1310GradeSettings=Array.isArray(rows)?rows:[];v1310GradeSource="db";
  }catch(e){v1310GradeSettings=[];v1310GradeSource="none"}
  v1310GradeSettingsAt=Date.now();
  return v1310GradeSettings;
}
function v1310GradesForItem(name){
  const key=v1300CanonKey(name);if(!key)return null;
  const s=v1310GradeSettings.find(x=>x.enabled!==false&&v1300CanonKey(x.item_name)===key);
  return s&&Array.isArray(s.grades)&&s.grades.length>=2?s.grades.slice():null;
}
async function v1310LoadGrades(force=false){
  if(!force&&Date.now()-v1310GradesAt<30000)return v1310GradeMap;
  if(v1310GradeLoading)return v1310GradeLoading;
  v1310GradeLoading=(async()=>{
    try{
      const rows=[];
      for(let off=0;off<200000;off+=V1300_PAGE){
        const page=await v1300SelectBase("qr_lot_grades_v1300",`select=lot_id,qr_key,grade,sort_order,received_qty,current_qty&order=lot_id.asc,sort_order.asc&limit=${V1300_PAGE}&offset=${off}`);
        if(!Array.isArray(page))break;rows.push(...page);if(page.length<V1300_PAGE)break;
      }
      const map=new Map();
      for(const r of rows){const k=String(r.lot_id);if(!map.has(k))map.set(k,[]);map.get(k).push(r)}
      for(const list of map.values())list.sort((a,b)=>Number(a.sort_order||0)-Number(b.sort_order||0));
      v1310GradeRows=rows;v1310GradeMap=map;
    }catch(e){if(!v1310GradeMap.size)v1310GradeMap=new Map()}
    v1310GradesAt=Date.now();
    return v1310GradeMap;
  })();
  try{return await v1310GradeLoading}finally{v1310GradeLoading=null}
}
function v1310GradesOf(lot){
  if(!lot)return null;
  const list=v1310GradeMap.get(String(lot.id||""))||v1310GradeRows.filter(r=>String(r.qr_key)===String(lot.qr_key||"_"));
  return list&&list.length?list:null;
}
function v1310GradeText(list,current=true,sep=" ／ "){
  return(list||[]).filter(g=>!current||Number(g.current_qty)>0).map(g=>`${g.grade} ${fmt(Number(current?g.current_qty:g.received_qty))}`).join(sep);
}
function v1310ReadGradeInputs(cls){
  return[...document.querySelectorAll(`.${cls}`)].map(x=>({grade:x.dataset.grade,raw:String(x.value||"").trim()}));
}
function v1310ValidQty(raw){if(raw==="")return 0;if(!/^\d+(\.\d+)?$/.test(raw))return null;return Number(raw)}

/* 入庫：規格ごとのケース数を入れる欄 */
let v1310PendingCreate=null;
/* c38：規格は入荷のたびに入力（候補＝設定＋その品目で過去に使った規格） */
let v1310PastGrades=new Map(),v1310PastAt=0;
async function v1310LoadPastGrades(force=false){
  if(!force&&Date.now()-v1310PastAt<300000)return v1310PastGrades;
  try{
    const rows=await v1300SelectBase("qr_lot_grades_v1300","select=grade,qr_lots(item_name)&order=updated_at.desc&limit=3000");
    const m=new Map();
    for(const r of Array.isArray(rows)?rows:[]){const k=v1300CanonKey(r?.qr_lots?.item_name||"");if(!k||!r.grade)continue;if(!m.has(k))m.set(k,new Set());m.get(k).add(String(r.grade))}
    v1310PastGrades=m;
  }catch(e){}
  v1310PastAt=Date.now();
  return v1310PastGrades;
}
function v1310GradeCandidates(name,extra=[]){
  const key=v1300CanonKey(name);
  return[...new Set([...(v1310GradesForItem(name)||[]),...(key&&v1310PastGrades.get(key)?[...v1310PastGrades.get(key)]:[]),...extra].filter(Boolean))];
}
function v1310GradeRowHtml(cls,name="",qty=""){
  return`<div class="v1310GradeLine"><input class="input ${cls}Name" list="v1310GradeList" type="text" maxlength="20" autocomplete="off" placeholder="規格（例：BL）" value="${esc(name)}" aria-label="規格名"><input class="input ${cls}" type="text" inputmode="numeric" autocomplete="off" placeholder="ケース数" value="${esc(qty)}" aria-label="ケース数"><button type="button" class="btn v1310GradeDel" aria-label="この行を消す">×</button></div>`;
}
function v1310GradeDatalist(names){return`<datalist id="v1310GradeList">${names.map(g=>`<option value="${esc(g)}"></option>`).join("")}</datalist>`}
function v1310BindGradeRows(box,cls,onChange){
  box.addEventListener("input",e=>{if(e.target.classList.contains(cls)||e.target.classList.contains(cls+"Name"))onChange()});
  box.addEventListener("click",e=>{
    if(e.target.classList.contains("v1310GradeDel")){const rows=box.querySelectorAll(".v1310GradeLine");if(rows.length>1)e.target.closest(".v1310GradeLine").remove();else e.target.closest(".v1310GradeLine").querySelectorAll("input").forEach(x=>x.value="");onChange()}
    if(e.target.classList.contains("v1310GradeAdd")){box.querySelector(".v1310GradeLines").insertAdjacentHTML("beforeend",v1310GradeRowHtml(cls));box.querySelector(".v1310GradeLine:last-child input")?.focus()}
  });
}
function v1310ReadGradeRows(cls){
  const list=[],seen=new Set();
  for(const row of document.querySelectorAll(".v1310GradeLine")){
    const nEl=row.querySelector(`.${cls}Name`),qEl=row.querySelector(`.${cls}`);if(!nEl||!qEl)continue;
    const g=String(nEl.value||"").trim(),raw=String(qEl.value||"").trim();
    if(!g&&!raw)continue;
    if(!g)return{error:"規格名が空の行があります"};
    if(g.length>20)return{error:`規格「${g}」は20文字以内にしてください`};
    if(seen.has(g))return{error:`規格「${g}」が2回入っています`};
    const n=v1310ValidQty(raw);if(n===null)return{error:`規格「${g}」のケース数は数字だけで入力してください`};
    seen.add(g);if(n>0)list.push({grade:g,qty:n});
  }
  return{list};
}
function v1310InjectInboundGrades(){
  const itemEl=document.getElementById("qrItemName"),qty=document.getElementById("qrQty");
  const old=document.getElementById("v1310InGrades");
  if(!itemEl||!qty){old?.remove();return}
  const type=document.getElementById("qrContainerType")?.value||"";
  const on=!qrIsLargeContainer(type)&&!!v1310GradesForItem(itemEl.value);
  if(!on){if(old){old.remove();qty.readOnly=false;qty.classList.remove("v1310Locked")}return}
  const key=v1300CanonKey(itemEl.value);
  if(old&&old.dataset.key===key)return;
  old?.remove();
  const unit=document.getElementById("qrUnit")?.value||"ケース";
  const html=`<div id="v1310InGrades" class="v1310GradeBox" data-key="${esc(key)}"><b>規格ごとのケース数</b><div class="small">このロット（1パレット）に入っていた規格を、1行に1つずつ入れてください。規格名は候補から選ぶか、そのまま入力できます。行は「＋規格を追加」で増やせます。数量は合計が自動で入ります。</div>${v1310GradeDatalist(v1310GradeCandidates(itemEl.value))}<div class="v1310GradeLines">${v1310GradeRowHtml("v1310InGrade")}</div><button type="button" class="btn v1310GradeAdd">＋規格を追加</button><div id="v1310InGradeSum" class="v1310GradeSum">合計 0 ${esc(unit)}</div></div>`;
  qty.closest("div")?.insertAdjacentHTML("afterend",html);
  qty.readOnly=true;qty.classList.add("v1310Locked");
  v1310BindGradeRows(document.getElementById("v1310InGrades"),"v1310InGrade",v1310InboundGradeSum);
  v1310InboundGradeSum();
  v1310LoadPastGrades().then(()=>{const b=document.getElementById("v1310InGrades");const dl=b?.querySelector("#v1310GradeList");if(dl)dl.outerHTML=v1310GradeDatalist(v1310GradeCandidates(itemEl.value))}).catch(()=>{});
}
function v1310InboundGradeSum(){
  let sum=0,bad=false;
  for(const row of document.querySelectorAll("#v1310InGrades .v1310GradeLine")){const n=v1310ValidQty(String(row.querySelector(".v1310InGrade")?.value||"").trim());if(n===null)bad=true;else sum+=n}
  const qty=document.getElementById("qrQty"),unit=document.getElementById("qrUnit")?.value||"ケース";
  if(qty){qty.value=sum>0?String(sum):"";qty.dispatchEvent(new Event("input",{bubbles:true}))}
  const box=document.getElementById("v1310InGradeSum");
  if(box)box.innerHTML=bad?`<span class="v1310Bad">ケース数は数字だけを入力してください</span>`:`合計 ${fmt(sum)} ${esc(unit)}`;
}
document.addEventListener("change",e=>{if(e.target&&["qrItemName","qrContainerType"].includes(e.target.id))setTimeout(v1310InjectInboundGrades,0)});
document.addEventListener("input",e=>{if(e.target&&e.target.id==="qrItemName")setTimeout(v1310InjectInboundGrades,0)});
if(typeof qrRenderContainerFields==="function"){
  const v1310RenderCFBase=qrRenderContainerFields;
  qrRenderContainerFields=function(...a){const r=v1310RenderCFBase.apply(this,a);setTimeout(v1310InjectInboundGrades,0);return r};
  window.qrRenderContainerFields=qrRenderContainerFields;
}
const v1310SaveLotBase=window.qrSaveLot;
window.qrSaveLot=async function(...args){
  v1310PendingCreate=null;
  await v1310LoadGradeSettings();
  const box=document.getElementById("v1310InGrades");
  if(box){
    const rd=v1310ReadGradeRows("v1310InGrade");
    if(rd.error)return alert(rd.error);
    const list=rd.list;
    if(!list.length)return alert("規格ごとのケース数を入力してください");
    const total=list.reduce((a,b)=>a+b.qty,0),qty=Number(document.getElementById("qrQty")?.value||0);
    if(Math.abs(total-qty)>0.000001)return alert(`規格ごとのケース数の合計（${fmt(total)}）と数量（${fmt(qty)}）が一致しません`);
    v1310PendingCreate={grades:list};
  }
  try{return await v1310SaveLotBase.apply(this,args)}
  finally{v1310PendingCreate=null}
};
try{qrSaveLot=window.qrSaveLot}catch(e){}

/* 出庫・廃棄・実数調整：規格ごとの数量 */
let v1310PendingOp=null;
const v1310OpPageBase=qrOperationLotPage;
qrOperationLotPage=async function(kind,q){
  if(["out","waste","adjust"].includes(kind))await v1310LoadGrades(true);
  const r=await v1310OpPageBase.apply(this,arguments);
  if(!["out","waste","adjust"].includes(kind))return r;
  try{
    const lot=await qrFindLot(q),grades=v1310GradesOf(lot),qty=document.getElementById("qrMoveQty");
    if(!lot||!grades||!qty||document.getElementById("v1310OpGrades"))return r;
    const adj=kind==="adjust",unit=qrLotUnit(lot);
    const title=adj?"規格ごとの実数（調整後の数）":kind==="waste"?"規格ごとの廃棄数":"規格ごとの出庫数";
    const html=`<div id="v1310OpGrades" class="v1310GradeBox" data-kind="${kind}"><b>${title}</b><div class="small">${adj?"数え直した数を規格ごとに入れてください。変わらない規格はそのままにします。":"規格ごとに数を入れてください。出さない規格は空欄のままにします。"}数量は合計が自動で入ります。</div><div class="v1310GradeGrid">${grades.map(g=>`<label class="v1310GradeCell"><span>${esc(g.grade)}<small>残 ${fmt(Number(g.current_qty))}</small></span><input class="input v1310OpGrade" data-grade="${esc(g.grade)}" data-cur="${esc(g.current_qty)}" type="text" inputmode="decimal" autocomplete="off" ${adj?`value="${esc(g.current_qty)}"`:'placeholder="0"'}></label>`).join("")}</div><div id="v1310OpGradeSum" class="v1310GradeSum"></div></div>`;
    qty.closest("div")?.insertAdjacentHTML("afterend",html);
    qty.readOnly=true;qty.classList.add("v1310Locked");
    document.querySelectorAll(".v1310OpGrade").forEach(el=>el.addEventListener("input",()=>v1310OpGradeSum(unit)));
    v1310OpGradeSum(unit);
  }catch(e){console.warn("[規格別ロット]",e)}
  return r;
};
window.qrOperationLotPage=qrOperationLotPage;
function v1310OpGradeSum(unit){
  const box=document.getElementById("v1310OpGrades");if(!box)return;
  const adj=box.dataset.kind==="adjust";let sum=0,bad="";
  for(const el of document.querySelectorAll(".v1310OpGrade")){
    const n=v1310ValidQty(String(el.value||"").trim()),cur=Number(el.dataset.cur||0);
    if(n===null){bad="数字だけを入力してください";continue}
    if(!adj&&n>cur)bad=`規格「${el.dataset.grade}」の残りは ${fmt(cur)} です`;
    sum+=adj&&String(el.value||"").trim()===""?cur:n;
  }
  const qty=document.getElementById("qrMoveQty");if(qty)qty.value=String(sum);
  const s=document.getElementById("v1310OpGradeSum");
  if(s)s.innerHTML=bad?`<span class="v1310Bad">${esc(bad)}</span>`:`${adj?"調整後の合計":"合計"} ${fmt(sum)} ${esc(unit)}`;
}
function v1310ReadOpGrades(){
  const box=document.getElementById("v1310OpGrades");if(!box)return null;
  const adj=box.dataset.kind==="adjust",list=[];
  for(const el of document.querySelectorAll(".v1310OpGrade")){
    const raw=String(el.value||"").trim(),n=v1310ValidQty(raw),cur=Number(el.dataset.cur||0),g=el.dataset.grade;
    if(n===null)throw new Error(`規格「${g}」の数は数字だけで入力してください`);
    if(adj){list.push({grade:g,qty:raw===""?cur:n})}
    else{if(n>cur)throw new Error(`規格「${g}」の残りは ${fmt(cur)} です`);if(n>0)list.push({grade:g,qty:n})}
  }
  if(!adj&&!list.length)throw new Error("規格ごとの数を入力してください");
  if(adj&&!list.some((x,i)=>Number(x.qty)!==Number(document.querySelectorAll(".v1310OpGrade")[i].dataset.cur||0)))throw new Error("規格ごとの数が変わっていません");
  return list;
}
const v1310SaveMoveBase=qrSaveLotMovement;
qrSaveLotMovement=async function(kind,q){
  v1310PendingOp=null;
  if(["out","waste","adjust"].includes(kind)){
    let lot=null;try{lot=await qrFindLot(q)}catch(e){}
    try{
      const grades=v1310ReadOpGrades();
      if(grades){v1310OpGradeSum(lot?qrLotUnit(lot):"");v1310PendingOp={qrKey:String(lot?.qr_key||""),grades}}
    }catch(e){return alert(e.message||e)}
  }
  try{return await v1310SaveMoveBase.apply(this,arguments)}
  finally{v1310PendingOp=null}
};
window.qrSaveLotMovement=qrSaveLotMovement;

/* RPCの切り替え：規格別ロットのときは、規格の数も一緒に保存する関数を呼ぶ */
function v1310GradeLineForOp(args){
  const session=typeof countSession==="function"?countSession(args.p_session_id):null;
  if(!session)return null;
  const seq=(Array.isArray(session.v188Confirmations)?session.v188Confirmations.length:0)+1;
  for(const line of session.qrLines||[]){
    if(!line.grade||String(line.qrKey)!==String(args.p_qr_key))continue;
    for(const s of[seq,seq-1,seq+1])if(qrInventoryStableUuid(`${session.id}:${line.lineId}:${s}`,'v188_qr_adjust')===args.p_operation_id)return line;
  }
  return null;
}
const v1310RpcBase=callRpc;
callRpc=async function(name,args){
  if(name==="create_qr_lot_v185"&&v1310PendingCreate){
    const pend=v1310PendingCreate;v1310PendingCreate=null;
    const ans=await v1310RpcBase("create_qr_lot_graded_v1300",{p_lot:args.p_lot,p_operation_id:args.p_operation_id,p_grades:pend.grades,p_device_meta:args.p_device_meta||{},p_operation_meta:args.p_operation_meta||{}});
    v1310GradesAt=0;return ans;
  }
  if(name==="apply_qr_lot_operation"&&v1310PendingOp&&String(args?.p_qr_key||"")===v1310PendingOp.qrKey){
    const pend=v1310PendingOp,p={};
    for(const[k,v]of Object.entries(args||{}))p[k.replace(/^p_/,"")]=v;
    const ans=await v1310RpcBase("apply_qr_lot_grade_operation_v1300",{p_args:p,p_grades:pend.grades});
    v1310GradesAt=0;return ans;
  }
  if(name===V188_QR_RPC&&args){
    const line=v1310GradeLineForOp(args);
    if(line){
      const ans=await v1310RpcBase("apply_month_end_grade_adjustment_v1300",{p_qr_key:args.p_qr_key,p_grade:line.grade,p_operation_id:args.p_operation_id,p_target_month:args.p_target_month,p_as_of_date:args.p_as_of_date,p_book_qty:args.p_book_qty,p_actual_qty:args.p_actual_qty,p_reason:args.p_reason,p_memo:args.p_memo,p_session_id:args.p_session_id,p_count_no:args.p_count_no});
      v1310GradesAt=0;return ans;
    }
  }
  const ans=await v1310RpcBase(name,args);
  if(/^(cancel_qr_lot_operation|cancel_qr_inventory_session)$/.test(String(name)))v1310GradesAt=0;
  if((name==="create_trimming_job"||name==="replace_trimming_job_v1203")&&ans?.ok)await v1310SaveTrimGrades(ans,args).catch(e=>console.warn("[規格別ロット] 日報の規格を保存できません",e));
  return ans;
};
window.callRpc=callRpc;

/* ロットの表示に規格を出す */
const v1310LotCardBase=qrLotCard;
qrLotCard=function(l){
  const html=v1310LotCardBase.apply(this,arguments);
  const list=v1310GradesOf(l);if(!list)return html;
  const t=v1310GradeText(list,true)||"残りなし";
  const add=`<div class="v1310LotGrades"><b>規格</b> ${esc(t)}</div>`;
  const i=html.lastIndexOf("</div>");
  return i<0?html+add:html.slice(0,i)+add+html.slice(i);
};
window.qrLotCard=qrLotCard;

/* 入庫直後の打ち間違い：規格の内訳を直す（管理者・青果社員） */
const v1310DetailBase=qrLotDetail;
qrLotDetail=async function(...args){
  await v1310LoadGrades(true);
  const r=await v1310DetailBase.apply(this,args);
  try{
    const lot=await qrFindLot(args[0]),list=v1310GradesOf(lot);
    if(lot&&list&&canQrOperate()&&!document.getElementById("v1310FixBtn")){
      const wrap=document.querySelector(".wrap");
      wrap?.insertAdjacentHTML("beforeend",`<div class="card"><b>規格の内訳</b><div class="small" style="margin:4px 0 8px">入庫：${esc(v1310GradeText(list,false))}<br>現在：${esc(v1310GradeText(list,true)||"残りなし")}</div><button id="v1310FixBtn" class="btn btn2" style="width:100%" ${seikaEventAttrs('click','v1310FixGradesPage',[String(lot.qr_key)])}>規格の内訳を直す（入庫直後の打ち間違い）</button></div>`);
    }
  }catch(e){}
  return r;
};
window.qrLotDetail=qrLotDetail;
async function v1310FixGradesPage(qrKey){
  if(!canQrOperate())return;
  await v1310LoadGrades(true);await v1310LoadGradeSettings();
  const lot=await qrFindLot(qrKey),list=v1310GradesOf(lot);
  if(!lot||!list)return alert("規格別ロットが見つかりません");
  await v1310LoadPastGrades();
  const names=v1310GradeCandidates(lot.item_name,list.map(g=>g.grade));
  setScreen("v1310FixGradesPage",[qrKey]);
  pageShell("規格の内訳を直す",`${lot.item_name} ／ ${lot.lot_no||""}`,`<div class="card"><div class="small">入庫したときの規格の数を打ち間違えたときや、規格を追加・変更したいときに使います。規格名は候補から選ぶか、そのまま入力できます。合計（${fmt(Number(lot.current_qty))} ${esc(qrLotUnit(lot))}）は変えられません。出庫・廃棄・調整をしたあとのロットは直せないため、実数調整を使ってください。</div><div id="v1310FixBox" style="margin-top:10px">${v1310GradeDatalist(names)}<div class="v1310GradeLines">${list.map(g=>v1310GradeRowHtml("v1310FixGrade",g.grade,String(Number(g.current_qty)))).join("")}</div><button type="button" class="btn v1310GradeAdd">＋規格を追加</button><div id="v1310FixSum" class="v1310GradeSum"></div></div><button class="btn blue" style="width:100%;margin-top:12px" ${seikaEventAttrs('click','v1310SaveFixGrades',[qrKey])}>この内訳で保存</button></div>`);
  const total=Number(lot.current_qty||0),unit=qrLotUnit(lot)||"ケース";
  const sum=()=>{let s=0,bad=false;for(const r of document.querySelectorAll("#v1310FixBox .v1310GradeLine")){const n=v1310ValidQty(String(r.querySelector(".v1310FixGrade")?.value||"").trim());if(n===null)bad=true;else s+=n}const b=document.getElementById("v1310FixSum");if(b)b.innerHTML=bad?`<span class="v1310Bad">数字だけを入力してください</span>`:`合計 ${fmt(s)} ／ ${fmt(total)} ${esc(unit)}${Math.abs(s-total)>0.000001?' <span class="v1310Bad">（合計を合わせてください）</span>':""}`};
  v1310BindGradeRows(document.getElementById("v1310FixBox"),"v1310FixGrade",sum);sum();
}
async function v1310SaveFixGrades(qrKey){
  try{
    const rd=v1310ReadGradeRows("v1310FixGrade");
    if(rd.error)throw new Error(rd.error);
    const list=rd.list;
    if(!list.length)throw new Error("規格ごとの数を入力してください");
    const ans=await callRpc("fix_qr_lot_grades_v1300",{p_qr_key:qrKey,p_grades:list});
    if(!ans?.ok)throw new Error(ans?.message||"保存できませんでした");
    v1310GradesAt=0;v1310PastAt=0;alert("規格の内訳を直しました。");
    return qrLotDetail(qrKey);
  }catch(e){alert(e.message||e)}
}
Object.assign(window,{v1310FixGradesPage,v1310SaveFixGrades});

/* 貼り紙：右側のQRの下に規格ごとのケース数 */
function v1310PosterGradesHtml(lot){
  const list=v1310GradesOf(lot);if(!list)return"";
  const rows=list.filter(g=>Number(g.received_qty)>0),total=rows.reduce((a,g)=>a+Number(g.received_qty||0),0);
  const n=rows.length+2,rowH=Math.max(30,Math.min(100,Math.floor(505/n))),fs=Math.max(20,Math.min(64,Math.floor(rowH*0.64)));
  const td=`border:3px solid #000;padding:0 12px;height:${rowH}px;font-size:${fs}px;font-weight:900;line-height:1;white-space:nowrap`;
  return`<table class="posterGrades" style="width:100%;margin-top:10px;border-collapse:collapse;color:#000;table-layout:fixed"><tr><th style="${td};background:#e5e7eb;text-align:left">規格</th><th style="${td};background:#e5e7eb;text-align:right">${esc(qrLotUnit(lot)||"ケース")}</th></tr>${rows.map(g=>`<tr><td style="${td};overflow:hidden">${esc(g.grade)}</td><td style="${td};text-align:right">${fmt(Number(g.received_qty))}</td></tr>`).join("")}<tr><td style="${td};background:#f3f4f6">合計</td><td style="${td};text-align:right;background:#f3f4f6">${fmt(total)}</td></tr></table>`;
}
window.v1310PosterGradesHtml=v1310PosterGradesHtml;
const v1310PrintBase=qrPrintLot;
qrPrintLot=async function(...args){await v1310LoadGrades(true);return v1310PrintBase.apply(this,args)};
window.qrPrintLot=qrPrintLot;

/* 月末棚卸し：規格別ロットは規格ごとに1行 */
function v1310EndOfDayIso(dayKey){return new Date(`${dayKey}T23:59:59.999+09:00`).toISOString()}
async function v1310GradeMovesAfter(lotIds,dayKey){
  if(!lotIds.length)return[];
  const out=[],iso=v1310EndOfDayIso(dayKey);
  for(let i=0;i<lotIds.length;i+=50){
    const ids=lotIds.slice(i,i+50).join(",");
    const rows=await v1300SelectBase("qr_lot_movements",`select=lot_id,occurred_at,created_at,operation_meta&lot_id=in.(${ids})&occurred_at=gt.${encodeURIComponent(iso)}&limit=1000`);
    out.push(...(rows||[]));
  }
  return out;
}
function v1310GradeQtyAt(list,moves,lotId){
  const q={};for(const g of list)q[g.grade]=Number(g.current_qty||0);
  for(const m of moves){if(String(m.lot_id)!==String(lotId))continue;const gs=m.operation_meta&&m.operation_meta.grades;if(!Array.isArray(gs))continue;for(const d of gs)if(d&&d.grade in q)q[d.grade]-=Number(d.delta||0)}
  return q;
}
if(typeof v188QrLines==="function"){
  const v1310QrLinesBase=v188QrLines;
  v188QrLines=async function(room,asOfKey){
    const rows=await v1310QrLinesBase.apply(this,arguments);
    await v1310LoadGrades(true);
    const graded=rows.filter(r=>r.lotId&&v1310GradeMap.has(String(r.lotId)));
    if(!graded.length)return rows;
    const moves=await v1310GradeMovesAfter([...new Set(graded.map(r=>String(r.lotId)))],asOfKey);
    const out=[];
    for(const row of rows){
      const list=row.lotId?v1310GradeMap.get(String(row.lotId)):null;
      if(!list){out.push(row);continue}
      const q=v1310GradeQtyAt(list,moves,row.lotId);
      for(const g of list){
        const n=yen(q[g.grade]||0);if(!(n>0))continue;
        out.push({...row,lineId:newId(),grade:g.grade,itemName:`${row.itemName}（${g.grade}）`,systemQty:n});
      }
    }
    return out;
  };
  window.v188QrLines=v188QrLines;
}
if(typeof v188LoadQrLive==="function"){
  const v1310LiveLoadBase=v188LoadQrLive;
  v188LoadQrLive=async function(...a){const r=await v1310LiveLoadBase.apply(this,a);await v1310LoadGrades(true);return r};
  window.v188LoadQrLive=v188LoadQrLive;
}
if(typeof v188LiveQty==="function"){
  const v1310LiveBase=v188LiveQty;
  v188LiveQty=function(line){
    if(line&&line.type==='qr'&&line.grade){
      const list=v1310GradeRows.filter(r=>String(r.qr_key)===String(line.qrKey));
      const g=list.find(r=>r.grade===line.grade);
      return g?yen(Number(g.current_qty||0)):(list.length?0:null);
    }
    return v1310LiveBase(line);
  };
  window.v188LiveQty=v188LiveQty;
}

/* 在庫表：規格別ロットの品目は、セルに規格ごとのケース数も出す */
const v1310ByDayBase=qrInventoryKgByItemForRoomByDay;
qrInventoryKgByItemForRoomByDay=async function(room,dayKeys){
  const result=await v1310ByDayBase.apply(this,arguments);
  try{
    await v1310LoadGrades(true);
    if(!v1310GradeMap.size||!result)return result;
    const ids=[...v1310GradeMap.keys()];
    const lots=[];
    for(let i=0;i<ids.length;i+=50){const rows=await v1300SelectBase("qr_lots",`select=*&id=in.(${ids.slice(i,i+50).join(",")})&limit=1000`);lots.push(...(rows||[]))}
    const locations=qrCountLocations(room),days=[...new Set(dayKeys||[])];
    const add={},addStand={};
    for(let i=0;i<lots.length;i+=40){
      const chunk=lots.slice(i,i+40),moves=await v1300SelectBase("qr_lot_movements",`select=*&lot_id=in.(${chunk.map(l=>l.id).join(",")})&order=created_at.asc&limit=1000`);
      for(const lot of chunk){
        const lotMoves=(moves||[]).filter(m=>String(m.lot_id)===String(lot.id)),list=v1310GradeMap.get(String(lot.id))||[];
        const resolved=qrResolveInventoryItem(lot),rule=resolved.rule||qrManagedRuleForName(lot.item_name);
        for(const dayKey of days){
          const snap=v1101LotSnapshotAtDayEnd(lot,lotMoves,dayKey);
          if(!snap||!locations.includes(snap.location)||!(snap.qty>0))continue;
          const iso=v1310EndOfDayIso(dayKey),q=v1310GradeQtyAt(list,lotMoves.filter(m=>new Date(m.occurred_at||m.created_at)>new Date(iso)),lot.id);
          let target;
          if(resolved.item){add[resolved.item.id]=add[resolved.item.id]||{};target=add[resolved.item.id]}
          else if(rule){const k=qrStandaloneInventoryIdentity(lot,rule).key;addStand[k]=addStand[k]||{};target=addStand[k]}
          else continue;
          target[dayKey]=target[dayKey]||{};
          for(const g of list)target[dayKey][g.grade]=(target[dayKey][g.grade]||0)+Number(q[g.grade]||0);
        }
      }
    }
    const order=g=>{for(const l of v1310GradeMap.values()){const x=l.find(r=>r.grade===g);if(x)return Number(x.sort_order||0)}return 999};
    const put=(dest,src)=>{for(const[id,byDay]of Object.entries(src)){dest[id]=dest[id]||{};for(const[day,grades]of Object.entries(byDay)){const t=Object.entries(grades).filter(([,n])=>n>0).sort((a,b)=>order(a[0])-order(b[0])).map(([g,n])=>`${g}${fmt(n)}`).join("・");if(!t)continue;dest[id][day]=dest[id][day]||[];dest[id][day].push(`規格 ${t}（ケース）`)}}};
    result.specs=result.specs||{};result.standaloneSpecs=result.standaloneSpecs||{};
    put(result.specs,add);put(result.standaloneSpecs,addStand);
  }catch(e){console.warn("[規格別ロット] 在庫表の規格表示を作れません",e)}
  return result;
};
window.qrInventoryKgByItemForRoomByDay=qrInventoryKgByItemForRoomByDay;

/* 製造日報：使用原料に規格を選ぶ */
const v1310TrimRenderBase=v1115RenderTrimming;
v1115RenderTrimming=function(...a){
  const r=v1310TrimRenderBase.apply(this,a);
  try{
    for(const line of v1115Trimming.lots||[]){
      const mode=document.getElementById(`trimLotMode_${line.id}`);if(!mode||document.getElementById(`v1310TrimGrade_${line.id}`))continue;
      const list=v1310GradeRows.filter(g=>String(g.qr_key)===String(line.qrKey));if(!list.length)continue;
      const label=mode.previousElementSibling&&mode.previousElementSibling.tagName==="LABEL"?mode.previousElementSibling:mode;
      label.insertAdjacentHTML("beforebegin",`<label class="label" style="margin-top:7px">規格</label><select id="v1310TrimGrade_${line.id}" class="input" ${seikaEventAttrs('change','v1310SetTrimGrade',[line.id])}><option value="">規格を選ぶ</option>${list.map(g=>`<option value="${esc(g.grade)}" ${line.grade===g.grade?"selected":""}>${esc(g.grade)}（残 ${fmt(Number(g.current_qty))}）</option>`).join("")}</select>`);
    }
  }catch(e){console.warn("[規格別ロット]",e)}
  return r;
};
window.v1115RenderTrimming=v1115RenderTrimming;
function v1310SetTrimGrade(id){const line=(v1115Trimming.lots||[]).find(x=>x.id===id);if(line)line.grade=document.getElementById(`v1310TrimGrade_${id}`)?.value||""}
window.v1310SetTrimGrade=v1310SetTrimGrade;
async function v1310SaveTrimGrades(ans,args){
  const lines=(typeof v1115Trimming!=="undefined"&&v1115Trimming.lots||[]).filter(x=>x.grade);
  if(!lines.length)return;
  const jobId=ans.job?.id||ans.job_id||ans.new_job_id||ans.id;
  if(!jobId)return;
  await v1310RpcBase("set_trimming_job_lot_grades_v1300",{p_job_id:String(jobId),p_grades:lines.map(x=>({qr_key:x.qrKey,grade:x.grade}))});
}

/* 規格別ロットの設定画面（管理者・青果社員が変更、ほかの人は見るだけ） */
function v1310CanEditGrades(){return["admin","worker"].includes(db?.role)}
async function qrGradeSettingsPage(msg=""){
  setScreen("qrGradeSettingsPage",[msg]);
  pageShell("規格別ロットの設定","1ロットに複数の規格を入れる品目",'<div class="card"><div class="notice">読み込んでいます。</div></div>');
  await v1310LoadGradeSettings(true);
  const edit=v1310CanEditGrades()&&v1310GradeSource==="db";
  const rows=v1310GradeSettings.map((s,i)=>edit
    ?`<div class="card"><div class="v1310GsRow"><input id="v1310GN_${i}" class="input" value="${esc(s.item_name)}" aria-label="品目名"><label class="v1310GsOn"><input id="v1310GE_${i}" type="checkbox" ${s.enabled!==false?"checked":""}> 使う</label></div><label class="label">規格の候補（「、」で区切る・入庫のときの候補になります）</label><input id="v1310GG_${i}" class="input" value="${esc((s.grades||[]).join("、"))}"><div class="v1310GsBtns"><button class="btn blue" ${seikaEventAttrs('click','v1310SaveGradeSetting',[i])}>保存</button><button class="btn danger" ${seikaEventAttrs('click','v1310DeleteGradeSetting',[i])}>削除</button></div></div>`
    :`<div class="card"><b>${esc(s.item_name)}</b>${s.enabled===false?'<span class="small">（使わない）</span>':""}<div class="small" style="margin-top:4px">規格：${esc((s.grades||[]).join("、"))}</div></div>`).join("");
  const add=edit?`<div class="card"><b>品目を追加</b><input id="v1310GN_new" class="input" placeholder="品目名（QR管理品目と同じ名前）" style="margin-top:6px"><label class="label">規格（「、」で区切る）</label><input id="v1310GG_new" class="input" placeholder="例：L、M、S"><button class="btn green" style="width:100%;margin-top:10px" ${seikaEventAttrs('click','v1310AddGradeSetting',[])}>追加</button></div>`:"";
  const info=`<div class="card"><b>規格別ロットとは</b><div class="small" style="margin-top:4px">1パレットに規格がまざって入荷する品目（胡瓜など）を、1つのロットで管理します。入庫のときに、入荷した規格を1行ずつ入れます（規格名はその都度入力でき、ここに登録した規格と過去に使った規格が候補に出ます）。出庫・廃棄・実数調整も規格ごとに行います。貼り紙・在庫表・月末棚卸し・棚卸表Excelにも規格ごとの数が出ます。</div>${v1310GradeSource==="db"?"":`<div class="err" style="margin-top:8px">規格別ロットの保存先がまだ準備されていません（SQL 013 の実行が必要です）。</div>`}${v1310CanEditGrades()?"":`<div class="small" style="margin-top:8px">変更できるのは管理者・青果社員です。</div>`}<div class="small" style="margin-top:8px">設定を変えても、登録済みのロットの規格は変わりません。</div></div>`;
  pageShell("規格別ロットの設定",`${v1310GradeSettings.length}品目`,`${msg?`<div class="ok">${esc(msg)}</div>`:""}${info}${rows}${add}`);
}
function v1310SplitGrades(id){return String(document.getElementById(id)?.value||"").split(/[、,，\s]+/).map(s=>s.trim()).filter(Boolean)}
async function v1310SaveGradeSetting(i){
  const s=v1310GradeSettings[i];if(!s)return qrGradeSettingsPage();
  try{
    const name=String(document.getElementById(`v1310GN_${i}`)?.value||"").trim(),enabled=!!document.getElementById(`v1310GE_${i}`)?.checked,grades=v1310SplitGrades(`v1310GG_${i}`);
    const ans=await callRpc("save_qr_item_grade_setting_v1300",{p_item_name:name,p_enabled:enabled,p_grades:grades,p_old_name:s.item_name});
    if(!ans?.ok)throw new Error(ans?.message||"保存できませんでした");
    return qrGradeSettingsPage(`${name}を保存しました`);
  }catch(e){alert(e.message||e)}
}
async function v1310AddGradeSetting(){
  try{
    const name=String(document.getElementById("v1310GN_new")?.value||"").trim(),grades=v1310SplitGrades("v1310GG_new");
    if(!name)throw new Error("品目名を入力してください");
    if(!qrIsManagedItemName(name))throw new Error("QR管理品目の名前を入力してください");
    const ans=await callRpc("save_qr_item_grade_setting_v1300",{p_item_name:name,p_enabled:true,p_grades:grades,p_old_name:null});
    if(!ans?.ok)throw new Error(ans?.message||"保存できませんでした");
    return qrGradeSettingsPage(`${name}を追加しました`);
  }catch(e){alert(e.message||e)}
}
async function v1310DeleteGradeSetting(i){
  const s=v1310GradeSettings[i];if(!s)return;
  if(!confirm(`${s.item_name}を規格別ロットの設定から削除しますか？\n登録済みのロットの規格は消えません。`))return;
  try{await callRpc("delete_qr_item_grade_setting_v1300",{p_item_name:s.item_name});return qrGradeSettingsPage(`${s.item_name}を削除しました`)}catch(e){alert(e.message||e)}
}
Object.assign(window,{qrGradeSettingsPage,v1310SaveGradeSetting,v1310AddGradeSetting,v1310DeleteGradeSetting});
function v1310InjectHome(tries=0){
  if(currentScreen!=="qrHome")return;
  const anchor=document.getElementById("v1250LimitsBtn");
  if(!anchor){if(tries<40)setTimeout(()=>v1310InjectHome(tries+1),100);return}
  if(document.getElementById("v1310GradeBtn"))return;
  const b=v1250HomeButton("v1310GradeBtn","homeBtnGrade","qrGradeSettingsPage",'規格別ロットの設定<br><span style="font-size:15px;font-weight:800">胡瓜など規格をまとめて1ロット</span>');
  anchor.parentNode.insertBefore(b,anchor.nextSibling);
}
const v1310HomeBase=qrHome;
qrHome=async function(...a){const r=await v1310HomeBase.apply(this,a);v1310InjectHome();v1310LoadGradeSettings();return r};
window.qrHome=qrHome;

/* 入庫画面を開いたときに規格設定を読み込む */
setTimeout(()=>{v1310LoadGradeSettings().then(()=>v1310InjectInboundGrades()).catch(()=>{})},1500);

/* QRロットを読み込んだら、規格の数も読み込む（30秒ごと） */
const v1310QrSelectBase=qrSelect;
qrSelect=async function(table,query){
  const rows=await v1310QrSelectBase.apply(this,arguments);
  if(table==="qr_lots"&&Array.isArray(rows)&&rows.length)await v1310LoadGrades().catch(()=>{});
  return rows;
};
window.qrSelect=qrSelect;
(function(){
  const st=document.createElement("style");
  st.textContent=`.v1310GradeBox{margin-top:10px;padding:12px;border:2px solid #ca8a04;border-radius:14px;background:#fefce8}
.v1310GradeGrid{display:grid;grid-template-columns:repeat(auto-fill,minmax(110px,1fr));gap:8px;margin-top:8px}
.v1310GradeCell{display:grid;gap:4px;font-weight:900}
.v1310GradeCell span{display:flex;justify-content:space-between;gap:4px}
.v1310GradeCell small{font-weight:700;color:#6b7280}
.v1310GradeSum{margin-top:8px;font-weight:900;font-size:17px}
.v1310Bad{color:#b91c1c}
.v1310GradeLines{display:grid;gap:8px;margin-top:8px}
.v1310GradeLine{display:grid;grid-template-columns:minmax(0,1.2fr) minmax(0,1fr) 46px;gap:6px;align-items:center}
.v1310GradeLine .input{margin:0}
.v1310GradeDel{margin:0 !important;min-height:44px;padding:0 !important;background:#fff !important;color:#991b1b !important;border:2px solid #f87171 !important;font-weight:900;font-size:20px !important;opacity:1 !important;box-shadow:none !important}
.v1310GradeAdd{margin-top:8px !important;width:100%;background:#fff !important;color:#713f12 !important;border:2px dashed #ca8a04 !important;font-weight:900;opacity:1 !important;box-shadow:none !important;text-shadow:none !important}
.v1310Locked{background:#f3f4f6 !important;color:#111 !important}
.v1310LotGrades{margin-top:6px;padding:6px 10px;border-radius:10px;background:#fef9c3;color:#713f12;font-weight:800}
.v1310GsRow{display:grid;grid-template-columns:1fr auto;gap:8px;align-items:center}
.v1310GsOn{display:flex;gap:6px;align-items:center;font-weight:800}
.v1310GsOn input{width:22px;height:22px}
.v1310GsBtns{display:grid;grid-template-columns:1fr 1fr;gap:6px;margin-top:6px}
.v1310GsBtns .btn{margin:0}
.homeBtnGrade{background:linear-gradient(90deg,#713f12 0%,#ca8a04 52%,#fde68a 100%) !important;color:#fff !important;text-shadow:0 1px 2px rgba(0,0,0,.3) !important;border-color:transparent !important;}`;
  document.head.appendChild(st);
  try{
    if(typeof V198_GUIDE_SECTIONS!=="undefined"){
      V198_GUIDE_SECTIONS.v1310Grades={title:"規格別ロット（胡瓜など）",where:"ホーム → QR在庫管理 → QR入庫 ／ 規格別ロットの設定",
        steps:["胡瓜は、1パレットに入っている規格（AL・BL・丸・B・Aなど）をまとめて1つのロットで入庫します。品名で胡瓜を選ぶと「規格ごとのケース数」の欄が出るので、入荷した規格を1行に1つずつ入れます。規格名は候補から選ぶか、そのまま入力できます（過去に使った規格も候補に出ます）。行は「＋規格を追加」で増やせます（数量は合計が自動で入ります）。産地・仕入先が違うものは別のロットにします。",
               "貼り紙には、右側のQRコードの下に規格ごとのケース数と合計が大きく入ります。",
               "出庫・廃棄・実数調整では、規格ごとに数を入れます。複数の規格をまとめて1回で処理できます（例：BL 5、丸 2）。全部出庫するときは「ロット全てを出庫」を押すと、規格ごとの残りがすべて入ります。実数調整は、数え直した数を規格ごとに入れます。",
               "QRロット一覧・ロット詳細には、規格ごとの残りが出ます。入庫直後に規格の数を打ち間違えたときや、規格を追加・変更したいときは、ロット詳細の「規格の内訳を直す」で直せます（出庫などをしたあとは実数調整を使います）。",
               "在庫表では胡瓜のセルに合計kgと規格ごとのケース数が出ます。月末棚卸しと棚卸表Excelは「胡瓜（BL）」のように規格ごとに1行で出ます。",
               "製造日報で胡瓜のロットを使用原料に追加したときは、規格も選びます。",
               "品質評価はロット単位です。規格を伝えたいときはメモに書きます。",
               "規格を使う品目と、よく使う規格の候補は「規格別ロットの設定」で変更・追加できます（管理者・青果社員）。設定にない規格も入庫のときにそのまま入力できます。"],
        check:"入庫のとき、規格ごとの数の合計がパレットのケース数と合っているか確認します。",
        caution:"規格別ロットは「QR連続出庫」では出庫できません。通常の出庫で規格ごとに数を入れてください。古い画面のまま操作すると保存されません（再読み込みしてください）。"};
      if(typeof V198_ROLE_ADD!=="undefined")for(const k of Object.keys(V198_ROLE_ADD))if(Array.isArray(V198_ROLE_ADD[k])&&V198_ROLE_ADD[k].includes("v1250StorageLimits")&&!V198_ROLE_ADD[k].includes("v1310Grades"))V198_ROLE_ADD[k].push("v1310Grades");
    }
  }catch(e){}
})();


/* ===== v1.199-c40 通信量を減らす（第1段階）：履歴は変わった分だけ受け取り、変わった分だけ送る =====
   SQL 014（synced_at列）があれば「ID＋更新時刻の一覧」だけを受け取り、変わった行・新しい行だけ中身を取りに行く。
   014が無いときは今までどおり全件を受け取る。送るときは、クラウドと同じ内容の行を送らない。 */
(function(){
 const V1240_KEY="hist_cache_v1240";
 const V1240_TABLES=new Set(Object.values(HISTORY_TABLES));
 let v1240Cache=null,v1240Loading=null,v1240Ready=null,v1240Dirty=false;
 window.v1240Stats={listRows:0,dataRows:0,fullRows:0,skipped:0,sent:0};
 function canon(v){
  if(v===null||typeof v!=="object")return JSON.stringify(v===undefined?null:v);
  if(Array.isArray(v))return"["+v.map(canon).join(",")+"]";
  return"{"+Object.keys(v).filter(k=>v[k]!==undefined).sort().map(k=>JSON.stringify(k)+":"+canon(v[k])).join(",")+"}";
 }
 function hash(v){const s=canon(v);let h=2166136261;for(let i=0;i<s.length;i++){h^=s.charCodeAt(i);h=Math.imul(h,16777619)}return(h>>>0).toString(36)+"."+s.length}
 async function load(){
  if(v1240Cache)return v1240Cache;
  if(!v1240Loading)v1240Loading=(async()=>{let c=null;try{c=await v188IdbGet(V1240_KEY)}catch(e){}
   v1240Cache=c&&typeof c==="object"&&c.v===1?c:{v:1,owner:"",tables:{}};return v1240Cache})();
  return v1240Loading;
 }
 function tableCache(c,table){
  const owner=String(db?.userId||db?.user||"");
  if(c.owner!==owner){c.owner=owner;c.tables={}}
  return c.tables[table]||(c.tables[table]={rows:{},sent:{}});
 }
 let saveTimer=null;
 function persist(){v1240Dirty=true;clearTimeout(saveTimer);saveTimer=setTimeout(async()=>{if(!v1240Dirty||!v1240Cache)return;v1240Dirty=false;try{await v188IdbPut(V1240_KEY,v1240Cache)}catch(e){console.warn("history cache save",e)}},800)}
 async function getJson(url){
  const res=await fetch(url,{headers:historyApiHeaders()});
  if(!res.ok){const t=await res.text();const err=new Error(t);err.status=res.status;throw err}
  return res.json();
 }
 async function listSignatures(table){
  const out=[];const page=1000;
  for(let off=0;off<200000;off+=page){
   const rows=await getJson(`${SUPABASE_URL}/rest/v1/${table}?select=id,synced_at&order=id.asc&limit=${page}&offset=${off}`);
   out.push(...rows);if(rows.length<page)break;
  }
  return out;
 }
 async function fetchFull(table){
  const out=[];const page=1000;
  for(let off=0;off<200000;off+=page){
   const rows=await getJson(`${SUPABASE_URL}/rest/v1/${table}?select=id,data&order=id.asc&limit=${page}&offset=${off}`);
   out.push(...rows);if(rows.length<page)break;
  }
  return out;
 }
 const v1240FetchBase=fetchHistoryTable;
 fetchHistoryTable=async function(table){
  if(!V1240_TABLES.has(table)||v1240Ready===false)return v1240FetchBase(table);
  const c=await load(),tc=tableCache(c,table);
  let sigs;
  try{sigs=await listSignatures(table);v1240Ready=true}
  catch(e){
   if(/synced_at/.test(String(e.message||""))||e.status===400){v1240Ready=false;return v1240FetchBase(table)}
   throw e;
  }
  window.v1240Stats.listRows+=sigs.length;
  const alive=new Set(),need=[];
  for(const s of sigs){const id=String(s.id);alive.add(id);const old=tc.rows[id];if(!old||old.s!==s.synced_at)need.push(id)}
  for(const id of Object.keys(tc.rows))if(!alive.has(id))delete tc.rows[id];
  const sigMap=new Map(sigs.map(s=>[String(s.id),s.synced_at]));
  for(let i=0;i<need.length;i+=80){
   const ids=need.slice(i,i+80);
   const rows=await getJson(`${SUPABASE_URL}/rest/v1/${table}?select=id,data,synced_at&id=in.(${ids.map(x=>'"'+String(x).replace(/"/g,'\\"')+'"').map(encodeURIComponent).join(",")})`);
   window.v1240Stats.dataRows+=rows.length;
   for(const r of rows){if(!r||!r.data)continue;tc.rows[String(r.id)]={s:r.synced_at||sigMap.get(String(r.id))||"",d:r.data,h:hash(r.data)};if(tc.sent&&r.data.id!=null)delete tc.sent[String(r.data.id)]}
  }
  if(need.length||sigs.length!==Object.keys(tc.rows).length)persist();
  return Object.values(tc.rows).map(x=>x.d).filter(Boolean);
 };
 window.fetchHistoryTable=fetchHistoryTable;

 function knownHashes(table){
  const tc=v1240Cache?tableCache(v1240Cache,table):null;if(!tc)return null;
  const m=new Map();
  for(const x of Object.values(tc.rows))if(x&&x.d&&x.d.id!=null)m.set(String(x.d.id),x.h);
  for(const [id,h] of Object.entries(tc.sent||{}))m.set(id,h);
  return m;
 }
 function changedOnly(table,rows){
  if(!Array.isArray(rows)||!rows.length||!v1240Cache)return{rows:rows||[],marks:[]};
  const known=knownHashes(table),keep=[],marks=[];
  for(const r of rows){if(!r||r.id==null){keep.push(r);continue}const h=hash(r);if(known&&known.get(String(r.id))===h){window.v1240Stats.skipped++;continue}keep.push(r);marks.push([String(r.id),h])}
  return{rows:keep,marks};
 }
 function markSent(table,marks){
  if(!marks.length||!v1240Cache)return;const tc=tableCache(v1240Cache,table);tc.sent=tc.sent||{};
  for(const [id,h] of marks)tc.sent[id]=h;window.v1240Stats.sent+=marks.length;persist();
 }
 const v1240RpcBase=callRpc;
 callRpc=async function(name,args,...rest){
  if((name==="save_history_records_v188"||name==="save_clerk_waste_history_v188")&&args&&typeof args==="object"){
   await load();
   const a={...args},marks=[];
   if(Array.isArray(a.p_records)){const r=changedOnly(HISTORY_TABLES.records,a.p_records);a.p_records=r.rows;marks.push([HISTORY_TABLES.records,r.marks])}
   if(Array.isArray(a.p_movements)){const r=changedOnly(HISTORY_TABLES.movements,a.p_movements);a.p_movements=r.rows;marks.push([HISTORY_TABLES.movements,r.marks])}
   if(Array.isArray(a.p_waste_records)){const r=changedOnly(HISTORY_TABLES.wasteRecords,a.p_waste_records);a.p_waste_records=r.rows;marks.push([HISTORY_TABLES.wasteRecords,r.marks])}
   const delCount=["p_delete_record_ids","p_delete_waste_ids","p_delete_movement_ids"].reduce((n,k)=>n+(Array.isArray(a[k])?a[k].length:0),0);
   const sendCount=(a.p_records||[]).length+(a.p_movements||[]).length+(a.p_waste_records||[]).length;
   if(!sendCount&&!delCount&&name==="save_history_records_v188")return{ok:true,skipped:true};
   if(!sendCount&&name==="save_clerk_waste_history_v188")return{ok:true,skipped:true};
   const ans=await v1240RpcBase.call(this,name,a,...rest);
   if(ans&&ans.ok!==false)for(const [t,m] of marks)markSent(t,m);
   return ans;
  }
  return v1240RpcBase.call(this,name,args,...rest);
 };
 window.callRpc=callRpc;
 const v1240UpsertBase=upsertHistoryTable;
 upsertHistoryTable=async function(table,rows,mapper){
  await load();
  const r=changedOnly(table,rows||[]);
  if(!r.rows.length)return;
  await v1240UpsertBase(table,r.rows,mapper);
  markSent(table,r.marks);
 };
 window.upsertHistoryTable=upsertHistoryTable;
 window.v1240ClearHistoryCache=async function(){v1240Cache={v:1,owner:"",tables:{}};try{await v188IdbPut(V1240_KEY,v1240Cache)}catch(e){}};
})();


/* ===== v1.199-c41 通信量を減らす（第2段階）：QRロット・QR移動履歴・月末QR記録は、変わった分だけ受け取る =====
   SQL 015（synced_at列）があれば、端末に一覧を保存しておき、前回から変わった行だけを受け取る。
   1件だけを探す問い合わせ（QRコード・ロット番号など）は今までどおりサーバーに聞く。
   015が無いときは今までどおり全件を受け取る。 */
(function(){
 const KEY="qr_cache_v1410";
 const TABLES={
  qr_lots:{key:r=>String(r.id),keyCols:"id"},
  qr_lot_movements:{key:r=>String(r.id),keyCols:"id"},
  qr_lot_monthly_snapshots:{key:r=>String(r.target_month)+"|"+String(r.lot_id),keyCols:"target_month,lot_id"}
 };
 const LOOKUP_COLS=new Set(["id","qr_key","lot_no","operation_id","lot_id","reversed_operation_id"]);
 const FRESH_MS=4000,PARTY_MS=300000,OVERLAP_MS=2*60*1000;
 let cache=null,loading=null,ready=null,lastWriteAt=0,saveTimer=null;
 const syncing={};
 window.v1410Stats={network:0,served:0,deltaRows:0,fullRows:0,syncs:0};

 const baseFetch=window.fetch.bind(window);
 window.fetch=function(input,init){
  try{
   const url=typeof input==="string"?input:(input&&input.url)||"";
   const method=String((init&&init.method)||(input&&input.method)||"GET").toUpperCase();
   if(url.indexOf(SUPABASE_URL)===0&&method!=="GET"&&method!=="HEAD")lastWriteAt=Date.now();
  }catch(e){}
  return baseFetch(input,init);
 };

 async function load(){
  if(cache)return cache;
  if(!loading)loading=(async()=>{let c=null;try{c=await v188IdbGet(KEY)}catch(e){}
   cache=c&&typeof c==="object"&&c.v===1?c:{v:1,owner:"",tables:{}};
   for(const t of Object.values(cache.tables||{}))t.at=0;
   return cache})();
  return loading;
 }
 function owner(){return String(db?.userId||db?.user||"")}
 function tc(table){
  if(cache.owner!==owner()){cache.owner=owner();cache.tables={}}
  return cache.tables[table]||(cache.tables[table]={rows:{},max:"",at:0,n:0});
 }
 function persist(){clearTimeout(saveTimer);saveTimer=setTimeout(async()=>{try{await v188IdbPut(KEY,cache)}catch(e){console.warn("qr cache save",e)}},1500)}
 async function getJson(path,extraHeaders){
  const res=await baseFetch(`${SUPABASE_URL}/rest/v1/${path}`,{headers:qrApiHeaders({"Content-Type":"application/json",...(extraHeaders||{})})});
  if(!res.ok){const t=await res.text();const err=new Error(t);err.status=res.status;throw err}
  return{rows:await res.json(),range:res.headers.get("content-range")||""};
 }
 async function pages(table,query){
  const out=[];
  for(let off=0;off<500000;off+=1000){
   const {rows}=await getJson(`${table}?${query}&limit=1000&offset=${off}`);
   out.push(...rows);if(rows.length<1000)break;
  }
  return out;
 }
 function bumpMax(t,rows){for(const r of rows){const s=r&&r.synced_at;if(s&&(!t.max||Date.parse(s)>Date.parse(t.max)))t.max=s}}
 async function fullLoad(table,t){
  const rows=await pages(table,`select=*&order=${TABLES[table].keyCols.split(",").map(c=>c+".asc").join(",")}`);
  t.rows={};t.max="";
  for(const r of rows)t.rows[TABLES[table].key(r)]=r;
  bumpMax(t,rows);window.v1410Stats.fullRows+=rows.length;
 }
 async function serverCount(table){
  const {range}=await getJson(`${table}?select=synced_at&limit=1`,{Prefer:"count=exact"});
  const n=Number(String(range).split("/")[1]);
  return Number.isFinite(n)?n:null;
 }
 async function doSync(table){
  const t=tc(table);
  if(!t.max&&!Object.keys(t.rows).length){await fullLoad(table,t)}
  else{
   const since=new Date(Date.parse(t.max||"1970-01-01T00:00:00Z")-OVERLAP_MS).toISOString();
   const rows=await pages(table,`select=*&synced_at=gte.${encodeURIComponent(since)}&order=synced_at.asc`);
   for(const r of rows)t.rows[TABLES[table].key(r)]=r;
   bumpMax(t,rows);window.v1410Stats.deltaRows+=rows.length;
   const n=await serverCount(table);
   if(n!==null&&n!==Object.keys(t.rows).length){
    const keys=await pages(table,`select=${TABLES[table].keyCols}`);
    const alive=new Set(keys.map(TABLES[table].key));
    for(const k of Object.keys(t.rows))if(!alive.has(k))delete t.rows[k];
    if(Object.keys(t.rows).length!==alive.size)await fullLoad(table,t);
   }
  }
  t.at=Date.now();window.v1410Stats.syncs++;persist();
 }
 async function sync(table,maxAge){
  await load();const t=tc(table);
  if(t.at&&Date.now()-t.at<maxAge&&lastWriteAt<t.at)return t;
  if(!syncing[table])syncing[table]=doSync(table).finally(()=>{delete syncing[table]});
  await syncing[table];
  return tc(table);
 }
 async function checkReady(){
  if(ready!==null)return ready;
  try{await getJson("qr_lots?select=synced_at&limit=1");ready=true}
  catch(e){ready=(e.status===400||/synced_at/.test(String(e.message||"")))?false:null;}
  return ready;
 }

 function splitList(s){const out=[];let cur="",q=false;for(let i=0;i<s.length;i++){const ch=s[i];if(ch==='"'){q=!q;continue}if(ch==="\\"&&q){cur+=s[++i];continue}if(ch===","&&!q){out.push(cur);cur="";continue}cur+=ch}out.push(cur);return out}
 function parse(query){
  const p={select:null,filters:[],order:[],limit:null,offset:0};
  for(const part of String(query||"").split("&")){
   if(!part)continue;
   const i=part.indexOf("=");if(i<0)return null;
   const k=decodeURIComponent(part.slice(0,i)),v=decodeURIComponent(part.slice(i+1));
   if(k==="select"){if(/[():!]/.test(v))return null;p.select=v==="*"?null:v.split(",").map(s=>s.trim());continue}
   if(k==="limit"){p.limit=Number(v);if(!Number.isFinite(p.limit))return null;continue}
   if(k==="offset"){p.offset=Number(v)||0;continue}
   if(k==="order"){for(const o of v.split(",")){const a=o.split(".");const col=a[0],dir=a.includes("desc")?"desc":"asc";const nulls=a.includes("nullsfirst")?"first":a.includes("nullslast")?"last":(dir==="asc"?"last":"first");p.order.push({col,dir,nulls})}continue}
   if(k==="or"||k==="and"||/[.()]/.test(k))return null;
   let neg=false,rest=v;if(rest.startsWith("not.")){neg=true;rest=rest.slice(4)}
   const d=rest.indexOf(".");if(d<0)return null;
   const op=rest.slice(0,d),val=rest.slice(d+1);
   if(!["eq","neq","gt","gte","lt","lte","is","in"].includes(op))return null;
   if(op==="eq"&&LOOKUP_COLS.has(k)&&!neg)return null;
   if(op==="in"&&!(val.startsWith("(")&&val.endsWith(")")))return null;
   p.filters.push({col:k,op,val:op==="in"?splitList(val.slice(1,-1)):val,neg});
  }
  return p;
 }
 const DATE_RE=/^\d{4}-\d{2}-\d{2}/;
 function cmp(a,b){
  if(typeof a==="number"||typeof b==="number"){const x=Number(a),y=Number(b);if(Number.isFinite(x)&&Number.isFinite(y))return x<y?-1:x>y?1:0}
  if(typeof a==="boolean"||typeof b==="boolean"){const x=String(a),y=String(b);return x<y?-1:x>y?1:0}
  const sa=String(a),sb=String(b);
  if(DATE_RE.test(sa)&&DATE_RE.test(sb)){const x=Date.parse(sa.length>10?sa.replace(" ","T"):sa+"T00:00:00Z"),y=Date.parse(sb.length>10?sb.replace(" ","T"):sb+"T00:00:00Z");if(Number.isFinite(x)&&Number.isFinite(y))return x<y?-1:x>y?1:0}
  return sa<sb?-1:sa>sb?1:0;
 }
 function test(row,f){
  const v=row[f.col];let ok;
  if(f.op==="is"){const w=f.val.toLowerCase();ok=w==="null"?v===null||v===undefined:w==="true"?v===true:w==="false"?v===false:false}
  else if(v===null||v===undefined)return false;
  else if(f.op==="in")ok=f.val.some(x=>cmp(v,x)===0);
  else{const c=cmp(v,f.val);ok=f.op==="eq"?c===0:f.op==="neq"?c!==0:f.op==="gt"?c>0:f.op==="gte"?c>=0:f.op==="lt"?c<0:c<=0}
  return f.neg?!ok:ok;
 }
 function evaluate(t,p){
  let rows=Object.values(t.rows).filter(r=>p.filters.every(f=>test(r,f)));
  const order=p.order.length?p.order:[{col:"created_at",dir:"asc",nulls:"last"}];
  rows.sort((a,b)=>{for(const o of order){const x=a[o.col],y=b[o.col];const xn=x===null||x===undefined,yn=y===null||y===undefined;
   if(xn||yn){if(xn&&yn)continue;return(xn?1:-1)*(o.nulls==="last"?1:-1)}
   const c=cmp(x,y);if(c)return o.dir==="desc"?-c:c}return 0});
  if(p.offset)rows=rows.slice(p.offset);
  if(p.limit!==null)rows=rows.slice(0,p.limit);
  return rows.map(r=>{if(p.select){const o={};for(const c of p.select)o[c]=r[c]===undefined?null:r[c];return o}const o={...r};delete o.synced_at;return o});
 }
 function maxAgeFor(table,p){
  if(table==="qr_lots"&&p.select&&p.select.every(c=>c==="supplier"||c==="cooperative_name"||c==="active"))return PARTY_MS;
  return FRESH_MS;
 }
 async function tryCache(table,query,wholeTable){
  if(!TABLES[table])return null;
  const p=parse(query);if(!p)return null;
  if(wholeTable){p.limit=null;p.offset=0}
  if(await checkReady()!==true)return null;
  let t;try{t=await sync(table,maxAgeFor(table,p))}catch(e){console.warn("qr cache sync",e);return null}
  window.v1410Stats.served++;
  return evaluate(t,p);
 }
 function stripSynced(table,rows){if(TABLES[table]&&Array.isArray(rows))for(const r of rows)if(r&&typeof r==="object")delete r.synced_at;return rows}

 const qrSelectBase=qrSelect;
 qrSelect=async function(table,query="select=*"){
  const hit=await tryCache(table,query,false);
  if(hit)return hit;
  window.v1410Stats.network++;
  return stripSynced(table,await qrSelectBase(table,query));
 };
 window.qrSelect=qrSelect;
 const selectAllBase=v163SelectAll;
 v163SelectAll=async function(table,baseQuery,pageSize=1000){
  const hit=await tryCache(table,baseQuery,true);
  if(hit)return hit;
  return selectAllBase(table,baseQuery,pageSize);
 };
 window.v163SelectAll=v163SelectAll;
 window.v1410ClearQrCache=async function(){cache={v:1,owner:"",tables:{}};try{await v188IdbPut(KEY,cache)}catch(e){}};
 window.v1410Debug={parse,evaluate:(table,q)=>evaluate(tc(table),parse(q)),sync};
})();


/* ===== v1.199-c42 画面の切り替えを安定させる =====
   ① QR在庫管理を開くとき、ホーム画面に別の部品が一瞬差し込まれていた（途中の qrHome が描画完了を待たずに終わっていたため）。
      待つように直したので、今まで実際には表示されていなかった部品が出ないよう、従来どおりの見た目にそろえる。
   ② ホームの「未確認の低評価」が後から差し込まれてボタンがずれるため、前回の表示を先に出しておく。 */
(function(){
 const V1420_HIDE=["v1104QrQualityArea","v135QrBatchActions","v1280PartyBtn"];
 const v1420QrHomeBase=qrHome;
 qrHome=async function(...a){
  const r=await v1420QrHomeBase.apply(this,a);
  if(currentScreen==="qrHome")for(const id of V1420_HIDE)document.getElementById(id)?.remove();
  return r;
 };
 window.qrHome=qrHome;
 function key(){return"v1420QualityTask:"+String(db?.userId||"")+":"+String(db?.role||"")}
 const v1420LoadBase=v1143LoadQualityTask;
 v1143LoadQualityTask=async function(...a){
  const r=await v1420LoadBase.apply(this,a);
  try{
   if(currentScreen==="home"){
    const box=document.getElementById("v1143QualityTask");
    if(box&&!box.querySelector(".err"))sessionStorage.setItem(key(),JSON.stringify({html:box.innerHTML,empty:!!document.getElementById("v1143TodayTaskEmpty")}));
   }
  }catch(e){}
  return r;
 };
 window.v1143LoadQualityTask=v1143LoadQualityTask;
 const v1420TaskHtmlBase=v1143TodayTaskHtml;
 v1143TodayTaskHtml=function(...a){
  const html=v1420TaskHtmlBase.apply(this,a);
  try{
   const c=JSON.parse(sessionStorage.getItem(key())||"null");
   if(!c||!html||html.indexOf("v1143QualityTask")<0)return html;
   const t=document.createElement("template");t.innerHTML=html;
   const box=t.content.getElementById("v1143QualityTask");
   if(!box||box.querySelector("[data-v1143-task-action]"))return html;
   box.innerHTML=c.html;
   if(c.html)t.content.getElementById("v1143TodayTaskEmpty")?.remove();
   const d=document.createElement("div");d.appendChild(t.content.cloneNode(true));return d.innerHTML;
  }catch(e){return html}
 };
 window.v1143TodayTaskHtml=v1143TodayTaskHtml;
 const v1420HomeBase=home;
 home=function(...a){
  const r=v1420HomeBase.apply(this,a);
  try{
   const c=JSON.parse(sessionStorage.getItem(key())||"null"),box=document.getElementById("v1143QualityTask");
   if(c&&box&&!box.querySelector("[data-v1143-task-action]")){
    box.innerHTML=c.html;
    if(c.html)document.getElementById("v1143TodayTaskEmpty")?.remove();
   }
  }catch(e){}
  return r;
 };
 window.home=home;
})();

