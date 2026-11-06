
/* ===== v1.199-c81 在庫・出庫の分析（石岡） ===== */
(()=>{
const A={tab:"stock",by:"dest",q:"",period:"thisMonth",from:"",to:"",item:"",data:null,key:""};
const pad=n=>String(n).padStart(2,"0");
const dk=d=>`${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())}`;
const jstDay=iso=>{const d=new Date(iso);return Number.isFinite(d.getTime())?dk(d):""};
const n1=v=>v==null||!Number.isFinite(Number(v))?"—":(Math.round(Number(v)*10)/10).toLocaleString("ja-JP");
function range(){
 const t=new Date();t.setHours(0,0,0,0);const today=dk(t);let f,to=today;
 if(A.period==="thisMonth")f=dk(new Date(t.getFullYear(),t.getMonth(),1));
 else if(A.period==="lastMonth"){f=dk(new Date(t.getFullYear(),t.getMonth()-1,1));to=dk(new Date(t.getFullYear(),t.getMonth(),0))}
 else if(A.period==="3months"){const d=new Date(t);d.setMonth(d.getMonth()-3);d.setDate(d.getDate()+1);f=dk(d)}
 else if(A.period==="fiscal"){const y=t.getMonth()>=8?t.getFullYear():t.getFullYear()-1;f=`${y}-09-01`}
 else{f=A.from||today;to=A.to||today;if(to>today)to=today;if(f>to)[f,to]=[to,f]}
 return {from:f,to};
}
function prevRange(f,t){
 const D=x=>new Date(x+"T00:00:00");
 if(A.period==="lastMonth"){const d=D(f);return {from:dk(new Date(d.getFullYear(),d.getMonth()-1,1)),to:dk(new Date(d.getFullYear(),d.getMonth(),0))}}
 if(A.period==="thisMonth"){const d=D(f),e=D(t),last=new Date(d.getFullYear(),d.getMonth(),0).getDate();return {from:dk(new Date(d.getFullYear(),d.getMonth()-1,1)),to:dk(new Date(d.getFullYear(),d.getMonth()-1,Math.min(e.getDate(),last)))}}
 const n=Math.round((D(t)-D(f))/864e5)+1,pt=D(f);pt.setDate(pt.getDate()-1);const pf=new Date(pt);pf.setDate(pf.getDate()-(n-1));return {from:dk(pf),to:dk(pt)};
}
function days(f,t){const out=[],d=new Date(f+"T00:00:00"),e=new Date(t+"T00:00:00");while(d<=e){out.push(dk(d));d.setDate(d.getDate()+1)}return out}
function unitOf(x){return String(x?.unit||"").trim()||(qrIsLargeContainer?.(x?.container_type)?"基":"ケース")}
function addQty(o,u,q){o[u]=(o[u]||0)+Number(q||0)}
function qtyText(o){const e=Object.entries(o||{}).filter(([,v])=>v);return e.length?e.map(([u,v])=>`${n1(v)}${u}`).join("・"):"—"}
function outKg(m,lot){if(m.weight!==null&&m.weight!==undefined&&m.weight!=="")return Number(m.weight);try{const k=lot?v163LotKgAtQuantity(lot,Number(m.qty||0)):0;return k>0?k:null}catch(e){return null}}
async function load(){
 const {from,to}=range(),key=from+"|"+to;if(A.data&&A.key===key)return A.data;
 const [lots,moves]=await Promise.all([v163SelectAll("qr_lots","select=*&order=qr_key.asc"),v163SelectAll("qr_lot_movements","select=*&order=created_at.asc")]);
 const byKey=new Map;for(const l of lots)for(const k of [l.qr_key,l.id,l.lot_no].filter(Boolean))byKey.set(String(k),l);
 const movesByLot=new Map;for(const m of moves){const l=byKey.get(String(m.qr_key||m.lot_id||m.lot_no||""));if(!l)continue;if(!movesByLot.has(l.id))movesByLot.set(l.id,[]);movesByLot.get(l.id).push(m)}
 const ds=days(from,to),stock={};
 const nameOf=l=>{try{const r=qrResolveInventoryItem(l);if(r?.item)return r.item.name}catch(e){}return String(l.item_name||"").trim()};
 for(const l of lots){
  const lm=movesByLot.get(l.id)||[],name=nameOf(l);
  for(const d of ds){let s=null;try{s=v1101LotSnapshotAtDayEnd(l,lm,d)}catch(e){}if(!s||!(s.qty>0))continue;
   const row=stock[name]=stock[name]||{name,qr:{},qrQty:{},unknown:{}};let kg=0;try{kg=v163LotKgAtQuantity(l,s.qty)}catch(e){}
   if(kg>0)row.qr[d]=(row.qr[d]||0)+kg;else row.unknown[d]=(row.unknown[d]||0)+1;
   row.qrQty[d]=row.qrQty[d]||{};addQty(row.qrQty[d],unitOf(l),s.qty)}
 }
 const normal={};for(const r of (db.records||[])){if(!r.createdAt||!r.itemId)continue;const d=jstDay(r.createdAt);if(d<from||d>to)continue;const it=(db.items||[]).find(x=>x.id===r.itemId);const name=it?.name||r.itemName||"";if(!name)continue;const o=normal[name]=normal[name]||{id:r.itemId,days:{}};const prev=o.days[d];if(!prev||new Date(r.createdAt)>=new Date(prev.at))o.days[d]={v:Number(r.total||0),at:r.createdAt}}
 const names=[...new Set([...(db.items||[]).filter(i=>i.active!==false).map(i=>i.name),...Object.keys(stock)])].filter(Boolean);
 const pr=prevRange(from,to),mkOuts=(from,to)=>{const outs=[];for(const m of moves){if(m.movement_type!=="出庫"||m.cancelled_at)continue;const dest=String(m.destination||"").trim()||"（出庫先なし）";if(dest==="廃棄")continue;const d=jstDay(m.occurred_at||m.created_at);if(d<from||d>to)continue;const l=byKey.get(String(m.qr_key||m.lot_id||m.lot_no||""));const name=l?nameOf(l):String(m.item_name||"");outs.push({d,dest,name,lot:m.lot_no||l?.lot_no||"",unit:unitOf(m.unit?m:l||m),qty:Number(m.qty||0),kg:outKg(m,l),user:m.user_name||""})}return outs};
 const outs=mkOuts(from,to),prevOuts=mkOuts(pr.from,pr.to);
 const first=moves.map(m=>jstDay(m.occurred_at||m.created_at)).filter(Boolean).sort()[0]||"",prevHas=!!first&&first<=pr.from;
 A.data={from,to,ds,stock,normal,names,outs,prevOuts,prevFrom:pr.from,prevTo:pr.to,prevHas};A.key=key;return A.data;
}
function stockSeries(data,name){
 const it=(db.items||[]).find(i=>i.name===name),set=it?db.settings?.[it.id]:null,q=data.stock[name]||{qr:{},qrQty:{},unknown:{}},nm=data.normal[name]?.days||{};
 return {it,min:set&&set.min!==undefined&&set.min!==""?Number(set.min):null,max:set&&set.max!==undefined&&set.max!==""?Number(set.max):null,
  rows:data.ds.map(d=>({d,normal:nm[d]?nm[d].v:null,qr:q.qr[d]||0,qrQty:q.qrQty[d]||{},unknown:q.unknown[d]||0,hasQr:!!(data.stock[name])}))};
}
function band(s){return s.min!=null&&s.max!=null}
function totOf(r){return r.normal==null&&!r.hasQr?null:(r.normal||0)+(r.qr||0)}
function stateOf(s,t){if(t==null||!band(s))return {t:"—",c:"#64748b"};if(t<s.min)return {t:"不足",c:"#2563eb"};if(t>s.max)return {t:"多い",c:"#dc2626"};return {t:"適正",c:"#15803d"}}
function outByDay(data,name){const o={};for(const r of data.outs)if(r.name===name&&r.kg!=null)o[r.d]=(o[r.d]||0)+r.kg;return o}
function chart(s,ob){
 const W=680,H=320,L=64,R=12,T=18,B=40,rows=s.rows;if(!rows.length)return"";
 const tot=rows.map(totOf),outs=rows.map(r=>ob[r.d]||0);
 const vals=[...tot.filter(v=>v!=null),...outs,s.min,s.max].filter(v=>v!=null&&Number.isFinite(v));const mx=Math.max(1,...vals)*1.1;
 const cw=(W-L-R)/rows.length,x=i=>L+cw*(i+.5),y=v=>T+(H-T-B)*(1-v/mx);
 const line=(arr,col,w,dash="")=>{let p="",on=false;arr.forEach((v,i)=>{if(v==null){on=false;return}p+=(on?"L":"M")+x(i).toFixed(1)+" "+y(v).toFixed(1)+" ";on=true});return p?`<path d="${p}" fill="none" stroke="${col}" stroke-width="${w}" stroke-linejoin="round" ${dash?`stroke-dasharray="${dash}"`:""}/>`:""};
 const bandRect=band(s)?`<rect x="${L}" y="${y(s.max)}" width="${W-L-R}" height="${Math.max(1,y(s.min)-y(s.max))}" fill="#dcfce7"/><text x="${W-R-4}" y="${y(s.max)+15}" font-size="13" text-anchor="end" fill="#15803d" font-weight="700">適正在庫 ${n1(s.min)}〜${n1(s.max)}kg</text>`:"";
 const bw=Math.max(2,Math.min(22,cw*.6)),bars=outs.map((v,i)=>v>0?`<rect x="${(x(i)-bw/2).toFixed(1)}" y="${y(v).toFixed(1)}" width="${bw.toFixed(1)}" height="${(y(0)-y(v)).toFixed(1)}" fill="#fb923c" opacity=".75" rx="2"/>`:"").join("");
 const step=Math.max(1,Math.ceil(rows.length/7)),xl=rows.map((r,i)=>i%step&&i!==rows.length-1?"":`<text x="${x(i)}" y="${H-12}" font-size="14" text-anchor="middle" fill="#334155">${Number(r.d.slice(5,7))}/${Number(r.d.slice(8))}</text>`).join("");
 const yl=[0,.5,1].map(f=>{const v=mx/1.1*f;return `<line x1="${L}" x2="${W-R}" y1="${y(v)}" y2="${y(v)}" stroke="#e2e8f0"/><text x="${L-6}" y="${y(v)+5}" font-size="14" text-anchor="end" fill="#334155">${n1(v)}</text>`}).join("");
 const dots=tot.map((v,i)=>v==null?"":`<circle cx="${x(i).toFixed(1)}" cy="${y(v).toFixed(1)}" r="${rows.length>40?1.5:3}" fill="${stateOf(s,v).c}"/>`).join("");
 return `<svg viewBox="0 0 ${W} ${H}" style="width:100%;height:auto;background:#fff;border-radius:10px">${bandRect}${yl}${bars}${s.rows.some(r=>r.hasQr)&&s.rows.some(r=>r.normal!=null)?line(rows.map(r=>r.hasQr?r.qr:null),"#64748b",2,"5 4"):""}${line(tot,"#0f766e",3.5)}${dots}${xl}</svg>
 <div style="margin-top:6px;font-size:14px;font-weight:700;line-height:1.7"><span style="color:#0f766e">━ 在庫（合計kg）</span>　<span style="color:#ea580c">▮ その日の出庫kg</span>　<span style="color:#15803d">■ 適正在庫の範囲</span>${s.rows.some(r=>r.hasQr)&&s.rows.some(r=>r.normal!=null)?`　<span style="color:#64748b">┅ うちQR在庫</span>`:""}</div>`;
}
function spark(s,tots){
 const W=120,H=36,v=tots.map((t,i)=>[i,t]).filter(([,t])=>t!=null);if(!v.length)return"";
 const mx=Math.max(1,...v.map(a=>a[1]),s.max||0)*1.1,x=i=>tots.length<2?W/2:i*(W-4)/(tots.length-1)+2,y=t=>H-2-(H-4)*t/mx;
 return `<svg viewBox="0 0 ${W} ${H}" width="${W}" height="${H}">${band(s)?`<rect x="0" y="${y(s.max)}" width="${W}" height="${Math.max(1,y(s.min)-y(s.max))}" fill="#dcfce7"/>`:""}<path d="${v.map(([i,t],k)=>(k?"L":"M")+x(i).toFixed(1)+" "+y(t).toFixed(1)).join(" ")}" fill="none" stroke="#0f766e" stroke-width="2"/></svg>`;
}
function stockListHtml(data){
 const list=data.names.map(n=>{const s=stockSeries(data,n),tots=s.rows.map(totOf),val=tots.filter(t=>t!=null);if(!val.length)return null;
  return {n,s,tots,latest:val[val.length-1],avg:val.reduce((a,b)=>a+b,0)/val.length,under:band(s)?val.filter(t=>t<s.min).length:0,over:band(s)?val.filter(t=>t>s.max).length:0}}).filter(Boolean)
  .sort((a,b)=>(b.under+b.over)-(a.under+a.over)||a.n.localeCompare(b.n,"ja"));
 if(!list.length)return '<div class="notice">この期間に在庫の記録がある品目はありません。</div>';
 return `<div class="small" style="margin:2px 0 8px">${list.length}品目。適正在庫から外れた日が多い品目ほど上に出ます。品目を押すと、グラフと日ごとの在庫が見られます。</div>`+list.map(r=>{const st=stateOf(r.s,r.latest);return `<button class="c81Row" ${seikaEventAttrs("click","c81OpenItem",[r.n])}><div style="flex:1;min-width:0;text-align:left"><div style="font-size:18px;font-weight:900">${esc(r.n)}</div><div style="font-size:15px;margin-top:2px">最新 <b style="font-size:18px">${n1(r.latest)}kg</b> <span style="color:${st.c};font-weight:800">${st.t==="—"?"":st.t}</span></div><div class="small">平均 ${n1(r.avg)}kg${band(r.s)?`　${r.under?`<span style="color:#2563eb;font-weight:800">不足 ${r.under}日</span>　`:""}${r.over?`<span style="color:#dc2626;font-weight:800">多い ${r.over}日</span>`:""}${!r.under&&!r.over?'<span style="color:#15803d;font-weight:800">ずっと適正</span>':""}`:"　適正在庫 未設定"}</div></div><div>${spark(r.s,r.tots)}</div></button>`}).join("");
}
function stockDetailHtml(data){
 const names=data.names.slice().sort((a,b)=>a.localeCompare(b,"ja"));
 const s=stockSeries(data,A.item),ob=outByDay(data,A.item);
 const sel=`<button class="btn btn2" style="width:100%;min-height:44px" ${seikaEventAttrs("click","c81OpenItem",[""])}>← 品目の一覧へ戻る</button><label class="label" style="margin-top:8px">品目</label><select class="input" ${seikaEventAttrs("change","c81OpenItem",[{__seikaValue:true}])}>${names.map(n=>`<option ${n===A.item?"selected":""}>${esc(n)}</option>`).join("")}</select>`;
 const days=s.rows.slice().reverse().map(r=>{const t=totOf(r),st=stateOf(s,t),o=ob[r.d];return `<details class="c81Day"><summary><span>${Number(r.d.slice(5,7))}/${Number(r.d.slice(8))}（${"日月火水木金土"[new Date(r.d+"T00:00:00").getDay()]}）</span><b>${t==null?"—":n1(t)+"kg"}</b><span style="color:${st.c};font-weight:900">${st.t}</span></summary><div class="small" style="padding:4px 0 8px">通常在庫（入力）：${r.normal==null?"入力なし":n1(r.normal)+"kg"} ／ QR在庫：${r.hasQr?`${n1(r.qr)}kg（${qtyText(r.qrQty)}）`:"なし"}${r.unknown?` ／ <span style="color:#b45309">ほか${r.unknown}ロット kg不明</span>`:""} ／ この日の出庫：${o?n1(o)+"kg":"なし"}</div></details>`}).join("");
 return `${sel}<div style="margin-top:12px">${chart(s,ob)}</div><div class="small" style="margin-top:6px">適正在庫：${band(s)?`${n1(s.min)}〜${n1(s.max)}kg`:"未設定"}。点の色は、青＝不足・緑＝適正・赤＝多いです。通常在庫は入力した日だけ数えます。</div><div style="margin-top:10px"><div class="c81DayHead"><span>日付</span><span>合計kg</span><span>状態</span></div>${days}</div><div class="small" style="margin-top:4px">日付を押すと、通常在庫とQR在庫の内訳・その日の出庫が開きます。</div>`;
}
function stockHtml(data){if(A.item&&!data.names.includes(A.item))A.item="";return A.item?stockDetailHtml(data):stockListHtml(data)}
function sumBy(rows,k1,k2){const m={};for(const r of rows){const a=m[r[k1]]=m[r[k1]]||{q:{},kg:0,unk:0,n:0,sub:{}};addQty(a.q,r.unit,r.qty);if(r.kg!=null)a.kg+=r.kg;else a.unk++;a.n++;const b=a.sub[r[k2]]=a.sub[r[k2]]||{q:{},kg:0,unk:0,n:0};addQty(b.q,r.unit,r.qty);if(r.kg!=null)b.kg+=r.kg;else b.unk++;b.n++}return m}
function diffHtml(data,cur,prev){
 if(!data.prevHas)return '<span class="small">比較なし</span>';
 if(!prev)return cur>0?'<span style="color:#b45309;font-weight:800;font-size:14px">前の期間 0</span>':"";
 const p=Math.round((cur-prev)/prev*100);if(p===0)return '<span style="color:#475569;font-weight:800;font-size:14px">→ 前と同じ</span>';
 return `<span style="color:${p>0?"#b45309":"#2563eb"};font-weight:900;font-size:14px">${p>0?"↑":"↓"}${Math.abs(p)}%</span>`;
}
function bar(w,col){return `<div style="height:10px;background:#f1f5f9;border-radius:6px;margin-top:6px;overflow:hidden"><div style="height:100%;width:${Math.max(1,Math.min(100,w)).toFixed(1)}%;background:${col};border-radius:6px"></div></div>`}
function outHtml(data,by){
 const k1=by==="dest"?"dest":"name",k2=by==="dest"?"name":"dest",m=sumBy(data.outs,k1,k2),pm=sumBy(data.prevOuts,k1,k2);
 const seg=`<div class="c81Seg">${[["dest","出庫先別"],["item","品目別"]].map(([k,l])=>`<button class="${A.by===k?"on":""}" ${seikaEventAttrs("click","c81SetBy",[k])}>${l}</button>`).join("")}</div>`;
 const filt=by==="item"?`<input class="input" style="margin-top:8px" placeholder="品目名で絞り込み" value="${esc(A.q)}" ${seikaEventAttrs("change","c81SetQ",[{__seikaValue:true}])}>`:"";
 const total=data.outs.reduce((s,r)=>s+(r.kg||0),0),ptotal=data.prevOuts.reduce((s,r)=>s+(r.kg||0),0);
 let keys=Object.keys(m).sort((a,b)=>m[b].kg-m[a].kg);if(by==="item"&&A.q)keys=keys.filter(k=>k.includes(A.q));
 const head=`${seg}${filt}<div style="margin:10px 0 8px"><div style="font-size:15px;font-weight:800">この期間の出庫 合計</div><div><b style="font-size:26px">${n1(total)}kg</b>　${diffHtml(data,total,ptotal)}</div><div class="small">${data.outs.length}件。${data.prevHas?`比べた期間：${esc(data.prevFrom)}〜${esc(data.prevTo)}（${n1(ptotal)}kg）。`:"前の期間はQRの記録がないため比べられません。"}取り消した出庫と廃棄は入りません。</div></div>`;
 if(!keys.length)return head+`<div class="notice">${data.outs.length?"該当する品目はありません。":"この期間の出庫はありません。"}</div>`;
 const top=Math.max(...keys.map(k=>m[k].kg),1);
 return head+keys.map((k,i)=>{const a=m[k],subs=Object.keys(a.sub).sort((x,y)=>a.sub[y].kg-a.sub[x].kg),sb=Math.max(...subs.map(s=>a.sub[s].kg),1);
  return `<details class="card c81Rank"><summary><div style="display:flex;align-items:baseline;gap:8px;flex-wrap:wrap"><span style="color:#64748b;font-weight:900">${i+1}</span><b style="font-size:19px">${esc(k)}</b><span style="margin-left:auto;white-space:nowrap"><b style="font-size:20px">${n1(a.kg)}kg</b> <span class="small">${total?Math.round(a.kg/total*100):0}%</span></span></div>${bar(a.kg/top*100,"#ea580c")}<div style="display:flex;gap:8px;align-items:center;margin-top:4px"><span class="small" style="flex:1">${qtyText(a.q)}・${a.n}件${a.unk?`（kg不明${a.unk}件）`:""}</span>${diffHtml(data,a.kg,pm[k]?.kg||0)}</div></summary>
  <div style="margin-top:8px;border-top:1px solid #e2e8f0;padding-top:6px">${subs.map(s=>{const b=a.sub[s];return `<div style="padding:6px 0;border-bottom:1px solid #f1f5f9"><div style="display:flex;gap:8px"><span style="flex:1;font-weight:700">${esc(s)}</span><b style="white-space:nowrap">${n1(b.kg)}kg</b><span class="small" style="width:38px;text-align:right">${a.kg?Math.round(b.kg/a.kg*100):0}%</span></div>${bar(b.kg/sb*100,"#fdba74")}<div class="small">${qtyText(b.q)}${b.unk?`・kg不明${b.unk}件`:""}</div></div>`}).join("")}</div></details>`}).join("");
}
async function c81AnalysisPage(tab){
 if(["hq_prep","hq_receiver"].includes(db?.role))return hqHome("この権限では在庫・出庫の分析を利用できません。");
 if(tab==="dest"||tab==="item"){A.by=tab;tab="out"}if(tab)A.tab=tab;setScreen("c81AnalysisPage",[A.tab]);const {from,to}=range();
 const P=[["thisMonth","今月"],["lastMonth","先月"],["3months","過去3か月"],["fiscal","年度（9月〜）"],["custom","自由に指定"]];
 const T=[["stock","在庫推移"],["out","出庫数量"]];
 pageShell("在庫・出庫の分析","品目ごとの在庫の動きと、どこへ何を出したかを見ます",`<div class="card"><div class="c81Tabs">${T.map(([k,l])=>`<button class="${A.tab===k?"on":""}" ${seikaEventAttrs("click","c81AnalysisPage",[k])}>${l}</button>`).join("")}</div><div class="label" style="margin-top:10px">期間</div><div class="c81Seg">${P.map(([k,l])=>`<button class="${A.period===k?"on":""}" ${seikaEventAttrs("click","c81SetPeriod",[k])}>${l}</button>`).join("")}</div>${A.period==="custom"?`<div class="grid" style="margin-top:8px"><div><label class="label">から</label><input id="c81From" class="input" type="date" value="${esc(from)}" ${seikaEventAttrs("change","c81SetCustom",[])}></div><div><label class="label">まで</label><input id="c81To" class="input" type="date" value="${esc(to)}" ${seikaEventAttrs("change","c81SetCustom",[])}></div></div>`:""}<div class="small" style="margin-top:6px">${esc(from)} 〜 ${esc(to)}</div>
 <button class="btn homeBtnAnalysis" style="width:100%;margin-top:10px;min-height:48px" ${seikaEventAttrs("click","c81Excel",[])}>この期間をExcelにする</button></div><div id="c81Body" class="card"><div class="notice">読み込んでいます…</div></div>`);
 try{const data=await load();const b=document.getElementById("c81Body");if(!b)return;b.innerHTML=A.tab==="stock"?stockHtml(data):outHtml(data,A.by)}
 catch(e){const b=document.getElementById("c81Body");if(b)b.innerHTML=`<div class="err">読み込めませんでした。${esc(e.message||e)}</div>`}
}
function c81SetPeriod(k){A.period=k;A.data=null;return c81AnalysisPage()}
function c81SetCustom(){A.from=document.getElementById("c81From")?.value||"";A.to=document.getElementById("c81To")?.value||"";A.data=null;return c81AnalysisPage()}
function c81SetItem(v){A.item=v;return c81AnalysisPage("stock")}
function c81OpenItem(v){A.item=v||"";const r=c81AnalysisPage("stock");window.scrollTo?.(0,0);return r}
function c81SetBy(k){A.by=k;return c81AnalysisPage("out")}
function c81SetQ(v){A.q=String(v||"").trim();return c81AnalysisPage("out")}
async function c81Excel(){
 if(["hq_prep","hq_receiver"].includes(db?.role))return hqHome("この権限では在庫・出庫の分析を利用できません。");
 try{const data=await load(),wb=XLSX.utils.book_new(),add=(name,aoa)=>{const ws=XLSX.utils.aoa_to_sheet(aoa);ws["!cols"]=aoa[0].map((_,i)=>({wch:i?12:18}));XLSX.utils.book_append_sheet(wb,ws,name)};
  const names=data.names.slice().sort((a,b)=>a.localeCompare(b,"ja")),hd=["品目","区分","適正在庫 下限","上限",...data.ds];
  const st=[hd];for(const n of names){const s=stockSeries(data,n);if(!s.rows.some(r=>r.normal!=null||r.hasQr))continue;st.push([n,"合計kg",s.min,s.max,...s.rows.map(r=>r.normal==null&&!r.hasQr?"":Math.round(((r.normal||0)+(r.qr||0))*10)/10)]);if(data.normal[n])st.push([n,"通常在庫（入力kg）","","",...s.rows.map(r=>r.normal==null?"":r.normal)]);if(data.stock[n])st.push([n,"QR在庫kg","","",...s.rows.map(r=>Math.round(r.qr*10)/10)])}
  add("在庫推移",st);
  for(const [by,label,k1,k2] of [["dest","出庫先別","dest","name"],["item","品目別","name","dest"]]){const m=sumBy(data.outs,k1,k2),aoa=[[by==="dest"?"出庫先":"品目",by==="dest"?"品目":"出庫先","kg","数量","件数","kg不明の件数"]];for(const k of Object.keys(m).sort((a,b)=>m[b].kg-m[a].kg)){const a=m[k];aoa.push([k,"（合計）",Math.round(a.kg*10)/10,qtyText(a.q),a.n,a.unk]);for(const s of Object.keys(a.sub).sort((x,y)=>a.sub[y].kg-a.sub[x].kg)){const b=a.sub[s];aoa.push([k,s,Math.round(b.kg*10)/10,qtyText(b.q),b.n,b.unk])}}add("出庫_"+label,aoa)}
  add("出庫明細",[["出庫日","出庫先","品目","ロット番号","数量","単位","kg","出庫した人"],...data.outs.map(r=>[r.d,r.dest,r.name,r.lot,r.qty,r.unit,r.kg==null?"":Math.round(r.kg*10)/10,r.user])]);
  downloadWorkbookXlsx(wb,`在庫・出庫の分析_${data.from}_${data.to}.xlsx`);
 }catch(e){alert("Excelを作れませんでした："+(e.message||e))}
}
Object.assign(window,{c81AnalysisPage,c81SetPeriod,c81SetCustom,c81SetItem,c81OpenItem,c81SetBy,c81SetQ,c81Excel});
const css=document.createElement("style");css.textContent=".c81Tabs{display:flex;gap:8px}.c81Tabs button{flex:1;min-height:50px;border-radius:14px;border:2px solid #cbd5e1;background:#f1f5f9;color:#1e293b;font-size:18px;font-weight:900}.c81Tabs button.on{background:#1e3a8a;border-color:#1e3a8a;color:#fff}.c81Seg{display:flex;flex-wrap:wrap;gap:6px;margin-top:4px}.c81Seg button{flex:1 1 auto;min-height:40px;padding:6px 12px;border-radius:999px;border:1.5px solid #cbd5e1;background:#fff;color:#1e293b;font-size:15px;font-weight:800;white-space:nowrap}.c81Seg button.on{background:#0f766e;border-color:#0f766e;color:#fff}.c81Row{display:flex;align-items:center;gap:10px;width:100%;padding:12px;margin-top:8px;border:1.5px solid #e2e8f0;border-radius:14px;background:#fff;color:#0f172a;font:inherit}.c81Rank{padding:12px 14px!important;margin-top:8px}.c81Rank summary{list-style:none;cursor:pointer}.c81Rank summary::-webkit-details-marker{display:none}.c81DayHead,.c81Day summary{display:grid;grid-template-columns:1.3fr 1.2fr .8fr;gap:6px;align-items:center}.c81DayHead{font-size:13px;font-weight:800;color:#475569;padding:0 4px 4px;border-bottom:2px solid #cbd5e1}.c81Day summary{list-style:none;padding:9px 4px;border-bottom:1px solid #e2e8f0;font-size:16px;cursor:pointer}.c81Day summary::-webkit-details-marker{display:none}.c81Day summary b{text-align:right}.c81Day summary span:last-child{text-align:center}.homeBtnAnalysis{background:linear-gradient(90deg,#431407 0%,#9a3412 52%,#ea580c 100%) !important;color:#fff !important;text-shadow:0 1px 2px rgba(0,0,0,.35);border-color:transparent !important}";document.head.appendChild(css);
function addHomeBtn(){
 if(["hq_prep","hq_receiver"].includes(db?.role)||typeof currentScreen!=="string"||currentScreen!=="home"||document.getElementById("c81HomeBtn"))return;
 const anchors=["purchasePricesPage","wasteManagementPage","lineCopyPage","inventoryManagementPage","qrHome"];let a=null;
 for(const k of anchors){a=document.querySelector(`#app button[data-seika-click-action="${k}"]`);if(a)break}
 const b=document.createElement("button");b.id="c81HomeBtn";b.className="btn homeBtnAnalysis";b.setAttribute("data-seika-click-action","c81AnalysisPage");b.setAttribute("data-seika-click-args","%5B%5D");b.setAttribute("data-c73","1");
 b.innerHTML='在庫・出庫の分析<br><span style="font-size:15px;font-weight:800">品目ごとの在庫推移・出庫先別／品目別の出庫</span>';
 if(a){if(a.className)b.style.cssText=a.style.cssText;a.insertAdjacentElement("afterend",b)}else{const c=document.querySelector("#app .card");if(c)c.appendChild(b)}
}
const app=document.getElementById("app");if(app)new MutationObserver(addHomeBtn).observe(app,{childList:true,subtree:true});
try{const sec={title:"在庫・出庫の分析を見る",where:"ホーム →「在庫・出庫の分析」",
 steps:["上の「在庫推移」「出庫数量」を選び、期間を「今月・先月・過去3か月・年度（9月〜）・自由に指定」から選びます。","「在庫推移」：全品目の一覧に、最新の在庫・平均・適正在庫を下回った日数（不足）と上回った日数（多い）・小さなグラフが出ます。外れた日が多い品目ほど上に出ます。","品目を押すと、在庫の折れ線グラフ（合計kg＝通常在庫の入力kg＋QR在庫kg）と、その日の出庫kgの棒が出ます。薄い緑の帯が適正在庫の範囲です。下の表は日付・合計kg・状態（不足・適正・多い）で、日付を押すと内訳が開きます。","「出庫数量」：「出庫先別」「品目別」を切り替えると、多い順に横棒と全体の割合が出ます。行を押すと内訳が開きます。品目別は品目名で絞り込めます。","↑↓の％は、前の期間（先月なら前々月、今月なら先月の同じ日まで、ほかは同じ日数だけ前）との比較です。前の期間にQRの記録がないときは「比較なし」と出ます。","「この期間をExcelにする」で、在庫推移・出庫先別・品目別・出庫明細をExcelにできます。"],
 check:"出庫はQR品目だけです（通常在庫の品目は出庫の記録がないため）。取り消した出庫と廃棄は入りません。量目が分からないロットはkgに入らず「kg不明」の件数で出ます。",
 caution:"通常在庫は入力した日の数だけです。アプリに残っている通常在庫の記録は約90日分です。"};
 if(typeof V198_GUIDE_SECTIONS!=="undefined")V198_GUIDE_SECTIONS.c81Analysis=sec;
 if(typeof V195_ROLE_GUIDES!=="undefined")for(const r of Object.keys(V195_ROLE_GUIDES)){if(["hq_prep","hq_receiver"].includes(r))continue;const g=V195_ROLE_GUIDES[r];if(g&&Array.isArray(g.sections)&&!g.sections.some(x=>x.title===sec.title))g.sections.push(sec)}
}catch(e){}
})();
