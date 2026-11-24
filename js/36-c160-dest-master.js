/* ===== v1.199-c160 納品先マスタをクラウドに =====
   これまで納品先マスタ（出庫先の選択肢・社外の客先）は各端末の中だけに保存され、クラウドに送られていなかった。
   追加した出庫先が再読込で消え、端末ごとに中身が違っていたため、クラウドの表（db/066：dest_master_v1199c160）に移す。
   区分は3つ：社内（内）／社外の客先（外：産地報告に入る。グループ＝産地報告のシート）／外販先（販：産地報告に入らない社外）。
   外販先への出庫は、出庫先の名前のまま記録・集計する（日量・分析・送った荷物の明細Excel）。出荷予定と確定の比較・伝票には入れない。
   SQL 066 がまだのとき（表がない）は、今までどおり端末の中の内容で動き、画面にその旨を出す。 */
(()=>{
const KINDS=[["内","社内"],["外","社外の客先（産地報告に入る）"],["販","外販先（産地報告に入らない）"]];
const kindLabel=k=>k==="外"?"社外の客先":k==="販"?"外販先":"社内";
const st={loaded:false,missing:false,loading:null,error:"",rows:[]};
const toRow=r=>({name:String(r.name||""),formal:String(r.formal||""),kind:["内","外","販"].includes(r.kind)?r.kind:"内",
 group:String(r.group||r.group_name||""),outbound:r.outbound!==false,weight:!!r.weight,active:r.active!==false,sort:Number(r.sort)||0});

async function c160LoadDests(force){
 if(st.loading&&!force)return st.loading;
 st.loading=(async()=>{
  try{
   const ans=await callRpc("list_dest_master_v1199c160",{});
   const rows=(Array.isArray(ans)?ans:[]).map(toRow).filter(r=>r.name);
   if(!rows.length)throw new Error("empty");
   st.rows=rows;db.v194Destinations=rows;st.loaded=true;st.missing=false;st.error="";
   try{v194SyncOutDestinations()}catch(_){}
  }catch(e){
   const m=String(e?.message||e);
   st.missing=/list_dest_master_v1199c160|does not exist|PGRST202|404|empty/.test(m);st.error=m;
  }
  return st.loaded;
 })();
 return st.loading;
}

/* データ：クラウドから読めたらその内容。読めないときは今までの端末の中の内容 */
const baseEnsure=v194EnsureDestinations;
const ensure=function(){
 /* c161：クラウドから読んだ内容は st.rows に持つ。再読込などで db が入れ替わって端末の古い内容に戻っても、こちらを使う */
 if(st.loaded){if(db&&db.v194Destinations!==st.rows)db.v194Destinations=st.rows;return st.rows}
 return baseEnsure();
};
window.v194EnsureDestinations=ensure;try{v194EnsureDestinations=ensure}catch(_){}

/* 画面 */
function c160Page(msg=""){
 setScreen("v194DestinationsPage",[msg]);
 if(!canAdmin()){alert("納品先マスタは管理者のみです");return qrHome()}
 const rows=ensure();
 const order=r=>r.kind==="内"?0:r.kind==="販"?1:2;
 const groups=[];
 for(const r of [...rows].sort((a,b)=>order(a)-order(b)||(a.sort-b.sort))){
  const g=r.kind==="内"?"社内":r.kind==="販"?"外販先（産地報告に入らない）":(r.group||"未分類");
  if(!groups.includes(g))groups.push(g);
 }
 const sheetGroups=[...new Set(rows.filter(r=>r.kind==="外").map(r=>r.group).filter(Boolean))];
 const note=st.loaded?"":st.missing
  ?`<div class="notice">納品先マスタがまだクラウドにありません（SQL 066 が未実行）。今は、この端末の中の内容です。追加・変更は再読込で消えることがあります。</div>`
  :`<div class="notice">納品先マスタをクラウドから読み込めませんでした。通信を確かめて「再読込」を押してください。</div>`;
 const form=`<div class="card"><b>納品先を追加</b>
<label class="label">納品先名</label><input id="v194DestName" class="input" placeholder="例：旭物産">
<label class="label">区分</label><select id="v194DestKind" class="input">${KINDS.map(([v,l])=>`<option value="${v}">${esc(l)}</option>`).join("")}</select>
<label class="label">グループ（産地報告のシート。社外の客先のときだけ）</label><input id="v194DestGroup" class="input" list="v194DestGroupList" placeholder="例：プライム"><datalist id="v194DestGroupList">${sheetGroups.map(g=>`<option value="${esc(g)}">`).join("")}</datalist>
<label class="label">正式名称（任意）</label><input id="v194DestFormal" class="input" placeholder="例：株式会社日本デリカサービス 八千代工場">
<label class="label"><input type="checkbox" id="v194DestOutbound" checked> 出庫先の選択肢に表示する</label>
<label class="label"><input type="checkbox" id="v194DestWeight"> レタス類を実重量(kg)で納品する</label>
<div class="small">外販先は、出庫先の名前のまま出庫の記録・日量・分析に入ります。出荷予定と確定の比較と伝票には入りません。</div>
<button class="btn" style="width:100%;margin-top:12px" ${seikaEventAttrs('click','c160AddDest',[])}>納品先を追加</button></div>`;
 const body=groups.map(g=>{
  const items=rows.map((r,i)=>[r,i]).filter(([r])=>(r.kind==="内"?"社内":r.kind==="販"?"外販先（産地報告に入らない）":(r.group||"未分類"))===g);
  return `<div class="card"><b>${esc(g)}</b>${items.map(([r,i])=>`<div class="itemHead" style="margin-top:8px"><div><b>${esc(r.name)}</b><div class="small">${r.formal?esc(r.formal)+"<br>":""}${kindLabel(r.kind)} ／ 出庫先に表示：${r.outbound?"する":"しない"}${r.weight?" ／ <b>レタス類は実重量(kg)で納品</b>":""}</div>
<select id="c160Kind_${i}" class="input" style="margin-top:6px" ${seikaEventAttrs('change','c160SetKind',[r.name,i])}>${KINDS.map(([v,l])=>`<option value="${v}" ${v===r.kind?"selected":""}>${esc(l)}</option>`).join("")}</select></div>
<div class="row" style="gap:6px"><button class="btn btn2" ${seikaEventAttrs('click','c160ToggleOutbound',[r.name])}>${r.outbound?"表示をやめる":"出庫先に出す"}</button><button class="btn red" ${seikaEventAttrs('click','c160RemoveDest',[r.name])}>削除</button></div></div>`).join("")}</div>`;
 }).join("");
 pageShell("納品先マスタ","社内の納品先・社外の客先・外販先を登録します。出庫先の選択肢に出すかどうかは1件ずつ切り替えられます。",`${okHtml(msg)}${note}${form}${body}`);
 if(typeof c130MasterTabs==="function"){const main=document.querySelector("#app main.wrap");if(main&&!document.getElementById("c134DestTabs"))main.insertAdjacentHTML("afterbegin",`<div id="c134DestTabs" class="card">${c130MasterTabs("dest")}</div>`)}
}
async function c160OpenPage(msg=""){
 await c160LoadDests(true);  /* c161：開くたびにクラウドの最新を読む */
 c160Page(msg);
}

/* 保存：クラウドがあればクラウドへ。なければ今までどおり端末の中へ */
async function persist(oldName,row,okMsg){
 if(!st.loaded){
  const rows=baseEnsure();
  if(oldName){const r=rows.find(x=>x.name===oldName);if(r)Object.assign(r,row)}else rows.push(row);
  try{save()}catch(_){}try{v194SyncOutDestinations()}catch(_){}
  return c160Page(okMsg);
 }
 try{await callRpc("save_dest_master_v1199c160",{p_old_name:oldName||null,p_row:row})}
 catch(e){alert("保存できませんでした。\n"+String(e?.message||e).replace(/^.*?"message":"([^"]+)".*$/,"$1"));return c160Page()}
 await c160LoadDests(true);
 c160Page(okMsg);
}
function c160AddDest(){
 if(!canAdmin())return alert("納品先マスタは管理者のみです");
 const name=(document.getElementById("v194DestName")?.value||"").trim().replace(/\s+/g," ");
 if(!name)return alert("納品先名を入力してください");
 const kind=document.getElementById("v194DestKind")?.value||"内";
 {const dup=ensure().find(r=>r.name===name);if(dup)return alert(`「${name}」はすでに「${kindLabel(dup.kind)}」に入っています。区分や表示は、その行で変えてください。`)}
 const g=(document.getElementById("v194DestGroup")?.value||"").trim();
 const row={name,formal:(document.getElementById("v194DestFormal")?.value||"").trim(),kind,
  group:kind==="外"?(g||"未分類"):kind==="販"?"外販先":"社内",
  outbound:!!document.getElementById("v194DestOutbound")?.checked,weight:!!document.getElementById("v194DestWeight")?.checked,active:true};
 return persist(null,row,"納品先を追加しました");
}
function c160ToggleOutbound(name){
 if(!canAdmin())return alert("納品先マスタは管理者のみです");
 const r=ensure().find(x=>x.name===name);if(!r)return c160Page("対象が見つかりません");
 return persist(name,{...r,outbound:!r.outbound},`${name} を出庫先に${r.outbound?"表示しないように":"表示するように"}しました`);
}
function c160SetKind(name,i){
 if(!canAdmin())return alert("納品先マスタは管理者のみです");
 const r=ensure().find(x=>x.name===name);if(!r)return c160Page("対象が見つかりません");
 const kind=document.getElementById(`c160Kind_${i}`)?.value||r.kind;if(kind===r.kind)return;
 let group=r.group;
 if(kind==="外"){group=(prompt("産地報告のシート（グループ）を入れてください",r.kind==="外"?r.group:"")||"").trim()||"未分類"}
 else group=kind==="販"?"外販先":"社内";
 return persist(name,{...r,kind,group},`${name} を「${kindLabel(kind)}」にしました`);
}
async function c160RemoveDest(name){
 if(!canAdmin())return alert("納品先マスタは管理者のみです");
 if(!confirm(`${name} を削除しますか？\n過去の出庫の記録は残ります。`))return;
 if(!st.loaded){const rows=baseEnsure(),i=rows.findIndex(x=>x.name===name);if(i>=0)rows.splice(i,1);try{save()}catch(_){}try{v194SyncOutDestinations()}catch(_){}return c160Page("削除しました")}
 try{await callRpc("delete_dest_master_v1199c160",{p_name:name})}catch(e){alert("削除できませんでした。\n"+String(e?.message||e));return c160Page()}
 await c160LoadDests(true);c160Page("削除しました");
}

window.v194DestinationsPage=c160OpenPage;try{v194DestinationsPage=c160OpenPage}catch(_){}
Object.assign(window,{c160LoadDests,c160AddDest,c160ToggleOutbound,c160SetKind,c160RemoveDest,c160Page,c160State:st});

try{
 const sec={title:'納品先マスタ（社内・社外の客先・外販先）',where:'QR在庫管理 →「納品先・仕入先・単協マスタ」→ 納品先',
  steps:['納品先名と区分を入れて「納品先を追加」を押します。区分は「社内」「社外の客先（産地報告に入る）」「外販先（産地報告に入らない）」の3つです。','社外の客先は、グループに産地報告のシート名を入れます。外販先（旭物産・イバラキ食品など）はグループはいりません。','QR出庫の出庫先に出すものは「出庫先の選択肢に表示する」にチェックを入れます。あとから「表示をやめる」「出庫先に出す」で切り替えられます。','区分を間違えたときは、各行の区分を選び直します。'],
  check:'追加・変更はクラウドに保存され、どの端末でも同じ内容になります（再読込しても消えません）。',
  caution:'外販先への出庫は、出庫先の名前のまま日量・分析・送った荷物の明細Excelに入ります。出荷予定と確定の比較と伝票には入りません。削除しても過去の出庫の記録は残ります。'};
 if(typeof V198_GUIDE_SECTIONS!=='undefined')V198_GUIDE_SECTIONS.c160DestMaster=sec;
 if(typeof V195_ROLE_GUIDES!=='undefined'){const g=V195_ROLE_GUIDES.admin;if(g&&Array.isArray(g.sections)&&!g.sections.some(x=>x.title===sec.title))g.sections.push(sec)}
}catch(e){}

/* 起動したら（ログイン後）クラウドから読み、出庫先の選択肢をそろえる */
(function wait(n=0){
 if(typeof callRpc==="function"&&db&&db.role&&db.userId){c160LoadDests().catch(()=>{});return}
 if(n<240)setTimeout(()=>wait(n+1),500);
})();
})();
