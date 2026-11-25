/* ===== v1.199-c163 返品を石岡の在庫に戻す =====
   本社・埼玉・深谷などから返ってきた分を、元の石岡のロットに戻す（石岡の入荷日はそのまま）。
   ・探し方は2つ：「出庫履歴から選ぶ」（出庫先と期間）と「QRで探す」（石岡のQR・ロット番号、本社で貼ったQR・ロット番号）。
   ・返品日・数量（規格別ロットは規格ごと）・メモを入れて登録する。戻せるのは出した数まで。
   ・本社から返ってきたときは、本社の在庫も同時に減らす（受け入れ済みなら本社の在庫から、入荷待ちなら入荷予定から）。DB側（SQL 067）で行う。
   ・登録した返品の一覧と取消。登録・取消は管理者・青果社員だけ。
   仕入先・産地へ返すほうは、QR出庫の出庫先「返品」を使う（js/02-core.js の c163NoTiming・c163IsReturnDest）。 */
(()=>{
const NO_RETURN=["","廃棄","返品"];
const st={mode:"list",dest:"",from:"",to:"",key:"",rows:[],returns:[],loaded:false,error:"",form:null,busy:false,camera:null};
const canReturn=()=>["admin","worker"].includes(db?.role);
const addDays=(d,n)=>{const t=new Date(d+"T00:00:00");t.setDate(t.getDate()+n);return new Intl.DateTimeFormat("sv-SE").format(t)};
const md=d=>{const m=String(d||"").match(/^\d{4}-(\d{2})-(\d{2})/);return m?`${Number(m[1])}/${Number(m[2])}`:"-"};
const num=v=>{if(String(v??"").trim()==="")return null;const n=Number(v);return Number.isFinite(n)?n:null};
const errorText=e=>{const s=String(e?.message||e||"");
 if(/PGRST202|Could not find the function|v1199c163.*does not exist/i.test(s))return"返品の準備（SQL 067）がまだ実行されていません。管理者に連絡してください。";
 const m=s.match(/"message"\s*:\s*"([^"]+)"/);return m?m[1]:s||"できませんでした。"};
const dests=()=>{try{return (QR_OUT_DESTINATIONS||[]).filter(d=>!NO_RETURN.includes(String(d).trim()))}catch(_){return["本社","埼玉","深谷"]}};
const hqText=h=>{if(!h)return"";if(h.status==="入荷待ち")return`本社：入荷待ち（予定 ${fmt(h.planned_qty)} ${esc(h.unit||"")}）→ 戻すと入荷予定を減らします`;
 if(h.status==="取消")return"本社：入荷待ちを取消済み";return`本社：受け入れ済み（本社の残り ${fmt(h.current_qty)} ${esc(h.unit||"")}）→ 戻すと本社の在庫も減らします`};

async function c163Search(){
 st.dest=document.getElementById("c163Dest")?.value??st.dest;
 st.from=document.getElementById("c163From")?.value||st.from;st.to=document.getElementById("c163To")?.value||st.to;
 st.key=(document.getElementById("c163Key")?.value??st.key).trim();
 if(st.mode==="qr"&&!st.key)return alert("QRを読むか、ロット番号を入れてください。");
 if(st.mode==="list"&&st.from>st.to)[st.from,st.to]=[st.to,st.from];
 const box=document.getElementById("c163Results");if(box)box.innerHTML='<div class="notice">探しています…</div>';
 try{
  const ans=await callRpc("list_qr_returnable_v1199c163",st.mode==="qr"?{p_destination:null,p_from:null,p_to:null,p_qr_key:st.key}:{p_destination:st.dest||null,p_from:st.from,p_to:st.to,p_qr_key:null});
  st.rows=Array.isArray(ans)?ans:[];st.error="";
 }catch(e){st.rows=[];st.error=errorText(e)}
 st.loaded=true;renderResults();
}
function renderResults(){
 const box=document.getElementById("c163Results");if(!box)return;
 if(st.error){box.innerHTML=`<div class="card err">${esc(st.error)}</div>`;return}
 if(!st.loaded){box.innerHTML="";return}
 if(!st.rows.length){box.innerHTML=`<div class="notice">${st.mode==="qr"?"このQRの出庫は見つかりませんでした（廃棄・返品・取り消した出庫は出ません）。":"この条件の出庫はありません。"}</div>`;return}
 box.innerHTML=st.rows.map((r,i)=>{
  const left=Number(r.left)||0,done=Number(r.returned)||0;
  return `<article class="card" style="margin:10px 0"><div class="itemHead"><b>${esc(r.item_name||"-")}</b><span class="badge normal">${esc(r.destination||"")}</span></div>
<div class="small">ロット：${esc(r.lot_no||r.qr_key||"-")} ／ 石岡の入荷日：${esc(md(r.received_date))} ／ 出庫日：${esc(md(r.out_date))}${r.origin?` ／ ${esc(r.origin)}`:""}</div>
<div class="grid" style="margin-top:8px"><div class="box">出した数<b>${fmt(r.qty)} ${esc(r.unit||"")}</b></div><div class="box">戻した数<b>${fmt(done)}</b></div><div class="box">まだ戻せる数<b>${fmt(left)}</b></div></div>
${r.hq?`<div class="small" style="margin-top:6px">${hqText(r.hq)}</div>`:""}
${!r.lot_active?'<div class="small" style="color:#b91c1c;margin-top:6px">元のロットが削除されているため戻せません。</div>':left>0&&canReturn()?`<button class="btn orange" style="width:100%;margin-top:10px" ${seikaEventAttrs("click","c163OpenForm",[i])}>石岡の在庫に戻す</button>`:left>0?"":'<div class="small" style="margin-top:6px">出した数はすべて戻し済みです。</div>'}</article>`;
 }).join("");
}

function c163OpenForm(i){
 if(!canReturn())return alert("返品の登録は管理者・青果社員のみです。");
 const r=st.rows[i];if(!r)return;
 const grades=(Array.isArray(r.grades)?r.grades:[]).filter(g=>Number(g.left)>0);
 st.form={r,grades,opId:operationMeta("qr_return_c163",{movementId:r.movement_id}).operationId,attempt:null};
 c163StopCamera();
 setScreen("c163ReturnsPage",[]);
 const today=todayKey(),min=String(r.out_date||"").slice(0,10);
 pageShell("返品を石岡の在庫に戻す",`${esc(r.item_name||"")} ／ ${esc(r.destination||"")}から。元の石岡のロット（入荷日 ${esc(md(r.received_date))}）に戻します。`,
 `<div class="card"><div class="small">元の出庫：${esc(md(r.out_date))} ${esc(r.destination||"")}へ ${fmt(r.qty)} ${esc(r.unit||"")}（まだ戻せる数 ${fmt(r.left)}）</div>
${r.hq?`<div class="notice" style="margin-top:8px">${hqText(r.hq)}</div>`:""}
<label class="label" style="margin-top:12px">返品日 <span style="color:#dc2626">必須</span></label><input id="c163Date" type="date" class="input" value="${esc(today)}" max="${esc(today)}" ${min?`min="${esc(min)}"`:""}>
<label class="label">戻す数量（${esc(r.unit||"")}） <span style="color:#dc2626">必須</span></label><input id="c163Qty" class="input" inputmode="decimal" value="${esc(String(r.left??""))}">
${grades.length?`<div class="small" style="margin-top:10px;font-weight:800">規格ごとの数（合計を戻す数量に合わせてください）</div>${grades.map((g,k)=>`<label class="label">${esc(g.grade)}（戻せる数 ${fmt(g.left)}）</label><input id="c163Grade_${k}" class="input" inputmode="decimal" value="${esc(String(g.left))}">`).join("")}`:""}
<label class="label">メモ（返品の理由など）</label><input id="c163Memo" class="input" maxlength="300" placeholder="例：品質不良で埼玉から戻り">
<div class="small" style="margin-top:8px">石岡の在庫履歴には「返品入庫」として残ります。入荷日は変わりません。</div>
<div id="c163Message" class="small" role="status" style="margin-top:10px;color:#b91c1c"></div>
<div class="row" style="margin-top:12px"><button id="c163Back" class="btn btn2" ${seikaEventAttrs("click","c163BackToList",[])}>戻る</button><button id="c163Save" class="btn orange" ${seikaEventAttrs("click","c163Save",[])}>登録する</button></div></div>`);
}
async function c163Save(){
 const f=st.form;if(!f||st.busy)return;
 if(!canReturn())return alert("返品の登録は管理者・青果社員のみです。");
 const r=f.r,day=document.getElementById("c163Date")?.value||"",qty=num(document.getElementById("c163Qty")?.value),memo=(document.getElementById("c163Memo")?.value||"").trim();
 if(!/^\d{4}-\d{2}-\d{2}$/.test(day))return alert("返品日を入れてください。");
 if(day>todayKey())return alert("返品日に先の日付は入れられません。");
 if(!(qty>0))return alert("戻す数量を0より大きい数で入れてください。");
 if(qty>Number(r.left)+1e-9)return alert(`戻せるのは ${fmt(r.left)} ${r.unit||""} までです。`);
 const grades=f.grades.map((g,k)=>({grade:g.grade,qty:num(document.getElementById(`c163Grade_${k}`)?.value)}));
 if(grades.length){
  if(grades.some(g=>g.qty===null||g.qty<0))return alert("規格ごとの数を0以上で入れてください。");
  if(grades.some((g,k)=>g.qty>Number(f.grades[k].left)+1e-9))return alert("規格ごとの数は、出した数より多くできません。");
  if(Math.abs(grades.reduce((n,g)=>n+g.qty,0)-qty)>1e-9)return alert("規格ごとの数の合計を、戻す数量に合わせてください。");
 }
 const args={p_operation_id:f.opId,p_movement_id:r.movement_id,p_qty:qty,p_return_date:day,p_memo:memo,p_grades:grades.filter(g=>g.qty>0)};
 const fp=JSON.stringify(args);
 if(f.attempt&&f.attempt!==fp){f.opId=operationMeta("qr_return_c163",{movementId:r.movement_id}).operationId;args.p_operation_id=f.opId}
 if(!confirm(`${r.item_name||""}\n${r.destination||""}から ${fmt(qty)} ${r.unit||""} を石岡の在庫に戻します。\n返品日：${day}\n${r.hq&&r.hq.status!=="取消"?(r.hq.status==="入荷待ち"?"本社の入荷予定も減らします。\n":"本社の在庫も減らします。\n"):""}\n登録しますか？`))return;
 st.busy=true;f.attempt=JSON.stringify(args);
 const controls=[...document.querySelectorAll("#c163Date,#c163Qty,#c163Memo,[id^='c163Grade_'],#c163Save,#c163Back")];controls.forEach(x=>x.disabled=true);
 try{
  const ans=await callRpc("return_qr_to_ishioka_v1199c163",args);
  if(!ans?.ok)throw new Error(ans?.message||"登録できませんでした。");
  st.form=null;
  const hq=ans.hq_action==="在庫から減らす"?`\n本社の在庫を ${fmt(ans.hq_qty)} ${ans.hq_unit||""} 減らしました。`:ans.hq_action==="入荷予定を減らす"?`\n本社の入荷予定を ${fmt(ans.hq_qty)} ${ans.hq_unit||""} 減らしました。`:"";
  await c163ReturnsPage({keep:true,msg:`石岡の在庫に戻しました（${fmt(ans.before_quantity)} → ${fmt(ans.after_quantity)}）。${hq}`});
 }catch(e){const box=document.getElementById("c163Message");if(box)box.textContent=errorText(e);else alert(errorText(e))}
 finally{st.busy=false;controls.forEach(x=>x.disabled=false)}
}
function c163BackToList(){st.form=null;return c163ReturnsPage({keep:true})}

async function c163LoadReturns(){
 const box=document.getElementById("c163Returns");if(!box)return;
 try{const ans=await callRpc("list_qr_returns_v1199c163",{p_limit:50});st.returns=Array.isArray(ans)?ans:[]}
 catch(e){box.innerHTML=`<div class="small">${esc(errorText(e))}</div>`;return}
 if(!st.returns.length){box.innerHTML='<div class="small">まだ登録した返品はありません。</div>';return}
 box.innerHTML=st.returns.map(x=>`<div class="itemHead" style="margin-top:8px;${x.cancelled_at?"opacity:.6":""}"><div><b>${esc(x.item_name||"")}</b> ${x.cancelled_at?'<span class="badge shortage">取消済み</span>':""}
<div class="small">返品日 ${esc(md(x.return_date))} ／ ${esc(x.from||"")}から ${fmt(x.qty)} ${esc(x.unit||"")}（${esc(md(x.out_date))}出庫分） ／ ロット ${esc(x.lot_no||x.qr_key||"")} ／ 入荷日 ${esc(md(x.received_date))}${x.hq_action?` ／ 本社：${esc(x.hq_action)} ${fmt(x.hq_qty)}`:""}${x.memo?` ／ ${esc(x.memo)}`:""} ／ ${esc(x.created_by_name||"")}${x.cancelled_at&&x.cancel_reason?` ／ 取消の理由：${esc(x.cancel_reason)}`:""}</div></div>
${!x.cancelled_at&&canReturn()?`<button class="btn btn2" ${seikaEventAttrs("click","c163Cancel",[x.id])}>取消</button>`:""}</div>`).join("");
}
async function c163Cancel(id){
 if(!canReturn())return alert("返品の取消は管理者・青果社員のみです。");
 const x=st.returns.find(r=>r.id===id);if(!x)return;
 const reason=(prompt(`${x.item_name||""}（${x.from||""}から ${fmt(x.qty)} ${x.unit||""}）の返品を取り消します。\n石岡の在庫から ${fmt(x.qty)} 減らし、本社の分も元に戻します。\n\n取り消す理由を入れてください`)||"").trim();
 if(!reason)return;
 try{
  const ans=await callRpc("cancel_qr_return_v1199c163",{p_operation_id:operationMeta("qr_return_cancel_c163",{returnId:id}).operationId,p_return_id:id,p_reason:reason});
  if(!ans?.ok)throw new Error(ans?.message||"取り消せませんでした。");
  await c163ReturnsPage({keep:true,msg:"返品を取り消しました。"});
 }catch(e){alert(errorText(e))}
}

function c163SetMode(mode){st.mode=mode==="qr"?"qr":"list";st.rows=[];st.loaded=false;st.error="";return c163ReturnsPage({keep:true})}
async function c163ReturnsPage(opt={}){
 c163StopCamera();
 if(!canReturn()&&!opt.keep)return alert("返品の登録は管理者・青果社員のみです。");
 const today=todayKey();
 if(!opt.keep){st.rows=[];st.loaded=false;st.error="";st.form=null}
 if(opt.key!==undefined){st.mode="qr";st.key=String(opt.key||"")}
 if(!st.from)st.from=addDays(today,-7);if(!st.to)st.to=today;
 setScreen("c163ReturnsPage",[]);
 const tab=(m,l)=>`<button class="btn ${st.mode===m?"blue":"btn2"}" ${seikaEventAttrs("click","c163SetMode",[m])}>${l}</button>`;
 const finder=st.mode==="qr"
  ?`<label class="label">QR・ロット番号（石岡のQRのほか、本社で貼ったQRでも探せます）</label><input id="c163Key" class="input" value="${esc(st.key)}" placeholder="QRを読むか、ロット番号を入れる" ${seikaEventAttrs("keydown","c163KeyEnter",[])}>
<div class="row" style="margin-top:8px"><button class="btn btn2" ${seikaEventAttrs("click","c163StartCamera",[])}>カメラでQRを読む</button><button class="btn blue" ${seikaEventAttrs("click","c163Search",[])}>探す</button></div><div id="c163Reader" style="width:100%;margin-top:8px"></div><div id="c163CameraMsg" class="small"></div>`
  :`<label class="label">返ってきた元の出庫先</label><select id="c163Dest" class="input"><option value="">すべて</option>${dests().map(d=>`<option value="${esc(d)}" ${d===st.dest?"selected":""}>${esc(d)}</option>`).join("")}</select>
<div class="row"><div><label class="label">出庫日（はじめ）</label><input id="c163From" type="date" class="input" value="${esc(st.from)}"></div><div><label class="label">出庫日（終わり）</label><input id="c163To" type="date" class="input" value="${esc(st.to)}" max="${esc(today)}"></div></div>
<button class="btn blue" style="width:100%;margin-top:10px" ${seikaEventAttrs("click","c163Search",[])}>探す</button>`;
 pageShell("返品を石岡の在庫に戻す","本社・埼玉・深谷などから返ってきた分を、元の石岡のロットに戻します（入荷日はそのまま）。",
 `${okHtml(opt.msg||"")}<div class="card"><div class="row" style="gap:6px">${tab("list","出庫履歴から選ぶ")}${tab("qr","QRで探す")}</div>${finder}
<div class="small" style="margin-top:8px">仕入先・産地へ返すときは、ここではなく「QR出庫」で出庫先「返品」を選んでください（理由のメモが必要です）。</div></div>
<div id="c163Results"></div>
<div class="card"><b>登録した返品（新しい順・50件）</b><div id="c163Returns" class="small">読み込んでいます…</div></div>`);
 renderResults();
 c163LoadReturns();
 if(opt.key&&!opt.keep)await c163Search();
 else if(opt.keep&&st.loaded&&!st.form&&opt.msg)await c163Search();
}
function c163KeyEnter(ev){if(ev?.key==="Enter")c163Search()}
function c163StopCamera(){const r=st.camera;st.camera=null;if(r){r.stop().catch(()=>{});if(qrActiveCameraReader===r)qrActiveCameraReader=null}}
async function c163StartCamera(){
 const msg=document.getElementById("c163CameraMsg");
 if(typeof Html5Qrcode==="undefined"){if(msg)msg.textContent="QR読取の部品を読み込めませんでした。ロット番号を入れて探してください。";return}
 c163StopCamera();try{await qrStopActiveCamera("lot")}catch(_){}
 const reader=new Html5Qrcode("c163Reader");st.camera=reader;qrActiveCameraReader=reader;
 if(msg)msg.textContent="カメラ許可を求められたら許可してください。";
 reader.start({facingMode:"environment"},{fps:10,qrbox:{width:250,height:250}},txt=>{
  c163StopCamera();const key=typeof qrExtractKey==="function"?qrExtractKey(txt):txt;
  const el=document.getElementById("c163Key");if(el)el.value=key;st.key=key;if(msg)msg.textContent="";c163Search();
 },()=>{}).catch(e=>{c163StopCamera();if(msg)msg.textContent="カメラを起動できませんでした。ロット番号を入れて探してください。"+String(e?.message||e)});
}

/* QR出庫履歴のカードに「石岡の在庫に戻す」 */
try{
 const cardsBase=v1144OutboundCards;
 const ok=r=>canReturn()&&!r?.is_cancelled&&!r?.cancelled_at&&String(r?.movement_type||"出庫")==="出庫"&&!NO_RETURN.includes(String(r?.destination||"").trim())&&!!r?.qr_key;
 v1144OutboundCards=function(rows){
  const html=cardsBase.apply(this,arguments);let i=0;
  return html.replace(/<\/article>/g,end=>{const r=rows[i++];return ok(r)?`<button class="btn btn2" style="width:100%;margin-top:8px" ${seikaEventAttrs("click","c163ReturnsPage",[{key:r.qr_key}])}>返品を石岡の在庫に戻す</button>${end}`:end});
 };
 window.v1144OutboundCards=v1144OutboundCards;
}catch(e){}

/* QR在庫管理のホームにボタン */
try{
 const homeBase=qrHome;
 qrHome=async function(...a){
  const r=await homeBase.apply(this,a);
  try{
   if(currentScreen==="qrHome"&&canReturn()&&!document.getElementById("c163ReturnsButton")){
    const anchor=document.getElementById("v1144QrOutboundHistoryButton");
    if(anchor)anchor.insertAdjacentHTML("afterend",`<button id="c163ReturnsButton" type="button" class="btn homeBtnOutboundHistory" ${seikaEventAttrs("click","c163ReturnsPage",[])}>返品を石岡の在庫に戻す<br><span style="font-size:15px;font-weight:800">本社・埼玉・深谷などから返ってきた分</span></button>`);
   }
  }catch(_){}
  return r;
 };
 window.qrHome=qrHome;
}catch(e){}

Object.assign(window,{c163ReturnsPage,c163Search,c163SetMode,c163OpenForm,c163Save,c163BackToList,c163Cancel,c163KeyEnter,c163StartCamera,c163StopCamera,c163ReturnsState:st});

try{
 const secIn={title:'返品を石岡の在庫に戻す（本社・埼玉・深谷などから）',where:'QR在庫管理 →「返品を石岡の在庫に戻す」（QR出庫履歴のカードからも開けます）',
  steps:['「出庫履歴から選ぶ」で、返ってきた元の出庫先と出庫日の期間を選んで「探す」を押します。「QRで探す」なら、QRを読むかロット番号を入れます（本社で貼ったQRでも探せます）。','返ってきた出庫の「石岡の在庫に戻す」を押します。','返品日・戻す数量（規格別ロットは規格ごと）・メモを入れて「登録する」を押します。'],
  check:'元の石岡のロットの在庫が増え、在庫履歴に「返品入庫」が残ります。入荷日は変わりません。本社から返ってきたときは、本社の在庫（入荷待ちなら入荷予定）も同時に減ります。',
  caution:'戻せるのは出した数までです。本社で使った分や下処理で使う予定の分は戻せません。間違えたときは「登録した返品」の一覧から取り消します（石岡の在庫に返品した分が残っているときだけ）。'};
 const secOut={title:'仕入先・産地へ返品する（出庫先「返品」）',where:'QR在庫管理 → QR出庫（単発・連続・棚卸しの簡単出庫）',
  steps:['出庫先で「返品」を選びます。当日発注分／翌日発注分の区分はいりません。','メモに返品の理由を入れます（必須）。'],
  check:'在庫から減り、出庫の記録に出庫先「返品」で残ります。',
  caution:'返品の出庫は、日量・在庫と出庫の分析・出荷予定との比べ・伝票には入りません。'};
 if(typeof V198_GUIDE_SECTIONS!=='undefined'){V198_GUIDE_SECTIONS.c163ReturnIn=secIn;V198_GUIDE_SECTIONS.c163ReturnOut=secOut}
 if(typeof V195_ROLE_GUIDES!=='undefined')for(const role of ['admin','worker']){const g=V195_ROLE_GUIDES[role];if(g&&Array.isArray(g.sections))for(const sec of [secOut,secIn])if(!g.sections.some(x=>x.title===sec.title))g.sections.push(sec)}
}catch(e){}
})();
