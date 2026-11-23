/* ===== v1.199-c153・c154 出荷予定と確定のちがい（仕入れ担当者・営業担当者別） =====
   c154：仕入れ担当者・営業担当者（有効なアカウント）だけを出す。営業担当は「客先名に含まれる言葉 → 担当者」の決まり（SQL 064、
   初期値は07_営業仕入れ担当者カード 2026.5月版）で客先ごとに割り振り、管理者・青果社員が「営業担当の客先」の画面で変えられる。
   1人の文面＝仕入れ担当の品目（品目ごと・客先の内訳つき）＋営業担当の客先（客先ごと・ちがいのある品目）。
   仕入れと営業の両方を持つ人（斎藤 大明・坂本 美穂・吉田 智彦）は1つの文面にまとめる。
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
 if(inhouse)for(const [k] of INHOUSE){for(const [it,kg] of inhouse[k]||new Map())cell(it,k).actual+=kg;for(const [it,kg] of inhouse.ahead?.[k]||new Map())cell(it,k).ahead=(cell(it,k).ahead||0)+kg}
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
const pct=r=>r.rate===null?"予定なし":`${r.rate>0?"+":r.rate<0?"−":"±"}${Math.abs(Math.round(r.rate*100))}%`;
const sign=v=>`${v>0?"+":v<0?"−":"±"}${fmt(Math.abs(v))}kg`;
function partLine(r,max=4){
 const ps=r.parts.filter(p=>Math.abs(p.actual-p.plan)>=0.05).slice(0,max);
 if(!ps.length)return "";
 const more=r.parts.filter(p=>Math.abs(p.actual-p.plan)>=0.05).length-ps.length;
 return ps.map(p=>`${shortCust(p.customer)} ${fmt(p.plan)}→${fmt(p.actual)}${p.ahead>0.05?`（前の日に先送り ${fmt(p.ahead)}kg を含む）`:""}`).join("／")+(more>0?`／ほか${more}客先`:"");
}
/* ---------- 営業担当（c154） ---------- */
const nk=s=>String(s||"").normalize("NFKC").replace(/[\s　]/g,"");
/* 客先の営業担当：客先名に含まれる言葉のうち、いちばん長いもの（より細かい決まり）を使う */
function c154StaffOf(customer,rules){
 const c=nk(customer);let hit=null;
 for(const r of rules||[]){const k=nk(r.keyword);if(k&&c.includes(k)&&(!hit||k.length>nk(hit.keyword).length))hit=r}
 return hit;
}
/* 社外の客先ごとの予定と確定（品目つき）。rows＝c153Compare の結果 */
function c154Customers(rows){
 const by=new Map();
 for(const r of rows)for(const p of r.parts){if(inhouseOf(p.customer))continue;
  if(!by.has(p.customer))by.set(p.customer,{customer:p.customer,items:[]});
  const plan=p.plan,actual=p.actual,rate=plan>0?(actual-plan)/plan:null;
  by.get(p.customer).items.push({item:r.item,plan,actual,diff:actual-plan,rate,big:Math.abs(actual-plan)>=0.05&&(rate===null||Math.abs(rate)>=RATE-1e-9)})}
 const out=[...by.values()];
 for(const c of out){c.items.sort((a,b)=>(b.big-a.big)||Math.abs(b.diff)-Math.abs(a.diff));c.big=c.items.filter(i=>i.big).length;c.changed=c.items.filter(i=>Math.abs(i.diff)>=0.05).length}
 return out.sort((a,b)=>(b.big-a.big)||(b.changed-a.changed)||a.customer.localeCompare(b.customer,"ja"));
}
/* 人ごとに分ける。people＝[{id,name,items:Set,legacy}]。rules＝営業担当の決まり（staff_profile_id） */
function c154Group(rows,people,rules){
 const custs=c154Customers(rows),owned=new Set;for(const p of people)for(const n of p.items)owned.add(n);
 const custOf=c=>c154StaffOf(c.customer,rules)?.staff_profile_id||"";
 const groups=people.map(p=>({...p,rows:rows.filter(r=>p.items.has(r.item)),custs:custs.filter(c=>custOf(c)===p.id)}))
  .filter(g=>g.items.size||g.custs.length||(rules||[]).some(r=>r.staff_profile_id===g.id));
 const noneItems=rows.filter(r=>!owned.has(r.item)),noneCusts=custs.filter(c=>!custOf(c));
 if(noneItems.length)groups.push({id:"",name:"仕入れ担当なしの品目",items:new Set(noneItems.map(r=>r.item)),rows:noneItems,custs:[],none:"items"});
 if(noneCusts.length)groups.push({id:"",name:"営業担当なしの客先",items:new Set,rows:[],custs:noneCusts,none:"custs"});
 return groups;
}
const c153Group=(rows,buyers)=>c154Group(rows,buyers,[]);
const pctOf=(plan,actual)=>plan>0?`${actual>plan?"+":actual<plan?"−":"±"}${Math.abs(Math.round((actual-plan)/plan*100))}%`:"予定なし";

