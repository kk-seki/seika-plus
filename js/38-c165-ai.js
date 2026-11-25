/* ===== v1.199-c165 AI（Claude）を使う =====
   呼び出しは Edge Function「seika-ai」（supabase/functions/seika-ai）。データは SQL 068 の ai_data_v1199c165（読むだけ）。
   ① 毎日のまとめ：管理者・青果社員・仕入れ担当・営業のホームに、その役割の「今日のまとめ」（3〜5行）。その日いちばん最初に開いた人のときに作り、1日1回保存する。
   ② AIに聞く：管理者・青果社員・仕入れ担当・営業。「先週のキャベツの廃棄は？」など。AIは読むだけで、在庫や伝票は変えない。
   ③ 写真で品質評価の候補：品質評価の画面（管理者・青果社員）。写真から 良好／要確認／不良 と状態の候補を入れる。写真は保存しない。最後は人が決める。
   ④ 帳票の読み取りの補助：積み込み表・産地報告書の取り込み（確認）で、読めなかった行の候補を出す（管理者）。「使う」を押したものだけ入る。登録は今まで通り管理者が押す。 */
(()=>{
const FN="seika-ai",ROLES=["admin","worker","buyer","sales"];
const ROLE_LABEL={admin:"管理者",worker:"青果社員",buyer:"仕入れ担当",sales:"営業"};
const canUse=()=>ROLES.includes(db?.role);
const msgOf=e=>String(e?.message||e||"AIを使えませんでした。");

async function c165Ai(action,payload={}){
 if(!await authEnsure())throw new Error("ログインし直してください。");
 let res;
 try{res=await fetch(`${SUPABASE_URL}/functions/v1/${FN}`,{method:"POST",headers:{apikey:SUPABASE_KEY,Authorization:"Bearer "+authToken(),"Content-Type":"application/json"},body:JSON.stringify({action,...payload})})}
 catch(_){throw new Error("通信できませんでした。電波のよいところでもう一度お試しください。")}
 const data=await res.json().catch(()=>({}));
 if(res.status===404)throw new Error("AIの準備（Edge Function seika-ai）がまだです。管理者に連絡してください。");
 if(!res.ok||data?.ok===false)throw new Error(data?.message||`AIを使えませんでした（${res.status}）`);
 return data;
}
const lines=t=>esc(String(t||"")).replace(/\n/g,"<br>");

/* ---------- ① 毎日のまとめ ---------- */
const sum={day:"",role:"",body:"",at:"",loading:false,error:""};
async function c165LoadSummary(force=false){
 if(!canUse())return;
 const today=todayKey(),role=db.role;
 if(!force&&sum.day===today&&sum.role===role&&(sum.body||sum.loading))return;
 Object.assign(sum,{day:today,role,loading:true,error:""});c165RenderSummary();
 try{
  let row=null;
  if(!force){try{row=(await qrSelect("ai_daily_summaries_v1199c165",`select=body,created_at&day=eq.${today}&role=eq.${role}&limit=1`))?.[0]||null}catch(_){}}
  if(!row){const a=await c165Ai("summary",{force});row={body:a.body,created_at:a.created_at||new Date().toISOString()}}
  Object.assign(sum,{body:row.body,at:row.created_at,loading:false});
 }catch(e){Object.assign(sum,{loading:false,error:msgOf(e),body:""})}
 c165RenderSummary();
}
function c165SummaryHtml(){
 const head=`<div class="c165Head"><b>AI 今日のまとめ</b><span class="small">（${esc(ROLE_LABEL[db?.role]||"")}向け）</span></div>`;
 const body=sum.loading?'<div class="small">AIがまとめています…</div>':sum.error?`<div class="small">${esc(sum.error)}</div>`:`<div class="c165Body">${lines(sum.body)}</div>`;
 const at=sum.at&&!sum.loading?`<div class="small" style="margin-top:4px">${esc(String(sum.at).slice(11,16)||"")}に作成・AIの文なので、大事な数字は画面で確かめてください</div>`:"";
 return `${head}${body}${at}<div class="row" style="gap:6px;margin-top:8px;flex-wrap:wrap"><button class="btn blue" style="flex:1" ${seikaEventAttrs("click","c165AskPage",[])}>AIに聞く</button>${db?.role==="admin"&&!sum.loading?`<button class="btn btn2" ${seikaEventAttrs("click","c165RefreshSummary",[])}>作り直す</button>`:""}</div>`;
}
function c165RenderSummary(){const c=document.getElementById("c165Sum");if(c)c.innerHTML=c165SummaryHtml()}
function c165RefreshSummary(){if(db?.role!=="admin")return;if(!confirm("今日のまとめをAIでもう一度作りますか？"))return;return c165LoadSummary(true)}
function c165InjectHome(){
 if(currentScreen!=="home"||!canUse()||document.getElementById("c165Sum"))return;
 const anchor=document.getElementById("c147Ship")||document.querySelector("#app .homeSummary")||document.querySelector("#app .homePrimary");if(!anchor)return;
 anchor.insertAdjacentHTML("beforebegin",`<div id="c165Sum" class="card c165">${c165SummaryHtml()}</div>`);
 c165LoadSummary();
}
const app=document.getElementById("app");
if(app)new MutationObserver(()=>{
 if(currentScreen==="home"&&canUse()&&!document.getElementById("c165Sum")&&document.querySelector("#app .homeSummary, #app .homePrimary"))c165InjectHome();
 if((currentScreen==="c140PreviewPage"||currentScreen==="c142PreviewPage")&&db?.role==="admin"&&!document.getElementById("c165Assist"))c165InjectAssist();
}).observe(app,{childList:true,subtree:true});

/* ---------- ② AIに聞く ---------- */
const ask={history:[],busy:false};
const EXAMPLES={
 admin:["先週のキャベツの廃棄は何kg？","昨日の予定と確定の差が大きい客先は？","今いちばん在庫が多い品目は？","今月の人参の歩留まりは？"],
 worker:["明日の出荷予定で多い品目は？","今の在庫で入荷日が古い品目は？","今週の下処理の歩留まりは？","最近の品質評価で不良だったものは？"],
 buyer:["明日から3日間の予定に対して在庫が足りなそうな品目は？","今週のキャベツの仕入れ価格は？","期限が近いGAP認証は？","今の在庫で入荷日が古い品目は？"],
 sales:["明日の客先ごとの予定は？","先週、予定より確定が減った客先は？","昨日の確定数量で多い品目は？","来週の予定でいちばん多い客先は？"]};
function c165AskPage(){
 if(!canUse()){alert("AIは管理者・青果社員・仕入れ担当・営業が使えます。");return home()}
 setScreen("c165AskPage",[]);
 const ex=(EXAMPLES[db.role]||[]).map(q=>`<button class="btn btn2 c165Ex" ${seikaEventAttrs("click","c165AskExample",[q])}>${esc(q)}</button>`).join("");
 const hist=ask.history.map(h=>`<div class="c165Q">${esc(h.q)}</div><div class="c165A">${lines(h.a)}${h.used?.length?`<div class="small" style="margin-top:4px">調べたデータ：${esc(h.used.map(u=>[KIND_LABEL[u.kind]||u.kind,u.from&&u.to?`${u.from}〜${u.to}`:"",u.item||"",u.customer||""].filter(Boolean).join(" ")).join("／"))}</div>`:""}</div>`).join("");
 pageShell("AIに聞く","SEIKA＋のデータを見て、AIが答えます（読むだけ。在庫や伝票は変わりません）",`
 <div class="card">${hist||'<div class="small">聞きたいことを書いて「聞く」を押してください。下の例を押すとそのまま聞けます。</div>'}
  <div id="c165AskBusy" class="small" style="display:${ask.busy?"block":"none"};margin-top:8px">AIが調べています…（10〜30秒ほど）</div></div>
 <div class="card"><textarea id="c165AskText" class="textarea" maxlength="500" placeholder="例：先週のキャベツの廃棄は何kg？"></textarea>
  <div class="row" style="gap:6px;margin-top:8px"><button id="c165AskBtn" class="btn green" style="flex:1" ${seikaEventAttrs("click","c165AskSend",[])}>聞く</button>${ask.history.length?`<button class="btn btn2" ${seikaEventAttrs("click","c165AskClear",[])}>はじめから</button>`:""}</div>
  <div class="small" style="margin-top:8px">AIの答えは間違えることがあります。大事な数字は、在庫・出荷予定などの画面で確かめてください。</div></div>
 <div class="card"><b>聞き方の例</b><div class="c165Exs">${ex}</div></div>
 ${db.role==="admin"?'<div class="card" id="c165Usage"><b>今月のAIの利用</b><div class="small">読み込んでいます…</div></div>':""}`);
 if(db.role==="admin")c165LoadUsage();
}
const KIND_LABEL={stock:"在庫",outbound:"出庫",waste:"廃棄",plan:"出荷予定",actual:"確定数量",plan_vs_actual:"予定と確定の差",trimming:"下処理",quality:"品質評価",gap:"GAP",prices:"仕入れ価格"};
function c165AskExample(q){const t=document.getElementById("c165AskText");if(t)t.value=q;return c165AskSend()}
function c165AskClear(){ask.history=[];return c165AskPage()}
async function c165AskSend(){
 if(ask.busy)return;
 const q=(document.getElementById("c165AskText")?.value||"").trim();if(!q)return alert("聞きたいことを入れてください。");
 ask.busy=true;const btn=document.getElementById("c165AskBtn"),busy=document.getElementById("c165AskBusy");if(btn)btn.disabled=true;if(busy)busy.style.display="block";
 try{const a=await c165Ai("ask",{question:q,history:ask.history.slice(-3).map(h=>({q:h.q,a:h.a}))});ask.history.push({q,a:a.answer,used:a.used||[]})}
 catch(e){ask.history.push({q,a:`（答えられませんでした）${msgOf(e)}`,used:[]})}
 finally{ask.busy=false}
 if(currentScreen==="c165AskPage"){c165AskPage();setTimeout(()=>{const b=document.getElementById("c165AskText");b?.scrollIntoView?.({block:"center"})},0)}
}
async function c165LoadUsage(){
 const box=document.getElementById("c165Usage");if(!box)return;
 try{const u=await callRpc("ai_usage_month_v1199c165",{});const yen=Math.round(Number(u.cost_usd||0)*150);
  box.innerHTML=`<b>今月のAIの利用</b><div class="small">${u.calls||0}回・約${Number(u.cost_usd||0).toFixed(2)}ドル（約${yen.toLocaleString()}円、1ドル150円で計算）。Maxプランの毎月のクレジット（100ドル）の中で使います。上限を超えると止まります。</div>
  <div class="small">${Object.entries(u.by_action||{}).map(([k,v])=>`${esc({summary:"まとめ",ask:"質問",photo:"写真",parse_assist:"帳票"}[k]||k)} ${v.calls}回`).join("・")}</div>`}
 catch(e){box.innerHTML=`<b>今月のAIの利用</b><div class="small">${esc(/ai_usage_month|PGRST202/.test(String(e?.message||e))?"AIの準備（SQL 068）がまだです。":"読み込めませんでした。")}</div>`}
}

/* ---------- ③ 写真で品質評価の候補 ---------- */
let photoItem="";
function c165InjectQuality(n=0){
 if(currentScreen!=="v1102QualityPage"||!["admin","worker"].includes(db?.role))return;
 const memo=document.getElementById("v1102QualityMemo");
 if(!memo){if(n<40)setTimeout(()=>c165InjectQuality(n+1),150);return}
 if(document.getElementById("c165Photo"))return;
 const card=memo.closest(".card")||memo.parentElement;
 card.insertAdjacentHTML("afterbegin",`<div id="c165Photo" class="c165Photo"><b>AIで写真から候補を出す</b><div class="small">写真を撮ると、AIが「総合判定」と「状態」の候補を入れます。写真は保存しません。最後は目で確かめて決めてください。</div>
  <input id="c165PhotoFile" type="file" accept="image/*" capture="environment" style="display:none" ${seikaEventAttrs("change","c165PhotoPicked",[{__seikaElement:true}])}>
  <button class="btn blue" type="button" style="width:100%;margin-top:6px" ${seikaEventAttrs("click","c165PhotoPick",[])}>写真を撮って候補を出す</button><div id="c165PhotoMsg" class="small" style="margin-top:6px"></div></div>`);
}
function c165PhotoPick(){const f=document.getElementById("c165PhotoFile");if(f){f.value="";f.click()}}
const toB64=blob=>new Promise((ok,ng)=>{const r=new FileReader();r.onload=()=>ok(String(r.result).split(",")[1]||"");r.onerror=()=>ng(new Error("写真を読めませんでした"));r.readAsDataURL(blob)});
async function c165PhotoPicked(input){
 const file=input?.files?.[0];if(!file)return;
 const msg=document.getElementById("c165PhotoMsg");if(msg)msg.textContent="AIが写真を見ています…（10秒ほど）";
 try{
  const blob=await v1102CompressPhoto(file),image=await toB64(blob);
  const a=await c165Ai("photo",{image,item_name:photoItem});
  const r=document.querySelector(`input[name="v1102Grade"][value="${a.grade}"]`);if(r){r.checked=true;try{v1102ToggleQualityFields()}catch(_){}}
  document.querySelectorAll('input[name="v1102Issue"]').forEach(x=>x.checked=(a.issues||[]).includes(x.value));
  const memo=document.getElementById("v1102QualityMemo");if(memo&&!memo.value.trim()&&a.memo)memo.value=`（AIの候補）${a.memo}`;
  const g={good:"良好",review:"要確認",bad:"不良"}[a.grade]||a.grade,c={high:"高い",medium:"ふつう",low:"低い"}[a.confidence]||"";
  if(msg)msg.innerHTML=`<b>AIの候補：${esc(g)}</b>${a.issues?.length?`（${esc(a.issues.join("・"))}）`:""}・自信：${esc(c)}<br>${esc(a.memo||"")}<br>上の判定と状態に入れました。目で確かめて、違うところは直してから登録してください。`;
 }catch(e){if(msg)msg.textContent=msgOf(e)}
}
try{
 const qBase=v1102QualityPage;
 v1102QualityPage=function(q,supersedesId=""){const r=qBase.apply(this,arguments);photoItem="";try{qrFindLot(q).then(l=>{photoItem=l?.item_name||""}).catch(()=>{})}catch(_){}setTimeout(()=>c165InjectQuality(),0);return r};
 window.v1102QualityPage=v1102QualityPage;
}catch(e){}

/* ---------- ④ 帳票の読み取りの補助 ---------- */
const assist={screen:"",res:null,busy:false,error:""};
function assistData(){return currentScreen==="c140PreviewPage"?window.c165PlanAssistData?.():currentScreen==="c142PreviewPage"?window.c165ActualAssistData?.():null}
function c165InjectAssist(){
 const d=assistData();if(!d)return;
 if(assist.screen!==currentScreen){assist.screen=currentScreen;assist.res=null;assist.error=""}
 const total=d.items.length+d.qty.length+d.customers.length;
 const warn=document.querySelector("#app .card.warn");
 if(!total&&!assist.res)return;
 const anchor=warn||document.querySelector("#app .card");if(!anchor)return;
 anchor.insertAdjacentHTML("beforebegin",`<div id="c165Assist" class="card c165">${c165AssistHtml(d)}</div>`);
}
function c165AssistHtml(d){
 const head=`<b>AIで読めなかった行の候補を出す</b><div class="small">今のルールで読めなかった行（品名${d.items.length}・数量${d.qty.length}・客先${d.customers.length}）について、AIが候補を出します。「使う」を押したものだけ入ります。登録は今まで通り下のボタンで行います。</div>`;
 if(assist.busy)return head+'<div class="small" style="margin-top:6px">AIが読んでいます…（20〜40秒ほど）</div>';
 const r=assist.res;
 const btn=`<button class="btn blue" style="width:100%;margin-top:8px" ${seikaEventAttrs("click","c165AssistRun",[])}>${r?"もう一度AIに候補を出してもらう":"AIに候補を出してもらう"}</button>`;
 if(!r)return head+(assist.error?`<div class="small" style="color:#b91c1c;margin-top:6px">${esc(assist.error)}</div>`:"")+((d.items.length+d.qty.length+d.customers.length)?btn:"");
 const left=(list,kind)=>list.filter(x=>kind==="item"?d.items.some(i=>i.key===x.key):kind==="kg"?d.qty.some(i=>i.key===x.key):d.customers.some(i=>i.key===x.key));
 const items=left(r.items,"item"),qty=left(r.qty,"kg"),cust=left(r.customers,"customer");
 const label=(list,k)=>list.find(x=>x.key===k);
 const row=(kind,x,text)=>`<div class="row" style="gap:6px;align-items:center;border-top:1px solid #e2e8f0;margin-top:6px;padding-top:6px"><div style="flex:1">${text}<div class="small">${esc(x.reason||"")}</div></div><button class="btn btn2" ${seikaEventAttrs("click","c165AssistUse",[kind,x.key])}>使う</button></div>`;
 const body=[
  ...items.map(x=>row("item",x,`品名「${esc(label(d.items,x.key)?.base||"")}」→ <b>${esc(x.item)}</b>`)),
  ...qty.map(x=>row("kg",x,`${esc(label(d.qty,x.key)?.label||"")} → <b>${esc(String(x.kg))}kg</b>`)),
  ...cust.map(x=>row("customer",x,`客先「${esc(label(d.customers,x.key)?.label||"")}」→ <b>${esc(x.customer)}</b>`))].join("");
 const none=d.items.length+d.qty.length+d.customers.length-(items.length+qty.length+cust.length);
 return head+(body?`${body}<button class="btn green" style="width:100%;margin-top:8px" ${seikaEventAttrs("click","c165AssistUseAll",[])}>候補を全部使う（${items.length+qty.length+cust.length}件）</button>`:'<div class="small" style="margin-top:6px">使える候補はありません。</div>')
  +(none>0?`<div class="small" style="margin-top:6px">AIが自信を持てなかった行（${none}件）は、下の欄で選んでください。</div>`:"")+((d.items.length+d.qty.length+d.customers.length)?btn:"");
}
function rerenderAssist(){const c=document.getElementById("c165Assist"),d=assistData();if(c&&d)c.innerHTML=c165AssistHtml(d)}
async function c165AssistRun(){
 const d=assistData();if(!d||assist.busy||db?.role!=="admin")return;
 assist.busy=true;assist.error="";rerenderAssist();
 try{const a=await c165Ai("parse_assist",{kind:d.kind,items:d.items,qty:d.qty,customers:d.customers,known_customers:d.known_customers,master_items:typeof seikaItems==="function"?seikaItems():[]});assist.res={items:a.items||[],qty:a.qty||[],customers:a.customers||[]}}
 catch(e){assist.error=msgOf(e)}
 finally{assist.busy=false}
 rerenderAssist();
}
function useOne(kind,k){
 const d=assistData(),r=assist.res;if(!d||!r)return;
 const fn=window[d.apply[kind]];if(typeof fn!=="function")return;
 if(kind==="item"){const x=r.items.find(i=>i.key===k);if(x)fn(k,x.item)}
 else if(kind==="kg"){const x=r.qty.find(i=>i.key===k);if(x)fn(k,String(x.kg))}
 else{const x=r.customers.find(i=>i.key===k);if(x)fn(k,x.customer)}
}
function c165AssistUse(kind,k){useOne(kind,k)}
function c165AssistUseAll(){
 const d=assistData(),r=assist.res;if(!d||!r)return;
 for(const x of r.items)if(d.items.some(i=>i.key===x.key))useOne("item",x.key);
 for(const x of r.qty)if(d.qty.some(i=>i.key===x.key))useOne("kg",x.key);
 for(const x of r.customers)if(d.customers.some(i=>i.key===x.key))useOne("customer",x.key);
}

/* ---------- メニュー・操作ガイド・見た目 ---------- */
try{
 const menuBase=accountMenu;
 accountMenu=function(...a){const r=menuBase.apply(this,a);setTimeout(()=>{const m=document.querySelector(".menu");if(!m||!canUse()||document.getElementById("c165MenuAsk"))return;
  m.insertAdjacentHTML("afterbegin",`<button id="c165MenuAsk" class="btn btn2" ${seikaEventAttrs("click","c165AskPage",[])}>AIに聞く</button>`)},0);return r};
 window.accountMenu=accountMenu;
}catch(e){}
Object.assign(window,{c165Ai,c165LoadSummary,c165RefreshSummary,c165InjectHome,c165AskPage,c165AskExample,c165AskClear,c165AskSend,c165LoadUsage,
 c165InjectQuality,c165PhotoPick,c165PhotoPicked,c165InjectAssist,c165AssistRun,c165AssistUse,c165AssistUseAll,c165State:{sum,ask,assist}});
{const st=document.createElement("style");st.textContent=`.c165{border:2px solid #7c3aed;background:linear-gradient(180deg,#faf5ff 0%,#fff 60%)}
.c165Head{display:flex;align-items:baseline;gap:6px;font-size:18px;color:#5b21b6}.c165Body{margin-top:6px;line-height:1.7;font-size:16px}
.c165Q{margin-top:10px;margin-left:15%;background:#ede9fe;border-radius:12px;padding:8px 10px;font-weight:700}
.c165A{margin-top:6px;margin-right:8%;background:#f8fafc;border:1px solid #e2e8f0;border-radius:12px;padding:8px 10px;line-height:1.7}
.c165Exs{display:flex;flex-wrap:wrap;gap:6px;margin-top:6px}.c165Ex{font-size:14px;padding:6px 10px}
.c165Photo{border:1px dashed #7c3aed;border-radius:10px;padding:8px;margin-bottom:10px;background:#faf5ff}`;document.head.appendChild(st)}

try{
 const common={where:"ホームの「AI 今日のまとめ」・メニューの「AIに聞く」",
  check:"AIは読むだけです。在庫・伝票・設定は変わりません。",caution:"AIの答えは間違えることがあります。大事な数字は、在庫・出荷予定などの画面で確かめてください。"};
 const sumSec={title:"AI 今日のまとめを見る",...common,steps:["ホームのいちばん上に、その役割向けの「今日のまとめ」（3〜5行）が出ます。その日いちばん最初に開いた人のときに作り、1日1回だけ作ります。","「AIに聞く」を押すと、くわしく聞けます。"]};
 const askSec={title:"AIに聞く",...common,steps:["メニューかホームの「AIに聞く」を開き、聞きたいことを書いて「聞く」を押します（例：先週のキャベツの廃棄は何kg？）。","AIが在庫・出庫・廃棄・出荷予定・確定・下処理・品質評価・GAPを調べて答えます。答えの下に、調べたデータが出ます。","続けて聞くと、前の話を覚えたまま答えます。「はじめから」で話を消します。"]};
 const photoSec={title:"AIで写真から品質評価の候補を出す",where:"QR品質評価の画面",steps:["「写真を撮って候補を出す」を押して、野菜の写真を撮ります。","AIが「総合判定」と「状態」に候補を入れます（メモが空なら、AIの見立ても入ります）。","目で確かめて、違うところは直してから「品質評価を登録」を押します。"],check:"写真はAIに見せるだけで、保存しません（登録用の写真は今まで通り「写真ライブラリから選択」で付けます）。",caution:"におい・温度など、写真で分からないことは判断しません。"};
 const assistSec={title:"AIで帳票の読めなかった行の候補を出す",where:"積み込み表・産地報告書の取り込み（確認）",steps:["要確認の行があるとき、「AIに候補を出してもらう」を押します。","品名・数量（kg）・客先の候補が出ます。「使う」か「候補を全部使う」を押すと、下の欄に入ります。","確かめてから、今まで通り「登録する」を押します。"],check:"AIが自信を持てない行は候補を出しません。下の欄で選んでください。",caution:"「大根」など取り違えやすい品名は、特によく確かめてください。"};
 if(typeof V195_ROLE_GUIDES!=="undefined")for(const [r,list] of [["admin",[sumSec,askSec,photoSec,assistSec]],["worker",[sumSec,askSec,photoSec]],["buyer",[sumSec,askSec]],["sales",[sumSec,askSec]]]){
  const g=V195_ROLE_GUIDES[r];if(!g||!Array.isArray(g.sections))continue;for(const s of list)if(!g.sections.some(x=>x&&x.title===s.title))g.sections.push(s)}
}catch(e){}
})();
