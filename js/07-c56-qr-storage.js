
/* ===== v1.199-c56 入庫時の保管場所の初期表示（品目ごとのいつもの保管場所）・Androidの貼り紙PDFを縦向きの紙に回して作成 ===== */
(function(){
function c56RuleIndex(name){const r=qrManagedRuleForName(name);if(!r)return -1;return qrManagedItemList().indexOf(r)}
function c56StorageFor(name){const r=String(name||"").trim()?qrManagedRuleForName(name):null;const v=r&&typeof r==="object"?r.storage:"";return QR_STORAGE_LOCATIONS.includes(v)?v:""}
function c56ApplyStorage(){
 const item=document.getElementById("qrItemName"),loc=document.getElementById("qrLoc");if(!item||!loc)return;
 const auto=loc.dataset.c56auto||"";if(loc.value&&loc.value!==auto)return;
 const v=c56StorageFor(item.value);loc.value=v;loc.dataset.c56auto=v;
 let note=document.getElementById("c56LocNote");if(!note){loc.insertAdjacentHTML("beforebegin",`<div id="c56LocNote" class="small" style="margin:0 0 4px;color:#0f766e;font-weight:700"></div>`);note=document.getElementById("c56LocNote")}
 note.textContent=v?"品目の設定から自動で入れました（違うときは選び直し）":"";note.style.display=v?"block":"none";
}
const c56FillBase=window.qrAutoFillStaff;
window.qrAutoFillStaff=function(){const r=c56FillBase?.apply(this,arguments);try{c56ApplyStorage()}catch(e){console.warn("[保管場所]",e)}return r};
try{qrAutoFillStaff=window.qrAutoFillStaff}catch(e){}
const c56CreateBase=window.qrCreatePage;
window.qrCreatePage=async function(){const r=await c56CreateBase.apply(this,arguments);try{const item=document.getElementById("qrItemName");if(item&&!item.dataset.c56){item.dataset.c56="1";["input","change"].forEach(t=>item.addEventListener(t,c56ApplyStorage))}c56ApplyStorage()}catch(e){console.warn("[保管場所]",e)}return r};
try{qrCreatePage=window.qrCreatePage}catch(e){}
function c56SetStorage(i,v){if(!canQrOperate())return alert("設定権限がありません");qrEnsureMasters();const list=db.qrManagedItems;let r=list[i];if(r===undefined)return;
 if(typeof r==="string")r={name:r,match:"exact",aliases:[]};r={...r};if(QR_STORAGE_LOCATIONS.includes(v))r.storage=v;else delete r.storage;r.storageGuess=false;list[i]=r;save();
 const n=document.getElementById(`c56Guess_${i}`);if(n)n.remove()}
async function c56GuessFromHistory(onlyEmpty=true){
 qrEnsureMasters();let lots=[];try{lots=await qrSelect("qr_lots","select=item_name,storage_location&storage_location=not.is.null&order=created_at.desc&limit=3000")||[]}catch(e){alert("過去の入庫を読み込めませんでした。");return 0}
 let n=0;db.qrManagedItems=db.qrManagedItems.map(r=>{const obj=typeof r==="string"?{name:r,match:"exact",aliases:[]}:{...r};if(onlyEmpty&&QR_STORAGE_LOCATIONS.includes(obj.storage))return r;
  const cnt={};for(const l of lots){if(!QR_STORAGE_LOCATIONS.includes(l.storage_location))continue;if(qrManagedItemMatches(obj,l.item_name))cnt[l.storage_location]=(cnt[l.storage_location]||0)+1}
  const best=Object.entries(cnt).sort((a,b)=>b[1]-a[1])[0];if(!best)return r;obj.storage=best[0];obj.storageGuess=true;n++;return obj});
 db.c56StorageGuessed=true;if(n)save();return n}
async function c56Regess(){const n=await c56GuessFromHistory(true);qrManagedItemsPage(n?`過去の入庫から ${n}品目に仮の保管場所を入れました。確認してください`:"仮に入れられる品目はありませんでした（過去の入庫がない品目は「未設定」のままです）")}
const c56ManagedBase=window.qrManagedItemsPage;
window.qrManagedItemsPage=async function(msg=""){
 qrEnsureMasters();
 if(canQrOperate()&&!qrManagedItemList().some(r=>r&&typeof r==="object"&&r.storage)&&!sessionStorage.getItem("c56Guessed")){sessionStorage.setItem("c56Guessed","1");const n=await c56GuessFromHistory(true);if(n)msg=`過去の入庫で一番多い保管場所を、${n}品目に仮に入れました。「仮」の表示がある品目を確認してください。`+(msg?` ${msg}`:"")}
 const r=await c56ManagedBase.call(this,msg);
 try{const list=qrManagedItemList();
  document.querySelectorAll('[data-seika-click-action="qrRemoveManagedItem"]').forEach(btn=>{let i=-1;try{i=Number(JSON.parse(decodeURIComponent(btn.dataset.seikaClickArgs||"[]"))[0])}catch(e){}const rule=list[i];if(rule===undefined)return;const card=btn.closest(".card");if(!card||card.querySelector(".c56Loc"))return;
   const cur=typeof rule==="object"?rule.storage||"":"",guess=typeof rule==="object"&&rule.storageGuess&&cur;
   card.insertAdjacentHTML("beforeend",`<div class="c56Loc" style="margin-top:8px"><label class="label">いつもの保管場所（入庫時に最初から入ります）${guess?`<span id="c56Guess_${i}" style="margin-left:6px;background:#fef3c7;color:#78350f;font-size:12px;font-weight:800;padding:2px 8px;border-radius:8px">仮（過去の入庫から）</span>`:""}</label><select class="input" ${seikaEventAttrs("change","c56SetStorageFromSelect",[i])} id="c56Loc_${i}"><option value="">未設定（入庫時は「選択」のまま）</option>${QR_STORAGE_LOCATIONS.map(v=>`<option value="${esc(v)}" ${v===cur?"selected":""}>${esc(v)}</option>`).join("")}</select></div>`)});
  const first=document.querySelector(".c56Loc")?.closest(".card");
  if(first&&!document.getElementById("c56GuessCard"))first.insertAdjacentHTML("beforebegin",`<div id="c56GuessCard" class="card notice"><b>いつもの保管場所</b><div class="small">品目ごとに決めておくと、QR入庫で品目を選んだときに保管場所が自動で入ります。「仮」は過去の入庫で一番多かった保管場所です。選び直すと「仮」が消えます。</div><button class="btn btn2" style="margin-top:8px" ${seikaEventAttrs("click","c56Regess",[])}>未設定の品目に、過去の入庫から仮に入れる</button></div>`);
 }catch(e){console.warn("[保管場所設定]",e)}
 return r;
};
try{qrManagedItemsPage=window.qrManagedItemsPage}catch(e){}
function c56SetStorageFromSelect(i){const el=document.getElementById(`c56Loc_${i}`);c56SetStorage(i,el?el.value:"")}
Object.assign(window,{c56SetStorageFromSelect,c56Regess,c56ApplyStorage});
/* Android：横向きの貼り紙を、縦向きの紙に90度回して入れる（iPhone・PCは今のまま） */
const c56Android=/Android/i.test(navigator.userAgent||"");
if(c56Android&&typeof window.html2canvas==="function"&&window.jspdf&&typeof window.jspdf.jsPDF==="function"){
 const h2c=window.html2canvas;
 window.html2canvas=async function(el,opts){const c=await h2c.apply(this,arguments);
  if(!(el&&el.classList&&(el.classList.contains("pdfSheet")||el.classList.contains("hqPdfPage")))||c.width<=c.height)return c;
  const r=document.createElement("canvas");r.width=c.height;r.height=c.width;const x=r.getContext("2d");x.fillStyle="#fff";x.fillRect(0,0,r.width,r.height);x.translate(r.width,0);x.rotate(Math.PI/2);x.drawImage(c,0,0);return r};
 const J=window.jspdf.jsPDF;
 window.jspdf.jsPDF=function(o,...rest){
  const land=o&&typeof o==="object"&&o.orientation==="landscape"&&String(o.format||"a4").toLowerCase()==="a4";
  if(!land)return new J(o,...rest);
  const doc=new J({...o,orientation:"portrait"},...rest),add=doc.addPage.bind(doc),img=doc.addImage.bind(doc);
  doc.addPage=function(f,ori){return add(f||"a4",ori==="landscape"?"portrait":ori)};
  doc.addImage=function(d,f,x,y,w,h,...more){if(w===297&&h===210)return img(d,f,0,0,210,297,...more);return img(d,f,x,y,w,h,...more)};
  return doc};
 Object.assign(window.jspdf.jsPDF,J);window.jspdf.jsPDF.prototype=J.prototype;
}
})();
