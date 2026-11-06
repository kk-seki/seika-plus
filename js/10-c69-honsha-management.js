
/* ===== v1.199-c69 原料出しロスの入力案内・スタッフQRの作り直し・月次保管のお知らせ・本社の月次管理・データの容量 ===== */
(function(){
const X=window.__h2||{};
const C69_MODNAME={qr:"QR在庫履歴",waste:"廃棄履歴",trimming:"歩留まり・仕入価格履歴",quality:"品質評価",hq:"本社"};
const c69Esc=v=>esc(v==null?"":String(v));
const c69Mon=k=>{const[y,m]=String(k).slice(0,7).split("-");return `${y}年${Number(m)}月`};
const c69Cur=()=>{const d=new Date();return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,"0")}`};
const c69AddM=(k,n)=>{const[y,m]=k.split("-").map(Number);const d=new Date(y,m-1+n,1);return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,"0")}`};
const c69MB=b=>Math.round(Number(b||0)/1048576);

/* ② 原料出しのあと、ロスの入力を案内 */
const rpcBase=hqRpc;
hqRpc=async function(name,args){
 const r=await rpcBase.apply(this,arguments);
 if(name==="hq_outbound_v1400"&&args&&args.p_destination==="原料出し")setTimeout(()=>c69RawLossAsk(args.p_lot_id),400);
 return r;
};
window.hqRpc=hqRpc;
async function c69RawLossAsk(lotId){
 if(!(X.h2CanRaw&&X.h2CanRaw())||(typeof hqViewOnly==="function"&&hqViewOnly()))return;
 let item="";try{item=(await X.sel2("hq_lots_v1400",`select=item_name&id=eq.${encodeURIComponent(lotId)}&limit=1`))[0]?.item_name||""}catch(e){}
 document.getElementById("c69RawAsk")?.remove();
 const box=document.createElement("div");box.id="c69RawAsk";
 box.style.cssText="position:fixed;inset:0;background:rgba(15,23,42,.55);z-index:9999;display:flex;align-items:center;justify-content:center;padding:16px";
 box.innerHTML=`<div class="card" style="max-width:420px;width:100%;margin:0"><b style="font-size:18px">原料出しの出庫を登録しました</b><div style="margin:8px 0">${item?`<b>${c69Esc(item)}</b><br>`:""}トリミングのロスがあれば入力してください。</div><div class="small">ロスは在庫から減らさず、廃棄一覧に「原料出しロス」として入ります。</div><button class="btn hqBtnWaste" style="width:100%;margin-top:10px" ${seikaEventAttrs("click","c69RawLossGo",[item])}>ロスを入力する</button><button class="btn btn2" style="width:100%;margin-top:8px" ${seikaEventAttrs("click","c69RawLossNo",[])}>ロスはない</button></div>`;
 document.body.appendChild(box);
}
function c69RawLossNo(){document.getElementById("c69RawAsk")?.remove()}
async function c69RawLossGo(item){
 c69RawLossNo();
 await hqWastePage(ymdKey(new Date()).slice(0,7),"原料出しロス");
 const sel=document.getElementById("h2WsI");
 if(sel&&item){if(![...sel.options].some(o=>o.value===item)){const o=document.createElement("option");o.textContent=item;sel.appendChild(o)}sel.value=item}
 document.getElementById("h2WsK")?.focus();
}