/* 送る文面（LINE向け） */
function c153Text(g,date){
 const who=g.none==="items"?"仕入れ担当なしの品目":g.none==="custs"?"営業担当なしの客先":`${g.name}さん`;
 const lines=[`【出荷予定と確定のちがい】${mdw(date)}納品`,who];
 const hasItems=g.items.size>0||g.none==="items",hasCusts=g.custs.length>0||g.none==="custs";
 if(!g.rows.length&&!g.custs.length){lines.push("","担当の出荷予定・確定はありませんでした（予定・確定とも10kg以下の品目は省いています）。");return lines.join("\n")}
 if(hasItems&&g.none!=="custs"){
  const big=g.rows.filter(r=>r.big),small=g.rows.filter(r=>!r.big);
  lines.push("",g.none?"＜品目ごと＞":"＜仕入れ担当の品目＞");
  if(!g.rows.length)lines.push("担当品目の出荷予定・確定はありませんでした。");
  else{
   if(big.length){lines.push(`■2割以上ちがう（${big.length}品目）`);for(const r of big){lines.push(`・${r.item}：予定 ${fmt(r.plan)}kg → 確定 ${fmt(r.actual)}kg（${sign(r.diff)}・${pct(r)}）`);const p=partLine(r);if(p)lines.push(`　${p}`)}}
   else lines.push("■2割以上ちがう品目はありませんでした");
   if(small.length){lines.push(`■2割未満（${small.length}品目）`);for(const r of small)lines.push(`・${r.item}：${fmt(r.plan)} → ${fmt(r.actual)}kg（${pct(r)}）`)}
  }
 }
 if(hasCusts&&g.none!=="items"){
  lines.push("",g.none?"＜客先ごと＞":"＜営業担当の客先＞");
  if(!g.custs.length)lines.push("担当客先の確定はありませんでした。");
  for(const c of g.custs){
   const ch=c.items.filter(i=>Math.abs(i.diff)>=0.05);
   if(!ch.length){lines.push(`・${shortCust(c.customer)}：予定どおり（${c.items.length}品目）`);continue}
   lines.push(`・${shortCust(c.customer)}：${ch.length}品目ちがう${c.big?`（2割以上 ${c.big}）`:""}`);
   const show=ch.slice(0,6);
   lines.push("　"+show.map(i=>`${i.item} ${fmt(i.plan)}→${fmt(i.actual)}（${pctOf(i.plan,i.actual)}）`).join("／")+(ch.length>show.length?`／ほか${ch.length-show.length}品目`:""));
  }
 }
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
 const [plan,actual,inhouse]=await Promise.all([lib.loadPlan(date),lib.loadActual(date),(window.c154InhouseFor?window.c154InhouseFor(date):window.c151InhouseOut?window.c151InhouseOut(ship):Promise.resolve(null)).catch(()=>null)]);
 return {date,ship,plan,actual,inhouse};
}
/* 営業担当の決まりと、仕入れ担当者・営業担当者の一覧（SQL 064）。まだなら null */
let staffCache=null,staffAt=0;
async function c154LoadStaff(force=false){
 if(!force&&staffCache&&Date.now()-staffAt<60000)return staffCache;
 try{const a=await callRpc("list_sales_customers_v1199c154",{});staffCache={rules:a?.rules||[],staff:a?.staff||[]};staffAt=Date.now();return staffCache}
 catch(e){if(L()?.sqlMissing?.(e)||/list_sales_customers_v1199c154|PGRST202|Could not find/i.test(String(e?.message||e)))return null;throw e}
}
/* c155：営業担当者のホームのカード用。自分の担当客先かどうかを返す関数。
   SQL 064 がまだ・読み込めない・自分の担当客先がない ときは null（全品目のまま） */
