/* ===== v1.199-c147 仕入れ担当者・営業担当者のホームに「出荷予定と確定」 =====
   ・ホームの一番上にまとめカードを出す。
     ①明日の出荷予定（品目ごとの合計kg）。仕入れ担当者は担当品目だけを出し、担当品目の日量と並べて「日量の何倍か」を出す。
     ②いちばん新しい確定（産地報告書）と予定の違い。確定のある客先の予定と確定のkgを比べ、2割以上違う品目を色付きで出す。
       予定・確定の両方が10kg以下の品目は、少しの違いでも2割を超えやすいので出さない。
   ・仕入れ担当者の「担当品目の日量」のボタンにも、明日の予定kgと日量の何倍かを書き足す。
   ・押すと「出荷予定（積み込み表）」の画面が開く。 */
(()=>{
const ROLES=["buyer","sales"];
const RATE=0.2;          // 予定と確定の違い：2割以上
const MANY=1.2,FEW=0.8;  // 明日の予定が日量の1.2倍以上＝多い、0.8倍以下＝少ない
const MIN_KG=10;         // 予定・確定の両方がこれ以下の品目は違いを出さない
const BACK=3;            // 確定は今日から何日さかのぼって探すか
const L=()=>window.c140Lib;
const r1=v=>Math.round(v*10)/10;
const fmt=v=>r1(v).toLocaleString("ja-JP");
const md=k=>`${Number(k.slice(5,7))}/${Number(k.slice(8,10))}`;

/* ---------- 計算（画面に依存しない。テストから直接呼ぶ） ---------- */
function sumKg(lines,filter){const mp=new Map;for(const l of lines||[]){const it=l.item||l.item_name;if(!it||(filter&&!filter(l)))continue;const kg=Number(l.kg);if(!Number.isFinite(kg)||l.kg===null||l.kg===undefined)continue;mp.set(it,(mp.get(it)||0)+kg)}return mp}
/* 予定と確定の違い：確定のある客先の予定だけと比べる（埼玉・深谷など確定のない客先は除く） */
function c147Diffs(planLines,actualLines,mine){
 const cust=new Set((actualLines||[]).map(l=>l.customer||l.customer_name));
 const p=sumKg(planLines,l=>cust.has(l.customer||l.customer_name)),a=sumKg(actualLines);
 const out=[];
 for(const it of new Set([...p.keys(),...a.keys()])){
  if(mine&&!mine.has(it))continue;
  const pk=p.get(it)||0,ak=a.get(it)||0;
  if(pk<=MIN_KG&&ak<=MIN_KG)continue;
  const rate=pk>0?(ak-pk)/pk:null;
  if(rate!==null&&Math.abs(rate)<RATE-1e-9)continue;
  out.push({item:it,plan:pk,actual:ak,rate});
 }
 return out.sort((x,y)=>Math.abs(y.actual-y.plan)-Math.abs(x.actual-x.plan));
}
/* 明日の予定：品目ごとの合計kg（多い順）。daily があれば日量と何倍かを付ける */
function c147Tomorrow(planLines,mine,daily){
 const p=sumKg(planLines);
 return [...p].filter(([it])=>!mine||mine.has(it)).map(([item,kg])=>{
  const d=daily?.[item],avg=d&&d.days?.size?d.kg/d.days.size:null,times=avg>0?kg/avg:null;
  return {item,kg,daily:avg,times,mark:times==null?"":times>=MANY-1e-9?"many":times<=FEW+1e-9?"few":""};
 }).sort((a,b)=>b.kg-a.kg);
}

/* ---------- 読み込み ---------- */
let cache=null,cacheAt=0,loading=null;
async function c147Load(){
 if(cache&&Date.now()-cacheAt<5*60000)return cache;
 if(loading)return loading;
 loading=(async()=>{
  const lib=L(),today=todayKey(),tomorrow=lib.addDays(today,1);
  const plan=await lib.loadPlan(tomorrow);
  let act=null,actDate="",actPlan=null;
  for(let i=0;i<BACK;i++){const d=lib.addDays(today,-i),a=await lib.loadActual(d);if(a===null)break;if(a.active){act=a;actDate=d;actPlan=await lib.loadPlan(d);break}}
  cache={tomorrow,plan,actDate,act,actPlan};cacheAt=Date.now();return cache})();
 try{return await loading}finally{loading=null}
}
function myItems(){if(db?.role!=="buyer")return null;try{return new Set((v1153BuyerOptimalItems()||[]).map(i=>i.name).filter(Boolean))}catch(_){return new Set}}
async function myDaily(){if(db?.role!=="buyer"||typeof window.c134Load!=="function")return null;try{return (await window.c134Load()).by}catch(_){return null}}

/* ---------- 表示 ---------- */
function timesText(r){if(r.times==null)return r.daily==null?'<span class="small">日量なし</span>':"";return `<span class="c147T ${r.mark}">日量の${r.times.toFixed(1)}倍${r.mark==="many"?"・多い":r.mark==="few"?"・少ない":""}</span>`}
function rateText(d){if(d.rate===null)return '<span class="c147R up">予定なし→確定あり</span>';const pc=Math.round(d.rate*100);return `<span class="c147R ${pc>0?"up":"down"}">${pc>0?"+":""}${pc}%</span>`}
function c147Html(data,mine,daily){
 const buyer=!!mine,tom=c147Tomorrow(data.plan?.lines,mine,daily);
 const head=`<div class="c147Head"><b>出荷予定と確定</b>${buyer?'<span class="small">（担当品目）</span>':""}</div>`;
 let s1;
 if(!data.plan?.active)s1=`<div class="small">明日（${md(data.tomorrow)}納品）の積み込み表はまだ取り込まれていません。</div>`;
 else if(!tom.length)s1=`<div class="small">明日（${md(data.tomorrow)}納品）の予定に${buyer?"担当品目は":"品目が"}ありません。</div>`;
 else{const max=buyer?50:8,show=tom.slice(0,max);
  s1=`<table class="table c147Tbl"><tr><th>品目</th><th>予定</th>${buyer?"<th>日量とくらべて</th>":""}</tr>${show.map(r=>`<tr class="${r.mark?`c147Row ${r.mark}`:""}"><td>${esc(r.item)}</td><td><b>${fmt(r.kg)}kg</b></td>${buyer?`<td>${r.daily!=null?`<span class="small">日量${fmt(r.daily)}kg</span><br>`:""}${timesText(r)}</td>`:""}</tr>`).join("")}</table>${tom.length>max?`<div class="small">ほか${tom.length-max}品目</div>`:""}`;
  if(buyer){const none=[...mine].filter(n=>!tom.some(r=>r.item===n)).sort((a,b)=>a.localeCompare(b,"ja"));if(none.length)s1+=`<div class="small">予定なし：${esc(none.join("、"))}</div>`}}
 let s2;
 if(!data.act)s2=`<div class="small">ここ${BACK}日の確定（産地報告書）はまだ取り込まれていません。</div>`;
 else{const diffs=c147Diffs(data.actPlan?.lines,data.act.lines,mine);
  s2=diffs.length?`<table class="table c147Tbl"><tr><th>品目</th><th>予定→確定</th></tr>${diffs.map(d=>`<tr><td>${esc(d.item)}</td><td>${fmt(d.plan)}kg → <b>${fmt(d.actual)}kg</b> ${rateText(d)}</td></tr>`).join("")}</table>`:`<div class="c147Ok">予定と2割以上違う${buyer?"担当品目":"品目"}はありません。</div>`}
 return `${head}
  <div class="c147Sec"><div class="c147Sub">明日（${md(data.tomorrow)}納品）の出荷予定</div>${s1}</div>
  <div class="c147Sec"><div class="c147Sub">${data.act?`${md(data.actDate)}納品の確定と予定の違い（2割以上）`:"確定と予定の違い"}</div>${s2}
   <div class="small">確定のある客先（産地報告書にある社外の客先）の予定とkgで比べます。予定・確定とも${MIN_KG}kg以下の品目は出しません。</div></div>
  <div class="row" style="gap:8px;flex-wrap:wrap;margin-top:8px"><button type="button" class="btn c147Btn" ${seikaEventAttrs("click","c140ShipPlanPage",[data.tomorrow,""])}>明日の出荷予定を開く</button>${data.act?`<button type="button" class="btn btn2" ${seikaEventAttrs("click","c140ShipPlanPage",[data.actDate,""])}>${md(data.actDate)}の確定を開く</button>`:""}</div>`;
}
/* 担当品目の日量のボタンに、明日の予定を書き足す */
function c147Decorate(tom){
 const box=document.getElementById("c134DailyBtns");if(!box)return false;
 const btns=[...box.querySelectorAll("button.c134Btn")];if(!btns.length)return false;
 const by=new Map(tom.map(r=>[r.item,r]));
 for(const b of btns){if(b.querySelector(".c147Add"))continue;const name=b.querySelector("b")?.textContent||"";const r=by.get(name);
  b.insertAdjacentHTML("beforeend",`<span class="c147Add ${r?.mark||""}">${r?`明日 ${fmt(r.kg)}kg${r.times!=null?`（${r.times.toFixed(1)}倍）`:""}`:"明日 予定なし"}</span>`)}
 return true;
}
let injecting=false;
async function c147InjectHome(){
 if(injecting||currentScreen!=="home"||!ROLES.includes(db?.role)||!L()?.canView?.()||document.getElementById("c147Ship"))return;
 const anchor=document.querySelector("#app .homeSummary")||document.querySelector("#app .homePrimary");if(!anchor)return;
 injecting=true;
 try{
  anchor.insertAdjacentHTML("beforebegin",`<div id="c147Ship" class="card c147"><b>出荷予定と確定</b><div class="small">読み込んでいます…</div></div>`);
  let data,daily;
  try{[data,daily]=await Promise.all([c147Load(),myDaily()])}
  catch(e){const c=document.getElementById("c147Ship");if(c)c.innerHTML=`<b>出荷予定と確定</b><div class="small">${esc(L().sqlMissing(e)?"出荷予定の機能（SQL 061）がまだ実行されていません。":"出荷予定を読み込めませんでした。")}</div>`;return}
  const c=document.getElementById("c147Ship");if(!c||currentScreen!=="home")return;
  const mine=myItems();c.innerHTML=c147Html(data,mine,daily);
  if(mine){const tom=c147Tomorrow(data.plan?.lines,mine,daily);let n=0;const t=()=>{if(!c147Decorate(tom)&&n++<40)setTimeout(t,150)};t()}
 }finally{injecting=false}
}
const app=document.getElementById("app");
if(app)new MutationObserver(()=>{if(currentScreen==="home"&&ROLES.includes(db?.role)&&!document.getElementById("c147Ship")&&document.querySelector("#app .homeSummary, #app .homePrimary"))c147InjectHome()}).observe(app,{childList:true,subtree:true});
{const st=document.createElement("style");st.textContent=`
.c147{border:2px solid #1d4ed8}
.c147Head{display:flex;align-items:baseline;gap:6px;font-size:19px}
.c147Sec{margin-top:10px}
.c147Sub{font-weight:900;color:#1e3a8a;margin-bottom:4px}
.c147Tbl{font-size:15px;width:100%}
.c147Tbl td,.c147Tbl th{padding:4px 6px}
.c147Row.many td{background:#fff7ed}
.c147Row.few td{background:#eff6ff}
.c147T{font-weight:800;font-size:13px}
.c147T.many{color:#c2410c}.c147T.few{color:#1d4ed8}
.c147R{display:inline-block;font-weight:900;font-size:13px;padding:1px 6px;border-radius:999px}
.c147R.up{background:#fee2e2;color:#b91c1c}.c147R.down{background:#dbeafe;color:#1d4ed8}
.c147Ok{color:#15803d;font-weight:800}
.c147Btn{background:linear-gradient(90deg,#1e293b 0%,#1d4ed8 55%,#f59e0b 100%) !important;color:#fff !important;border-color:transparent !important}
.c147Add{display:block;font-size:13px;font-weight:800;color:#334155}
.c147Add.many{color:#c2410c}.c147Add.few{color:#1d4ed8}`;document.head.appendChild(st)}

Object.assign(window,{c147InjectHome,c147Load,c147Lib:{c147Diffs,c147Tomorrow,c147Html,c147Decorate,RATE,MIN_KG}});
})();
