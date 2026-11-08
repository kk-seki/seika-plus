
/* ===== v1.199-c48 本社 第1段階（移動中・本社移動用の貼り紙・受け入れ・品質評価・確定・使用出庫・取消） ===== */
(function(){
const HQ_ROLES=["hq_worker","hq_clerk","hq_receiver","hq_prep"];
const HQ_LABEL={hq_worker:"本社社員",hq_clerk:"本社事務",hq_receiver:"本社 荷受け担当者",hq_prep:"本社 下処理班"};
Object.assign(ROLE,HQ_LABEL);Object.assign(GROUP,HQ_LABEL);
const HQ_GRADE={good:"良好",review:"要確認",bad:"不良"};
const HQ_ISSUES=["傷み","腐敗","変色","異物","サイズ不良","数量違い","その他"];
const HQ_CONTAINERS=["ダンボール","コンテナ","網コンテナ","鉄コンテナ","パレテーナ","紙袋","その他"];
const HQ_BIG_CONTAINERS=["網コンテナ","鉄コンテナ","パレテーナ"];
function hqSpecMemo(spec){const t=String(spec||"").replace(/ \/ /g,"／").trim().slice(0,20);return t?`規格：${t}`:null}
function hqSpecOf(l){const seg=String(l?.memo||"").split(" / ").find(x=>x.startsWith("規格："));return seg?seg.slice(3).trim():""}
function hqFocus(id,msg){typeof v161FocusField==="function"?v161FocusField(id,msg):alert(msg)}
const HQ_BUCKET="hq-quality-photos";
let hqBusy=false,hqPhotos=[],hqReader=null;
const role=()=>db?.role||"";
const has=list=>list.includes(role());
function hqIsHqRole(){return HQ_ROLES.includes(role())}
function hqOnlyHq(){return has(["hq_receiver","hq_prep"])}
function hqViewOnly(){return !hqIsHqRole()&&role()!=="admin"}
function hqMyId(){return authProfile?.id||""}
function hqCanReceive(){return has(["admin","hq_worker","hq_receiver"])}
function hqCanOut(){return has(["admin","hq_worker","hq_prep"])}
function hqCanAdjust(){return has(["admin","hq_worker"])}
function hqCanItems(){return has(["admin","hq_worker"])}
function hqCanNormal(){return has(["admin","hq_worker","hq_receiver"])}
function hqCanPrint(){return has(["admin","worker","hq_worker","hq_receiver"])}
function hqCanCancelOut(m){if(!m||m.movement_type!=="出庫"||m.cancelled_at)return false;if(has(["admin","hq_worker"]))return true;if(!has(["hq_prep"]))return false;return m.user_id===hqMyId()&&ymdKey(new Date(m.occurred_at))===hqToday()}
function hqSiteKey(){return STORE+"_site_v1400_"+(db?.userId||"")}
function hqSite(){if(hqOnlyHq())return"honsha";let s="";try{s=localStorage.getItem(hqSiteKey())||""}catch(e){}return s==="honsha"||s==="ishioka"?s:(hqIsHqRole()?"honsha":"ishioka")}
function hqSetSite(s){try{localStorage.setItem(hqSiteKey(),s)}catch(e){}return home()}
function hqQty(v){const n=Number(v||0);return Number.isInteger(n)?String(n):String(Math.round(n*100)/100)}
function hqDateLabel(d){if(!d)return"-";const x=new Date(String(d).slice(0,10)+"T00:00:00");return `${x.getMonth()+1}月${x.getDate()}日（${"日月火水木金土"[x.getDay()]}）`}
function hqToday(){return ymdKey(new Date)}
function hqErr(e){let s=String(e?.message||e||"");try{const o=JSON.parse(s);s=o.message||s}catch(_){}return s}
async function hqRpc(name,args){return callRpc(name,args)}
function hqPackOf(l){const p=String(l?.slip_pack||"").trim();return p||(l?.pack_weight||"")}
function hqPackNorm(v){const s=String(v??"").trim().replace(/[０-９．]/g,c=>String.fromCharCode(c.charCodeAt(0)-0xFEE0));if(!s)return{ok:true,pack:""};if(/^[-−ー]/.test(s))return{ok:false,msg:"入数は0より大きく1000より小さい数字で入れてください"};const m=s.match(/^([0-9.]+)\s*(kg|㎏|ｋｇ|キロ)?$/i);if(m){const n=Number(m[1]);if(!(n>0&&n<1000))return{ok:false,msg:"入数は0より大きく1000より小さい数字で入れてください"};return{ok:true,pack:`${m[1]}kg`}}return s.length>20?{ok:false,msg:"入数は20文字以内で入れてください"}:{ok:true,pack:s}}
async function hqSlipPackAttach(rows,force){
 const list=(Array.isArray(rows)?rows:[]).filter(l=>l&&l.source_kind==="石岡から"&&l.source_movement_id&&(force||l.status==="入荷待ち")&&!l.slip_pack_checked);
 if(!list.length)return rows;
 const ids=[...new Set(list.map(l=>String(l.source_movement_id)))],parts=[];
 for(let i=0;i<ids.length;i+=40)parts.push(ids.slice(i,i+40).map(encodeURIComponent).join(","));
 try{
  const adj=new Map(),mv=new Map();
  await Promise.all(parts.map(async part=>{
   const [a,m]=await Promise.all([
    qrSelect("qr_slip_adjust_v1199c86",`select=movement_id,pack&movement_id=in.(${part})`).catch(e=>{if(/qr_slip_adjust_v1199c86|schema cache|does not exist|404/.test(String(e?.message||e)))return[];throw e}),
    qrSelect("qr_lot_movements",`select=id,operation_meta&id=in.(${part})`)]);
   a.forEach(x=>adj.set(String(x.movement_id),String(x.pack||"").trim()));
   m.forEach(x=>mv.set(String(x.id),String(x.operation_meta?.slip?.pack||"").trim()));
  }));
  for(const l of list){const k=String(l.source_movement_id);l.slip_pack=adj.get(k)||mv.get(k)||"";l.slip_pack_checked=true;l.slip_pack_error=false}
 }catch(e){console.warn("入数の変更を読み込めませんでした");list.forEach(l=>{l.slip_pack_error=true})}
 return rows;
}
async function hqLots(q){const rows=await qrSelect("hq_lots_v1400",q);if(/(^|&)select=\*(&|$)/.test(String(q)))await hqSlipPackAttach(rows,false);return rows}
function hqStatusBadge(l){const c={"入荷待ち":"warn","在庫あり":"normal","在庫なし":"unset","取消":"unset"}[l.status]||"";return `<span class="badge ${c}">${esc(l.status)}</span>`}
function hqGradeBadge(g){if(!g)return"";const c={good:"normal",review:"warn",bad:"danger"}[g];return `<span class="badge ${c}">${HQ_GRADE[g]}</span>`}
let hqLimits=null;
async function hqLoadLimits(){if(hqLimits)return hqLimits;try{const r=await qrSelect("qr_storage_limits_v1250","select=item_name,limit_days");hqLimits={};r.forEach(x=>hqLimits[x.item_name]=Number(x.limit_days))}catch(e){hqLimits={}}return hqLimits}
function hqAgeBadge(l){const lim=hqLimits?.[l.item_name];const base=l.ishioka_received_date||l.hq_received_date||l.planned_date;if(!lim||!base||l.status==="取消"||l.status==="在庫なし")return"";const days=Math.floor((new Date(hqToday()+"T00:00:00")-new Date(String(base).slice(0,10)+"T00:00:00"))/864e5);const c=days>=lim?"danger":days>=lim-1?"warn":"normal";return `<span class="badge ${c}">入荷から${days}日／目安${lim}日</span>`}
function hqDiffBadge(l){if(l.status!=="在庫あり"&&l.status!=="在庫なし")return"";if(Number(l.received_qty)===Number(l.planned_qty))return"";return `<span class="badge warn">差異あり（予定 ${hqQty(l.planned_qty)}→実際 ${hqQty(l.received_qty)}${esc(l.unit)}）</span>`}
function hqPlanText(l){if(l.unit==="kg"&&Number(l.planned_count)>0&&Number(l.unit_weight_kg)>0)return `${hqQty(l.planned_count)}基（1基 ${hqQty(l.unit_weight_kg)}kg）＝${hqQty(l.planned_qty)}kg`;if(l.unit==="kg"&&l.via_ishioka&&Number(l.planned_count)>0&&!(Number(l.planned_qty)>0))return `${hqQty(l.planned_count)}基（実測前）`;return `${hqQty(l.planned_qty)}${l.unit}`}
function hqLotCard(l,open=true){
 const qty=l.status==="入荷待ち"?`予定 ${esc(hqPlanText(l))}`:`在庫 ${hqQty(l.current_qty)}${esc(l.unit)}`;
 const moving=l.status==="入荷待ち"&&(l.source_kind==="石岡から"||l.via_ishioka)?'<span class="badge warn">移動中</span> ':"";
 return `<div class="card hqLotCard"><div class="itemHead"><div><b style="font-size:20px">${esc(l.item_name)}</b><div class="small">${esc(l.lot_no)} / ${esc(l.source_kind)}${l.via_ishioka?"（石岡経由）":""}</div></div><div>${moving}${hqStatusBadge(l)} ${hqGradeBadge(l.grade)}</div></div><div style="margin-top:6px">${hqAgeBadge(l)} ${hqDiffBadge(l)}</div>
 <div class="hqLotMeta"><div><span>数量</span><b>${qty}</b></div><div><span>量目</span><b>${esc(hqPackOf(l)||"-")}</b></div><div><span>仕入先</span><b>${esc(l.supplier||"-")}</b></div><div><span>産地</span><b>${esc(l.origin||"-")}</b></div>${hqSpecOf(l)?`<div><span>規格</span><b>${esc(hqSpecOf(l))}</b></div>`:""}<div><span>本社入荷日</span><b>${hqDateLabel(l.hq_received_date||l.planned_date)}</b></div>${l.ishioka_received_date?`<div><span>石岡入荷日</span><b>${hqDateLabel(l.ishioka_received_date)}</b></div>`:""}</div>
 ${hqShipLine(l)}${open?`<button class="btn green" style="width:100%;margin-top:10px" ${seikaEventAttrs("click","hqLotPage",[l.qr_key])}>開く</button>`:""}</div>`}
function hqTimingLabel(t){return t==="当日分"?"当日発注分":t==="翌日分先送り"?"翌日発注分":(t||"")}
function hqShipLine(l){
 if(l.source_kind!=="石岡から"&&!l.via_ishioka)return"";
 const out=l.via_ishioka?["石岡経由",l.shipped_date?hqDateLabel(l.shipped_date):"",l.ship_day||""].filter(Boolean).join("　"):[l.shipped_date?hqDateLabel(l.shipped_date):"",hqTimingLabel(l.order_timing)].filter(Boolean).join("　");
 const run=l.ship_run?`${l.ship_run}${l.ship_run_time?` ${l.ship_run_time}着`:""}`:"";
 const rows=[["出庫",out],["便",run],["出庫者",l.created_by_name||""]].filter(r=>r[1]);
 return rows.length?`<div class="hqShipLine" style="margin-top:8px;padding:8px 12px;border-radius:10px;background:#fef9e7;border:1px solid #fde68a;color:#422006">${rows.map(r=>`<div style="display:flex;gap:10px;padding:2px 0"><span style="flex:0 0 4.5em;font-size:13px;color:#92400e">${r[0]}</span><span style="font-weight:600">${esc(r[1])}</span></div>`).join("")}</div>`:"";
}
function hqShipGroups(rows){
 const order=[],map=new Map();
 for(const l of rows){
  let k,label;
  if(l.source_kind!=="石岡から"){k=l.via_ishioka?"via":"direct";label=l.via_ishioka?"本社直接入荷（石岡経由）":"本社直接入荷"}
  else{const d=l.shipped_date||"";const t=hqTimingLabel(l.order_timing);k=`${d}|${t}`;label=d?`${hqDateLabel(d)} 出庫 ・ ${t||"発注分の記録なし"}`:"出庫日・発注分の記録なし（c50より前の出庫）"}
  if(!map.has(k)){map.set(k,{label,rows:[]});order.push(k)}
  map.get(k).rows.push(l);
 }
 return order.map(k=>map.get(k));
}
function hqGroupedHtmlG(rows){return hqGroupedHtml(rows,l=>hqLotCard(l,false)+hqPrintBtn(l))}
function hqPrinted(l){return !!(l&&l.sheet_meta&&l.sheet_meta.saved_at)}
function hqPrintBtn(l){return hqPrinted(l)?`<button class="btn hqBtnPrint" style="width:100%;margin:-4px 0 14px" ${seikaEventAttrs("click","hqSheetPage",[l.qr_key])}>印刷済み（もう一度印刷する）</button>`:`<div style="margin:-4px 0 0;padding:6px 10px;border-radius:10px 10px 0 0;background:#dc2626;color:#fff;font-weight:900">未印刷</div><button class="btn hqBtnPrint" style="width:100%;margin:0 0 14px;border-radius:0 0 12px 12px" ${seikaEventAttrs("click","hqSheetPage",[l.qr_key])}>本社移動用の貼り紙を印刷</button>`}
function hqGroupedHtml(rows,cardFn){
 return hqShipGroups(rows).map(g=>`<div class="hqGroupHead" style="margin:16px 0 8px;padding:10px 12px;border-radius:12px;background:#1e293b;color:#fff;font-weight:900;font-size:17px">${esc(g.label)}　${g.rows.length}件</div>`+g.rows.map(cardFn).join("")).join("");
}
function hqSwitchHtml(){if(hqOnlyHq())return"";const s=hqSite();return `<div class="card hqSiteBar"><div><b>いまの画面：${s==="honsha"?"本社":"石岡青果センター"}</b><div class="small">石岡と本社の画面を切り替えられます。</div></div><button class="btn hqBtnSwitch" ${seikaEventAttrs("click","hqSetSite",[s==="honsha"?"ishioka":"honsha"])}>${s==="honsha"?"石岡の画面へ":"本社の画面へ"}</button></div>`}

/* ---- 本社ホーム ---- */
function hqHome(msg=""){
 setScreen("hqHome",[msg]);
 const b=(cls,act,label,sub="")=>`<button class="btn ${cls}" ${seikaEventAttrs("click",act,[])}>${label}${sub?`<br><span style="font-size:14px;font-weight:700">${sub}</span>`:""}</button>`;
 const stockKids=hqStockHubItems(),entryKids=hqEntryHubItems();
 const btns=[
  b("hqBtnPending","hqPendingPage","入荷待ち原料",'<span id="hqPendingCount">…</span>'),
  b("hqBtnScan","hqScanPage","QR読み取り（受け入れ・出庫）"),
  stockKids.length?b("hqBtnStockHub","hqStockHub","在庫管理",'<span id="hqStockCount">…</span>'):"",
  entryKids.length?b("hqBtnEntryHub","hqEntryHub","入荷登録・品目"):"",
  b("hqBtnGuide","v195RoleGuidePage","操作ガイド")
 ].join("");
 pageShell("SEIKA＋",`本社 / ${esc(db.user||"")}（${esc(ROLE[role()]||role())}）`,`${okHtml(msg)}${hqSwitchHtml()}${hqViewOnly()?'<div class="card notice">本社の画面は見るだけです（入力・出庫は本社のアカウントと管理者が行います）。</div>':""}<div class="homePrimary hqHomeGrid">${btns}</div>`,{noBack:true});
 Promise.all([hqLots("select=id,source_kind&status=eq.入荷待ち"),hqLots("select=id&status=eq.在庫あり")]).then(([p,s])=>{
  const a=document.getElementById("hqPendingCount"),c=document.getElementById("hqStockCount");
  const mv=p.filter(x=>x.source_kind==="石岡から").length,dr=p.length-mv;
  if(a)a.textContent=`移動中 ${mv}件${dr?`・直接入荷 ${dr}件`:""}`;if(c)c.textContent=`本社在庫 ${s.length}ロット`;
 }).catch(()=>{});
}
function hqHubBtn(cls,act,label,sub=""){return `<button class="btn ${cls}" ${seikaEventAttrs("click",act,[])}>${label}${sub?`<br><span style="font-size:14px;font-weight:700">${sub}</span>`:""}</button>`}
function hqStockHubItems(){return[["hqBtnStock","hqStockPage","本社在庫",'<span id="hqHubStockCount"></span>'],["hqBtnTable","hqTablePage","在庫表","QR品目＋通常在庫（kg）"],hqCanNormal()?["hqBtnNormal","hqNormalPage","通常在庫入力"]:null,hqCanOut()?["hqBtnOut","hqOutPage","使用出庫"]:null,["hqBtnHistory","hqHistoryPage","入出庫履歴"]].filter(Boolean)}
function hqEntryHubItems(){return[hqCanReceive()?["hqBtnDirect","hqDirectPage","本社直接入荷"]:null,hqCanItems()?["hqBtnItems","hqItemsPage","品目の追加・変更"]:null].filter(Boolean)}
function hqStockHub(){
 setScreen("hqStockHub",[]);
 pageShell("在庫管理","本社の在庫・使用出庫・入出庫履歴",`${hqViewOnly()?'<div class="card notice">本社の画面は見るだけです。</div>':""}<div class="homePrimary hqHomeGrid">${hqStockHubItems().map(x=>hqHubBtn(...x)).join("")}</div>`);
 hqLots("select=id&status=eq.在庫あり").then(s=>{const c=document.getElementById("hqHubStockCount");if(c)c.textContent=`${s.length}ロット`}).catch(()=>{});
}
function hqEntryHub(){
 setScreen("hqEntryHub",[]);const it=hqEntryHubItems();if(!it.length)return home();
 pageShell("入荷登録・品目","本社直接入荷・品目の追加・変更",`<div class="homePrimary hqHomeGrid">${it.map(x=>hqHubBtn(...x)).join("")}</div>`);
}
function hqIshiokaView(msg=""){
 setScreen("hqIshiokaView",[msg]);
 pageShell("SEIKA＋",`石岡青果センター（確認のみ） / ${esc(db.user||"")}`,`${okHtml(msg)}${hqSwitchHtml()}<div class="card notice">本社のアカウントでは、石岡の在庫は見るだけです。入力や出庫はできません。</div><div class="homePrimary hqHomeGrid">
 <button class="btn hqBtnStock" ${seikaEventAttrs("click","qrTotalsPage",[])}>QR 品目別在庫量</button>
 <button class="btn hqBtnPending" ${seikaEventAttrs("click","qrLotListPage",[])}>QRロット一覧</button>
 <button class="btn hqBtnHistory" ${seikaEventAttrs("click","weeklyData",[])}>在庫表</button>${typeof c91IshiokaButtons==="function"?c91IshiokaButtons():""}</div>`,{noBack:true});
}

/* ---- 一覧 ---- */
async function hqPendingPage(msg=""){
 setScreen("hqPendingPage",[msg]);
 pageShell("入荷待ち原料","石岡から移動中の原料と本社直接入荷",`${okHtml(msg)}<div id="hqList"><div class="notice">読み込んでいます…</div></div>`);
 try{
  const rows=await hqLots("select=*&status=eq.入荷待ち&order=planned_date.asc,created_at.asc&limit=300");await hqLoadLimits();
  document.getElementById("hqList").innerHTML=rows.length?`<div class="small" style="margin:4px 0 10px">${rows.length}件。出庫日・発注分ごとにまとめています。届いた原料のQRを読み取るか「開く」を押して、品質評価と確定をしてください。</div>`+hqGroupedHtml(rows,l=>hqLotCard(l)):'<div class="notice">入荷待ちの原料はありません。</div>';
 }catch(e){document.getElementById("hqList").innerHTML=`<div class="err">${esc(hqErr(e))}</div>`}
}
async function hqStockPage(filter="",stock="在庫あり"){
 stock=["在庫あり","在庫なし","すべて"].includes(stock)?stock:"在庫あり";setScreen("hqStockPage",[filter,stock]);
 const tabs=["在庫あり","在庫なし","すべて"].map(x=>`<button class="filterBtn ${x===stock?"on":""}" ${seikaEventAttrs("click","hqStockPage",[filter,x])}>${x}</button>`).join("");
 pageShell("本社在庫","確定済みの原料だけが入ります",`<div class="card"><div class="filterBtns">${tabs}</div>${stock!=="在庫あり"?'<div class="small" style="margin-top:6px">在庫なしは、最近30日に動きがあったロットだけ出ます。間違えた出庫は、ロットを開いて「このロットの履歴」から取り消せます。</div>':""}<input id="hqStockFilter" class="input" style="margin-top:8px" placeholder="品名・ロット番号・仕入先で絞り込み" value="${esc(filter)}" ${seikaEventAttrs("change","hqStockPage",[{__seikaValue:true},stock])}></div><div id="hqList"><div class="notice">読み込んでいます…</div></div>`);
 try{
  const since=new Date(Date.now()-30*864e5).toISOString();
  const q=x=>hqLots(x==="在庫あり"?"select=*&status=eq.在庫あり&order=item_name.asc,hq_received_date.asc&limit=1000":`select=*&status=eq.在庫なし&updated_at=gte.${encodeURIComponent(since)}&order=updated_at.desc&limit=500`);
  let rows=stock==="すべて"?[...await q("在庫あり"),...await q("在庫なし")]:await q(stock);await hqLoadLimits();
  const f=filter.trim();if(f)rows=rows.filter(l=>[l.item_name,l.lot_no,l.supplier,l.origin].some(x=>String(x||"").includes(f)));
  const sum={};rows.filter(l=>l.status==="在庫あり").forEach(l=>{const k=l.item_name+"|"+l.unit;sum[k]=(sum[k]||0)+Number(l.current_qty||0)});
  const total=Object.entries(sum).map(([k,v])=>{const[n,u]=k.split("|");return `<tr><td style="padding:8px 4px;border-bottom:1px solid #e2e8f0">${esc(n)}</td><td style="padding:8px 4px;border-bottom:1px solid #e2e8f0;text-align:right;white-space:nowrap"><b>${hqQty(v)}</b> ${esc(u)}</td></tr>`}).join("");
  document.getElementById("hqList").innerHTML=rows.length?(total?`<div class="card"><b>品目ごとの合計</b><table style="width:100%;margin-top:8px;border-collapse:collapse;font-size:15px">${total}</table></div>`:"")+rows.map(l=>hqLotCard(l)).join(""):`<div class="notice">${stock==="在庫あり"?"本社の在庫はありません。":"該当するロットはありません。"}</div>`;
 }catch(e){document.getElementById("hqList").innerHTML=`<div class="err">${esc(hqErr(e))}</div>`}
}
async function hqOutPage(filter=""){
 setScreen("hqOutPage",[filter]);
 if(!hqCanOut())return hqHome();
 pageShell("使用出庫","古いものから順に並んでいます",`<button class="btn hqBtnScan" style="width:100%" ${seikaEventAttrs("click","hqScanPage",[])}>QRを読み取って出庫</button><div class="card"><input id="hqOutFilter" class="input" placeholder="品名で絞り込み" value="${esc(filter)}" ${seikaEventAttrs("change","hqOutPage",[{__seikaValue:true}])}></div><div id="hqList"><div class="notice">読み込んでいます…</div></div>`);
 try{
  let rows=await hqLots("select=*&status=eq.在庫あり&order=hq_received_date.asc,created_at.asc&limit=1000");await hqLoadLimits();
  const f=filter.trim();if(f)rows=rows.filter(l=>String(l.item_name).includes(f));
  document.getElementById("hqList").innerHTML=rows.map(l=>hqLotCard(l)).join("")||'<div class="notice">出庫できる在庫はありません。</div>';
 }catch(e){document.getElementById("hqList").innerHTML=`<div class="err">${esc(hqErr(e))}</div>`}
}

/* ---- ロット画面（受け入れ・出庫・調整） ---- */
async function hqLotPage(key,msg=""){
 key=String(key||"");setScreen("hqLotPage",[key,msg]);hqPhotos=[];
 pageShell("本社の原料","",`<div class="notice">読み込んでいます…</div>`);
 let l,moves=[],dests=[];
 try{
  const rows=await hqLots(`select=*&or=(qr_key.eq.${encodeURIComponent(key)},lot_no.eq.${encodeURIComponent(key)})&limit=1`);
  l=rows[0];if(!l)return pageShell("本社の原料","見つかりません",`<div class="err">この原料は見つかりません。</div>`);
  await hqLoadLimits();
  [moves,dests]=await Promise.all([qrSelect("hq_lot_movements_v1400",`select=*&lot_id=eq.${l.id}&order=occurred_at.desc&limit=50`),qrSelect("hq_destinations_v1400","select=*&active=eq.true&order=sort_order.asc")]);
 }catch(e){return pageShell("本社の原料","エラー",`<div class="err">${esc(hqErr(e))}</div>`)}
 let body=okHtml(msg)+hqLotCard(l,false);
 if(l.status==="入荷待ち"){
  if(hqCanReceive())body+=hqReceiveForm(l);else body+='<div class="card notice">まだ受け入れが確定していません。荷受け担当者または本社社員が確定すると本社の在庫になります。</div>';
  if(hqCanPrint()&&l.source_kind==="石岡から")body+=`<button class="btn hqBtnPrint" style="width:100%" ${seikaEventAttrs("click","hqSheetPage",[l.qr_key])}>本社移動用の貼り紙を印刷</button>`;
  if(hqCanAdjust()&&l.source_kind==="本社直接入荷")body+=`<button class="btn red" style="width:100%" ${seikaEventAttrs("click","hqCancelPending",[l.id,l.qr_key])}>この入荷を取消</button>`;
 }else{
  if(l.grade)body+=`<div class="card"><b>品質評価</b> ${hqGradeBadge(l.grade)}<div class="small">${esc((l.issues||[]).join("・"))} ${esc(l.quality_memo||"")}</div><div class="small">${esc(l.evaluated_by_name||"")} / 確定 ${l.confirmed_at?esc(new Date(l.confirmed_at).toLocaleString("ja-JP")):""}</div>${(l.photo_paths||[]).length?`<button class="btn btn2" style="margin-top:8px" ${seikaEventAttrs("click","hqShowPhotos",[l.id])}>写真を見る（${l.photo_paths.length}枚）</button><div id="hqPhotoView"></div>`:""}</div>`;
  if(l.status==="在庫あり"&&hqCanOut())body+=`<div class="card"><b>使用出庫</b><label class="label" style="margin-top:8px">出庫先</label><select id="hqDest" class="input"><option value="">選んでください</option>${dests.map(d=>`<option>${esc(d.name)}</option>`).join("")}</select><label class="label" style="margin-top:8px">出庫する数量（${esc(l.unit)}・在庫 ${hqQty(l.current_qty)}）</label><input id="hqOutQty" class="input" inputmode="decimal" placeholder="例：2"><div style="display:flex;gap:8px;margin-top:8px"><button class="btn btn2" style="flex:1" ${seikaEventAttrs("click","hqFillAll",[hqQty(l.current_qty)])}>全部</button></div><label class="label" style="margin-top:8px">メモ（任意）</label><input id="hqOutMemo" class="input"><button class="btn hqBtnOut" style="width:100%;margin-top:12px" ${seikaEventAttrs("click","hqDoOut",[l.id,l.qr_key])}>出庫する</button></div>`;
  if(hqCanAdjust()&&l.status!=="取消")body+=`<details class="card"><summary><b>実数調整（本社社員）</b></summary><label class="label" style="margin-top:8px">実際の数量（${esc(l.unit)}）</label><input id="hqAdjQty" class="input" inputmode="decimal" value="${hqQty(l.current_qty)}"><label class="label" style="margin-top:8px">理由</label><input id="hqAdjReason" class="input" placeholder="例：数え直し"><button class="btn orange" style="width:100%;margin-top:10px" ${seikaEventAttrs("click","hqDoAdjust",[l.id,l.qr_key])}>実数に合わせる</button></details>`;
  if(hqCanPrint()&&!hqViewOnly()||hqCanPrint()&&l.source_kind==="石岡から")body+=`<button class="btn hqBtnPrint" style="width:100%" ${seikaEventAttrs("click","hqSheetPage",[l.qr_key])}>${l.source_kind==="本社直接入荷"?"貼り紙を印刷":"本社移動用の貼り紙を印刷し直す"}</button>`;
  if(hqCanAdjust()&&(l.status==="在庫あり"||l.status==="在庫なし"))body+=`<details class="card"><summary><b>受け入れ確定を取り消す（本社社員）</b></summary><div class="small" style="margin-top:6px">取り消すと「入荷待ち」に戻り、品質評価と確定をやり直せます。出庫や実数調整がある場合は、先にそれを取り消してください。</div><button class="btn red" style="width:100%;margin-top:10px" ${seikaEventAttrs("click","hqCancelReceive",[l.id,l.qr_key])}>受け入れ確定を取り消す</button></details>`;
 }
 body+=`<div class="card"><b>このロットの履歴</b>${moves.map(m=>`<div style="padding:8px 0;border-top:1px solid rgba(148,163,184,.28)${m.cancelled_at?";opacity:.55":""}"><b>${esc(m.movement_type)}</b> ${hqQty(m.qty)}${esc(m.unit||"")}${m.destination?` → ${esc(m.destination)}`:""}${m.cancelled_at?' <span class="badge unset">取消済み</span>':""}<div class="small">${esc(m.user_name||"")} / ${esc(new Date(m.occurred_at).toLocaleString("ja-JP"))}${m.reason?` / ${esc(m.reason)}`:""}${m.memo?` / ${esc(m.memo)}`:""}</div>${hqCanCancelOut(m)&&l.status!=="取消"?`<button class="btn red" style="margin-top:6px;min-height:40px" ${seikaEventAttrs("click","hqCancelOut",[m.id,l.qr_key])}>この出庫を取り消す</button>`:""}</div>`).join("")||'<div class="small">まだありません。</div>'}</div>`;
 pageShell("本社の原料",`${esc(l.item_name)} / ${esc(l.status)}`,body);
}
function hqReceiveForm(l){
 return `<div class="card hqReceive"><b style="font-size:18px">受け入れ（品質評価と確定）</b>
 <div class="small" style="margin-top:8px">予定：${esc(hqPlanText(l))}</div><label class="label" style="margin-top:10px">届いた数量（${esc(l.unit)}）</label><input id="hqRecvQty" class="input" inputmode="decimal" value="${hqQty(l.planned_qty)}"><div class="small">予定と違うときは、実際の数量に直してください。</div>
 <label class="label" style="margin-top:10px">品質評価</label><div class="hqGrades">${Object.entries(HQ_GRADE).map(([k,v])=>`<label class="hqGrade hqGrade_${k}"><input type="radio" name="hqGrade" value="${k}" ${k==="good"?"checked":""} ${seikaEventAttrs("change","hqToggleGrade",[])}> ${v}</label>`).join("")}</div>
 <div id="hqIssueBox" style="display:none"><label class="label" style="margin-top:10px">気になった点</label><div class="hqIssues">${HQ_ISSUES.map(x=>`<label><input type="checkbox" class="hqIssue" value="${esc(x)}"> ${esc(x)}</label>`).join("")}</div>
 <label class="label" style="margin-top:10px">写真（要確認・不良は1枚以上必須）</label><input id="hqPhotoInput" type="file" accept="image/*" capture="environment" multiple class="input" ${seikaEventAttrs("change","hqAddPhotos",[])}><div id="hqPhotoList" class="small">写真はまだありません。</div></div>
 <label class="label" style="margin-top:10px">メモ（任意）</label><input id="hqRecvMemo" class="input">
 <button id="hqRecvBtn" class="btn hqBtnConfirm" style="width:100%;margin-top:14px" ${seikaEventAttrs("click","hqDoReceive",[l.id,l.qr_key])}>確定して本社の在庫にする</button>
 <div class="small" style="margin-top:6px">「確定」を押したときに本社の在庫になります。</div></div>`}
function hqToggleGrade(){const g=document.querySelector('input[name="hqGrade"]:checked')?.value;const box=document.getElementById("hqIssueBox");if(box)box.style.display=g&&g!=="good"?"block":"none"}
async function hqAddPhotos(){
 const input=document.getElementById("hqPhotoInput");const files=[...(input?.files||[])];
 try{for(const f of files){if(hqPhotos.length>=5){alert("写真は5枚までです");break}hqPhotos.push(await v1102CompressPhoto(f))}}catch(e){alert(hqErr(e))}
 if(input)input.value="";hqRenderPhotos();
}
function hqRenderPhotos(){const el=document.getElementById("hqPhotoList");if(!el)return;el.innerHTML=hqPhotos.length?hqPhotos.map((p,i)=>`<span class="badge normal" style="margin:3px">写真${i+1} <button class="btn btn2" style="padding:2px 8px;min-height:0" ${seikaEventAttrs("click","hqRemovePhoto",[i])}>×</button></span>`).join(""):"写真はまだありません。"}
function hqRemovePhoto(i){hqPhotos.splice(i,1);hqRenderPhotos()}
async function hqUpload(lotId,blob){
 if(!await authEnsure())throw new Error("再ログインしてください");
 const path=`${lotId}/${newId()}.jpg`,enc=path.split("/").map(encodeURIComponent).join("/");
 const res=await fetch(`${SUPABASE_URL}/storage/v1/object/${HQ_BUCKET}/${enc}`,{method:"POST",headers:{apikey:SUPABASE_KEY,Authorization:"Bearer "+authToken(),"Content-Type":blob.type||"image/jpeg","x-upsert":"false"},body:blob});
 if(!res.ok)throw new Error("写真を保存できませんでした："+await res.text());return path;
}
async function hqDoReceive(lotId,key){
 if(hqBusy)return;
 const qty=Number(String(document.getElementById("hqRecvQty")?.value||"").replace(/[０-９．]/g,c=>String.fromCharCode(c.charCodeAt(0)-0xfee0)));
 const grade=document.querySelector('input[name="hqGrade"]:checked')?.value;
 if(!Number.isFinite(qty)||qty<0)return alert("届いた数量を入れてください");
 if(!grade)return alert("品質評価を選んでください");
 if(grade!=="good"&&!hqPhotos.length)return alert("要確認・不良のときは写真を1枚以上付けてください");
 const issues=[...document.querySelectorAll(".hqIssue:checked")].map(x=>x.value);
 if(!confirm(`${HQ_GRADE[grade]}・${hqQty(qty)} で確定します。確定すると本社の在庫になります。よろしいですか？`))return;
 hqBusy=true;const btn=document.getElementById("hqRecvBtn");if(btn){btn.disabled=true;btn.textContent="保存中…"}
 try{
  const paths=[];if(grade!=="good")for(const p of hqPhotos)paths.push(await hqUpload(lotId,p.blob));
  await hqRpc("hq_receive_v1400",{p_operation_id:newId(),p_lot_id:lotId,p_qty:qty,p_grade:grade,p_issues:grade==="good"?[]:issues,p_quality_memo:document.getElementById("hqRecvMemo")?.value||null,p_photo_paths:paths});
  hqBusy=false;hqPhotos=[];
  const direct=(await hqLots(`select=source_kind&id=eq.${lotId}`).catch(()=>[]))[0]?.source_kind==="本社直接入荷";
  const done=grade==="good"?"確定しました。本社の在庫に入りました。":"確定しました。要確認・不良は社員に伝えてください。";
  if(direct&&hqCanPrint())return hqSheetPage(key,done+"続けて貼り紙を印刷してください。");
  return hqLotPage(key,done);
 }catch(e){alert(hqErr(e));if(btn){btn.disabled=false;btn.textContent="確定して本社の在庫にする"}}
 hqBusy=false;
}
function hqFillAll(v){const el=document.getElementById("hqOutQty");if(el)el.value=v}
async function hqDoOut(lotId,key){
 if(hqBusy)return;
 const dest=document.getElementById("hqDest")?.value||"",qty=Number(String(document.getElementById("hqOutQty")?.value||"").replace(/[０-９．]/g,c=>String.fromCharCode(c.charCodeAt(0)-0xfee0)));
 if(!dest)return alert("出庫先を選んでください");if(!Number.isFinite(qty)||qty<=0)return alert("数量を入れてください");
 if(window.hqLimitGuard){let lot=null;try{lot=(await hqLots(`select=*&id=eq.${encodeURIComponent(lotId)}&limit=1`))[0]}catch(_){}if(lot&&!window.hqLimitGuard(lot,`${dest}へ出庫`))return}
 if(!confirm(`${dest}へ ${hqQty(qty)} 出庫します。よろしいですか？`))return;
 hqBusy=true;
 try{await hqRpc("hq_outbound_v1400",{p_operation_id:newId(),p_lot_id:lotId,p_qty:qty,p_destination:dest,p_memo:document.getElementById("hqOutMemo")?.value||null});hqBusy=false;return hqLotPage(key,`${dest}へ出庫しました`)}
 catch(e){alert(hqErr(e))}hqBusy=false;
}
async function hqDoAdjust(lotId,key){
 if(hqBusy)return;
 const qty=Number(document.getElementById("hqAdjQty")?.value),reason=document.getElementById("hqAdjReason")?.value.trim()||"";
 if(!Number.isFinite(qty)||qty<0)return alert("実際の数量を入れてください");if(!reason)return alert("理由を入れてください");
 if(!confirm(`在庫を ${hqQty(qty)} に合わせます。よろしいですか？`))return;
 hqBusy=true;
 try{await hqRpc("hq_adjust_v1400",{p_operation_id:newId(),p_lot_id:lotId,p_after_qty:qty,p_reason:reason});hqBusy=false;return hqLotPage(key,"実数に合わせました")}
 catch(e){alert(hqErr(e))}hqBusy=false;
}
async function hqCancelPending(lotId,key){
 const reason=prompt("取消の理由を入れてください");if(reason===null)return;
 try{await hqRpc("hq_cancel_pending_v1400",{p_lot_id:lotId,p_reason:reason});return hqPendingPage("入荷を取消しました")}catch(e){alert(hqErr(e))}
}
async function hqShowPhotos(lotId){
 const box=document.getElementById("hqPhotoView");if(!box)return;box.innerHTML='<div class="small">読み込んでいます…</div>';
 try{
  const l=(await hqLots(`select=photo_paths&id=eq.${lotId}`))[0];const urls=[];
  for(const p of l?.photo_paths||[]){const enc=p.split("/").map(encodeURIComponent).join("/");const r=await fetch(`${SUPABASE_URL}/storage/v1/object/sign/${HQ_BUCKET}/${enc}`,{method:"POST",headers:{apikey:SUPABASE_KEY,Authorization:"Bearer "+authToken(),"Content-Type":"application/json"},body:JSON.stringify({expiresIn:300})});if(r.ok){const a=await r.json();urls.push(SUPABASE_URL+"/storage/v1"+(a.signedURL||a.signedUrl))}}
  box.innerHTML=urls.map(u=>`<img src="${esc(u)}" style="width:100%;margin-top:8px;border-radius:10px">`).join("")||'<div class="small">写真を開けませんでした。</div>';
  box.querySelectorAll("img").forEach(im=>im.addEventListener("error",()=>{const d=document.createElement("div");d.className="small";d.style.cssText="color:#b91c1c;font-weight:700;margin-top:8px";d.textContent="この写真は保存されていません。品質評価一覧の「写真を追加」から登録し直してください。";im.replaceWith(d)}));
 }catch(e){box.innerHTML=`<div class="err">${esc(hqErr(e))}</div>`}
}

/* ---- 貼り紙 ---- */
function hqSheetHtml(l,pages){
 if(!Array.isArray(pages)||!pages.length)pages=[{label:"",qty:""}];
 const payload=location.origin+location.pathname+"?qr="+encodeURIComponent(l.qr_key);
 const qr=qrDataUrlForPosterHq(payload),fromIshioka=l.source_kind==="石岡から",via=!!l.via_ishioka,big=(fromIshioka||via)&&l.unit==="kg";
 const viaShip=via?[l.ship_run?`${l.ship_run}${l.ship_run_time?` ${l.ship_run_time}着`:""}`:"",l.ship_day||""].filter(Boolean).join("・"):"";
 const qtyLabel=`${hqQty(l.status==="入荷待ち"?l.planned_qty:l.received_qty)} ${l.unit==="kg"?"kg":"ケース"}`;
 const row=(k,v,cls="")=>`<tr><th>${k}</th><td class="${cls}">${esc(v||"-")}</td></tr>`;
 const lotCount=(()=>{for(const pg of pages){const m=String(pg.note||"").match(/（(\d+)基）/);if(m)return m[1]}const c=Number(l.sheet_meta?.count||l.measured_count||0);return c>0?String(c):""})();
 return `<!doctype html><html lang="ja"><head><meta charset="utf-8"><title>${fromIshioka||via?"本社移動用":"本社入荷"} ${esc(l.item_name)}</title><style>
 @page{size:A4 landscape;margin:10mm}*{-webkit-print-color-adjust:exact;print-color-adjust:exact;box-sizing:border-box}body{margin:0;font-family:"Hiragino Sans","Noto Sans JP",sans-serif}
 .bar{position:sticky;top:0;display:flex;gap:10px;padding:10px;background:#f1f5f9}.bar button{font-size:18px;padding:10px 18px}@media print{.bar{display:none}}
 .sheet{border:4px solid #000;height:186mm;display:flex;flex-direction:column;color:#000}.head{background:#fff;color:#000;display:flex;justify-content:space-between;align-items:center;padding:3mm 7mm;border-bottom:3px solid #000}.head h1{margin:0;font-size:30pt;font-weight:900;color:#000}.head span{font-size:12pt;font-weight:700;color:#000}
 .main{display:flex;flex:1;padding:3mm 6mm}.left{flex:1}.sheet.ishioka{border-width:2mm}.sheet.ishioka .left{display:flex;flex-direction:column}.sheet.ishioka .left table{flex:1;height:100%}.right{width:78mm;border-left:2px solid #000;display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center;font-size:11pt;font-weight:700;color:#000}
 table{width:100%;border-collapse:collapse}th{width:34mm;text-align:left;vertical-align:middle;color:#000;font-weight:800;font-size:12pt;border-bottom:1.5px solid #000}td{font-size:26pt;font-weight:700;color:#000;padding:2.5mm 0;border-bottom:1.5px solid #000}
 .sheet{page-break-after:always;break-after:page;margin-bottom:6mm}.sheet:last-child{page-break-after:auto;break-after:auto}td.this{font-size:34pt;font-weight:900}td.this small{font-size:16pt;font-weight:800;color:#000;margin-left:4mm}
 td.name{font-size:46pt;font-weight:900}td.name small.spec{font-size:20pt;font-weight:800;margin-left:5mm}td.name .nameLine{display:flex;align-items:baseline;gap:5mm;line-height:1.1}td.name .nameLine .item{flex:1 1 auto;min-width:0;overflow-wrap:anywhere}td.name .nameLine small.spec{flex:0 1 auto;min-width:0;max-width:30%;line-height:1.1;overflow-wrap:anywhere;margin-left:0}td.date{color:#000;font-size:34pt;font-weight:900}td.small{font-size:14pt;font-weight:800;color:#000!important}td.total{font-size:34pt;font-weight:900;color:#000}.right img{width:58mm;height:58mm;image-rendering:pixelated}.right .sub{color:#000!important}
 </style></head><body><div class="bar"><button onclick="window.close()">閉じる</button><button onclick="window.print()">印刷</button></div>
 ${pages.map(pg=>`<div class="sheet${fromIshioka||via?" ishioka":""}"><div class="head"><h1>${fromIshioka?"石岡 → 本社":via?"石岡経由 → 本社":"本社入荷"}</h1><span>SEIKA＋　${fromIshioka?"石岡青果センター発":via?"本社直接入荷（石岡経由）":"本社"}</span></div><div class="main"><div class="left"><table>
 <tr><th>品名</th><td class="name">${hqSpecOf(l)?`<span class="nameLine"><span class="item">${esc(l.item_name||"-")}</span><small class="spec">${esc(hqSpecOf(l))}</small></span>`:esc(l.item_name||"-")}</td></tr>${row("本社入荷日",hqDateLabel(l.hq_received_date||l.planned_date),"date")}${pg.qty?`<tr><th>${l.unit==="kg"?"この容器":"このパレット"}</th><td class="this">${esc(pg.qty)}<small>${esc(pg.label)}</small>${pg.note&&!(big&&/^実測合計/.test(pg.note))?`<div style="font-size:15pt;font-weight:800">${esc(pg.note)}</div>`:""}</td></tr>`:""}${row("ロット合計",big&&lotCount?`${qtyLabel}（${lotCount}基）`:qtyLabel,"total")}${big?"":row("量目",l.unit==="kg"&&Number(l.sheet_meta?.per||l.unit_weight_kg)>0?`1基 ${hqQty(l.sheet_meta?.per||l.unit_weight_kg)}kg`:(hqPackOf(l)?`${hqPackOf(l)}`:"-"))}${row("仕入先",l.supplier)}${row("産地",l.origin)}${fromIshioka||via&&l.supplier?"":row("単協名",l.cooperative_name,"small")}
 </table></div><div class="right"><img src="${qr}" alt="QR"><div style="margin-top:4mm">本社で読み取ると<br>${fromIshioka?"入荷待ち原料":"この原料"}が開きます</div><div class="sub" style="margin-top:3mm;font-size:10pt">${fromIshioka?`元ロット No. ${esc(l.source_lot_no||"-")}<br>`:""}本社ロット No. ${esc(l.lot_no)}</div>${fromIshioka?`<div class="ishiokaDate" style="margin-top:4mm;padding-top:3mm;border-top:1.5px solid #000;width:66mm"><div style="font-size:11pt;font-weight:800">石岡入荷日</div><div style="font-size:18pt;font-weight:900;margin-top:1mm">${esc(hqDateLabel(l.ishioka_received_date)||"-")}</div></div>`:""}${via?`<div class="viaIshioka" style="margin-top:4mm;padding-top:3mm;border-top:1.5px solid #000;width:66mm"><div style="font-size:16pt;font-weight:900">石岡経由</div><div style="font-size:11pt;font-weight:800;margin-top:1mm">便</div><div style="font-size:15pt;font-weight:900">${esc(viaShip||"-")}</div><div style="font-size:11pt;font-weight:800;margin-top:1mm">出庫者</div><div style="font-size:15pt;font-weight:900">${esc(l.created_by_name||"-")}</div></div>`:""}</div></div></div>`).join("")}</body></html>`;
}
function qrDataUrlForPosterHq(payload){if(typeof qrcode!=="function")throw new Error("QRを作れませんでした");const q=qrcode(0,"M");q.addData(String(payload));q.make();return q.createDataURL(10,2)}
function hqOpenSheet(w,l){if(!w)return alert("印刷画面を開けませんでした。ポップアップを許可してください。");w.document.open();w.document.write(hqSheetHtml(l));w.document.close()}
async function hqPrintLot(key){
 if(!hqCanPrint())return alert("印刷の権限がありません");
 return hqSheetPage(key);
 const w=window.open("","_blank");
 try{const l=(await hqLots(`select=*&qr_key=eq.${encodeURIComponent(key)}`))[0];if(!l)throw new Error("原料が見つかりません");hqOpenSheet(w,l)}catch(e){w?.close();alert(hqErr(e))}
}
async function hqPrintFromPage(key){
 const d=document.getElementById("hqPlanned")?.value||"";
 try{
  let l=(await hqLots(`select=*&qr_key=eq.${encodeURIComponent(key)}`))[0];if(!l)throw new Error("原料が見つかりません");
  if(d&&d!==l.planned_date){await hqRpc("hq_set_planned_date_v1400",{p_lot_id:l.id,p_date:d});l={...l,planned_date:d}}
  await hqMakePdf(l);
 }catch(e){alert(hqErr(e))}
}
let hqLastPdfUrl="";
function hqPdfStatus(msg,type="notice",url="",name=""){
 let host=document.getElementById("hqPdfStatus");
 if(!host){const t=document.querySelector(".wrap")||document.querySelector(".appShell")||document.body;host=document.createElement("div");host.id="hqPdfStatus";t.prepend(host)}
 const open=url?`<a class="btn blue" style="display:block;width:100%;margin-top:10px;text-decoration:none;text-align:center" href="${esc(url)}" target="_blank" rel="noopener" aria-label="${esc(name||"PDF")}を開いて印刷">PDFを開く・印刷</a>`:"";
 host.innerHTML=`<div class="${type}">${msg}${open}</div>`;try{host.scrollIntoView({block:"start"})}catch(_){}
}
function hqScopeCss(css){
 css=css.replace(/@page\{[^}]*\}/g,"").replace(/@media print\{[^{}]*\{[^}]*\}\}/g,"");
 return css.split("}").map(r=>{const i=r.indexOf("{");if(i<0)return"";const sel=r.slice(0,i).trim(),body=r.slice(i+1);
  if(!sel||sel==="*"||sel==="body"||sel.startsWith(".bar"))return"";
  return sel.split(",").map(s=>".hqPdfRoot "+s.trim()).join(",")+"{"+body+"}"}).join("");
}
function hqFitSheetSpec(sheet){
 const line=sheet.querySelector("td.name .nameLine");if(!line)return;
 const item=line.querySelector(".item"),spec=line.querySelector(".spec"),table=sheet.querySelector("table"),main=sheet.querySelector(".main");
 const bounds=sheet.getBoundingClientRect(),style=getComputedStyle(sheet),padding=getComputedStyle(main);
 const bottom=bounds.bottom-parseFloat(style.borderBottomWidth)-parseFloat(padding.paddingBottom);
 const fits=()=>{
  if(table.getBoundingClientRect().bottom>bottom+1)return false;
  return [...sheet.querySelectorAll("th,td,.head h1,.head span,.right img,.right div")].every(el=>{
   const r=el.getBoundingClientRect(),range=document.createRange();range.selectNodeContents(el);
   return r.bottom<=bounds.bottom-parseFloat(style.borderBottomWidth)+1&&r.right<=bounds.right-parseFloat(style.borderRightWidth)+1&&[...range.getClientRects()].every(t=>t.bottom<=r.bottom+1&&t.right<=r.right+1&&t.left>=r.left-1);
  });
 };
 for(let size=46;!fits();){
  if(size<=28)throw new Error("品名と規格が貼り紙の枠に収まりません。品名や規格を短くして、もう一度印刷してください。");
  size--;item.style.fontSize=`${size}pt`;spec.style.fontSize=`${Math.max(12,20*size/46)}pt`;
 }
}
async function hqMakePdf(l,pages){
 if(l&&l.slip_pack_error)throw new Error("入数の変更を読み込めていないため、印刷できません。通信を確認して、貼り紙の画面を開き直してください。");
 if(hqLastPdfUrl){try{URL.revokeObjectURL(hqLastPdfUrl)}catch(_){}hqLastPdfUrl=""}
 hqPdfStatus("A4横のPDFを作成中です。しばらくお待ちください…","notice");let root=null;
 try{
  if(typeof window.html2canvas!=="function")throw new Error("PDF作成用のhtml2canvasが読み込まれていません。通信状況を確認してから、もう一度お試しください。");
  if(!window.jspdf||typeof window.jspdf.jsPDF!=="function")throw new Error("PDF作成用のjsPDFが読み込まれていません。通信状況を確認してから、もう一度お試しください。");
  const d=new DOMParser().parseFromString(hqSheetHtml(l,pages),"text/html");
  const css=hqScopeCss(d.querySelector("style")?.textContent||"");
  const sheets=[...d.querySelectorAll(".sheet")];if(!sheets.length)throw new Error("貼り紙の準備に失敗しました。");
  root=document.createElement("div");root.className="hqPdfRoot";root.setAttribute("aria-hidden","true");
  root.style.cssText="position:fixed;left:-20000px;top:0;width:1122px;background:#fff;pointer-events:none;font-family:'Hiragino Sans','Noto Sans JP',sans-serif;color:#000";
  root.innerHTML=`<style>.hqPdfRoot *{box-sizing:border-box;-webkit-print-color-adjust:exact;print-color-adjust:exact}${css}.hqPdfRoot .hqPdfPage{width:1122px;height:794px;padding:38px;background:#fff;overflow:hidden}.hqPdfRoot .hqPdfPage .sheet{height:100%;margin:0}.hqPdfRoot .sheet>.head{background:#fff!important;background-image:none!important;color:#000!important;border-radius:0!important;box-shadow:none!important;border-bottom:3px solid #000!important}.hqPdfRoot .sheet>.head h1,.hqPdfRoot .sheet>.head span{color:#000!important}</style>`+sheets.map(s=>`<div class="hqPdfPage">${s.outerHTML}</div>`).join("");
  document.body.appendChild(root);
  if(document.fonts&&document.fonts.ready)await document.fonts.ready;
  if(typeof qrWaitForPosterImages==="function")await qrWaitForPosterImages(root);
  const{jsPDF}=window.jspdf,doc=new jsPDF({orientation:"landscape",unit:"mm",format:"a4",compress:true});
  const pg=[...root.querySelectorAll(".hqPdfPage")];
  for(let i=0;i<pg.length;i++){
   hqFitSheetSpec(pg[i].querySelector(".sheet"));
   const c=await window.html2canvas(pg[i],{scale:2,backgroundColor:"#ffffff",useCORS:true,logging:false,width:1122,height:794,windowWidth:1122,windowHeight:794});
   if(i)doc.addPage("a4","landscape");doc.addImage(c.toDataURL("image/png"),"PNG",0,0,297,210,undefined,"FAST");
  }
  const blob=doc.output("blob");if(!blob||!blob.size)throw new Error("PDFの作成に失敗しました。");
  const name=`本社移動用_${String(l.lot_no||"lot").replace(/[\/:*?"<>|\s]+/g,"_")}.pdf`;
  hqLastPdfUrl=URL.createObjectURL(blob);
  hqPdfStatus(`PDFを作成しました（${pg.length}枚）。下のボタンで開いて、共有からEpson iPrintなどで印刷してください。`,"ok",hqLastPdfUrl,name);
 }catch(e){hqPdfStatus(`PDFを作成できませんでした。${esc(hqErr(e))}`,"err")}
 finally{if(root)root.remove()}
}

/* ---- QR読み取り ---- */
async function hqStopReader(){const r=hqReader;hqReader=null;if(r){try{await r.stop()}catch(e){}try{r.clear()}catch(e){}}}
function hqKeyOf(raw){try{return qrExtractKey(raw)}catch(e){return String(raw||"").trim()}}
async function hqOpenKey(raw){
 const k=hqKeyOf(raw);if(!k)return;await hqStopReader();
 if(/^HQ-|^H\d{8}-/.test(k))return hqLotPage(k);
 alert("これは本社の貼り紙のQRではありません。石岡の貼り紙のQRは、石岡の画面で読み取ってください。");return hqScanPage();
}
async function hqScanPage(){
 setScreen("hqScanPage",[]);
 pageShell("QR読み取り（受け入れ・出庫）","本社移動用・本社入荷の貼り紙のQR",`<div id="hqReader" style="width:100%;min-height:300px;background:#0f172a;border-radius:14px"></div><div class="card"><label class="label">QRが読めないときはロット番号を入力</label><input id="hqKeyInput" class="input" placeholder="例：H20261022-0001"><button class="btn green" style="width:100%;margin-top:8px" ${seikaEventAttrs("click","hqOpenTyped",[])}>開く</button></div>`);
 if(typeof Html5Qrcode!=="function")return;
 try{const r=new Html5Qrcode("hqReader");hqReader=r;await r.start({facingMode:"environment"},{fps:8,qrbox:{width:240,height:240}},raw=>{if(hqReader===r)hqOpenKey(raw)})}catch(e){const el=document.getElementById("hqReader");if(el)el.innerHTML=`<div class="err">カメラを開けませんでした：${esc(hqErr(e))}</div>`}
}
function hqOpenTyped(){return hqOpenKey(document.getElementById("hqKeyInput")?.value||"")}

/* ---- 直接入荷・品目 ---- */
async function hqDirectPage(){
 setScreen("hqDirectPage",[]);if(!hqCanReceive())return hqHome();
 let items=[];try{items=await qrSelect("hq_items_v1400","select=*&active=eq.true&order=sort_order.asc")}catch(e){}
 window.__hqItems=items;
 pageShell("本社直接入荷","入庫入力 → 品質評価 → 貼り紙の印刷 の順に進みます",`<div class="card">
 <label class="label">品目 <span style="color:#dc2626">必須</span></label><select id="hqDItem" class="input" ${seikaEventAttrs("change","hqDirectItemChanged",[])}><option value="">選んでください</option>${items.map(i=>`<option>${esc(i.name)}</option>`).join("")}</select><div class="small">品目がないときは、本社社員が「入荷登録・品目」→「品目の追加・変更」で追加します。</div>
 <label class="label" style="margin-top:10px">荷姿</label><select id="hqDCont" class="input" ${seikaEventAttrs("change","hqDirectContChanged",[])}>${HQ_CONTAINERS.map(c=>`<option>${c}</option>`).join("")}</select><div class="small">網コンテナ・鉄コンテナ・パレテーナはkg、それ以外はケースで数えます。</div>
 <label class="label" style="margin-top:10px">数量 <span style="color:#dc2626">必須</span></label><input id="hqDQty" class="input" inputmode="decimal">
 <label class="label" style="margin-top:10px">量目（例：10kg） <span id="hqDPackMark" style="color:#dc2626">必須</span></label><input id="hqDPack" class="input">
 <label class="label" style="margin-top:10px">仕入先 <span style="color:#dc2626">必須</span></label><input id="hqDSup" class="input">
 <label class="label" style="margin-top:10px">産地 <span style="color:#dc2626">必須</span></label><input id="hqDOri" class="input">
 <label class="label" style="margin-top:10px">単協名（任意）</label><input id="hqDCoop" class="input">
 <label class="label" style="margin-top:10px">規格（任意）</label><input id="hqDSpec" class="input" maxlength="20" placeholder="例：3L、秀品">
 <label class="label" style="margin-top:10px">入荷日 <span style="color:#dc2626">必須</span></label><input id="hqDDate" type="date" class="input" value="${hqToday()}">
 <button class="btn hqBtnDirect" style="width:100%;margin-top:14px" ${seikaEventAttrs("click","hqDoDirect",[])}>登録して品質評価へ進む</button><div class="small" style="margin-top:6px">網コンテナ・鉄コンテナ・パレテーナは、数量に合計kgを入れます。基数は貼り紙の印刷のときに入れます。</div></div>`);
}
function hqDirectItemChanged(){const n=document.getElementById("hqDItem")?.value;const it=(window.__hqItems||[]).find(x=>x.name===n);if(!it)return;const p=document.getElementById("hqDPack");if(p&&!p.value)p.value=it.pack_weight||"";const c=document.getElementById("hqDCont");if(c&&it.default_unit==="kg")c.value="網コンテナ";hqDirectContChanged()}
function hqDirectContChanged(){const m=document.getElementById("hqDPackMark");if(m)m.style.display=HQ_BIG_CONTAINERS.includes(document.getElementById("hqDCont")?.value||"")?"none":""}
async function hqDoDirect(){
 if(hqBusy)return;const v=id=>document.getElementById(id)?.value.trim()||"";
 const qty=Number(v("hqDQty"));if(!v("hqDItem"))return hqFocus("hqDItem","品目を選んでください");if(!Number.isFinite(qty)||qty<=0)return hqFocus("hqDQty","数量を入れてください");
 if(!v("hqDPack")&&!HQ_BIG_CONTAINERS.includes(v("hqDCont")))return hqFocus("hqDPack","量目を入れてください（例：10kg）");
 if(!v("hqDSup"))return hqFocus("hqDSup","仕入先を入れてください");if(!v("hqDOri"))return hqFocus("hqDOri","産地を入れてください");if(!v("hqDDate"))return hqFocus("hqDDate","入荷日を入れてください");
 hqBusy=true;
 try{const a=await hqRpc("hq_direct_inbound_v1400",{p_item_name:v("hqDItem"),p_origin:v("hqDOri"),p_supplier:v("hqDSup"),p_cooperative_name:v("hqDCoop"),p_container_type:v("hqDCont"),p_pack_weight:v("hqDPack"),p_qty:qty,p_date:v("hqDDate"),p_memo:hqSpecMemo(v("hqDSpec"))});hqBusy=false;return hqLotPage(a.lot.qr_key,"登録しました。続けて品質評価をして確定してください。確定のあとに貼り紙を印刷します。")}
 catch(e){alert(hqErr(e))}hqBusy=false;
}
async function hqItemsPage(msg=""){
 setScreen("hqItemsPage",[msg]);if(!hqCanItems())return hqHome();
 let items=[];try{items=await qrSelect("hq_items_v1400","select=*&order=sort_order.asc")}catch(e){return pageShell("品目の追加・変更","エラー",`<div class="err">${esc(hqErr(e))}</div>`)}
 pageShell("品目の追加・変更","QR品目（本社直接入荷で選べる品目）",`${okHtml(msg)}${hqItemTabs("qr")}<div class="card"><b>品目を追加</b><label class="label" style="margin-top:8px">品目名</label><input id="hqINm" class="input" placeholder="例：加工用玉葱"><label class="label" style="margin-top:8px">ふだんの単位</label><select id="hqIUnit" class="input"><option>ケース</option><option>kg</option></select><label class="label" style="margin-top:8px">量目（任意）</label><input id="hqIPack" class="input" placeholder="例：10kg"><button class="btn hqBtnItems" style="width:100%;margin-top:10px" ${seikaEventAttrs("click","hqSaveItem",["",true])}>追加する</button></div>
 ${items.map(i=>`<div class="card"><div class="itemHead"><div><b>${esc(i.name)}</b><div class="small">${esc(i.default_unit)}${i.pack_weight?` / ${esc(i.pack_weight)}`:""}</div></div><button class="btn ${i.active?"btn2":"green"}" ${seikaEventAttrs("click","hqSaveItem",[i.name,!i.active])}>${i.active?"表示しない":"表示する"}</button></div></div>`).join("")}`);
}
async function hqSaveItem(name,active){
 let unit,pack;
 if(name){const it=(await qrSelect("hq_items_v1400",`select=*&name=eq.${encodeURIComponent(name)}`))[0];unit=it?.default_unit||"ケース";pack=it?.pack_weight||""}
 else{name=document.getElementById("hqINm")?.value.trim()||"";unit=document.getElementById("hqIUnit")?.value||"ケース";pack=document.getElementById("hqIPack")?.value.trim()||"";if(!name)return alert("品目名を入れてください")}
 try{await hqRpc("hq_save_item_v1400",{p_name:name,p_default_unit:unit,p_pack_weight:pack,p_active:active});return hqItemsPage(`${name}を保存しました`)}catch(e){alert(hqErr(e))}
}

/* ---- 通常在庫（QRで管理しない品目） ---- */
function hqItemTabs(cur){const t=(k,act,l)=>`<button class="btn ${cur===k?"hqBtnItems":"btn2"}" style="flex:1" ${seikaEventAttrs("click",act,[""])}>${l}</button>`;return `<div class="card" style="display:flex;gap:8px">${t("qr","hqItemsPage","QR品目")}${t("normal","hqNormalItemsPage","通常在庫の品目")}</div>`}
function hqKg(v){if(v==null||v==="")return"";const n=Number(v);return Number.isInteger(n)?n.toLocaleString("ja-JP"):n.toLocaleString("ja-JP",{maximumFractionDigits:1})}
function hqNormalItems(all=false){return qrSelect("hq_normal_items_v1410",`select=*${all?"":"&active=eq.true"}&order=sort_order.asc`)}
async function hqNormalItemsPage(msg=""){
 setScreen("hqNormalItemsPage",[msg]);if(!hqCanItems())return hqHome();
 let items=[];try{items=await hqNormalItems(true)}catch(e){return pageShell("品目の追加・変更","エラー",`${hqItemTabs("normal")}<div class="err">${esc(hqErr(e))}</div><div class="notice">017のSQLが未実行の可能性があります。</div>`)}
 pageShell("品目の追加・変更","通常在庫の品目（QRで管理しない品目）",`${okHtml(msg)}${hqItemTabs("normal")}${hqNormalAddForm("hqNormalItemsPage")}
 ${items.length?"":'<div class="notice">通常在庫の品目はまだありません。</div>'}${items.map(i=>`<div class="card"><div class="itemHead"><div><b>${esc(i.name)}</b><div class="small">1ケース ${hqKg(i.pack_weight_kg)}kg${i.active?"":" / 表示しない"}</div></div><div style="display:flex;gap:6px"><button class="btn btn2" ${seikaEventAttrs("click","hqEditNormalItem",[i.name,Number(i.pack_weight_kg),i.active])}>kgを直す</button><button class="btn ${i.active?"btn2":"green"}" ${seikaEventAttrs("click","hqSaveNormalItem",[i.name,Number(i.pack_weight_kg),!i.active,"hqNormalItemsPage"])}>${i.active?"表示しない":"表示する"}</button></div></div></div>`).join("")}`);
}
function hqNormalAddForm(back){if(!hqCanItems())return"";return `<div class="card"><b>通常在庫の品目を追加</b><label class="label" style="margin-top:8px">品目名</label><input id="hqNNm" class="input" placeholder="例：ブロッコリー"><label class="label" style="margin-top:8px">1ケースのkg</label><input id="hqNPack" class="input" inputmode="decimal" placeholder="例：8"><div class="small">QR品目と同じ名前は登録できません。</div><button class="btn hqBtnItems" style="width:100%;margin-top:10px" ${seikaEventAttrs("click","hqAddNormalItem",[back])}>追加する</button></div>`}
async function hqAddNormalItem(back){
 const name=document.getElementById("hqNNm")?.value.trim()||"",kg=Number(document.getElementById("hqNPack")?.value);
 if(!name)return alert("品目名を入れてください");if(!(kg>0))return alert("1ケースのkgを入れてください");
 if(back==="hqNormalPage")hqNormalKeepDraft();
 return hqSaveNormalItem(name,kg,true,back);
}
async function hqEditNormalItem(name,kg,active){const v=prompt(`${name} の1ケースのkg`,String(kg));if(v==null)return;const n=Number(v);if(!(n>0))return alert("0より大きい数を入れてください");return hqSaveNormalItem(name,n,active,"hqNormalItemsPage")}
async function hqSaveNormalItem(name,kg,active,back){
 try{await hqRpc("hq_save_normal_item_v1410",{p_name:name,p_pack_weight_kg:kg,p_active:active});const m=`${name}を保存しました`;return back==="hqNormalPage"?hqNormalPage(hqNormalDate,m):hqNormalItemsPage(m)}catch(e){alert(hqErr(e))}
}
let hqNormalDate="",hqNormalDraft=null;
function hqNormalKeepDraft(){const d={};document.querySelectorAll("[data-hqn]").forEach(r=>{const n=r.dataset.hqn;d[n]={c:r.querySelector(".hqNC")?.value??"",b:r.querySelector(".hqNB")?.value??""}});hqNormalDraft={date:hqNormalDate,rows:d}}
async function hqNormalPage(date="",msg=""){
 date=date||hqToday();if(date>hqToday())date=hqToday();hqNormalDate=date;setScreen("hqNormalPage",[date,msg]);
 const can=hqCanNormal()&&!hqViewOnly();
 pageShell("通常在庫入力","QRで管理しない品目の在庫（ケース＋バラkg）",`${okHtml(msg)}<div class="card"><label class="label">日付</label><input type="date" class="input" max="${hqToday()}" value="${esc(date)}" ${seikaEventAttrs("change","hqNormalPage",[{__seikaValue:true}])}></div><div id="hqNList"><div class="notice">読み込んでいます…</div></div>`);
 let items,cur,prev;
 try{[items,cur,prev]=await Promise.all([hqNormalItems(),qrSelect("hq_normal_counts_v1410",`select=*&count_date=eq.${date}`),qrSelect("hq_normal_counts_v1410",`select=item_name,count_date,total_kg&count_date=lt.${date}&order=count_date.desc&limit=1000`)])}
 catch(e){document.getElementById("hqNList").innerHTML=`<div class="err">${esc(hqErr(e))}</div><div class="notice">017のSQLが未実行の可能性があります。</div>`;return}
 const cm={};cur.forEach(c=>cm[c.item_name]=c);const pm={};prev.forEach(c=>{if(!pm[c.item_name])pm[c.item_name]=c});
 const dr=hqNormalDraft&&hqNormalDraft.date===date?hqNormalDraft.rows:{};hqNormalDraft=null;
 const val=(n,k,f)=>dr[n]?dr[n][k]:(cm[n]?String(Number(cm[n][f])||""):"");
 const rows=items.map(i=>{const p=pm[i.name];return `<div class="card" data-hqn="${esc(i.name)}" data-kg="${Number(i.pack_weight_kg)}" style="padding:12px 14px"><div class="itemHead"><div><b>${esc(i.name)}</b><div class="small">1ケース ${hqKg(i.pack_weight_kg)}kg${p?` / 前回 ${esc(p.count_date.slice(5).replace("-","/"))} ${hqKg(p.total_kg)}kg`:""}${cm[i.name]?` / この日の入力：${esc(cm[i.name].user_name||"")}`:""}</div></div><div style="text-align:right"><b class="hqNT" style="font-size:20px">—</b><div class="small">kg</div></div></div><div class="row" style="margin-top:8px"><div><label class="label">ケース</label><input class="input hqNC" inputmode="decimal" value="${esc(val(i.name,"c","cases"))}" ${can?"":"disabled"}></div><div><label class="label">バラkg</label><input class="input hqNB" inputmode="decimal" value="${esc(val(i.name,"b","bara_kg"))}" ${can?"":"disabled"}></div></div></div>`}).join("");
 document.getElementById("hqNList").innerHTML=`${items.length?`<div class="small" style="margin:4px 0 10px">ケースとバラ（kg）を入れると、合計kgが出ます。両方とも空にして保存すると、その日の入力を消します。</div>${rows}`:`<div class="notice">通常在庫の品目がありません。${hqCanItems()&&!hqViewOnly()?"下の「通常在庫の品目を追加」で追加してください。":"品目の追加は本社社員か管理者が行います（入荷登録・品目 → 品目の追加・変更 → 通常在庫の品目）。"}</div>`}
 ${can&&items.length?`<button class="btn hqBtnNormal" style="width:100%;margin-top:10px" ${seikaEventAttrs("click","hqSaveNormal",[])}>保存する</button>`:""}
 ${hqCanItems()&&!hqViewOnly()?hqNormalAddForm("hqNormalPage"):""}`;
 const calc=()=>document.querySelectorAll("[data-hqn]").forEach(r=>{const c=r.querySelector(".hqNC").value,b=r.querySelector(".hqNB").value,t=r.querySelector(".hqNT");if(c===""&&b===""){t.textContent="—";return}const v=(Number(c)||0)*Number(r.dataset.kg)+(Number(b)||0);t.textContent=hqKg(Math.round(v*10)/10)});
 calc();document.getElementById("hqNList").addEventListener("input",calc);
}
async function hqSaveNormal(){
 const rows=[];let bad="";
 document.querySelectorAll("[data-hqn]").forEach(r=>{const c=r.querySelector(".hqNC").value.trim(),b=r.querySelector(".hqNB").value.trim();if((c&&!(Number(c)>=0))||(b&&!(Number(b)>=0)))bad=r.dataset.hqn;rows.push({item_name:r.dataset.hqn,cases:c,bara_kg:b})});
 if(bad)return alert(`${bad} の数が正しくありません`);
 try{const r=await hqRpc("hq_save_normal_counts_v1410",{p_date:hqNormalDate,p_rows:rows});return hqNormalPage(hqNormalDate,`保存しました（${r?.saved??0}品目${r?.cleared?`・消去 ${r.cleared}品目`:""}）`)}catch(e){alert(hqErr(e))}
}
/* ---- 在庫表（QR品目＋通常在庫） ---- */
function hqAddDays(d,n){const x=new Date(d+"T00:00:00");x.setDate(x.getDate()+n);return ymdKey(x)}
async function hqTableData(from,to){const r=await hqRpc("get_hq_stock_table_v1410",{p_from:from,p_to:to});return Array.isArray(r)?r[0]:r}
async function hqTablePage(end="",span=7){
 end=end||hqToday();if(end>hqToday())end=hqToday();span=[7,14,31].includes(Number(span))?Number(span):7;setScreen("hqTablePage",[end,span]);
 const from=hqAddDays(end,1-span);
 pageShell("在庫表","本社のQR品目と通常在庫を合わせた在庫（kg）",`<div class="card"><div class="row"><div><label class="label">最後の日</label><input type="date" class="input" max="${hqToday()}" value="${esc(end)}" ${seikaEventAttrs("change","hqTablePage",[{__seikaValue:true},span])}></div><div><label class="label">日数</label><select class="input" ${seikaEventAttrs("change","hqTablePage",[end,{__seikaValue:true}])}>${[7,14,31].map(n=>`<option value="${n}" ${n===span?"selected":""}>${n}日</option>`).join("")}</select></div></div><div style="display:flex;gap:8px;margin-top:10px"><button class="btn btn2" style="flex:1" ${seikaEventAttrs("click","hqTablePage",[hqAddDays(end,-span),span])}>◀ 前</button><button class="btn btn2" style="flex:1" ${end>=hqToday()?"disabled":""} ${seikaEventAttrs("click","hqTablePage",[hqAddDays(end,span)>hqToday()?hqToday():hqAddDays(end,span),span])}>次 ▶</button></div></div><div id="hqTbl"><div class="notice">集計中…</div></div>`);
 let data;try{data=await hqTableData(from,end)}catch(e){document.getElementById("hqTbl").innerHTML=`<div class="err">${esc(hqErr(e))}</div><div class="notice">017のSQLが未実行の可能性があります。</div>`;return}
 const all=data?.rows||[];const dates=all[0]?.values?.map(v=>v.date)||[];
 const kindOf=r=>r._kind||(r.kind==="QR"?"QR":"原料");
 const zero=r=>r.values.every(v=>(v.kg==null||Number(v.kg)===0)&&!Number(v.unknown_qty||0));
 const rows=all.filter(r=>!zero(r)),hidden=all.length-rows.length;
 const tot=dates.map((_,i)=>rows.reduce((s,r)=>s+(r.values[i].kg==null?0:Number(r.values[i].kg)),0));
 const cell=(r,v)=>{if(r.kind==="通常"){return v.kg==null?'<span style="color:#94a3b8">—</span>':`<span class="stockVal">${hqKg(v.kg)}</span>`}const u=Number(v.unknown_qty||0);return `<span class="stockVal">${hqKg(v.kg)}</span>${u?`<div class="small" style="color:#b45309">＋${hqQty(u)}（kg不明）</div>`:""}`};
 const badge={QR:'<span class="badge normal">QR</span>',原料:'<span class="badge warn">原料</span>',仕掛品:'<span class="badge danger">仕掛品</span>'};
 const today=hqToday(),wd="日月火水木金土";
 const head=`<thead><tr><th>品目名</th>${dates.map(d=>`<th class="${d===today?"today":""}">${Number(d.slice(5,7))}/${Number(d.slice(8,10))}<br>${wd[new Date(d+"T00:00:00").getDay()]}</th>`).join("")}</tr></thead>`;
 const sec=["QR","原料","仕掛品"].map(k=>{const rs=rows.filter(r=>kindOf(r)===k);if(!rs.length)return "";return `<tr><td class="weekSection" colspan="${dates.length+1}"><span style="position:sticky;left:8px;font-weight:800">${k==="QR"?"QR品目":k}（${rs.length}品目）</span></td></tr>`+rs.map(r=>`<tr><td>${esc(r.item_name)}<br>${badge[k]}</td>${r.values.map(v=>`<td class="${v.date===today?"today":""}">${cell(r,v)}</td>`).join("")}</tr>`).join("")}).join("");
 const foot=`<tr><td><b>合計kg</b></td>${tot.map((t,i)=>`<td class="${dates[i]===today?"today":""}"><span class="stockVal">${hqKg(Math.round(t*10)/10)}</span></td>`).join("")}</tr>`;
 document.getElementById("hqTbl").innerHTML=rows.length?`<div class="card"><div class="weeklyWrap" style="margin-top:0"><table class="weeklyTable">${head}<tbody>${sec}${foot}</tbody></table></div>${hidden?`<div class="small" style="margin-top:8px">期間中ずっと在庫0の品目${hidden}件は表示していません。</div>`:""}</div><div class="small">QR品目：その日の終わりの在庫（取り消した出庫・受け入れは数えません）。通常在庫：その日に入力した数（入力がない日は「—」）。量目が分からないQRのロットは「kg不明」として別に出します。</div>`:`<div class="notice">${hidden?"期間中に在庫がある品目はありません。":"品目がありません。"}</div>`;
}

/* ---- 履歴・Excel ---- */
async function hqHistoryPage(month=""){
 month=month||monthInputValue(new Date);setScreen("hqHistoryPage",[month]);
 pageShell("入出庫履歴","本社の受け入れ確定・出庫・実数調整・取消",`<div class="card"><label class="label">月</label><input id="hqMonth" type="month" class="input" value="${esc(month)}" ${seikaEventAttrs("change","hqHistoryPage",[{__seikaValue:true}])}>${hqOnlyHq()?"":`<button class="btn hqBtnExcel" style="width:100%;margin-top:10px" ${seikaEventAttrs("click","hqExcel",[month])}>この月のExcelを作る</button>`}</div><div id="hqList"><div class="notice">読み込んでいます…</div></div>`);
 try{
  const rows=await hqMonthMoves(month);
  document.getElementById("hqList").innerHTML=rows.map(m=>`<div class="card" style="padding:10px 14px"><b>${esc(m.movement_type)}</b> ${esc(m.item_name||"")} ${hqQty(m.qty)}${esc(m.unit||"")}${m.destination?` → ${esc(m.destination)}`:""}${m.cancelled_at?' <span class="badge unset">取消済み</span>':""}<div class="small">${esc(m.lot_no||"")} / ${esc(m.user_name||"")} / ${esc(new Date(m.occurred_at).toLocaleString("ja-JP"))}${m.reason?` / ${esc(m.reason)}`:""}</div>${m.lot_no?`<button class="btn btn2" style="margin-top:6px;min-height:40px" ${seikaEventAttrs("click","hqLotPage",[m.lot_no])}>${hqCanCancelOut(m)?"このロットを開く（出庫の取り消し）":"このロットを開く"}</button>`:""}</div>`).join("")||'<div class="notice">この月の履歴はありません。</div>';
 }catch(e){document.getElementById("hqList").innerHTML=`<div class="err">${esc(hqErr(e))}</div>`}
}
async function hqMonthMoves(month){
 const[y,m]=month.split("-").map(Number);const from=new Date(y,m-1,1).toISOString(),to=new Date(y,m,1).toISOString();
 return qrSelect("hq_lot_movements_v1400",`select=*&occurred_at=gte.${encodeURIComponent(from)}&occurred_at=lt.${encodeURIComponent(to)}&order=occurred_at.asc&limit=5000`);
}
async function hqExcel(month){
 if(hqOnlyHq())return hqHome();
 if(typeof XLSX==="undefined")return alert("Excel機能を読み込めませんでした");
 try{
  const[moves,stock]=await Promise.all([hqMonthMoves(month),hqLots("select=*&status=eq.在庫あり&order=item_name.asc,hq_received_date.asc&limit=5000")]);
  const wb=XLSX.utils.book_new();
  const s1=[["品名","本社ロットNo.","元ロットNo.","入荷区分","数量","単位","量目","仕入先","産地","単協名","本社入荷日","石岡入荷日","品質評価"]].concat(stock.map(l=>[l.item_name,l.lot_no,l.source_lot_no||"",l.source_kind,Number(l.current_qty),l.unit,l.pack_weight||"",l.supplier||"",l.origin||"",l.cooperative_name||"",l.hq_received_date||"",l.ishioka_received_date||"",HQ_GRADE[l.grade]||""]));
  const s2=[["日時","区分","品名","本社ロットNo.","数量","単位","前","後","出庫先","理由","メモ","担当"]].concat(moves.map(m=>[new Date(m.occurred_at).toLocaleString("ja-JP"),m.movement_type+(m.cancelled_at?"（取消済み）":""),m.item_name||"",m.lot_no||"",Number(m.qty),m.unit||"",m.before_qty==null?"":Number(m.before_qty),m.after_qty==null?"":Number(m.after_qty),m.destination||"",m.reason||"",m.memo||"",m.user_name||""]));
  const a=XLSX.utils.aoa_to_sheet(s1),b=XLSX.utils.aoa_to_sheet(s2);a["!cols"]=s1[0].map(()=>({wch:14}));b["!cols"]=s2[0].map(()=>({wch:14}));
  XLSX.utils.book_append_sheet(wb,a,"本社在庫（現在）");XLSX.utils.book_append_sheet(wb,b,`入出庫履歴 ${month}`);
  try{
   const[y,mo]=month.split("-").map(Number);const from=`${month}-01`;let to=ymdKey(new Date(y,mo,0));if(to>hqToday())to=hqToday();
   if(from<=to){
    const[cnt,tbl]=await Promise.all([qrSelect("hq_normal_counts_v1410",`select=*&count_date=gte.${from}&count_date=lte.${to}&order=count_date.asc,item_name.asc&limit=5000`),hqTableData(from,to)]);
    const s3=[["日付","品名","ケース","バラkg","1ケースkg","合計kg","入力者"]].concat(cnt.map(c=>[c.count_date,c.item_name,Number(c.cases),Number(c.bara_kg),Number(c.pack_weight_kg),Number(c.total_kg),c.user_name||""]));
    const rs=tbl?.rows||[],ds=rs[0]?.values?.map(v=>v.date)||[];
    const s4=[["品名","区分"].concat(ds)].concat(rs.map(r=>[r.item_name,r.kind].concat(r.values.map(v=>v.kg==null?"":Number(v.kg))))).concat([["合計kg",""].concat(ds.map((_,i)=>rs.reduce((s,r)=>s+(r.values[i].kg==null?0:Number(r.values[i].kg)),0)))]);
    const c3=XLSX.utils.aoa_to_sheet(s3),c4=XLSX.utils.aoa_to_sheet(s4);c3["!cols"]=s3[0].map(()=>({wch:14}));c4["!cols"]=s4[0].map((_,i)=>({wch:i?11:16}));
    XLSX.utils.book_append_sheet(wb,c3,`通常在庫 ${month}`);XLSX.utils.book_append_sheet(wb,c4,`在庫表 ${month}`);
   }
  }catch(e){console.warn("通常在庫・在庫表のExcel",e)}
  XLSX.writeFile(wb,`本社在庫・入出庫_${month}.xlsx`);
 }catch(e){alert(hqErr(e))}
}

/* ---- 石岡：本社へ出庫したら貼り紙の印刷を案内 ---- */
function hqToast(lot){
 document.getElementById("hqToast")?.remove();
 document.body.insertAdjacentHTML("beforeend",`<div id="hqToast" style="position:fixed;left:12px;right:12px;bottom:16px;z-index:9999;background:#0f766e;color:#fff;border-radius:16px;padding:14px;box-shadow:0 8px 24px rgba(0,0,0,.25);display:flex;gap:10px;align-items:center"><div style="flex:1"><b>本社へ出庫しました</b><div style="font-size:14px">${esc(lot.item_name)} ${esc(hqPlanText(lot))}</div></div><button class="btn" style="background:#fff;color:#0f766e;min-height:44px" ${seikaEventAttrs("click","hqSheetFromToast",[lot.qr_key])}>本社移動用の貼り紙を印刷</button><button class="btn btn2" style="min-height:44px" ${seikaEventAttrs("click","hqCloseToast",[])}>閉じる</button></div>`);
}
function hqCloseToast(){document.getElementById("hqToast")?.remove()}
const hqCallRpcBase=callRpc;
callRpc=async function(name,args){
 const r=await hqCallRpcBase(name,args);
 try{
  if(/qr_lot.*operation/.test(name)&&String(args?.p_destination||"").trim()==="本社"&&args?.p_qr_key&&r&&r.ok!==false){
   setTimeout(async()=>{try{const lot=(await qrSelect("qr_lots",`select=id&qr_key=eq.${encodeURIComponent(args.p_qr_key)}&limit=1`))[0];if(!lot)return;const h=(await hqLots(`select=*&source_lot_id=eq.${lot.id}&status=eq.入荷待ち&order=created_at.desc&limit=1`))[0];if(h)hqToast(h)}catch(e){}},300);
  }
 }catch(e){}
 return r;
};
window.callRpc=callRpc;
async function hqIshiokaPendingPage(){
 setScreen("hqIshiokaPendingPage",[]);
 pageShell("本社へ移動中","本社でまだ確定していない原料（本社移動用の貼り紙の印刷もここから）",`${typeof canAdmin==="function"&&canAdmin()?`<button class="btn btn2" style="width:100%;margin-bottom:12px" ${seikaEventAttrs("click","c50ShipRunsPage",[])}>本社への便の設定（便の名前・到着時間）</button>`:""}<div id="hqList"><div class="notice">読み込んでいます…</div></div>`);
 try{const rows=await hqLots("select=*&status=eq.入荷待ち&source_kind=eq.石岡から&order=created_at.desc&limit=300");await hqLoadLimits();
  const unp=hqCanPrint()?rows.filter(l=>!hqPrinted(l)).length:0;
  document.getElementById("hqList").innerHTML=(unp?`<div class="card" style="background:#fee2e2;border:2px solid #dc2626;color:#991b1b;font-weight:900">貼り紙が未印刷の原料：${unp}件</div>`:"")+hqGroupedHtml(rows,l=>hqLotCard(l,false)+(hqCanPrint()?hqPrintBtn(l):""))||'<div class="notice">本社へ移動中の原料はありません。</div>';
 }catch(e){document.getElementById("hqList").innerHTML=`<div class="err">${esc(hqErr(e))}</div>`}
}

/* ---- QRの読み取り先の振り分け ---- */
const hqScanBase=qrScannedLotActionPage;
qrScannedLotActionPage=function(q,...rest){const k=hqKeyOf(q);if(/^HQ-/.test(k))return hqLotPage(k);return hqScanBase.call(this,q,...rest)};
window.qrScannedLotActionPage=qrScannedLotActionPage;
const hqOpLotBase=qrOperationLotPage;
qrOperationLotPage=function(kind,q,...rest){const k=hqKeyOf(q);if(/^HQ-/.test(k))return hqLotPage(k);return hqOpLotBase.call(this,kind,q,...rest)};
window.qrOperationLotPage=qrOperationLotPage;

/* ---- 荷受け担当者・下処理班は本社の画面だけ ---- */
const HQ_ONLY_ALLOWED=["login","accountMenu","changePasswordPage","displaySettingsPage","v195RoleGuidePage","settings"];
const hqSetScreenBase=setScreen;
setScreen=function(name,args){
 const r=hqSetScreenBase.apply(this,arguments);
 try{if(db?.user&&hqOnlyHq()&&!String(name||"").startsWith("hq")&&!HQ_ONLY_ALLOWED.includes(name))setTimeout(()=>{if(currentScreen===name)hqHome("この画面は本社のアカウントでは使えません。")},0)}catch(e){}
 return r;
};
window.setScreen=setScreen;

/* ---- ホームの切り替え ---- */
function hqEnsureIshiokaTop(){
 try{
  if(currentScreen!=="home"||!db?.user||hqSite()==="honsha"||hqIsHqRole()||document.getElementById("hqIshiokaFoot"))return;
  const main=document.querySelector("#app main")||document.querySelector("#app .appShell");if(!main)return;
  main.insertAdjacentHTML("afterbegin",`<div id="hqIshiokaFoot">${hqSwitchHtml()}<button class="btn btn2" style="width:100%;margin-bottom:12px" ${seikaEventAttrs("click","hqIshiokaPendingPage",[])}>本社へ移動中の原料・本社移動用の紙</button></div>`);
 }catch(e){}
}
(()=>{const app=document.getElementById("app");if(!app||window.hqTopObserver)return;window.hqTopObserver=new MutationObserver(()=>{if(currentScreen==="home"&&!document.getElementById("hqIshiokaFoot"))hqEnsureIshiokaTop()});window.hqTopObserver.observe(app,{childList:true,subtree:true})})();
const hqHomeBase=home;
home=function(...a){
 if(!db?.user)return hqHomeBase.apply(this,a);
 if(hqSite()==="honsha")return hqHome();
 if(hqIsHqRole())return hqIshiokaView();
 const r=hqHomeBase.apply(this,a);
 hqEnsureIshiokaTop();
 return r;
};
window.home=home;
const hqGoBackBase=goBack;
goBack=function(...a){
 if(currentScreen==="hqScanPage")return hqStopReader().finally(()=>home());
 if(currentScreen==="hqStockPage"||currentScreen==="hqOutPage"||currentScreen==="hqHistoryPage"||currentScreen==="hqTablePage"||currentScreen==="hqNormalPage")return hqStockHub();
 if(currentScreen==="hqDirectPage"||currentScreen==="hqItemsPage"||currentScreen==="hqNormalItemsPage")return hqEntryHub();
 if(currentScreen==="hqLotPage"||currentScreen==="hqPendingPage"||currentScreen==="hqStockHub"||currentScreen==="hqEntryHub"||currentScreen==="hqIshiokaPendingPage")return home();
 if(currentScreen==="hqSheetPage"){const k=hqSheetBackKey;hqSheetBackKey="";return k?hqLotPage(k):home()}
 if(hqIsHqRole()&&hqSite()==="ishioka"&&!String(currentScreen||"").startsWith("hq"))return home();
 return hqGoBackBase.apply(this,a);
};
window.goBack=goBack;

/* ---- ユーザー登録：本社の役割・初回パスワード変更 ---- */
const HQ_ALL_ROLES=[["admin","管理者"],["worker","青果社員"],["buyer","仕入れ担当者"],["sales","営業担当者"],["clerk","事務員"],["office_viewer","総務（閲覧）"],["viewer","閲覧者（閲覧のみ）"],["hq_worker","本社社員"],["hq_clerk","本社事務"],["hq_receiver","本社 荷受け担当者"],["hq_prep","本社 下処理班"]];
const hqUserFormBase=userFormHtml;
userFormHtml=function(u){
 let html=hqUserFormBase(u);
 const cur=u?.role||"worker";
 html=html.replace(/<select id="uRole"([^>]*)>[\s\S]*?<\/select>/,(m,attrs)=>`<select id="uRole"${attrs}>${HQ_ALL_ROLES.map(([v,n])=>`<option value="${v}" ${cur===v?"selected":""}>${n}</option>`).join("")}</select>`);
 const must=u?u.must_change_password!==false:true;
 html=html.replace('<label class="switch"><input id="uActive"',`<label class="switch"><input id="uMustChange" type="checkbox" ${must?"checked":""}> 初回ログイン時にパスワード変更を求める</label><div class="small">荷受け担当者・下処理班など、みんなで使うアカウントは外します。</div><br><label class="switch"><input id="uActive"`);
 return html;
};
window.userFormHtml=userFormHtml;window.v188UserFormHtml=userFormHtml;
const hqAdminReqBase=v188AdminRequest;
const hqSaveUserBase=saveUser;
saveUser=async function(id=""){
 if(!canAdmin())return;
 const role=document.getElementById("uRole")?.value,must=!!document.getElementById("uMustChange")?.checked,lid=document.getElementById("uId")?.value.trim().toLowerCase();
 const isHq=HQ_ROLES.includes(role);
 let sent=false;
 v188AdminRequest=async function(action,payload={}){
  if((action==="create"||action==="update")&&payload.user){sent=true;payload={...payload,user:{...payload.user,role:isHq?"viewer":payload.user.role,group_name:isHq&&(!payload.user.group_name||payload.user.group_name===ROLE[role])?HQ_LABEL[role]:payload.user.group_name}}}
  const ans=await hqAdminReqBase(action,payload);
  if(sent&&(action==="create"||action==="update")){
   sent=false;
   let pid=id||ans?.user?.id||ans?.id;
   if(!pid){const list=await hqAdminReqBase("list");pid=(list.users||[]).find(x=>x.legacy_user_id===lid)?.id}
   if(!pid)throw new Error("登録はできましたが、権限の設定に失敗しました。一覧から編集して保存し直してください。");
   await hqCallRpcBase("seika_set_user_role_v1400",{p_profile_id:pid,p_role:role,p_must_change:must});
  }
  return ans;
 };
 try{return await hqSaveUserBase(id)}finally{v188AdminRequest=hqAdminReqBase}
};
window.saveUser=saveUser;

const HQ_INITIAL=[["磯崎 貴広","isozaki","hq_worker",true],["朝日 琢磨","asahi","hq_worker",true],["片山 浩之","katayama","hq_worker",true],["佐藤 真帆","sato_maho","hq_worker",true],["三木 麻琴","miki","hq_worker",true],["横小路 友愛","yokokoji","hq_worker",true],["本社事務員","hq_jimu","hq_clerk",true],["荷受け担当者","hq_uketsuke","hq_receiver",false],["下処理班","hq_shitashori","hq_prep",false]];
function hqBulkPage(){
 setScreen("hqBulkPage",[]);if(!canAdmin())return home();
 pageShell("本社の初期アカウント","まとめて登録します（管理者のみ）",`<div class="card notice">すでに同じユーザーIDがある人は登録しません。パスワードはこの画面で入力するだけで、アプリには保存されません。</div><div class="card"><table class="weeklyTable" style="width:100%"><tr><th>名前</th><th>ユーザーID</th><th>権限</th><th>初回変更</th></tr>${HQ_INITIAL.map(([n,id,r,m],i)=>`<tr><td>${esc(n)}</td><td><input id="hqBId${i}" class="input" value="${esc(id)}" style="min-width:110px"></td><td>${esc(HQ_LABEL[r])}</td><td style="text-align:center"><input id="hqBMust${i}" type="checkbox" ${m?"checked":""}></td></tr>`).join("")}</table>
 <label class="label" style="margin-top:12px">初期パスワード（8文字以上）</label><input id="hqBPass" class="input" type="password" autocomplete="new-password">
 <button id="hqBBtn" class="btn green" style="width:100%;margin-top:12px" ${seikaEventAttrs("click","hqBulkRun",[])}>まとめて登録する</button><div id="hqBLog" class="small" style="margin-top:10px"></div></div>`);
}
async function hqBulkRun(){
 const pass=document.getElementById("hqBPass")?.value||"";if(pass.length<8)return alert("初期パスワードは8文字以上にしてください");
 if(!confirm("本社の初期アカウントを登録します。よろしいですか？"))return;
 const btn=document.getElementById("hqBBtn"),log=document.getElementById("hqBLog");btn.disabled=true;
 const line=t=>{log.insertAdjacentHTML("beforeend",`<div>${esc(t)}</div>`)};
 try{
  let users=(await hqAdminReqBase("list")).users||[];
  for(let i=0;i<HQ_INITIAL.length;i++){
   const[n,,r]=HQ_INITIAL[i],lid=(document.getElementById("hqBId"+i)?.value||"").trim().toLowerCase(),must=!!document.getElementById("hqBMust"+i)?.checked;
   if(!/^[a-z0-9_-]+$/.test(lid)){line(`× ${n}：ユーザーIDが正しくありません`);continue}
   let u=users.find(x=>x.legacy_user_id===lid);
   try{
    if(!u){const ans=await hqAdminReqBase("create",{user:{legacy_user_id:lid,display_name:n,role:"viewer",group_name:HQ_LABEL[r],active:true,password:pass}});users=(await hqAdminReqBase("list")).users||[];u=users.find(x=>x.legacy_user_id===lid)||ans?.user;line(`○ ${n}：登録しました`)}else line(`－ ${n}：すでに登録済み（権限だけ合わせます）`);
    if(!u?.id)throw new Error("登録した人が見つかりません");
    await hqCallRpcBase("seika_set_user_role_v1400",{p_profile_id:u.id,p_role:r,p_must_change:must});
   }catch(e){line(`× ${n}：${hqErr(e)}`)}
  }
  line("終わりました。");try{v188SaveLoginUsers(users)}catch(e){}
 }catch(e){line("× "+hqErr(e))}
 btn.disabled=false;
}
const hqUserAdminBase=userAdminPage;
userAdminPage=async function(...a){const r=await hqUserAdminBase.apply(this,a);try{const b=document.querySelector('[data-seika-click-action="newUserPage"]');if(b&&!document.getElementById("hqBulkBtn"))b.insertAdjacentHTML("afterend",`<button id="hqBulkBtn" class="btn btn2" style="width:100%;margin-top:8px" ${seikaEventAttrs("click","hqBulkPage",[])}>本社の初期アカウントをまとめて登録</button>`)}catch(e){}return r};
window.userAdminPage=userAdminPage;

/* ---- 操作ガイド ---- */
const HQ_GUIDE={
 switch:{title:"石岡と本社の画面を切り替える",where:"ホーム → いちばん上",steps:["ホームの「本社の画面へ」「石岡の画面へ」を押します。","本社社員・本社事務で石岡の画面を開いたときは、在庫を見るだけです。","石岡のアカウントで本社の画面を開いたときも、見るだけです（管理者を除く）。"],check:"ホームの上に「いまの画面」が出ます。",caution:"荷受け担当者・下処理班のアカウントは本社の画面だけで、切り替えはありません。切り替えはこの端末とこのアカウントだけに残ります。"},
 hqReceive:{title:"本社で受け入れる（品質評価と確定）",where:"本社ホーム → 入荷待ち原料 または QR読み取り（受け入れ・出庫）",steps:["届いた原料の「本社移動用」の貼り紙のQRを読み取ります。読めないときはロット番号を入力します。","入荷待ち原料は、出庫日と当日発注分／翌日発注分ごとにまとまって出ます。カードの黄色い帯で、便（例：原料便（12時着）・翌日便）と出庫した人を確認できます。","届いた数量を確認します。予定と違うときは実際の数量に直します。","品質評価（良好・要確認・不良）を選びます。要確認・不良は気になった点を選び、写真を1枚以上付けます。","「確定して本社の在庫にする」を押します。"],check:"確定すると「本社在庫」に入ります。確定するまでは本社の在庫に入りません。数量が予定と違うと「差異あり」と表示されます。本社入荷日は、受け入れが遅れて後日まとめて確定しても、石岡で出庫したときに決めた本社入荷日（本社直接入荷は登録したときに入れた入荷日）のままです（在庫表もその日に入ったものとして数えます）。",caution:"要確認・不良は社員に伝えてください。石岡から出庫を取り消した原料は、入荷待ちから自動で消えます。確定を間違えたときは、本社社員がロットの画面の「受け入れ確定を取り消す」で入荷待ちに戻せます（出庫がある場合は先に出庫を取り消します）。"},
 hqOut:{title:"使うときに出庫する",where:"本社ホーム → 在庫管理 → 使用出庫（QR読み取りからも出庫できます）",steps:["QRを読み取るか、一覧から原料を選びます（古い順に並んでいます）。","出庫先（下処理・原料出し）を選びます。","出庫する数量を入れます（小数も入れられます）。全部使うときは「全部」を押します。","「出庫する」を押すと、本社の在庫から数量が引かれます。"],check:"ロットの画面の「このロットの履歴」に出庫が残ります。間違えた出庫は、その出庫の「この出庫を取り消す」で取り消せます（本社社員・管理者。下処理班は自分がその日に出した分だけ）。使い切ったロットは「本社在庫」の「在庫なし」か「入出庫履歴」の「このロットを開く」から開きます。",caution:"網コンテナ・鉄コンテナ・パレテーナはkg、それ以外はケースで数えます。出庫を間違えたときは、履歴の「この出庫を取り消す」を押すと在庫が元に戻ります。出庫した本人はその日のうち、本社社員はいつでも取り消せます。"},
 hqDirect:{title:"本社に直接届いた原料を登録する",where:"本社ホーム → 入荷登録・品目 → 本社直接入荷",steps:["品目・荷姿・数量・量目・仕入先・産地・入荷日を入れます（必須）。網コンテナ・鉄コンテナ・パレテーナは量目を入れなくても登録できます。単協名と規格は、必要なときだけ入れます（規格は20文字まで。貼り紙の品名の右に印刷され、長い場合は文字の大きさを自動で調整します）。荷姿は、ダンボール・コンテナ・網コンテナ・鉄コンテナ・パレテーナ・紙袋・その他から選びます。","「登録して品質評価へ進む」を押します。","品質評価をして「確定して本社の在庫にする」を押します。確定した日が後日になっても、本社入荷日は登録したときに入れた入荷日のままです。","続けて出る画面で、パレットのケース数（大型容器は基数）と印刷枚数を入れて、貼り紙を印刷します。"],check:"確定すると本社在庫に入ります。",caution:"品目がないときは、本社社員が「入荷登録・品目」→「品目の追加・変更」で追加します。"},
 hqStock:{title:"本社の在庫と履歴を見る・Excelを作る",where:"本社ホーム → 在庫管理 → 本社在庫／入出庫履歴",steps:["「本社在庫」で品目ごとの合計とロットを見ます。上の「在庫あり／在庫なし／すべて」で切り替えると、使い切ったロット（最近30日に動きがあったもの）も探せます。","「入出庫履歴」で月を選ぶと、受け入れ確定・出庫・実数調整が並びます。各行の「このロットを開く」で、そのロットの画面へ進めます。","「この月のExcelを作る」で、現在の本社在庫・月の入出庫履歴・通常在庫・在庫表をExcelにします。"],check:"数量が合わないときは、本社社員がロットの画面の「実数調整」で直します。",caution:"実数調整には理由が必要です。"},
 hqItems:{title:"本社の品目を追加する",where:"本社ホーム → 入荷登録・品目 → 品目の追加・変更",steps:["上のタブで「QR品目」か「通常在庫の品目」を選びます。","QR品目：品目名・ふだんの単位・量目を入れて「追加する」を押します。","通常在庫の品目：品目名と1ケースのkgを入れて「追加する」を押します。通常在庫入力の画面の下の「通常在庫の品目を追加」からも追加できます。","使わなくなった品目は「表示しない」にします。"],check:"QR品目は本社直接入荷に、通常在庫の品目は通常在庫入力に出てきます。同じ名前をQR品目と通常在庫の品目の両方には登録できません。",caution:"加工用玉葱・皮むき人参(国産)・皮むき人参(中国)・皮むきじゃが芋は最初から入っています（保管目安は入荷日＋3日）。"},
 hqNormal:{title:"通常在庫を入力する（QRで管理しない品目）",where:"本社ホーム → 在庫管理 → 通常在庫入力",steps:["日付を確かめます（ふだんは今日）。","品目ごとにケース数とバラ（kg）を入れます。合計kgが自動で出ます。","「保存する」を押します。同じ日にもう一度保存すると上書きします。","品目がないときは、画面の下の「通常在庫の品目を追加」で追加します（本社社員・管理者）。"],check:"在庫表に、その日の数が出ます。",caution:"ケースもバラも空にして保存すると、その日の入力を消します。入力できるのは本社社員と荷受け担当者です。"},
 hqTable:{title:"在庫表を見る（QR品目＋通常在庫）",where:"本社ホーム → 在庫管理 → 在庫表",steps:["最後の日と日数（7・14・31日）を選びます。「◀ 前」「次 ▶」で期間を動かせます。","石岡の在庫表と同じ形で、「QR品目」「原料」「仕掛品」の見出しごとに品目が並び、日ごとのkgといちばん下に合計kgが出ます。今日の列には色が付きます。","品目名の列は左に固定されているので、横に動かしても品目名が見えます。期間中ずっと在庫0の品目は表示せず、表の下に件数だけ出ます。"],check:"QR品目はその日の終わりの在庫、通常在庫はその日に入力した数です（入力がない日は「—」）。",caution:"量目が分からないQRのロットは「kg不明」として別に出ます。月ごとのExcelにも「通常在庫」「在庫表」のシートが入ります。"},
 hqPrint:{title:"本社移動用の貼り紙を印刷する（石岡）",where:"QR出庫で出庫先「本社」 → 登録後に自動で印刷画面へ（あとで印刷するときはホーム「本社へ移動中の原料・本社移動用の紙」）",steps:["いつもどおりQR出庫で、出庫先に「本社」を選んで出庫します。","登録すると、本社移動用の貼り紙の印刷画面へ自動で切り替わります。すぐ印刷しないときは、そのまま別の画面へ進めます。","ケースのものは「1パレットのケース数」を入れます。パレット枚数とパレットごとのケース数が自動で出ます（直せます）。","ダンボールなど、ロットの量目と違う入数で送るとき（例：10kgのキャベツを12kgで送る）は、QR出庫で出庫先「本社」を選ぶと出る「入数」欄に入れます。出庫したあとは、この貼り紙の画面の「入数（量目と違うとき）」に入れて「入数を保存」を押します（管理者・青果社員）。貼り紙の量目と本社の納品書の入数が変わります。石岡・本社の在庫（ケース数）は出庫した数のままで、入数では変わりません。","網コンテナ・鉄コンテナ・パレテーナは、送る分の実測合計kgと基数を入れます。1基あたりkgは自動で出ます。1基に1枚ずつ貼り、紙には1基あたりkgと実測合計・基数の両方が出ます。印刷すると本社の入荷待ちの数量が実測に変わります（石岡の在庫は出庫した数のまま）。","1パレット（1基）あたりの印刷枚数を入れて「印刷する」を押します。A4横のPDFができます。","画面の上に出る「PDFを開く・印刷」を押し、共有からEpson iPrintなどを選んで印刷します（いつものQR貼り紙と同じ）。","印刷し直すときは、ホームのいちばん上「本社へ移動中の原料・本社移動用の紙」から印刷します。まだ印刷していない原料には赤い「未印刷」が付き、画面の上に未印刷の件数が出ます。"],check:"出庫した時点で、本社の「入荷待ち原料」に「移動中」として出ます。本社でこの紙のQRを読むと、その原料が開きます。",caution:"パレットごとのケース数の合計が出庫数と合わないと印刷できません。大型容器は実測合計kgを基数で割った重さが1基あたりkgになります。本社への便の名前・到着時間は、管理者が「本社へ移動中の原料・本社移動用の紙」の画面の「本社への便の設定」から変えられます。出庫を取り消すと、本社の移動中も取消になります。"},
 hqUsers:{title:"本社のアカウントを登録する（管理者）",where:"メニュー → ユーザー登録・管理",steps:["「本社の初期アカウントをまとめて登録」を押します。","ユーザーIDを確認し、初期パスワードを入れて「まとめて登録する」を押します。","1人ずつ登録・変更するときは、権限で本社社員・本社事務・本社 荷受け担当者・本社 下処理班を選びます。","みんなで使うアカウントは「初回ログイン時にパスワード変更を求める」を外します。"],check:"一覧に本社の権限で表示されます。",caution:"パスワードはアプリに保存されません。本人へ直接伝えてください。"}
};
const HQ_ROLE_GUIDE={
 hq_worker:{name:"本社社員",intro:"本社の受け入れ・確定、使用出庫、実数調整、品目の追加・変更ができます。",keys:["switch","hqReceive","hqOut","hqDirect","hqStock","hqTable","hqNormal","hqItems"]},
 hq_clerk:{name:"本社事務",intro:"本社の在庫と入出庫履歴を見て、Excelを作れます。",keys:["switch","hqStock","hqTable"]},
 hq_receiver:{name:"本社 荷受け担当者",intro:"届いた原料の品質評価と確定、貼り紙の印刷、在庫の確認ができます。本社の画面だけを使います。",keys:["hqReceive","hqDirect","hqStock","hqTable","hqNormal"]},
 hq_prep:{name:"本社 下処理班",intro:"本社の在庫を見て、使うときに出庫できます。本社の画面だけを使います。",keys:["hqOut","hqStock","hqTable"]}
};
try{
 for(const[r,g]of Object.entries(HQ_ROLE_GUIDE))V195_ROLE_GUIDES[r]={name:g.name,intro:g.intro,sections:g.keys.map(k=>HQ_GUIDE[k])};
 const add={admin:["switch","hqPrint","hqReceive","hqOut","hqDirect","hqStock","hqTable","hqNormal","hqItems","hqUsers"],worker:["switch","hqPrint"]};
 for(const[r,keys]of Object.entries(add)){const g=V195_ROLE_GUIDES[r];if(g&&Array.isArray(g.sections))for(const k of keys)if(!g.sections.some(s=>s.title===HQ_GUIDE[k].title))g.sections.push(HQ_GUIDE[k])}
 for(const r of["buyer","sales","clerk","viewer","office_viewer"]){const g=V195_ROLE_GUIDES[r];if(g&&Array.isArray(g.sections)&&!g.sections.some(s=>s.title===HQ_GUIDE.switch.title))g.sections.push(HQ_GUIDE.switch)}
}catch(e){}

/* ---- 貼り紙の印刷（パレットごと・1基ごと） ---- */
let hqSheetBackKey="",hqSheetLot=null;
function hqNum(v){return Number(String(v??"").replace(/[０-９．]/g,c=>String.fromCharCode(c.charCodeAt(0)-0xfee0)))}
function hqSheetTotal(l){return Number(l.status==="入荷待ち"?l.planned_qty:l.received_qty)||0}
async function hqSheetFromToast(key){hqCloseToast();hqSheetBackKey="";return hqSheetPage(key)}
async function hqSheetPage(key,msg=""){
 key=String(key||"");if(currentScreen==="hqLotPage")hqSheetBackKey=key;
 setScreen("hqSheetPage",[key,msg]);if(!hqCanPrint())return home();
 pageShell("貼り紙の印刷","",`<div class="notice">読み込んでいます…</div>`);
 let l;try{await hqLoadLimits();l=(await hqLots(`select=*&qr_key=eq.${encodeURIComponent(key)}&limit=1`))[0]}catch(e){return pageShell("貼り紙の印刷","エラー",`<div class="err">${esc(hqErr(e))}</div>`)}
 if(!l)return pageShell("貼り紙の印刷","見つかりません",`<div class="err">この原料は見つかりません。</div>`);
 await hqSlipPackAttach([l],true);hqSheetLot=l;const m=l.sheet_meta||{},total=hqSheetTotal(l),fromIshioka=l.source_kind==="石岡から",viaIshioka=!!l.via_ishioka;
 const copies=Number(m.copies)>0?Number(m.copies):1;
 let form;
 if(l.unit==="kg"){
  const count=Number(m.count)>0?Number(m.count):(Number(l.planned_count)>0?Number(l.planned_count):"");
  const per=Number(m.per)>0?Number(m.per):(Number(l.unit_weight_kg)>0?Number(l.unit_weight_kg):(count?Math.round(total/count*10)/10:""));
  const measuring=(fromIshioka||viaIshioka)&&l.status==="入荷待ち";
  if(measuring){const mt=Number(l.measured_total_kg)>0?Number(l.measured_total_kg):"";
  form=`<div class="small">大型容器（${esc(l.container_type||"網コンテナなど")}）は1基に1枚ずつ貼ります。送る分の実測合計kgと基数を入れると、1基あたりkgが自動で出ます。</div>
  <div class="row" style="margin-top:8px"><div><label class="label">実測合計kg（必須）</label><input id="hqSTotal" class="input" inputmode="decimal" value="${esc(mt)}" placeholder="例：820" ${seikaEventAttrs("input","hqSheetCheck",[])}></div><div><label class="label">基数（必須）</label><input id="hqSCount" class="input" inputmode="numeric" value="${esc(count)}" ${seikaEventAttrs("input","hqSheetCheck",[])}></div></div>
  <label class="label" style="margin-top:8px">1基あたりkg（自動）</label><input id="hqSPer" class="input" readonly value="">
  <div class="small" style="margin-top:4px">${viaIshioka?"印刷すると、本社の入荷待ちの数量・基数・1基あたりkgが実測に変わります。石岡の在庫には入りません。":"印刷すると、本社の入荷待ちの数量・基数・1基あたりkgが実測に変わります。石岡の在庫は出庫した数のままです。"}</div>`;
  }else
  form=`<div class="small">大型容器（${esc(l.container_type||"網コンテナなど")}）は1基に1枚ずつ貼ります。</div>
  <div class="row" style="margin-top:8px"><div><label class="label">基数</label><input id="hqSCount" class="input" inputmode="numeric" value="${esc(count)}" ${seikaEventAttrs("input","hqSheetCheck",[])}></div><div><label class="label">1基あたりkg</label><input id="hqSPer" class="input" inputmode="decimal" value="${esc(per)}" ${seikaEventAttrs("input","hqSheetCheck",[])}></div></div>
  <div class="small" style="margin-top:4px">${fromIshioka?"1基あたりkgは、石岡の入荷時の総重量を入荷基数で割った重さです。":"合計kgを基数で割った重さが入ります。"}</div>`;
 }else{
  const qtys=Array.isArray(m.palletQtys)&&m.palletQtys.length?m.palletQtys:[];
  form=`<div class="row" style="margin-top:8px"><div><label class="label">パレット枚数（自動）</label><input id="hqSPalCount" class="input" readonly value="${qtys.length||""}"></div><div><label class="label">1パレットのケース数</label><input id="hqSEach" class="input" inputmode="decimal" value="${esc(m.each||"")}" placeholder="例：30" ${seikaEventAttrs("input","hqSheetRows",[])}></div></div>
  <div id="hqSRows" style="margin-top:8px">${qtys.map((q,i)=>hqSheetRowHtml(i+1,q)).join("")}</div>`;
 }
 const packShow=fromIshioka&&l.unit!=="kg",packEdit=packShow&&has(["admin","worker"])&&!!l.source_movement_id;
 const packBox=packShow?`<div class="notice" style="margin-top:8px"><b>入数（量目と違うとき）</b><div class="small">今の入数：${esc(hqPackOf(l)||"-")}${l.slip_pack?`（ロットの量目 ${esc(l.pack_weight||"-")} から変更）`:""}。貼り紙の量目と伝票の入数に入ります。石岡・本社の在庫（ケース数）は変わりません。</div>${l.slip_pack_error?'<div class="err" style="margin-top:6px">入数の変更を読み込めませんでした。通信を確認して、この画面を開き直してください（このままでは印刷できません）。</div>':""}${packEdit?`<div class="row" style="margin-top:6px"><input id="hqSPackIn" class="input" placeholder="例：12kg" value="${esc(l.slip_pack||"")}"><button type="button" class="btn btn2" ${seikaEventAttrs("click","hqPackSave",[l.qr_key])}>入数を保存</button></div><div class="small">空欄で保存すると、出庫時に入れた入数（なければロットの量目）に戻ります。</div>`:""}</div>`:"";
 const body=`${okHtml(msg)}${hqLotCard(l,false)}<div class="card"><b style="font-size:18px">${fromIshioka||viaIshioka?"本社移動用の貼り紙":"本社入荷の貼り紙"}</b><div class="small" style="margin-top:4px">${viaIshioka&&l.unit==="kg"&&!(total>0)?"合計：実測合計kgを入れると決まります":`合計：${hqQty(total)}${esc(l.unit)}`}</div>${packBox}${form}
 <label class="label" style="margin-top:10px">1${l.unit==="kg"?"基":"パレット"}あたりの印刷枚数</label><input id="hqSCopies" class="input" inputmode="numeric" value="${copies}" ${seikaEventAttrs("input","hqSheetCheck",[])}>
 ${l.status==="入荷待ち"&&(fromIshioka||viaIshioka)?`<label class="label" style="margin-top:10px">本社入荷日（予定）</label><input id="hqPlanned" type="date" class="input" value="${esc(l.planned_date||hqToday())}">`:""}
 <div id="hqSWarn" class="small" style="margin-top:10px"></div>
 <button id="hqSBtn" class="btn hqBtnPrint" style="width:100%;margin-top:12px" ${seikaEventAttrs("click","hqSheetPrint",[l.qr_key])}>印刷する</button></div>`;
 pageShell("貼り紙の印刷",`${esc(l.item_name)}`,body);hqSheetCheck();
}
function hqSheetRowHtml(i,q){return `<div class="row" style="align-items:center;margin-top:6px"><label class="label" style="margin:0;flex:.8">パレット${i}</label><input class="input hqSPal" inputmode="decimal" value="${esc(q)}" ${seikaEventAttrs("input","hqSheetCheck",[])}><span class="small">ケース</span></div>`}
function hqSheetRows(){
 const l=hqSheetLot;if(!l)return;const total=hqSheetTotal(l),each=hqNum(document.getElementById("hqSEach")?.value),box=document.getElementById("hqSRows");
 if(!box)return;if(!(total>0&&each>0)){box.innerHTML="";hqSheetCheck();return}
 const n=Math.ceil(total/each-1e-9);let rest=total,html="";
 for(let i=1;i<=n;i++){const v=i<n?each:Math.round(rest*100)/100;rest-=v;html+=hqSheetRowHtml(i,v)}
 box.innerHTML=html;hqSheetCheck();
}
function hqSheetPlan(){
 const l=hqSheetLot;if(!l)return{ok:false,msg:""};const total=hqSheetTotal(l),copies=Math.floor(hqNum(document.getElementById("hqSCopies")?.value));
 if(!(copies>=1&&copies<=10))return{ok:false,msg:"印刷枚数は1〜10で入れてください"};
 if(l.unit==="kg"){
  const totalEl=document.getElementById("hqSTotal"),count=hqNum(document.getElementById("hqSCount")?.value);
  let per=hqNum(document.getElementById("hqSPer")?.value);
  if(totalEl){
   const mt=hqNum(totalEl.value),perEl=document.getElementById("hqSPer");
   per=mt>0&&Number.isInteger(count)&&count>=1?Math.round(mt/count*10)/10:NaN;if(perEl)perEl.value=per>0?String(per):"";
   if(!(mt>0))return{ok:false,msg:"実測合計kgを入れてください"};
   if(!(Number.isInteger(count)&&count>=1&&count<=200))return{ok:false,msg:"基数を入れてください"};
   const pages=[];for(let i=1;i<=count;i++)for(let c=0;c<copies;c++)pages.push({label:`${i} / ${count} 基目`,qty:`1基 ${hqQty(per)} kg`,note:`実測合計 ${hqQty(mt)} kg（${count}基）`});
   const d=Number(l.measured_total_kg)>0||l.via_ishioka?0:Math.round((mt-total)*10)/10;
   return{ok:true,pages,measured:{total:mt,count},meta:{mode:"container",count,per,copies,measured_total:mt},msg:`${count}基 × ${copies}枚 ＝ ${pages.length}枚 を印刷します。1基あたり ${hqQty(per)}kg。`+(Math.abs(d)>=0.1?`<br><span style="color:#b45309;font-weight:800">石岡の出庫時の重さ（${hqQty(total)}kg）との差：${d>0?"+":""}${hqQty(d)}kg（本社は実測に合わせます）</span>`:"")};
  }
  if(!(Number.isInteger(count)&&count>=1&&count<=200))return{ok:false,msg:"基数を入れてください"};
  if(!(per>0))return{ok:false,msg:"1基あたりkgを入れてください"};
  const pages=[];for(let i=1;i<=count;i++)for(let c=0;c<copies;c++)pages.push({label:`${i} / ${count} 基目`,qty:`1基 ${hqQty(per)} kg`});
  const diff=Math.abs(count*per-total)>Math.max(1,total*0.02);
  return{ok:true,pages,meta:{mode:"container",count,per,copies},msg:`${count}基 × ${copies}枚 ＝ ${pages.length}枚 を印刷します。`+(diff?`<br><span style="color:#b45309;font-weight:800">基数×1基あたりkg（${hqQty(count*per)}kg）が合計（${hqQty(total)}kg）と違います。確認してください。</span>`:"")};
 }
 const qtys=[...document.querySelectorAll(".hqSPal")].map(x=>hqNum(x.value)).filter(x=>x>0),pc=document.getElementById("hqSPalCount");if(pc)pc.value=qtys.length||"";
 if(!qtys.length)return{ok:false,msg:"1パレットのケース数を入れてください"};
 const sum=qtys.reduce((a,b)=>a+b,0);
 if(Math.abs(sum-total)>1e-6)return{ok:false,msg:`<span style="color:#b91c1c;font-weight:800">パレットごとの合計（${hqQty(sum)}）が合計（${hqQty(total)}ケース）と合いません。合うまで印刷できません。</span>`};
 const pages=[];qtys.forEach((q,i)=>{for(let c=0;c<copies;c++)pages.push({label:`パレット ${i+1} / ${qtys.length}`,qty:`${hqQty(q)} ケース`})});
 return{ok:true,pages,meta:{mode:"pallet",each:hqNum(document.getElementById("hqSEach")?.value)||null,palletQtys:qtys,copies},msg:`<span style="color:#166534;font-weight:800">合計一致</span>　${qtys.length}パレット × ${copies}枚 ＝ ${pages.length}枚 を印刷します。`};
}
function hqSheetCheck(){const r=hqSheetPlan(),w=document.getElementById("hqSWarn"),b=document.getElementById("hqSBtn");if(w)w.innerHTML=r.msg||"";if(b)b.disabled=!r.ok}
async function hqPackSave(key){
 const l=hqSheetLot;if(!l||String(l.qr_key)!==String(key)||!l.source_movement_id)return;
 if(!has(["admin","worker"]))return alert("入数を直せるのは、石岡の管理者・青果社員です。");
 const r=hqPackNorm(document.getElementById("hqSPackIn")?.value);if(!r.ok)return alert(r.msg);
 try{await hqRpc("qr_slip_adjust_save_v1199c86",{p_movement_id:l.source_movement_id,p_total_kg:null,p_pack:r.pack||null});return hqSheetPage(key,r.pack?`入数を ${r.pack} にしました。`:"入数の変更を取り消しました。")}
 catch(e){const m=String(e?.message||e||"");alert(/qr_slip_adjust_save_v1199c86|schema cache|does not exist|404/.test(m)?"入数を保存する仕組み（SQL 036）がまだ入っていません。管理者にSQLの実行を頼んでください。":hqErr(e))}
}
Object.assign(window,{hqPackSave});
async function hqSheetPrint(key){
 const l=hqSheetLot,plan=hqSheetPlan();if(l&&l.slip_pack_error)return alert("入数の変更を読み込めていないため、印刷できません。通信を確認して、貼り紙の画面を開き直してください。");if(!l||!plan.ok)return alert(String(plan.msg||"入力を確認してください").replace(/<[^>]+>/g,""));
 try{
  let lot={...l};const d=document.getElementById("hqPlanned")?.value||"";
  if(d&&d!==l.planned_date&&l.status==="入荷待ち"){await hqRpc("hq_set_planned_date_v1400",{p_lot_id:l.id,p_date:d});lot.planned_date=d}
  if(plan.measured){const ans=await hqRpc("hq_set_measured_v1420",{p_lot_id:l.id,p_total_kg:plan.measured.total,p_count:plan.measured.count});lot={...lot,planned_qty:Math.round(plan.measured.total*10)/10,planned_count:plan.measured.count,unit_weight_kg:ans?.per??lot.unit_weight_kg,measured_total_kg:plan.measured.total,measured_count:plan.measured.count}}
  await hqRpc("hq_save_sheet_v1400",{p_lot_id:l.id,p_meta:plan.meta});lot.sheet_meta=plan.meta;hqSheetLot=lot;
  await hqMakePdf(lot,plan.pages);
 }catch(e){alert(hqErr(e))}
}
async function hqCancelOut(movementId,key){
 const reason=prompt("この出庫を取り消します。理由を入れてください（例：数量の入れ間違い）");if(reason===null)return;
 if(hqBusy)return;hqBusy=true;
 try{await hqRpc("hq_cancel_out_v1400",{p_operation_id:newId(),p_movement_id:movementId,p_reason:reason});hqBusy=false;return hqLotPage(key,"出庫を取り消しました。在庫が元に戻りました。")}catch(e){alert(hqErr(e))}
 hqBusy=false;
}
async function hqCancelReceive(lotId,key){
 const reason=prompt("受け入れ確定を取り消して「入荷待ち」に戻します。理由を入れてください");if(reason===null)return;
 if(hqBusy)return;hqBusy=true;
 try{await hqRpc("hq_cancel_receive_v1400",{p_operation_id:newId(),p_lot_id:lotId,p_reason:reason});hqBusy=false;return hqLotPage(key,"受け入れ確定を取り消しました。品質評価と確定をやり直してください。")}catch(e){alert(hqErr(e))}
 hqBusy=false;
}

Object.assign(window,{hqMakePdf,hqNormalItemsPage,hqAddNormalItem,hqEditNormalItem,hqSaveNormalItem,hqNormalPage,hqSaveNormal,hqTablePage,hqStockHub,hqEntryHub,hqToast,hqSheetPage,hqSheetFromToast,hqGroupedHtmlG,hqSheetRows,hqSheetCheck,hqSheetPrint,hqCancelOut,hqCancelReceive,hqHome,hqIshiokaView,hqSetSite,hqPendingPage,hqStockPage,hqOutPage,hqLotPage,hqToggleGrade,hqAddPhotos,hqRemovePhoto,hqDoReceive,hqFillAll,hqDoOut,hqDoAdjust,hqCancelPending,hqShowPhotos,hqPrintLot,hqPrintFromPage,hqScanPage,hqOpenTyped,hqDirectPage,hqDirectItemChanged,hqDirectContChanged,hqDoDirect,hqItemsPage,hqSaveItem,hqHistoryPage,hqExcel,hqCloseToast,hqIshiokaPendingPage,hqBulkPage,hqBulkRun});
window.c83Hq={hqErr,hqLots,hqRpc,hqToday,hqLotCard,hqPrintBtn,HQ_CONTAINERS,HQ_BIG_CONTAINERS,hqSheetHtml,hqSpecMemo,hqFocus};
/* ===== v1.199-c58 本社 第2段階 =====
   下処理（入力・確認・確定）・スタッフQRと作業時間・在庫入力（原料／仕掛品）・廃棄一覧・仕入れ価格表・
   歩留まり・使用数量・品質評価一覧・棚卸し・Excel出力・石岡ホームの数量の差のお知らせ。
   データベースは db/019_本社_第2段階.sql（スタッフの初期登録は db/020）。 */
(function(){
"use strict";

/* ---------- 共通 ---------- */
const H2={s2:null,s2At:0,timer:null,reader:null,readerScreen:"",busy:false};
const r2=(name,args)=>hqRpc(name,args);
const sel2=(t,q)=>qrSelect(t,q);
const enc2=v=>encodeURIComponent(v);
const num2=v=>{if(v==null)return NaN;const s=String(v).replace(/[０-９．]/g,c=>String.fromCharCode(c.charCodeAt(0)-0xfee0)).replace(/[,，\s]/g,"");return s===""?NaN:Number(s)};
const kg2=v=>v==null||v===""||!Number.isFinite(Number(v))?"—":hqKg(Math.round(Number(v)*10)/10);
const yen2=v=>v==null||!Number.isFinite(Number(v))?"未計算":`${Math.round(Number(v)).toLocaleString("ja-JP")}円`;
const pct2=v=>v==null||!Number.isFinite(v)?"—":`${(Math.round(v*1000)/10).toFixed(1)}%`;
const time2=t=>t?new Date(t).toLocaleTimeString("ja-JP",{hour:"2-digit",minute:"2-digit",timeZone:"Asia/Tokyo"}):"";
const dt2=t=>t?new Date(t).toLocaleString("ja-JP",{month:"numeric",day:"numeric",hour:"2-digit",minute:"2-digit",timeZone:"Asia/Tokyo"}):"";
const md2=d=>d?String(d).slice(5).replace("-","/"):"";
const mins2=(a,b)=>{if(!a)return 0;const e=b?new Date(b):new Date();return Math.max(0,Math.round((e-new Date(a))/60000))};
const hm2=m=>{m=Math.round(m||0);return `${Math.floor(m/60)}時間${String(m%60).padStart(2,"0")}分`};
const btnAttr=(act,args=[])=>seikaEventAttrs("click",act,args);
const roleIs=list=>list.includes(db?.role||"");
const H2_ALL_VIEW=["admin","worker","buyer","sales","clerk","office_viewer","viewer","hq_worker","hq_clerk","hq_receiver"];
function h2CanPrep(){return roleIs(["admin","hq_worker","hq_prep"])}
function h2CanBoss(){return roleIs(["admin","hq_worker"])}
function h2CanRaw(){return roleIs(["admin","hq_worker","hq_receiver"])}
function h2CanMoney(){return roleIs(H2_ALL_VIEW)&&!roleIs(["hq_prep"])}
function h2CanCount(){return roleIs(["admin","hq_worker","hq_receiver"])}
function h2CanReport(){return roleIs(["admin","hq_worker","hq_clerk","sales","buyer"])}
function h2Month(m){return /^\d{4}-\d{2}$/.test(String(m||""))?m:monthInputValue(new Date)}
function h2MonthRange(m){const[y,mo]=h2Month(m).split("-").map(Number);const from=`${h2Month(m)}-01`;let to=ymdKey(new Date(y,mo,0));return{from,to,y,mo,toCap:to>hqToday()?hqToday():to}}
function h2MonthLabel(m){const[y,mo]=h2Month(m).split("-").map(Number);return `${y}年${mo}月`}
function h2Monday(d){const x=new Date(String(d).slice(0,10)+"T00:00:00");const w=(x.getDay()+6)%7;x.setDate(x.getDate()-w);return ymdKey(x)}
function h2FiscalStart(m){const[y,mo]=h2Month(m).split("-").map(Number);return mo>=9?y:y-1}
function h2Err(e){return hqErr(e)}
function h2Notice(t){return `<div class="card notice">${t}</div>`}
function h2Loading(){return '<div class="notice">読み込んでいます…</div>'}
function h2Set(id,html){const el=document.getElementById(id);if(el)el.innerHTML=html}
function h2Val(id){return document.getElementById(id)?.value??""}
async function h2Stage2(force=false){
 if(!force&&H2.s2!==null&&Date.now()-H2.s2At<60000)return H2.s2;
 try{const r=await sel2("hq_settings_v1500","select=key,value&key=eq.stage2_stock");H2.s2=!!(r[0]&&r[0].value===true)}catch(e){if(H2.s2===null)H2.s2=false}
 H2.s2At=Date.now();return H2.s2;
}
window.h2Stage2=h2Stage2;

/* ---------- 画面の切り替えで止めるもの（カメラ・自動更新） ---------- */
function h2StopAll(){if(H2.timer){clearInterval(H2.timer);H2.timer=null}h2StopReader()}
async function h2StopReader(){const r=H2.reader;H2.reader=null;H2.readerScreen="";if(r){try{await r.stop()}catch(e){}try{r.clear()}catch(e){}}}
const h2SetScreenBase=setScreen;
setScreen=function(name,args){
 if(H2.readerScreen&&H2.readerScreen!==name)h2StopReader();
 if(H2.timer&&H2.timerScreen!==name){clearInterval(H2.timer);H2.timer=null}
 return h2SetScreenBase.apply(this,arguments);
};
window.setScreen=setScreen;
function h2Every(ms,fn){if(H2.timer)clearInterval(H2.timer);H2.timerScreen=currentScreen;H2.timer=setInterval(()=>{if(currentScreen!==H2.timerScreen){clearInterval(H2.timer);H2.timer=null;return}fn()},ms)}
async function h2StartReader(elId,onCode){
 await h2StopReader();
 const el=document.getElementById(elId);if(!el)return;
 if(typeof Html5Qrcode!=="function"){el.innerHTML='<div class="err">カメラを使えません。下の一覧から選んでください。</div>';return}
 const screen=currentScreen;let last="",lastAt=0,busy=false;
 try{
  const r=new Html5Qrcode(elId);H2.reader=r;H2.readerScreen=screen;
  await r.start({facingMode:"environment"},{fps:8,qrbox:{width:220,height:220}},async raw=>{
   if(H2.reader!==r||busy)return;const k=hqKeyOf(raw);const now=Date.now();if(!k||(k===last&&now-lastAt<2500))return;last=k;lastAt=now;busy=true;
   try{await onCode(k)}catch(e){alert(h2Err(e))}finally{busy=false}
  },()=>{});
 }catch(e){el.innerHTML=`<div class="err">カメラを開けませんでした：${esc(h2Err(e))}<br>下の一覧から選べます。</div>`}
}
function h2Beep(){try{const a=new (window.AudioContext||window.webkitAudioContext)();const o=a.createOscillator();o.frequency.value=880;o.connect(a.destination);o.start();setTimeout(()=>{o.stop();a.close()},120)}catch(e){}try{navigator.vibrate&&navigator.vibrate(80)}catch(e){}}

/* ---------- A4縦のPDF ---------- */
let h2PdfUrl="";
function h2PdfStatus(msg,type="notice",url="",name=""){
 let host=document.getElementById("h2PdfStatus");
 if(!host){const t=document.querySelector(".wrap")||document.body;host=document.createElement("div");host.id="h2PdfStatus";t.prepend(host)}
 const open=url?`<a class="btn blue" style="display:block;width:100%;margin-top:10px;text-decoration:none;text-align:center" href="${esc(url)}" target="_blank" rel="noopener" download="${esc(name)}">PDFを開く・印刷</a>`:"";
 host.innerHTML=`<div class="${type}">${msg}${open}</div>`;try{host.scrollIntoView({block:"start"})}catch(_){}
}
async function h2MakePdf(pagesHtml,css,name){
 if(h2PdfUrl){try{URL.revokeObjectURL(h2PdfUrl)}catch(_){}h2PdfUrl=""}
 h2PdfStatus("A4縦のPDFを作成中です。しばらくお待ちください…");let root=null;
 try{
  if(typeof window.html2canvas!=="function"||!window.jspdf||typeof window.jspdf.jsPDF!=="function")throw new Error("PDF作成の部品が読み込まれていません。通信を確認して、もう一度お試しください。");
  root=document.createElement("div");root.className="h2PdfRoot";root.setAttribute("aria-hidden","true");
  root.style.cssText="position:fixed;left:-20000px;top:0;width:794px;background:#fff;pointer-events:none;font-family:'Hiragino Sans','Noto Sans JP',sans-serif;color:#000";
  root.innerHTML=`<style>.h2PdfRoot *{box-sizing:border-box}.h2PdfRoot .h2Page{width:794px;height:1123px;padding:34px 36px;background:#fff;overflow:hidden;position:relative}${css||""}</style>`+pagesHtml.map(p=>`<div class="h2Page">${p}</div>`).join("");
  document.body.appendChild(root);
  if(document.fonts&&document.fonts.ready)await document.fonts.ready;
  await Promise.all([...root.querySelectorAll("img")].map(i=>i.complete?0:new Promise(r=>{i.onload=i.onerror=r})));
  const{jsPDF}=window.jspdf,doc=new jsPDF({orientation:"portrait",unit:"mm",format:"a4",compress:true});
  const pg=[...root.querySelectorAll(".h2Page")];
  for(let i=0;i<pg.length;i++){
   const c=await window.html2canvas(pg[i],{scale:2,backgroundColor:"#ffffff",useCORS:true,logging:false,width:794,height:1123,windowWidth:794,windowHeight:1123});
   if(i)doc.addPage("a4","portrait");doc.addImage(c.toDataURL("image/png"),"PNG",0,0,210,297,undefined,"FAST");
  }
  const blob=doc.output("blob");if(!blob||!blob.size)throw new Error("PDFの作成に失敗しました。");
  h2PdfUrl=URL.createObjectURL(blob);
  h2PdfStatus(`PDFを作成しました（${pg.length}枚・A4縦）。下のボタンで開いて印刷してください。`,"ok",h2PdfUrl,name);
  return true;
 }catch(e){h2PdfStatus(`PDFを作成できませんでした。${esc(h2Err(e))}`,"err");return false}
 finally{if(root)root.remove()}
}
function h2Qr(payload,cell=8){if(typeof qrcode!=="function")throw new Error("QRを作れませんでした");const q=qrcode(0,"M");q.addData(String(payload));q.make();return q.createDataURL(cell,2)}

/* ---------- 画面の色（ホームのボタンはほかと重ならない色） ---------- */
(()=>{if(document.getElementById("h2Css"))return;const st=document.createElement("style");st.id="h2Css";st.textContent=`
.hqBtnPrep{background:linear-gradient(135deg,#a855f7,#581c87)!important;color:#fff!important}
.hqBtnPrepCheck{background:linear-gradient(135deg,#d946ef,#86198f)!important;color:#fff!important}
.hqBtnQuality{background:linear-gradient(135deg,#dc2626,#7f1d1d)!important;color:#fff!important}
.hqBtnYield{background:linear-gradient(135deg,#22c55e,#14532d)!important;color:#fff!important}
.hqBtnWaste{background:linear-gradient(135deg,#a16207,#422006)!important;color:#fff!important}
.hqBtnPrice{background:linear-gradient(135deg,#fde047,#ca8a04)!important;color:#1c1917!important}
.hqBtnMaster{background:linear-gradient(135deg,#2dd4bf,#115e59)!important;color:#fff!important}
.hqBtnStaff{background:linear-gradient(135deg,#374151,#030712)!important;color:#fff!important}
.hqBtnExcelOut{background:linear-gradient(135deg,#ffffff,#e2e8f0)!important;color:#14532d!important;border:3px solid #15803d!important}.homePrimary .btn.hqBtnExcelOut,.hqHomeGrid .btn.hqBtnExcelOut,.btn.hqBtnExcelOut span{color:#14532d!important;text-shadow:none!important}
.hqBtnUsage{background:linear-gradient(135deg,#60a5fa,#1e3a8a)!important;color:#fff!important}
.hqBtnTake{background:linear-gradient(135deg,#fb923c,#7c2d12)!important;color:#fff!important}
.hqBtnTime{background:linear-gradient(135deg,#94a3b8,#1e293b)!important;color:#fff!important}
.h2Big{width:100%;min-height:72px!important;font-size:22px!important;font-weight:900!important}
.h2Steps{display:flex;gap:4px;margin:0 0 10px;flex-wrap:wrap}
.h2Steps span{flex:1;min-width:58px;text-align:center;padding:6px 2px;border-radius:10px;background:#e2e8f0;color:#475569;font-weight:800;font-size:13px}
.h2Steps span.on{background:#7c3aed;color:#fff}.h2Steps span.done{background:#dcfce7;color:#166534}
.h2Chip{display:inline-flex;align-items:center;gap:6px;margin:3px 4px 3px 0;padding:6px 10px;border-radius:999px;background:#ede9fe;color:#4c1d95;font-weight:800}
.h2Chip button{border:0;background:#c4b5fd;color:#2e1065;border-radius:999px;width:26px;height:26px;font-weight:900}
.h2Work{border-left:8px solid #16a34a}.h2Work.s入力待ち{border-left-color:#d97706}.h2Work.s清掃中{border-left-color:#0284c7}.h2Work.s完了{border-left-color:#94a3b8}.h2Work.s取消{border-left-color:#cbd5e1;opacity:.7}
.h2Badge{display:inline-block;padding:3px 10px;border-radius:999px;font-weight:900;font-size:13px;color:#fff}
.h2B作業中{background:#16a34a}.h2B入力待ち{background:#d97706}.h2B清掃中{background:#0284c7}.h2B完了{background:#64748b}.h2B取消{background:#94a3b8}
.h2Sum{display:grid;grid-template-columns:repeat(3,1fr);gap:8px}.h2Sum div{background:#f1f5f9;border-radius:12px;padding:8px;text-align:center}.h2Sum b{display:block;font-size:24px}
.h2Tbl{border-collapse:collapse;font-size:14px;min-width:100%}.h2Tbl th,.h2Tbl td{padding:6px 8px;border-bottom:1px solid #e2e8f0;white-space:nowrap;text-align:right}.h2Tbl th{background:#f8fafc;border-bottom:2px solid #cbd5e1}.h2Tbl td:first-child,.h2Tbl th:first-child{text-align:left;position:sticky;left:0;background:#fff}.h2Tbl th:first-child{background:#f8fafc}
.h2Red{color:#dc2626!important;font-weight:900}
.h2Tabs{display:flex;gap:6px;flex-wrap:wrap}.h2Tabs .btn{flex:1;min-width:90px}
.h2Line{display:grid;grid-template-columns:1fr auto 1fr auto;gap:6px;align-items:end;margin-top:6px}
.h2Line .x{min-height:44px;padding:0 10px}
`;document.head.appendChild(st)})();

/* ---------- 共通データ ---------- */
async function h2Staff(all=false){return sel2("hq_staff_v1500",`select=*${all?"":"&deleted_at=is.null"}&order=print_group.asc,sort_order.asc,created_at.asc&limit=2000`)}
async function h2Teams(){return sel2("hq_teams_v1500","select=*&active=eq.true&order=sort_order.asc")}
async function h2Places(all=false){return sel2("hq_places_v1500",`select=*${all?"":"&active=eq.true"}&order=sort_order.asc`)}
async function h2Tasks(all=false){return sel2("hq_tasks_v1500",`select=*${all?"":"&active=eq.true"}&order=sort_order.asc`)}
async function h2Masters(all=false){return sel2("hq_prep_masters_v1500",`select=*${all?"":"&active=eq.true"}&order=item_name.asc,sort_order.asc`)}
async function h2QrItems(){return sel2("hq_items_v1400","select=*&active=eq.true&order=sort_order.asc")}
async function h2Works(q){return sel2("hq_works_v1500",q)}
async function h2Members(ids){if(!ids.length)return[];const out=[];for(let i=0;i<ids.length;i+=60)out.push(...await sel2("hq_work_members_v1500",`select=*&work_id=in.(${ids.slice(i,i+60).join(",")})&order=start_at.asc&limit=5000`));return out}
async function h2Materials(ids){if(!ids.length)return[];const out=[];for(let i=0;i<ids.length;i+=60)out.push(...await sel2("hq_work_materials_v1500",`select=*&work_id=in.(${ids.slice(i,i+60).join(",")})&order=created_at.asc&limit=5000`));return out}
function h2MatKg(m){const q=Number(m.qty);if(!Number.isFinite(q))return null;if(m.unit==="kg")return q;return Number(m.pack_kg)>0?q*Number(m.pack_kg):null}
function h2UsedKg(mats){let s=0,unknown=false;for(const m of mats){const k=h2MatKg(m);if(k==null)unknown=true;else s+=k}return{kg:s,unknown}}
function h2Diff(w,mats){const u=h2UsedKg(mats);if(w.yield_kg==null||w.waste_kg==null||!u.kg)return null;const d=u.kg-(Number(w.yield_kg)+Number(w.waste_kg));return{kg:d,rate:d/u.kg,used:u.kg,unknown:u.unknown}}
function h2Yield(w){const y=Number(w.yield_kg),ws=Number(w.waste_kg);if(!(y+ws>0))return null;return y/(y+ws)}
let h2PriceCache={};
async function h2Prices(from,to,items){
 if(!h2CanMoney())return{};
 const key=`${from}|${to}|${(items||[]).join(",")}`;if(h2PriceCache[key])return h2PriceCache[key];
 const rows=await r2("hq_price_table_v1500",{p_from:from,p_to:to,p_items:items&&items.length?items:null});
 const map={};(Array.isArray(rows)?rows:[]).forEach(r=>{map[`${r.item_name}|${r.week}`]=r});h2PriceCache[key]=map;return map;
}
function h2PriceOf(map,item,date){const r=map[`${item}|${h2Monday(date)}`];return r&&r.price!=null?Number(r.price):null}

Object.assign(window,{h2StopReader});
window.__h2=Object.assign(window.__h2||{},{H2,r2,sel2,enc2,num2,kg2,yen2,pct2,time2,dt2,md2,mins2,hm2,btnAttr,roleIs,h2CanPrep,h2CanBoss,h2CanRaw,h2CanMoney,h2CanCount,h2CanReport,h2Month,h2MonthRange,h2MonthLabel,h2Monday,h2FiscalStart,h2Err,h2Notice,h2Loading,h2Set,h2Val,h2Stage2,h2Every,h2StartReader,h2StopReader,h2Beep,h2MakePdf,h2PdfStatus,h2Qr,h2Staff,h2Teams,h2Places,h2Tasks,h2Masters,h2QrItems,h2Works,h2Members,h2Materials,h2MatKg,h2UsedKg,h2Diff,h2Yield,h2Prices,h2PriceOf});
})();

/* ===== 下処理・作業（パートさん＝下処理班の共用アカウント／本社社員） ===== */
(function(){
"use strict";
const X=window.__h2;const{H2,r2,sel2,num2,kg2,time2,dt2,md2,mins2,hm2,btnAttr,h2CanPrep,h2CanBoss,h2Err,h2Notice,h2Loading,h2Set,h2Val,h2Stage2,h2Every,h2StartReader,h2StopReader,h2Beep,h2MakePdf,h2Qr,h2Staff,h2Places,h2Tasks,h2Masters,h2Works,h2Members,h2Materials,h2Diff}=X;
const OP={"HQOP-START":"start","HQOP-END":"end","HQOP-CLEAN":"clean","HQOP-CLEANEND":"cleanend"};
const OP_LABEL={start:"作業開始",end:"作業終了",clean:"清掃",cleanend:"清掃終了"};
function opOf(k){return OP[String(k||"").toUpperCase()]||""}

/* --- いま動いている作業（全端末で同じ一覧。自動で更新） --- */
function workCard(w,mem,mats){
 const people=mem.filter(m=>m.work_id===w.id&&!m.end_at);
 const lots=mats.filter(m=>m.work_id===w.id);
 const label=w.status==="入力待ち"?"作業終了・数量未入力":w.status;
 const title=w.kind==="下処理"?`${esc(w.raw_item_name||"")} → ${esc(w.product_name||"")}`:esc(w.task_name);
 return `<div class="card h2Work s${esc(w.status)}"><div class="itemHead"><div><b style="font-size:20px">${esc(w.place||"場所なし")}</b></div><span class="h2Badge h2B${esc(w.status)}">${esc(label)}</span></div>
 <div style="font-size:18px;font-weight:900;margin-top:4px">${title}</div>
 ${lots.length?`<div class="small">原料：${esc(lots.map(l=>l.lot_no).slice(0,2).join("、"))}${lots.length>2?` ほか${lots.length-2}ロット`:""}</div>`:""}
 <div class="small">開始 ${time2(w.started_at)}　${w.status==="入力待ち"?"作業者：入力を待っています":`作業者 ${people.length}名：${esc(people.map(p=>p.staff_name).join("、"))}`}</div>
 <button class="btn btn2" style="width:100%;margin-top:8px" ${btnAttr("hqWorkPage",[w.id])}>開く</button></div>`;
}
async function liveData(){
 const works=await h2Works("select=*&status=in.(作業中,入力待ち,清掃中)&order=started_at.asc&limit=200");
 const ids=works.map(w=>w.id);const[mem,mats]=await Promise.all([h2Members(ids),h2Materials(ids)]);
 return{works,mem,mats};
}
async function renderLive(){
 try{
  const{works,mem,mats}=await liveData();
  const people=mem.filter(m=>!m.end_at).length,waiting=works.filter(w=>w.status==="入力待ち").length;
  h2Set("h2LiveSum",`<div class="h2Sum"><div><b>${works.length}</b>作業</div><div><b>${people}</b>人</div><div><b class="${waiting?"h2Red":""}">${waiting}</b>未入力</div></div>`);
  h2Set("h2LiveList",works.length?works.map(w=>workCard(w,mem,mats)).join(""):'<div class="notice">いま動いている作業はありません。</div>');
  const t=document.getElementById("h2LiveTime");if(t)t.textContent=`${time2(new Date())} 更新`;
 }catch(e){h2Set("h2LiveList",`<div class="err">${esc(h2Err(e))}</div>`)}
}
async function hqPrepHome(msg=""){
 setScreen("hqPrepHome",[msg]);
 if(!h2CanPrep()&&!h2CanBoss())return hqHome();
 const on=await h2Stage2();
 pageShell(db.role==="hq_prep"?"SEIKA＋":"いま動いている作業",db.role==="hq_prep"?`本社 下処理 / ${esc(db.user||"")}`:"下処理・作業・清掃（どの端末からも同じ一覧）",`${okHtml(msg)}
 <div class="card" id="h2LiveSum">${h2Loading()}</div>
 ${h2CanPrep()?`<div class="card"><button class="btn hqBtnPrep h2Big" ${btnAttr("hqPrepNew",["下処理"])}>＋ 新しい下処理を始める</button>
 <div class="small" style="margin-top:6px">原料QR → 仕掛品 → 作業場所 → 作業する人のQR → 作業開始</div>
 <div class="row" style="margin-top:10px"><button class="btn btn2" ${btnAttr("hqPrepNew",["作業"])}>ほかの作業を始める</button><button class="btn btn2" ${btnAttr("hqPrepNew",["清掃"])}>清掃だけ始める</button></div>
 <button class="btn btn2" style="width:100%;margin-top:8px" ${btnAttr("hqOpScanPage",[])}>QRを読む（作業開始・作業終了・清掃終了）</button></div>`:""}
 <div class="small" style="text-align:right" id="h2LiveTime"></div>
 <div id="h2LiveList">${h2Loading()}</div>
 ${db.role==="hq_prep"&&!on?`<button class="btn hqBtnOut" style="width:100%;margin-top:12px" ${btnAttr("hqOutPage",[])}>使用出庫（いまの使い方）</button>`:""}
 ${db.role==="hq_prep"?`<button class="btn hqBtnGuide" style="width:100%;margin-top:12px" ${btnAttr("v195RoleGuidePage",[])}>操作ガイド</button>`:""}
 <div class="card small">同じ人は、同時に1つの作業にしか入れません。ほかの作業に移るときは、その作業の画面で「抜ける」を押してください。</div>`,db.role==="hq_prep"?{noBack:true}:{});
 await renderLive();h2Every(15000,renderLive);
}

/* --- 新しい作業を始める --- */
let NW=null;
function nwReset(kind){NW={kind,lots:[],masterId:"",place:"",task:"",staff:[],op:newId()}}
async function hqPrepNew(kind="下処理",keep=false){
 if(!h2CanPrep())return alert("この操作の権限がありません");
 if(!keep||!NW||NW.kind!==kind)nwReset(kind);
 setScreen("hqPrepNew",[kind]);
 const title=kind==="下処理"?"新しい下処理":kind==="清掃"?"清掃だけ始める":"ほかの作業を始める";
 pageShell(title,"QRを読み取るか、下の一覧から選んでください",`<div id="h2NwSteps"></div><div id="h2NwReader" style="width:100%;min-height:240px;background:#0f172a;border-radius:14px"></div><div class="small" style="margin:6px 0 10px">${kind==="下処理"?"原料の貼り紙のQR・作業する人のスタッフQR・「作業開始」のQRを続けて読み取れます。":"作業する人のスタッフQR・「作業開始」（清掃は「清掃」）のQRを続けて読み取れます。"}</div><div id="h2NwBody">${h2Loading()}</div>`);
 let masters=[],places=[],staff=[],tasks=[],lots=[];
 try{[masters,places,staff,tasks,lots]=await Promise.all([h2Masters(),h2Places(),h2Staff(),h2Tasks(),kind==="下処理"?hqLots("select=id,qr_key,lot_no,item_name,current_qty,unit,status,hq_received_date&status=eq.在庫あり&order=item_name.asc,hq_received_date.asc&limit=500"):Promise.resolve([])])}
 catch(e){return h2Set("h2NwBody",`<div class="err">${esc(h2Err(e))}</div><div class="notice">019のSQLが未実行の可能性があります。</div>`)}
 NW.cache={masters,places,staff,tasks,lots};
 nwRender();
 h2StartReader("h2NwReader",nwScan);
}
function nwRender(){
 const{masters,places,staff,tasks,lots}=NW.cache,k=NW.kind;
 const item=NW.lots[0]?.item_name||"";
 const cands=masters.filter(m=>m.item_name===item);
 if(NW.masterId&&!cands.some(m=>m.id===NW.masterId))NW.masterId="";
 if(!NW.masterId&&cands.length===1)NW.masterId=cands[0].id;
 const st=(i,label,done)=>`<span class="${done?"done":""}">${i} ${label}</span>`;
 const steps=k==="下処理"?[st("①","原料",NW.lots.length),st("②","仕掛品",NW.masterId),st("③","場所",NW.place),st("④","人",NW.staff.length)]:k==="作業"?[st("①","作業名",NW.task),st("②","場所",NW.place),st("③","人",NW.staff.length)]:[st("①","場所",NW.place),st("②","人",NW.staff.length)];
 const ready=k==="下処理"?NW.lots.length&&NW.masterId&&NW.place&&NW.staff.length:k==="作業"?NW.task&&NW.place&&NW.staff.length:NW.place&&NW.staff.length;
 const lotOpts=lots.filter(l=>!NW.lots.some(x=>x.id===l.id)&&(!item||l.item_name===item)).map(l=>`<option value="${esc(l.id)}">${esc(l.item_name)} ${esc(l.lot_no)}（${hqQty(l.current_qty)}${esc(l.unit)}）</option>`).join("");
 const staffOpts=g=>staff.filter(s=>s.print_group===g&&!NW.staff.some(x=>x.id===s.id)).map(s=>`<option value="${esc(s.id)}">${esc(s.name)}（${esc(s.team)}）</option>`).join("");
 h2Set("h2NwSteps",`<div class="h2Steps">${steps.join("")}<span class="${ready?"on":""}">${k==="清掃"?"清掃開始":"作業開始"}</span></div>`);
 const html=`${k==="下処理"?`<div class="card"><b>① 原料</b><div style="margin-top:6px">${NW.lots.map(l=>`<span class="h2Chip">${esc(l.item_name)} ${esc(l.lot_no)}<button ${btnAttr("h2NwDelLot",[l.id])}>×</button></span>`).join("")||'<span class="small">まだありません（QRを読み取ってください）</span>'}</div>
  ${lotOpts?`<select class="input" style="margin-top:6px" ${seikaEventAttrs("change","h2NwAddLot",[{__seikaValue:true}])}><option value="">一覧から選ぶ（QRが読めないとき）</option>${lotOpts}</select>`:""}</div>
 <div class="card"><b>② 仕掛品</b>${!item?'<div class="small">先に原料を選んでください。</div>':cands.length?`<div class="h2Tabs" style="margin-top:6px">${cands.map(m=>`<button class="btn ${NW.masterId===m.id?"hqBtnPrep":"btn2"}" ${btnAttr("h2NwSet",["masterId",m.id])}>${esc(m.name)}</button>`).join("")}</div>`:`<div class="err">「${esc(item)}」の仕掛品が下処理マスタにありません。本社社員に登録を頼んでください。</div>`}</div>`:""}
 ${k==="作業"?`<div class="card"><b>① 作業名</b><div class="h2Tabs" style="margin-top:6px">${tasks.filter(t=>t.kind==="作業").map(t=>`<button class="btn ${NW.task===t.name?"hqBtnPrep":"btn2"}" ${btnAttr("h2NwSet",["task",t.name])}>${esc(t.name)}</button>`).join("")||'<span class="small">作業名がありません。本社社員が「スタッフQR → 作業名・作業場所」で追加します。</span>'}</div></div>`:""}
 <div class="card"><b>${k==="下処理"?"③":k==="作業"?"②":"①"} 作業場所</b><div class="h2Tabs" style="margin-top:6px">${places.map(p=>`<button class="btn ${NW.place===p.name?"hqBtnPrep":"btn2"}" ${btnAttr("h2NwSet",["place",p.name])}>${esc(p.name)}</button>`).join("")}</div></div>
 <div class="card"><b>${k==="下処理"?"④":k==="作業"?"③":"②"} 作業する人（${NW.staff.length}名）</b><div style="margin-top:6px">${NW.staff.map(s=>`<span class="h2Chip">${esc(s.name)}<button ${btnAttr("h2NwDelStaff",[s.id])}>×</button></span>`).join("")||'<span class="small">スタッフQRを読み取ってください。</span>'}</div>
  <details style="margin-top:6px"><summary class="small">QRが読めないときは、一覧から選ぶ</summary>${[1,2,3,4,5,6].map(g=>staffOpts(g)?`<select class="input" style="margin-top:6px" ${seikaEventAttrs("change","h2NwAddStaff",[{__seikaValue:true}])}><option value="">${"①②③④⑤⑥"[g-1]} の人から選ぶ</option>${staffOpts(g)}</select>`:"").join("")}</details></div>
 <button class="btn hqBtnPrep h2Big" ${ready?"":"disabled"} ${btnAttr("h2NwStart",[])}>${k==="清掃"?"清掃開始":"作業開始"}</button>`;
 h2Set("h2NwBody",html);
}
async function nwScan(k){
 const op=opOf(k);
 if(op){if(op==="start"||(op==="clean"&&NW.kind==="清掃"))return h2NwStart();return alert(`「${OP_LABEL[op]}」のQRです。作業を始めてから使います。`)}
 if(/^HQST-/i.test(k)){const s=NW.cache.staff.find(x=>x.qr_key===k);if(!s)return alert("このスタッフQRは登録されていません（削除された人かもしれません）");if(!NW.staff.some(x=>x.id===s.id)){NW.staff.push(s);h2Beep()}return nwRender()}
 if(/^HQ-|^H\d{8}-/.test(k)){
  if(NW.kind!=="下処理")return alert("原料のQRは、下処理のときに読み取ります");
  const l=(await hqLots(`select=id,qr_key,lot_no,item_name,current_qty,unit,status&or=(qr_key.eq.${encodeURIComponent(k)},lot_no.eq.${encodeURIComponent(k)})&limit=1`))[0];
  return addLot(l);
 }
 alert("本社の原料・スタッフ・操作用のQRではありません");
}
function addLot(l){
 if(!l)return alert("この原料は見つかりません");
 if(!["在庫あり","在庫なし"].includes(l.status))return alert(`この原料は、まだ使えません（${l.status}）。受け入れの確定をしてください`);
 if(!NW.lots.some(x=>x.id===l.id)&&window.hqLimitGuard&&!window.hqLimitGuard(l,"下処理に使う"))return;
 if(NW.lots.length&&NW.lots[0].item_name!==l.item_name)return alert(`ちがう品目です（${l.item_name}）。1つの下処理では、同じ品目の原料だけを使います`);
 if(!NW.lots.some(x=>x.id===l.id)){NW.lots.push(l);h2Beep()}
 nwRender();
}
function h2NwAddLot(id){if(!id)return;const l=NW.cache.lots.find(x=>x.id===id);addLot(l)}
function h2NwDelLot(id){NW.lots=NW.lots.filter(x=>x.id!==id);nwRender()}
function h2NwAddStaff(id){if(!id)return;const s=NW.cache.staff.find(x=>x.id===id);if(s&&!NW.staff.some(x=>x.id===id))NW.staff.push(s);nwRender()}
function h2NwDelStaff(id){NW.staff=NW.staff.filter(x=>x.id!==id);nwRender()}
function h2NwSet(k,v){NW[k]=v;nwRender()}
async function h2NwStart(){
 if(H2.busy)return;const k=NW.kind;
 if(k==="下処理"&&(!NW.lots.length||!NW.masterId))return alert("原料と仕掛品を選んでください");
 if(k==="作業"&&!NW.task)return alert("作業名を選んでください");
 if(!NW.place)return alert("作業場所を選んでください");
 if(!NW.staff.length)return alert("作業する人のスタッフQRを読み取ってください");
 H2.busy=true;
 try{
  const r=await r2("hq_work_start_v1500",{p_operation_id:NW.op,p_kind:k,p_task_name:k==="作業"?NW.task:null,p_place:NW.place,p_master_id:k==="下処理"?NW.masterId:null,p_lot_ids:k==="下処理"?NW.lots.map(l=>l.id):null,p_staff_ids:NW.staff.map(s=>s.id)});
  H2.busy=false;NW=null;await h2StopReader();return hqWorkPage(r.id,k==="清掃"?"清掃を始めました":"作業を始めました");
 }catch(e){H2.busy=false;alert(h2Err(e))}
}

/* --- 操作用QRを読む画面（作業開始・作業終了・清掃・清掃終了） --- */
let OPS={op:"",staff:[]};
async function hqOpScanPage(msg=""){
 setScreen("hqOpScanPage",[msg]);
 pageShell("QRを読む","作業者のスタッフQR → 操作用QR（作業終了・清掃終了など）",`${okHtml(msg)}<div id="h2OpReader" style="width:100%;min-height:260px;background:#0f172a;border-radius:14px"></div><div class="card" id="h2OpInfo"></div>`);
 OPS={op:"",staff:[]};opInfo();
 h2StartReader("h2OpReader",opScan);
}
function opInfo(){h2Set("h2OpInfo",`<div><b>読み取った人：</b>${OPS.staff.map(s=>`<span class="h2Chip">${esc(s.name)}</span>`).join("")||"まだいません"}</div><div class="small" style="margin-top:6px">・作業終了／清掃終了：その人が入っている作業を終えます。<br>・作業開始：新しい作業を始める画面に進みます。<br>・清掃：読み取った人で「清掃だけ」を始めます。</div>`)}
async function opScan(k){
 const op=opOf(k);
 if(/^HQST-/i.test(k)){const s=(await sel2("hq_staff_v1500",`select=*&qr_key=eq.${encodeURIComponent(k)}&deleted_at=is.null`))[0];if(!s)return alert("このスタッフQRは登録されていません");if(!OPS.staff.some(x=>x.id===s.id)){OPS.staff.push(s);h2Beep()}return opInfo()}
 if(!op)return alert("スタッフQRか操作用のQRを読み取ってください");
 if(op==="start"||op==="clean"){
  const kind=op==="start"?"下処理":"清掃";nwReset(kind);NW.staff=[...OPS.staff];await h2StopReader();return hqPrepNew(kind,true);
 }
 if(!OPS.staff.length)return alert("先に、作業している人のスタッフQRを1人分読み取ってください");
 const mem=await sel2("hq_work_members_v1500",`select=work_id,staff_name&staff_id=eq.${OPS.staff[0].id}&end_at=is.null&limit=1`);
 if(!mem[0])return alert(`${OPS.staff[0].name}さんは、いま作業に入っていません`);
 await h2StopReader();
 if(op==="end")return h2WorkEnd(mem[0].work_id);
 return h2CleanEnd(mem[0].work_id);
}

/* --- 作業の画面 --- */
async function hqWorkPage(id,msg=""){
 setScreen("hqWorkPage",[id,msg]);
 pageShell("作業","",h2Loading());
 let w,mem=[],mats=[],staff=[];
 try{
  w=(await h2Works(`select=*&id=eq.${id}`))[0];if(!w)return pageShell("作業","見つかりません",'<div class="err">この作業は見つかりません。</div>');
  [mem,mats]=await Promise.all([h2Members([id]),h2Materials([id])]);
 }catch(e){return pageShell("作業","エラー",`<div class="err">${esc(h2Err(e))}</div>`)}
 const open=mem.filter(m=>!m.end_at);
 const title=w.kind==="下処理"?`${w.raw_item_name||""} → ${w.product_name||""}`:w.task_name;
 let body=`${okHtml(msg)}<div class="card h2Work s${esc(w.status)}"><div class="itemHead"><div><b style="font-size:21px">${esc(title)}</b><div class="small">${esc(w.place||"")} ／ ${esc(w.work_date)} 開始 ${time2(w.started_at)}${w.ended_at?` ／ 終了 ${time2(w.ended_at)}`:""}</div></div><span class="h2Badge h2B${esc(w.status)}">${esc(w.status==="入力待ち"?"作業終了・数量未入力":w.status)}</span></div>
 ${mats.length?`<div class="small" style="margin-top:6px">原料：${mats.map(m=>`${esc(m.lot_no)}（${esc(m.unit==="kg"?"kg":"ケース")}${m.pack_kg?`・量目${hqQty(m.pack_kg)}kg`:""}）`).join("、")}</div>`:""}
 ${w.kind==="下処理"&&w.confirm_status!=="未確定"?`<div style="margin-top:6px"><span class="badge ${w.confirm_status==="確定"?"normal":"unset"}">${esc(w.confirm_status)}</span></div>`:""}</div>`;
 if(w.status==="作業中"||w.status==="清掃中"){
  body+=`<div class="card"><b>いまの作業者（${open.length}名）</b>${open.map(m=>`<div class="itemHead" style="padding:6px 0;border-top:1px solid #e2e8f0"><div><b>${esc(m.staff_name)}</b><div class="small">${esc(m.team||"")} ／ ${m.phase} ${time2(m.start_at)}〜</div></div>${h2CanPrep()?`<button class="btn btn2" style="min-height:40px" ${btnAttr("h2WorkLeave",[w.id,m.staff_id,m.staff_name])}>抜ける</button>`:""}</div>`).join("")||'<div class="small">いません</div>'}
  ${h2CanPrep()?`<button class="btn btn2" style="width:100%;margin-top:8px" ${btnAttr("h2WorkJoinOpen",[w.id])}>途中から入る人を追加（スタッフQR）</button><div id="h2JoinBox"></div>`:""}</div>`;
  if(h2CanPrep())body+=w.status==="作業中"?`<button class="btn hqBtnOut h2Big" ${btnAttr("h2WorkEnd",[w.id])}>作業終了</button><div class="small" style="text-align:center;margin-top:4px">「作業終了」のQRを読み取っても終われます（QRを読む画面）。</div>`:`<button class="btn blue h2Big" ${btnAttr("h2CleanEnd",[w.id])}>清掃終了</button>`;
 }
 if(w.kind==="下処理"&&w.status==="入力待ち"&&h2CanPrep()&&w.confirm_status==="未確定"){
  body+=`<div class="card"><b style="font-size:19px">⑥ 使用原料の数</b>${mats.map(m=>`<label class="label" style="margin-top:8px">${esc(m.item_name)} ${esc(m.lot_no)}（${m.unit==="kg"?"kg":"ケース・小数も入れられます"}）</label><input class="input h2MatQty" data-id="${esc(m.id)}" inputmode="decimal" value="${m.qty==null?"":hqQty(m.qty)}" placeholder="${m.unit==="kg"?"例：120":"例：3.5"}">`).join("")}
  <label class="label" style="margin-top:12px;font-size:19px">⑦ 廃棄（kg・無ければ0）</label><input id="h2Waste" class="input" inputmode="decimal" value="${w.waste_kg==null?"":hqQty(w.waste_kg)}" placeholder="例：0">
  <label class="label" style="margin-top:12px;font-size:19px">⑧ 出来高（kg）</label><input id="h2Yield" class="input" inputmode="decimal" value="${w.yield_kg==null?"":hqQty(w.yield_kg)}" placeholder="例：85">
  <button class="btn hqBtnPrep h2Big" style="margin-top:12px" ${btnAttr("h2SaveInputs",[w.id])}>保存して ⑨ 清掃へ</button></div>`;
  if(w.inputs_saved_at)body+=labelBox(w,true);
 }
 if(w.kind==="下処理"&&(w.status==="清掃中"||w.status==="完了")&&w.confirm_status!=="取消"&&h2CanPrep())body+=labelBox(w,false);
 if(w.kind==="下処理"&&w.inputs_saved_at){
  const d=h2Diff(w,mats);
  body+=`<div class="card"><b>入力した数</b><div class="small">使用原料：${mats.map(m=>`${esc(m.lot_no)} ${m.qty==null?"—":hqQty(m.qty)}${m.unit==="kg"?"kg":"ケース"}`).join("、")}</div><div class="small">廃棄 ${kg2(w.waste_kg)}kg ／ 出来高 ${kg2(w.yield_kg)}kg${d?` ／ 差 <span class="${Math.abs(d.rate)>=0.1?"h2Red":""}">${kg2(d.kg)}kg（${X.pct2(d.rate)}）</span>`:""}</div><div class="small">入力：${esc(w.inputs_saved_by_name||"")} ${dt2(w.inputs_saved_at)}${w.label_printed_at?` ／ ラベル印刷 ${dt2(w.label_printed_at)}（${w.label_print_count}回）`:""}</div></div>`;
 }
 body+=`<div class="card"><b>作業時間の記録</b>${mem.map(m=>`<div style="padding:6px 0;border-top:1px solid #e2e8f0"><b>${esc(m.staff_name)}</b> <span class="small">${m.phase}</span><div class="small">${time2(m.start_at)}〜${m.end_at?time2(m.end_at):"（作業中）"}　${hm2(mins2(m.start_at,m.end_at))}${m.end_reason?` ／ ${esc(m.end_reason)}`:""}${m.fixed_by_name?` ／ 修正：${esc(m.fixed_by_name)}`:""}</div>${h2CanBoss()?`<button class="btn btn2" style="min-height:36px;margin-top:4px" ${btnAttr("h2FixMember",[m.id,m.start_at,m.end_at||"",m.staff_name])}>時刻を直す</button>`:""}</div>`).join("")||'<div class="small">まだありません</div>'}
 ${h2CanBoss()?`<button class="btn btn2" style="width:100%;margin-top:8px" ${btnAttr("h2AddMemberPage",[w.id])}>読み忘れた人を追加する</button>`:""}</div>`;
 if(w.status!=="取消"&&w.status!=="完了"&&(h2CanBoss()||(db.role==="hq_prep"&&w.status==="作業中")))body+=`<details class="card"><summary><b>間違えて始めた作業を取り消す</b></summary><button class="btn red" style="width:100%;margin-top:8px" ${btnAttr("h2WorkCancel",[w.id])}>この作業を取り消す</button></details>`;
 if(h2CanBoss())body+=h2DeleteWorkHtml(w);
 if(h2CanBoss()&&w.kind==="下処理"&&w.status!=="作業中"&&w.status!=="取消")body+=`<button class="btn hqBtnPrepCheck" style="width:100%;margin-top:8px" ${btnAttr("hqPrepConfirmPage",[w.id])}>確認・確定の画面へ</button>`;
 body+=`<button class="btn btn2" style="width:100%;margin-top:12px" ${btnAttr("hqPrepHome",[])}>いま動いている作業の一覧へ</button>`;
 pageShell(w.kind==="下処理"?"下処理":w.kind==="清掃"?"清掃":"作業",`${esc(w.place||"")} ／ ${esc(w.status)}`,body);
 if(w.status==="作業中"||w.status==="清掃中")h2Every(20000,()=>{if(!document.getElementById("h2JoinReader")&&!document.activeElement?.matches?.("input,select,textarea"))hqWorkPage(id)});
}
var H2_LABEL_ON=window.H2_LABEL_ON=false;
function labelBox(w,beforeClean){
 if(!H2_LABEL_ON)return beforeClean?`<div class="card"><b style="font-size:19px">⑨ 清掃へ</b><div class="small" style="margin-top:4px">数を保存したら、清掃に移ります。</div><button class="btn hqBtnPrint h2Big" style="margin-top:10px" ${btnAttr("h2ToCleanNoLabel",[w.id])}>⑨ 清掃へ</button></div>`:"";
 const exp=w.expiry_days==null?"":ymdKey(new Date(new Date(w.work_date+"T00:00:00").getTime()+Number(w.expiry_days)*864e5));
 return `<div class="card"><b style="font-size:19px">⑨ 仕掛品ラベルを印刷</b><div class="small" style="margin-top:4px">品名「${esc(w.product_name||"")}」／ 下処理日 ${esc(w.work_date)} ／ 使用期限 ${esc(exp)}（QRは付きません）</div>
 <label class="label" style="margin-top:8px">ラベルの枚数（A4に8枚ずつ並びます）</label><input id="h2LabelN" class="input" inputmode="numeric" value="8">
 ${beforeClean?`<button class="btn hqBtnPrint h2Big" style="margin-top:10px" ${btnAttr("h2PrintLabel",[w.id,true])}>ラベルを印刷して ⑩ 清掃へ</button><button class="btn btn2" style="width:100%;margin-top:8px" ${btnAttr("h2ToClean",[w.id,false])}>印刷できないときは、印刷しないで清掃へ</button>`:`<button class="btn hqBtnPrint" style="width:100%;margin-top:10px" ${btnAttr("h2PrintLabel",[w.id,false])}>ラベルをもう一度印刷</button>`}</div>`;
}
async function h2WorkEnd(id){
 if(H2.busy)return;if(!confirm("作業を終わります。よろしいですか？"))return;H2.busy=true;
 try{const r=await r2("hq_work_end_v1500",{p_work_id:id});H2.busy=false;return hqWorkPage(id,r?.status==="入力待ち"?"作業を終えました。使用原料・廃棄・出来高を入れてください":"作業を終えました")}catch(e){H2.busy=false;alert(h2Err(e))}
}
async function h2CleanEnd(id){
 if(H2.busy)return;if(!confirm("清掃を終わります。よろしいですか？"))return;H2.busy=true;
 try{await r2("hq_work_clean_end_v1500",{p_work_id:id});H2.busy=false;return hqPrepHome("清掃を終えました。次の作業に進めます")}catch(e){H2.busy=false;alert(h2Err(e))}
}
async function h2WorkLeave(id,staffId,name){
 if(!confirm(`${name}さんが、この作業から抜けます。よろしいですか？`))return;
 try{await r2("hq_work_leave_v1500",{p_work_id:id,p_staff_id:staffId});return hqWorkPage(id,`${name}さんが抜けました`)}catch(e){alert(h2Err(e))}
}
async function h2WorkJoinOpen(id){
 const box=document.getElementById("h2JoinBox");if(!box)return;
 const staff=await h2Staff();
 box.innerHTML=`<div id="h2JoinReader" style="width:100%;min-height:220px;background:#0f172a;border-radius:14px;margin-top:8px"></div><select class="input" style="margin-top:6px" id="h2JoinSel"><option value="">QRが読めないときは一覧から選ぶ</option>${staff.map(s=>`<option value="${esc(s.id)}">${esc(s.name)}（${esc(s.team)}）</option>`).join("")}</select><button class="btn green" style="width:100%;margin-top:6px" ${btnAttr("h2JoinSelected",[id])}>選んだ人を入れる</button>`;
 h2StartReader("h2JoinReader",async k=>{
  if(!/^HQST-/i.test(k))return alert("スタッフQRを読み取ってください");
  const s=staff.find(x=>x.qr_key===k);if(!s)return alert("このスタッフQRは登録されていません");
  await r2("hq_work_join_v1500",{p_work_id:id,p_staff_ids:[s.id]});h2Beep();await h2StopReader();return hqWorkPage(id,`${s.name}さんが入りました`);
 });
}
async function h2JoinSelected(id){const sid=h2Val("h2JoinSel");if(!sid)return alert("人を選んでください");try{await r2("hq_work_join_v1500",{p_work_id:id,p_staff_ids:[sid]});await h2StopReader();return hqWorkPage(id,"追加しました")}catch(e){alert(h2Err(e))}}
async function h2SaveInputs(id){
 if(H2.busy)return;
 const mats=[];let bad="";
 document.querySelectorAll(".h2MatQty").forEach(el=>{const v=num2(el.value);if(!Number.isFinite(v)||v<0)bad="使用原料の数を入れてください";mats.push({id:el.dataset.id,qty:v})});
 const waste=num2(h2Val("h2Waste")),yld=num2(h2Val("h2Yield"));
 if(bad)return alert(bad);if(!Number.isFinite(waste)||waste<0)return alert("廃棄（kg）を入れてください。無ければ 0 です");if(!Number.isFinite(yld)||yld<0)return alert("出来高（kg）を入れてください");
 H2.busy=true;
 try{await r2("hq_work_save_inputs_v1500",{p_work_id:id,p_materials:mats,p_waste_kg:waste,p_yield_kg:yld});H2.busy=false;await hqWorkPage(id,H2_LABEL_ON?"保存しました。ラベルを印刷してください":"保存しました。「⑨ 清掃へ」を押してください");document.getElementById("h2LabelN")?.scrollIntoView({block:"center"})}catch(e){H2.busy=false;alert(h2Err(e))}
}
function labelPages(w,n){
 const exp=ymdKey(new Date(new Date(w.work_date+"T00:00:00").getTime()+Number(w.expiry_days||0)*864e5));
 const f=d=>{const x=new Date(d+"T00:00:00");return `${x.getMonth()+1}月${x.getDate()}日（${"日月火水木金土"[x.getDay()]}）`};
 const one=`<div class="lab"><div class="nm">${esc(w.product_name||"")}</div><table><tr><th>下処理日</th><td>${f(w.work_date)}</td></tr><tr><th>使用期限</th><td class="ex">${f(exp)}</td></tr></table></div>`;
 const pages=[];for(let i=0;i<n;i+=8)pages.push(`<div class="labs">${Array.from({length:Math.min(8,n-i)},()=>one).join("")}</div>`);return pages;
}
const LABEL_CSS=`.h2PdfRoot .labs{display:grid;grid-template-columns:1fr 1fr;grid-template-rows:repeat(4,1fr);gap:14px;height:100%}.h2PdfRoot .lab{border:3px solid #000;border-radius:10px;padding:14px 16px;display:flex;flex-direction:column;justify-content:center}.h2PdfRoot .nm{font-size:34px;font-weight:900;line-height:1.15;margin-bottom:10px;word-break:break-all}.h2PdfRoot .lab table{border-collapse:collapse;width:100%}.h2PdfRoot .lab th{font-size:18px;text-align:left;padding:4px 0;width:92px}.h2PdfRoot .lab td{font-size:26px;font-weight:900;padding:4px 0}.h2PdfRoot .lab td.ex{font-size:30px;text-decoration:underline}`;
async function h2PrintLabel(id,thenClean){
 if(H2.busy)return;
 const n=Math.max(1,Math.min(80,Math.round(num2(h2Val("h2LabelN"))||8)));
 H2.busy=true;
 try{
  const w=(await h2Works(`select=*&id=eq.${id}`))[0];if(!w)throw new Error("作業が見つかりません");
  const ok=await h2MakePdf(labelPages(w,n),LABEL_CSS,`仕掛品ラベル_${w.product_name||""}_${w.work_date}.pdf`);
  if(!ok){H2.busy=false;return}
  if(thenClean){await r2("hq_work_to_clean_v1500",{p_work_id:id,p_printed:true});H2.busy=false;const st=document.getElementById("h2PdfStatus")?.innerHTML||"";await hqWorkPage(id,"ラベルのPDFを作りました。作業者全員が清掃に移りました");const host=document.createElement("div");host.id="h2PdfStatus";host.innerHTML=st;document.querySelector(".wrap")?.prepend(host)}
  else{await r2("hq_work_mark_printed_v1500",{p_work_id:id});H2.busy=false}
 }catch(e){H2.busy=false;alert(h2Err(e))}
}
async function h2ToCleanNoLabel(id){
 if(!confirm("作業した人全員が清掃に移ります。よろしいですか？"))return;
 try{await r2("hq_work_to_clean_v1500",{p_work_id:id,p_printed:false});return hqWorkPage(id,"作業者全員が清掃に移りました")}catch(e){alert(h2Err(e))}
}
window.h2ToCleanNoLabel=h2ToCleanNoLabel;
async function h2ToClean(id,printed){
 if(!confirm("ラベルを印刷しないで、清掃に移ります。ラベルはあとで「もう一度印刷」から印刷できます。よろしいですか？"))return;
 try{await r2("hq_work_to_clean_v1500",{p_work_id:id,p_printed:!!printed});return hqWorkPage(id,"作業者全員が清掃に移りました")}catch(e){alert(h2Err(e))}
}
function h2DeleteWorkHtml(w){return `<details class="card"><summary><b>この記録を完全に削除する（本社社員・管理者）</b></summary><div class="small" style="margin-top:6px">試しに入力した作業などを、一覧からも完全に消します。作業時間の記録も一緒に消えます。確定して在庫を減らしていた場合は、在庫と下処理ロスを元に戻してから消します。印刷した仕掛品ラベルは捨ててください。</div><button class="btn red" style="width:100%;margin-top:8px" ${btnAttr("h2DeleteWork",[w.id,w.work_date||"",w.kind||"",w.raw_item_name||"",w.product_name||w.task_name||""])}>完全に削除する</button></details>`}
async function h2DeleteWork(id,date,kind,item,product){
 const info=`作業日：${date}\n種類：${kind}${item?`\n原料：${item}`:""}${product?`\n内容：${product}`:""}`;
 if(!confirm(`【完全に削除】\n${info}\n\nこの記録を完全に削除します。元に戻せません。よろしいですか？`))return;
 if(!confirm(`もう一度確認します。\n${info}\n\n本当に削除しますか？`))return;
 try{const r=await r2("hq_work_delete_v1500",{p_work_id:id});return hqPrepHome(r&&r.restored?"削除しました（在庫と下処理ロスを元に戻しました）":"削除しました")}catch(e){alert(h2Err(e))}
}
async function h2WorkCancel(id){
 const reason=prompt("取り消す理由を入れてください（例：間違えて開始）");if(reason==null)return;
 try{await r2("hq_work_cancel_v1500",{p_work_id:id,p_reason:reason});return hqPrepHome("作業を取り消しました")}catch(e){alert(h2Err(e))}
}
function toLocalInput(t){if(!t)return"";const d=new Date(t);const p=n=>String(n).padStart(2,"0");return `${d.getFullYear()}-${p(d.getMonth()+1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`}
async function h2FixMember(mid,start,end,name){
 const s=prompt(`${name}さんの開始（例：2026-10-25 09:05）`,toLocalInput(start).replace("T"," "));if(s==null)return;
 const e=prompt(`${name}さんの終了（空欄＝まだ作業中／「削除」と入れるとこの記録を消します）`,end?toLocalInput(end).replace("T"," "):"");if(e==null)return;
 try{
  if(e.trim()==="削除"){if(!confirm("この記録を消します。よろしいですか？"))return;await r2("hq_member_fix_v1500",{p_member_id:mid,p_start:null,p_end:null,p_delete:true})}
  else{const ps=new Date(s.trim().replace(" ","T")),pe=e.trim()?new Date(e.trim().replace(" ","T")):null;if(isNaN(ps)||(pe&&isNaN(pe)))return alert("日時の形が正しくありません（例：2026-10-25 09:05）");await r2("hq_member_fix_v1500",{p_member_id:mid,p_start:ps.toISOString(),p_end:pe?pe.toISOString():null,p_delete:false})}
  return hqWorkPage(currentArgs?.[0]||"", "直しました");
 }catch(err){alert(h2Err(err))}
}
async function h2AddMemberPage(workId){
 const staff=await h2Staff();
 const box=document.createElement("div");box.className="card";box.id="h2AddMem";
 box.innerHTML=`<b>読み忘れた人を追加</b><label class="label" style="margin-top:6px">人</label><select id="h2AmS" class="input">${staff.map(s=>`<option value="${esc(s.id)}">${esc(s.name)}（${esc(s.team)}）</option>`).join("")}</select><label class="label" style="margin-top:6px">作業か清掃か</label><select id="h2AmP" class="input"><option>作業</option><option>清掃</option></select><div class="row" style="margin-top:6px"><div><label class="label">開始</label><input id="h2AmA" type="datetime-local" class="input"></div><div><label class="label">終了</label><input id="h2AmB" type="datetime-local" class="input"></div></div><button class="btn green" style="width:100%;margin-top:8px" ${btnAttr("h2AddMemberSave",[workId])}>追加する</button>`;
 document.getElementById("h2AddMem")?.remove();document.querySelector(".wrap")?.appendChild(box);box.scrollIntoView({block:"center"});
}
async function h2AddMemberSave(workId){
 const a=h2Val("h2AmA"),b=h2Val("h2AmB");if(!a||!b)return alert("開始と終了を入れてください");
 try{await r2("hq_member_add_v1500",{p_work_id:workId,p_staff_id:h2Val("h2AmS"),p_phase:h2Val("h2AmP"),p_start:new Date(a).toISOString(),p_end:new Date(b).toISOString()});return hqWorkPage(workId,"追加しました")}catch(e){alert(h2Err(e))}
}
Object.assign(window,{h2DeleteWorkHtml,h2DeleteWork,hqPrepHome,hqPrepNew,h2NwAddLot,h2NwDelLot,h2NwAddStaff,h2NwDelStaff,h2NwSet,h2NwStart,hqOpScanPage,hqWorkPage,h2WorkEnd,h2CleanEnd,h2WorkLeave,h2WorkJoinOpen,h2JoinSelected,h2SaveInputs,h2PrintLabel,h2ToClean,h2WorkCancel,h2FixMember,h2AddMemberPage,h2AddMemberSave});
Object.assign(X,{labelPages,LABEL_CSS,workCard,liveData});
})();

/* ===== 下処理の確認・確定／下処理マスタ／スタッフQR／作業時間（本社社員・管理者） ===== */
(function(){
"use strict";
const X=window.__h2;const{H2,r2,sel2,num2,kg2,yen2,pct2,time2,dt2,md2,mins2,hm2,btnAttr,roleIs,h2CanBoss,h2CanMoney,h2CanReport,h2Month,h2MonthRange,h2MonthLabel,h2Err,h2Notice,h2Loading,h2Set,h2Val,h2Stage2,h2MakePdf,h2Qr,h2Staff,h2Teams,h2Places,h2Tasks,h2Masters,h2QrItems,h2Works,h2Members,h2Materials,h2Diff,h2Yield,h2UsedKg,h2Prices,h2PriceOf}=X;
const GROUPS=["","①下処理班","②下処理班","③人参班・ライン班ほか","④手切班","⑤機械班","⑥原料班"];

/* --- 下処理の確認（一覧） --- */
async function hqPrepCheckPage(from="",to="",only="未確定",msg=""){
 if(!h2CanBoss()&&!h2CanReport())return hqHome();
 to=to||hqToday();from=from||hqAddDays(to,-6);
 setScreen("hqPrepCheckPage",[from,to,only,msg]);
 const on=await h2Stage2(true);
 pageShell("下処理の確認","パートさんが入れた下処理を確認して確定します",`${okHtml(msg)}
 ${roleIs(["admin"])?`<div class="card" style="border:2px solid ${on?"#16a34a":"#d97706"}"><b>第2段階の在庫反映：${on?"オン（実用中）":"オフ（説明・練習の期間）"}</b><div class="small" style="margin-top:4px">${on?"下処理の確定で原料の在庫が減ります。使用出庫は使えません。":"下処理を確定しても原料の在庫は減りません（記録だけ）。使用出庫は今までどおり使えます。"}</div><button class="btn ${on?"btn2":"orange"}" style="width:100%;margin-top:8px" ${btnAttr("h2ToggleStage2",[!on])}>${on?"オフに戻す":"オンにする（実用開始）"}</button></div>`:(on?"":h2Notice("いまは説明・練習の期間です。下処理を確定しても、原料の在庫は減りません。"))}
 <button class="btn hqBtnPrep" style="width:100%" ${btnAttr("hqPrepHome",[])}>いま動いている作業（下処理入力）</button>
 <div class="card"><div class="row"><div><label class="label">から</label><input id="h2CkF" type="date" class="input" value="${esc(from)}"></div><div><label class="label">まで</label><input id="h2CkT" type="date" class="input" value="${esc(to)}"></div></div>
 <div class="h2Tabs" style="margin-top:8px">${["未確定","確定","取消","すべて"].map(k=>`<button class="btn ${only===k?"hqBtnPrepCheck":"btn2"}" ${btnAttr("h2CkFilter",[k])}>${k}</button>`).join("")}</div></div>
 <div id="h2CkList">${h2Loading()}</div>`);
 try{
  let q=`select=*&kind=eq.下処理&work_date=gte.${from}&work_date=lte.${to}&order=work_date.desc,started_at.desc&limit=500`;
  if(only==="未確定")q=`select=*&kind=eq.下処理&confirm_status=eq.未確定&status=neq.取消&order=work_date.asc,started_at.asc&limit=500`;
  else if(only!=="すべて")q+=`&confirm_status=eq.${encodeURIComponent(only)}`;
  const works=await h2Works(q);const ids=works.map(w=>w.id);const[mats,mem]=await Promise.all([h2Materials(ids),h2Members(ids)]);
  h2Set("h2CkList",works.length?works.map(w=>checkCard(w,mats.filter(m=>m.work_id===w.id),mem.filter(m=>m.work_id===w.id))).join(""):'<div class="notice">該当する下処理はありません。</div>');
 }catch(e){h2Set("h2CkList",`<div class="err">${esc(h2Err(e))}</div>`)}
}
function checkCard(w,mats,mem){
 const d=h2Diff(w,mats),u=h2UsedKg(mats),yr=h2Yield(w);
 const people=new Set(mem.filter(m=>m.phase==="作業").map(m=>m.staff_id)).size,min=mem.filter(m=>m.phase==="作業").reduce((s,m)=>s+mins2(m.start_at,m.end_at),0);
 const old=w.confirm_status==="未確定"&&w.work_date<hqToday();
 return `<div class="card h2Work s${esc(w.status)}" ${old?'style="border:2px solid #dc2626"':""}><div class="itemHead"><div><b style="font-size:18px">${esc(w.raw_item_name||"")} → ${esc(w.product_name||"")}</b><div class="small">${esc(w.work_date)} ${esc(w.place||"")} ／ ${esc(w.status)}${old?' <span class="h2Red">前の日から未確定</span>':""}</div></div><span class="badge ${w.confirm_status==="確定"?"normal":w.confirm_status==="取消"?"unset":"warn"}">${esc(w.confirm_status)}</span></div>
 <div class="hqLotMeta"><div><span>使用原料</span><b>${u.kg?kg2(u.kg)+"kg":"—"}${u.unknown?"＋量目不明":""}</b></div><div><span>出来高</span><b>${kg2(w.yield_kg)}kg</b></div><div><span>廃棄</span><b>${kg2(w.waste_kg)}kg</b></div><div><span>差</span><b class="${d&&Math.abs(d.rate)>=0.1?"h2Red":""}">${d?`${kg2(d.kg)}kg（${pct2(d.rate)}）`:"—"}</b></div><div><span>歩留まり</span><b>${pct2(yr)}</b></div><div><span>作業</span><b>${people}名 ${hm2(min)}</b></div></div>
 ${w.confirm_status==="確定"?`<div class="small">確定：${esc(w.confirmed_by_name||"")} ${dt2(w.confirmed_at)}${w.stock_applied?" ／ 在庫に反映済み":" ／ 在庫には反映していません（オフの期間）"}</div>`:""}
 <div class="row" style="margin-top:8px">${h2CanBoss()&&w.confirm_status!=="取消"&&w.status!=="作業中"?`<button class="btn hqBtnPrepCheck" ${btnAttr("hqPrepConfirmPage",[w.id])}>${w.confirm_status==="確定"?"修正・取消":"確認して確定"}</button>`:""}<button class="btn btn2" ${btnAttr("hqWorkPage",[w.id])}>作業の記録</button></div></div>`;
}
function h2CkFilter(k){return hqPrepCheckPage(h2Val("h2CkF"),h2Val("h2CkT"),k)}
async function h2ToggleStage2(on){
 const t=on?"第2段階の在庫反映を「オン」にします。\n\n・これから確定する下処理は、原料の在庫を減らします。\n・下処理への使用出庫は使えなくなります。\n・パートさんの画面から「使用出庫」が消えます。\n\n実用を始める日に押してください。よろしいですか？":"在庫反映を「オフ」に戻します。これから確定する下処理は在庫を減らしません。使用出庫が使えるようになります。よろしいですか？";
 if(!confirm(t))return;
 try{await r2("hq_set_setting_v1500",{p_key:"stage2_stock",p_value:!!on});await h2Stage2(true);return hqPrepCheckPage("","","未確定",on?"在庫反映をオンにしました":"在庫反映をオフにしました")}catch(e){alert(h2Err(e))}
}

/* --- 確認・確定（修正・取消） --- */
async function hqPrepConfirmPage(id,msg=""){
 if(!h2CanBoss())return hqHome();
 setScreen("hqPrepConfirmPage",[id,msg]);pageShell("下処理の確定","",h2Loading());
 let w,mats,mem;
 try{w=(await h2Works(`select=*&id=eq.${id}`))[0];if(!w)throw new Error("下処理が見つかりません");[mats,mem]=await Promise.all([h2Materials([id]),h2Members([id])])}catch(e){return pageShell("下処理の確定","エラー",`<div class="err">${esc(h2Err(e))}</div>`)}
 const on=await h2Stage2(true);const d=h2Diff(w,mats);
 let price=null;if(h2CanMoney()){try{const pm=await h2Prices(w.work_date,w.work_date,[w.raw_item_name]);price=h2PriceOf(pm,w.raw_item_name,w.work_date)}catch(e){}}
 const y=Number(w.yield_kg),ws=Number(w.waste_kg),cost=price!=null&&y>0?price*(y+ws)/y:null;
 pageShell("下処理の確定",`${esc(w.work_date)} ${esc(w.product_name||"")}`,`${okHtml(msg)}
 <div class="card"><b style="font-size:19px">${esc(w.raw_item_name||"")} → ${esc(w.product_name||"")}</b><div class="small">${esc(w.work_date)}（この日の数字として記録します）／ ${esc(w.place||"")} ／ 入力：${esc(w.inputs_saved_by_name||"未入力")}</div>
 <div class="small" style="margin-top:4px">${on?"確定すると、下の使用数だけ原料の在庫を減らします。":"いまは在庫反映がオフです。確定しても原料の在庫は減りません（記録だけ）。"}</div></div>
 <div class="card"><b>使用原料</b>${mats.map(m=>`<label class="label" style="margin-top:8px">${esc(m.lot_no)}（${m.unit==="kg"?"kg":"ケース"}${m.pack_kg?`・量目${hqQty(m.pack_kg)}kg`:"・量目不明"}）</label><input class="input h2CfQty" data-id="${esc(m.id)}" inputmode="decimal" value="${m.qty==null?"":hqQty(m.qty)}">`).join("")}
 <div class="row" style="margin-top:8px"><div><label class="label">廃棄（kg）</label><input id="h2CfW" class="input" inputmode="decimal" value="${w.waste_kg==null?"":hqQty(w.waste_kg)}"></div><div><label class="label">出来高（kg）</label><input id="h2CfY" class="input" inputmode="decimal" value="${w.yield_kg==null?"":hqQty(w.yield_kg)}"></div></div>
 <div class="hqLotMeta" style="margin-top:8px"><div><span>差（使用−出来高−廃棄）</span><b class="${d&&Math.abs(d.rate)>=0.1?"h2Red":""}">${d?`${kg2(d.kg)}kg（${pct2(d.rate)}）`:"—"}</b></div><div><span>歩留まり率</span><b>${pct2(h2Yield(w))}</b></div>${h2CanMoney()?`<div><span>単価（市場・週平均）</span><b>${price==null?"未計算":`${hqKg(price)}円/kg`}</b></div><div><span>歩留まり原価</span><b>${cost==null?"未計算":`${hqKg(Math.round(cost*10)/10)}円/kg`}</b></div>`:""}</div>
 ${d&&Math.abs(d.rate)>=0.1?'<div class="err" style="margin-top:8px">差が10%以上あります。数を確かめてください。</div>':""}
 ${w.confirm_status==="確定"?`<label class="label" style="margin-top:8px">修正の理由</label><input id="h2CfR" class="input" placeholder="例：出来高の入れ間違い">`:""}
 <button class="btn hqBtnConfirm" style="width:100%;margin-top:12px" ${btnAttr("h2ConfirmPrep",[w.id,w.confirm_status==="確定"])}>${w.confirm_status==="確定"?"直して確定し直す":"この内容で確定する"}</button>
 ${w.confirm_status==="確定"?'<div class="small" style="margin-top:4px">品名・日付は変わらないので、ラベルの印刷し直しは不要です。</div>':""}</div>
 ${H2_LABEL_ON?"":"<!--"}<div class="card"><b>仕掛品ラベル</b><div class="small">${w.label_printed_at?`印刷 ${dt2(w.label_printed_at)}（${w.label_print_count}回）`:"まだ印刷していません"}</div><label class="label" style="margin-top:6px">枚数</label><input id="h2LabelN" class="input" inputmode="numeric" value="8"><button class="btn hqBtnPrint" style="width:100%;margin-top:8px" ${btnAttr("h2PrintLabel",[w.id,false])}>ラベルを印刷する</button></div>${H2_LABEL_ON?"":"-->"}
 ${w.history?.length?`<div class="card"><b>確定・修正・取消の記録</b>${w.history.map(h=>`<div class="small" style="padding:4px 0;border-top:1px solid #e2e8f0">${dt2(h.at)} ${esc(h.by||"")}：${esc(h.action||"")}${h.reason?`（${esc(h.reason)}）`:""}${h.stock===true?" ／ 在庫に反映":h.stock===false?" ／ 在庫には反映なし":""}</div>`).join("")}</div>`:""}
 <details class="card"><summary><b>この下処理を取り消す</b></summary><div class="small" style="margin-top:6px">確定済みなら、減らした原料の在庫と下処理ロスを元に戻します。印刷したラベルは使わないでください。</div><input id="h2CxR" class="input" style="margin-top:6px" placeholder="取消の理由（必須）"><button class="btn red" style="width:100%;margin-top:8px" ${btnAttr("h2CancelPrep",[w.id])}>取り消す</button></details>
 ${window.h2DeleteWorkHtml(w)}
 <button class="btn btn2" style="width:100%" ${btnAttr("hqWorkPage",[w.id])}>作業時間の記録を見る・直す</button>`);
}
async function h2ConfirmPrep(id,again){
 if(H2.busy)return;const mats=[];let bad=false;
 document.querySelectorAll(".h2CfQty").forEach(el=>{const v=num2(el.value);if(!Number.isFinite(v)||v<0)bad=true;mats.push({id:el.dataset.id,qty:v})});
 const ws=num2(h2Val("h2CfW")),y=num2(h2Val("h2CfY"));
 if(bad)return alert("使用原料の数を入れてください");if(!Number.isFinite(ws)||ws<0||!Number.isFinite(y)||y<0)return alert("廃棄と出来高を入れてください");
 const reason=h2Val("h2CfR");if(again&&!reason.trim())return alert("修正の理由を入れてください");
 if(!confirm(again?"直した内容で確定し直します。よろしいですか？":"この内容で確定します。よろしいですか？"))return;
 H2.busy=true;
 try{const r=await r2("hq_prep_confirm_v1500",{p_work_id:id,p_materials:mats,p_waste_kg:ws,p_yield_kg:y,p_reason:reason||null});H2.busy=false;return hqPrepConfirmPage(id,r?.stock_applied?"確定しました（原料の在庫を減らしました）":"確定しました（在庫反映オフのため、在庫はそのままです）")}catch(e){H2.busy=false;alert(h2Err(e))}
}
async function h2CancelPrep(id){
 const r=h2Val("h2CxR");if(!r.trim())return alert("取消の理由を入れてください");if(!confirm("この下処理を取り消します。よろしいですか？"))return;
 try{await r2("hq_prep_cancel_v1500",{p_work_id:id,p_reason:r});return hqPrepCheckPage("","","取消","取り消しました")}catch(e){alert(h2Err(e))}
}

/* --- 下処理マスタ --- */
async function hqPrepMasterPage(msg=""){
 if(!h2CanBoss())return hqHome();setScreen("hqPrepMasterPage",[msg]);pageShell("下処理マスタ","仕掛品の登録（原料・名前・初期入れ数kg・使用期限）",h2Loading());
 let ms=[],items=[];try{[ms,items]=await Promise.all([h2Masters(true),h2PrepItemNames()])}catch(e){return pageShell("下処理マスタ","エラー",`<div class="err">${esc(h2Err(e))}</div>`)}
 const opt=items.map(n=>`<option value="${esc(n)}"></option>`).join("");
 const groups={};ms.forEach(m=>(groups[m.item_name]=groups[m.item_name]||[]).push(m));
 pageShell("下処理マスタ","仕掛品の登録（原料・名前・初期入れ数kg・使用期限）",`${okHtml(msg)}
 <div class="card"><b>仕掛品を追加</b><label class="label" style="margin-top:6px">原料の品目</label><input id="h2MsI" class="input" list="h2MsIList" autocomplete="off" placeholder="品目名を入れると候補が出ます"><datalist id="h2MsIList">${opt}</datalist><div class="small">候補は、本社の品目・在庫入力の原料・本社に届いた原料・石岡の品目・市場価格のある品目です。候補にない名前もそのまま入れられます。</div>
 <label class="label" style="margin-top:6px">仕掛品の名前</label><input id="h2MsN" class="input" placeholder="例：千切り用カット">
 <div class="row" style="margin-top:6px"><div><label class="label">初期入れ数kg（必須）</label><input id="h2MsK" class="input" inputmode="decimal" placeholder="例：5"></div><div><label class="label">使用期限（日数）</label><input id="h2MsD" class="input" inputmode="numeric" value="2"></div></div>
 <div class="small">1つの原料に、いくつでも登録できます。使用期限は「下処理日＋日数」でラベルに印字します。</div>
 <button class="btn hqBtnMaster" style="width:100%;margin-top:8px" ${btnAttr("h2SaveMaster",[""])}>追加する</button></div>
 ${Object.keys(groups).sort().map(k=>`<div class="card"><b>${esc(k)}</b>${groups[k].map(m=>`<div class="itemHead" style="padding:6px 0;border-top:1px solid #e2e8f0"><div><b>${esc(m.name)}</b><div class="small">初期入れ数 ${hqKg(m.default_pack_kg)}kg ／ 使用期限 ${m.expiry_days}日${m.active?"":" ／ 使わない"}</div></div><div style="display:flex;gap:6px"><button class="btn btn2" ${btnAttr("h2EditMaster",[m.id])}>直す</button><button class="btn ${m.active?"btn2":"green"}" ${btnAttr("h2ToggleMaster",[m.id])}>${m.active?"使わない":"使う"}</button></div></div>`).join("")}</div>`).join("")||'<div class="notice">まだ登録がありません。</div>'}`);
 X.masterCache=ms;
}
async function h2PrepItemNames(){
 const names=new Set();const add=n=>{n=String(n||"").trim();if(n)names.add(n)};
 const jobs=[h2QrItems().then(r=>r.forEach(x=>add(x.name))),hqNormalItems().then(r=>r.forEach(x=>add(x.name))),hqLots("select=item_name&limit=5000").then(r=>r.forEach(x=>add(x.item_name)))];
 if(h2CanMoney()){const to=hqToday();jobs.push(r2("hq_price_table_v1500",{p_from:hqAddDays(to,-56),p_to:to,p_items:null}).then(r=>(r||[]).forEach(x=>{if(x.price!=null)add(x.item_name)})))}
 await Promise.all(jobs.map(j=>j.catch(()=>{})));
 (db.items||[]).forEach(it=>{if(it&&it.deleted!==true&&it.active!==false)add(it.name)});
 return [...names].sort((a,b)=>a.localeCompare(b,"ja"));
}
async function h2SaveMaster(id,data){
 const d=data||{item:h2Val("h2MsI").trim(),name:h2Val("h2MsN").trim(),kg:num2(h2Val("h2MsK")),days:Math.round(num2(h2Val("h2MsD"))),active:true};
 if(!d.item)return alert("原料の品目を選んでください");if(!d.name)return alert("仕掛品の名前を入れてください");if(!(d.kg>0))return alert("初期入れ数kgを入れてください");if(!(d.days>=0))return alert("使用期限の日数を入れてください");
 try{await r2("hq_save_prep_master_v1500",{p_id:id||null,p_item_name:d.item,p_name:d.name,p_pack_kg:d.kg,p_expiry_days:d.days,p_active:d.active});return hqPrepMasterPage(`${d.name}を保存しました`)}catch(e){alert(h2Err(e))}
}
async function h2EditMaster(id){
 const m=(X.masterCache||[]).find(x=>x.id===id);if(!m)return;
 const name=prompt("仕掛品の名前",m.name);if(name==null)return;const kg=prompt("初期入れ数kg",String(m.default_pack_kg));if(kg==null)return;const days=prompt("使用期限（日数）",String(m.expiry_days));if(days==null)return;
 return h2SaveMaster(id,{item:m.item_name,name:name.trim(),kg:num2(kg),days:Math.round(num2(days)),active:m.active});
}
function h2ToggleMaster(id){const m=(X.masterCache||[]).find(x=>x.id===id);if(!m)return;return h2SaveMaster(id,{item:m.item_name,name:m.name,kg:Number(m.default_pack_kg),days:m.expiry_days,active:!m.active})}

/* --- スタッフQR（登録・印刷・作業名・作業場所） --- */
function staffTabs(cur){const t=(k,act,l)=>`<button class="btn ${cur===k?"hqBtnStaff":"btn2"}" ${btnAttr(act,[])}>${l}</button>`;return `<div class="card h2Tabs">${t("reg","hqStaffPage","スタッフ登録")}${t("print","hqStaffPrintPage","QRの印刷")}${t("tasks","hqTaskPlacePage","作業名・作業場所")}${t("time","hqWorkTimePage","作業時間")}${t("cmp","hqWorkComparePage","個人の比較")}</div>`}
async function hqStaffPage(msg=""){
 if(!h2CanBoss())return hqHome();setScreen("hqStaffPage",[msg]);pageShell("スタッフQR","スタッフ登録",h2Loading());
 let staff=[],teams=[];try{[staff,teams]=await Promise.all([h2Staff(),h2Teams()])}catch(e){return pageShell("スタッフQR","エラー",`<div class="err">${esc(h2Err(e))}</div><div class="notice">019のSQLが未実行の可能性があります。</div>`)}
 X.staffCache=staff;X.teamCache=teams;
 pageShell("スタッフQR","スタッフ登録（入社・退職・グループの変更）",`${okHtml(msg)}${staffTabs("reg")}
 <div class="card"><b>入社したとき：スタッフを登録</b><label class="label" style="margin-top:6px">班名</label><select id="h2StT" class="input" ${seikaEventAttrs("change","h2TeamChanged",[{__seikaValue:true}])}><option value="">選んでください</option>${teams.map(t=>`<option value="${esc(t.name)}" data-g="${t.default_group}">${esc(t.name)}</option>`).join("")}<option value="__new">＋ 新しい班名を追加</option></select>
 <input id="h2StTN" class="input" style="margin-top:6px;display:none" placeholder="新しい班名">
 <label class="label" style="margin-top:6px">名前</label><input id="h2StN" class="input" placeholder="例：山田 花子">
 <label class="label" style="margin-top:6px">印刷グループ（一覧ボード）</label><select id="h2StG" class="input">${[1,2,3,4,5,6].map(g=>`<option value="${g}">${GROUPS[g]}</option>`).join("")}</select>
 <div class="small">班を選ぶと、ふだんのグループが自動で選ばれます。登録するとスタッフQRができます。</div>
 <button class="btn hqBtnStaff" style="width:100%;margin-top:8px" ${btnAttr("h2SaveStaff",[""])}>登録する</button></div>
 ${[1,2,3,4,5,6].map(g=>{const list=staff.filter(s=>s.print_group===g);return `<details class="card" ${list.length&&g<=2?"open":""}><summary><b>${GROUPS[g]}（${list.length}名）</b></summary>${list.map(s=>`<div class="itemHead" style="padding:6px 0;border-top:1px solid #e2e8f0"><div><b>${esc(s.name)}</b><div class="small">${esc(s.team)}</div></div><div style="display:flex;gap:6px"><button class="btn btn2" ${btnAttr("h2EditStaff",[s.id])}>変更</button><button class="btn red" ${btnAttr("h2DeleteStaff",[s.id])}>削除</button></div></div>`).join("")||'<div class="small">いません</div>'}</details>`}).join("")}
 <div class="card small">退職したときは「削除」を押します。一覧ボードと読み取りの対象から消えますが、過去の作業時間の記録は名前つきで残ります。</div>`);
}
function h2TeamChanged(v){const n=document.getElementById("h2StTN");if(n)n.style.display=v==="__new"?"block":"none";const t=(X.teamCache||[]).find(x=>x.name===v);if(t){const g=document.getElementById("h2StG");if(g)g.value=String(t.default_group)}}
async function h2SaveStaff(id,data){
 let d=data;
 if(!d){let team=h2Val("h2StT");if(team==="__new")team=h2Val("h2StTN").trim();d={team,name:h2Val("h2StN").trim(),group:Number(h2Val("h2StG"))}}
 if(!d.team)return alert("班名を選んでください");if(!d.name)return alert("名前を入れてください");
 try{await r2("hq_save_staff_v1500",{p_id:id||null,p_team:d.team,p_name:d.name,p_group:d.group});return hqStaffPage(`${d.name}さんを${id?"変更":"登録"}しました`)}catch(e){alert(h2Err(e))}
}
function h2EditStaff(id){
 const s=(X.staffCache||[]).find(x=>x.id===id);if(!s)return;
 const box=document.createElement("div");box.className="card";box.id="h2StEdit";
 box.innerHTML=`<b>${esc(s.name)}さんを変更</b><label class="label" style="margin-top:6px">班名</label><select id="h2SeT" class="input">${(X.teamCache||[]).map(t=>`<option ${t.name===s.team?"selected":""}>${esc(t.name)}</option>`).join("")}</select><label class="label" style="margin-top:6px">名前</label><input id="h2SeN" class="input" value="${esc(s.name)}"><label class="label" style="margin-top:6px">印刷グループ</label><select id="h2SeG" class="input">${[1,2,3,4,5,6].map(g=>`<option value="${g}" ${g===s.print_group?"selected":""}>${GROUPS[g]}</option>`).join("")}</select><div class="small">QRはそのまま使えます（印刷し直す必要はありません。グループを変えたときは一覧ボードを印刷し直してください）。</div><button class="btn hqBtnStaff" style="width:100%;margin-top:8px" ${btnAttr("h2SaveStaffEdit",[id])}>変更する</button>`;
 document.getElementById("h2StEdit")?.remove();document.querySelector(".wrap")?.prepend(box);box.scrollIntoView({block:"start"});
}
function h2SaveStaffEdit(id){return h2SaveStaff(id,{team:h2Val("h2SeT"),name:h2Val("h2SeN").trim(),group:Number(h2Val("h2SeG"))})}
async function h2DeleteStaff(id){
 const s=(X.staffCache||[]).find(x=>x.id===id);if(!s)return;
 if(!confirm(`${s.name}さんを削除します（退職など）。\n過去の作業時間の記録は残ります。よろしいですか？`))return;
 try{await r2("hq_delete_staff_v1500",{p_id:id});return hqStaffPage(`${s.name}さんを削除しました`)}catch(e){alert(h2Err(e))}
}
const BOARD_CSS=`.h2PdfRoot .bh{display:flex;justify-content:space-between;align-items:flex-end;border-bottom:3px solid #000;padding-bottom:8px;margin-bottom:6px}.h2PdfRoot .bh h1{font-size:30px;margin:0}.h2PdfRoot .bs{font-size:15px;margin:4px 0 12px}.h2PdfRoot .grid{display:grid;grid-template-columns:repeat(4,1fr);gap:10px}.h2PdfRoot .c{border:2px solid #000;border-radius:10px;padding:8px 6px;text-align:center;height:196px}.h2PdfRoot .c img{width:132px;height:132px}.h2PdfRoot .c .n{font-size:20px;font-weight:900;line-height:1.15;margin-top:2px}.h2PdfRoot .c .t{font-size:13px}.h2PdfRoot .ft{position:absolute;left:36px;right:36px;bottom:26px;font-size:12px;border-top:1px solid #000;padding-top:4px}.h2PdfRoot .ops{display:grid;grid-template-columns:1fr 1fr;gap:24px;margin-top:20px}.h2PdfRoot .op{border:4px solid #000;border-radius:16px;text-align:center;padding:18px 10px;height:440px}.h2PdfRoot .op img{width:290px;height:290px}.h2PdfRoot .op .n{font-size:44px;font-weight:900}.h2PdfRoot .op .s{font-size:16px}`;
async function hqStaffPrintPage(msg=""){
 if(!h2CanBoss())return hqHome();setScreen("hqStaffPrintPage",[msg]);
 let staff=[];try{staff=await h2Staff()}catch(e){}
 pageShell("スタッフQR","QRの印刷（A4縦）",`${okHtml(msg)}${staffTabs("print")}
 <div class="card"><b>スタッフQR 一覧ボード（グループごとに1枚）</b><div class="small">作業する人は、自分の名前のQRを読み取ります。QRの中身は名前ではなく番号です。</div>
 ${[1,2,3,4,5,6].map(g=>`<button class="btn hqBtnStaff" style="width:100%;margin-top:8px" ${btnAttr("h2PrintBoard",[g])}>${GROUPS[g]}（${staff.filter(s=>s.print_group===g).length}名）を印刷</button>`).join("")}</div>
 <div class="card"><b>操作用QR（作業開始・作業終了・清掃・清掃終了）</b><div class="small">画面のボタンでも同じ操作ができます。清掃のQRは、清掃だけ行うとき（大掃除など）にも使います。</div><button class="btn hqBtnStaff" style="width:100%;margin-top:8px" ${btnAttr("h2PrintOps",[])}>操作用QRを印刷</button></div>`);
}
async function h2PrintBoard(g){
 const staff=(await h2Staff()).filter(s=>s.print_group===g);if(!staff.length)return alert("このグループには登録がありません");
 const today=new Date();const ds=`${today.getFullYear()}年${today.getMonth()+1}月${today.getDate()}日`;
 const pages=[];for(let i=0;i<staff.length;i+=20){const part=staff.slice(i,i+20);
  pages.push(`<div class="bh"><h1>スタッフQR 一覧ボード　${esc(GROUPS[g])}</h1><div style="font-size:14px;white-space:nowrap">印刷日：${ds}　${staff.length}名${staff.length>20?`（${Math.floor(i/20)+1}枚目）`:""}</div></div><div class="bs">作業する人は、自分の名前のQRを読み取ってください。</div><div class="grid">${part.map(s=>`<div class="c"><img src="${h2Qr(s.qr_key,6)}"><div class="n">${esc(s.name)}</div><div class="t">${esc(String(s.team||"").replace(/[①-⑳]$/,""))}</div></div>`).join("")}</div><div class="ft">SEIKA＋ 本社　QRの中身は名前ではなく番号です。退職した人は登録画面で削除し、このボードを印刷し直してください。</div>`)}
 return h2MakePdf(pages,BOARD_CSS,`スタッフQR_${GROUPS[g]}.pdf`);
}
async function h2PrintOps(){
 const ops=[["HQOP-START","作業開始","作業する人のQRを読んだあとに読みます"],["HQOP-END","作業終了","作業が終わったら読みます"],["HQOP-CLEAN","清掃","清掃だけ行うときにも使えます"],["HQOP-CLEANEND","清掃終了","清掃が終わったら読みます"]];
 return h2MakePdf([`<div class="bh"><h1>操作用QR</h1><div style="font-size:14px">SEIKA＋ 本社</div></div><div class="bs">画面のボタンでも同じ操作ができます。</div><div class="ops">${ops.map(o=>`<div class="op"><img src="${h2Qr(o[0],8)}"><div class="n">${o[1]}</div><div class="s">${o[2]}</div></div>`).join("")}</div>`],BOARD_CSS,"操作用QR.pdf");
}
async function hqTaskPlacePage(msg=""){
 if(!h2CanBoss())return hqHome();setScreen("hqTaskPlacePage",[msg]);
 let tasks=[],places=[];try{[tasks,places]=await Promise.all([h2Tasks(true),h2Places(true)])}catch(e){return pageShell("スタッフQR","エラー",`<div class="err">${esc(h2Err(e))}</div>`)}
 const row=(name,active,act,fixed)=>`<div class="itemHead" style="padding:6px 0;border-top:1px solid #e2e8f0"><b>${esc(name)}${active?"":' <span class="badge unset">非表示</span>'}</b>${fixed?'<span class="small">（変えられません）</span>':`<div style="display:flex;gap:6px"><button class="btn ${active?"btn2":"green"}" ${btnAttr(act,[name,!active])}>${active?"非表示にする":"表示する"}</button><button class="btn red" ${btnAttr(act==="h2SaveTask"?"h2DeleteTask":"h2DeletePlace",[name])}>削除</button></div>`}</div>`;
 pageShell("スタッフQR","作業名・作業場所",`${okHtml(msg)}${staffTabs("tasks")}
 <div class="card"><b>作業名（下処理以外の作業）</b><div class="small">下処理・清掃のほかに、作業時間を記録したい作業を追加します（例：袋詰め、仕分け）。</div><div class="row" style="margin-top:6px"><input id="h2TkN" class="input" placeholder="例：袋詰め"><button class="btn hqBtnStaff" ${btnAttr("h2SaveTask",["",true])}>追加</button></div>${tasks.map(t=>row(t.name,t.active,"h2SaveTask",t.kind!=="作業")).join("")}</div>
 <div class="card"><b>作業場所</b><div class="small">作業を始めるときに選ぶ場所です。</div><div class="row" style="margin-top:6px"><input id="h2PlN" class="input" placeholder="例：下処理室③"><button class="btn hqBtnStaff" ${btnAttr("h2SavePlace",["",true])}>追加</button></div>${places.map(p=>row(p.name,p.active,"h2SavePlace",false)).join("")}</div>`);
}
async function h2SaveTask(name,active){name=name||h2Val("h2TkN").trim();if(!name)return alert("作業名を入れてください");try{await r2("hq_save_task_v1500",{p_name:name,p_active:active});return hqTaskPlacePage("保存しました")}catch(e){alert(h2Err(e))}}
async function h2DeleteTask(name){if(!confirm(`作業名「${name}」を削除します。\n\n作業を始める画面に出なくなります。これまでの作業時間の記録はそのまま残ります。`))return;try{await r2("hq_delete_task_v1700",{p_name:name});return hqTaskPlacePage(`「${name}」を削除しました`)}catch(e){alert(h2Err(e))}}
async function h2DeletePlace(name){if(!confirm(`作業場所「${name}」を削除します。\n\n作業を始める画面に出なくなります。これまでの作業の記録の場所名はそのまま残ります。`))return;try{await r2("hq_delete_place_v1700",{p_name:name});return hqTaskPlacePage(`「${name}」を削除しました`)}catch(e){alert(h2Err(e))}}
async function h2SavePlace(name,active){name=name||h2Val("h2PlN").trim();if(!name)return alert("作業場所を入れてください");try{await r2("hq_save_place_v1500",{p_name:name,p_active:active});return hqTaskPlacePage("保存しました")}catch(e){alert(h2Err(e))}}

/* --- 作業時間（人×時間）と作業人数 --- */
async function workTimeData(month){
 const{from,to}=h2MonthRange(month);
 const works=await h2Works(`select=*&work_date=gte.${from}&work_date=lte.${to}&status=neq.取消&order=work_date.asc&limit=5000`);
 const mem=await h2Members(works.map(w=>w.id));
 return{works,mem};
}
function workTimeSummary(works,mem){
 const wm=new Map(works.map(w=>[w.id,w]));const per=new Map(),perDay=new Map(),perTask=new Map();
 for(const m of mem){const w=wm.get(m.work_id);if(!w)continue;const min=mins2(m.start_at,m.end_at);
  const p=per.get(m.staff_id)||{name:m.staff_name,team:m.team||"",work:0,clean:0,days:new Set()};if(m.phase==="清掃")p.clean+=min;else p.work+=min;p.days.add(w.work_date);per.set(m.staff_id,p);
  const d=perDay.get(w.work_date)||{people:new Set(),min:0};d.people.add(m.staff_id);d.min+=min;perDay.set(w.work_date,d);
  const tk=m.phase==="清掃"?"清掃":w.kind==="下処理"?`下処理（${w.product_name||""}）`:w.task_name;const t=perTask.get(tk)||{min:0,people:new Set(),count:new Set()};t.min+=min;t.people.add(m.staff_id);t.count.add(w.id);perTask.set(tk,t);
 }
 return{per,perDay,perTask};
}
async function hqWorkTimePage(month=""){
 if(!h2CanBoss()&&!h2CanReport())return hqHome();month=h2Month(month);setScreen("hqWorkTimePage",[month]);
 pageShell("作業時間","人×時間・作業人数（月ごと）",`${h2CanBoss()?staffTabs("time"):""}<div class="card"><label class="label">月</label><input type="month" class="input" value="${esc(month)}" ${seikaEventAttrs("change","hqWorkTimePage",[{__seikaValue:true}])}><button class="btn hqBtnExcelOut" style="width:100%;margin-top:8px" ${btnAttr("h2ExcelWorkTime",[month])}>この月の作業時間をExcelにする</button></div><div id="h2WtBody">${h2Loading()}</div>`);
 try{
  const{works,mem}=await workTimeData(month);const{per,perDay,perTask}=workTimeSummary(works,mem);
  const open=mem.filter(m=>!m.end_at).length;
  h2Set("h2WtBody",`${open?h2Notice(`終わっていない記録が ${open}件あります（作業中、または読み忘れ）。時間は「いま」までで計算しています。`):""}
  <div class="card" style="overflow-x:auto"><b>人ごと</b><table class="h2Tbl"><tr><th>名前</th><th>班</th><th>日数</th><th>作業</th><th>清掃</th><th>合計</th></tr>${[...per.values()].sort((a,b)=>a.team.localeCompare(b.team,"ja")||a.name.localeCompare(b.name,"ja")).map(p=>`<tr><td>${esc(p.name)}</td><td>${esc(p.team)}</td><td>${p.days.size}</td><td>${hm2(p.work)}</td><td>${hm2(p.clean)}</td><td><b>${hm2(p.work+p.clean)}</b></td></tr>`).join("")||'<tr><td colspan="6">記録がありません</td></tr>'}</table></div>
  <div class="card" style="overflow-x:auto"><b>日ごとの作業人数</b><table class="h2Tbl"><tr><th>日付</th><th>人数</th><th>人×時間</th></tr>${[...perDay.entries()].sort().map(([d,v])=>`<tr><td>${esc(d)}</td><td>${v.people.size}名</td><td>${hm2(v.min)}</td></tr>`).join("")}</table></div>
  <div class="card" style="overflow-x:auto"><b>作業ごと</b><table class="h2Tbl"><tr><th>作業</th><th>回数</th><th>人数（のべ）</th><th>人×時間</th></tr>${[...perTask.entries()].sort((a,b)=>b[1].min-a[1].min).map(([k,v])=>`<tr><td>${esc(k)}</td><td>${v.count.size}</td><td>${v.people.size}名</td><td>${hm2(v.min)}</td></tr>`).join("")}</table></div>
  <div class="card small">読み忘れは、作業の画面の「作業時間の記録」で本社社員が直せます。時給はアプリに持ちません。荷受けは対象外です。</div>`);
 }catch(e){h2Set("h2WtBody",`<div class="err">${esc(h2Err(e))}</div>`)}
}
async function h2ExcelWorkTime(month){return X.excelOut("worktime",month)}
async function workRangeData(from,to){
 const works=await h2Works(`select=*&work_date=gte.${from}&work_date=lte.${to}&status=neq.取消&order=work_date.asc&limit=5000`);
 const mem=await h2Members(works.map(w=>w.id));
 return{works,mem};
}
function workCompare(works,mem){
 const wm=new Map(works.map(w=>[w.id,w])),per=new Map(),prod=new Map(),workMin=new Map();
 for(const m of mem){if(m.phase==="清掃")continue;workMin.set(m.work_id,(workMin.get(m.work_id)||0)+mins2(m.start_at,m.end_at))}
 for(const m of mem){const w=wm.get(m.work_id);if(!w||m.phase==="清掃")continue;const min=mins2(m.start_at,m.end_at);
  const p=per.get(m.staff_id)||{name:m.staff_name,team:m.team||"",prep:0,other:0,days:new Set()};if(w.kind==="下処理")p.prep+=min;else p.other+=min;p.days.add(w.work_date);per.set(m.staff_id,p);
  if(w.kind!=="下処理"||w.confirm_status!=="確定"||!(Number(w.yield_kg)>0))continue;
  const tot=workMin.get(w.id)||0;if(!tot)continue;const name=w.product_name||"（名前なし）";
  const g=prod.get(name)||new Map();const q=g.get(m.staff_id)||{name:m.staff_name,team:m.team||"",min:0,kg:0,works:new Set()};
  q.min+=min;q.kg+=Number(w.yield_kg)*min/tot;q.works.add(w.id);g.set(m.staff_id,q);prod.set(name,g);
 }
 return{per,prod};
}
const kgh=q=>q.min>0?Math.round(q.kg/(q.min/60)*10)/10:0;
async function hqWorkComparePage(from="",to=""){
 if(!h2CanBoss())return hqHome();
 const today=ymdKey(new Date());from=from||today.slice(0,8)+"01";to=to||today;if(from>to){const t=from;from=to;to=t}
 setScreen("hqWorkComparePage",[from,to]);
 pageShell("作業時間","個人の比較（本社社員・管理者）",`${staffTabs("cmp")}<div class="card"><div class="row"><div><label class="label">開始日</label><input type="date" class="input" value="${esc(from)}" ${seikaEventAttrs("change","h2CmpFrom",[{__seikaValue:true},to])}></div><div><label class="label">終了日</label><input type="date" class="input" value="${esc(to)}" ${seikaEventAttrs("change","h2CmpTo",[from,{__seikaValue:true}])}></div></div><div class="small">清掃の時間は入れずに比べます。</div></div><div id="h2CmpBody">${h2Loading()}</div>`);
 try{
  const{works,mem}=await workRangeData(from,to);const{per,prod}=workCompare(works,mem);
  const ps=[...per.values()].sort((a,b)=>(b.prep+b.other)-(a.prep+a.other));
  const max=Math.max(1,...ps.map(p=>p.prep+p.other));
  const bar=(v,c)=>`<div style="height:8px;background:#e2e8f0;border-radius:4px;overflow:hidden;margin-top:2px"><div style="height:8px;width:${Math.round(v/max*100)}%;background:${c}"></div></div>`;
  h2Set("h2CmpBody",`<div class="card" style="overflow-x:auto"><b>人ごとの作業時間</b><table class="h2Tbl"><tr><th>名前</th><th>班</th><th>日数</th><th>下処理</th><th>ほかの作業</th><th>合計</th><th>1日平均</th></tr>${ps.map(p=>{const t=p.prep+p.other;return `<tr><td>${esc(p.name)}${bar(t,"#2563eb")}</td><td>${esc(p.team)}</td><td>${p.days.size}</td><td>${hm2(p.prep)}</td><td>${hm2(p.other)}</td><td><b>${hm2(t)}</b></td><td>${hm2(Math.round(t/Math.max(1,p.days.size)))}</td></tr>`}).join("")||'<tr><td colspan="7">記録がありません</td></tr>'}</table></div>
  <div class="card"><b>下処理ごとの速さ（1時間あたりの出来高）</b><div class="small">確定した下処理だけで計算します。何人かで作業したときは、出来高を一人ひとりの作業時間の割合で分けています。回数が少ない人の数字は参考にしてください。</div></div>
  ${[...prod.entries()].sort((a,b)=>a[0].localeCompare(b[0],"ja")).map(([name,g])=>{const qs=[...g.values()].sort((a,b)=>kgh(b)-kgh(a));const top=Math.max(0.1,...qs.map(kgh));return `<div class="card" style="overflow-x:auto"><b>${esc(name)}</b><table class="h2Tbl"><tr><th>名前</th><th>回数</th><th>作業時間</th><th>出来高（分けた分）</th><th>1時間あたり</th></tr>${qs.map(q=>`<tr><td>${esc(q.name)}<div class="small">${esc(q.team)}</div></td><td>${q.works.size}</td><td>${hm2(q.min)}</td><td>${(Math.round(q.kg*10)/10).toLocaleString()}kg</td><td><b>${kgh(q).toLocaleString()}kg</b><div style="height:8px;background:#e2e8f0;border-radius:4px;overflow:hidden;margin-top:2px"><div style="height:8px;width:${Math.round(kgh(q)/top*100)}%;background:#16a34a"></div></div></td></tr>`).join("")}</table></div>`}).join("")||'<div class="card small">この期間に確定した下処理がありません。</div>'}`);
 }catch(e){h2Set("h2CmpBody",`<div class="err">${esc(h2Err(e))}</div>`)}
}
function h2CmpFrom(v,to){return hqWorkComparePage(v,to)}
function h2CmpTo(from,v){return hqWorkComparePage(from,v)}
window.h2MakePdfC69=h2MakePdf;window.h2QrC69=h2Qr;Object.assign(window,{hqPrepCheckPage,h2CkFilter,h2ToggleStage2,hqPrepConfirmPage,h2ConfirmPrep,h2CancelPrep,hqPrepMasterPage,h2SaveMaster,h2EditMaster,h2ToggleMaster,hqStaffPage,h2TeamChanged,h2SaveStaff,h2EditStaff,h2SaveStaffEdit,h2DeleteStaff,hqStaffPrintPage,h2PrintBoard,h2PrintOps,hqTaskPlacePage,h2SaveTask,h2SavePlace,h2DeleteTask,h2DeletePlace,hqWorkTimePage,h2ExcelWorkTime,hqWorkComparePage,h2CmpFrom,h2CmpTo});
Object.assign(X,{workTimeData,workTimeSummary,workCompare,kgh,GROUPS});
})();

/* ===== 在庫入力（原料・仕掛品）／在庫表／使用数量／棚卸し ===== */
(function(){
"use strict";
const X=window.__h2;const{H2,r2,sel2,num2,kg2,btnAttr,roleIs,h2CanBoss,h2CanCount,h2CanReport,h2Month,h2MonthRange,h2MonthLabel,h2Err,h2Notice,h2Loading,h2Set,h2Val,h2MakePdf,h2Masters}=X;

/* --- 在庫入力 --- */
let SC=null;
function scLines(c,defKg){const ls=(c?.lines||[]).map(l=>({pack:String(l.pack_kg??""),cases:String(l.cases??"")}));return ls.length?ls:[{pack:defKg==null?"":String(defKg),cases:""}]}
async function h2StockInputPage(date="",msg="",tab=""){
 date=date||hqToday();if(date>hqToday())date=hqToday();
 if(!SC||SC.date!==date)SC={date,tab:tab||SC?.tab||"原料",rows:null};if(tab)SC.tab=tab;
 setScreen("hqNormalPage",[date,msg]);
 const can=hqCanNormal()&&!hqViewOnly();
 pageShell("在庫入力","原料と仕掛品の在庫（入れ数kg × ケース数）",`${okHtml(msg)}<div class="card"><label class="label">日付</label><input type="date" class="input" max="${hqToday()}" value="${esc(date)}" ${seikaEventAttrs("change","hqNormalPage",[{__seikaValue:true}])}>
 <div class="h2Tabs" style="margin-top:8px"><button class="btn ${SC.tab==="原料"?"hqBtnNormal":"btn2"}" ${btnAttr("h2ScTab",["原料"])}>原料</button><button class="btn ${SC.tab==="仕掛品"?"hqBtnNormal":"btn2"}" ${btnAttr("h2ScTab",["仕掛品"])}>仕掛品</button></div></div><div id="h2ScBody">${h2Loading()}</div>`);
 if(!SC.rows){
  try{
   const[items,masters,cur,prev]=await Promise.all([hqNormalItems(),h2Masters(),sel2("hq_stock_counts_v1500",`select=*&count_date=eq.${date}`),sel2("hq_stock_counts_v1500",`select=kind,item_name,count_date,total_kg&count_date=lt.${date}&order=count_date.desc&limit=2000`)]);
   const cm={},pm={};cur.forEach(c=>cm[c.kind+"|"+c.item_name]=c);prev.forEach(c=>{const k=c.kind+"|"+c.item_name;if(!pm[k])pm[k]=c});
   const raw=items.map(i=>({kind:"原料",name:i.name,def:Number(i.pack_weight_kg),cur:cm["原料|"+i.name],prev:pm["原料|"+i.name]}));
   const wip=[];const seen=new Set();
   masters.forEach(m=>{if(seen.has(m.name))return;seen.add(m.name);wip.push({kind:"仕掛品",name:m.name,master:m.id,item:m.item_name,def:Number(m.default_pack_kg),cur:cm["仕掛品|"+m.name],prev:pm["仕掛品|"+m.name]})});
   cur.filter(c=>c.kind==="仕掛品"&&!seen.has(c.item_name)).forEach(c=>wip.push({kind:"仕掛品",name:c.item_name,manual:true,def:null,cur:c}));
   cur.filter(c=>c.kind==="原料"&&!items.some(i=>i.name===c.item_name)).forEach(c=>raw.push({kind:"原料",name:c.item_name,def:null,cur:c,hidden:true}));
   SC.rows=[...raw,...wip].map(r=>({...r,lines:scLines(r.cur,r.def),dirty:false}));
  }catch(e){return h2Set("h2ScBody",`<div class="err">${esc(h2Err(e))}</div><div class="notice">019のSQLが未実行の可能性があります。</div>`)}
 }
 scRender(can);
}
function scTotal(r){let kg=0,any=false;for(const l of r.lines){const p=num2(l.pack),c=num2(l.cases);if(Number.isFinite(p)&&Number.isFinite(c)){kg+=p*c;any=true}}return any?kg:null}
function scRender(can){
 const rows=SC.rows.map((r,i)=>({r,i})).filter(x=>x.r.kind===SC.tab);
 const card=({r,i})=>`<div class="card" style="padding:12px 14px"><div class="itemHead"><div><b>${esc(r.name)}</b>${r.manual?' <span class="badge warn">手入力</span>':""}${r.hidden?' <span class="badge unset">表示しない品目</span>':""}<div class="small">${r.def!=null?`初期入れ数 ${hqKg(r.def)}kg`:""}${r.item?` ／ 原料：${esc(r.item)}`:""}${r.prev?` ／ 前回 ${esc(String(r.prev.count_date).slice(5).replace("-","/"))} ${hqKg(r.prev.total_kg)}kg`:""}${r.cur?` ／ この日の入力：${esc(r.cur.user_name||"")}`:""}</div></div><div style="text-align:right"><b style="font-size:20px" id="h2ScT${i}">${kg2(scTotal(r))}</b><div class="small">kg</div></div></div>
 ${r.lines.map((l,j)=>`<div class="h2Line"><div><label class="label">入れ数kg</label><input class="input" inputmode="decimal" value="${esc(l.pack)}" ${can?"":"disabled"} ${seikaEventAttrs("input","h2ScField",[i,j,"pack",{__seikaValue:true}])}></div><div style="padding-bottom:12px;font-weight:900">×</div><div><label class="label">ケース数</label><input class="input" inputmode="decimal" value="${esc(l.cases)}" ${can?"":"disabled"} ${seikaEventAttrs("input","h2ScField",[i,j,"cases",{__seikaValue:true}])}></div>${j&&can?`<button class="btn btn2 x" ${btnAttr("h2ScDelLine",[i,j])}>削除</button>`:"<span></span>"}</div>`).join("")}
 ${can?`<button class="btn btn2" style="margin-top:6px;min-height:40px" ${btnAttr("h2ScAddLine",[i])}>＋ 入れ数を追加</button>`:""}</div>`;
 const sum=rows.reduce((s,x)=>s+(scTotal(x.r)||0),0);
 h2Set("h2ScBody",`<div class="small" style="margin:4px 0 10px">1行が「入れ数kg × ケース数」です。入れ数がちがう箱は「＋ 入れ数を追加」で行を増やします。全部の行を空にして保存すると、その日の入力を消します。</div>
 ${rows.map(card).join("")||`<div class="notice">${SC.tab==="原料"?"原料の品目がありません。本社社員が「入荷登録・品目 → 品目の追加・変更 → 在庫入力の原料」で追加します。":"仕掛品がありません。本社社員が下処理マスタで登録します（下の手入力も使えます）。"}</div>`}
 ${SC.tab==="仕掛品"&&can?`<details class="card"><summary><b>マスタに無い仕掛品を手入力</b></summary><label class="label" style="margin-top:6px">品名</label><input id="h2ScMN" class="input"><div class="row"><div><label class="label">1ケースのkg</label><input id="h2ScMK" class="input" inputmode="decimal"></div><div><label class="label">数量（ケース数）</label><input id="h2ScMC" class="input" inputmode="decimal"></div></div><div class="small">手入力した仕掛品は、この日の記録だけに残ります（マスタには追加されません）。</div><button class="btn btn2" style="width:100%;margin-top:8px" ${btnAttr("h2ScManual",[])}>この日の在庫に追加</button></details>`:""}
 <div class="card"><b>${SC.tab}の合計：<span id="h2ScSum">${kg2(sum)}</span>kg</b></div>
 ${can?`<button class="btn hqBtnNormal" style="width:100%;margin-top:6px" ${btnAttr("h2ScSave",[])}>保存する（原料・仕掛品の両方）</button>`:""}
 ${SC.tab==="原料"&&hqCanItems()&&!hqViewOnly()?hqNormalAddForm("hqNormalPage"):""}`);
}
function h2ScTab(t){SC.tab=t;return h2StockInputPage(SC.date,"",t)}
function h2ScField(i,j,f,v){const r=SC.rows[i];if(!r)return;r.lines[j][f]=v;r.dirty=true;const t=document.getElementById("h2ScT"+i);if(t)t.textContent=kg2(scTotal(r));const s=document.getElementById("h2ScSum");if(s)s.textContent=kg2(SC.rows.filter(x=>x.kind===SC.tab).reduce((a,x)=>a+(scTotal(x)||0),0))}
function h2ScAddLine(i){const r=SC.rows[i];r.lines.push({pack:r.def==null?"":String(r.def),cases:""});r.dirty=true;scRender(true)}
function h2ScDelLine(i,j){const r=SC.rows[i];r.lines.splice(j,1);r.dirty=true;scRender(true)}
function h2ScManual(){const n=h2Val("h2ScMN").trim(),k=h2Val("h2ScMK"),c=h2Val("h2ScMC");if(!n)return alert("品名を入れてください");if(!(num2(k)>0))return alert("1ケースのkgを入れてください");if(!(num2(c)>=0))return alert("数量を入れてください");if(SC.rows.some(r=>r.kind==="仕掛品"&&r.name===n))return alert("同じ名前の仕掛品があります。上の行に入れてください");SC.rows.push({kind:"仕掛品",name:n,manual:true,def:null,lines:[{pack:k,cases:c}],dirty:true});scRender(true)}
async function h2ScSave(){
 if(H2.busy)return;const rows=[];let bad="";
 for(const r of SC.rows){
  const lines=r.lines.filter(l=>String(l.pack).trim()!==""||String(l.cases).trim()!=="").map(l=>({pack_kg:num2(l.pack),cases:num2(l.cases)}));
  for(const l of lines){if(!(l.pack_kg>0))bad=`${r.name} の入れ数kgを入れてください`;if(!(l.cases>=0))bad=`${r.name} のケース数を入れてください`}
  const onlyDefault=r.lines.every(l=>String(l.cases).trim()==="");
  if(!r.cur&&!lines.length)continue;
  if(!r.cur&&onlyDefault)continue;
  rows.push({kind:r.kind,item_name:r.name,master_id:r.master||null,manual:!!r.manual,lines:onlyDefault?[]:lines});
 }
 if(bad)return alert(bad);if(!rows.length)return alert("入力がありません");
 H2.busy=true;
 try{const a=await r2("hq_save_stock_counts_v1500",{p_date:SC.date,p_rows:rows});H2.busy=false;SC.rows=null;return h2StockInputPage(SC.date,`保存しました（${a?.saved??0}品目${a?.cleared?`・消去 ${a.cleared}品目`:""}）`)}catch(e){H2.busy=false;alert(h2Err(e))}
}
hqNormalPage=async function(date="",msg=""){if(SC&&date&&SC.date!==date)SC=null;return h2StockInputPage(date,msg)};
window.hqNormalPage=hqNormalPage;
window.hqNormalKeepDraft=function(){};
const nfBase=hqNormalAddForm;
hqNormalAddForm=function(back){return nfBase(back).replace("通常在庫の品目を追加","在庫入力の原料を追加").replace("1ケースのkg","初期入れ数kg（必須）").replace("例：8","例：8（在庫入力の1行目に入ります）")};
window.hqNormalAddForm=hqNormalAddForm;
const niBase=hqNormalItemsPage;
hqNormalItemsPage=async function(...a){const r=await niBase.apply(this,a);try{const app=document.getElementById("app");app.querySelectorAll(".small").forEach(el=>{el.innerHTML=el.innerHTML.replace(/1ケース ([0-9.,]+)kg/,"初期入れ数 $1kg")});app.querySelectorAll("button").forEach(b=>{if(b.textContent==="kgを直す")b.textContent="初期入れ数を直す";if(b.textContent==="通常在庫の品目")b.textContent="在庫入力の原料"});const s=app.querySelector(".head .sub");if(s)s.textContent="在庫入力の原料（QRで管理しない品目）"}catch(e){}return r};
window.hqNormalItemsPage=hqNormalItemsPage;
const itBase=hqItemTabs;hqItemTabs=function(cur){return itBase(cur).replace(">通常在庫の品目<",">在庫入力の原料<")};window.hqItemTabs=hqItemTabs;
hqEditNormalItem=async function(name,kg,active){const v=prompt(`${name} の初期入れ数kg`,String(kg));if(v==null)return;const n=Number(v);if(!(n>0))return alert("0より大きい数を入れてください");return hqSaveNormalItem(name,n,active,"hqNormalItemsPage")};window.hqEditNormalItem=hqEditNormalItem;
const snBase=hqSaveNormalItem;hqSaveNormalItem=async function(name,kg,active,back){if(back==="hqNormalPage")SC=null;return snBase.apply(this,arguments)};window.hqSaveNormalItem=hqSaveNormalItem;

/* --- 在庫表（QR品目＋原料＋仕掛品） --- */
hqTableData=async function(from,to,raw){const r=await r2("get_hq_stock_table_v1500",{p_from:from,p_to:to});const d=Array.isArray(r)?r[0]:r;if(raw)return d;X.lastTable=d;return{...d,rows:(d?.rows||[]).map(x=>x.kind==="QR"?x:{...x,kind:"通常",_kind:x.kind})}};
window.hqTableData=hqTableData;
const tpBase=hqTablePage;
hqTablePage=async function(...a){
 const r=await tpBase.apply(this,a);
 try{
  const box=document.getElementById("hqTbl");if(!box)return r;
  const sub=document.querySelector(".head .sub");if(sub)sub.textContent="本社のQR品目・原料・仕掛品の在庫（kg）";
  const note=box.querySelector(":scope > .small");if(note)note.textContent="QR品目：その日の終わりの在庫（取り消した出庫・受け入れは数えません。下処理の確定で減らした分・廃棄も引きます）。原料・仕掛品：その日に在庫入力した数（入力がない日は「—」）。量目が分からないQRのロットは「kg不明」として別に出します。";
 }catch(e){}
 return r;
};
window.hqTablePage=hqTablePage;

/* --- 品目別使用数量 --- */
async function usageData(month){
 const{from,toCap}=h2MonthRange(month);const prevDay=hqAddDays(from,-1);
 if(from>hqToday())return{dates:[],items:[],countDays:[]};
 const data=await hqTableData(prevDay,toCap,true);const rows=data?.rows||[];
 const countDays=new Set((data?.count_days||[]).map(String));
 const dates=(rows[0]?.values||[]).map(v=>v.date).slice(1);
 const items=[];
 for(const r of rows){
  if(r.kind==="仕掛品")continue;
  const days=[];
  for(let i=1;i<r.values.length;i++){
   const p=r.values[i-1],c=r.values[i];
   if(r.kind==="QR"){
    const caseUse=Number(p.cases)+Number(c.in_cases)-Number(c.cases),kgUse=Number(p.kg)+Number(c.in_kg)-Number(c.kg),kguUse=Number(p.kg_unit_qty)+Number(c.in_kgu)-Number(c.kg_unit_qty);
    days.push({date:c.date,cases:caseUse,kgu:kguUse,kg:kgUse,waste:Number(c.waste_kg),rawout:Number(c.rawout_kg),work:countDays.has(String(c.date))});
   }else{
    if(c.kg==null||p.kg==null){days.push({date:c.date,kg:null,cases:null,work:countDays.has(String(c.date))});continue}
    days.push({date:c.date,kg:Number(p.kg)-Number(c.kg),cases:Number(p.cases)-Number(c.cases),work:true});
   }
  }
  const has=days.some(d=>d.kg);if(!has)continue;
  items.push({name:r.item_name,kind:r.kind,days});
 }
 return{dates,items,countDays:[...countDays].sort()};
}
function usageTotals(it){const wd=it.days.filter(d=>d.work&&d.kg!=null);const sum=k=>it.days.reduce((s,d)=>s+(Number(d[k])||0),0);return{kg:sum("kg"),cases:sum("cases"),kgu:sum("kgu"),waste:sum("waste"),rawout:sum("rawout"),avgKg:wd.length?wd.reduce((s,d)=>s+d.kg,0)/wd.length:null,avgCases:wd.length?wd.reduce((s,d)=>s+(d.cases||0),0)/wd.length:null,workDays:wd.length}}
async function hqUsagePage(month=""){
 if(!h2CanReport())return hqHome();month=h2Month(month);setScreen("hqUsagePage",[month]);
 pageShell("品目別使用数量","前日の在庫＋その日の入荷−その日の在庫",`<div class="card"><label class="label">月</label><input type="month" class="input" value="${esc(month)}" ${seikaEventAttrs("change","hqUsagePage",[{__seikaValue:true}])}><button class="btn hqBtnExcelOut" style="width:100%;margin-top:8px" ${btnAttr("h2ExcelUsage",[month])}>この月の使用数量をExcelにする</button></div><div id="h2UsBody">${h2Loading()}</div>`);
 try{
  const{dates,items,countDays}=await usageData(month);
  const u=(v,unit)=>v==null||!Number.isFinite(v)?"—":`${hqQty(Math.round(v*100)/100)}${unit}`;
  h2Set("h2UsBody",`<div class="card small">稼働日（在庫を入力した日）：${countDays.length}日。平均は稼働日で割っています。QR品目は単位の数（ケース・大型容器はkg）とkgを並べています。仕掛品は対象外です。</div>
  ${items.map(it=>{const t=usageTotals(it);return `<details class="card"><summary><b>${esc(it.name)}</b> <span class="badge ${it.kind==="QR"?"normal":"warn"}">${it.kind==="QR"?"QR":"原料"}</span><div class="small">月の合計 ${kg2(t.kg)}kg${it.kind==="QR"?`（ケース ${u(t.cases,"")}・大型容器 ${u(t.kgu,"kg")}）`:`（${u(t.cases,"ケース")}）`} ／ 稼働日平均 ${kg2(t.avgKg)}kg${it.kind==="QR"?` ／ 廃棄 ${kg2(t.waste)}kg ／ 原料のまま出荷 ${kg2(t.rawout)}kg`:""}</div></summary>
   <div style="overflow-x:auto"><table class="h2Tbl"><tr><th>日付</th><th>使用kg</th>${it.kind==="QR"?"<th>ケース</th><th>大型容器kg</th><th>うち廃棄kg</th><th>うち原料出しkg</th>":"<th>ケース</th>"}<th>稼働日</th></tr>${it.days.map(d=>`<tr><td>${esc(String(d.date).slice(5))}</td><td>${kg2(d.kg)}</td>${it.kind==="QR"?`<td>${u(d.cases,"")}</td><td>${u(d.kgu,"")}</td><td>${kg2(d.waste)}</td><td>${kg2(d.rawout)}</td>`:`<td>${u(d.cases,"")}</td>`}<td>${d.work?"○":""}</td></tr>`).join("")}</table></div></details>`}).join("")||'<div class="notice">この月の使用数量はありません。</div>'}`);
 }catch(e){h2Set("h2UsBody",`<div class="err">${esc(h2Err(e))}</div>`)}
}
function h2ExcelUsage(m){return X.excelOut("usage",m)}

/* --- 棚卸し --- */
const TAKE_CSS=`.h2PdfRoot h1{font-size:26px;margin:0 0 4px}.h2PdfRoot .m{font-size:13px;margin-bottom:8px}.h2PdfRoot table{border-collapse:collapse;width:100%;font-size:13px}.h2PdfRoot th,.h2PdfRoot td{border:1px solid #000;padding:5px 6px}.h2PdfRoot th{background:#e5e7eb}.h2PdfRoot td.n{text-align:right}.h2PdfRoot td.blank{width:90px}.h2PdfRoot .neg{font-weight:900;text-decoration:underline}`;
async function hqStocktakePage(msg=""){
 if(!h2CanBoss())return hqHome();setScreen("hqStocktakePage",[msg]);pageShell("棚卸し","確認表を印刷 → 数える → 実数を入力 → 結果を印刷",h2Loading());
 let list=[];try{list=await sel2("hq_stocktakes_v1500","select=id,take_date,status,created_by_name,confirmed_at,confirmed_by_name&order=created_at.desc&limit=30")}catch(e){return pageShell("棚卸し","エラー",`<div class="err">${esc(h2Err(e))}</div>`)}
 const cur=list.find(t=>t.status==="入力中");
 pageShell("棚卸し","確認表を印刷 → 数える → 実数を入力 → 結果を印刷",`${okHtml(msg)}
 ${cur?`<div class="card"><b>入力中の棚卸し：${esc(cur.take_date)}</b><button class="btn hqBtnTake" style="width:100%;margin-top:8px" ${btnAttr("hqStocktakeEdit",[cur.id])}>続きを入力する</button></div>`:`<div class="card"><b>新しい棚卸しを始める</b><label class="label" style="margin-top:6px">棚卸しの日</label><input id="h2TkD" type="date" class="input" max="${hqToday()}" value="${hqToday()}"><div class="small">その時点で在庫のあるQRの原料（ロットごと）と、在庫入力の原料・仕掛品が確認表に並びます。</div><button class="btn hqBtnTake" style="width:100%;margin-top:8px" ${btnAttr("h2TakeNew",[])}>確認表を作る</button></div>`}
 <div class="card"><b>これまでの棚卸し</b>${list.map(t=>`<div class="itemHead" style="padding:6px 0;border-top:1px solid #e2e8f0"><div><b>${esc(t.take_date)}</b> <span class="badge ${t.status==="確定"?"normal":"warn"}">${esc(t.status)}</span><div class="small">${esc(t.created_by_name||"")}${t.confirmed_at?` ／ 確定 ${esc(t.confirmed_by_name||"")}`:""}</div></div><button class="btn btn2" ${btnAttr("hqStocktakeEdit",[t.id])}>開く</button></div>`).join("")||'<div class="small">まだありません</div>'}</div>`);
}
async function h2TakeNew(){
 const date=h2Val("h2TkD")||hqToday();
 try{
  const[lots,cnt,items,masters]=await Promise.all([hqLots("select=id,lot_no,item_name,current_qty,unit,pack_weight&status=eq.在庫あり&order=item_name.asc,lot_no.asc&limit=2000"),sel2("hq_stock_counts_v1500",`select=*&count_date=lte.${date}&order=count_date.desc&limit=3000`),hqNormalItems(),h2Masters()]);
  const latest={};cnt.forEach(c=>{const k=c.kind+"|"+c.item_name;if(!latest[k])latest[k]=c});
  const rows=lots.map(l=>({type:"QR",lot_id:l.id,lot_no:l.lot_no,item_name:l.item_name,unit:l.unit,book:Number(l.current_qty),actual:""}));
  items.forEach(i=>{const c=latest["原料|"+i.name];rows.push({type:"count",kind:"原料",item_name:i.name,pack_kg:Number(c?.lines?.[0]?.pack_kg||i.pack_weight_kg),book_cases:c?Number(c.total_cases):null,book_kg:c?Number(c.total_kg):null,book_date:c?.count_date||null,actual:""})});
  const seen=new Set();masters.forEach(m=>{if(seen.has(m.name))return;seen.add(m.name);const c=latest["仕掛品|"+m.name];rows.push({type:"count",kind:"仕掛品",item_name:m.name,master_id:m.id,pack_kg:Number(c?.lines?.[0]?.pack_kg||m.default_pack_kg),book_cases:c?Number(c.total_cases):null,book_kg:c?Number(c.total_kg):null,book_date:c?.count_date||null,actual:""})});
  const r=await r2("hq_stocktake_save_v1500",{p_id:null,p_date:date,p_rows:rows});
  return hqStocktakeEdit(r.id,"確認表を作りました。印刷して数えてください");
 }catch(e){alert(h2Err(e))}
}
let TK=null;
async function hqStocktakeEdit(id,msg=""){
 if(!h2CanBoss())return hqHome();setScreen("hqStocktakeEdit",[id,msg]);pageShell("棚卸し","",h2Loading());
 try{TK=(await sel2("hq_stocktakes_v1500",`select=*&id=eq.${id}`))[0];if(!TK)throw new Error("棚卸しが見つかりません")}catch(e){return pageShell("棚卸し","エラー",`<div class="err">${esc(h2Err(e))}</div>`)}
 const done=TK.status==="確定",rows=done?(TK.result||TK.rows):TK.rows;
 const sec=(title,list)=>`<div class="card" style="overflow-x:auto"><b>${title}（${list.length}）</b><table class="h2Tbl"><tr><th>品名</th><th>${title==="QRの原料"?"ロットNo.":"入れ数kg"}</th><th>帳簿</th><th>実数${title==="QRの原料"?"":"（ケース）"}</th>${done?"<th>差・結果</th>":""}</tr>${list.map(({r,i})=>`<tr><td>${esc(r.item_name)}</td><td>${r.type==="QR"?esc(r.lot_no):hqKg(r.pack_kg)}</td><td>${r.type==="QR"?`${hqQty(r.book)}${r.unit==="kg"?"kg":"ケース"}`:r.book_cases==null?"—":`${hqQty(r.book_cases)}ケース（${esc(String(r.book_date||"").slice(5))}）`}</td><td>${done?esc(r.actual===""||r.actual==null?"—":String(r.actual)):`<input class="input" style="min-width:90px" inputmode="decimal" value="${esc(r.actual??"")}" ${seikaEventAttrs("input","h2TakeField",[i,{__seikaValue:true}])}>`}</td>${done?`<td class="${r.diff?"h2Red":""}">${r.diff!=null?`${r.diff>0?"+":""}${hqQty(r.diff)} `:""}${esc(r.result||"")}</td>`:""}</tr>`).join("")}</table></div>`;
 const idx=rows.map((r,i)=>({r,i}));
 pageShell("棚卸し",`${esc(TK.take_date)} ／ ${esc(TK.status)}`,`${okHtml(msg)}
 <div class="card"><div class="row"><button class="btn btn2" ${btnAttr("h2TakePrint",[false])}>確認表を印刷</button>${done?`<button class="btn hqBtnTake" ${btnAttr("h2TakePrint",[true])}>結果を印刷</button>`:""}</div>${done?"":'<div class="small" style="margin-top:6px">数えた数を入れて「途中保存」。全部入れたら「確定」。空欄の行は変えません。</div>'}</div>
 ${sec("QRの原料",idx.filter(x=>x.r.type==="QR"))}${sec("原料",idx.filter(x=>x.r.type!=="QR"&&x.r.kind==="原料"))}${sec("仕掛品",idx.filter(x=>x.r.type!=="QR"&&x.r.kind==="仕掛品"))}
 ${done?"":`<div class="row"><button class="btn btn2" ${btnAttr("h2TakeSave",[false])}>途中保存</button><button class="btn hqBtnConfirm" ${btnAttr("h2TakeSave",[true])}>確定する</button></div><div class="small" style="margin-top:6px">確定すると、QRの原料はロットごとに「実数調整（棚卸し）」として記録し、原料・仕掛品はその日の在庫入力として保存します。</div>`}`);
}
function h2TakeField(i,v){if(TK&&TK.rows[i])TK.rows[i].actual=v}
async function h2TakeSave(confirmIt){
 if(H2.busy)return;
 for(const r of TK.rows){if(String(r.actual??"").trim()!==""&&!(num2(r.actual)>=0))return alert(`${r.item_name} の実数が正しくありません`);r.actual=String(r.actual??"").trim()===""?"":num2(r.actual)}
 if(confirmIt&&!confirm("棚卸しを確定します。差がある分は在庫を直します。よろしいですか？"))return;
 H2.busy=true;
 try{await r2("hq_stocktake_save_v1500",{p_id:TK.id,p_date:TK.take_date,p_rows:TK.rows});if(confirmIt)await r2("hq_stocktake_confirm_v1500",{p_id:TK.id});H2.busy=false;return hqStocktakeEdit(TK.id,confirmIt?"確定しました。結果を印刷できます":"途中保存しました")}catch(e){H2.busy=false;alert(h2Err(e))}
}
async function h2TakePrint(result){
 const rows=result?(TK.result||[]):TK.rows;const perPage=30;const pages=[];
 const head=`<h1>本社 棚卸し ${result?"結果":"確認表"}　${esc(TK.take_date)}</h1><div class="m">作成：${esc(TK.created_by_name||"")}${TK.confirmed_at?` ／ 確定：${esc(TK.confirmed_by_name||"")}`:""}</div>`;
 const tr=r=>`<tr><td>${r.type==="QR"?"QR":esc(r.kind)}</td><td>${esc(r.item_name)}</td><td>${r.type==="QR"?esc(r.lot_no):`入れ数${hqKg(r.pack_kg)}kg`}</td><td class="n">${r.type==="QR"?`${hqQty(r.book)}${r.unit==="kg"?"kg":"ケース"}`:r.book_cases==null?"—":`${hqQty(r.book_cases)}ケース`}</td>${result?`<td class="n">${r.actual===""||r.actual==null?"—":hqQty(r.actual)}</td><td class="n ${r.diff?"neg":""}">${r.diff!=null?hqQty(r.diff):""}</td><td>${esc(r.result||"")}</td>`:'<td class="blank"></td>'}</tr>`;
 for(let i=0;i<Math.max(1,rows.length);i+=perPage)pages.push(`${head}<table><tr><th>区分</th><th>品名</th><th>ロット・入れ数</th><th>帳簿</th>${result?"<th>実数</th><th>差</th><th>結果</th>":"<th>実数</th>"}</tr>${rows.slice(i,i+perPage).map(tr).join("")}</table>`);
 return h2MakePdf(pages,TAKE_CSS,`本社_棚卸し${result?"結果":"確認表"}_${TK.take_date}.pdf`);
}
Object.assign(window,{h2ScTab,h2ScField,h2ScAddLine,h2ScDelLine,h2ScManual,h2ScSave,hqUsagePage,h2ExcelUsage,hqStocktakePage,h2TakeNew,hqStocktakeEdit,h2TakeField,h2TakeSave,h2TakePrint});
Object.assign(X,{usageData,usageTotals});
})();

/* ===== 廃棄一覧／仕入れ価格表／歩留まり／品質評価一覧／Excel出力 ===== */
(function(){
"use strict";
const X=window.__h2;const{H2,r2,sel2,num2,kg2,yen2,pct2,dt2,mins2,hm2,btnAttr,roleIs,h2CanBoss,h2CanRaw,h2CanMoney,h2CanReport,h2Month,h2MonthRange,h2MonthLabel,h2Monday,h2FiscalStart,h2Err,h2Notice,h2Loading,h2Set,h2Val,h2Works,h2Materials,h2Members,h2UsedKg,h2Diff,h2Yield,h2Prices,h2PriceOf,h2QrItems}=X;
const KINDS=["下処理ロス","原料出しロス","原料廃棄"];

/* --- 廃棄一覧 --- */
async function wasteData(month){const{from,to}=h2MonthRange(month);return sel2("hq_waste_v1500",`select=*&waste_date=gte.${from}&waste_date=lte.${to}&order=waste_date.asc,created_at.asc&limit=5000`)}
async function hqWastePage(month="",kind="すべて",msg=""){
 if(!h2CanReport()&&!h2CanRaw())return hqHome();month=h2Month(month);setScreen("hqWastePage",[month,kind,msg]);
 const{from,to}=h2MonthRange(month);
 let items=[];try{const[a,b]=await Promise.all([h2QrItems(),hqNormalItems()]);items=[...new Set([...a.map(x=>x.name),...b.map(x=>x.name)])]}catch(e){}
 pageShell("廃棄一覧","下処理ロス・原料出しロス・原料廃棄",`${okHtml(msg)}<div class="card"><label class="label">月</label><input type="month" class="input" value="${esc(month)}" ${seikaEventAttrs("change","hqWastePage",[{__seikaValue:true},kind])}>
 <div class="h2Tabs" style="margin-top:8px">${["すべて",...KINDS].map(k=>`<button class="btn ${kind===k?"hqBtnWaste":"btn2"}" ${btnAttr("hqWastePage",[month,k])}>${k}</button>`).join("")}</div>
 ${h2CanReport()?`<button class="btn hqBtnExcelOut" style="width:100%;margin-top:8px" ${btnAttr("h2ExcelWaste",[month])}>この月の廃棄をExcelにする</button>`:""}</div>
 ${h2CanRaw()&&!hqViewOnly()?`<details class="card" ${kind==="原料出しロス"?"open":""}><summary><b>原料出しロスを入力（kg）</b></summary><div class="small" style="margin-top:4px">原料のまま出荷するときに出たロスです。在庫は減らしません。</div><div class="row" style="margin-top:6px"><div><label class="label">日付</label><input id="h2WsD" type="date" class="input" max="${hqToday()}" value="${hqToday()}"></div><div><label class="label">kg</label><input id="h2WsK" class="input" inputmode="decimal" placeholder="例：3.5"></div></div><label class="label" style="margin-top:6px">品目</label><select id="h2WsI" class="input"><option value="">選んでください</option>${items.map(n=>`<option>${esc(n)}</option>`).join("")}</select><label class="label" style="margin-top:6px">メモ（任意）</label><input id="h2WsM" class="input"><button class="btn hqBtnWaste" style="width:100%;margin-top:8px" ${btnAttr("h2SaveRawLoss",[month])}>保存する</button></details>
 <div class="card small">原料廃棄（在庫を減らす廃棄）は、原料のQRを読み取って、ロットの画面の「廃棄」で入れます。</div>`:""}
 <div id="h2WsBody">${h2Loading()}</div>`);
 try{
  let rows=(await wasteData(month)).filter(r=>!r.cancelled_at);const all=rows;if(kind!=="すべて")rows=rows.filter(r=>r.kind===kind);
  const money=h2CanMoney();let pm={};if(money&&all.length){try{pm=await h2Prices(from,to,[...new Set(all.map(r=>r.item_name))])}catch(e){}}
  const amt=r=>{const p=h2PriceOf(pm,r.item_name,r.waste_date);return p==null?null:p*Number(r.kg)};
  const byKind=KINDS.map(k=>{const l=all.filter(r=>r.kind===k);return{k,kg:l.reduce((s,r)=>s+Number(r.kg),0),yen:l.reduce((s,r)=>s+(amt(r)||0),0),un:l.some(r=>amt(r)==null)}});
  const byItem={};rows.forEach(r=>{const o=byItem[r.item_name]=byItem[r.item_name]||{kg:0,yen:0,un:false};o.kg+=Number(r.kg);const a=amt(r);if(a==null)o.un=true;else o.yen+=a});
  h2Set("h2WsBody",`<div class="card" style="overflow-x:auto"><b>区分別（${esc(h2MonthLabel(month))}）</b><table class="h2Tbl"><tr><th>区分</th><th>kg</th>${money?"<th>金額</th>":""}</tr>${byKind.map(o=>`<tr><td>${o.k}</td><td>${kg2(o.kg)}</td>${money?`<td>${yen2(o.yen)}${o.un?"＋未計算あり":""}</td>`:""}</tr>`).join("")}</table></div>
  <div class="card" style="overflow-x:auto"><b>品目別（${esc(kind)}）</b><table class="h2Tbl"><tr><th>品目</th><th>kg</th>${money?"<th>金額</th>":""}</tr>${Object.entries(byItem).sort((a,b)=>b[1].kg-a[1].kg).map(([n,o])=>`<tr><td>${esc(n)}</td><td>${kg2(o.kg)}</td>${money?`<td>${yen2(o.yen)}${o.un?"＋未計算あり":""}</td>`:""}</tr>`).join("")||'<tr><td colspan="3">ありません</td></tr>'}</table>${money?'<div class="small">金額は、作業日の週の市場価格（同じ品目の平均）×kg です。</div>':""}</div>
  ${rows.slice().reverse().map(r=>`<div class="card" style="padding:10px 14px"><div class="itemHead"><div><b>${esc(r.item_name)}</b> <span class="badge ${r.kind==="原料廃棄"?"danger":r.kind==="下処理ロス"?"warn":"unset"}">${esc(r.kind)}</span><div class="small">${esc(r.waste_date)} ／ ${kg2(r.kg)}kg${r.qty!=null?`（${hqQty(r.qty)}${r.unit==="kg"?"kg":"ケース"}）`:""}${money?` ／ ${yen2(amt(r))}`:""} ／ ${esc(r.user_name||"")}${r.lot_no?` ／ ${esc(r.lot_no)}`:""}${r.memo?` ／ ${esc(r.memo)}`:""}</div></div>${h2CanBoss()&&r.kind!=="下処理ロス"?`<button class="btn btn2" ${btnAttr("h2CancelWaste",[r.id,month,kind])}>取消</button>`:""}</div></div>`).join("")}`);
 }catch(e){h2Set("h2WsBody",`<div class="err">${esc(h2Err(e))}</div>`)}
}
async function h2SaveRawLoss(month){
 const d=h2Val("h2WsD"),k=num2(h2Val("h2WsK")),i=h2Val("h2WsI");if(!i)return alert("品目を選んでください");if(!(k>0))return alert("kgを入れてください");
 try{await r2("hq_rawout_loss_v1500",{p_date:d,p_item_name:i,p_kg:k,p_memo:h2Val("h2WsM")});return hqWastePage(month,"原料出しロス","保存しました")}catch(e){alert(h2Err(e))}
}
async function h2CancelWaste(id,month,kind){const r=prompt("取り消す理由");if(r==null)return;try{await r2("hq_waste_cancel_v1500",{p_id:id,p_reason:r});return hqWastePage(month,kind,"取り消しました")}catch(e){alert(h2Err(e))}}
async function h2Dispose(lotId,key,unit,cur){
 const q=num2(h2Val("h2DsQ"));if(!(q>0))return alert("数量を入れてください");if(q>Number(cur))return alert("在庫より多くは廃棄できません");
 if(!confirm(`${hqQty(q)}${unit==="kg"?"kg":"ケース"} を廃棄します。在庫から減ります。よろしいですか？`))return;
 try{const r=await r2("hq_dispose_v1500",{p_operation_id:newId(),p_lot_id:lotId,p_qty:q,p_memo:h2Val("h2DsM")});return hqLotPage(key,r?.kg_unknown?"廃棄しました（量目が分からないため、廃棄一覧のkgは0です。量目を確認してください）":"廃棄しました")}catch(e){alert(h2Err(e))}
}

/* --- 仕入れ価格表（本社用） --- */
async function hqPricePage(end=""){
 if(!h2CanMoney())return hqHome();end=end||hqToday();setScreen("hqPricePage",[end]);
 const last=h2Monday(end),first=hqAddDays(last,-49);
 pageShell("仕入れ価格表（本社）","市場価格の週平均（同じ品目・産地は問わない）",`<div class="card"><label class="label">この週まで（8週分）</label><input type="date" class="input" value="${esc(end)}" ${seikaEventAttrs("change","hqPricePage",[{__seikaValue:true}])}><div class="small" style="margin-top:6px">社内売りは週間価格（市場相場）なので、石岡の契約価格は使いません。市場は 水戸大同・大同・水戸中央・中央・東一・シティ です。その週に価格がないときは前の週（さらに前）の価格を使い、1件もなければ「未計算」です。価格の入力は石岡の「仕入れ価格表」の画面のままです。</div></div><div id="h2PrBody">${h2Loading()}</div>`);
 try{
  const rows=await r2("hq_price_table_v1500",{p_from:first,p_to:last,p_items:null});
  const weeks=[...new Set((rows||[]).map(r=>r.week))].sort(),items=[...new Set((rows||[]).map(r=>r.item_name))].sort((a,b)=>a.localeCompare(b,"ja"));
  const m={};(rows||[]).forEach(r=>m[r.item_name+"|"+r.week]=r);
  h2Set("h2PrBody",`<div class="card" style="overflow-x:auto"><table class="h2Tbl"><tr><th>品目</th>${weeks.map(w=>`<th>${esc(w.slice(5).replace("-","/"))}週</th>`).join("")}</tr>${items.map(n=>`<tr><td>${esc(n)}</td>${weeks.map(w=>{const r=m[n+"|"+w];if(!r||r.price==null)return '<td style="color:#94a3b8">未計算</td>';const carry=r.src_week!==w;return `<td><b>${hqKg(r.price)}</b>${carry?`<div class="small" style="color:#b45309">${esc(String(r.src_week).slice(5).replace("-","/"))}週の価格</div>`:`<div class="small">${r.count}件の平均</div>`}</td>`}).join("")}</tr>`).join("")}</table><div class="small">円/kg（税抜）。週は月曜日から始まります。</div></div>`);
 }catch(e){h2Set("h2PrBody",`<div class="err">${esc(h2Err(e))}</div>`)}
}

/* --- 歩留まり管理 --- */
async function yieldData(from,to){
 const works=await h2Works(`select=*&kind=eq.下処理&confirm_status=eq.確定&work_date=gte.${from}&work_date=lte.${to}&order=work_date.asc,started_at.asc&limit=5000`);
 const ids=works.map(w=>w.id);const[mats,mem]=await Promise.all([h2Materials(ids),h2Members(ids)]);
 let pm={};if(h2CanMoney()&&works.length){try{pm=await h2Prices(from,to,[...new Set(works.map(w=>w.raw_item_name))])}catch(e){}}
 return works.map(w=>{const ms=mats.filter(m=>m.work_id===w.id),mm=mem.filter(m=>m.work_id===w.id&&m.phase==="作業");const u=h2UsedKg(ms);const y=Number(w.yield_kg),ws=Number(w.waste_kg);const price=h2PriceOf(pm,w.raw_item_name,w.work_date);
  return{w,date:w.work_date,item:w.raw_item_name||"",product:w.product_name||"",used:u.kg,usedUnknown:u.unknown,usedText:ms.map(m=>`${hqQty(m.qty)}${m.unit==="kg"?"kg":"ケース"}`).join("+"),yield:y,waste:ws,rate:h2Yield(w),diff:h2Diff(w,ms),price,cost:price!=null&&y>0?price*(y+ws)/y:null,people:new Set(mm.map(m=>m.staff_id)).size,min:mm.reduce((s,m)=>s+mins2(m.start_at,m.end_at),0)}});
}
function yieldAvg(list){const by={};list.forEach(r=>{const k=r.item+"|"+r.product;const o=by[k]=by[k]||{item:r.item,product:r.product,n:0,y:0,ws:0,used:0,costW:0,costY:0};o.n++;o.y+=r.yield;o.ws+=r.waste;o.used+=r.used||0;if(r.cost!=null){o.costW+=r.cost*r.yield;o.costY+=r.yield}});return Object.values(by).map(o=>({...o,rate:o.y+o.ws>0?o.y/(o.y+o.ws):null,cost:o.costY>0?o.costW/o.costY:null})).sort((a,b)=>a.item.localeCompare(b.item,"ja")||a.product.localeCompare(b.product,"ja"))}
async function hqYieldPage(month="",tab="日報"){
 if(!h2CanReport())return hqHome();month=h2Month(month);setScreen("hqYieldPage",[month,tab]);
 const money=h2CanMoney();
 pageShell("歩留まり管理","製造日報・平均・月ごとの推移（確定した下処理）",`<div class="card"><label class="label">月</label><input type="month" class="input" value="${esc(month)}" ${seikaEventAttrs("change","hqYieldPage",[{__seikaValue:true},tab])}>
 <div class="h2Tabs" style="margin-top:8px">${["日報","平均","推移"].map(k=>`<button class="btn ${tab===k?"hqBtnYield":"btn2"}" ${btnAttr("hqYieldPage",[month,k])}>${k==="日報"?"製造日報":k==="平均"?"品目・仕掛品の平均":"年度の推移"}</button>`).join("")}</div>
 <button class="btn hqBtnExcelOut" style="width:100%;margin-top:8px" ${btnAttr("h2ExcelYield",[month])}>この月の歩留まりをExcelにする</button>
 <div class="small" style="margin-top:6px">歩留まり率＝出来高÷（出来高＋廃棄）。${money?"歩留まり原価（1kgあたり）＝単価×（出来高＋廃棄）÷出来高。単価は作業日の週の市場価格の平均です。":""}</div></div><div id="h2YdBody">${h2Loading()}</div>`);
 try{
  if(tab==="推移"){
   const fy=h2FiscalStart(month);const from=`${fy}-09-01`,to=`${fy+1}-08-31`;const list=await yieldData(from,to>hqToday()?hqToday():to);
   const months=[];for(let i=0;i<12;i++){const d=new Date(fy,8+i,1);months.push(`${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,"0")}`)}
   const keys=yieldAvg(list).map(o=>o.item+"|"+o.product);
   const cell=(k,m)=>{const l=list.filter(r=>r.date.startsWith(m)&&r.item+"|"+r.product===k);if(!l.length)return"—";const a=yieldAvg(l)[0];return `${pct2(a.rate)}${money&&a.cost!=null?`<div class="small">${hqKg(Math.round(a.cost))}円</div>`:""}`};
   h2Set("h2YdBody",`<div class="card" style="overflow-x:auto"><b>${fy}年度（${fy}年9月〜${fy+1}年8月）</b><table class="h2Tbl"><tr><th>原料 → 仕掛品</th>${months.map(m=>`<th>${Number(m.slice(5))}月</th>`).join("")}</tr>${keys.map(k=>`<tr><td>${esc(k.replace("|"," → "))}</td>${months.map(m=>`<td>${cell(k,m)}</td>`).join("")}</tr>`).join("")||'<tr><td>確定した下処理がありません</td></tr>'}</table></div>`);
   return;
  }
  const{from,to}=h2MonthRange(month);const list=await yieldData(from,to);
  if(tab==="平均"){
   h2Set("h2YdBody",`<div class="card" style="overflow-x:auto"><table class="h2Tbl"><tr><th>原料 → 仕掛品</th><th>回数</th><th>出来高kg</th><th>廃棄kg</th><th>歩留まり率</th>${money?"<th>歩留まり原価</th>":""}</tr>${yieldAvg(list).map(o=>`<tr><td>${esc(o.item)} → ${esc(o.product)}</td><td>${o.n}</td><td>${kg2(o.y)}</td><td>${kg2(o.ws)}</td><td>${pct2(o.rate)}</td>${money?`<td>${o.cost==null?"未計算":`${hqKg(Math.round(o.cost*10)/10)}円/kg`}</td>`:""}</tr>`).join("")||'<tr><td colspan="6">確定した下処理がありません</td></tr>'}</table><div class="small">平均の歩留まり率は、月の合計（出来高÷（出来高＋廃棄））で出しています。</div></div>`);
   return;
  }
  const days=[...new Set(list.map(r=>r.date))];
  h2Set("h2YdBody",days.map(d=>`<div class="card" style="overflow-x:auto"><b>${esc(hqDateLabel(d))}</b><table class="h2Tbl"><tr><th>原料 → 仕掛品</th><th>使用原料</th><th>出来高kg</th><th>廃棄kg</th><th>差</th><th>歩留まり率</th>${money?"<th>単価</th><th>歩留まり原価</th>":""}<th>作業</th></tr>${list.filter(r=>r.date===d).map(r=>`<tr><td>${esc(r.item)} → ${esc(r.product)}</td><td>${esc(r.usedText)}${r.used?`（${kg2(r.used)}kg）`:""}</td><td>${kg2(r.yield)}</td><td>${kg2(r.waste)}</td><td class="${r.diff&&Math.abs(r.diff.rate)>=0.1?"h2Red":""}">${r.diff?pct2(r.diff.rate):"—"}</td><td>${pct2(r.rate)}</td>${money?`<td>${r.price==null?"未計算":hqKg(r.price)}</td><td>${r.cost==null?"未計算":`${hqKg(Math.round(r.cost*10)/10)}円/kg`}</td>`:""}<td>${r.people}名 ${hm2(r.min)}</td></tr>`).join("")}</table></div>`).join("")||'<div class="notice">この月に確定した下処理はありません。</div>');
 }catch(e){h2Set("h2YdBody",`<div class="err">${esc(h2Err(e))}</div>`)}
}

/* --- 本社の品質評価一覧 --- */
async function qualityData(month){const{from,to}=h2MonthRange(month);return hqLots(`select=*&grade=not.is.null&hq_received_date=gte.${from}&hq_received_date=lte.${to}&order=hq_received_date.desc,confirmed_at.desc&limit=2000`)}
function qState(l){if(l.grade==="good")return"確認不要";if(l.quality_checked_at)return"確認済み";return l.purchase_staff?`${l.purchase_staff}さんの確認待ち`:"管理者の確認待ち"}
async function hqQualityPage(month="",only="all",msg=""){
 if(!h2CanReport()&&!roleIs(["hq_receiver"]))return hqHome();month=h2Month(month);setScreen("hqQualityPage",[month,only,msg]);
 pageShell("品質評価一覧","本社で評価した原料（直接入荷・石岡からの受け入れ）",`${okHtml(msg)}<div class="card"><label class="label">本社入荷の月</label><input type="month" class="input" value="${esc(month)}" ${seikaEventAttrs("change","hqQualityPage",[{__seikaValue:true},only])}>
 <div class="h2Tabs" style="margin-top:8px">${[["all","すべて"],["need","要確認・不良"],["wait","確認待ち"]].map(([k,l])=>`<button class="btn ${only===k?"hqBtnQuality":"btn2"}" ${btnAttr("hqQualityPage",[month,k])}>${l}</button>`).join("")}</div>
 ${h2CanReport()?`<button class="btn hqBtnExcelOut" style="width:100%;margin-top:8px" ${btnAttr("h2ExcelQuality",[month])}>この月の品質評価をExcelにする</button>`:""}</div><div id="h2QBody">${h2Loading()}</div><input id="h2QAddInput" type="file" accept="image/*" multiple style="display:none" ${seikaEventAttrs("change","h2QAddPhotosRun",[])}>`);
 try{
  let rows=await qualityData(month);let dis=new Set();
  if(roleIs(["admin","hq_worker"])&&authProfile?.id){try{(await sel2("hq_quality_dismiss_v1500",`select=lot_id&user_id=eq.${authProfile.id}&limit=5000`)).forEach(d=>dis.add(d.lot_id))}catch(e){}}
  if(only==="need")rows=rows.filter(l=>l.grade!=="good");if(only==="wait")rows=rows.filter(l=>l.grade!=="good"&&!l.quality_checked_at);
  const me=authProfile?.id;
  h2Set("h2QBody",`<div class="small" style="margin:4px 0 8px">${rows.length}件。要確認・不良は写真1枚以上が必須です。担当の仕入れ担当者が「確認済み」にします（担当がいないときは管理者）。管理者・本社社員は「確認しました」で自分のお知らせを消せます。</div>`+rows.map(l=>{
   const canCheck=l.grade!=="good"&&!l.quality_checked_at&&((roleIs(["buyer"])&&l.purchase_staff_profile_id===me)||(roleIs(["admin"])&&(!l.purchase_staff_profile_id||l.purchase_staff_profile_id===me)));
   const canDis=l.grade!=="good"&&roleIs(["admin","hq_worker"])&&!dis.has(l.id);
   const canAdd=l.grade!=="good"&&roleIs(["admin","hq_worker","hq_receiver"]);
   return `<div class="card" style="padding:10px 14px"><div class="itemHead"><div><b>${esc(l.item_name)}</b> ${hqGradeBadge(l.grade)} <span class="badge ${l.source_kind==="石岡から"?"normal":"warn"}">${l.source_kind==="石岡から"?"石岡からの受け入れ":"直接入荷"}</span><div class="small">${esc(l.hq_received_date||"")} ／ ${esc(l.supplier||"-")}${l.cooperative_name?` ／ ${esc(l.cooperative_name)}`:""} ／ 写真 ${(l.photo_paths||[]).length}枚 ／ 評価：${esc(l.evaluated_by_name||"")}</div>${(l.issues||[]).length||l.quality_memo?`<div class="small">${esc((l.issues||[]).join("・"))} ${esc(l.quality_memo||"")}</div>`:""}<div class="small"><b>${esc(qState(l))}</b>${l.quality_checked_at?`（${esc(l.quality_checked_by_name||"")} ${dt2(l.quality_checked_at)}）`:""}${dis.has(l.id)?" ／ お知らせ確認済み":""}</div>${l.grade!=="good"&&!(l.photo_paths||[]).length?`<div class="small" style="color:#b91c1c;font-weight:700">写真が保存されていません。${canAdd?"「写真を追加」から登録し直してください。":""}</div>`:""}</div></div>
   <div class="row" style="margin-top:6px">${(l.photo_paths||[]).length?`<button class="btn btn2" ${btnAttr("h2QPhotos",[l.id])}>写真</button>`:""}${canAdd&&(l.photo_paths||[]).length<5?`<button class="btn btn2" ${btnAttr("h2QAddPhotos",[l.id,month,only])}>写真を追加</button>`:""}<button class="btn btn2" ${btnAttr("hqLotPage",[l.qr_key])}>ロット</button>${canCheck?`<button class="btn hqBtnQuality" ${btnAttr("h2QCheck",[l.id,month,only])}>確認済みにする</button>`:""}${canDis?`<button class="btn btn2" ${btnAttr("h2QDismiss",[l.id,month,only])}>確認しました</button>`:""}</div><div id="hqPhotoView_${esc(l.id)}"></div></div>`}).join(""));
 }catch(e){h2Set("h2QBody",`<div class="err">${esc(h2Err(e))}</div>`)}
}
let h2QAddTarget=null;
function h2QAddPhotos(id,m,o){h2QAddTarget={id,m,o};const i=document.getElementById("h2QAddInput");if(i){i.value="";i.click()}}
async function h2QAddPhotosRun(){
 const input=document.getElementById("h2QAddInput"),files=[...(input?.files||[])],t=h2QAddTarget;if(input)input.value="";if(!files.length||!t)return;
 v161ShowProcessing("写真を保存しています");
 try{const paths=[];for(const f of files){const p=await v1102CompressPhoto(f);paths.push(await hqUpload(t.id,p.blob));if(p.preview)URL.revokeObjectURL(p.preview)}
  await r2("hq_add_quality_photos_v1199c80",{p_lot_id:t.id,p_photo_paths:paths});v161HideProcessing();return hqQualityPage(t.m,t.o,`写真を${paths.length}枚追加しました`)}
 catch(e){v161HideProcessing();alert(h2Err(e))}
}
async function h2QPhotos(id){document.getElementById("hqPhotoView")?.removeAttribute("id");const b=document.getElementById("hqPhotoView_"+id);if(!b)return;b.id="hqPhotoView";await hqShowPhotos(id);b.id="hqPhotoView_"+id}
async function h2QCheck(id,m,o){try{await r2("hq_quality_check_v1500",{p_lot_id:id});return hqQualityPage(m,o,"確認済みにしました")}catch(e){alert(h2Err(e))}}
async function h2QDismiss(id,m,o){try{await r2("hq_quality_dismiss_v1500",{p_lot_id:id});return hqQualityPage(m,o,"お知らせを消しました")}catch(e){alert(h2Err(e))}}

/* --- Excel出力 --- */
function sheet(wb,name,aoa,w){const s=XLSX.utils.aoa_to_sheet(aoa);s["!cols"]=(aoa[0]||[]).map((_,i)=>({wch:Array.isArray(w)?(w[i]||12):(w||14)}));let nm=String(name).replace(/[\\/?*\[\]:]/g,"").slice(0,31);for(let i=2;(wb.SheetNames||[]).includes(nm);i++)nm=String(name).replace(/[\\/?*\[\]:]/g,"").slice(0,28)+"_"+i;XLSX.utils.book_append_sheet(wb,s,nm)}
async function excelOut(kind,month,outWb){
 if(roleIs(["hq_prep","hq_receiver"]))return hqHome();
 if(typeof XLSX==="undefined")return alert("Excel機能を読み込めませんでした");
 month=h2Month(month);const{from,to,toCap}=h2MonthRange(month);const label=h2MonthLabel(month),money=h2CanMoney();const wb=outWb||XLSX.utils.book_new();let title="";
 try{
  if(kind==="stock"){
   title="在庫";const[moves,stock]=await Promise.all([hqMonthMoves(month),hqLots("select=*&status=eq.在庫あり&order=item_name.asc,hq_received_date.asc&limit=5000")]);
   sheet(wb,"本社在庫（現在）",[["品名","本社ロットNo.","元ロットNo.","入荷区分","数量","単位","量目","仕入先","産地","単協名","本社入荷日","石岡入荷日","品質評価"]].concat(stock.map(l=>[l.item_name,l.lot_no,l.source_lot_no||"",l.source_kind,Number(l.current_qty),l.unit,l.pack_weight||"",l.supplier||"",l.origin||"",l.cooperative_name||"",l.hq_received_date||"",l.ishioka_received_date||"",HQ_GRADE[l.grade]||""])));
   sheet(wb,"入出庫",[["日時","区分","品名","本社ロットNo.","数量","単位","前","後","出庫先","理由","メモ","担当"]].concat(moves.map(m=>[new Date(m.occurred_at).toLocaleString("ja-JP"),m.movement_type+(m.cancelled_at?"（取消済み）":""),m.item_name||"",m.lot_no||"",Number(m.qty),m.unit||"",m.before_qty==null?"":Number(m.before_qty),m.after_qty==null?"":Number(m.after_qty),m.destination||"",m.reason||"",m.memo||"",m.user_name||""])));
  }else if(kind==="counts"){
   title="在庫入力";const c=await sel2("hq_stock_counts_v1500",`select=*&count_date=gte.${from}&count_date=lte.${to}&order=count_date.asc,kind.asc,item_name.asc&limit=10000`);
   sheet(wb,"在庫入力",[["日付","区分","品名","入れ数kg×ケース数","ケース合計","合計kg","手入力","入力者"]].concat(c.map(x=>[x.count_date,x.kind,x.item_name,(x.lines||[]).map(l=>`${l.pack_kg}kg×${l.cases}`).join("、"),Number(x.total_cases),Number(x.total_kg),x.manual?"手入力":"",x.user_name||""])));
  }else if(kind==="table"){
   title="在庫表";if(from>hqToday())throw new Error("先の月です");const t=await hqTableData(from,toCap,true);const rs=t?.rows||[],ds=rs[0]?.values?.map(v=>v.date)||[];
   sheet(wb,`在庫表`,[["品名","区分"].concat(ds)].concat(rs.map(r=>[r.item_name,r.kind].concat(r.values.map(v=>v.kg==null?"":Number(v.kg))))).concat([["合計kg",""].concat(ds.map((_,i)=>rs.reduce((s,r)=>s+(r.values[i].kg==null?0:Number(r.values[i].kg)),0)))]),[16,8]);
  }else if(kind==="waste"){
   title="廃棄";const rows=(await wasteData(month)).filter(r=>!r.cancelled_at);let pm={};if(money&&rows.length)pm=await h2Prices(from,to,[...new Set(rows.map(r=>r.item_name))]);
   const amt=r=>{const p=h2PriceOf(pm,r.item_name,r.waste_date);return p==null?"":Math.round(p*Number(r.kg))};
   sheet(wb,"廃棄一覧",[["日付","区分","品目","kg","数量","単位","ロットNo.",...(money?["単価（円/kg）","金額"]:[]),"メモ","入力者"]].concat(rows.map(r=>[r.waste_date,r.kind,r.item_name,Number(r.kg),r.qty==null?"":Number(r.qty),r.unit||"",r.lot_no||"",...(money?[h2PriceOf(pm,r.item_name,r.waste_date)??"未計算",amt(r)]:[]),r.memo||"",r.user_name||""])));
   const agg={};rows.forEach(r=>{const k=r.kind+"|"+r.item_name;const o=agg[k]=agg[k]||{kind:r.kind,item:r.item_name,kg:0,yen:0};o.kg+=Number(r.kg);const a=amt(r);if(a!=="")o.yen+=a});
   sheet(wb,"区分別・品目別",[["区分","品目","kg",...(money?["金額"]:[])]].concat(Object.values(agg).sort((a,b)=>a.kind.localeCompare(b.kind,"ja")||b.kg-a.kg).map(o=>[o.kind,o.item,Math.round(o.kg*10)/10,...(money?[o.yen]:[])])));
  }else if(kind==="yield"){
   title="歩留まり";const list=await yieldData(from,to);
   sheet(wb,"製造日報",[["作業日","原料","仕掛品","使用原料","使用原料kg","出来高kg","廃棄kg","差kg","差%","歩留まり率",...(money?["単価（円/kg）","歩留まり原価（円/kg）"]:[]),"人数","人×時間（分）"]].concat(list.map(r=>[r.date,r.item,r.product,r.usedText,Math.round((r.used||0)*10)/10,r.yield,r.waste,r.diff?Math.round(r.diff.kg*10)/10:"",r.diff?Math.round(r.diff.rate*1000)/10:"",r.rate==null?"":Math.round(r.rate*1000)/10,...(money?[r.price??"未計算",r.cost==null?"未計算":Math.round(r.cost*10)/10]:[]),r.people,r.min])));
   sheet(wb,"平均",[["原料","仕掛品","回数","出来高kg","廃棄kg","歩留まり率%",...(money?["歩留まり原価（円/kg）"]:[])]].concat(yieldAvg(list).map(o=>[o.item,o.product,o.n,o.y,o.ws,o.rate==null?"":Math.round(o.rate*1000)/10,...(money?[o.cost==null?"未計算":Math.round(o.cost*10)/10]:[])])));
   const fy=h2FiscalStart(month);const all=await yieldData(`${fy}-09-01`,`${fy+1}-08-31`>hqToday()?hqToday():`${fy+1}-08-31`);const months=[];for(let i=0;i<12;i++){const d=new Date(fy,8+i,1);months.push(`${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,"0")}`)}
   const keys=yieldAvg(all).map(o=>[o.item,o.product]);
   sheet(wb,`${fy}年度の推移（歩留まり率%）`,[["原料","仕掛品"].concat(months.map(m=>`${Number(m.slice(5))}月`))].concat(keys.map(([i,p])=>[i,p].concat(months.map(m=>{const l=all.filter(r=>r.date.startsWith(m)&&r.item===i&&r.product===p);if(!l.length)return"";const a=yieldAvg(l)[0];return a.rate==null?"":Math.round(a.rate*1000)/10})))),[14,16]);
  }else if(kind==="usage"){
   title="使用数量";const{items,countDays}=await X.usageData(month);
   sheet(wb,"月のまとめ",[["品目","区分","使用kg（月計）","ケース（月計）","大型容器kg（月計）","廃棄kg","原料のまま出荷kg","稼働日","稼働日平均kg"]].concat(items.map(it=>{const t=X.usageTotals(it);return[it.name,it.kind==="QR"?"QR":"原料",Math.round(t.kg*10)/10,Math.round(t.cases*100)/100,Math.round((t.kgu||0)*10)/10,Math.round((t.waste||0)*10)/10,Math.round((t.rawout||0)*10)/10,t.workDays,t.avgKg==null?"":Math.round(t.avgKg*10)/10]})));
   const ds=items[0]?.days.map(d=>d.date)||[];
   sheet(wb,"日ごと（kg）",[["品目","区分"].concat(ds)].concat(items.map(it=>[it.name,it.kind==="QR"?"QR":"原料"].concat(it.days.map(d=>d.kg==null?"":Math.round(d.kg*10)/10)))).concat([["稼働日",""].concat(ds.map(d=>countDays.includes(String(d))?"○":""))]),[16,8]);
  }else if(kind==="quality"){
   title="品質評価";const rows=await qualityData(month);
   sheet(wb,"品質評価",[["本社入荷日","評価した場所","品目","仕入先","単協名","産地","評価","内容","メモ","写真枚数","評価した人","確認の状況","確認した人","確認日時"]].concat(rows.map(l=>[l.hq_received_date||"",l.source_kind==="石岡から"?"石岡からの受け入れ":"直接入荷",l.item_name,l.supplier||"",l.cooperative_name||"",l.origin||"",HQ_GRADE[l.grade]||"",(l.issues||[]).join("・"),l.quality_memo||"",(l.photo_paths||[]).length,l.evaluated_by_name||"",qState(l),l.quality_checked_by_name||"",l.quality_checked_at?new Date(l.quality_checked_at).toLocaleString("ja-JP"):""])));
  }else if(kind==="worktime"){
   title="作業時間";const{works,mem}=await X.workTimeData(month);const{per,perDay,perTask}=X.workTimeSummary(works,mem);const wm=new Map(works.map(w=>[w.id,w]));
   sheet(wb,"人ごと",[["名前","班","日数","作業（分）","清掃（分）","合計（分）","合計（時間）"]].concat([...per.values()].map(p=>[p.name,p.team,p.days.size,p.work,p.clean,p.work+p.clean,Math.round((p.work+p.clean)/6)/10])));
   sheet(wb,"日ごとの作業人数",[["日付","人数","人×時間（分）"]].concat([...perDay.entries()].sort().map(([d,v])=>[d,v.people.size,v.min])));
   sheet(wb,"作業ごと",[["作業","回数","人数（のべ）","人×時間（分）"]].concat([...perTask.entries()].map(([k,v])=>[k,v.count.size,v.people.size,v.min])));
   if(h2CanBoss()){const{per:cp,prod}=X.workCompare(works,mem);
    sheet(wb,"個人の比較（時間）",[["名前","班","日数","下処理（分）","ほかの作業（分）","合計（分）","合計（時間）","1日平均（分）"]].concat([...cp.values()].map(p=>{const t=p.prep+p.other;return[p.name,p.team,p.days.size,p.prep,p.other,t,Math.round(t/6)/10,Math.round(t/Math.max(1,p.days.size))]})));
    const rows=[["下処理（仕掛品）","名前","班","回数","作業時間（分）","出来高（分けた分・kg）","1時間あたり（kg）"]];for(const[name,g]of prod)for(const q of g.values())rows.push([name,q.name,q.team,q.works.size,q.min,Math.round(q.kg*10)/10,X.kgh(q)]);
    sheet(wb,"個人の比較（下処理）",rows)}
   sheet(wb,"記録",[["作業日","作業","仕掛品","作業場所","名前","班","作業／清掃","開始","終了","分","終わり方","修正した人"]].concat(mem.map(m=>{const w=wm.get(m.work_id)||{};return[w.work_date||"",w.task_name||"",w.product_name||"",w.place||"",m.staff_name,m.team||"",m.phase,new Date(m.start_at).toLocaleString("ja-JP"),m.end_at?new Date(m.end_at).toLocaleString("ja-JP"):"（終わっていない）",mins2(m.start_at,m.end_at),m.end_reason||"",m.fixed_by_name||""]})));
  }
  if(outWb)return title;
  XLSX.writeFile(wb,`本社_${title}_${label}.xlsx`);
 }catch(e){if(outWb)throw e;alert(h2Err(e))}
}
X.excelOut=excelOut;
async function hqExcelPage(month=""){
 if(!h2CanReport())return hqHome();month=h2Month(month);setScreen("hqExcelPage",[month]);
 const b=(k,l,s)=>`<button class="btn hqBtnExcelOut" style="width:100%;margin-top:8px" ${btnAttr("h2ExcelOut",[k,month])}>${l}<br><span style="font-size:13px;font-weight:700">${s}</span></button>`;
 pageShell("Excel出力","月を選んで、Excelを作ります",`<div class="card"><label class="label">月</label><input type="month" class="input" value="${esc(month)}" ${seikaEventAttrs("change","hqExcelPage",[{__seikaValue:true}])}><div class="small" style="margin-top:6px">ファイル名の例：本社_歩留まり_${esc(h2MonthLabel(month))}.xlsx</div></div>
 <div class="card">${b("stock","在庫（現在・入出庫）","いまの本社在庫と、その月の入出庫")}${b("counts","在庫入力（原料・仕掛品）","その月に入力した在庫")}${b("table","在庫表","QR品目・原料・仕掛品の日ごとのkg")}${b("waste","廃棄（区分別）","下処理ロス・原料出しロス・原料廃棄")}${b("yield","歩留まり","製造日報・平均・年度の推移")}${b("usage","使用数量","品目別・日ごと・稼働日平均")}${b("quality","品質評価","本社で評価した原料")}${b("worktime","作業時間・作業人数","人×時間・日ごとの人数")}</div>`);
}
function h2ExcelOut(k,m){return excelOut(k,m)}
function h2ExcelWaste(m){return excelOut("waste",m)}
function h2ExcelYield(m){return excelOut("yield",m)}
function h2ExcelQuality(m){return excelOut("quality",m)}
Object.assign(window,{h2QAddPhotos,h2QAddPhotosRun,hqWastePage,h2SaveRawLoss,h2CancelWaste,h2Dispose,hqPricePage,hqYieldPage,hqQualityPage,h2QPhotos,h2QCheck,h2QDismiss,hqExcelPage,h2ExcelOut,h2ExcelWaste,h2ExcelYield,h2ExcelQuality});
})();

/* ===== つなぎ込み（ホーム・在庫管理・ロット画面・戻る・石岡ホームのお知らせ） ===== */
(function(){
"use strict";
const X=window.__h2;const{H2,sel2,btnAttr,roleIs,h2CanPrep,h2CanBoss,h2CanRaw,h2CanMoney,h2CanReport,h2Stage2,h2Err}=X;

/* 出庫は v1500（在庫反映オンの後は下処理への使用出庫を止める） */
hqRpc=async function(name,args){return callRpc(name==="hq_outbound_v1400"?"hq_outbound_v1500":name,args)};window.hqRpc=hqRpc;
hqCanOut=function(){return H2.s2?roleIs(["admin","hq_worker","hq_receiver"]):roleIs(["admin","hq_worker","hq_prep","hq_receiver"])};window.hqCanOut=hqCanOut;

/* ロットの画面：出庫先の絞り込み・廃棄 */
const lotBase=hqLotPage;
hqLotPage=async function(key,msg=""){
 await h2Stage2();
 const r=await lotBase.apply(this,arguments);
 try{
  const sel=document.getElementById("hqDest");
  if(sel){
   const onlyRaw=H2.s2;
   if(onlyRaw){[...sel.options].forEach(o=>{if(o.value&&o.value!=="原料出し")o.remove()});sel.value="原料出し";const b=sel.closest(".card")?.querySelector("b");if(b)b.textContent="原料出し（原料のまま出荷）"}
   else if(roleIs(["hq_prep","hq_receiver"])){[...sel.options].forEach(o=>{if(o.value&&o.value!=="下処理"&&o.value!=="原料出し")o.remove()})}
  }
  if(h2CanRaw()&&!hqViewOnly()){
   const l=(await hqLots(`select=id,qr_key,status,current_qty,unit&or=(qr_key.eq.${encodeURIComponent(key)},lot_no.eq.${encodeURIComponent(key)})&limit=1`))[0];
   if(l&&l.status==="在庫あり"&&currentScreen==="hqLotPage"){
    const hist=[...document.querySelectorAll(".wrap .card")].find(c=>c.querySelector("b")?.textContent==="このロットの履歴");
    const html=`<details class="card" id="h2DisposeCard"><summary><b>廃棄（原料廃棄・在庫から減らす）</b></summary><label class="label" style="margin-top:8px">廃棄する数量（${l.unit==="kg"?"kg":"ケース"}・在庫 ${hqQty(l.current_qty)}）</label><input id="h2DsQ" class="input" inputmode="decimal"><label class="label" style="margin-top:8px">理由・メモ</label><input id="h2DsM" class="input" placeholder="例：腐敗"><button class="btn hqBtnWaste" style="width:100%;margin-top:10px" ${btnAttr("h2Dispose",[l.id,l.qr_key,l.unit,Number(l.current_qty)])}>廃棄する</button><div class="small" style="margin-top:4px">廃棄一覧の「原料廃棄」に入ります。</div></details>`;
    if(hist)hist.insertAdjacentHTML("beforebegin",html);
   }
  }
 }catch(e){}
 return r;
};
window.hqLotPage=hqLotPage;

/* 在庫管理のボタン */
hqStockHubItems=function(){
 const s2=H2.s2;
 return[["hqBtnStock","hqStockPage","本社在庫",'<span id="hqHubStockCount"></span>'],["hqBtnTable","hqTablePage","在庫表","QR品目・原料・仕掛品（kg）"],hqCanNormal()?["hqBtnNormal","hqNormalPage","在庫入力","原料・仕掛品"]:null,
  hqCanOut()&&!s2&&roleIs(["admin","hq_worker","hq_prep"])?["hqBtnOut","hqOutPage","使用出庫","在庫反映オフの間だけ"]:null,
  h2CanRaw()?["hqBtnWaste","hqWastePage","原料出しロスの入力・廃棄一覧"]:null,
  h2CanReport()?["hqBtnUsage","hqUsagePage","品目別使用数量"]:null,
  h2CanBoss()?["hqBtnTake","hqStocktakePage","棚卸し"]:null,
  ["hqBtnHistory","hqHistoryPage","入出庫履歴"]].filter(Boolean);
};
window.hqStockHubItems=hqStockHubItems;
const hubBase=hqStockHub;hqStockHub=async function(...a){await h2Stage2();const r=hubBase.apply(this,a);try{const s=document.querySelector(".head .sub");if(s)s.textContent="本社の在庫・在庫入力・使用数量・棚卸し・入出庫履歴"}catch(e){}return r};window.hqStockHub=hqStockHub;

/* 本社ホーム（役割ごと） */
hqHome=async function(msg=""){
 if(roleIs(["hq_prep"]))return hqPrepHome(msg);
 setScreen("hqHome",[msg]);
 const b=(cls,act,label,sub="")=>`<button class="btn ${cls}" ${btnAttr(act,[])}>${label}${sub?`<br><span style="font-size:14px;font-weight:700">${sub}</span>`:""}</button>`;
 const boss=h2CanBoss(),recv=roleIs(["hq_receiver"]),view=!boss&&!recv;
 const btns=[
  b("hqBtnPending","hqPendingPage","入荷待ち原料",'石岡からの移動・直接入荷<br><span id="hqPendingCount">…</span>'),
  boss||recv?b("hqBtnScan","hqScanPage","QR読み取り（受け入れ・出庫）","受け入れ・使用出庫"):"",
  b("hqBtnStockHub","hqStockHub","在庫管理",'在庫・在庫表・入出庫履歴<br><span id="hqStockCount">…</span>'),
  hqEntryHubItems().length&&(boss||recv)?b("hqBtnEntryHub","hqEntryHub","入荷登録・品目","直接入荷・品目の追加"):"",
  boss?b("hqBtnPrepCheck","hqPrepCheckPage","下処理の確認",'入力の確認・確定<br><span id="h2PrepCount">…</span>'):"",
  b("hqBtnQuality","hqQualityPage","品質評価一覧","受け入れ時の品質評価"),
  h2CanReport()?b("hqBtnYield","hqYieldPage","歩留まり管理","製造日報・平均・推移"):"",
  h2CanReport()?b("hqBtnWaste","hqWastePage","廃棄一覧","原料・仕掛品の廃棄"):"",
  h2CanMoney()&&h2CanReport()?b("hqBtnPrice","hqPricePage","仕入れ価格表","市場価格の週平均"):"",
  boss?b("hqBtnMaster","hqPrepMasterPage","下処理マスタ","仕掛品の登録・使用期限"):"",
  boss?b("hqBtnStaff","hqStaffPage","スタッフQR","登録・印刷・作業時間"):"",
  !boss&&h2CanReport()?b("hqBtnTime","hqWorkTimePage","作業時間","人ごと・作業ごとの時間"):"",
  h2CanReport()?b("hqBtnExcelOut","hqExcelPage","Excel出力","月ごとの集計をExcelに"):"",
  b("hqBtnGuide","v195RoleGuidePage","操作ガイド","使い方の説明")
 ].join("");
 pageShell("SEIKA＋",`本社 / ${esc(db.user||"")}（${esc(ROLE[db.role]||db.role)}）`,`${okHtml(msg)}${hqSwitchHtml()}<div id="h2HomeNotice"></div>${hqViewOnly()?'<div class="card notice">本社の画面は見るだけです（入力・出庫は本社のアカウントと管理者が行います）。</div>':""}<div class="homePrimary hqHomeGrid">${btns}</div>`,{noBack:true});
 h2Stage2();
 Promise.all([hqLots("select=id,source_kind&status=eq.入荷待ち"),hqLots("select=id&status=eq.在庫あり")]).then(([p,s])=>{
  const a=document.getElementById("hqPendingCount"),c=document.getElementById("hqStockCount");const mv=p.filter(x=>x.source_kind==="石岡から").length,dr=p.length-mv;
  if(a)a.textContent=`移動中 ${mv}件${dr?`・直接入荷 ${dr}件`:""}`;if(c)c.textContent=`本社在庫 ${s.length}ロット`;
 }).catch(()=>{});
 if(boss){
  try{
   const[un,live,q]=await Promise.all([sel2("hq_works_v1500","select=id,work_date&kind=eq.下処理&confirm_status=eq.未確定&status=neq.取消&limit=500"),sel2("hq_works_v1500","select=id&status=in.(作業中,入力待ち,清掃中)&limit=500"),hqLots("select=id&grade=in.(review,bad)&quality_checked_at=is.null&limit=500")]);
   let dis=new Set();if(authProfile?.id&&q.length){try{(await sel2("hq_quality_dismiss_v1500",`select=lot_id&user_id=eq.${authProfile.id}&limit=5000`)).forEach(d=>dis.add(d.lot_id))}catch(e){}}
   const old=un.filter(w=>w.work_date<hqToday()).length,qn=q.filter(l=>!dis.has(l.id)).length;
   const c=document.getElementById("h2PrepCount");if(c)c.textContent=`作業中 ${live.length}件・未確定 ${un.length}件`;
   const box=document.getElementById("h2HomeNotice");if(box&&currentScreen==="hqHome")box.innerHTML=(old?`<div class="card err" style="cursor:pointer" ${btnAttr("hqPrepCheckPage",[])}><b>前の日から未確定の下処理が ${old}件あります。</b>「下処理の確認」で確定してください。</div>`:"")+(qn?`<div class="card notice" style="cursor:pointer" ${btnAttr("hqQualityPage",["","need"])}><b>要確認・不良の品質評価が ${qn}件あります。</b>品質評価一覧で「確認しました」を押すと消えます。</div>`:"");
  }catch(e){}
 }
};
window.hqHome=hqHome;

/* 戻る */
const BACK={hqPrepNew:()=>hqPrepHome(),hqOpScanPage:()=>hqPrepHome(),hqWorkPage:()=>h2CanBoss()?hqPrepCheckPage():hqPrepHome(),hqPrepHome:()=>home(),hqPrepConfirmPage:()=>hqPrepCheckPage(),
 hqPrepCheckPage:()=>home(),hqPrepMasterPage:()=>home(),hqStaffPage:()=>home(),hqStaffPrintPage:()=>hqStaffPage(),hqTaskPlacePage:()=>hqStaffPage(),hqWorkTimePage:()=>h2CanBoss()?hqStaffPage():home(),
 hqWastePage:()=>home(),hqPricePage:()=>home(),hqYieldPage:()=>home(),hqQualityPage:()=>home(),hqExcelPage:()=>home(),hqUsagePage:()=>hqStockHub(),hqStocktakePage:()=>hqStockHub(),hqStocktakeEdit:()=>hqStocktakePage()};
const backBase=goBack;
goBack=function(...a){const f=BACK[currentScreen];if(f){h2StopReader();return f()}return backBase.apply(this,a)};window.goBack=goBack;

/* 石岡ホーム：本社で受け入れたときの数量の差（管理者・青果社員）と、本社の品質評価の確認待ち（担当の仕入れ担当者） */
async function h2IshiokaNotice(){
 if(currentScreen!=="home"||!db?.user||hqSite()==="honsha"||hqIsHqRole()||document.getElementById("h2IshNotice"))return;
 const main=document.querySelector("#app main");if(!main)return;
 const box=document.createElement("div");box.id="h2IshNotice";main.insertBefore(box,document.getElementById("hqIshiokaFoot")?.nextSibling||main.firstChild);
 let html="";
 try{
  if(roleIs(["admin","worker"])){
   const since=hqAddDays(hqToday(),-30);
   const lots=await hqLots(`select=id,lot_no,item_name,unit,planned_qty,received_qty,hq_received_date,source_lot_no,confirmed_by_name&source_kind=eq.石岡から&status=in.(在庫あり,在庫なし)&hq_received_date=gte.${since}&order=hq_received_date.desc&limit=300`);
   const diff=lots.filter(l=>Number(l.planned_qty)!==Number(l.received_qty));
   if(diff.length){const acks=await sel2("hq_diff_acks_v1500",`select=lot_id&lot_id=in.(${diff.map(l=>l.id).join(",")})`);const ak=new Set(acks.map(a=>a.lot_id));const list=diff.filter(l=>!ak.has(l.id));
    if(list.length)html+=`<div class="card" style="border:2px solid #d97706;background:#fffbeb"><b>本社で受け入れた数が、石岡で予定した数と違います（${list.length}件）</b><div class="small">石岡の在庫は自動では直しません。必要なら実数調整をしてください。</div>${list.slice(0,8).map(l=>`<div class="itemHead" style="padding:6px 0;border-top:1px solid #fde68a"><div><b>${esc(l.item_name)}</b><div class="small">${esc(l.hq_received_date||"")} ／ 石岡ロット ${esc(l.source_lot_no||"")} ／ 予定 ${hqQty(l.planned_qty)}${l.unit==="kg"?"kg":"ケース"} → 本社 ${hqQty(l.received_qty)}${l.unit==="kg"?"kg":"ケース"}（${esc(l.confirmed_by_name||"")}）</div></div><button class="btn btn2" ${btnAttr("h2DiffAck",[l.id])}>確認しました</button></div>`).join("")}${list.length>8?`<div class="small">ほか ${list.length-8}件</div>`:""}</div>`}
  }
  if(roleIs(["buyer","admin"])&&authProfile?.id){
   const q=await hqLots(`select=id&grade=in.(review,bad)&quality_checked_at=is.null${roleIs(["buyer"])?`&purchase_staff_profile_id=eq.${authProfile.id}`:"&purchase_staff_profile_id=is.null"}&limit=200`);
   if(q.length)html+=`<div class="card notice" style="cursor:pointer" ${btnAttr("h2OpenHqQuality",[])}><b>本社の品質評価で、確認待ちが ${q.length}件あります。</b>${roleIs(["buyer"])?"担当の原料です。":"担当の仕入れ担当者がいない原料です。"}押すと本社の品質評価一覧を開きます。</div>`;
  }
 }catch(e){}
 box.innerHTML=html;
}
async function h2DiffAck(id){try{await callRpc("hq_diff_ack_v1500",{p_lot_id:id});document.getElementById("h2IshNotice")?.remove();h2IshiokaNotice()}catch(e){alert(h2Err(e))}}
function h2OpenHqQuality(){return hqQualityPage("","wait")}
(()=>{const app=document.getElementById("app");if(!app||window.h2IshObserver)return;window.h2IshObserver=new MutationObserver(()=>{if(currentScreen==="home"&&!document.getElementById("h2IshNotice"))h2IshiokaNotice()});window.h2IshObserver.observe(app,{childList:true,subtree:true})})();

Object.assign(window,{h2DiffAck,h2OpenHqQuality});
})();

/* ===== 操作ガイド（第2段階） ===== */
(function(){
"use strict";
try{
 const G={
  prepStart:{title:"下処理を始める（パートさん）",where:"ホーム（下処理）→「＋ 新しい下処理を始める」",steps:["原料の貼り紙のQRを読みます。原料が2つ以上なら、続けて読みます。","仕掛品のボタンを押します。","作業場所のボタンを押します。","作業する人全員の名前のQRを読みます。","「作業開始」を押します（「作業開始」のQRを読んでもよいです）。"],check:"ホームの一覧に、作業が緑色で出ます。",caution:"同じ人は、1つの作業にしか入れません。"},
  prepEnd:{title:"下処理を終える（パートさん）",where:"ホーム（下処理）→ 作業の「開く」",steps:["「作業終了」を押します。","使った原料の数を入れます（大きい容器はkg、それ以外はケース。0.5なども入れられます）。","廃棄のkgを入れます。無ければ 0 です。","出来高のkgを入れます。","「保存して ⑨ 清掃へ」を押します。","「⑨ 清掃へ」を押すと、作業した人全員が清掃に移ります（仕掛品ラベルの印刷は、今は使いません）。","清掃が終わったら「清掃終了」を押します。"],check:"作業した人は、全員そろって清掃に移ります。",caution:"確定は本社社員がします。間違えたときは本社社員に言ってください。"},
  prepJoin:{title:"途中から入る・抜ける（パートさん）",where:"作業の画面",steps:["途中から入る人：「途中から入る人を追加」を押して、名前のQRを読みます。","抜ける人：名前の横の「抜ける」を押します。","ほかの作業に移るときは、先に「抜ける」を押します。"],check:"「いまの作業者」に名前が出ます。",caution:""},
  prepOther:{title:"ほかの作業・清掃だけを記録する",where:"ホーム（下処理）→「ほかの作業を始める」「清掃だけ始める」",steps:["作業名（清掃のときはなし）と作業場所を選びます。","作業する人の名前のQRを読みます。","「作業開始」（清掃は「清掃開始」）を押します。","終わったら「作業終了」（清掃は「清掃終了」）を押します。"],check:"作業時間に記録されます。",caution:"大掃除など、清掃だけのときは「清掃」のQRでも始められます。"},
  prepCheck:{title:"下処理を確認して確定する（本社社員）",where:"本社ホーム →「下処理の確認」",steps:["「未確定」の一覧から、下処理の「確認して確定」を押します。","使用原料・廃棄・出来高を確かめます。差（使用−出来高−廃棄）が10%以上のときは赤く出ます。","違っていれば直して「この内容で確定する」を押します。","確定した後に直すときは、理由を入れて「直して確定し直す」を押します。取り消すときは「この下処理を取り消す」を使います。"],check:"確定すると、廃棄一覧（下処理ロス）・歩留まり・製造日報に入ります。在庫反映がオンなら、原料の在庫も減ります。",caution:"確定が次の日になっても、下処理をした日の数字になります。前の日から未確定のものは、ホームにお知らせが出ます。"},
  stage2:{title:"第2段階の在庫反映をオンにする（管理者・実用開始の日）",where:"本社ホーム →「下処理の確認」→ いちばん上",steps:["説明・練習のあいだは「オフ」のままにします（確定しても原料の在庫は減らず、使用出庫が使えます）。","実用を始める日に「オンにする（実用開始）」を押します。","オンにすると、使用出庫のボタンが消え、下処理の確定で原料の在庫が減ります。"],check:"「第2段階の在庫反映：オン（実用中）」と出ます。",caution:"オンにする前に、練習で作った下処理は取り消しておくと、集計がきれいです。"},
  master:{title:"下処理マスタ（仕掛品）を登録する",where:"本社ホーム →「下処理マスタ」",steps:["原料の品目を入れます（名前を入れると候補が出ます。候補にない名前もそのまま入れられます）。","仕掛品の名前・初期入れ数kg・使用期限の日数（ふつうは2日）を入れて「追加する」を押します。","使わなくなったら「使わない」を押します（削除はしません）。"],check:"パートさんの下処理で、その原料を読んだときに候補に出ます。",caution:"初期入れ数kgは、在庫入力で仕掛品を選んだときの入れ数になります。"},
  staff:{title:"スタッフを登録・削除する（スタッフQR）",where:"本社ホーム →「スタッフQR」→「スタッフ登録」",steps:["入社したとき：班名を選び、名前を入れて「登録する」を押します（グループは班に合わせて自動で選ばれます）。","グループや班を変えるとき：名前の横の「変更」を押します。","退職したとき：「削除」を押します。","「QRの印刷」で、グループごとの一覧ボードと操作用QRを印刷します。"],check:"登録するとスタッフQRができます。",caution:"削除しても、過去の作業時間は名前つきで残ります。登録・削除・グループ変更のあとは、一覧ボードを印刷し直してください。"},
  tasks:{title:"作業名・作業場所を増やす",where:"スタッフQR →「作業名・作業場所」",steps:["作業名（下処理以外の作業）を入れて「追加」を押します。","作業場所を入れて「追加」を押します。","使わなくなったものは「非表示にする」を押します（あとで「表示する」で戻せます）。","いらないものは「削除」を押します。これまでの作業の記録に書かれた名前はそのまま残ります。"],check:"作業を始める画面のボタンに出ます。",caution:""},
  worktime:{title:"作業時間を見る・読み忘れを直す",where:"スタッフQR →「作業時間」／ 作業の画面",steps:["月を選ぶと、人ごと・日ごとの人数・作業ごとの人×時間が出ます。","読み忘れは、作業の画面の「時刻を直す」「読み忘れた人を追加する」で直します。","「この月の作業時間をExcelにする」で月次のExcelを作ります。本社社員・管理者が作ると「個人の比較」のシートも入ります。","「個人の比較」で開始日と終了日を選ぶと、人ごとの作業時間（下処理・ほかの作業・合計・1日平均）と、下処理ごとの1時間あたりの出来高kgを、人ごとに並べて比べられます（本社社員・管理者だけ）。"],check:"",caution:"時給はアプリに持ちません。荷受けは対象外です。個人の比較には清掃の時間を入れません。1時間あたりの出来高は確定した下処理だけで計算し、何人かで作業したときは作業時間の割合で分けます。"},
  stockInput:{title:"在庫入力（原料・仕掛品）",where:"本社ホーム → 在庫管理 →「在庫入力」",steps:["日付を確かめます（ふだんは今日）。","上の「原料」「仕掛品」で切り替えます。","1行に「入れ数kg × ケース数」を入れます。入れ数がちがう箱は「＋ 入れ数を追加」で行を増やします。","マスタに無い仕掛品は「マスタに無い仕掛品を手入力」で入れます。","「保存する」を押します。"],check:"在庫表に、原料・仕掛品として出ます。",caution:"同じ日に入れ直すと上書きです。全部の行を空にして保存すると、その日の入力を消します。手入力の仕掛品はマスタに追加されません。"},
  waste:{title:"廃棄一覧・原料出しロス・原料廃棄",where:"本社ホーム →「廃棄一覧」／ 在庫管理 →「原料出しロスの入力・廃棄一覧」",steps:["原料出しロス：「原料出しロスを入力」で日付・品目・kgを入れます（在庫は減りません）。","原料廃棄：原料のQRを読み、ロットの画面の「廃棄」で数量を入れます（在庫が減ります）。","下処理ロスは、下処理の確定で自動で入ります。","月を選ぶと、区分別・品目別の合計（金額つき）が出ます。"],check:"",caution:"金額は、作業日の週の市場価格（同じ品目の平均）×kgです。"},
  rawout:{title:"原料出し（原料のまま出荷）",where:"QR読み取り → ロットの画面",steps:["原料のQRを読みます。","「原料出し（原料のまま出荷）」に数量（ケース・大きい容器はkg）を入れて「出庫する」を押します。"],check:"このロットの履歴に「出庫 → 原料出し」が残ります。",caution:"在庫反映がオンになると、下処理への使用出庫はなくなり、出庫は原料出しだけになります。"},
  price:{title:"仕入れ価格表（本社）を見る",where:"本社ホーム →「仕入れ価格表」",steps:["品目ごとの週の市場価格（平均）が8週分並びます。この8週に市場価格が登録されている品目は、すべて出ます（契約産地の価格は入りません）。","価格がない週は、前の週の価格を使います（黄色の字で何週の価格か出ます）。"],check:"",caution:"価格の入力は石岡の「仕入れ価格表」の画面です。"},
  workDelete:{title:"試しに入力した作業を完全に削除する（本社社員・管理者）",where:"作業の画面 または 下処理の確認・確定の画面 →「この記録を完全に削除する」",steps:["「この記録を完全に削除する」を開き、「完全に削除する」を押します。","作業日・種類・原料が出るので、2回確認して削除します。"],check:"一覧と作業時間の集計から消えます。",caution:"元に戻せません。作業時間の記録も一緒に消えます。確定して在庫を減らしていた場合は、在庫と下処理ロスを元に戻してから消します。印刷した仕掛品ラベルは捨ててください。"},
  yield:{title:"歩留まり管理（製造日報・平均・推移）",where:"本社ホーム →「歩留まり管理」",steps:["月を選びます。","「製造日報」で日ごとの下処理、「品目・仕掛品の平均」で月の平均、「年度の推移」で9月〜8月の月ごとの歩留まり率を見ます。"],check:"確定した下処理だけが入ります。",caution:"歩留まり率＝出来高÷（出来高＋廃棄）。歩留まり原価＝単価×（出来高＋廃棄）÷出来高。"},
  usage:{title:"品目別使用数量を見る",where:"在庫管理 →「品目別使用数量」",steps:["月を選びます。","品目を押すと、日ごとの使用数量（前日の在庫＋入荷−その日の在庫）と、廃棄・原料のまま出荷の内訳が出ます。"],check:"",caution:"平均は在庫を入力した日（稼働日）で割っています。仕掛品は対象外です。"},
  take:{title:"棚卸しをする",where:"在庫管理 →「棚卸し」",steps:["棚卸しの日を選び「確認表を作る」を押します。","「確認表を印刷」で印刷し、実物を数えます。","数えた数を入れて「途中保存」。全部入れたら「確定する」を押します。","「結果を印刷」で差の入った結果を印刷します。"],check:"QRの原料はロットごとに「実数調整（棚卸し）」、原料・仕掛品はその日の在庫入力になります。",caution:"実数が空欄の行は変えません。"},
  quality:{title:"本社の品質評価一覧",where:"本社ホーム →「品質評価一覧」",steps:["月を選び、「要確認・不良」「確認待ち」で絞り込みます。","担当の仕入れ担当者は「確認済みにする」を押します（担当がいないときは管理者）。","管理者・本社社員は「確認しました」で自分のお知らせを消します。","写真を付け忘れたときや「写真が保存されていません」と出たときは、「写真を追加」から写真を撮るか選びます（管理者・本社社員・荷受け担当。1件5枚まで）。"],check:"「写真」を押すと、登録した写真が見られます。",caution:"要確認・不良は写真1枚以上が必須です。"},
  excel:{title:"Excelを作る",where:"本社ホーム →「Excel出力」",steps:["月を選びます。","作りたいもののボタンを押します（在庫・在庫入力・在庫表・廃棄・歩留まり・使用数量・品質評価・作業時間）。"],check:"ファイル名は「本社_歩留まり_2026年10月.xlsx」のようになります。",caution:""},
  diff:{title:"本社で数が違ったときのお知らせ（石岡）",where:"石岡のホームのいちばん上",steps:["本社で受け入れた数が、石岡で予定した数と違うと、お知らせが出ます。","内容を見て「確認しました」を押すと消えます。"],check:"",caution:"石岡の在庫は自動では直しません。必要なら実数調整をします。"},
  viewHq:{title:"本社の画面を見る（見るだけ）",where:"ホーム →「本社の画面へ」",steps:["本社の在庫・品質評価・歩留まり・廃棄・仕入れ価格表・作業時間を見られます。","「Excel出力」で月ごとのExcelを作れます。"],check:"",caution:"入力はできません。"}
 };
 Object.assign(HQ_GUIDE,G);
 HQ_GUIDE.hqNormal=G.stockInput;
 HQ_GUIDE.hqTable={...HQ_GUIDE.hqTable,title:"在庫表を見る（QR品目＋原料＋仕掛品）",steps:["最後の日と日数（7・14・31日）を選びます。「◀ 前」「次 ▶」で期間を動かせます。","石岡の在庫表と同じ形で、「QR品目」「原料」「仕掛品」の見出しごとに品目が並び、日ごとのkgといちばん下に合計kgが出ます。今日の列には色が付きます。","品目名の列は左に固定されているので、横に動かしても品目名が見えます。期間中ずっと在庫0の品目は表示せず、表の下に件数だけ出ます。"],check:"QR品目はその日の終わりの在庫、原料・仕掛品はその日に在庫入力した数です（入力がない日は「—」）。"};
 const R={
  hq_prep:{name:"本社 下処理班",intro:"下処理と作業時間の記録をします。お金の数字は出ません。",keys:["prepStart","prepEnd","prepJoin","prepOther"]},
  hq_worker:{name:"本社社員",intro:"受け入れ・確定、下処理の確認と確定、在庫入力、棚卸し、マスタ・スタッフの登録、集計とExcelができます。",keys:["switch","hqReceive","prepCheck","stockInput","rawout","waste","take","usage","quality","yield","price","master","workDelete","staff","tasks","worktime","excel","hqDirect","hqStock","hqTable","hqItems","prepStart","prepEnd","hqOut"]},
  hq_receiver:{name:"本社 荷受け担当者",intro:"届いた原料の品質評価と確定、貼り紙の印刷、在庫入力、原料出しと原料出しロス・廃棄の入力ができます。",keys:["hqReceive","hqDirect","stockInput","rawout","waste","quality","hqStock","hqTable"]},
  hq_clerk:{name:"本社事務",intro:"本社の在庫・集計を見て、Excelを作れます。",keys:["switch","viewHq","hqStock","hqTable","usage","yield","waste","price","quality","worktime","excel"]}
 };
 for(const[r,g]of Object.entries(R))V195_ROLE_GUIDES[r]={name:g.name,intro:g.intro,sections:g.keys.map(k=>HQ_GUIDE[k]).filter(Boolean)};
 const add={admin:["stage2","prepCheck","workDelete","stockInput","rawout","waste","take","usage","quality","yield","price","master","staff","tasks","worktime","excel","diff"],worker:["diff"],buyer:["viewHq","quality","price","yield","excel"],sales:["viewHq","price","yield","usage","excel"]};
 for(const[r,keys]of Object.entries(add)){const g=V195_ROLE_GUIDES[r];if(!g||!Array.isArray(g.sections))continue;g.sections=g.sections.map(s=>s&&s.title&&s.title.startsWith("通常在庫を入力する")?G.stockInput:s);for(const k of keys)if(!g.sections.some(s=>s&&s.title===HQ_GUIDE[k].title))g.sections.push(HQ_GUIDE[k])}
 for(const r of Object.keys(V195_ROLE_GUIDES)){const g=V195_ROLE_GUIDES[r];if(g&&Array.isArray(g.sections))g.sections=g.sections.map(s=>s&&s.title===HQ_GUIDE.hqTable.title.replace("（QR品目＋原料＋仕掛品）","（QR品目＋通常在庫）")?HQ_GUIDE.hqTable:s)}
}catch(e){console.warn("[本社 第2段階 ガイド]",e)}
})();
/* ===== v1.199-c61 本社の使用期限（本社入荷日から）・トレース表・品目の呼び方のまとめ ===== */
(function(){
"use strict";
try{
 const H=window.__h2||{};
 const traceBlocked=()=>["hq_prep","hq_receiver"].includes(db?.role);
 const css=`.hqBtnRules{background:linear-gradient(135deg,#0e7490,#164e63)!important;color:#fff!important}
.hqBtnTrace{background:#fff!important;color:#0f172a!important;border:3px solid #334155!important}
.hqNg{margin-top:8px;padding:10px 12px;border-radius:12px;background:#f8fafc;border:1px solid #cbd5e1}
.hqNg b{display:block;font-size:13px;color:#475569;margin-bottom:2px}`;
 const st=document.createElement("style");st.textContent=css;document.head.appendChild(st);

 let rules=[],rulesAt=0,ruleMap=new Map(),ruleKeys=[];
 const norm=v=>qrNormalizeName(String(v||"")).toLowerCase();
 function build(){
  const m=new Map();
  for(const r of rules){const k=norm(r.item_name);if(k)m.set(k,r)}
  for(const r of rules)for(const a of(r.aliases||[])){const k=norm(a);if(k&&!m.has(k))m.set(k,r)}
  ruleMap=m;ruleKeys=[...m.keys()].sort((a,b)=>b.length-a.length);
 }
 async function loadRules(force=false){
  if(!force&&rulesAt&&Date.now()-rulesAt<300000)return rules;
  try{rules=await qrSelect("hq_item_rules_v1600","select=*&order=sort_order.asc,item_name.asc");rulesAt=Date.now();build()}catch(e){console.warn("[本社の使用期限] 読み込めません",e)}
  return rules;
 }
 function ruleOf(name){
  const raw=String(name||"").trim();if(!raw)return null;
  const n=norm(raw),plain=norm(raw.replace(/[（(][^）)]*[）)]/g,""));
  for(const k of[n,plain])if(ruleMap.has(k))return ruleMap.get(k);
  if(/皮むき|カット/.test(raw))return null;
  const hit=ruleKeys.find(k=>plain.includes(k));
  return hit?ruleMap.get(hit):null;
 }
 function limitInfo(l){
  if(!l||l.status==="取消"||l.status==="在庫なし")return null;
  const r=ruleOf(l.item_name);if(!r||!r.limit_days)return null;
  const base=l.hq_received_date||l.planned_date;if(!base)return null;
  const elapsed=Math.max(0,Math.floor((new Date(hqToday()+"T00:00:00")-new Date(String(base).slice(0,10)+"T00:00:00"))/864e5));
  const limit=Number(r.limit_days),level=v1250LevelOf(elapsed,limit);
  return{rule:r,elapsed,limit,level,over:elapsed>limit,lv:V1250_LEVELS[level]};
 }
 const canConfirm=()=>["admin","hq_worker"].includes(db?.role);
 function guard(l,what){
  const i=limitInfo(l);if(!i||!i.over)return true;
  const msg=`この原料は使用期限を過ぎています。\n${l.item_name||""}（${l.lot_no||""}）：本社入荷から${i.elapsed}日（期限${i.limit}日）${i.rule.ng_sign?`\n\nNGサイン：${i.rule.ng_sign}`:""}`;
  if(!canConfirm()){alert(`${msg}\n\n${what}できません。本社社員に相談してください。`);return false}
  if(!confirm(`${msg}\n\n実物を確認し、使える品質であることを確認しましたか？\n「OK」で${what}します（確認した人を記録します）。`))return false;
  callRpc("hq_limit_check_v1600",{p_lot_id:String(l.id),p_action:what,p_elapsed:i.elapsed,p_limit:i.limit}).catch(e=>console.warn("[本社の使用期限] 確認の記録を保存できません",e));
  return true;
 }
 window.hqLimitGuard=guard;window.hqLimitInfo=limitInfo;window.hqItemRuleOf=ruleOf;

 hqLoadLimits=async function(){await loadRules();hqLimits=hqLimits||{};return hqLimits};window.hqLoadLimits=hqLoadLimits;
 hqAgeBadge=function(l){const i=limitInfo(l);if(!i)return"";return `<span class="badge ${i.lv.badge}">${esc(i.lv.label)}｜本社入荷から${i.elapsed}日（期限${i.limit}日）</span>`};window.hqAgeBadge=hqAgeBadge;
 const cardBase=hqLotCard;
 hqLotCard=function(l,open){const h=cardBase.apply(this,arguments);const i=limitInfo(l);return i&&i.level>1?h.replace('class="card hqLotCard"',`class="card hqLotCard ${i.lv.card}"`):h};window.hqLotCard=hqLotCard;

 const lotPageBase=hqLotPage;
 hqLotPage=async function(key,msg){
  await loadRules();
  const r=await lotPageBase.apply(this,arguments);
  try{
   if(currentScreen!=="hqLotPage")return r;
   const k=String(key||"");const l=(await hqLots(`select=*&or=(qr_key.eq.${encodeURIComponent(k)},lot_no.eq.${encodeURIComponent(k)})&limit=1`))[0];
   const card=document.querySelector(".hqLotCard");
   if(l&&card){
    const i=limitInfo(l),rule=ruleOf(l.item_name);let add="";
    if(i&&i.over)add+=`<div class="${i.level>=5?"v1250Stop":"v1250Need"}">使用期限を過ぎています（本社入荷から${i.elapsed}日／期限${i.limit}日）。使う前に実物を確認してください。</div>`;
    if(rule&&rule.ng_sign)add+=`<div class="hqNg"><b>NGサイン（この症状があれば社員に報告し廃棄）</b>${esc(rule.ng_sign)}</div>`;
    if(add)card.insertAdjacentHTML("beforeend",add);
   }
   const wrap=document.querySelector(".wrap");
   if(l&&wrap&&!traceBlocked()&&!document.getElementById("hqTraceBtn"))wrap.insertAdjacentHTML("beforeend",`<div class="card" id="hqTraceBtn"><b>トレース表（監査用）</b><div class="small">石岡の入荷から本社での使用・下処理・廃棄までを、画面で見るか、A4縦の紙に印刷します。</div><button class="btn hqBtnTrace" style="width:100%;margin-top:8px" ${H.btnAttr("hqTracePrint",["hq",l.qr_key])}>トレース表を印刷</button><button class="btn btn2" style="width:100%;margin-top:8px" ${H.btnAttr("hqTraceView",["hq",l.qr_key])}>トレースを画面で見る</button></div>`);
  }catch(e){console.warn("[本社の使用期限]",e)}
  return r;
 };window.hqLotPage=hqLotPage;

 const qrDetailBase=qrLotDetail;
 qrLotDetail=async function(q,msg){
  const r=await qrDetailBase.apply(this,arguments);
  try{
   const lot=await qrFindLot(q);const wrap=document.querySelector(".wrap");
   if(lot&&wrap&&!traceBlocked()&&!document.getElementById("qrTraceBtn"))wrap.insertAdjacentHTML("beforeend",`<div class="card" id="qrTraceBtn"><b>トレース表（監査用）</b><div class="small">このロットの入荷から、本社への移動・本社での使用までを、画面で見るか、A4縦の紙に印刷します。</div><button class="btn hqBtnTrace" style="width:100%;margin-top:8px" ${H.btnAttr("hqTracePrint",["qr",lot.qr_key||lot.lot_no])}>トレース表を印刷</button><button class="btn btn2" style="width:100%;margin-top:8px" ${H.btnAttr("hqTraceView",["qr",lot.qr_key||lot.lot_no])}>トレースを画面で見る</button></div>`);
  }catch(e){}
  return r;
 };window.qrLotDetail=qrLotDetail;

 /* --- トレース表 --- */
 const d10=v=>v?String(v).slice(0,10):"";
 const dtj=v=>{if(!v)return"";const s=String(v);if(s.length<=10)return s.replace(/-/g,"/");const x=new Date(s);const p=n=>String(n).padStart(2,"0");return `${x.getFullYear()}/${p(x.getMonth()+1)}/${p(x.getDate())} ${p(x.getHours())}:${p(x.getMinutes())}`};
 const q2=(v,u)=>v==null||v===""?"":`${hqQty(v)}${u==="kg"?"kg":u?` ${u}`:""}`;
 function traceRows(t){
  const ev=[],ql=t.qr_lot,hqNo=new Map((t.hq_lots||[]).map(l=>[l.id,l.lot_no]));
  if(ql)ev.push({at:ql.received_date||ql.created_at,place:"石岡",kind:"入荷",lot:ql.lot_no,qty:q2(ql.received_qty,ql.unit),detail:[ql.supplier,ql.origin,ql.storage_location?`保管：${ql.storage_location}`:""].filter(Boolean).join(" / "),who:ql.user_name||ql.purchase_staff||""});
  for(const m of t.qr_moves||[])ev.push({at:m.occurred_at,place:"石岡",kind:m.movement_type+(m.cancelled_at?"（取消済み）":""),lot:m.lot_no||ql?.lot_no,qty:q2(m.qty,m.unit||ql?.unit),detail:[m.destination?`出庫先：${m.destination}`:"",m.reason||"",m.memo||""].filter(Boolean).join(" / "),who:m.user_name||""});
  for(const l of t.hq_lots||[]){
   ev.push({at:l.created_at,place:"本社",kind:l.source_kind==="石岡から"?"移動（入荷待ち）":"直接入荷の登録",lot:l.lot_no,qty:q2(l.planned_qty,l.unit),detail:[l.shipped_date?`出庫日 ${d10(l.shipped_date)}`:"",l.ship_run||"",l.planned_date?`本社入荷日（予定）${d10(l.planned_date)}`:""].filter(Boolean).join(" / "),who:l.created_by_name||""});
   if(l.confirmed_at)ev.push({at:l.confirmed_at,place:"本社",kind:"受け入れ確定",lot:l.lot_no,qty:q2(l.received_qty,l.unit),detail:[l.hq_received_date?`本社入荷日 ${d10(l.hq_received_date)}`:"",l.grade?`品質：${({good:"良好",review:"要確認",bad:"不良"})[l.grade]||l.grade}`:"",(l.issues||[]).join("・")].filter(Boolean).join(" / "),who:l.confirmed_by_name||l.evaluated_by_name||""});
  }
  for(const m of t.hq_moves||[]){if(m.movement_type==="入庫確定")continue;ev.push({at:m.occurred_at,place:"本社",kind:m.movement_type+(m.cancelled_at?"（取消済み）":""),lot:m.lot_no||hqNo.get(m.lot_id),qty:q2(m.qty,m.unit),detail:[m.destination?`出庫先：${m.destination}`:"",m.reason||"",m.memo||""].filter(Boolean).join(" / "),who:m.user_name||""})}
  for(const x of t.works||[]){const w=x.work||{};const mats=x.materials||[];ev.push({at:w.started_at||w.work_date,place:"本社",kind:`下処理${w.confirm_status==="確定"?"（確定）":w.confirm_status==="取消"||w.status==="取消"?"（取消）":"（未確定）"}`,lot:mats.map(m=>m.lot_no||hqNo.get(m.lot_id)).filter(Boolean).join("、"),qty:mats.map(m=>q2(m.qty,m.unit==="kg"?"kg":"ケース")).join("＋"),detail:[w.product_name?`仕掛品：${w.product_name}`:"",w.yield_kg!=null?`出来高 ${hqQty(w.yield_kg)}kg`:"",w.waste_kg!=null?`廃棄 ${hqQty(w.waste_kg)}kg`:"",w.expiry_days!=null&&w.work_date?`使用期限 ${hqAddDays(d10(w.work_date),Number(w.expiry_days))}`:""].filter(Boolean).join(" / "),who:w.confirmed_by_name||w.created_by_name||""})}
  for(const x of t.waste||[]){if(x.work_id)continue;ev.push({at:x.created_at,place:"本社",kind:x.kind+(x.cancelled_at?"（取消済み）":""),lot:x.lot_no||hqNo.get(x.lot_id),qty:x.kg!=null?`${hqQty(x.kg)}kg`:q2(x.qty,x.unit),detail:x.memo||"",who:x.user_name||""})}
  return ev.sort((a,b)=>String(a.at||"").localeCompare(String(b.at||"")));
 }
 const TRACE_CSS=`.h2PdfRoot .th{display:flex;justify-content:space-between;align-items:flex-end;border-bottom:3px solid #000;padding-bottom:6px}.h2PdfRoot .th h1{font-size:26px;margin:0}.h2PdfRoot .ti{display:grid;grid-template-columns:1fr 1fr;gap:2px 16px;font-size:13px;margin:8px 0 10px}.h2PdfRoot .ti div{border-bottom:1px solid #cbd5e1;padding:3px 0}.h2PdfRoot .ti span{display:inline-block;width:7.5em;color:#334155}.h2PdfRoot table.tr{width:100%;border-collapse:collapse;font-size:11.5px;table-layout:fixed}.h2PdfRoot table.tr th{background:#e2e8f0;border:1px solid #000;padding:4px 3px}.h2PdfRoot table.tr td{border:1px solid #000;padding:4px 3px;vertical-align:top;word-break:break-all;line-height:1.35}.h2PdfRoot .tf{position:absolute;left:36px;right:36px;bottom:24px;font-size:11px;border-top:1px solid #000;padding-top:4px;display:flex;justify-content:space-between}`;
 async function tracePrint(kind,key){
  if(traceBlocked())return alert("この権限ではトレース表を表示・印刷できません。");
  let t;H.h2PdfStatus&&H.h2PdfStatus("トレース表を作っています…");
  try{t=await callRpc("get_lot_trace_v1600",{p_kind:kind,p_key:String(key||"")})}catch(e){return H.h2PdfStatus(`トレース表を作れませんでした。${esc(e?.message||String(e))}`,"err")}
  const ql=t.qr_lot,hl=t.hq_lots||[],first=hl[0]||{};
  const item=ql?.item_name||first.item_name||"",rows=traceRows(t);
  const info=[["品目",item],["石岡ロットNo.",ql?.lot_no||"（本社直接入荷）"],["本社ロットNo.",hl.map(l=>l.lot_no).join("、")||"-"],["仕入先",ql?.supplier||first.supplier||"-"],["産地",ql?.origin||first.origin||"-"],["量目",ql?.pack_weight||first.pack_weight||"-"],["石岡入荷日",ql?.received_date?d10(ql.received_date):"-"],["本社入荷日",hl.map(l=>d10(l.hq_received_date||l.planned_date)).filter(Boolean).join("、")||"-"],["石岡の残り",ql?q2(ql.current_qty,ql.unit):"-"],["本社の残り",hl.map(l=>`${l.lot_no.slice(-4)}：${q2(l.current_qty,l.unit)||0}（${l.status}）`).join("、")||"-"]];
  const now=new Date(),ds=dtj(now.toISOString());
  const head=p=>`<div class="th"><h1>ロットのトレース表</h1><div style="font-size:12px">印刷日時：${esc(ds)}　${p}</div></div>`;
  const tbl=list=>`<table class="tr"><colgroup><col style="width:15%"><col style="width:7%"><col style="width:15%"><col style="width:14%"><col style="width:12%"><col style="width:26%"><col style="width:11%"></colgroup><tr><th>日時</th><th>場所</th><th>内容</th><th>ロットNo.</th><th>数量</th><th>詳細</th><th>担当</th></tr>${list.map(r=>`<tr><td>${esc(dtj(r.at))}</td><td>${esc(r.place)}</td><td>${esc(r.kind)}</td><td>${esc(r.lot||"")}</td><td>${esc(r.qty||"")}</td><td>${esc(r.detail||"")}</td><td>${esc(r.who||"")}</td></tr>`).join("")||'<tr><td colspan="7">記録がありません</td></tr>'}</table>`;
  const foot=`<div class="tf"><span>SEIKA＋　株式会社せき</span><span>印刷した人：${esc(t.printed_by||db.user||"")}</span></div>`;
  const chunks=[];let i=0;const firstN=20,nextN=28;chunks.push(rows.slice(0,firstN));i=firstN;while(i<rows.length){chunks.push(rows.slice(i,i+nextN));i+=nextN}
  const pages=chunks.map((c,n)=>`${head(chunks.length>1?`${n+1}/${chunks.length}枚`:"")}${n===0?`<div class="ti">${info.map(x=>`<div><span>${esc(x[0])}</span><b>${esc(x[1])}</b></div>`).join("")}</div>`:'<div style="height:10px"></div>'}${tbl(c)}${foot}`);
  return H.h2MakePdf(pages,TRACE_CSS,`トレース表_${item}_${ql?.lot_no||first.lot_no||""}.pdf`);
 }
 window.hqTracePrint=tracePrint;
 let traceBack=null;
 async function traceView(kind,key){
  if(traceBlocked())return hqHome("この権限ではトレース表を表示・印刷できません。");
  if(currentScreen!=="hqTraceView")traceBack={screen:currentScreen,kind,key};
  setScreen("hqTraceView",[kind,key]);
  pageShell("ロットのトレース","入荷から使用までの記録",'<div class="notice">読み込んでいます…</div>');
  let t;try{t=await callRpc("get_lot_trace_v1600",{p_kind:kind,p_key:String(key||"")})}catch(e){return pageShell("ロットのトレース","",`<div class="err">トレースを読み込めませんでした。${esc(e?.message||String(e))}</div>`)}
  if(currentScreen!=="hqTraceView")return;
  const ql=t.qr_lot,hl=t.hq_lots||[],first=hl[0]||{},item=ql?.item_name||first.item_name||"",rows=traceRows(t);
  const info=[["品目",item],["石岡ロットNo.",ql?.lot_no||"（本社直接入荷）"],["本社ロットNo.",hl.map(l=>l.lot_no).join("、")||"-"],["仕入先",ql?.supplier||first.supplier||"-"],["産地",ql?.origin||first.origin||"-"],["量目",ql?.pack_weight||first.pack_weight||"-"],["石岡入荷日",ql?.received_date?d10(ql.received_date):"-"],["本社入荷日",hl.map(l=>d10(l.hq_received_date||l.planned_date)).filter(Boolean).join("、")||"-"],["石岡の残り",ql?q2(ql.current_qty,ql.unit):"-"],["本社の残り",hl.map(l=>`${l.lot_no.slice(-4)}：${q2(l.current_qty,l.unit)||0}（${l.status}）`).join("、")||"-"]];
  const ev=rows.map(r=>`<div class="c91Ev ${r.place==="本社"?"hq":"ik"}"><div class="c91EvTop"><span class="c91Pl">${esc(r.place)}</span><b>${esc(r.kind)}</b><span class="c91At">${esc(dtj(r.at))}</span></div><div class="c91EvBody">${r.qty?`<b>${esc(r.qty)}</b>　`:""}${esc(r.lot||"")}${r.detail?`<div class="small">${esc(r.detail)}</div>`:""}${r.who?`<div class="small">担当：${esc(r.who)}</div>`:""}</div></div>`).join("")||'<div class="notice">記録がありません。</div>';
  pageShell("ロットのトレース",`${esc(item)}　入荷から使用までの記録`,`<div class="card"><div class="c91Info">${info.map(x=>`<div><span>${esc(x[0])}</span><b>${esc(x[1])}</b></div>`).join("")}</div><button class="btn hqBtnTrace" style="width:100%;margin-top:10px" ${H.btnAttr("hqTracePrint",[kind,key])}>トレース表を印刷</button></div><div class="card"><b>記録（古い順）</b><div class="small" style="margin:4px 0 8px">石岡（青）と本社（緑）の記録が、日時の順に並びます。取り消した操作も「取消」と出ます。</div>${ev}</div>`);
 }
 function traceViewBack(){if(traceBlocked()){traceBack=null;return hqHome()}const b=traceBack;traceBack=null;if(b&&b.kind==="hq")return hqLotPage(b.key);if(b&&b.kind==="qr")return qrLotDetail(b.key);return home()}
 window.hqTraceView=traceView;window.hqTraceViewBack=traceViewBack;

 /* --- 使用期限・品目の呼び方の設定（本社社員・管理者） --- */
 async function rulesPage(msg=""){
  if(!["admin","hq_worker"].includes(db?.role))return hqHome();
  setScreen("hqItemRulesPage",[msg]);pageShell("原料の使用期限・呼び方","本社入荷日から数える使用期限／同じ品目の別の書き方",'<div class="notice">読み込んでいます…</div>');
  await loadRules(true);
  const lvGuide=d=>{d=Number(d);if(!d)return"期限なし（呼び方のまとめだけ）";const w=Math.ceil(d*0.5);return `要観察 ${w}日〜／優先使用 ${d-1}日目／要品質確認 ${d}日目〜／${d+1}日目から使う前に確認／使用不可・保留 ${d+2}日目〜`};
  pageShell("原料の使用期限・呼び方","本社入荷日から数える使用期限／同じ品目の別の書き方",`${okHtml(msg)}
  <div class="card small">本社の入荷日（まだ受け入れていない原料は本社入荷日（予定））から数えます。期限の日数を過ぎた原料を使うときは確認画面が出ます。「別の書き方」に入れた名前は同じ品目として扱い、仕入れ価格表でも1行にまとめます。</div>
  <div class="card"><b>品目を追加</b><label class="label" style="margin-top:6px">品目名</label><input id="hqRuN" class="input" placeholder="例：ブロッコリー"><label class="label" style="margin-top:6px">使用期限（本社入荷日から何日）　空欄＝期限なし</label><input id="hqRuD" class="input" inputmode="numeric"><label class="label" style="margin-top:6px">NGサイン</label><input id="hqRuG" class="input"><label class="label" style="margin-top:6px">別の書き方（「、」で区切る）</label><input id="hqRuA" class="input" placeholder="例：ぶろっこりー、ブロッコリ"><button class="btn hqBtnRules" style="width:100%;margin-top:8px" ${H.btnAttr("hqRuleSave",[""])}>追加する</button></div>
  ${rules.map(r=>`<div class="card"><div class="itemHead"><div><b style="font-size:18px">${esc(r.item_name)}</b>　<b>${r.limit_days?`${r.limit_days}日`:"期限なし"}</b><div class="small">${esc(lvGuide(r.limit_days))}</div>${r.aliases?.length?`<div class="small">別の書き方：${esc(r.aliases.join("、"))}</div>`:""}${r.ng_sign?`<div class="small">NGサイン：${esc(r.ng_sign)}</div>`:""}</div><div style="display:flex;gap:6px;flex-direction:column"><button class="btn btn2" ${H.btnAttr("hqRuleEdit",[r.item_name])}>変更</button><button class="btn red" ${H.btnAttr("hqRuleDelete",[r.item_name])}>削除</button></div></div></div>`).join("")}`);
 }
 const splitA=s=>String(s||"").split(/[、,，\s]+/).map(x=>x.trim()).filter(Boolean);
 async function ruleSave(old,data){
  const d=data||{name:H.h2Val("hqRuN").trim(),days:H.h2Val("hqRuD").trim(),ng:H.h2Val("hqRuG"),al:splitA(H.h2Val("hqRuA"))};
  if(!d.name)return alert("品目名を入れてください");
  const days=d.days===""?null:Math.round(Number(d.days));if(days!=null&&!(days>0))return alert("日数は1以上の数字で入れてください（期限なしは空欄）");
  try{await callRpc("hq_save_item_rule_v1600",{p_old_name:old||null,p_item_name:d.name,p_limit_days:days,p_ng_sign:d.ng||null,p_aliases:d.al});rulesAt=0;return rulesPage(`${d.name}を保存しました`)}catch(e){alert(e?.message||String(e))}
 }
 async function ruleEdit(name){
  const r=rules.find(x=>x.item_name===name);if(!r)return;
  const n=prompt("品目名",r.item_name);if(n==null)return;
  const d=prompt("使用期限（本社入荷日から何日）。空欄＝期限なし",r.limit_days==null?"":String(r.limit_days));if(d==null)return;
  const g=prompt("NGサイン",r.ng_sign||"");if(g==null)return;
  const a=prompt("別の書き方（「、」で区切る）",(r.aliases||[]).join("、"));if(a==null)return;
  return ruleSave(r.item_name,{name:n.trim(),days:d.trim(),ng:g,al:splitA(a)});
 }
 async function ruleDelete(name){
  if(!confirm(`${name}の設定を削除します。使用期限の表示と、呼び方のまとめがなくなります。よろしいですか？`))return;
  try{await callRpc("hq_delete_item_rule_v1600",{p_item_name:name});rulesAt=0;return rulesPage(`${name}を削除しました`)}catch(e){alert(e?.message||String(e))}
 }
 Object.assign(window,{hqItemRulesPage:rulesPage,hqRuleSave:ruleSave,hqRuleEdit:ruleEdit,hqRuleDelete:ruleDelete});
 const hubBase=hqEntryHubItems;
 hqEntryHubItems=function(){const a=hubBase.apply(this,arguments);if(["admin","hq_worker"].includes(db?.role))a.push(["hqBtnRules","hqItemRulesPage","原料の使用期限・呼び方","期限の日数・NGサイン・別の書き方"]);return a};window.hqEntryHubItems=hqEntryHubItems;

 /* --- 操作ガイド --- */
 const G={
  hqLimit:{title:"本社の原料の使用期限を見る",where:"入荷待ち原料・本社在庫・ロットの画面",steps:["原料のカードに「良好・要観察・優先使用・要品質確認・使用不可/保留」と、本社入荷から何日かが出ます。","本社の入荷日から数えます。まだ受け入れていない原料は、本社入荷日（予定）から数えます。","ロットの画面には、その品目のNGサイン（傷みの見分け方）が出ます。","期限の日数を過ぎた原料を使用出庫・原料出し・下処理に使うときは、確認画面が出ます。本社社員・管理者が実物を確認して「OK」を押すと使えます（確認した人を記録します）。"],check:"",caution:"下処理班・荷受け担当のアカウントでは、期限を過ぎた原料は使えません。本社社員に相談してください。"},
  hqRules:{title:"使用期限の日数・NGサイン・別の書き方を変える（本社社員・管理者）",where:"本社ホーム →「入荷登録・品目」→「原料の使用期限・呼び方」",steps:["品目の「変更」で、日数・NGサイン・別の書き方を直します。","表にない品目は「品目を追加」で追加します。期限を付けない品目は日数を空欄にします。","「別の書き方」に入れた名前（例：胡瓜＝きゅうり）は同じ品目として扱い、仕入れ価格表でも1行にまとめます。"],check:"",caution:"最初は「原料使用期限・廃棄目安（2026.8.12更新）」の日数が入っています。"},
  trace:{title:"トレース表を印刷する（監査用）",where:"本社のロットの画面 または 石岡のQRロットの画面 → いちばん下「トレース表を印刷」",steps:["「トレース表を印刷」を押すと、A4縦のPDFができます。","「PDFを開く・印刷」で開いて印刷します。","石岡の入荷・本社への出庫・本社の受け入れ・使用出庫・下処理（仕掛品）・廃棄が、日時の順に並びます。"],check:"いちばん上に、品目・ロットNo.・仕入先・産地・入荷日・今の残りが出ます。",caution:"本社 下処理班・本社 荷受け担当者のアカウントでは、トレース表を表示・印刷できません。"}
 };
 Object.assign(HQ_GUIDE,G);
 for(const r of Object.keys(V195_ROLE_GUIDES)){const g=V195_ROLE_GUIDES[r];if(!g||!Array.isArray(g.sections))continue;
  const keys=["hq_prep","hq_receiver"].includes(r)?[]:["trace"];if(r.startsWith("hq_")||r==="admin")keys.unshift("hqLimit");if(r==="hq_worker"||r==="admin")keys.push("hqRules");
  for(const k of keys)if(!g.sections.some(s=>s&&s.title===G[k].title))g.sections.push(G[k]);}
}catch(e){console.warn("[v1.199-c61]",e)}
})();
})();


/* ===== v1.199-c49 QR出庫：ロット全てを出庫 ===== */
(function(){
const c49OpPageBase=qrOperationLotPage;
qrOperationLotPage=async function(kind,q){
 const r=await c49OpPageBase.apply(this,arguments);
 if(kind!=="out")return r;
 try{
  const qty=document.getElementById("qrMoveQty");
  if(!qty||document.getElementById("c49AllOutBtn"))return r;
  const lot=await qrFindLot(q);if(!lot)return r;
  const cur=Number((lot.current_qty??lot.current_quantity)||0);if(!(cur>0))return r;
  qty.insertAdjacentHTML("afterend",`<button id="c49AllOutBtn" type="button" class="btn btn2" style="width:100%;margin-top:8px" ${seikaEventAttrs("click","c49FillAllOut",[lot.qr_key])}>ロット全てを出庫（残り ${fmt(cur)} ${esc(qrLotUnit(lot))}）</button>`);
 }catch(e){console.warn("[ロット全てを出庫]",e)}
 return r;
};
window.qrOperationLotPage=qrOperationLotPage;
async function c49FillAllOut(key){
 const grades=[...document.querySelectorAll(".v1310OpGrade")];
 try{const lot=await qrFindLot(key);
  if(grades.length){grades.forEach(el=>{el.value=String(Number(el.dataset.cur||0)||"");el.dispatchEvent(new Event("input",{bubbles:true}))})}
  else{const qty=document.getElementById("qrMoveQty");if(qty&&lot)qty.value=String(Number((lot.current_qty??lot.current_quantity)||0))}
  if(typeof qrCalcOperation==="function")qrCalcOperation("out",key);
  document.getElementById("qrMoveDestination")?.focus();
 }catch(e){alert(e.message||e)}
}
window.c49FillAllOut=c49FillAllOut;
})();

function hqTimingLabelG(t){return t==="当日分"?"当日発注分":t==="翌日分先送り"?"翌日発注分":(t||"")}
new MutationObserver(ms=>{for(const m of ms)for(const n of m.addedNodes){if(n.nodeType!==1)continue;const os=n.tagName==="OPTION"?[n]:n.querySelectorAll?.("option")||[];for(const o of os)if((o.value==="当日分"||o.value==="翌日分先送り")&&o.textContent.trim()===o.value)o.textContent=hqTimingLabelG(o.value)}}).observe(document.body,{childList:true,subtree:true});
/* ===== v1.199-c50 本社への便の選択・発注分の表示名・本社出庫後に印刷画面へ ===== */
(function(){
const C50_DEFAULT_RUNS=[{name:"配送便",time:"11時"},{name:"原料便",time:"12時"},{name:"市場便",time:"15時以降"}];
const C50_TIMING_LABEL={"当日分":"当日発注分","翌日分先送り":"翌日発注分"};
function c50Runs(){if(!Array.isArray(db.c50ShipRuns)||!db.c50ShipRuns.length)db.c50ShipRuns=C50_DEFAULT_RUNS.map(r=>({...r}));return db.c50ShipRuns.filter(r=>r&&r.name)}
function c50RunLabel(r){return `${r.name}（${r.time}着）`}
let c50Pending=null,c50SuppressToastUntil=0;
const C50_SHIP_KEY="seika_c50_hq_ship_by_op";
function c50ShipStore(){try{return JSON.parse(localStorage.getItem(C50_SHIP_KEY)||"{}")||{}}catch(e){return{}}}
function c50RememberShip(opId,ship){const m=c50ShipStore();m[opId]={...ship,at:Date.now()};for(const[k,v]of Object.entries(m))if(Date.now()-Number(v.at||0)>7*86400000)delete m[k];try{localStorage.setItem(C50_SHIP_KEY,JSON.stringify(m))}catch(e){}}
function c50ShipBoxHtml(){
 return `<div id="c50ShipBox" style="display:none;margin-top:12px;padding:10px;border:2px solid #f59e0b;border-radius:12px;background:#fffbeb">
 <label class="label" style="margin-top:0">本社への便（必須）</label><select id="c50ShipRun" class="input"><option value="">選択してください</option>${c50Runs().map((r,i)=>`<option value="${i}">${esc(c50RunLabel(r))}</option>`).join("")}</select>
 <label class="label" style="margin-top:10px">当日便・翌日便（必須）</label><select id="c50ShipDay" class="input"><option value="">選択してください</option><option value="当日便">当日便</option><option value="翌日便">翌日便</option></select>
 <div class="small" style="margin-top:6px">本社の画面に「原料便（12時着）・翌日便」のように出ます。</div></div>`;
}
function c50RelabelTimings(root=document){root.querySelectorAll("#qrShipTiming option,#v135ShipTiming option").forEach(o=>{if(C50_TIMING_LABEL[o.value])o.textContent=C50_TIMING_LABEL[o.value]})}
function c50ToggleShipBox(){const box=document.getElementById("c50ShipBox");if(!box)return;box.style.display=(document.getElementById("qrMoveDestination")?.value||"")==="本社"?"block":"none"}
const c50OpPageBase=qrOperationLotPage;
qrOperationLotPage=async function(kind,q){
 const r=await c50OpPageBase.apply(this,arguments);
 if(kind==="out"){try{c50RelabelTimings();const t=document.getElementById("qrShipTimingBox");if(t&&!document.getElementById("c50ShipBox")){t.insertAdjacentHTML("afterend",c50ShipBoxHtml());const d=document.getElementById("qrMoveDestination");d?.addEventListener("change",c50ToggleShipBox);c50ToggleShipBox()}}catch(e){console.warn("[本社の便]",e)}}
 return r;
};
window.qrOperationLotPage=qrOperationLotPage;
function c50ReadShip(){
 const runEl=document.getElementById("c50ShipRun"),dayEl=document.getElementById("c50ShipDay");if(!runEl||!dayEl)return null;
 const r=c50Runs()[Number(runEl.value)];
 if(runEl.value===""||!r){typeof v161FocusField==="function"?v161FocusField("c50ShipRun","本社への便を選択してください。"):alert("本社への便を選択してください。");return false}
 if(!dayEl.value){typeof v161FocusField==="function"?v161FocusField("c50ShipDay","当日便か翌日便かを選択してください。"):alert("当日便か翌日便かを選択してください。");return false}
 return{run:r.name,time:r.time,day:dayEl.value};
}
const c50SaveBase=qrSaveLotMovement;
qrSaveLotMovement=async function(kind,q){
 c50Pending=null;
 if(kind==="out"&&(document.getElementById("qrMoveDestination")?.value||"")==="本社"){const ship=c50ReadShip();if(ship===false)return;if(ship)c50Pending=ship}
 try{return await c50SaveBase.apply(this,arguments)}finally{c50Pending=null}
};
window.qrSaveLotMovement=qrSaveLotMovement;
function c50Dest(args){return String(args?.p_destination??args?.p_args?.destination??"").trim()}
const c50RpcBase=callRpc;
callRpc=async function(name,args){
 let hq=false;
 if(/qr_lot.*operation/.test(String(name))&&c50Dest(args)==="本社"){
  hq=true;
  const inner=args?.p_args&&typeof args.p_args==="object"?args.p_args:args,opKey=inner===args?"p_operation_meta":"operation_meta",idKey=inner===args?"p_operation_id":"operation_id";
  const opId=String(inner[idKey]||"");let ship=opId?c50ShipStore()[opId]:null;
  if(!ship&&c50Pending&&opId){ship=c50Pending;c50RememberShip(opId,ship)}
  if(!ship&&inner[opKey]?.batchId&&typeof v135GetBatch==="function")ship=v135GetBatch(inner[opKey].batchId)?.defaults?.hqShip||null;
  if(ship){const m=inner[opKey]&&typeof inner[opKey]==="object"?inner[opKey]:{};inner[opKey]={...m,hqShip:{run:ship.run,time:ship.time,day:ship.day}}}
  if(c50Pending)c50SuppressToastUntil=Date.now()+8000;
 }
 const r=await c50RpcBase(name,args);
 if(hq&&c50Pending&&r&&r.ok!==false){
  const key=String(args?.p_qr_key||args?.p_args?.qr_key||"");
  setTimeout(()=>c50OpenSheetAfterOut(key),700);
 }
 return r;
};
window.callRpc=callRpc;
async function c50OpenSheetAfterOut(qrKey){
 try{
  const lot=(await qrSelect("qr_lots",`select=id&qr_key=eq.${encodeURIComponent(qrKey)}&limit=1`))[0];if(!lot)return;
  let h=null;for(let i=0;i<4&&!h;i++){h=(await qrSelect("hq_lots_v1400",`select=qr_key&source_lot_id=eq.${lot.id}&status=eq.入荷待ち&order=created_at.desc&limit=1`))[0];if(!h)await new Promise(r=>setTimeout(r,600))}
  if(!h)return;
  document.getElementById("hqToast")?.remove();
  if(typeof hqSheetFromToast==="function")await hqSheetFromToast(h.qr_key);
 }catch(e){console.warn("[本社の貼り紙へ]",e)}
}
new MutationObserver(()=>{if(Date.now()<c50SuppressToastUntil)document.getElementById("hqToast")?.remove()}).observe(document.body,{childList:true});
function c50ShipRunsPage(msg=""){
 setScreen("c50ShipRunsPage",[]);if(!canAdmin())return home();
 const rows=c50Runs();
 pageShell("本社への便の設定","石岡から本社へ出庫するときに選ぶ便と到着時間です（管理者のみ）",`${okHtml(msg)}<div class="card">${rows.map((r,i)=>`<div class="row" style="align-items:end;margin-top:8px"><div><label class="label">便の名前</label><input id="c50RunName${i}" class="input" value="${esc(r.name)}"></div><div><label class="label">到着時間</label><input id="c50RunTime${i}" class="input" value="${esc(r.time)}"></div><button class="btn btn2" style="flex:0 0 auto" ${seikaEventAttrs("click","c50RemoveRun",[i])}>削除</button></div>`).join("")}
 <button class="btn green" style="width:100%;margin-top:12px" ${seikaEventAttrs("click","c50SaveRuns",[])}>保存</button></div>
 <div class="card"><b>便を追加</b><div class="row" style="margin-top:8px"><div><label class="label">便の名前</label><input id="c50NewName" class="input" placeholder="例：追加便"></div><div><label class="label">到着時間</label><input id="c50NewTime" class="input" placeholder="例：17時"></div></div><button class="btn" style="width:100%;margin-top:10px" ${seikaEventAttrs("click","c50AddRun",[])}>追加</button></div>`);
}
function c50SaveRuns(){if(!canAdmin())return;const rows=c50Runs().map((r,i)=>({name:document.getElementById(`c50RunName${i}`)?.value.trim()||"",time:document.getElementById(`c50RunTime${i}`)?.value.trim()||""}));if(rows.some(r=>!r.name||!r.time))return alert("便の名前と到着時間を入れてください");db.c50ShipRuns=rows;save();c50ShipRunsPage("保存しました")}
function c50AddRun(){if(!canAdmin())return;const name=document.getElementById("c50NewName")?.value.trim()||"",time=document.getElementById("c50NewTime")?.value.trim()||"";if(!name||!time)return alert("便の名前と到着時間を入れてください");const rows=c50Runs();if(rows.some(r=>r.name===name))return alert("同じ名前の便があります");rows.push({name,time});db.c50ShipRuns=rows;save();c50ShipRunsPage("追加しました")}
function c50RemoveRun(i){if(!canAdmin())return;const rows=c50Runs();if(rows.length<=1)return alert("便は1つ以上必要です");if(!confirm(`${rows[i]?.name} を削除しますか？`))return;rows.splice(i,1);db.c50ShipRuns=rows;save();c50ShipRunsPage("削除しました")}

const st=document.createElement("style");st.textContent="#hqToast .btn:not(.btn2){color:#0f766e!important;-webkit-text-fill-color:#0f766e!important;font-weight:900}";document.head.appendChild(st);

/* 連続出庫：本社の便・一覧からまとめて選ぶ・全量・まとめて印刷画面へ */
const c50DefHtmlBase=v135DefaultsHtml;
v135DefaultsHtml=function(kind,values={}){const h=c50DefHtmlBase.apply(this,arguments);return kind==="out"?h+c50ShipBoxHtml().replace('id="c50ShipBox"','id="c50ShipBox" data-c50-batch="1"'):h};
window.v135DefaultsHtml=v135DefaultsHtml;
const c50BatchCreateBase=v135BatchCreatePage;
v135BatchCreatePage=async function(kind){const r=await c50BatchCreateBase.apply(this,arguments);if(kind==="out"){const d=document.getElementById("v135Destination"),f=()=>{const b=document.getElementById("c50ShipBox");if(b)b.style.display=d?.value==="本社"?"block":"none"};d?.addEventListener("change",f);f()}return r};
window.v135BatchCreatePage=v135BatchCreatePage;
const c50ReadDefBase=v135ReadDefaults;
v135ReadDefaults=function(kind){const d=c50ReadDefBase.apply(this,arguments);if(kind==="out"&&d.destination==="本社"){const r=c50Runs()[Number(document.getElementById("c50ShipRun")?.value)],day=document.getElementById("c50ShipDay")?.value||"";if(document.getElementById("c50ShipRun")?.value!==""&&r&&day)d.hqShip={run:r.name,time:r.time,day}}return d};
window.v135ReadDefaults=v135ReadDefaults;
const c50CreateBatchBase=v135CreateBatch;
v135CreateBatch=async function(kind){if(kind==="out"&&document.getElementById("v135Destination")?.value==="本社"&&c50ReadShip()===false)return;return c50CreateBatchBase.apply(this,arguments)};
window.v135CreateBatch=v135CreateBatch;
function c50ShipText(sh){return sh?`${sh.run}（${sh.time}着）・${sh.day}`:""}
const c50ScanBase=v135BatchScanPage;
v135BatchScanPage=async function(batchId,msg=""){
 const r=await c50ScanBase.apply(this,arguments);
 try{const b=v135GetBatch(batchId);if(b&&b.kind==="out"&&currentScreen==="v135BatchScanPage"){
  const cond=document.querySelector(".card.notice .small");if(cond&&!cond.dataset.c50){cond.dataset.c50="1";const t=b.defaults?.shipTiming;if(t&&C50_TIMING_LABEL[t])cond.textContent=cond.textContent.replace(` / ${t}`,` / ${C50_TIMING_LABEL[t]}`);if(b.defaults?.hqShip)cond.insertAdjacentText("beforeend",` / ${c50ShipText(b.defaults.hqShip)}`)}
  const reader=document.getElementById("v135Reader")?.closest(".card");if(reader&&!document.getElementById("c50PickBtn"))reader.insertAdjacentHTML("beforebegin",`<button id="c50PickBtn" class="btn green" style="width:100%;margin-bottom:12px" ${seikaEventAttrs("click","c50LotPickPage",[batchId])}>在庫一覧からまとめて選ぶ（全てのQRロット）</button>`);
 }}catch(e){console.warn("[一覧から選ぶ]",e)}
 return r;
};
window.v135BatchScanPage=v135BatchScanPage;
let c50PickLots=[];
async function c50LotPickPage(batchId){
 const b=v135GetBatch(batchId);if(!b)return v135PersonalWorkPage("保留作業が見つかりません。");
 await v135BatchStopCamera();setScreen("c50LotPickPage",[batchId]);
 pageShell("在庫一覧からまとめて選ぶ","出庫するロットにチェックを入れて「選んだロットを追加」を押します",`<div class="card"><input id="c50PickSearch" class="input" placeholder="品名・ロット番号・仕入先で絞り込み" ${seikaEventAttrs("input","c50PickFilter",[])}><div class="row" style="margin-top:8px"><button class="btn btn2" ${seikaEventAttrs("click","c50PickAll",[true])}>表示中を全て選ぶ</button><button class="btn btn2" ${seikaEventAttrs("click","c50PickAll",[false])}>選択を外す</button></div></div><div id="c50PickList"><div class="notice">読み込んでいます…</div></div><div class="card" style="position:sticky;bottom:0"><button class="btn green" style="width:100%" ${seikaEventAttrs("click","c50PickAdd",[batchId])}>選んだロットを追加</button><button class="btn btn2" style="width:100%;margin-top:8px" ${seikaEventAttrs("click","v135BatchScanPage",[batchId])}>戻る</button></div>`);
 try{
  const added=new Set((b.rows||[]).map(r=>r.qrKey));
  c50PickLots=(await qrSelect("qr_lots","select=*&active=eq.true&current_qty=gt.0&order=item_name.asc,received_date.asc,created_at.asc&limit=1000")).filter(l=>!added.has(l.qr_key));
  c50PickFilter();
 }catch(e){document.getElementById("c50PickList").innerHTML=`<div class="err">${esc(e.message||e)}</div>`}
}
function c50PickFilter(){
 const q=(document.getElementById("c50PickSearch")?.value||"").trim().toLowerCase(),host=document.getElementById("c50PickList");if(!host)return;
 const checked=new Set([...document.querySelectorAll(".c50PickChk:checked")].map(x=>x.value));
 const rows=c50PickLots.filter(l=>!q||[l.item_name,l.lot_no,l.supplier,l.origin].some(v=>String(v||"").toLowerCase().includes(q)));
 host.innerHTML=rows.length?rows.map(l=>`<label class="card" style="display:flex;gap:10px;align-items:center;margin:6px 0;cursor:pointer"><input type="checkbox" class="c50PickChk" value="${esc(l.qr_key)}" ${checked.has(l.qr_key)?"checked":""} style="width:26px;height:26px"><div><b>${esc(l.item_name||"-")}</b><div class="small">${esc(l.lot_no||"-")} / 入荷 ${esc(l.received_date||"-")} / ${esc(l.supplier||"-")}</div><div class="small">現在残 ${fmt(Number(l.current_qty||0))} ${esc(qrLotUnit(l))}</div></div></label>`).join(""):'<div class="notice">該当するロットはありません。</div>';
}
function c50PickAll(on){document.querySelectorAll(".c50PickChk").forEach(x=>x.checked=!!on)}
async function c50PickAdd(batchId){
 const keys=[...document.querySelectorAll(".c50PickChk:checked")].map(x=>x.value);if(!keys.length)return alert("ロットを選んでください");
 v161ShowProcessing?.("ロットを追加しています");const errs=[];let n=0;
 try{for(const k of keys){try{await v135AddKey(batchId,k);n++}catch(e){errs.push(`${k.slice(0,8)}…：${e.message||e}`)}}}finally{v161HideProcessing?.()}
 if(errs.length)alert(`追加できなかったロットがあります。\n${errs.join("\n")}`);
 await v135BatchScanPage(batchId,`${n}件追加しました`);
}
const c50ReviewBase=v135BatchReviewPage;
v135BatchReviewPage=async function(batchId,msg=""){
 const r=await c50ReviewBase.apply(this,arguments);
 try{const b=v135GetBatch(batchId);if(b&&b.kind==="out"&&currentScreen==="v135BatchReviewPage"){
  let any=false;
  for(const row of b.rows||[]){const inp=document.getElementById(`v135Qty_${row.id}`);if(!inp||inp.dataset.c50)continue;inp.dataset.c50="1";any=true;inp.insertAdjacentHTML("afterend",`<button class="btn btn2" style="margin-top:6px;padding:6px 9px;width:100%" ${seikaEventAttrs("click","c50FillAll",[batchId,row.id])}>ロット全て（${fmt(Number(row.snapshotQuantity||0))}）</button>`)}
  const table=document.querySelector("table");if(any&&table&&!document.getElementById("c50FillAllBtn"))table.insertAdjacentHTML("beforebegin",`<button id="c50FillAllBtn" class="btn btn2" style="width:100%;margin-bottom:8px" ${seikaEventAttrs("click","c50FillAll",[batchId,""])}>全てのロットを「ロット全て」にする</button>`);
  {const cond=document.querySelector(".card.notice .small");if(cond&&!cond.dataset.c50&&/出庫先/.test(cond.textContent)){cond.dataset.c50="1";const t=b.defaults?.shipTiming;if(t&&C50_TIMING_LABEL[t])cond.textContent=cond.textContent.replace(t,C50_TIMING_LABEL[t]);if(b.defaults?.hqShip)cond.insertAdjacentText("beforeend",` / ${c50ShipText(b.defaults.hqShip)}`)}}
 }}catch(e){console.warn("[ロット全て]",e)}
 return r;
};
window.v135BatchReviewPage=v135BatchReviewPage;
function c50FillAll(batchId,rowId){
 const b=v135GetBatch(batchId);if(!b)return;
 for(const row of b.rows||[]){if(rowId&&row.id!==rowId)continue;const inp=document.getElementById(`v135Qty_${row.id}`);if(!inp)continue;const v=String(Number(row.snapshotQuantity||0));inp.value=v;v135SetQty(batchId,row.id,v)}
}
const c50RunBase=v135RunBatch;
v135RunBatch=async function(batchId){
 const b=v135GetBatch(batchId),hq=b?.kind==="out"&&b.defaults?.destination==="本社";
 const before=new Set((b?.rows||[]).filter(v135MovementDone).map(r=>r.id));
 if(hq)c50SuppressToastUntil=Date.now()+3600000;
 try{await c50RunBase.apply(this,arguments)}finally{if(hq)c50SuppressToastUntil=Date.now()+8000}
 if(!hq)return;
 const after=v135GetBatch(batchId),keys=(after?.rows||[]).filter(r=>v135MovementDone(r)&&!before.has(r.id)).map(r=>r.qrKey);
 if(keys.length)await c50BatchPrintPage(keys);
};
window.v135RunBatch=v135RunBatch;
async function c50BatchPrintPage(qrKeys){
 setScreen("c50BatchPrintPage",[qrKeys]);
 pageShell("本社移動用の貼り紙を印刷",`${qrKeys.length}件を本社へ出庫しました。1件ずつ印刷してください（後から「本社へ移動中」でも印刷できます）`,`<div id="c50PrintList"><div class="notice">読み込んでいます…</div></div><button class="btn btn2" style="width:100%;margin-top:10px" ${seikaEventAttrs("click","home",[])}>あとで印刷する（ホームへ）</button>`);
 try{
  let lots=[];for(let i=0;i<4;i++){const src=await qrSelect("qr_lots",`select=id&qr_key=in.(${qrKeys.map(k=>encodeURIComponent(k)).join(",")})`);const ids=src.map(x=>x.id);lots=ids.length?await window.c83Hq.hqLots(`select=*&source_lot_id=in.(${ids.join(",")})&status=eq.入荷待ち&order=created_at.desc&limit=300`):[];if(lots.length)break;await new Promise(r=>setTimeout(r,700))}
  document.getElementById("c50PrintList").innerHTML=lots.length?hqGroupedHtmlG(lots):'<div class="notice">本社の入荷待ちがまだ見つかりません。「本社へ移動中」から印刷してください。</div>';
 }catch(e){document.getElementById("c50PrintList").innerHTML=`<div class="err">${esc(e.message||e)}</div>`}
}
Object.assign(window,{c50LotPickPage,c50PickFilter,c50PickAll,c50PickAdd,c50FillAll,c50BatchPrintPage});
Object.assign(window,{c50ShipRunsPage,c50SaveRuns,c50AddRun,c50RemoveRun});
})();