async function c155MyCustomerFilter(){
 if(db?.role!=="sales")return null;
 let st;try{st=await c154LoadStaff()}catch(_){return null}
 if(!st)return null;
 const me=(st.staff||[]).find(s=>canon(s.legacy_user_id)===canon(db.userId));
 if(!me||!(st.rules||[]).some(r=>r.staff_profile_id===me.id))return null;
 const memo=new Map;
 return c=>{const k=String(c||"");if(!memo.has(k))memo.set(k,c154StaffOf(k,st.rules)?.staff_profile_id===me.id);return memo.get(k)};
}
const canon=id=>typeof v1151CanonicalBuyerId==="function"?v1151CanonicalBuyerId(id):id;
function c154People(staff){
 return (staff||[]).map(s=>{const legacy=s.legacy_user_id||"";let name=s.display_name||legacy;try{name=buyerFullName(canon(legacy),name)||name}catch(_){}
  const items=new Set(s.role==="buyer"&&legacy&&typeof window.c149BuyerItemNames==="function"?window.c149BuyerItemNames(legacy):[]);
  return {id:s.id,name,role:s.role,legacy,items}});
}
/* SQL 064 がまだのとき：今までどおり仕入れ担当者だけ（c153） */
function buyersAll(){
 let list=[];try{list=v1144PurchaseStaffCandidates()||[]}catch(_){}
 const seen=new Set,out=[];
 for(const c of list){const id=canon(c.legacy_user_id);if(!id||seen.has(id))continue;seen.add(id);
  let name=c.display_name||id;try{name=buyerFullName(id,name)||name}catch(_){}
  const items=new Set(typeof window.c149BuyerItemNames==="function"?window.c149BuyerItemNames(c.legacy_user_id):[]);
  if(items.size)out.push({id,name,items,legacy:c.legacy_user_id})}
 return out;
}
const canCopy=()=>typeof canWorkerReport==="function"&&canWorkerReport();
const canSee=()=>db?.role==="buyer"||db?.role==="sales"||canCopy();
const canEditStaff=()=>db?.role==="admin"||db?.role==="worker";

