/* ===== v1.199-c134 納品先・仕入先・単協マスタの入口を1つに／仕入れ担当者のホームに担当品目の日量 =====
   ・QR在庫管理ホームとメニューの入口を「納品先・仕入先・単協マスタ」1つにまとめ、画面の上のタブで切り替える。
     納品先マスタは管理者だけなので、青果社員は今までどおり「仕入先・単協マスタ」。
   ・仕入れ担当者のホームに、担当品目ごとの日量（昨日までの7日間の出庫 ÷ 出庫した日数）のボタンを並べる。
     押すと、その品目を選んだ状態で「在庫・出庫の分析」が開く。日量はQR品目の出庫から計算する（取消・廃棄は除く）。 */
(()=>{
const LABEL="納品先・仕入先・単協マスタ";

/* ---------- 入口 ---------- */
function c134FixHome(tries=0){
 if(currentScreen!=="qrHome")return;
 const box=document.querySelector(".homePrimary");
 const dest=box&&box.querySelector('[data-seika-click-action="v194DestinationsPage"]'),party=document.getElementById("v1280PartyBtn");
 if(dest&&!dest.dataset.c134){dest.dataset.c134="1";dest.innerHTML=`${LABEL}<br><span style="font-size:15px;font-weight:800">出庫先・客先と、仕入先・単協名の正式名</span>`}
 if(dest&&party)party.style.display="none";
 if(!party&&tries<30)setTimeout(()=>c134FixHome(tries+1),100);
}
const homeBase=qrHome;
qrHome=async function(...a){const r=await homeBase.apply(this,a);setTimeout(()=>c134FixHome(),0);return r};window.qrHome=qrHome;
const menuBase=accountMenu;
accountMenu=function(...a){const r=menuBase.apply(this,a);
 const fix=()=>{const b=document.getElementById("v1280MenuParty");if(!b||b.dataset.c134)return;b.dataset.c134="1";
  if(canAdmin()){b.textContent=LABEL;b.setAttribute("data-seika-click-action","v194DestinationsPage");b.setAttribute("data-seika-click-args",encodeURIComponent(JSON.stringify([""])))}
  else b.textContent="仕入先・単協マスタ"};
 fix();setTimeout(fix,350);return r};window.accountMenu=accountMenu;

/* 納品先マスタの画面の上にタブ */
if(typeof v194DestinationsPage==="function"){
 const destBase=v194DestinationsPage;
 const page=function(...a){const r=destBase.apply(this,a);
  if(currentScreen==="v194DestinationsPage"&&canAdmin()&&typeof c130MasterTabs==="function"){const main=document.querySelector("#app main.wrap");if(main&&!document.getElementById("c134DestTabs"))main.insertAdjacentHTML("afterbegin",`<div id="c134DestTabs" class="card">${c130MasterTabs("dest")}</div>`)}
  return r};
 window.v194DestinationsPage=page;try{v194DestinationsPage=page}catch(_){}
}

/* ---------- 担当品目の日量（仕入れ担当者） ---------- */
const DAYS=7;
let cache=null,cacheAt=0,loading=null;
const ymd=d=>ymdKey(d);
function c134Range(){const t=new Date();t.setHours(0,0,0,0);const to=new Date(t),from=new Date(t);from.setDate(from.getDate()-DAYS);return{from,to,fromKey:ymd(from),toKey:ymd(new Date(to.getTime()-864e5))}}
async function c134Load(){
 if(cache&&Date.now()-cacheAt<10*60000)return cache;
 if(loading)return loading;
 loading=(async()=>{
  const {from,to,fromKey,toKey}=c134Range();
  const q=`select=*&movement_type=eq.${encodeURIComponent("出庫")}&occurred_at=gte.${encodeURIComponent(from.toISOString())}&occurred_at=lt.${encodeURIComponent(to.toISOString())}&limit=5000`;
  const moves=(await qrSelect("qr_lot_movements",q)||[]).filter(m=>!m.cancelled_at&&String(m.destination||"").trim()!=="廃棄");
  const ids=[...new Set(moves.map(m=>m.lot_id).filter(Boolean))],lots=new Map;
  for(let i=0;i<ids.length;i+=80){const part=ids.slice(i,i+80);for(const l of (await qrSelect("qr_lots",`select=*&id=in.(${part.join(",")})`)||[]))lots.set(l.id,l)}
  const by={};
  for(const m of moves){const l=lots.get(m.lot_id);let name="";try{name=qrResolveInventoryItem(l)?.item?.name||""}catch(_){}name=name||String(l?.item_name||m.item_name||"").trim();if(!name)continue;
   const d=ymd(new Date(m.occurred_at||m.created_at)),o=by[name]=by[name]||{days:new Set,kg:0,unk:0,hqKg:0};o.days.add(d);const toHq=String(m.destination||"").trim()==="本社";
   let kg=null;if(m.weight!==null&&m.weight!==undefined&&m.weight!==""&&Number.isFinite(Number(m.weight)))kg=Number(m.weight);else{try{const k=l?v163LotKgAtQuantity(l,Number(m.qty||0)):0;kg=k>0?k:null}catch(_){}}
   if(kg==null)o.unk++;else{o.kg+=kg;if(toHq)o.hqKg+=kg}}  // c151：本社への出庫は分けても数える（本社は積み込み表に入らないため）
  cache={by,fromKey,toKey};cacheAt=Date.now();return cache})();
 try{return await loading}finally{loading=null}
}
function c134Fmt(v){return(Math.round(v*10)/10).toLocaleString("ja-JP")}
async function c134InjectBuyer(){
 if(currentScreen!=="home"||db?.role!=="buyer"||document.getElementById("c134Daily"))return;
 const anchor=document.querySelector("#app .homeSummary");if(!anchor)return;
 /* c149：QRで管理する品目のうち、仕入れ担当者の一覧でこの人の品目になっているもの（例：人参→荒木さん）も入れる */
 let items=[];try{items=typeof window.c149BuyerItemNames==="function"?window.c149BuyerItemNames().map(name=>({name})):(v1153BuyerOptimalItems()||[])}catch(_){}
 if(!items.length)return;
 anchor.insertAdjacentHTML("afterend",`<div id="c134Daily" class="card"><b>担当品目の日量</b><div class="small" id="c134DailySub">読み込んでいます…</div><div id="c134DailyBtns" class="c134Grid"></div></div>`);
 let data;try{data=await c134Load()}catch(e){const s=document.getElementById("c134DailySub");if(s)s.textContent="日量を読み込めませんでした。";return}
 const sub=document.getElementById("c134DailySub"),box=document.getElementById("c134DailyBtns");if(!sub||!box)return;
 sub.textContent=`${data.fromKey.slice(5).replace("-","/")}〜${data.toKey.slice(5).replace("-","/")}（昨日までの${DAYS}日間）の出庫 ÷ 出庫した日数。QR品目だけです。押すと在庫・出庫の分析が開きます。`;
 const names=[...new Set(items.map(i=>i.name).filter(Boolean))].sort((a,b)=>a.localeCompare(b,"ja"));
 box.innerHTML=names.map(nm=>{const o=data.by[nm];let main,cls="";
  if(!o){main="出庫なし";cls=" none"}
  else{const d=o.days.size,avg=d?o.kg/d:0;main=o.kg>0?`日量 ${c134Fmt(avg)}kg`:"日量 －";main+=`<span>出庫${d}日${o.unk?`・重さ不明${o.unk}件`:""}</span>`}
  return `<button type="button" class="c134Btn${cls}" ${seikaEventAttrs("click","c81OpenItem",[nm])}><b>${esc(nm)}</b><em>${main}</em></button>`}).join("");
}
const app=document.getElementById("app");
if(app)new MutationObserver(()=>{if(currentScreen==="home"&&db?.role==="buyer"&&!document.getElementById("c134Daily")&&document.querySelector("#app .homeSummary"))c134InjectBuyer()}).observe(app,{childList:true,subtree:true});
{const st=document.createElement("style");st.textContent=".c134Grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:8px;margin-top:8px}.c134Btn{display:flex;flex-direction:column;align-items:flex-start;gap:2px;padding:10px 12px;border-radius:14px;border:2px solid #0f766e;background:#f0fdfa;color:#134e4a;text-align:left;cursor:pointer}.c134Btn b{font-size:17px}.c134Btn em{font-style:normal;font-size:16px;font-weight:900}.c134Btn em span{display:block;font-size:12px;font-weight:700;color:#475569}.c134Btn.none{border-color:#cbd5e1;background:#f8fafc;color:#64748b}";document.head.appendChild(st)}

Object.assign(window,{c134FixHome,c134Load,c134InjectBuyer});

/* ---------- 操作ガイド ---------- */
try{
 if(typeof V195_ROLE_GUIDES!=="undefined"){
  const daily={title:"担当品目の日量を見る",where:"ホーム（仕入れ担当者）→「担当品目の日量」",
   steps:["ホームの「担当品目の日量」に、担当品目ごとのボタンが並びます。","日量は、昨日までの7日間の出庫の合計kgを、出庫した日数で割った数です（休みの日で薄まりません）。QR品目の出庫から計算し、取り消した出庫と廃棄は入りません。","ボタンを押すと、その品目を選んだ状態で「在庫・出庫の分析」が開き、在庫の推移や出庫先別の出庫を見られます。"],
   check:"「出庫なし」は、7日間にQR出庫がなかった品目です。通常在庫の品目は出庫の記録がないので出ません。",
   caution:"重さが分からないロット（量目が未入力など）はkgに入らず、「重さ不明○件」と出ます。"};
  const g=V195_ROLE_GUIDES.buyer;if(g&&Array.isArray(g.sections)&&!g.sections.some(x=>x&&x.title===daily.title))g.sections.unshift(daily);
  for(const r of ["admin","worker"]){const gg=V195_ROLE_GUIDES[r];const sec=gg?.sections?.find(x=>x&&x.title==="仕入先・単協マスタ（正式名）を整える");if(!sec)continue;
   sec.where=r==="admin"?"QR在庫管理 →「納品先・仕入先・単協マスタ」（上のタブで納品先・仕入先・単協名を切り替え。メニューからも開けます）":"QR在庫管理 →「仕入先・単協マスタ」（メニューからも開けます）";
   if(!sec.steps.some(s=>s.includes("候補から外す")))sec.steps.splice(4,0,"いらない名前（間違えて入れた名前など）は「候補から外す」で一覧から消せます。登録済みのロットの表記はそのままです。あとで「非表示にした○○」から戻せます。")}
 }
}catch(e){}
})();
