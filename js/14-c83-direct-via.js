
/* ===== v1.199-c83 本社直接入荷（石岡経由） =====
   本社へ直接入荷する原料のうち、一度石岡を経由して積み込むものを、石岡で入庫せずに本社の「入荷待ち原料」として登録し、貼り紙を印刷する。
   石岡のQR在庫・在庫表・在庫/出庫の分析には入らない。受け入れ前なら石岡の管理者・青果社員が取消・再印刷できる。 */
(()=>{
const {hqErr,hqLots,hqRpc,hqToday,hqLotCard,hqPrintBtn,HQ_CONTAINERS,hqSpecMemo,hqFocus}=window.c83Hq||{};
const C83_RUNS=[{name:"配送便",time:"11時"},{name:"原料便",time:"12時"},{name:"市場便",time:"15時以降"}];
const C83_BIG=window.c83Hq?.HQ_BIG_CONTAINERS||["網コンテナ","鉄コンテナ","パレテーナ"];
function c83Can(){return!!window.c83Hq&&["admin","worker"].includes(String(db?.role||""))}
function c83Runs(){return(Array.isArray(db.c50ShipRuns)&&db.c50ShipRuns.length?db.c50ShipRuns:C83_RUNS).filter(r=>r&&r.name)}
function c83AddDays(d,n){const t=new Date(d+"T00:00:00");t.setDate(t.getDate()+n);return ymdKey(t)}
let c83Busy=false,c83DateTouched=false;
async function c83ViaPage(msg=""){
 setScreen("c83ViaPage",[msg]);if(!c83Can())return qrHome();
 c83DateTouched=false;
 pageShell("本社直接入荷（石岡経由）","石岡を通って本社へ運ぶ原料の登録・貼り紙",`<div class="notice">読み込んでいます…</div>`);
 let items=[],rows=[];
 try{[items,rows]=await Promise.all([qrSelect("hq_items_v1400","select=*&active=eq.true&order=sort_order.asc"),hqLots("select=*&via_ishioka=is.true&status=eq.入荷待ち&order=created_at.desc&limit=200")])}
 catch(e){return pageShell("本社直接入荷（石岡経由）","エラー",`<div class="err">読み込みに失敗しました。<br>${esc(hqErr(e))}</div>`)}
 window.__c83Items=items;
 const today=hqToday();
 const list=rows.length?rows.map(l=>hqLotCard(l,false)+hqPrintBtn(l)+`<button class="btn btn2" style="width:100%;margin:-6px 0 16px" ${seikaEventAttrs("click","c83Cancel",[l.id])}>この登録を取消す</button>`).join(""):'<div class="notice">本社でまだ受け入れていない原料はありません。</div>';
 pageShell("本社直接入荷（石岡経由）","石岡を通って本社へ運ぶ原料の登録・貼り紙",`${okHtml(msg)}<div class="card notice"><b>石岡の在庫には入りません</b><div class="small">本社の「入荷待ち原料」に入ります。本社で受け入れを確定すると本社の在庫になります。石岡のQR在庫・在庫表・在庫/出庫の分析には入りません。</div></div>
 <div class="card"><b style="font-size:18px">登録する</b>
 <label class="label" style="margin-top:10px">品目（本社の品目） <span style="color:#dc2626">必須</span></label><select id="c83Item" class="input" ${seikaEventAttrs("change","c83ItemChanged",[])}><option value="">選んでください</option>${items.map(i=>`<option>${esc(i.name)}</option>`).join("")}</select><div class="small">品目がないときは、本社社員が本社の「品目の追加・変更」で追加します。</div>
 <label class="label" style="margin-top:10px">荷姿</label><select id="c83Cont" class="input" ${seikaEventAttrs("change","c83ContChanged",[])}>${HQ_CONTAINERS.map(c=>`<option>${c}</option>`).join("")}</select>
 <div id="c83QtyBox"></div>
 <label class="label" style="margin-top:10px">量目（例：10kg） <span id="c83PackMark" style="color:#dc2626">必須</span></label><input id="c83Pack" class="input">
 <label class="label" style="margin-top:10px">仕入先 <span style="color:#dc2626">必須</span></label><input id="c83Sup" class="input">
 <label class="label" style="margin-top:10px">産地 <span style="color:#dc2626">必須</span></label><input id="c83Ori" class="input">
 <label class="label" style="margin-top:10px">単協名（任意）</label><input id="c83Coop" class="input">
 <label class="label" style="margin-top:10px">規格（任意）</label><input id="c83Spec" class="input" maxlength="20" placeholder="例：3L、秀品">
 <div style="margin-top:12px;padding:10px;border:2px solid #f59e0b;border-radius:12px;background:#fffbeb">
 <label class="label" style="margin-top:0">本社への便（必須）</label><select id="c83Run" class="input"><option value="">選択してください</option>${c83Runs().map((r,i)=>`<option value="${i}">${esc(r.name)}（${esc(r.time||"")}着）</option>`).join("")}</select>
 <label class="label" style="margin-top:10px">当日便・翌日便（必須）</label><select id="c83Day" class="input" ${seikaEventAttrs("change","c83DayChanged",[])}><option value="">選択してください</option><option value="当日便">当日便</option><option value="翌日便">翌日便</option></select>
 <label class="label" style="margin-top:10px">本社入荷日（予定）</label><input id="c83Date" type="date" class="input" value="${today}" ${seikaEventAttrs("change","c83DateChanged",[])}><div class="small">当日便は今日、翌日便は明日が自動で入ります。変えることもできます。</div></div>
 <button class="btn homeBtnHqVia" style="width:100%;margin-top:14px" ${seikaEventAttrs("click","c83Save",[])}>登録して貼り紙の印刷へ</button></div>
 <h3 style="margin:18px 0 8px">本社でまだ受け入れていない原料（${rows.length}件）</h3><div class="small" style="margin-bottom:8px">貼り紙の再印刷・取消ができます。本社で受け入れたあとは、ここには出ません。</div>${list}`);
 c83ContChanged();
}
function c83ContChanged(){const box=document.getElementById("c83QtyBox");if(!box)return;const big=C83_BIG.includes(document.getElementById("c83Cont")?.value||"");const mark=document.getElementById("c83PackMark");if(mark)mark.style.display=big?"none":"";const old=document.getElementById("c83Qty")?.value||"";
 box.innerHTML=big?`<label class="label" style="margin-top:10px">基数（必須）</label><input id="c83Qty" class="input" inputmode="numeric" value="${esc(old)}"><div class="small">網コンテナ・鉄コンテナ・パレテーナは、貼り紙の印刷のときに実測合計kgを入れます。</div>`:`<label class="label" style="margin-top:10px">数量（ケース・必須）</label><input id="c83Qty" class="input" inputmode="decimal" value="${esc(old)}">`}
function c83ItemChanged(){const n=document.getElementById("c83Item")?.value;const it=(window.__c83Items||[]).find(x=>x.name===n);if(!it)return;const p=document.getElementById("c83Pack");if(p&&!p.value)p.value=it.pack_weight||"";const c=document.getElementById("c83Cont");if(c&&it.default_unit==="kg"&&!C83_BIG.includes(c.value)){c.value="網コンテナ";c83ContChanged()}}
function c83DayChanged(){if(c83DateTouched)return;const d=document.getElementById("c83Date"),day=document.getElementById("c83Day")?.value;if(d)d.value=c83AddDays(hqToday(),day==="翌日便"?1:0)}
function c83DateChanged(){c83DateTouched=true}
function c83Focus(id,msg){hqFocus(id,msg)}
async function c83Save(){
 if(c83Busy)return;const v=id=>document.getElementById(id)?.value.trim()||"";
 const cont=v("c83Cont"),big=C83_BIG.includes(cont),q=Number(v("c83Qty")),run=c83Runs()[Number(v("c83Run"))];
 if(!v("c83Item"))return c83Focus("c83Item","品目を選んでください。");
 if(big?!(Number.isInteger(q)&&q>=1&&q<=200):!(Number.isFinite(q)&&q>0))return c83Focus("c83Qty",big?"基数を入れてください。":"数量を入れてください。");
 if(!big&&!v("c83Pack"))return c83Focus("c83Pack","量目を入れてください（例：10kg）。");
 if(!v("c83Sup"))return c83Focus("c83Sup","仕入先を入れてください。");
 if(!v("c83Ori"))return c83Focus("c83Ori","産地を入れてください。");
 if(v("c83Run")===""||!run)return c83Focus("c83Run","本社への便を選択してください。");
 if(!v("c83Day"))return c83Focus("c83Day","当日便か翌日便かを選択してください。");
 if(!v("c83Date"))return c83Focus("c83Date","本社入荷日を入れてください。");
 c83Busy=true;
 try{const a=await hqRpc("hq_direct_via_ishioka_v1199c83",{p_item_name:v("c83Item"),p_origin:v("c83Ori"),p_supplier:v("c83Sup"),p_cooperative_name:v("c83Coop"),p_container_type:cont,p_pack_weight:v("c83Pack"),p_qty:big?null:q,p_count:big?q:null,p_planned_date:v("c83Date"),p_ship_run:run.name,p_ship_run_time:run.time||"",p_ship_day:v("c83Day"),p_memo:hqSpecMemo(v("c83Spec"))});
  c83Busy=false;return hqSheetPage(a.lot.qr_key,"登録しました。貼り紙を印刷してください。")}
 catch(e){c83Busy=false;alert(hqErr(e))}
}
async function c83Cancel(lotId){
 const reason=prompt("取消の理由を入れてください（例：入力の間違い）");if(reason===null)return;
 if(c83Busy)return;c83Busy=true;
 try{await hqRpc("hq_cancel_via_ishioka_v1199c83",{p_lot_id:lotId,p_reason:reason});c83Busy=false;return c83ViaPage("取消しました。本社の入荷待ちからも消えました。")}
 catch(e){c83Busy=false;alert(hqErr(e))}
}
Object.assign(window,{c83ViaPage,c83ContChanged,c83ItemChanged,c83DayChanged,c83DateChanged,c83Save,c83Cancel});
const st=document.createElement("style");st.textContent='.homeBtnHqVia{background:linear-gradient(90deg,#3f2a1d 0%,#7c4a2d 52%,#d6a77a 100%) !important;color:#fff !important;text-shadow:0 1px 2px rgba(0,0,0,.3) !important;border-color:transparent !important;}';document.head.appendChild(st);
const base=qrHome;
qrHome=async function(...a){
 const r=await base.apply(this,a);
 if(currentScreen==="qrHome"&&c83Can()&&!document.getElementById("c83ViaBtn")){
  const host=document.querySelector(".homePrimary"),after=host?.querySelector(".homeBtnQr");
  const html=`<button id="c83ViaBtn" type="button" class="btn homeBtnHqVia" data-c73="1" ${seikaEventAttrs("click","c83ViaPage",[])}>本社直接入荷（石岡経由）<br><span style="font-size:15px;font-weight:800">石岡在庫に入れず本社へ・貼り紙</span></button>`;
  if(after)after.insertAdjacentHTML("afterend",html);else host?.insertAdjacentHTML("beforeend",html);
 }
 return r;
};
window.qrHome=qrHome;
try{
 const sec={title:"本社直接入荷（石岡経由）を登録する",where:"QR在庫管理 → 本社直接入荷（石岡経由）",
  steps:["本社へ直接入荷する原料のうち、石岡を通って積み込むものに使います。石岡の入庫（QR入庫）はしません。",
   "品目（本社の品目）・荷姿・数量を入れます。網コンテナ・鉄コンテナ・パレテーナは数量のかわりに基数を入れます。",
   "量目・仕入先・産地を入れます（必須。網コンテナ・鉄コンテナ・パレテーナは量目を入れなくても登録できます）。単協名と規格は、必要なときだけ入れます。本社への便と当日便・翌日便を選びます。本社入荷日は当日便なら今日、翌日便なら明日が自動で入ります（変更できます）。",
   "「登録して貼り紙の印刷へ」を押すと貼り紙の印刷画面になります。大型容器は、ここで実測合計kgと基数を入れてから印刷します。",
   "貼り紙には「石岡経由」・便・出庫者が出ます。仕入先が入っているときは、単協名は貼り紙に出ません。規格は20文字まで入力できます。入れたときは貼り紙の品名の右に出て、長い場合は文字の大きさを自動で調整します。"],
  check:"本社でまだ受け入れていない原料は、同じ画面の下に出ます。貼り紙の再印刷と取消はここからできます。",
  caution:"石岡のQR在庫・在庫表・在庫/出庫の分析には入りません。本社の入荷待ち原料・本社の在庫にだけ入ります。本社で受け入れたあとは石岡では取消できません。"};
 if(typeof V198_GUIDE_SECTIONS!=="undefined")V198_GUIDE_SECTIONS.c83Via=sec;
 if(typeof V195_ROLE_GUIDES!=="undefined")for(const r of ["admin","worker"]){const g=V195_ROLE_GUIDES[r];if(g&&Array.isArray(g.sections)&&!g.sections.some(x=>x.title===sec.title))g.sections.push(sec)}
}catch(e){}
})();