/* ---------- 画面 ---------- */
function rowsHtml(rows){
 if(!rows.length)return '<div class="small">担当品目の出荷予定・確定はありませんでした。</div>';
 return `<table class="table c153Tbl"><tr><th>品目</th><th>予定→確定</th></tr>${rows.map(r=>`<tr class="${r.big?"c153Big":""}"><td><b>${esc(r.item)}</b></td><td>${fmt(r.plan)}kg → <b>${fmt(r.actual)}kg</b> <span class="c153R ${r.diff>0?"up":r.diff<0?"down":""}">${esc(pct(r))}</span>${partLine(r,6)?`<div class="small">${esc(partLine(r,6))}</div>`:""}</td></tr>`).join("")}</table>`;
}
function custsHtml(custs){
 if(!custs.length)return '<div class="small">担当客先の確定はありませんでした。</div>';
 return `<table class="table c153Tbl"><tr><th>客先</th><th>ちがう品目（予定→確定）</th></tr>${custs.map(c=>{const ch=c.items.filter(i=>Math.abs(i.diff)>=0.05);
  return `<tr class="${c.big?"c153Big":""}"><td><b>${esc(shortCust(c.customer))}</b><div class="small">${c.items.length}品目</div></td><td>${ch.length?ch.map(i=>`<div>${esc(i.item)} ${fmt(i.plan)}→<b>${fmt(i.actual)}</b>kg <span class="c153R ${i.diff>0?"up":"down"}">${esc(pctOf(i.plan,i.actual))}</span></div>`).join(""):'<span class="small">予定どおり</span>'}</td></tr>`}).join("")}</table>`;
}
function groupBody(g){
 const parts=[];
 if(g.items.size||g.none==="items")parts.push(`<div class="c154Sub">${g.none?"品目ごと":"仕入れ担当の品目"}</div>${rowsHtml(g.rows)}`);
 if(g.custs.length||g.none==="custs"||(!g.none&&g.role==="sales"))parts.push(`<div class="c154Sub">${g.none?"客先ごと":"営業担当の客先"}</div>${custsHtml(g.custs)}`);
 return parts.join("");
}
async function c153GapPage(date="",msg=""){
 if(!canSee()){alert("仕入れ担当者・営業担当者・管理者・青果社員が使えます");return home()}
 setScreen("c153GapPage",[date,msg]);
 pageShell("出荷予定と確定のちがい","読み込んでいます",'<div class="card"><div class="notice">読み込んでいます。</div></div>');
 let data,st;
 try{date=date||await findLatest();[data,st]=await Promise.all([c153Load(date),c154LoadStaff()])}
 catch(e){return pageShell("出荷予定と確定のちがい","",`<div class="err">${esc(L()?.sqlMissing?.(e)?"出荷予定の機能（SQL 061・062）がまだ実行されていません。":String(e?.message||e))}</div><button class="btn btn2" style="width:100%" ${seikaEventAttrs("click","home",[])}>ホームへ</button>`)}
 if(currentScreen!=="c153GapPage")return;
 const lib=L(),nav=`<div class="row" style="gap:8px;flex-wrap:wrap;align-items:center"><button class="btn btn2" ${seikaEventAttrs("click","c153GapPage",[lib.addDays(date,-1),""])}>前の日</button><input type="date" value="${esc(date)}" ${seikaEventAttrs("change","c153GapPage",[{__seikaValue:true},""])} style="font-size:18px;padding:6px"><button class="btn btn2" ${seikaEventAttrs("click","c153GapPage",[lib.addDays(date,1),""])}>次の日</button></div>
  <div class="small" style="margin-top:6px">納品日 <b>${mdw(date)}</b> ／ 出荷日 <b>${mdw(data.ship)}</b></div>`;
 const back=`<button class="btn btn2" style="width:100%;margin-top:8px" ${seikaEventAttrs("click","home",[])}>ホームへ</button>`;
 const sqlNote=st?"":'<div class="notice" style="margin-top:8px">営業担当の割り振り（SQL 064）がまだ実行されていないので、仕入れ担当者だけを出しています。</div>';
 const editBtn=st&&canEditStaff()?`<button class="btn btn2" style="width:100%;margin-top:8px" ${seikaEventAttrs("click","c154SalesCustomersPage",[date,""])}>営業担当の客先を変える</button>`:"";
 if(!data.actual?.active){
  return pageShell("出荷予定と確定のちがい",`${mdw(date)}納品`,`${msg?`<div class="ok">${esc(msg)}</div>`:""}<div class="card">${nav}<div class="notice" style="margin-top:10px">この日の確定（産地報告書）はまだ取り込まれていません。産地報告書は翌日の納品分が10時ごろに届きます。</div>${sqlNote}</div>${editBtn}${back}`);
 }
 const rows=c153Compare(data.plan?.lines,data.actual.lines,data.inhouse);
 const note=`<div class="small">社外は産地報告書の確定と、確定のある客先の予定で比べます。埼玉・深谷は積み込み表の予定と、出荷日のQRの出庫で比べます（翌日分を前の日に先送りした出庫も足します）。本社は積み込み表に入らないので比べません。予定・確定とも${MIN_KG}kg以下の品目は出しません。</div>${data.inhouse===null?'<div class="small">埼玉・深谷への出庫を読み込めなかったので、社外だけで比べています。</div>':""}${sqlNote}`;
 const people=st?c154People(st.staff):buyersAll(),rules=st?st.rules:[];
 if(!canCopy()){
  /* 仕入れ担当者・営業担当者：自分の分だけ */
  const me=people.find(p=>canon(p.legacy)===canon(db.userId))||{id:"",name:db.user||"",role:db.role,items:new Set(typeof window.c149BuyerItemNames==="function"?window.c149BuyerItemNames(db.userId):[])};
  let g=c154Group(rows,[me],rules).find(x=>!x.none)||{...me,rows:[],custs:[]};
  let label=[g.items.size?"担当品目":"",g.custs.length||rules.some(r=>r.staff_profile_id===me.id)?"担当客先":""].filter(Boolean).join("・");
  if(!label){g={...me,items:new Set(rows.map(r=>r.item)),rows,custs:[],none:"items"};label="担当が未設定のため全品目"}
  return pageShell("出荷予定と確定のちがい",`${mdw(date)}納品・${label}`,`${msg?`<div class="ok">${esc(msg)}</div>`:""}<div class="card">${nav}</div><div class="card"><b>${esc(g.name||me.name)}さん</b>${groupBody(g)}${note}</div>${back}`);
 }
 const groups=c154Group(rows,people,rules);
 const all=groups.filter(g=>g.rows.length||g.custs.length).map(g=>c153Text(g,date)).join("\n\n――――――――\n\n");
 const sec=groups.map((g,i)=>{const id=`c153Text${i}`,txt=c153Text(g,date),big=g.rows.filter(r=>r.big).length+g.custs.reduce((t,c)=>t+c.big,0);
  const title=g.none?g.name:`${g.name}さん`,tags=[g.items.size&&!g.none?`品目${g.rows.length}`:"",g.custs.length&&!g.none?`客先${g.custs.length}`:""].filter(Boolean).join("・");
  return `<div class="card c153Card"><div class="c153Head"><b>${esc(title)}</b><span class="small">${esc(tags)}${big?`・<span class="c153Warn">2割以上 ${big}</span>`:""}</span></div>
   <details${big?" open":""}><summary class="small" style="cursor:pointer">内容を見る</summary>${groupBody(g)}</details>
   <textarea id="${id}" class="textarea c153Ta" rows="6">${esc(txt)}</textarea>
   <div class="row" style="margin-top:8px;gap:6px;flex-wrap:wrap"><button class="btn blue" ${seikaEventAttrs("click","copyTextFrom",[id])}>コピー</button><button class="btn btn2" ${seikaEventAttrs("click","shareLineFrom",[id])}>LINEで共有</button><button class="btn btn2" ${seikaEventAttrs("click","shareLineWorksFrom",[id])}>LINE WORKSで共有</button></div></div>`}).join("");
 pageShell("出荷予定と確定のちがい（担当者別）",`${mdw(date)}納品・仕入れ担当者・営業担当者ごとに送れます`,`${msg?`<div class="ok">${esc(msg)}</div>`:""}<div class="card">${nav}${note}</div>${editBtn}${sec}
  <div class="card"><b>全員分をまとめて</b><textarea id="c153TextAll" class="textarea c153Ta" rows="6">${esc(all||"この日はちがいのある品目がありませんでした。")}</textarea><div class="row" style="margin-top:8px;gap:6px;flex-wrap:wrap"><button class="btn blue" ${seikaEventAttrs("click","copyTextFrom",["c153TextAll"])}>コピー</button><button class="btn btn2" ${seikaEventAttrs("click","shareLineFrom",["c153TextAll"])}>LINEで共有</button><button class="btn btn2" ${seikaEventAttrs("click","shareLineWorksFrom",["c153TextAll"])}>LINE WORKSで共有</button></div></div>${back}`);
}

