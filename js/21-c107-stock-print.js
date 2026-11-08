/* ===== v1.199-c107 在庫表の印刷：A4横1枚・左右2ブロック・在庫がある品目のみ・QR在庫はkg表示 ===== */
(function(){
const PAGE_W=291,PAGE_H=206,MM_PX=96/25.4;
const DAY_LABELS='日月火水木金土';

function c107Positive(text){
  const parts=String(text??'').split('/').map(x=>x.replace(/[,\s]/g,'')).filter(x=>x!=='');
  return parts.some(x=>{const n=Number(x);return Number.isFinite(n)?n>0:true});
}
function c107LatestBy(list){
  let best=null;
  for(const r of list){if(r&&r.createdAt&&(!best||new Date(r.createdAt)>new Date(best.createdAt)))best=r}
  return best;
}
function c107RowHasStock(row){
  if(row.kind==='qr')return Number(row.qrKg)>0;
  if(row.kind==='special'){
    const last=c107LatestBy((db.specialRecords||[]).filter(r=>r.tableId===row.tableId&&r.itemId===row.id));
    return !!last&&Number(last.qty)>0;
  }
  const last=c107LatestBy((db.records||[]).filter(r=>r.itemId===row.id));
  return !!last&&c107Positive(printDayValue(row,ymdKey(new Date(last.createdAt))));
}

const C107_PLAIN_GROUP='適正在庫品目',C107_QR_GROUP='QR在庫',C107_GROUP_ORDER=[C107_PLAIN_GROUP,'その他','片岡在庫',C107_QR_GROUP];
function c107GroupRank(g){const i=C107_GROUP_ORDER.indexOf(g);return i<0?C107_GROUP_ORDER.length-1.5:i}

function c107BuildRows(group,dayKeys,qr){
  const rows=printInventoryRows(group,dayKeys).filter(c107RowHasStock);
  const totals=(qr&&qr.totals)||{},standalone=(qr&&qr.standaloneTotals)||{};
  const items=allSortedItems();
  for(const [id,kg] of Object.entries(totals)){
    if(!(Number(kg)>0))continue;
    const item=items.find(it=>String(it.id)===String(id));
    rows.push({kind:'qr',id,name:`${item?item.name:id}（QR）`,spec:'kg',origin:'',qrKg:Number(kg),sort:Number(item?.sort||0),group:C107_QR_GROUP});
  }
  for(const entry of Object.values(standalone)){
    if(!(Number(entry?.total)>0))continue;
    rows.push({kind:'qr',id:entry.name,name:`${entry.name}（QR）`,spec:'kg',origin:'',qrKg:Number(entry.total),sort:20000,group:C107_QR_GROUP});
  }
  return rows.sort((a,b)=>c107GroupRank(a.group)-c107GroupRank(b.group)||a.sort-b.sort||String(a.name).localeCompare(String(b.name),'ja'));
}

function c107Entries(rows){
  const out=[];
  rows.forEach((r,i)=>{
    if((i===0||r.group!==rows[i-1].group)&&r.group!==C107_PLAIN_GROUP)out.push({type:'section',label:r.group});
    out.push({type:'row',row:r});
  });
  return out;
}
function c107Units(entry){
  if(entry.type==='section')return .7;
  const r=entry.row;
  return Math.max(printInventoryTextUnits(r.name,12),printInventoryTextUnits(r.spec,5),printInventoryTextUnits(r.origin,5));
}
function c107Split(entries){
  const units=entries.map(c107Units),total=units.reduce((a,b)=>a+b,0);
  let best=0,bestGap=Infinity,run=0;
  for(let i=0;i<=entries.length;i++){
    const gap=Math.abs(run-total/2);
    if(gap<bestGap&&!(i>0&&entries[i-1].type==='section')){best=i;bestGap=gap}
    if(i<entries.length)run+=units[i];
  }
  const left=entries.slice(0,best),right=entries.slice(best);
  if(right.length&&right[0].type==='row'&&right[0].row.group!==C107_PLAIN_GROUP){
    right.unshift({type:'section',label:`${right[0].row.group}（続き）`});
  }
  return[left,right];
}

function c107BlockHtml(entries,days,todayKey){
  const head=`<thead><tr><th class="name">品名</th><th class="spec">規格</th><th class="origin">産地</th>${days.map(d=>`<th class="day">${d.getMonth()+1}/${d.getDate()}<br>${DAY_LABELS[d.getDay()]}</th>`).join('')}</tr></thead>`;
  const body=entries.map(e=>{
    if(e.type==='section')return `<tr class="section"><td colspan="10">${esc(e.label)}</td></tr>`;
    const r=e.row;
    const cells=days.map(d=>{
      const key=ymdKey(d);
      if(r.kind==='qr')return `<td class="day">${key===todayKey?esc(fmt(r.qrKg)):''}</td>`;
      return `<td class="day">${esc(printDayValue(r,key))}</td>`;
    }).join('');
    return `<tr class="data${r.kind==='qr'?' qr':''}"><td class="name">${esc(r.name)}</td><td class="spec">${esc(r.spec||'')}</td><td class="origin">${esc(r.origin||'')}</td>${cells}</tr>`;
  }).join('');
  return `<table class="blk">${head}<tbody>${body}</tbody></table>`;
}

function c107Css(){
  return `@page{size:A4 landscape;margin:2mm 3mm}*{box-sizing:border-box}html,body{margin:0;padding:0;background:#fff;color:#111;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif}`+
  `.page{width:${PAGE_W}mm;height:${PAGE_H}mm;overflow:hidden;background:#fff}`+
  `.pageContent{width:calc(100% / var(--fit-scale));transform:scale(var(--fit-scale));transform-origin:top left}`+
  `.printHead{height:7mm;display:flex;justify-content:space-between;align-items:flex-end;gap:3mm;overflow:hidden}`+
  `h1{font-size:11pt;line-height:1;margin:0;font-weight:900;white-space:nowrap}.meta{font-size:6.2pt;line-height:1;text-align:right;white-space:nowrap}`+
  `.blocks{display:flex;gap:3mm;align-items:flex-start;margin-top:.6mm}`+
  `table.blk{flex:1 1 0;min-width:0;border-collapse:collapse;table-layout:fixed}`+
  `th,td{border:.2mm solid #111;padding:var(--pad-y) .4mm;height:var(--row-mm);font-size:var(--font-pt);line-height:1.05;vertical-align:middle;overflow:hidden}`+
  `th{height:5.5mm;background:#eaf3fb;font-weight:900;text-align:center;font-size:calc(var(--font-pt)*.95)}`+
  `.name{width:29%;font-weight:700;white-space:normal;overflow-wrap:anywhere;word-break:break-all}`+
  `.spec{width:10.5%;font-size:calc(var(--font-pt)*.9);overflow-wrap:anywhere;word-break:break-all}`+
  `.origin{width:10%;font-size:calc(var(--font-pt)*.9);overflow-wrap:anywhere;word-break:break-all}`+
  `.day{width:7.2%;text-align:center;white-space:nowrap;letter-spacing:-.03em;font-size:calc(var(--font-pt)*.95)}`+
  `.section td{height:var(--section-mm);background:#dfe7ef;font-weight:900;text-align:left;padding:0 .5mm}`+
  `tr.qr td{background:#f3f8ee}tr.qr td.name{color:#1d4f1d}`+
  `.foot{margin-top:1mm;font-size:6pt;line-height:1.2;color:#333}`+
  `.actions{margin:4mm 0 2mm;font-size:10pt}.backLink{display:inline-block;margin-right:3mm;padding:1.5mm 3mm;border:1px solid #334155;border-radius:1.5mm;color:#0f172a;font-weight:800;text-decoration:none}`+
  `@media screen{body{background:#e2e8f0;padding:8px}.page{box-shadow:0 1px 5px #94a3b8}}`+
  `@media print{html,body{width:${PAGE_W}mm;height:${PAGE_H}mm}.actions{display:none}.page{margin:0;break-inside:avoid;page-break-after:avoid;box-shadow:none}tr{break-inside:avoid;page-break-inside:avoid}}`;
}

function c107Page(inner,vars,scale,backUrl,probe){
  const css=c107Css()+(probe?'.page{height:auto!important;overflow:visible!important}':'');
  const actions=probe?'':`<div class="actions"><a class="backLink" href="${esc(backUrl)}" target="_self">← アプリに戻る</a>PCの印刷画面からA4・横向きで印刷してください。</div>`;
  return `<!doctype html><html lang="ja"><head><meta charset="utf-8"><title>在庫表</title><style>${css}</style></head><body>${actions}<div class="page" style="${vars}--fit-scale:${scale.toFixed(6)};"><div class="pageContent">${inner}</div></div></body></html>`;
}

function c107Measure(inner,vars){
  const frame=document.createElement('iframe');
  frame.setAttribute('aria-hidden','true');
  frame.style.cssText=`position:fixed;left:-100000px;top:0;width:${PAGE_W}mm;height:400mm;border:0;visibility:hidden;pointer-events:none`;
  document.body.appendChild(frame);
  try{
    const doc=frame.contentDocument;doc.open();doc.write(c107Page(inner,vars,1,'',true));doc.close();
    const box=doc.querySelector('.pageContent'),blocks=doc.querySelector('.blocks');
    const h=Math.max(box.getBoundingClientRect().height,box.scrollHeight),w=Math.max(box.getBoundingClientRect().width,blocks.scrollWidth);
    return Math.max(.4,Math.min(1,PAGE_H*MM_PX/Math.max(h,1),PAGE_W*MM_PX/Math.max(w,1)));
  }finally{frame.remove()}
}

window.c107StockPrintHtml=function(group,qr,now=new Date()){
  const title=group==='room3'?'第3冷蔵庫 在庫表':'第2冷蔵庫＋片岡在庫 在庫表';
  const start=printWeekStartDate(),days=[...Array(7)].map((_,i)=>{const d=new Date(start);d.setDate(start.getDate()+i);return d});
  const dayKeys=days.map(d=>ymdKey(d)),rows=c107BuildRows(group,dayKeys,qr),entries=c107Entries(rows),[left,right]=c107Split(entries);
  const maxUnits=Math.max(left.reduce((a,e)=>a+c107Units(e),0),right.reduce((a,e)=>a+c107Units(e),0),1);
  const rowMm=Math.min(6.2,Math.max(2.3,(PAGE_H-4-7-5.5-6)/maxUnits)),fontPt=Math.min(8.5,Math.max(5,rowMm*1.3)),padY=Math.min(.45,Math.max(.04,rowMm*.07));
  const vars=`--row-mm:${rowMm.toFixed(3)}mm;--section-mm:${Math.max(1.8,rowMm*.65).toFixed(3)}mm;--font-pt:${fontPt.toFixed(2)}pt;--pad-y:${padY.toFixed(3)}mm;`;
  const nowKey=ymdKey(now),todayKey=dayKeys.includes(nowKey)?nowKey:(nowKey>dayKeys[6]?dayKeys[6]:dayKeys[0]),unconvertible=Array.isArray(qr?.unconvertible)?qr.unconvertible.length:0;
  const notes=['在庫がある品目だけを表示しています。','「（QR）」の行は印刷時点のQR在庫（kg）で、本日の列に記載しています。'];
  if(unconvertible)notes.push(`kg換算できないQRロットが${unconvertible}件あり、この表には含まれていません。`);
  const inner=`<div class="printHead"><h1>${esc(title)}</h1><div class="meta">${days[0].toLocaleDateString('ja-JP')}〜${days[6].toLocaleDateString('ja-JP')}　印刷：${now.toLocaleString('ja-JP')}　${rows.length}品目</div></div>`+
    `<div class="blocks">${c107BlockHtml(left,days,todayKey)}${c107BlockHtml(right,days,todayKey)}</div><div class="foot">${esc(notes.join(' '))}</div>`;
  const scale=c107Measure(inner,vars);
  return{html:c107Page(inner,vars,scale,location.origin+location.pathname,false),rows,scale,title};
};

window.printInventorySheet=async function(group){
  const w=window.open('','_blank');
  if(!w){alert('印刷画面を開けませんでした。ポップアップ許可を確認してください。');return}
  w.document.open();w.document.write('<!doctype html><html lang="ja"><head><meta charset="utf-8"><title>在庫表</title></head><body style="font:16px sans-serif;padding:16px">在庫表を準備しています…</body></html>');w.document.close();
  const room=group==='room3'?'room3':'room2';
  let qr;
  try{qr=await qrInventoryKgByItemForRoom(room)}
  catch(error){
    try{w.close()}catch(_){}
    alert(`QR在庫を取得できないため、在庫表を印刷できません。\n${typeof v161ErrorText==='function'?v161ErrorText(error):String(error&&error.message||error)}`);return;
  }
  const built=window.c107StockPrintHtml(group,qr);
  w.document.open();w.document.write(built.html);w.document.close();
};
{
  const section={title:'在庫表を印刷する',where:'在庫表 → 印刷用チェック表',
    steps:['在庫表の画面で「第2冷蔵庫＋片岡在庫を印刷」または「第3冷蔵庫を印刷」を押します。','在庫がある品目だけが、左右2ブロックでA4横1枚に出ます。','QR在庫は「QR在庫」の欄にまとめて、kgで出ます。印刷した日の列に印刷時点の在庫が入ります。','PCの印刷画面からA4・横向きで印刷します。'],
    check:'QR在庫を読み込めない場合は、不完全な表を出さずに印刷を止めます。再度押してください。',
    caution:'kg換算できないQRロットがある場合は、表の下に件数が出ます。'};
  for(const role of ['admin','worker','buyer','sales','clerk','viewer','office_viewer']){
    const guide=V195_ROLE_GUIDES[role];
    if(guide&&Array.isArray(guide.sections)&&!guide.sections.some(x=>x.title===section.title))guide.sections.push({...section});
  }
}
})();