/* ③ スタッフQRを1人分だけ作り直す */
function c69StaffButtons(){
 document.querySelectorAll('[data-seika-click-action="h2EditStaff"]').forEach(b=>{
  const wrap=b.parentElement;if(!wrap||wrap.querySelector(".c69Reissue"))return;
  let id="";try{id=JSON.parse(decodeURIComponent(b.getAttribute("data-seika-click-args")||"[]"))[0]}catch(e){}
  if(!id)return;
  wrap.insertAdjacentHTML("beforeend",`<button class="btn btn2 c69Reissue" ${seikaEventAttrs("click","c69Reissue",[id])}>QRを作り直す</button>`);
 });
 const note=[...document.querySelectorAll(".wrap .card.small")].find(c=>c.textContent.includes("退職したときは"));
 if(note&&!note.querySelector(".c69Note"))note.insertAdjacentHTML("beforeend",`<div class="c69Note" style="margin-top:4px">QRをなくした・汚れたときは「QRを作り直す」を押します。新しいQRを印刷でき、古いQRは読めなくなります。</div>`);
}
async function c69Reissue(id){
 const s=(X.staffCache||[]).find(x=>x.id===id);const name=s?s.name:"このスタッフ";
 if(!confirm(`${name}さんのQRを作り直します。\n\n・新しいQRを印刷します\n・今のQR（一覧ボードに載っているものも）は読めなくなります\n\nよろしいですか？`))return;
 let r;try{r=await callRpc("hq_reissue_staff_qr_v1690",{p_id:id})}catch(e){return alert((X.h2Err?X.h2Err(e):e.message)||e)}
 if(!r||!r.qr_key)return alert("作り直せませんでした");
 if(s)s.qr_key=r.qr_key;
 const css=`.h2PdfRoot .c69One{width:70mm;margin:20mm auto 0;border:2px solid #000;border-radius:10px;padding:10mm 6mm;text-align:center}.h2PdfRoot .c69One img{width:50mm;height:50mm}.h2PdfRoot .c69One .n{font-size:26px;font-weight:900;margin-top:4mm}.h2PdfRoot .c69One .t{font-size:15px}.h2PdfRoot .c69Hd{font-size:15px;text-align:center}`;
 const d=new Date();
 await window.h2MakePdfC69([`<div class="c69Hd">スタッフQR（作り直し　${d.getFullYear()}年${d.getMonth()+1}月${d.getDate()}日）</div><div class="c69One"><img src="${window.h2QrC69(r.qr_key,8)}"><div class="n">${c69Esc(r.name)}</div><div class="t">${c69Esc(r.team)}</div></div>`],css,`スタッフQR_${r.name}_作り直し.pdf`);
 alert(`${r.name}さんのQRを作り直しました。\n古いQRは読めなくなりました。\n一覧ボードに載っている古いQRも読めないので、一覧ボードも印刷し直してください。`);
}

/* ⑤ データの容量 / ④ 月次保管のお知らせ（管理者だけ） */
let c69NoticeCache=null,c69NoticeAt=0,c69NoticeBusy=false;
async function c69DbSize(){try{const r=await callRpc("seika_db_size_v1690",{});return r&&r.ok?r:null}catch(e){return null}}
async function c69HqMonths(){const r=await callRpc("hq_monthly_list_v1690",{});return Array.isArray(r&&r.rows)?r.rows:[]}
async function c69CollectNotice(){
 const prev=c69AddM(c69Cur(),-1),delLimit=c69AddM(c69Cur(),-4),unsaved={},deletable={};
 const add=(o,mod,k)=>{(o[mod]=o[mod]||[]).push(k)};
 const mods=["qr","waste","trimming"].filter(m=>typeof v1101CanModule!=="function"||v1101CanModule(m));
 await Promise.all(mods.map(async m=>{try{const rows=await v1101LoadArchives(m);(rows||[]).forEach(r=>{const k=String(r.target_month||"").slice(0,7);if(!k||k>prev||r.status==="deleted")return;if(r.status!=="excel_saved"){if(Number(r.row_count||0)>0)add(unsaved,m,k)}else if(k<=delLimit)add(deletable,m,k)})}catch(e){}}));
 try{const rows=typeof v1102LoadQualityArchives==="function"?await v1102LoadQualityArchives():[];(rows||[]).forEach(r=>{const k=String(r.target_month||"").slice(0,7);if(!k||k>prev||r.status==="deleted")return;if(r.status!=="excel_saved"){if(Number(r.row_count||r.evaluation_count||0)>0)add(unsaved,"quality",k)}else if(k<=c69AddM(c69Cur(),-4))add(deletable,"quality",k)})}catch(e){}
 try{(await c69HqMonths()).forEach(r=>{const k=r.target_month;if(r.status==="deleted")return;const n=Object.values(r.counts||{}).reduce((a,b)=>a+Number(b||0),0);if(r.status!=="excel_saved"){if(n>0)add(unsaved,"hq",k)}else if(r.deletable)add(deletable,"hq",k)})}catch(e){}
 return{unsaved,deletable,size:await c69DbSize()};
}
async function c69AdminNotice(){
 if(c69NoticeBusy||currentScreen!=="home"||typeof canAdmin!=="function"||!canAdmin()||document.getElementById("c69AdminNotice"))return;
 const main=document.querySelector("#app main");if(!main)return;
 const box=document.createElement("div");box.id="c69AdminNotice";main.insertBefore(box,main.firstChild);
 c69NoticeBusy=true;
 try{if(!c69NoticeCache||Date.now()-c69NoticeAt>30*60*1000){c69NoticeCache=await c69CollectNotice();c69NoticeAt=Date.now()}}catch(e){}finally{c69NoticeBusy=false}
 const n=c69NoticeCache;if(!n||!document.body.contains(box))return;
 const fmt=o=>Object.entries(o).map(([m,ks])=>`${C69_MODNAME[m]}（${ks.sort().slice(0,3).map(c69Mon).join("・")}${ks.length>3?` ほか${ks.length-3}か月`:""}）`).join("、");
 let html="";
 if(n.size){const pct=Math.round(n.size.bytes/n.size.limit_bytes*100);if(pct>=70)html+=`<div class="card" style="border:2px solid #dc2626;background:#fef2f2"><b>データの容量が ${pct}% になりました（約${c69MB(n.size.bytes)}MB／${c69MB(n.size.limit_bytes)}MB）</b><div class="small">月次Excelを保管して、3か月たった月を整理してください。上限を超えると使える量が制限されます。</div></div>`}
 if(Object.keys(n.unsaved).length)html+=`<div class="card" style="border:2px solid #d97706;background:#fffbeb"><b>まだデスクネッツに保管していない月があります</b><div class="small">${c69Esc(fmt(n.unsaved))}</div></div>`;
 if(Object.keys(n.deletable).length)html+=`<div class="card" style="border:2px solid #2563eb;background:#eff6ff"><b>3か月たった月の整理ができます</b><div class="small">${c69Esc(fmt(n.deletable))}</div></div>`;
 if(html)html+=`<button class="btn" style="width:100%;margin:-4px 0 10px" ${seikaEventAttrs("click","c69OpenArchive",[])}>月次Excel・履歴管理を開く</button>`;
 box.innerHTML=html;
}
function c69OpenArchive(){c69NoticeCache=null;return monthlyArchivePage()}