/* ---------- 営業担当の客先を変える（管理者・青果社員） ---------- */
async function recentCustomers(date){
 const lib=L(),days=[];for(let i=-3;i<=7;i++)days.push(lib.addDays(date||todayKey(),i));
 const res=await Promise.all(days.flatMap(d=>[lib.loadPlan(d).catch(()=>null),lib.loadActual(d).catch(()=>null)]));
 const set=new Set;for(const r of res)for(const l of r?.lines||[]){const c=cust(l);if(c&&!inhouseOf(c))set.add(c)}
 return [...set].sort((a,b)=>a.localeCompare(b,"ja"));
}
function staffOptions(staff,sel){
 const groups=[["buyer","仕入れ担当者"],["sales","営業担当者"]];
 return `<option value="">（担当なし）</option>`+groups.map(([r,label])=>`<optgroup label="${label}">${staff.filter(s=>s.role===r).map(s=>`<option value="${esc(s.id)}"${s.id===sel?" selected":""}>${esc(s.display_name)}</option>`).join("")}</optgroup>`).join("");
}
async function c154SalesCustomersPage(date="",msg=""){
 if(!canEditStaff()){alert("営業担当の客先は、管理者・青果社員が変えられます");return c153GapPage(date)}
 setScreen("c154SalesCustomersPage",[date,msg]);
 pageShell("営業担当の客先","読み込んでいます",'<div class="card"><div class="notice">読み込んでいます。</div></div>');
 let st,custs;
 try{[st,custs]=await Promise.all([c154LoadStaff(true),recentCustomers(date)])}
 catch(e){return pageShell("営業担当の客先","",`<div class="err">${esc(String(e?.message||e))}</div>`)}
 if(currentScreen!=="c154SalesCustomersPage")return;
 if(!st)return pageShell("営業担当の客先","",`<div class="err">営業担当の割り振り（SQL 064）がまだ実行されていません。</div><button class="btn btn2" style="width:100%" ${seikaEventAttrs("click","c153GapPage",[date,""])}>戻る</button>`);
 const rows=st.rules.map(r=>{const hits=custs.filter(c=>c154StaffOf(c,st.rules)?.id===r.id);
  return `<tr><td><input id="c154Kw${r.id}" class="input" value="${esc(r.keyword)}"><div class="small">${hits.length?`当たる客先：${esc(hits.map(shortCust).join("、"))}`:"最近の客先には当たりません"}</div></td><td><select id="c154St${r.id}" class="input">${staffOptions(st.staff,r.staff_profile_id)}</select></td><td><button class="btn blue" ${seikaEventAttrs("click","c154SaveRule",[r.id,date])}>保存</button><button class="btn btn2" style="margin-top:4px" ${seikaEventAttrs("click","c154DeleteRule",[r.id,r.keyword,date])}>削除</button></td></tr>`}).join("");
 const free=custs.filter(c=>!c154StaffOf(c,st.rules));
 const freeHtml=free.length?`<table class="table c153Tbl"><tr><th>客先</th><th>営業担当</th><th></th></tr>${free.map((c,i)=>`<tr><td>${esc(c)}</td><td><select id="c154Free${i}" class="input">${staffOptions(st.staff,"")}</select></td><td><button class="btn blue" ${seikaEventAttrs("click","c154AddRule",[c,`c154Free${i}`,date])}>割り振る</button></td></tr>`).join("")}</table>`:'<div class="c147Ok">最近の客先は、すべて営業担当が決まっています。</div>';
 pageShell("営業担当の客先","客先名に含まれる言葉で、営業担当を決めます",`${msg?`<div class="ok">${esc(msg)}</div>`:""}
  <div class="card"><b>営業担当が決まっていない客先</b><div class="small">前後の積み込み表・産地報告書に出てくる客先のうち、どの決まりにも当たらないものです。担当者を選んで「割り振る」と、その客先名で決まりを作ります。</div>${freeHtml}</div>
  <div class="card"><b>決まりの一覧（${st.rules.length}件）</b><div class="small">客先名にこの言葉が含まれていれば、その担当者になります（空白は無視、いくつも当たるときは長い言葉が優先）。例：「虎昭」→ 虎昭産業 もおか工場・茨城工場・館林工場。</div>
   <table class="table c153Tbl"><tr><th>客先名に含まれる言葉</th><th>営業担当</th><th></th></tr>${rows}</table>
   <div class="row" style="gap:6px;flex-wrap:wrap;margin-top:8px"><input id="c154NewKw" class="input" placeholder="新しい言葉（例：ティキューシー）" style="flex:1;min-width:160px"><select id="c154NewSt" class="input" style="flex:1;min-width:140px">${staffOptions(st.staff,"")}</select><button class="btn blue" ${seikaEventAttrs("click","c154AddRule",["","",date])}>追加</button></div></div>
  <button class="btn btn2" style="width:100%" ${seikaEventAttrs("click","c153GapPage",[date,""])}>戻る</button>`);
}
async function saveRule(id,kw,staff,date,done){
 try{const a=await callRpc("save_sales_customer_v1199c154",{p_id:id||null,p_keyword:kw,p_staff:staff||null});if(!a?.ok)throw new Error(a?.message||"保存できませんでした");staffCache=null;return c154SalesCustomersPage(date,done)}
 catch(e){alert(`保存できませんでした。\n${e?.message||e}`)}
}
function c154SaveRule(id,date){const kw=document.getElementById(`c154Kw${id}`)?.value||"",st=document.getElementById(`c154St${id}`)?.value||"";return saveRule(id,kw,st,date,`「${kw.trim()}」を保存しました。`)}
function c154AddRule(customer,selId,date){
 date=String(date||"").trim();
 const kw=customer||document.getElementById("c154NewKw")?.value||"",st=document.getElementById(selId||"c154NewSt")?.value||"";
 if(!kw.trim())return alert("客先名に含まれる言葉を入れてください");
 if(!st&&!confirm("担当者が「担当なし」のままです。このまま追加しますか？"))return;
 return saveRule(null,kw,st,date,`「${kw.trim()}」を追加しました。`);
}
async function c154DeleteRule(id,kw,date){
 if(!confirm(`「${kw}」の決まりを削除しますか？\n当たっていた客先は「営業担当なし」になります。`))return;
 try{const a=await callRpc("delete_sales_customer_v1199c154",{p_id:id});if(!a?.ok)throw new Error("削除できませんでした");staffCache=null;return c154SalesCustomersPage(date,`「${kw}」を削除しました。`)}
 catch(e){alert(`削除できませんでした。\n${e?.message||e}`)}
}

