/* ===== v1.199-c147 仕入れ担当者・営業担当者のホームに「出荷予定と確定」 =====
   ・ホームの一番上にまとめカードを出す。
     ①明日の出荷予定（品目ごとの合計kg）。仕入れ担当者は担当品目だけを出し、担当品目の日量と並べて「日量の何倍か」を出す。
     ②いちばん新しい確定（産地報告書）と予定の違い（産地報告書は翌日の納品分なので明日から探す。c149）。確定のある客先の予定と確定のkgを比べ、2割以上違う品目を色付きで出す。
       予定・確定の両方が10kg以下の品目は、少しの違いでも2割を超えやすいので出さない。
   ・仕入れ担当者の「担当品目の日量」のボタンにも、明日の予定kgと日量の何倍かを書き足す。
   ・押すと「出荷予定（積み込み表）」の画面が開く。 */
(()=>{
const ROLES=["buyer","sales"];
const RATE=0.2;          // 予定と確定の違い：2割以上
const MANY=1.2,FEW=0.8;  // 明日の予定が日量の1.2倍以上＝多い、0.8倍以下＝少ない
const MIN_KG=10;         // 予定・確定の両方がこれ以下の品目は違いを出さない
const BACK=3;            // 確定は明日から探し、今日から何日さかのぼるか（明日・今日・昨日・おととい）
const L=()=>window.c140Lib;
const r1=v=>Math.round(v*10)/10;
const fmt=v=>r1(v).toLocaleString("ja-JP");
const md=k=>`${Number(k.slice(5,7))}/${Number(k.slice(8,10))}`;

/* ---------- 計算（画面に依存しない。テストから直接呼ぶ） ---------- */
function sumKg(lines,filter){const mp=new Map;for(const l of lines||[]){const it=l.item||l.item_name;if(!it||(filter&&!filter(l)))continue;const kg=Number(l.kg);if(!Number.isFinite(kg)||l.kg===null||l.kg===undefined)continue;mp.set(it,(mp.get(it)||0)+kg)}return mp}
/* 予定と確定の違い：確定のある客先の予定だけと比べる（埼玉・深谷など確定のない客先は除く） */
/* 社内の客先：積み込み表の客先名で見分ける（(株)せき 埼玉工場・(株)せき 深谷青果センター） */
const INHOUSE=[["埼玉",/埼玉/],["深谷",/深谷/]];
const inhouseOf=c=>{const n=String(c||"");for(const [k,re] of INHOUSE)if(re.test(n))return k;return ""};
/* 予定と確定の違い（c151）：
   社外＝確定のある客先（産地報告書）の予定と、産地報告書の確定。
   社内（埼玉・深谷）＝積み込み表の予定と、出荷日（納品日の前日）の出庫（QRの出庫先「埼玉」「深谷」）。inhouse が null のときは社外だけ。 */
function c147Diffs(planLines,actualLines,mine,inhouse){
 const ext=new Set((actualLines||[]).map(l=>l.customer||l.customer_name).filter(c=>!inhouseOf(c)));
 const parts=[["社外",sumKg(planLines,l=>ext.has(l.customer||l.customer_name)),sumKg(actualLines,l=>!inhouseOf(l.customer||l.customer_name))]];
 if(inhouse)for(const [k] of INHOUSE)parts.push([k,sumKg(planLines,l=>inhouseOf(l.customer||l.customer_name)===k),inhouse[k]||new Map]);
 const items=new Set();for(const [,p,a] of parts){for(const k of p.keys())items.add(k);for(const k of a.keys())items.add(k)}
 const out=[];
 for(const it of items){
  if(mine&&!mine.has(it))continue;
  const by=parts.map(([label,p,a])=>({label,plan:p.get(it)||0,actual:a.get(it)||0})).filter(x=>x.plan||x.actual);
  const pk=by.reduce((t,x)=>t+x.plan,0),ak=by.reduce((t,x)=>t+x.actual,0);
  if(pk<=MIN_KG&&ak<=MIN_KG)continue;
  const rate=pk>0?(ak-pk)/pk:null;
  if(rate!==null&&Math.abs(rate)<RATE-1e-9)continue;
  out.push({item:it,plan:pk,actual:ak,rate,parts:by});
 }
 return out.sort((x,y)=>Math.abs(y.actual-y.plan)-Math.abs(x.actual-x.plan));
}
/* 明日の予定：品目ごとの合計kg（多い順）。daily があれば日量と何倍かを付ける。
   c151：日量は社内（埼玉・深谷・本社・現場作業など）への出庫も含む。積み込み表には埼玉・深谷は入っているが本社は入らないので、
   本社の分は出庫履歴から足す（本社分＝昨日までの7日間の本社への出庫 ÷ 出庫した日数。日量と同じ割り方）。比べるのは「予定＋本社分」と日量。
   荻沼（本社管轄の協力工場。人参・大根・玉葱を加工）への人参・大根は本社からの発注なので、本社の分に入れる（玉葱は入れない）。 */
function c147Tomorrow(planLines,mine,daily){
 const p=sumKg(planLines);
 return [...p].filter(([it])=>!mine||mine.has(it)).map(([item,kg])=>{
  const d=daily?.[item],nd=d?.days?.size||0,avg=nd?d.kg/nd:null,hq=nd&&d.hqKg>0?d.hqKg/nd:0,total=kg+hq,times=avg>0?total/avg:null;
  const inh=INHOUSE.map(([k])=>[k,sumKg(planLines,l=>inhouseOf(l.customer||l.customer_name)===k).get(item)||0]).filter(([,v])=>v>0);
  return {item,kg,hq,total,inh,daily:avg,times,mark:times==null?"":times>=MANY-1e-9?"many":times<=FEW+1e-9?"few":""};
 }).sort((a,b)=>b.kg-a.kg);
}

/* ---------- 読み込み ---------- */
let cache=null,cacheAt=0,loading=null;
/* 出荷日の社内への出庫（埼玉・深谷）を品目ごとのkgに（c151）。重さは出庫の重さ、なければロットの量目×数（日量と同じ） */
async function c151InhouseOut(day){
 const from=new Date(day+"T00:00:00+09:00"),to=new Date(from.getTime()+864e5),dest=INHOUSE.map(([k])=>encodeURIComponent(k)).join(",");
 const q=`select=*&movement_type=eq.${encodeURIComponent("出庫")}&destination=in.(${dest})&occurred_at=gte.${encodeURIComponent(from.toISOString())}&occurred_at=lt.${encodeURIComponent(to.toISOString())}&limit=3000`;
 const moves=(await qrSelect("qr_lot_movements",q)||[]).filter(m=>!m.cancelled_at);
 const ids=[...new Set(moves.map(m=>m.lot_id).filter(Boolean))],lots=new Map,parts=[];
 for(let i=0;i<ids.length;i+=80)parts.push(ids.slice(i,i+80));
 for(const rows of await Promise.all(parts.map(part=>qrSelect("qr_lots",`select=*&id=in.(${part.join(",")})`))))for(const l of rows||[])lots.set(l.id,l);
 const out={};for(const [k] of INHOUSE)out[k]=new Map;let unknown=0;
 for(const m of moves){const k=String(m.destination||"").trim();if(!out[k])continue;const l=lots.get(m.lot_id);let name="";try{name=qrResolveInventoryItem(l)?.item?.name||""}catch(_){}name=name||String(l?.item_name||m.item_name||"").trim();if(!name)continue;
  let kg=null;if(m.weight!==null&&m.weight!==undefined&&m.weight!==""&&Number.isFinite(Number(m.weight)))kg=Number(m.weight);else{try{const v=l?v163LotKgAtQuantity(l,Number(m.qty||0)):0;kg=v>0?v:null}catch(_){}}
  if(kg==null){unknown++;continue}out[k].set(name,(out[k].get(name)||0)+kg)}
 out.unknown=unknown;return out;
}
/* c154：埼玉・深谷の先送り。翌日分を前の日にまとめて出庫したときは、積み込み表（納品日）と出庫日がずれる。
   納品日Dの比べる出庫＝出荷日（D−1）の出庫＋「D−2の出庫のうち、前日分（Dの前日の積み込み表）を超えた分」（品目ごと）。
   前日分の積み込み表がないときは足さない（どこまでが前日分か分からないため）。 */
function c154AheadMerge(outShip,outPrev,prevPlanLines){
 if(!outShip)return outShip;
 const res={unknown:outShip.unknown||0,ahead:{}};
 for(const [k] of INHOUSE){
  const m=new Map(outShip[k]||new Map()),ah=new Map();
  if(outPrev&&prevPlanLines){
   const pp=sumKg(prevPlanLines,l=>inhouseOf(l.customer||l.customer_name)===k);
   for(const [it,kg] of outPrev[k]||new Map()){const extra=kg-(pp.get(it)||0);if(extra>0.05){ah.set(it,extra);m.set(it,(m.get(it)||0)+extra)}}
  }
  res[k]=m;res.ahead[k]=ah;
 }
 return res;
}
async function c154InhouseFor(planDate){
 const lib=L(),ship=lib.addDays(planDate,-1),prev=lib.addDays(planDate,-2),get=window.c151InhouseOut||c151InhouseOut;
 const [a,b,pp]=await Promise.all([get(ship),get(prev).catch(()=>null),lib.loadPlan(ship).catch(()=>null)]);
 return c154AheadMerge(a,b,pp?.lines?.length?pp.lines:null);
}
/* c151：まとめて同時に読む（明日の予定・確定の候補4日分）。社内の出庫は確定の日が決まってから */
async function c147Load(){
 if(cache&&Date.now()-cacheAt<5*60000)return cache;
 if(loading)return loading;
 loading=(async()=>{
  const lib=L(),today=todayKey(),tomorrow=lib.addDays(today,1);
  const days=[];for(let i=-1;i<BACK;i++)days.push(lib.addDays(today,-i));  // 明日→今日→昨日→おととい
  const [plan,...acts]=await Promise.all([lib.loadPlan(tomorrow),...days.map(d=>lib.loadActual(d))]);
  let act=null,actDate="",actPlan=null,inhouse=null,shipDate="";
  const k=acts.findIndex(a=>a?.active);
  if(k>=0){act=acts[k];actDate=days[k];shipDate=lib.addDays(actDate,-1);
   [actPlan,inhouse]=await Promise.all([actDate===tomorrow?plan:lib.loadPlan(actDate),c154InhouseFor(actDate).catch(()=>null)])}
  cache={tomorrow,plan,actDate,act,actPlan,inhouse,shipDate,today};cacheAt=Date.now();return cache})();
 try{return await loading}finally{loading=null}
}
function c147Fresh(){return !!cache&&Date.now()-cacheAt<5*60000}
/* 仕入れ担当者の担当品目の名前（c149）：適正在庫を設定した担当品目に加えて、
   QRで管理する品目のうち、仕入れ担当者の一覧（07_営業仕入れ担当者カード）でこの人の品目になっているもの（例：人参→荒木さん） */
function c149BuyerItemNames(userId=db?.userId){
 const set=new Set;
 try{for(const i of v1153BuyerOptimalItems(userId)||[])if(i?.name)set.add(i.name)}catch(_){}
 try{
  const me=typeof v1151CanonicalBuyerId==="function"?v1151CanonicalBuyerId(userId):userId;
  const names=typeof qrAllowedItemNames==="function"?qrAllowedItemNames()||[]:[];
  for(const n of names){if(!n||set.has(n))continue;const c=window.v1144AutoPurchaseStaffForItemName?.(n);const id=c?.legacy_user_id;if(id&&(typeof v1151CanonicalBuyerId==="function"?v1151CanonicalBuyerId(id):id)===me)set.add(n)}
 }catch(_){}
 return [...set].sort((a,b)=>a.localeCompare(b,"ja"));
}
/* 担当品目が1つもない仕入れ担当者は、全品目を出す（何も出ないと役に立たないため） */
function myItems(){if(db?.role!=="buyer")return null;const set=new Set(c149BuyerItemNames());return set.size?set:null}
async function myDaily(){if(db?.role!=="buyer"||typeof window.c134Load!=="function")return null;try{return (await window.c134Load()).by}catch(_){return null}}

/* ---------- 表示 ---------- */
function timesText(r){if(r.times==null)return r.daily==null?'<span class="small">日量なし</span>':"";return `<span class="c147T ${r.mark}">日量の${r.times.toFixed(1)}倍${r.mark==="many"?"・多い":r.mark==="few"?"・少ない":""}</span>`}
function rateText(d){if(d.rate===null)return '<span class="c147R up">予定なし→確定あり</span>';const pc=Math.round(d.rate*100);return `<span class="c147R ${pc>0?"up":"down"}">${pc>0?"+":""}${pc}%</span>`}
function c147Html(data,mine,daily){
 const buyer=!!mine,noMine=db?.role==="buyer"&&!mine,tom=c147Tomorrow(data.plan?.lines,mine,daily);
 const head=`<div class="c147Head"><b>出荷予定と確定</b>${buyer?'<span class="small">（担当品目）</span>':noMine?'<span class="small">（担当品目が未設定のため全品目）</span>':""}</div>`;
 let s1;
 if(!data.plan?.active)s1=`<div class="small">明日（${md(data.tomorrow)}納品）の積み込み表はまだ取り込まれていません。</div>`;
 else if(!tom.length)s1=`<div class="small">明日（${md(data.tomorrow)}納品）の予定に${buyer?"担当品目は":"品目が"}ありません。</div>`;
 else{const max=buyer?50:8,show=tom.slice(0,max);
  s1=`<table class="table c147Tbl"><tr><th>品目</th><th>予定</th>${buyer?"<th>日量とくらべて</th>":""}</tr>${show.map(r=>`<tr class="${r.mark?`c147Row ${r.mark}`:""}"><td>${esc(r.item)}</td><td><b>${fmt(r.kg)}kg</b>${r.inh.length?`<div class="small">うち${r.inh.map(([k,v])=>`${k} ${fmt(v)}kg`).join("・")}</div>`:""}${r.hq>0?`<div class="small">＋本社 ${fmt(r.hq)}kg<br>＝${fmt(r.total)}kg</div>`:""}</td>${buyer?`<td>${r.daily!=null?`<span class="small">日量${fmt(r.daily)}kg</span><br>`:""}${timesText(r)}</td>`:""}</tr>`).join("")}</table>${tom.length>max?`<div class="small">ほか${tom.length-max}品目</div>`:""}`;
  if(buyer){const none=[...mine].filter(n=>!tom.some(r=>r.item===n)).sort((a,b)=>a.localeCompare(b,"ja"));if(none.length)s1+=`<div class="small">予定なし：${esc(none.join("、"))}</div>`}}
 let s2;
 if(!data.act)s2=`<div class="small">明日〜${BACK-1}日前の確定（産地報告書）はまだ取り込まれていません。</div>`;
 else{const diffs=c147Diffs(data.actPlan?.lines,data.act.lines,mine,data.inhouse);
  const partText=d=>d.parts.length>1||d.parts[0]?.label!=="社外"?`<div class="small">${d.parts.map(x=>`${x.label} ${fmt(x.plan)}→${fmt(x.actual)}`).join("・")}</div>`:"";
  s2=diffs.length?`<table class="table c147Tbl"><tr><th>品目</th><th>予定→確定</th></tr>${diffs.map(d=>`<tr><td>${esc(d.item)}</td><td>${fmt(d.plan)}kg → <b>${fmt(d.actual)}kg</b> ${rateText(d)}${partText(d)}</td></tr>`).join("")}</table>`:`<div class="c147Ok">予定と2割以上違う${buyer?"担当品目":"品目"}はありません。</div>`;
  if(data.inhouse===null)s2+=`<div class="small">埼玉・深谷への出庫を読み込めなかったので、社外だけで比べています。</div>`;
  else if(data.shipDate>=data.today)s2+=`<div class="small">埼玉・深谷の確定は、出荷日 ${md(data.shipDate)} の出庫です（今日の分は途中までです）。</div>`}
 return `${head}
  <div class="c147Sec"><div class="c147Sub">明日（${md(data.tomorrow)}納品）の出荷予定</div>${s1}${buyer?'<div class="small">日量は社内（埼玉・深谷・本社など）への出庫も含みます。本社は積み込み表に入らないので、本社への出庫（昨日までの7日間。荻沼への人参・大根は本社の分）から1日分を足して比べます。</div>':""}</div>
  <div class="c147Sec"><div class="c147Sub">${data.act?`${md(data.actDate)}納品の確定と予定の違い（2割以上）`:"確定と予定の違い"}</div>${s2}
   <div class="small">社外は産地報告書の確定と、確定のある客先の予定で比べます。埼玉・深谷は積み込み表の予定と、出荷日（納品日の前日）の出庫で比べます（翌日分を前の日に先送りした出庫も足します）。kgで比べ、予定・確定とも${MIN_KG}kg以下の品目は出しません。</div></div>
  <div class="row" style="gap:8px;flex-wrap:wrap;margin-top:8px"><button type="button" class="btn c147Btn" ${seikaEventAttrs("click","c140ShipPlanPage",[data.tomorrow,""])}>明日の出荷予定を開く</button>${data.act?`<button type="button" class="btn btn2" ${seikaEventAttrs("click","c140ShipPlanPage",[data.actDate,""])}>${md(data.actDate)}の確定を開く</button>`:""}</div>`;
}
/* 担当品目の日量のボタンに、明日の予定を書き足す */
function c147Decorate(tom){
 const box=document.getElementById("c134DailyBtns");if(!box)return false;
 const btns=[...box.querySelectorAll("button.c134Btn")];if(!btns.length)return false;
 const by=new Map(tom.map(r=>[r.item,r]));
 for(const b of btns){if(b.querySelector(".c147Add"))continue;const name=b.querySelector("b")?.textContent||"";const r=by.get(name);
  b.insertAdjacentHTML("beforeend",`<span class="c147Add ${r?.mark||""}">${r?`明日 ${fmt(r.total)}kg${r.hq>0?`（本社込み）`:""}${r.times!=null?`（${r.times.toFixed(1)}倍）`:""}`:"明日 予定なし"}</span>`)}
 return true;
}
/* c150：起動直後はホームが何度か描き直される。読み込み中に描き直されてカードが消えたときは、読み終わったあとにもう一度出す。
   日量のボタン（c134）が描き直されたときも、覚えておいた明日の予定をもう一度書き足す。 */
let injecting=false,lastTom=null;
async function c147InjectHome(){
 if(injecting||currentScreen!=="home"||!ROLES.includes(db?.role)||!L()?.canView?.()||document.getElementById("c147Ship"))return;
 const anchor=document.querySelector("#app .homeSummary")||document.querySelector("#app .homePrimary");if(!anchor)return;
 injecting=true;
 try{
  /* c151：読み込み済み（アプリを開いたときに先に読んでおく）なら、「読み込んでいます」を出さずに一度で全部出す */
  if(!c147Fresh())anchor.insertAdjacentHTML("beforebegin",`<div id="c147Ship" class="card c147"><b>出荷予定と確定</b><div class="small">読み込んでいます…</div></div>`);
  let data,daily;
  try{[data,daily]=await Promise.all([c147Load(),myDaily()])}
  catch(e){const c=document.getElementById("c147Ship");if(c)c.innerHTML=`<b>出荷予定と確定</b><div class="small">${esc(L().sqlMissing(e)?"出荷予定の機能（SQL 061）がまだ実行されていません。":"出荷予定を読み込めませんでした。")}</div>`;return}
  const mine=myItems();
  lastTom=mine?c147Tomorrow(data.plan?.lines,mine,daily):null;
  if(currentScreen!=="home")return;
  let c=document.getElementById("c147Ship");
  if(!c){const a=document.querySelector("#app .homeSummary")||document.querySelector("#app .homePrimary");if(!a)return;a.insertAdjacentHTML("beforebegin",`<div id="c147Ship" class="card c147"></div>`);c=document.getElementById("c147Ship")}
  c.innerHTML=c147Html(data,mine,daily);c.dataset.ready="1";
  if(lastTom){let n=0;const t=()=>{if(!c147Decorate(lastTom)&&n++<40)setTimeout(t,150)};t()}
 }finally{
  injecting=false;
  /* 読み込み中に描き直されてカードが消えていたら、もう一度（読み込んだ内容は5分覚えているのですぐ出る） */
  if(currentScreen==="home"&&!document.getElementById("c147Ship")&&document.querySelector("#app .homeSummary, #app .homePrimary"))setTimeout(()=>c147InjectHome(),0);
 }
}
/* c151：アプリを開いたら、ホームを描く前に出荷予定と日量を先に読んでおく（ホームでは読み込み待ちなしで出る） */
function c151Prefetch(n=0){
 if(ROLES.includes(db?.role)&&L()?.canView?.()&&typeof qrSelect==="function"&&(db?.items||[]).length){/* 品目（アプリのデータ）を読み終えてから */Promise.all([c147Load(),myDaily()]).catch(()=>{});return}
 if(n<120)setTimeout(()=>c151Prefetch(n+1),500);
}
setTimeout(()=>c151Prefetch(),0);
const app=document.getElementById("app");
if(app)new MutationObserver(()=>{
 if(currentScreen!=="home"||!ROLES.includes(db?.role))return;
 if(!document.getElementById("c147Ship")&&document.querySelector("#app .homeSummary, #app .homePrimary"))c147InjectHome();
 if(lastTom){const box=document.getElementById("c134DailyBtns");if(box&&box.querySelector("button.c134Btn:not(:has(.c147Add))"))c147Decorate(lastTom)}
}).observe(app,{childList:true,subtree:true});
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

Object.assign(window,{c147InjectHome,c147Load,c151Prefetch,c151InhouseOut,c154InhouseFor,c154AheadMerge,c149BuyerItemNames,c147Lib:{c147Diffs,c147Tomorrow,c147Html,c147Decorate,RATE,MIN_KG}});
})();