/* ④ 本社の月次管理（月次Excel・履歴管理の画面に追加） */
let c69ArchBusy=false;
async function c69ArchiveSection(force){
 if(currentScreen!=="v1101ArchivePage"||typeof canAdmin!=="function"||!canAdmin())return;
 if(!force&&(c69ArchBusy||document.getElementById("c69HqArchive")))return;
 const main=document.querySelector("#app main");if(!main)return;
 let sec=document.getElementById("c69HqArchive");
 if(!sec){sec=document.createElement("div");sec.id="c69HqArchive";main.appendChild(sec)}
 let size=document.getElementById("c69DbSize");
 if(!size){size=document.createElement("div");size.id="c69DbSize";const first=main.querySelector(".notice");(first&&first.parentElement===main?first:main.firstChild)?.after?.(size)||main.prepend(size)}
 c69ArchBusy=true;let rows=[],err="",sz=null;
 try{[rows,sz]=await Promise.all([c69HqMonths(),c69DbSize()])}catch(e){err=(X.h2Err?X.h2Err(e):e.message)||String(e)}finally{c69ArchBusy=false}
 if(sz){const pct=Math.round(sz.bytes/sz.limit_bytes*100);size.innerHTML=`<div class="card" style="${pct>=70?"border:2px solid #dc2626;background:#fef2f2":""}"><b>データの容量：約${c69MB(sz.bytes)}MB／${c69MB(sz.limit_bytes)}MB（${pct}%）</b><div style="height:10px;background:#e2e8f0;border-radius:5px;margin-top:6px;overflow:hidden"><div style="height:10px;width:${Math.min(pct,100)}%;background:${pct>=70?"#dc2626":pct>=50?"#d97706":"#16a34a"}"></div></div><div class="small" style="margin-top:4px">7割（${Math.round(c69MB(sz.limit_bytes)*0.7)}MB）を超えるとホームに注意が出ます。写真の容量は別です。</div></div>`}
 const st=r=>r.status==="deleted"?"整理済み":r.status==="excel_saved"?"保管済み":r.status==="excel_created"?"Excel作成済み":"未処理";
 const cnt=c=>{c=c||{};return `入出庫 ${c.movements||0}・廃棄 ${c.waste||0}・作業 ${c.works||0}・在庫入力 ${c.counts||0}`};
 const card=r=>{const k=r.target_month;let act="";
  if(r.status==="deleted")act=`<div class="small">整理：${c69Esc(r.deleted_at?new Date(r.deleted_at).toLocaleString("ja-JP"):"")} ${c69Esc(r.deleted_by_name||"")}</div>`;
  else{act+=`<button class="btn hqBtnExcelOut" style="width:100%;margin-top:6px" ${seikaEventAttrs("click","c69HqExcel",[k])}>この月の本社Excelをまとめて作る</button>`;
   if(r.status==="excel_created"||r.status==="excel_saved")act+=r.status==="excel_saved"?`<div class="small" style="margin-top:4px">保管：${c69Esc(r.excel_saved_at?new Date(r.excel_saved_at).toLocaleString("ja-JP"):"")} ${c69Esc(r.excel_saved_by_name||"")}</div>`:`<label class="small" style="display:block;margin-top:6px"><input type="checkbox" id="c69Saved_${k}"> Excelをデスクネッツ文書管理の「本社」フォルダへ保管した</label><button class="btn green" style="width:100%;margin-top:4px" ${seikaEventAttrs("click","c69HqSaved",[k])}>保管済みにする</button>`;
   if(r.status==="excel_saved")act+=r.deletable?`<button class="btn" style="width:100%;margin-top:6px;background:#b91c1c;color:#fff" ${seikaEventAttrs("click","c69HqDelete",[k])}>この月の本社データを整理する</button>`:`<div class="small" style="margin-top:4px">整理できるのは ${c69Mon(c69AddM(k,4))} からです（直近3か月は残します）。</div>`}
  return `<div class="box" style="margin:8px 0"><div class="itemHead"><b>${c69Mon(k)}</b><span class="badge">${st(r)}</span></div><div class="small">${cnt(r.counts)}</div>${act}</div>`};
 sec.innerHTML=`<section class="card"><h2 style="margin-top:0">本社のデータ</h2><div class="small">月ごとに、本社のExcel（在庫・在庫入力・在庫表・廃棄・歩留まり・使用数量・品質評価・作業時間）を1つのファイルにまとめて作り、デスクネッツへ保管してから、3か月たった月を整理します。<br>整理で消えるもの：使い切ったロットの入出庫の履歴、廃棄、終わった作業の記録（確定・取消したもの）、在庫入力、期限確認の記録。<br>残るもの：ロット本体（在庫・品質評価・写真）、スタッフ、下処理マスタなどの設定。整理した月の使い切ったロットは、トレース表に入出庫が出なくなります（Excelには残っています）。</div>${err?`<div class="err">読み込めませんでした。${c69Esc(err)}<div class="small">SQL（db/027）が未実行の可能性があります。</div></div>`:rows.length?rows.slice(0,12).map(card).join(""):'<div class="small" style="margin-top:6px">先月以前の本社のデータはまだありません。</div>'}</section>`;
}
async function c69HqExcel(k){
 if(typeof XLSX==="undefined"||!X.excelOut)return alert("Excel機能を読み込めませんでした");
 const wb=XLSX.utils.book_new(),label=c69Mon(k),done=[];
 try{for(const kind of ["stock","counts","table","waste","yield","usage","quality","worktime"])done.push(await X.excelOut(kind,k,wb))}
 catch(e){return alert(`Excelを作れませんでした（${done.length+1}番目）。\n${(X.h2Err?X.h2Err(e):e.message)||e}`)}
 const file=`本社_月次まとめ_${label}.xlsx`;XLSX.writeFile(wb,file);
 try{await callRpc("hq_monthly_mark_created_v1690",{p_month:`${k}-01`,p_file_name:file})}catch(e){return alert((X.h2Err?X.h2Err(e):e.message)||e)}
 c69NoticeCache=null;c69ArchiveSection(true);
}
async function c69HqSaved(k){
 if(!document.getElementById(`c69Saved_${k}`)?.checked)return alert("デスクネッツへ保管したことを確認して、チェックを入れてください");
 try{await callRpc("hq_monthly_confirm_saved_v1690",{p_month:`${k}-01`})}catch(e){return alert((X.h2Err?X.h2Err(e):e.message)||e)}
 c69NoticeCache=null;c69ArchiveSection(true);
}
async function c69HqDelete(k){
 if(!confirm(`${c69Mon(k)}の本社データを整理（削除）します。\n\n消したデータは元に戻せません。\nデスクネッツにExcelが保管されていることを確かめてから進めてください。`))return;
 if(prompt(`確認のため「${c69Mon(k)}」と入力してください`)!==c69Mon(k))return alert("入力が違うため、やめました");
 try{const r=await callRpc("hq_monthly_delete_v1690",{p_month:`${k}-01`});const c=r&&r.counts||{};alert(`${c69Mon(k)}の本社データを整理しました。\n入出庫 ${c.movements||0}件・廃棄 ${c.waste||0}件・作業 ${c.works||0}件・在庫入力 ${c.counts||0}件`)}catch(e){return alert((X.h2Err?X.h2Err(e):e.message)||e)}
 c69NoticeCache=null;c69ArchiveSection(true);
}