/* ---------- 入口 ---------- */
/* ①出荷予定（積み込み表）の画面 ②在庫報告コピー（管理者・青果社員） ③ホームの「出荷予定と確定」カード（仕入れ担当者・営業担当者） */
const ENTRY_ID="c153Entry";
function entryHtml(){return `<div id="${ENTRY_ID}" class="card"><b>出荷予定と確定のちがい${canCopy()?"（担当者別・送る用）":"（自分の担当）"}</b><div class="small">${canCopy()?"仕入れ担当者・営業担当者ごとに、予定と確定のちがいを送る文面を作ります。":"担当品目・担当客先の予定と確定のちがいを見られます。"}</div><button class="btn c153Btn" style="width:100%;margin-top:8px" ${seikaEventAttrs("click","c153GapPage",["",""])}>ちがいを見る${canCopy()?"・送る":""}</button></div>`}
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
/* ホームのカード（c147）に、仕入れ担当者・営業担当者向けのボタンを足す */
const app=document.getElementById("app");
if(app)new MutationObserver(()=>{
 if(currentScreen!=="home"||!["buyer","sales"].includes(db?.role))return;
 const c=document.getElementById("c147Ship");if(!c||c.dataset.ready!=="1"||c.querySelector(".c153HomeBtn"))return;
 const row=c.querySelector(".row");if(!row)return;
 row.insertAdjacentHTML("beforeend",`<button type="button" class="btn btn2 c153HomeBtn" ${seikaEventAttrs("click","c153GapPage",["",""])}>${db.role==="sales"?"担当客先":"担当品目"}のちがいを詳しく</button>`);
}).observe(app,{childList:true,subtree:true});

