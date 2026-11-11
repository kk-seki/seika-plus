/* ===== v1.199-c113 埼玉・深谷QR出庫の当日数量訂正 ===== */
(()=>{
const DESTS=['埼玉','深谷'],BIG=['網コンテナ','鉄コンテナ','パレテーナ'],LATER_OK=['出庫','取消','入庫・調整増','出庫・調整減','差分なし','調整','場所移動','重量確定','重量更新','ロット情報訂正'];
let state=null,busy=false;
const canCorrect=()=>['admin','worker'].includes(db?.role);
const number=v=>{if(String(v??'').trim()==='')return null;const n=Number(v);return Number.isFinite(n)&&n>=0?n:null};
const day=v=>{const d=new Date(v);return Number.isFinite(d.getTime())?new Intl.DateTimeFormat('sv-SE',{timeZone:'Asia/Tokyo'}).format(d):''};
const allowed=r=>canCorrect()&&r?.movement_type!=='取消'&&DESTS.includes(r?.destination)&&!r?.is_cancelled&&!r?.cancelled_at&&!r?.reversed_operation_id&&!!r?.operation_id&&day(r.occurred_at||r.created_at)===day(new Date());
const errorText=e=>{const s=String(e?.message||e||'');return /PGRST202|Could not find the function/i.test(s)?'訂正の準備（SQL 043）がまだ実行されていません。管理者に連絡してください。':s||'保存できませんでした。'};
const cardsBase=v1144OutboundCards;
v1144OutboundCards=function(rows){
  const html=cardsBase.apply(this,arguments);let i=0;
  return html.replace(/<\/article>/g,end=>{const r=rows[i++];return allowed(r)?`<button class="btn orange" style="width:100%;margin-top:8px" ${seikaEventAttrs('click','c113CorrectPage',[r.operation_id])}>数を訂正</button>${end}`:end});
};
window.v1144OutboundCards=v1144OutboundCards;
async function c113CorrectPage(op){
  if(!canCorrect())return alert('出庫数の訂正は管理者・青果社員のみです。');
  if(busy)return;
  try{
    const m=(await qrSelect('qr_lot_movements',`select=*&operation_id=eq.${encodeURIComponent(op)}&limit=1`))[0];
    if(!m)throw new Error('元の出庫履歴が見つかりません。');
    if(!allowed(m))throw new Error('埼玉・深谷への未取消の当日出庫だけ訂正できます。');
    const [lots,grades,after]=await Promise.all([
      qrSelect('qr_lots',`select=*&id=eq.${encodeURIComponent(m.lot_id)}&limit=1`),
      qrSelect('qr_lot_grades_v1300',`select=*&lot_id=eq.${encodeURIComponent(m.lot_id)}&order=sort_order.asc`),
      qrSelect('qr_lot_movements',`select=id,movement_type,created_at&lot_id=eq.${encodeURIComponent(m.lot_id)}&created_at=gt.${encodeURIComponent(m.created_at)}&order=created_at.asc`)
    ]);
    const lot=lots[0];if(!lot)throw new Error('対象QRロットが見つかりません。');
    const blocked=after.find(x=>!LATER_OK.includes(x.movement_type));
    if(blocked)throw new Error(`この出庫の後に「${blocked.movement_type}」があるため訂正できません。`);
    const old=Array.isArray(m.operation_meta?.grades)?m.operation_meta.grades:[];
    state={m,lot,grades:grades.map(g=>({...g,qty:Math.abs(Number(old.find(x=>x.grade===g.grade)?.delta??0))})),later:after.map(x=>x.movement_type).filter(t=>t!=='出庫'&&t!=='取消'),opId:operationMeta('qr_outbound_correct',{originalOperationId:op}).operationId,attempt:null};
    render();
  }catch(e){alert(errorText(e))}
}
const round=n=>Math.round(n*1e6)/1e6;
const stockAfter=q=>round(Number(state.lot.current_qty)+Number(state.m.qty)-q);
const previewText=q=>{const after=stockAfter(q),unit=state.lot.unit||state.m.unit||'';return after<0?'在庫が足りません。':`在庫：現在 ${fmt(state.lot.current_qty)} → 訂正後 ${fmt(after)} ${unit}`};
function c113Preview(){const box=document.getElementById('c113Preview'),q=number(document.getElementById('c113Qty')?.value);if(box&&state)box.textContent=q===null?'':previewText(q)}
function render(){
  const s=state,m=s.m,l=s.lot,big=BIG.includes(m.container_type||l.container_type);
  setScreen('c113CorrectPage',[m.operation_id]);
  pageShell('QR出庫数を訂正',`${esc(m.item_name||'')} / ${esc(m.destination)}。元の出庫履歴は残し、正しい数で出庫し直します。`,
    `<div class="card"><div class="small">元の出庫</div><b>${fmt(m.qty)} ${esc(m.unit||'')}</b><div class="small">現在の在庫：${fmt(l.current_qty)} ${esc(l.unit||m.unit||'')}</div>
    ${s.later.length?`<div class="notice" style="margin-top:10px">この出庫の後に「${esc([...new Set(s.later)].join('」「'))}」があります。訂正は出庫数の差の分だけを現在の在庫へ反映します。実際の在庫数と合っているか確認してください。</div>`:''}
    <label class="label" style="margin-top:12px">訂正後の出庫数</label><input id="c113Qty" class="input" inputmode="decimal" value="${esc(String(m.qty??''))}" ${seikaEventAttrs('input','c113Preview',[])}>
    <div id="c113Preview" class="small" role="status" style="margin-top:6px;font-weight:800">${esc(previewText(Number(m.qty)))}</div>
    ${s.grades.length?`<div class="small" style="margin-top:10px;font-weight:800">規格ごとの訂正後数量（0も入力）</div>${s.grades.map((g,i)=>`<label class="label">${esc(g.grade)}</label><input id="c113Grade_${i}" class="input" inputmode="decimal" value="${esc(String(g.qty))}">`).join('')}`:''}
    ${big?'<label class="label" style="margin-top:10px">訂正後の総重量（kg）</label><input id="c113Kg" class="input" inputmode="decimal" placeholder="例：808"><div class="small">0で全部取りやめる場合は、重量の入力は不要です。</div>':''}
    <div class="small" style="margin-top:10px">0にすると出庫を取り消します。在庫を超える数にはできません。翌日、または棚卸し・入庫・廃棄の後は訂正できません。</div>
    <div id="c113Message" class="small" role="status" style="margin-top:10px;color:#b91c1c"></div><div class="row" style="margin-top:12px"><button id="c113Back" class="btn btn2" ${seikaEventAttrs('click','v1144ReturnToOutboundHistory',[])}>戻る</button><button id="c113Save" class="btn orange" ${seikaEventAttrs('click','c113Save',[])}>訂正を保存</button></div></div>`);
}
async function c113Save(){
  if(busy||!state)return;
  if(!canCorrect())return alert('出庫数の訂正は管理者・青果社員のみです。');
  const s=state,q=number(document.getElementById('c113Qty')?.value);
  if(q===null)return alert('訂正後の出庫数は0以上の数字で入力してください。');
  if(q>Number(s.lot.current_qty)+Number(s.m.qty))return alert('訂正後の出庫数に必要な在庫がありません。');
  const grades=s.grades.map((g,i)=>({grade:g.grade,qty:number(document.getElementById(`c113Grade_${i}`)?.value)}));
  if(grades.length&&(grades.some(g=>g.qty===null)||Math.abs(grades.reduce((n,g)=>n+g.qty,0)-q)>1e-9))return alert('規格ごとの数量を0以上で入力し、合計を出庫数と一致させてください。');
  const big=BIG.includes(s.m.container_type||s.lot.container_type),kg=big&&q>0?number(document.getElementById('c113Kg')?.value):null;
  if(big&&q>0&&!(kg>0&&kg<100000))return alert('大型容器は訂正後の総重量を0より大きく100000未満で入力してください。');
  const args={p_operation_id:s.opId,p_original_operation_id:s.m.operation_id,p_qty:q,p_expected_qty:Number(s.lot.current_qty),p_grades:grades,p_total_kg:kg,p_device_meta:{deviceId:operationMeta('qr_outbound_correct').deviceId,userAgent:navigator.userAgent||''}};
  const fingerprint=JSON.stringify({...args,p_device_meta:null});
  if(s.attempt&&s.attempt!==fingerprint)return alert('先ほどの保存結果を確認するため、同じ入力で再試行してください。数量を変える場合は履歴画面を開き直して最新の出庫を確認してください。');
  if(!confirm(`${s.m.item_name||''} → ${s.m.destination}\n出庫数を ${fmt(s.m.qty)} → ${fmt(q)} ${s.m.unit||''} に訂正します。\n${previewText(q)}\n${q===0?'全部取りやめとして在庫へ戻します。':'在庫には差の分だけを反映します。'}\n保存しますか？`))return;
  busy=true;s.attempt=fingerprint;
  const controls=[...document.querySelectorAll('#c113Qty,#c113Kg,[id^="c113Grade_"],#c113Save,#c113Back')];controls.forEach(x=>x.disabled=true);
  try{
    const ans=await callRpc('correct_qr_outbound_v1199c113',args);
    if(!ans?.ok){s.attempt=null;throw new Error(ans?.message||'保存できませんでした。')}
    state=null;
    v1144QrOutboundHistoryPage({destination:v1144OutboundState.destination,date:v1144OutboundState.date,includeCancelled:v1144OutboundState.includeCancelled,autoLoad:false});
    await v1144LoadOutboundHistory(false);
    document.getElementById('v1144OutboundResults')?.insertAdjacentHTML('beforebegin','<div class="notice" role="status">出庫数の訂正は保存済みです。履歴を取得できない場合は「再読込」で確認してください。</div>');
  }catch(e){
    const box=document.getElementById('c113Message');
    if(box)box.textContent=errorText(e);else alert(`出庫数の訂正は保存済みですが、履歴の表示に失敗しました。${errorText(e)}`);
  }finally{busy=false;controls.forEach(x=>x.disabled=false)}
}
const cancelBase=v1231CancelLatest;
v1231CancelLatest=async function(q,id){
  try{
    const r=(await qrSelect('qr_lot_movements',`select=operation_meta&id=eq.${encodeURIComponent(id)}&limit=1`))[0];
    if(r?.operation_meta?.outbound_correction_operation_id)return alert('出庫数訂正で作成した出庫は、通常の取消では取り消せません。出庫履歴の「数を訂正」から正しい数を入れてください。');
  }catch(e){return alert(errorText(e))}
  return cancelBase.apply(this,arguments);
};
window.v1231CancelLatest=v1231CancelLatest;
const guide={title:'埼玉・深谷へのQR出庫数を訂正する',where:'ホーム → QR出庫履歴 → 該当の出庫 →「数を訂正」',
  steps:['管理者・青果社員は、埼玉・深谷へ出庫した当日の行から「数を訂正」を押します。','訂正後の出庫数を入れます。0にすると出庫を全部取り消します。','規格別ロットは全規格を0を含めて入力し、合計を出庫数に合わせます。大型容器は訂正後の総重量も入力します（0の場合は不要）。入数は元の出庫から引き継ぎます。','確認して保存します。訂正後の出庫も「数を訂正」から再訂正できます。'],
  check:'出庫履歴の数量と在庫数、伝票の数量が正しいことを確認します。印刷済みの伝票は訂正後に作り直してください。',
  caution:'在庫を超える数にはできません。翌日になった後、または棚卸し・入庫・廃棄の後は訂正できません。出庫の後に実数調整や場所移動をしていても訂正できますが、出庫数の差の分だけ現在の在庫が増減するため、訂正前後の在庫が実際の数と合っているか確認します。合わない場合は実数調整で在庫を直します（出庫履歴・伝票の数量は変わりません）。訂正後の出庫は通常の「直前操作を取消」ではなく、数の再訂正を使います。'};
for(const role of ['admin','worker']){const g=V195_ROLE_GUIDES[role];if(g?.sections&&!g.sections.some(x=>x.title===guide.title))g.sections.push({...guide})}
Object.assign(window,{c113CorrectPage,c113Save,c113Preview});
})();