(()=>{const app=document.getElementById("app");if(!app||window.c69Observer)return;window.c69Observer=new MutationObserver(()=>{
 if(currentScreen==="home"&&!document.getElementById("c69AdminNotice"))c69AdminNotice();
 else if(currentScreen==="hqStaffPage")c69StaffButtons();
 else if(currentScreen==="v1101ArchivePage"&&!document.getElementById("c69HqArchive"))c69ArchiveSection();
});window.c69Observer.observe(app,{childList:true,subtree:true})})();

/* 操作ガイド */
try{
 const add=(title,steps)=>{const seen=new Set();for(const g of Object.values(typeof V195_ROLE_GUIDES!=="undefined"?V195_ROLE_GUIDES:{}))for(const sec of (g&&g.sections)||[]){if(sec.title!==title||seen.has(sec))continue;seen.add(sec);sec.steps=sec.steps||[];for(const st of steps)if(!sec.steps.includes(st))sec.steps.push(st)}if(typeof V198_GUIDE_SECTIONS!=="undefined")for(const sec of Object.values(V198_GUIDE_SECTIONS)){if(!sec||sec.title!==title||seen.has(sec))continue;seen.add(sec);sec.steps=sec.steps||[];for(const st of steps)if(!sec.steps.includes(st))sec.steps.push(st)}};
 add("使うときに出庫する",["出庫先「原料出し」で出庫すると、「トリミングのロスがあれば入力してください」と出ます。ロスがあれば「ロスを入力する」を押し、kgを入れて保存します（品目は最初から入っています）。ロスがなければ「ロスはない」を押します。"]);
 add("スタッフを登録・削除する（スタッフQR）",["QRをなくした・汚れたときは、名前の横の「QRを作り直す」を押します。新しいQRが1枚印刷でき、古いQR（一覧ボードに載っているものも）は読めなくなります。一覧ボードも印刷し直してください。"]);
 const sec={title:"月次Excelの保管・本社データの整理・データの容量（管理者）",where:"右上のメニュー → 月次Excel・履歴管理",
  steps:["ホームに「まだデスクネッツに保管していない月があります」「3か月たった月の整理ができます」「データの容量が○%になりました」と出たら、「月次Excel・履歴管理を開く」を押します。",
   "いちばん上に、データの容量（約○MB／500MB）が出ます。7割を超えるとホームに注意が出ます。",
   "石岡の履歴（QR・廃棄・歩留まり・品質評価）は、これまでどおりExcel出力 → 保管 → 整理をします。",
   "いちばん下の「本社のデータ」で、月ごとに「この月の本社Excelをまとめて作る」を押すと、本社の8種類のExcelが1つのファイルにまとまって保存されます。",
   "Excelをデスクネッツ文書管理の「本社」フォルダへ保管したら、チェックを入れて「保管済みにする」を押します。",
   "3か月たった月は「この月の本社データを整理する」が出ます。月の名前を入れて確かめてから整理します。消したデータは元に戻せません。"],
  check:"整理したあと、その月が「整理済み」になったか確かめます。",
  caution:"整理で消えるのは、使い切ったロットの入出庫の履歴・廃棄・終わった作業の記録・在庫入力・期限確認の記録です。ロット本体・写真・スタッフ・設定は残ります。"};
 if(typeof V198_GUIDE_SECTIONS!=="undefined")V198_GUIDE_SECTIONS.c69Archive=sec;
 const ag=typeof V195_ROLE_GUIDES!=="undefined"&&V195_ROLE_GUIDES.admin;if(ag&&Array.isArray(ag.sections)&&!ag.sections.some(x=>x.title===sec.title))ag.sections.push(sec);
}catch(e){}
Object.assign(window,{c69RawLossGo,c69RawLossNo,c69Reissue,c69OpenArchive,c69HqExcel,c69HqSaved,c69HqDelete});
})();