/* 操作ガイド */
try{if(typeof V195_ROLE_GUIDES!=="undefined"){
 const send={title:"出荷予定と確定のちがいを担当者に送る",where:"ホーム →「出荷予定（積み込み表）」または「在庫報告コピー」→「ちがいを見る・送る」",
  steps:["いちばん新しい確定（産地報告書）の納品日が出ます。「前の日」「次の日」や日付で切り替えます。","仕入れ担当者・営業担当者ごとに、仕入れ担当の品目（客先ごとの内訳つき）と営業担当の客先（ちがいのある品目）が出ます。","送る文面の下の「コピー」「LINEで共有」「LINE WORKSで共有」で送ります。いちばん下に全員分をまとめた文面もあります。"],
  check:"社外は産地報告書、埼玉・深谷は出荷日のQRの出庫で比べます。",caution:"本社は積み込み表に入らないので比べません。担当のない品目・客先は「仕入れ担当なしの品目」「営業担当なしの客先」にまとまります。"};
 const edit={title:"営業担当の客先を変える",where:"「ちがいを見る・送る」→「営業担当の客先を変える」",
  steps:["上に、営業担当が決まっていない客先が出ます。担当者を選んで「割り振る」を押します。","下の一覧で、客先名に含まれる言葉と担当者を直して「保存」、要らない決まりは「削除」します。","「虎昭」のように短い言葉にすると、虎昭産業の工場がまとめて当たります。"],
  check:"初期値は「07_営業仕入れ担当者カード（2026.5月版）」の客先別営業担当です。",caution:"仕入れ担当の品目は、今までどおり品目設定と仕入れ担当者の一覧で決まります。"};
 const see={title:"担当の予定と確定のちがいを見る",where:"ホーム →「出荷予定と確定」→「担当品目（担当客先）のちがいを詳しく」",
  steps:["仕入れ担当の品目ごとに、予定と確定のkgとちがい（%）が、客先ごとの内訳つきで出ます。","営業担当の客先ごとに、予定と確定がちがう品目が出ます。"],
  check:"2割以上ちがうものが上に来ます。",caution:"予定・確定とも10kg以下の品目は出ません。"};
 const add=(r,s)=>{const g=V195_ROLE_GUIDES[r];if(g&&Array.isArray(g.sections)&&!g.sections.some(x=>x&&x.title===s.title))g.sections.push(s)};
 add("admin",send);add("worker",send);add("admin",edit);add("worker",edit);add("buyer",see);add("sales",see);
}}catch(_){}

