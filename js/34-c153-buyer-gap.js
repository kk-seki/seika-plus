/* ===== v1.199-c153 出荷予定と確定のちがい（仕入れ担当者別） =====
   ・ある納品日の「予定（積み込み表）」と「確定」のちがいを、仕入れ担当者の担当品目ごとにまとめる。
     確定：社外は産地報告書、埼玉・深谷は出荷日（納品日の前日）のQRの出庫（c151 と同じ）。
     予定：社外は確定のある客先の予定だけ（埼玉・深谷は積み込み表の埼玉工場・深谷青果センターの行）。本社は積み込み表に入らないので比べない。
   ・仕入れ担当者：自分の担当品目だけを見る（ホームの「出荷予定と確定」から）。
   ・管理者・青果社員：仕入れ担当者ごとに送る文面を作り、「コピー」「LINEで共有」「LINE WORKSで共有」で送る（在庫報告コピーと同じボタン）。
     どの担当者の担当にも入っていない品目は「担当なし」にまとめる。
   ・担当品目は c149 と同じ（適正在庫の担当品目＋仕入れ担当者の一覧でその人の品目になっているQR品目）。
   ・2割以上ちがう品目を先に、客先ごとの内訳つきで。予定・確定とも10kg以下の品目は出さない。 */
(()=>{
const RATE=0.2,MIN_KG=10,BACK=4;
const L=()=>window.c140Lib;
const r1=v=>Math.round(v*10)/10;
const fmt=v=>r1(v).toLocaleString("ja-JP");
const WD=["日","月","火","水","木","金","土"];
const md=k=>`${Number(k.slice(5,7))}/${Number(k.slice(8,10))}`;
const mdw=k=>`${md(k)}（${WD[new Date(k+"T00:00:00Z").getUTCDay()]}）`;
const INHOUSE=[["埼玉",/埼玉/],["深谷",/深谷/]];
const inhouseOf=c=>{const n=String(c||"");for(const [k,re] of INHOUSE)if(re.test(n))return k;return ""};
const cust=l=>l.customer||l.customer_name||"";
const itemOf=l=>l.item||l.item_name||"";
const kgOf=l=>{const v=Number(l.kg);return l.kg===null||l.kg===undefined||!Number.isFinite(v)?null:v};
/* 客先の名前を短く（送る文面用）："(株)せき 埼玉工場"→"埼玉"、"フジフーズ(株) 千葉工場(ニチノウ)"→"フジフーズ 千葉工場" */
function shortCust(c){const h=inhouseOf(c);if(h)return h;return String(c||"").replace(/[（(](株|有)[)）]|株式会社|有限会社/g,"").replace(/[（(][^）)]*[）)]/g,"").replace(/\s+/g," ").trim()}

/* ---------- 計算（画面に依存しない。テストからも呼ぶ） ---------- */
/* 品目ごと・客先ごとの予定と確定。inhouse＝{埼玉:Map(品目→kg),深谷:Map}（出荷日の出庫）、null なら社外だけ */
function c153Compare(planLines,actualLines,inhouse){
 const ext=new Set((actualLines||[]).map(cust).filter(c=>c&&!inhouseOf(c)));
 const by=new Map();
 const cell=(it,c)=>{if(!by.has(it))by.set(it,new Map());const m=by.get(it);if(!m.has(c))m.set(c,{customer:c,plan:0,actual:0});return m.get(c)};
 for(const l of planLines||[]){const c=cust(l),it=itemOf(l),kg=kgOf(l);if(!it||kg==null)continue;const h=inhouseOf(c);
  if(h){if(inhouse)cell(it,h).plan+=kg}else if(ext.has(c))cell(it,c).plan+=kg}
 for(const l of actualLines||[]){const c=cust(l),it=itemOf(l),kg=kgOf(l);if(!it||kg==null||inhouseOf(c))continue;cell(it,c).actual+=kg}
 if(inhouse)for(const [k] of INHOUSE)for(const [it,kg] of inhouse[k]||new Map())cell(it,k).actual+=kg;
 const out=[];
 for(const [item,m] of by){
  const parts=[...m.values()].filter(x=>x.plan||x.actual),plan=parts.reduce((t,x)=>t+x.plan,0),actual=parts.reduce((t,x)=>t+x.actual,0);
  if(plan<=MIN_KG&&actual<=MIN_KG)continue;
  const rate=plan>0?(actual-plan)/plan:null,big=rate===null||Math.abs(rate)>=RATE-1e-9;
  parts.sort((a,b)=>Math.abs(b.actual-b.plan)-Math.abs(a.actual-a.plan));
  out.push({item,plan,actual,diff:actual-plan,rate,big,parts});
 }
 return out.sort((a,b)=>(b.big-a.big)||Math.abs(b.diff)-Math.abs(a.diff));
}
/* 仕入れ担当者ごとに分ける。buyers＝[{id,name,items:Set}]。どの担当にも入らない品目は「担当なし」 */
function c153Group(rows,buyers){
 const owned=new Set;for(const b of buyers)for(const n of b.items)owned.add(n);
 const groups=buyers.map(b=>({...b,rows:rows.filter(r=>b.items.has(r.item))}));
 const none=rows.filter(r=>!owned.has(r.item));
 if(none.length)groups.push({id:"",name:"担当なし",items:new Set(none.map(r=>r.item)),rows:none,none:true});
 return groups;
}
const pct=r=>r.rate===null?"予定なし":`${r.rate>0?"+":r.rate<0?"−":"±"}${Math.abs(Math.round(r.rate*100))}%`;
const sign=v=>`${v>0?"+":v<0?"−":"±"}${fmt(Math.abs(v))}kg`;
function partLine(r,max=4){
 const ps=r.parts.filter(p=>Math.abs(p.actual-p.plan)>=0.05).slice(0,max);
 if(!ps.length)return "";
 const more=r.parts.filter(p=>Math.abs(p.actual-p.plan)>=0.05).length-ps.length;
 return ps.map(p=>`${shortCust(p.customer)} ${fmt(p.plan)}→${fmt(p.actual)}`).join("／")+(more>0?`／ほか${more}客先`:"");
}
/* 送る文面（LINE向け） */
function c153Text(g,date){
 const head=`【出荷予定と確定のちがい】${mdw(date)}納品\n${g.none?"担当なしの品目":`${g.name}さん（担当品目）`}`;
 if(!g.rows.length)return `${head}\n\n担当品目の出荷予定・確定はありませんでした（予定・確定とも10kg以下の品目は省いています）。`;
 const big=g.rows.filter(r=>r.big),small=g.rows.filter(r=>!r.big);
 const lines=[head,""];
 if(big.length){lines.push(`■2割以上ちがう（${big.length}品目）`);for(const r of big){lines.push(`・${r.item}：予定 ${fmt(r.plan)}kg → 確定 ${fmt(r.actual)}kg（${sign(r.diff)}・${pct(r)}）`);const p=partLine(r);if(p)lines.push(`　${p}`)}}
 else lines.push("■2割以上ちがう品目はありませんでした");
 if(small.length){lines.push("",`■2割未満（${small.length}品目）`);for(const r of small)lines.push(`・${r.item}：${fmt(r.plan)} → ${fmt(r.actual)}kg（${pct(r)}）`)}
 lines.push("","※社外は産地報告書、埼玉・深谷は出荷日の出庫で比べています。本社は積み込み表に入らないので比べていません。");
 return lines.join("\n");
}

/* ---------- 読み込み ---------- */
async function findLatest(){
 const lib=L(),today=todayKey(),days=[];for(let i=-1;i<BACK;i++)days.push(lib.addDays(today,-i));
 const acts=await Promise.all(days.map(d=>lib.loadActual(d).catch(()=>null)));
 const k=acts.findIndex(a=>a?.active);return k>=0?days[k]:lib.addDays(today,1);
}
async function c153Load(date){
 const lib=L(),ship=lib.addDays(date,-1);
 const [plan,actual,inhouse]=await Promise.all([lib.loadPlan(date),lib.loadActual(date),(window.c151InhouseOut?window.c151InhouseOut(ship):Promise.resolve(null)).catch(()=>null)]);
 return {date,ship,plan,actual,inhouse};
}
function buyersAll(){
 let list=[];try{list=v1144PurchaseStaffCandidates()||[]}catch(_){}
 const seen=new Set,out=[];
 for(const c of list){const id=typeof v1151CanonicalBuyerId==="function"?v1151CanonicalBuyerId(c.legacy_user_id):c.legacy_user_id;if(!id||seen.has(id))continue;seen.add(id);
  let name=c.display_name||id;try{name=buyerFullName(id,name)||name}catch(_){}
  const items=new Set(typeof window.c149BuyerItemNames==="function"?window.c149BuyerItemNames(c.legacy_user_id):[]);
  out.push({id,name,items})}
 return out;
}
function buyerMe(){
 const items=new Set(typeof window.c149BuyerItemNames==="function"?window.c149BuyerItemNames(db.userId):[]);
 let name=db.user||"";try{name=buyerFullName(db.userId,name)||name}catch(_){}
 return {id:db.userId,name,items};
}
const canCopy=()=>typeof canWorkerReport==="function"&&canWorkerReport();
const canSee=()=>db?.role==="buyer"||canCopy();

/* ---------- 画面 ---------- */
function rowsHtml(g){
 if(!g.rows.length)return '<div class="small">担当品目の出荷予定・確定はありませんでした。</div>';
 return `<table class="table c153Tbl"><tr><th>品目</th><th>予定→確定</th></tr>${g.rows.map(r=>`<tr class="${r.big?"c153Big":""}"><td><b>${esc(r.item)}</b></td><td>${fmt(r.plan)}kg → <b>${fmt(r.actual)}kg</b> <span class="c153R ${r.diff>0?"up":r.diff<0?"down":""}">${esc(pct(r))}</span>${partLine(r,6)?`<div class="small">${esc(partLine(r,6))}</div>`:""}</td></tr>`).join("")}</table>`;
}
async function c153GapPage(date="",msg=""){
 if(!canSee()){alert("仕入れ担当者・管理者・青果社員が使えます");return home()}
 setScreen("c153GapPage",[date,msg]);
 pageShell("出荷予定と確定のちがい","読み込んでいます",'<div class="card"><div class="notice">読み込んでいます。</div></div>');
 let data;
 try{date=date||await findLatest();data=await c153Load(date)}
 catch(e){return pageShell("出荷予定と確定のちがい","",`<div class="err">${esc(L()?.sqlMissing?.(e)?"出荷予定の機能（SQL 061・062）がまだ実行されていません。":String(e?.message||e))}</div><button class="btn btn2" style="width:100%" ${seikaEventAttrs("click","home",[])}>ホームへ</button>`)}
 if(currentScreen!=="c153GapPage")return;
 const lib=L(),nav=`<div class="row" style="gap:8px;flex-wrap:wrap;align-items:center"><button class="btn btn2" ${seikaEventAttrs("click","c153GapPage",[lib.addDays(date,-1),""])}>前の日</button><input type="date" value="${esc(date)}" ${seikaEventAttrs("change","c153GapPage",[{__seikaValue:true},""])} style="font-size:18px;padding:6px"><button class="btn btn2" ${seikaEventAttrs("click","c153GapPage",[lib.addDays(date,1),""])}>次の日</button></div>
  <div class="small" style="margin-top:6px">納品日 <b>${mdw(date)}</b> ／ 出荷日 <b>${mdw(data.ship)}</b></div>`;
 const back=`<button class="btn btn2" style="width:100%;margin-top:8px" ${seikaEventAttrs("click","home",[])}>ホームへ</button>`;
 if(!data.actual?.active){
  return pageShell("出荷予定と確定のちがい",`${mdw(date)}納品`,`${msg?`<div class="ok">${esc(msg)}</div>`:""}<div class="card">${nav}<div class="notice" style="margin-top:10px">この日の確定（産地報告書）はまだ取り込まれていません。産地報告書は翌日の納品分が10時ごろに届きます。</div></div>${back}`);
 }
 const rows=c153Compare(data.plan?.lines,data.actual.lines,data.inhouse);
 const note=`<div class="small">社外は産地報告書の確定と、確定のある客先の予定で比べます。埼玉・深谷は積み込み表の予定と、出荷日のQRの出庫で比べます。本社は積み込み表に入らないので比べません。予定・確定とも${MIN_KG}kg以下の品目は出しません。</div>${data.inhouse===null?'<div class="small">埼玉・深谷への出庫を読み込めなかったので、社外だけで比べています。</div>':""}`;
 if(!canCopy()){
  const g=c153Group(rows,[buyerMe()])[0];
  const mine=g.items.size?g:{...g,rows,name:g.name};
  return pageShell("出荷予定と確定のちがい",`${mdw(date)}納品・${g.items.size?"担当品目":"担当品目が未設定のため全品目"}`,`${msg?`<div class="ok">${esc(msg)}</div>`:""}<div class="card">${nav}</div><div class="card"><b>${esc(mine.name)}さん${g.items.size?"の担当品目":"（全品目）"}</b>${rowsHtml(mine)}${note}</div>${back}`);
 }
 const groups=c153Group(rows,buyersAll());
 const all=groups.filter(g=>g.rows.length).map(g=>c153Text(g,date)).join("\n\n――――――――\n\n");
 const sec=groups.map((g,i)=>{const id=`c153Text${i}`,txt=c153Text(g,date),big=g.rows.filter(r=>r.big).length;
  return `<div class="card c153Card"><div class="c153Head"><b>${esc(g.none?"担当なしの品目":`${g.name}さん`)}</b><span class="small">${g.rows.length}品目${big?`・<span class="c153Warn">2割以上 ${big}</span>`:""}</span></div>
   <details${big?" open":""}><summary class="small" style="cursor:pointer">内容を見る</summary>${rowsHtml(g)}</details>
   <textarea id="${id}" class="textarea c153Ta" rows="6">${esc(txt)}</textarea>
   <div class="row" style="margin-top:8px;gap:6px;flex-wrap:wrap"><button class="btn blue" ${seikaEventAttrs("click","copyTextFrom",[id])}>コピー</button><button class="btn btn2" ${seikaEventAttrs("click","shareLineFrom",[id])}>LINEで共有</button><button class="btn btn2" ${seikaEventAttrs("click","shareLineWorksFrom",[id])}>LINE WORKSで共有</button></div></div>`}).join("");
 pageShell("出荷予定と確定のちがい（仕入れ担当者別）",`${mdw(date)}納品・担当者ごとに送れます`,`${msg?`<div class="ok">${esc(msg)}</div>`:""}<div class="card">${nav}${note}</div>${sec}
  <div class="card"><b>全員分をまとめて</b><textarea id="c153TextAll" class="textarea c153Ta" rows="6">${esc(all||"この日はちがいのある品目がありませんでした。")}</textarea><div class="row" style="margin-top:8px;gap:6px;flex-wrap:wrap"><button class="btn blue" ${seikaEventAttrs("click","copyTextFrom",["c153TextAll"])}>コピー</button><button class="btn btn2" ${seikaEventAttrs("click","shareLineFrom",["c153TextAll"])}>LINEで共有</button><button class="btn btn2" ${seikaEventAttrs("click","shareLineWorksFrom",["c153TextAll"])}>LINE WORKSで共有</button></div></div>${back}`);
}

/* ---------- 入口 ---------- */
/* ①出荷予定（積み込み表）の画面 ②在庫報告コピー（管理者・青果社員） ③ホームの「出荷予定と確定」カード（仕入れ担当者） */
const ENTRY_ID="c153Entry";
function entryHtml(){return `<div id="${ENTRY_ID}" class="card"><b>出荷予定と確定のちがい${canCopy()?"（仕入れ担当者別・送る用）":"（担当品目）"}</b><div class="small">${canCopy()?"仕入れ担当者ごとに、予定と確定のちがいを送る文面を作ります。":"担当品目の予定と確定のちがいを、客先ごとの内訳つきで見られます。"}</div><button class="btn c153Btn" style="width:100%;margin-top:8px" ${seikaEventAttrs("click","c153GapPage",["",""])}>ちがいを見る${canCopy()?"・送る":""}</button></div>`}
function addEntry(screen){
 if(!canSee()||currentScreen!==screen||document.getElementById(ENTRY_ID))return false;
 const main=document.querySelector("#app main.wrap")||document.getElementById("app");if(!main)return false;
 const first=main.querySelector(".card");if(!first)return false;
 first.insertAdjacentHTML("afterend",entryHtml());return true;
}
function wrapAfter(fn,screen,roleOk){
 const base=window[fn];if(typeof base!=="function"||base.__c153)return;
 const w=function(...a){const r=base.apply(this,a);Promise.resolve(r).then(()=>{if(roleOk())addEntry(screen)}).catch(()=>{});return r};
 w.__c153=true;window[fn]=w;try{if(fn==="lineCopyPage")lineCopyPage=w}catch(_){}
}
wrapAfter("c140ShipPlanPage","c140ShipPlanPage",canSee);
wrapAfter("lineCopyPage","lineCopyPage",canCopy);
/* ホームのカード（c147）に、仕入れ担当者向けのボタンを足す */
const app=document.getElementById("app");
if(app)new MutationObserver(()=>{
 if(currentScreen!=="home"||db?.role!=="buyer")return;
 const c=document.getElementById("c147Ship");if(!c||c.dataset.ready!=="1"||c.querySelector(".c153HomeBtn"))return;
 const row=c.querySelector(".row");if(!row)return;
 row.insertAdjacentHTML("beforeend",`<button type="button" class="btn btn2 c153HomeBtn" ${seikaEventAttrs("click","c153GapPage",["",""])}>担当品目のちがいを詳しく</button>`);
}).observe(app,{childList:true,subtree:true});

/* 操作ガイド */
try{if(typeof V195_ROLE_GUIDES!=="undefined"){
 const send={title:"出荷予定と確定のちがいを仕入れ担当者に送る",where:"ホーム →「出荷予定（積み込み表）」または「在庫報告コピー」→「ちがいを見る・送る」",
  steps:["いちばん新しい確定（産地報告書）の納品日が出ます。「前の日」「次の日」や日付で切り替えます。","仕入れ担当者ごとに、担当品目の予定と確定のちがい（2割以上ちがう品目を先に、客先ごとの内訳つき）が出ます。","送る文面の下の「コピー」「LINEで共有」「LINE WORKSで共有」で送ります。いちばん下に全員分をまとめた文面もあります。"],
  check:"社外は産地報告書、埼玉・深谷は出荷日のQRの出庫で比べます。",caution:"本社は積み込み表に入らないので比べません。どの担当にも入っていない品目は「担当なし」にまとまります。"};
 const see={title:"担当品目の予定と確定のちがいを見る",where:"ホーム →「出荷予定と確定」→「担当品目のちがいを詳しく」",
  steps:["担当品目ごとに、予定と確定のkgと、ちがい（%）が出ます。2割以上ちがう品目が上に来ます。","品目の下に、客先ごとの予定→確定が出ます。"],
  check:"担当品目は、品目設定の担当と、仕入れ担当者の一覧（人参→荒木さんなど）で決まります。",caution:"予定・確定とも10kg以下の品目は出ません。"};
 const add=(r,s)=>{const g=V195_ROLE_GUIDES[r];if(g&&Array.isArray(g.sections)&&!g.sections.some(x=>x&&x.title===s.title))g.sections.push(s)};
 add("admin",send);add("worker",send);add("buyer",see);
}}catch(_){}

{const st=document.createElement("style");st.textContent=`
.c153Btn{background:linear-gradient(90deg,#1e293b 0%,#1d4ed8 55%,#f59e0b 100%) !important;color:#fff !important;border-color:transparent !important}
.c153Head{display:flex;justify-content:space-between;align-items:baseline;gap:8px;font-size:17px}
.c153Warn{color:#b91c1c;font-weight:900}
.c153Tbl{font-size:14px;width:100%;margin-top:6px}
.c153Tbl td,.c153Tbl th{padding:4px 6px;vertical-align:top}
.c153Big td{background:#fff7ed}
.c153R{display:inline-block;font-weight:900;font-size:12px;padding:1px 6px;border-radius:999px;background:#e5e7eb}
.c153R.up{background:#fee2e2;color:#b91c1c}.c153R.down{background:#dbeafe;color:#1d4ed8}
.c153Ta{margin-top:8px;font-size:14px}`;document.head.appendChild(st)}

Object.assign(window,{c153GapPage,c153Lib:{c153Compare,c153Group,c153Text,shortCust,RATE,MIN_KG}});
})();