{const st=document.createElement("style");st.textContent=`
.c153Btn{background:linear-gradient(90deg,#1e293b 0%,#1d4ed8 55%,#f59e0b 100%) !important;color:#fff !important;border-color:transparent !important}
.c153Head{display:flex;justify-content:space-between;align-items:baseline;gap:8px;font-size:17px}
.c153Warn{color:#b91c1c;font-weight:900}
.c153Tbl{font-size:14px;width:100%;margin-top:6px}
.c153Tbl td,.c153Tbl th{padding:4px 6px;vertical-align:top}
.c153Tbl td:first-child{min-width:4.5em;word-break:keep-all;overflow-wrap:anywhere}
.c153Big td{background:#fff7ed}
.c153R{display:inline-block;font-weight:900;font-size:12px;padding:1px 6px;border-radius:999px;background:#e5e7eb}
.c153R.up{background:#fee2e2;color:#b91c1c}.c153R.down{background:#dbeafe;color:#1d4ed8}
.c154Sub{font-weight:900;color:#1e3a8a;margin-top:10px}
.c153Ta{margin-top:8px;font-size:14px}`;document.head.appendChild(st)}

Object.assign(window,{c155MyCustomerFilter,c153GapPage,c154SalesCustomersPage,c154SaveRule,c154AddRule,c154DeleteRule,c153Lib:{c153Compare,c153Group,c154Group,c154Customers,c154StaffOf,c153Text,shortCust,RATE,MIN_KG}});
})();
