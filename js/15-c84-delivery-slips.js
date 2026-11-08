
/* ===== v1.199-c84 伝票発行（埼玉・深谷・本社） =====
   選んだ日のQR出庫（取消を除く）から、埼玉・深谷は1枚、本社は便ごとに1枚の伝票（A4横・左が納品書、右が請求書）を作る。
   納品書側の各行に小さなQR（読むとロット画面）。手書き用の空き行3行。伝票Excel・月の一覧Excelも出力。保存はしない（SQLなし）。 */
(()=>{
const C84_TO={"埼玉":"㈱せき　埼玉工場","深谷":"㈱せき　深谷青果センター","本社":"㈱せき　本社工場"};
const C84_FROM="㈱せき　石岡営業所",C84_ADDR="〒315-0073<br>茨城県かすみがうら市西野寺730-17<br>TEL　0299-23-0997<br>FAX　0299-35-8181";
const C84_BIG=["網コンテナ","鉄コンテナ","パレテーナ"],C84_ROWS=12,C84_BLANK=3;
const C84_RUNS_DEFAULT=["配送便","原料便","市場便"];
let c84Tickets=[],c84Date="",c84Url="",c84Busy=false;
const C84_SUN=["日曜積込分","日曜積込分・先送り"];
function c84Dow(d){return new Date(String(d).slice(0,10)+"T00:00:00").getDay()}
function c84Can(){return["admin","worker","clerk"].includes(String(db?.role||""))}
function c84Add(d,n){const t=new Date(String(d).slice(0,10)+"T00:00:00");t.setDate(t.getDate()+n);return ymdKey(t)}
function c84Md(d){if(!d)return"";const t=new Date(String(d).slice(0,10)+"T00:00:00");return `${t.getMonth()+1}/${t.getDate()}`}
function c84Jp(d){if(!d)return"";const t=new Date(String(d).slice(0,10)+"T00:00:00");return `${t.getFullYear()}年${t.getMonth()+1}月${t.getDate()}日（${"日月火水木金土"[t.getDay()]}）`}
function c84Num(v){const n=Math.round(Number(v)*10)/10;return Number.isFinite(n)?n.toLocaleString("ja-JP"):""}
function c84Pack(p){const s=String(p??"").trim().replace(/[０-９．]/g,c=>String.fromCharCode(c.charCodeAt(0)-0xFEE0));if(!s)return"";const m=s.match(/^([0-9.]+)\s*(kg|㎏|ｋｇ|キロ)?$/i);return m?`${m[1]}kg`:s}
function c84RunOrder(){const r=Array.isArray(db.c50ShipRuns)&&db.c50ShipRuns.length?db.c50ShipRuns.map(x=>x&&x.name).filter(Boolean):C84_RUNS_DEFAULT;return r}
async function c84In(table,cols,key,ids){const out=[];const u=[...new Set(ids.filter(Boolean).map(String))];for(let i=0;i<u.length;i+=80){const part=u.slice(i,i+80).map(encodeURIComponent).join(",");out.push(...(await qrSelect(table,`select=${cols}&${key}=in.(${part})`)||[]))}return out}
async function c84LoadDay(date,cache){
 if(cache&&cache.has(date))return cache.get(date);
 if(date>todayKey()){cache?.set(date,[]);return[]}
 const p=c84LoadDay0(date);cache?.set(date,p);return p;
}
async function c84LoadDay0(date){
 const rows=[];let offset=0,total=Infinity;
 while(offset<total){const a=await callRpc("list_qr_outbound_history_v1144",{p_destination:null,p_work_date:date,p_include_cancelled:false,p_limit:500,p_offset:offset});const page=Array.isArray(a?.rows)?a.rows:[];total=Number(a?.total_count||0);rows.push(...page);offset+=page.length;if(!page.length)break}
 const list=rows.filter(r=>!r.is_cancelled&&C84_TO[String(r.destination||"")]);
 if(!list.length)return[];
 const mv=new Map((await c84In("qr_lot_movements","id,lot_id,origin,supplier,cooperative_name,operation_meta,weight","id",list.map(r=>r.id))).map(m=>[String(m.id),m]));
 const lots=new Map((await c84In("qr_lots","id,qr_key,received_date,origin,supplier,cooperative_name,total_weight,received_qty,pack_weight","id",[...mv.values()].map(m=>m.lot_id))).map(l=>[String(l.id),l]));
 let adj=new Map();try{adj=new Map((await c84In("qr_slip_adjust_v1199c86","movement_id,total_kg,pack","movement_id",list.map(r=>r.id))).map(a=>[String(a.movement_id),a]))}catch(e){}
 let hq=new Map();
 const hqIds=list.filter(r=>r.destination==="本社").map(r=>r.id);
 if(hqIds.length){try{hq=new Map((await c84In("hq_lots_v1400","source_movement_id,measured_total_kg,measured_count,planned_qty,planned_count,unit,planned_date","source_movement_id",hqIds)).map(h=>[String(h.source_movement_id),h]))}catch(e){}}
 return list.map(r=>{
  const m=mv.get(String(r.id))||{},l=lots.get(String(m.lot_id||""))||{},h=hq.get(String(r.id)),ship=(m.operation_meta&&typeof m.operation_meta==="object"&&m.operation_meta.hqShip)||{};
  const a=adj.get(String(r.id))||{},sm=(m.operation_meta&&typeof m.operation_meta==="object"&&m.operation_meta.slip)||{};
  const big=C84_BIG.includes(String(r.container_type||""));let kg=null,count=null,kgSet=false;
  if(big){count=Number(r.qty||0);
   const set=Number(a.total_kg)>0?Number(a.total_kg):Number(sm.kg)>0?Number(sm.kg):null;if(set!==null){kg=set;kgSet=true}
   if(kg===null)
{if(h&&h.unit==="kg"){kg=Number(h.measured_total_kg)>0?Number(h.measured_total_kg):Number(h.planned_qty)>0?Number(h.planned_qty):null;if(Number(h.measured_count)>0)count=Number(h.measured_count)}}
   if(kg===null&&r.weight!=null&&r.weight!=="")kg=Number(r.weight);
   if(kg===null&&Number(l.total_weight)>0&&Number(l.received_qty)>0)kg=Math.round(Number(l.total_weight)/Number(l.received_qty)*count*10)/10}
  return{id:r.id,dest:r.destination,date,occurred:r.occurred_at,timing:v1144OutboundMemoParts(r.memo).timing,lotKey:String(m.lot_id||r.qr_key||r.lot_no||r.id),lot_no:r.lot_no||"",qr_key:r.qr_key||l.qr_key||"",
   item:r.item_name||"",coop:m.cooperative_name||l.cooperative_name||"",supplier:m.supplier||l.supplier||"",origin:m.origin||l.origin||"",received:l.received_date||"",pack:c84Pack(a.pack||sm.pack||(r.pack_weight??l.pack_weight)),packSet:!!(a.pack||sm.pack),
   big,count,kg,kgSet,qty:Number(r.qty||0),unit:r.unit||"",run:String(ship.run||"").trim(),runTime:String(ship.time||"").trim(),day:String(ship.day||"").trim(),hqDate:h?.planned_date||""}
 });
}
async function c84Collect(slip,cache){
 const prev=c84Add(slip,-1),prev2=c84Add(slip,-2);
 const [d0,d1,d2]=await Promise.all([c84LoadDay(slip,cache),c84LoadDay(prev,cache),c84Dow(prev2)===6?c84LoadDay(prev2,cache):Promise.resolve([])]);
 const hqDate=x=>x.hqDate||c84Add(x.date,x.day==="翌日便"?1:0);
 const out=[];
 for(const x of d1)if(x.dest!=="本社"&&!C84_SUN.includes(x.timing))out.push(x);
 for(const x of d2)if(x.dest!=="本社"&&C84_SUN.includes(x.timing))out.push(x);
 for(const x of [...d1,...d0])if(x.dest==="本社"&&hqDate(x)===slip)out.push(x);
 return out;
}
function c84Build(items,date){
 const map=new Map;
 for(const x of items){
  const hqRun=x.dest==="本社"?(x.run||"便の記録なし"):"";
  const tk=x.dest==="本社"?`本社|${hqRun}`:x.dest;
  let t=map.get(tk);
  if(!t){t={key:tk,dest:x.dest,run:hqRun,runTime:x.runTime,date,lines:new Map};map.set(tk,t)}
  const fwd=x.dest!=="本社"&&(x.timing==="翌日分先送り"||x.timing==="日曜積込分・先送り"),lk=`${fwd?1:0}|${x.date}|${x.lotKey}|${x.big?"":x.pack}`,party=x.coop||x.supplier||"";
  const g=t.lines.get(lk)||{fwd,ship:x.date,sun:C84_SUN.includes(x.timing),item:x.item,coop:x.coop,party,name:party?`${x.item}　${party}`:x.item,mv:[],hq:x.dest==="本社",day:x.day,origin:x.origin,received:x.received,pack:x.pack,big:x.big,count:0,kg:0,kgOk:true,qty:0,unit:x.unit,qr_key:x.qr_key,lot_no:x.lot_no};
  g.mv.push({id:x.id,qty:x.qty,count:x.count,kg:x.kg,kgSet:x.kgSet,pack:x.pack,unit:x.unit});
  g.qty+=x.qty;if(x.big){g.count+=x.count||0;if(x.kg===null||!Number.isFinite(x.kg))g.kgOk=false;else g.kg+=x.kg}
  t.lines.set(lk,g);
 }
 const order=c84RunOrder(),dOrder=["埼玉","深谷","本社"];
 return [...map.values()].map(t=>c89Sort({...t,lines:[...t.lines.values()]})).sort((a,b)=>dOrder.indexOf(a.dest)-dOrder.indexOf(b.dest)||((order.indexOf(a.run)+99)%99)-((order.indexOf(b.run)+99)%99));
}
function c84Qr(payload){const q=qrcode(0,"M");q.addData(String(payload));q.make();return q.createDataURL(4,1)}
function c84Unit(u){return /^(ケース|ｃｓ|cs)$/i.test(String(u||"").trim())?"cs":String(u||"")}
function c84Title(t){return t.dest==="本社"?`本社工場　${t.run}`:t.dest}
function c84Cells(g){return{pack:g.big?`${c84Num(g.count)}基`:g.pack,qty:g.big?(g.kgOk&&g.kg>0?c84Num(g.kg):""):c84Num(g.qty),unit:g.big?"kg":c84Unit(g.unit),received:c84Md(g.received)}}
const C89_PER=15,C89_KEEP=2;
const C89_ORDER={
 "埼玉":[["さつま芋","さつま"],["南瓜"],["キャベツ"],["白菜"],["カット大根","大根"],["人参"],["胡瓜"],["ピーマン"],["赤パプリカ"],["黄パプリカ"],["長葱"],["水菜"],["小松菜"],["茄子"],["青梗菜","チンゲン菜"],["ゴーヤ"],["小葱"],["牛蒡","ごぼう"],["ニラ"],["大葉"]],
 "深谷":[["レタス"],["キャベツ"],["紫キャベツ"],["水菜"],["胡瓜"],["小松菜"],["小葱"],["ミニトマト"],["サニーレタス","サニー"],["カット大根","大根"],["葉付大根"],["長葱"],["トマト"],["人参"],["グリーンリーフ","リーフ"],["蓮根","レンコン","れんこん"],["大葉"]]
};
function c89Norm(v){return String(v||"").replace(/[（(][^）)]*[）)]/g,"").replace(/[\s　]/g,"").trim()}
function c89Rank(dest,item){
 const list=C89_ORDER[dest];if(!list)return 999;const n=c89Norm(item);let best=999,len=0;
 list.forEach((al,i)=>al.forEach(a=>{const x=c89Norm(a);if(n===x){if(len<1000){best=i;len=1000}}else if(len<1000&&(n.startsWith(x)||x.startsWith(n))&&x.length>len){best=i;len=x.length}}));
 return best;
}
function c89Sort(t){if(!C89_ORDER[t.dest])return t;const r=g=>c89Rank(t.dest,g.item);
 t.lines.sort((a,b)=>(a.fwd?1:0)-(b.fwd?1:0)||r(a)-r(b)||(r(a)===999?String(a.item).localeCompare(String(b.item),"ja"):0)||String(a.received||"").localeCompare(String(b.received||""))||String(a.party||"").localeCompare(String(b.party||""),"ja"));return t}
function c89Blank(n,keep){return Array.from({length:Math.max(0,n)},(_,k)=>({blank:true,keep:k<keep}))}
function c89Pages(t){
 const today=t.lines.filter(g=>!g.fwd),fwd=t.lines.filter(g=>g.fwd),head=`【${c84Md(c84Add(t.date,1))}　納品分　先送り】`;
 const total=today.length+C89_KEEP+(fwd.length?fwd.length+1:0);
 if(total<=C89_PER){
  const ent=today.length||!fwd.length?[...today.map(g=>({g})),...c89Blank(C89_KEEP,C89_KEEP)]:[];
  if(fwd.length)ent.push({head},...fwd.map(g=>({g})));
  if(!today.length&&fwd.length)ent.push(...c89Blank(C89_KEEP,C89_KEEP));
  ent.push(...c89Blank(C89_PER-ent.length,0));return [ent];
 }
 const pages=[],cap=C89_PER-C89_KEEP;
 for(let i=0;i<today.length;i+=cap){const ent=[...today.slice(i,i+cap).map(g=>({g})),...c89Blank(C89_KEEP,C89_KEEP)];ent.push(...c89Blank(C89_PER-ent.length,0));pages.push(ent)}
 for(let i=0;i<fwd.length;i+=C89_PER-1){const ent=[{head:head+(i?"（続き）":"")},...fwd.slice(i,i+C89_PER-1).map(g=>({g}))];ent.push(...c89Blank(C89_PER-ent.length,0));pages.push(ent)}
 return pages;
}
function c89HqPages(t){const cap=C89_PER-C89_KEEP,ls=t.lines,pages=[];
 for(let i=0;i<Math.max(ls.length,1);i+=cap){const ent=[...ls.slice(i,i+cap).map(g=>({g})),...c89Blank(C89_KEEP,C89_KEEP)];ent.push(...c89Blank(C89_PER-ent.length,0));pages.push(ent)}return pages}
function c89HqHtml(t,ent,pi,pn){
 const rows=ent.map(e=>{if(e.blank)return `<tr class="b${e.keep?" keep":""}">${"<td></td>".repeat(8)}</tr>`;const g=e.g,c=c84Cells(g);
  let img="";if(g.qr_key){try{img=`<img src="${c84Qr(location.origin+location.pathname+"?qr="+encodeURIComponent(g.qr_key))}">`}catch(_){}}
  return `<tr class="r"><td class="nm">${esc(g.item)}</td><td class="c">${esc(c.pack)}</td><td class="n">${esc(c.qty)}</td><td class="c u">${esc(c.unit)}</td><td class="og">${esc(g.origin||"")}${g.party?`<br><span>${esc(g.party)}</span>`:""}</td><td class="c">${esc(c.received)}</td><td></td><td class="q">${img}</td></tr>`}).join("");
 const last=pi===pn-1;
 return `<div class="half"><div class="hqtop"><div class="hqttl">納　品　書</div><span class="pg">${pn>1?`${pi+1} / ${pn}`:""}</span></div>
 <div class="top"><div><div class="dt" style="font-size:18px">${esc(c84Jp(t.date))}</div><div class="run" style="font-size:24px">${esc(t.run)}</div><div class="to">${esc(C84_TO[t.dest])}　御中</div></div><div class="from"><b>${esc(C84_FROM)}</b><div>${C84_ADDR}</div></div></div>
 <table><colgroup><col style="width:22%"><col style="width:9%"><col style="width:10%"><col style="width:5%"><col style="width:18%"><col style="width:8%"><col style="width:19%"><col style="width:9%"></colgroup>
 <tr class="th"><td>品　　名</td><td>入　数</td><td colspan="2">数　量</td><td>産地（単協）</td><td>入荷日</td><td>備　考</td><td>QR</td></tr>${rows}</table>
 ${last?`<div class="foot">上記の通り納品致しました</div>`:""}</div>`;
}
function c84Pages(t){
 if(t.dest!=="本社")return c89Pages(t);
 const today=t.lines.filter(g=>!g.fwd),fwd=t.lines.filter(g=>g.fwd),ent=[...today.map(g=>({g}))];
 if(fwd.length)ent.push({head:`【${c84Md(c84Add(t.date,1))}　納品分　先送り】`},...fwd.map(g=>({g})));
 const pages=[];for(let i=0;i<ent.length;i+=C84_ROWS)pages.push(ent.slice(i,i+C84_ROWS));if(!pages.length)pages.push([]);return pages;
}
function c84Half(t,ent,last,pi,pn,side){
 const nou=side==="nou",qr=nou;
 const rows=ent.map(e=>{if(e.blank)return `<tr class="b${e.keep?" keep":""}"><td></td><td></td><td></td><td></td><td></td><td></td>${qr?"<td></td>":""}</tr>`;if(e.head)return `<tr class="r"><td colspan="${qr?7:6}" class="hd">${esc(e.head)}</td></tr>`;const g=e.g,c=c84Cells(g);
  let img="";if(qr&&g.qr_key){try{img=`<img src="${c84Qr(location.origin+location.pathname+"?qr="+encodeURIComponent(g.qr_key))}">`}catch(_){}}
  return `<tr class="r"><td class="nm">${esc(g.name)}</td><td class="c">${esc(c.pack)}</td><td class="n">${esc(c.qty)}</td><td class="c u">${esc(c.unit)}</td><td class="c">${esc(g.origin)}</td><td class="c">${esc(c.received)}</td>${qr?`<td class="q">${img}</td>`:""}</tr>`}).join("");
 const blanks=last&&t.dest==="本社"?Array.from({length:C84_BLANK},()=>`<tr class="b"><td></td><td></td><td></td><td></td><td></td><td></td>${qr?"<td></td>":""}</tr>`).join(""):"";
 return `<div class="half"><div class="ttl">${nou?"納　品　書":"請　求　書"}<span class="pg">${pn>1?`${pi+1} / ${pn}`:""}</span></div>
 <div class="run">${esc(c84Title(t))}</div>
 <div class="top"><div><div class="to">${esc(C84_TO[t.dest])}　${nou?"御中":"殿"}</div><div class="dt">${esc(c84Jp(t.date))}</div></div><div class="from"><b>${esc(C84_FROM)}</b><div>${C84_ADDR}</div></div></div>
 <table><colgroup><col style="width:${qr?"34%":"40%"}"><col style="width:10%"><col style="width:11%"><col style="width:6%"><col style="width:${qr?"12%":"15%"}"><col style="width:${qr?"10%":"18%"}">${qr?'<col style="width:11%">':""}</colgroup>
 <tr class="th"><td>品　　名</td><td>入　数</td><td colspan="2">数　量</td><td>産　地</td><td>入荷日</td>${qr?"<td>QR</td>":""}</tr>${rows}${blanks}</table>
 ${last?`<div class="foot">上記の通り納品致しました</div>`:""}</div>`;
}
const C84_CSS=`.c84Page{width:1122px;height:794px;padding:22px 24px;background:#fff;color:#000;font-family:'Hiragino Sans','Noto Sans JP',sans-serif;display:flex;gap:22px;box-sizing:border-box;overflow:hidden}
.c84Page *{box-sizing:border-box}.c84Page .half{flex:1;min-width:0;display:flex;flex-direction:column}
.c84Page .ttl{font-size:22px;font-weight:900;text-align:center;border-bottom:3px double #000;padding-bottom:2px;position:relative}.c84Page .pg{position:absolute;right:0;bottom:4px;font-size:12px;font-weight:700}
.c84Page .run{font-size:20px;font-weight:900;margin-top:4px}
.c84Page .top{display:flex;justify-content:space-between;gap:8px;margin:4px 0 6px}.c84Page .to{font-size:15px;font-weight:800;border-bottom:1.5px solid #000;padding-bottom:2px}.c84Page .dt{font-size:14px;font-weight:700;margin-top:6px}
.c84Page .from{font-size:10px;line-height:1.35;text-align:left}.c84Page .from b{font-size:12.5px}
.c84Page table{width:100%;border-collapse:collapse;table-layout:fixed;font-size:calc(12.5px*var(--f,1))}.c84Page td{border:1px solid #000;padding:1px 3px;vertical-align:middle;overflow:hidden;white-space:nowrap}
.c84Page tr.th td{text-align:center;font-weight:800;height:24px;background:#f1f5f9}.c84Page tr.r td{height:calc(44px*var(--k,1))}.c84Page tr.b td{height:calc(34px*var(--k,1))}
.c84Page td.nm{white-space:normal;line-height:1.15;font-weight:700;font-size:calc(12px*var(--f,1))}.c84Page td.c{text-align:center}.c84Page td.n{text-align:right;font-weight:800;font-size:calc(14px*var(--f,1))}.c84Page td.u{font-size:11px}
.c84Page td.hd{font-weight:900;font-size:13px}.c84Page td.q{text-align:center;padding:0}.c84Page td.q img{width:calc(42px*var(--k,1));height:calc(42px*var(--k,1));display:block;margin:auto;image-rendering:pixelated}
.c84Page .hqtop{position:relative;text-align:center}.c84Page .hqttl{display:inline-block;font-size:26px;font-weight:900;border:2px solid #000;border-radius:8px;padding:2px 28px;letter-spacing:4px}.c84Page .hqtop .pg{position:absolute;right:0;bottom:4px;font-size:12px;font-weight:700}.c84Page td.og{white-space:normal;line-height:1.15;text-align:center;font-size:calc(12px*var(--f,1))}.c84Page td.og span{font-size:calc(11px*var(--f,1))}
.c84Page .foot{margin-top:6px;font-size:13px;font-weight:700;padding-left:20px}`;
function c87Fit(pg){
 const hs=[...pg.querySelectorAll(".half")],over=()=>{const r=pg.getBoundingClientRect(),z=r.height/794||1,lim=r.bottom-20*z;return hs.some(h=>[...h.children].some(c=>c.getBoundingClientRect().bottom>lim))};
 pg.style.removeProperty("--k");pg.style.removeProperty("--f");
 while(over()){const bs=hs.map(h=>[...h.querySelectorAll("tr.b:not(.keep)")].pop()).filter(Boolean);if(!bs.length)break;bs.forEach(b=>b.remove())}
 for(let k=.95;over()&&k>=.5;k-=.05){pg.style.setProperty("--k",k.toFixed(2));pg.style.setProperty("--f",Math.max(.78,k).toFixed(2))}
}
function c87FitAll(root){(root||document).querySelectorAll(".c84Page").forEach(c87Fit)}
function c84TicketPages(t){if(t.dest==="本社"){const hp=c89HqPages(t);return hp.map((ent,i)=>`<div class="c84Page hqPdfPage c89hq">${c89HqHtml(t,ent,i,hp.length)}</div>`)}const ps=c84Pages(t);return ps.map((ent,i)=>`<div class="c84Page hqPdfPage">${c84Half(t,ent,i===ps.length-1,i,ps.length,"nou")}${c84Half(t,ent,i===ps.length-1,i,ps.length,"sei")}</div>`)}
async function c84Pdf(idx){
 if(c84Busy)return;const box=document.getElementById("c84Status");const list=idx==null?c84Tickets:[c84Tickets[idx]].filter(Boolean);if(!list.length)return;
 const say=(h,c="notice")=>{if(box)box.innerHTML=`<div class="${c}">${h}</div>`};
 if(c84Url){try{URL.revokeObjectURL(c84Url)}catch(_){}c84Url=""}
 let root=null;c84Busy=true;say("A4横のPDFを作成中です。しばらくお待ちください…");
 try{
  if(typeof window.html2canvas!=="function"||!window.jspdf||typeof window.jspdf.jsPDF!=="function")throw new Error("PDF作成の部品が読み込まれていません。通信状況を確認してから、もう一度お試しください。");
  root=document.createElement("div");root.setAttribute("aria-hidden","true");root.style.cssText="position:fixed;left:-20000px;top:0;width:1122px;background:#fff;pointer-events:none";
  root.innerHTML=`<style>${C84_CSS}</style>`+list.flatMap(c84TicketPages).join("");document.body.appendChild(root);
  if(document.fonts&&document.fonts.ready)await document.fonts.ready;if(typeof qrWaitForPosterImages==="function")await qrWaitForPosterImages(root);
  const{jsPDF}=window.jspdf,doc=new jsPDF({orientation:"landscape",unit:"mm",format:"a4",compress:true});c87FitAll(root);const pg=[...root.querySelectorAll(".c84Page")];
  for(let i=0;i<pg.length;i++){const c=await window.html2canvas(pg[i],{scale:2,backgroundColor:"#ffffff",useCORS:true,logging:false,width:1122,height:794,windowWidth:1122,windowHeight:794});if(i)doc.addPage("a4","landscape");doc.addImage(c.toDataURL("image/png"),"PNG",0,0,297,210,undefined,"FAST")}
  const blob=doc.output("blob");if(!blob||!blob.size)throw new Error("PDFの作成に失敗しました。");
  const name=`伝票_${c84Date}_${idx==null?"すべて":c84Title(list[0]).replace(/[\s（）()]+/g,"_")}.pdf`;c84Url=URL.createObjectURL(blob);
  say(`PDFを作成しました（${pg.length}枚）。下のボタンで開いて印刷してください。<a class="btn green" style="display:block;width:100%;margin-top:8px;text-align:center;text-decoration:none" href="${c84Url}" download="${esc(name)}" target="_blank" rel="noopener">PDFを開く（${esc(name)}）</a>`,"ok");
 }catch(e){say(`PDFを作成できませんでした。${esc(e?.message||String(e))}`,"err")}
 finally{if(root)root.remove();c84Busy=false}
}
function c84Kind(g){if(g.hq)return g.day||"";return g.sun?(g.fwd?"日曜積込分・先送り":"日曜積込分"):(g.fwd?"先送り":"当日分")}
function c84Aoa(t){
 const a=[["伝票",c84Title(t)],["宛先",C84_TO[t.dest]],["伝票の日付",t.date],[],["品名","入数","数量","単位","産地","入荷日","単協・仕入先","出庫日","区分","ロットNo."]];
 const put=g=>{const c=c84Cells(g);a.push([g.name,c.pack,c.qty===""?"":Number(String(c.qty).replace(/,/g,"")),c.unit,g.origin,g.received||"",g.party,g.ship,c84Kind(g),g.lot_no])};
 t.lines.filter(g=>!g.fwd).forEach(put);const f=t.lines.filter(g=>g.fwd);if(f.length){a.push([`【${c84Md(c84Add(t.date,1))}　納品分　先送り】`]);f.forEach(put)}return a;
}
function c84Excel(){
 if(!c84Tickets.length)return;if(typeof XLSX==="undefined")return alert("Excel出力の部品が読み込まれていません。");
 const wb=XLSX.utils.book_new(),used=new Set;
 for(const t of c84Tickets){let n=c84Title(t).replace(/[\\\/?*\[\]:]/g,"").slice(0,28);while(used.has(n))n+="_";used.add(n);const ws=XLSX.utils.aoa_to_sheet(c84Aoa(t));ws["!cols"]=[{wch:30},{wch:8},{wch:9},{wch:6},{wch:10},{wch:12},{wch:14},{wch:12},{wch:16},{wch:22}];XLSX.utils.book_append_sheet(wb,ws,n)}
 XLSX.writeFile(wb,`伝票_${c84Date}.xlsx`);
}
async function c84MonthExcel(){
 if(c84Busy)return;if(typeof XLSX==="undefined")return alert("Excel出力の部品が読み込まれていません。");
 const month=document.getElementById("c84Month")?.value||String(c84Date||todayKey()).slice(0,7);if(!/^\d{4}-\d{2}$/.test(month))return alert("月を選んでください。");
 const box=document.getElementById("c84MonthStatus");c84Busy=true;
 try{const a=[["伝票の日付","出庫先","便","区分","品名","単協・仕入先","入数","数量","単位","産地","入荷日","出庫日","ロットNo."]];const [y,m]=month.split("-").map(Number),last=new Date(y,m,0).getDate(),limit=c84Add(todayKey(),2),cache=new Map;
  for(let d=1;d<=last;d++){const day=`${month}-${String(d).padStart(2,"0")}`;if(day>limit)break;if(box)box.innerHTML=`<div class="notice">${d}日の伝票を読み込み中です…</div>`;
   for(const t of c84Build(await c84Collect(day,cache),day))for(const g of t.lines){const c=c84Cells(g);a.push([t.date,t.dest==="本社"?"本社工場":t.dest,t.dest==="本社"?t.run:"",c84Kind(g),g.item,g.party,c.pack,c.qty===""?"":Number(String(c.qty).replace(/,/g,"")),c.unit,g.origin,g.received||"",g.ship,g.lot_no])}}
  const wb=XLSX.utils.book_new(),ws=XLSX.utils.aoa_to_sheet(a);ws["!cols"]=[{wch:12},{wch:9},{wch:9},{wch:16},{wch:22},{wch:14},{wch:8},{wch:9},{wch:6},{wch:10},{wch:12},{wch:12},{wch:22}];XLSX.utils.book_append_sheet(wb,ws,"伝票の一覧");XLSX.writeFile(wb,`伝票の一覧_${month}.xlsx`);
  if(box)box.innerHTML=`<div class="ok">${a.length-1}行を出力しました。</div>`}
 catch(e){if(box)box.innerHTML=`<div class="err">出力できませんでした。${esc(e?.message||String(e))}</div>`}
 finally{c84Busy=false}
}
function c86CanEdit(){return["admin","worker"].includes(String(db?.role||""))}
function c86EditHtml(t,i){
 if(!c86CanEdit())return"";
 const hq=t.dest==="本社";
 const rows=t.lines.map((g,j)=>{if(hq&&g.big)return"";const c=c84Cells(g);
  const need=g.big&&!g.mv.every(x=>x.kgSet);
  return `<div style="display:flex;gap:6px;align-items:center;justify-content:space-between;border-top:1px solid #e2e8f0;padding:6px 0"><div class="small" style="flex:1;min-width:0"><b>${esc(g.name)}</b><br>${esc(c.pack)}　${esc(c.qty||"（重さ未入力）")}${esc(c.qty?c.unit:"")}${need?'　<span style="color:#b91c1c;font-weight:800">総重量が未入力</span>':""}</div>
  <button class="btn btn2" style="flex:0 0 auto;padding:6px 10px;font-size:14px" ${seikaEventAttrs("click",g.big?"c86EditKg":"c86EditPack",[i,j])}>${g.big?"総重量を入れる・直す":"入数を直す"}</button></div>`}).join("");
 if(!rows)return"";
 const open=!hq&&t.lines.some(g=>g.big&&!g.mv.every(x=>x.kgSet));
 return `<details style="margin-top:8px" ${open?"open":""}><summary style="font-weight:800;cursor:pointer">${hq?"入数を直す":"総重量・入数を入れる・直す"}</summary>${rows}</details>`;
}
async function c86Save(id,kg,pack){await callRpc("qr_slip_adjust_save_v1199c86",{p_movement_id:id,p_total_kg:kg,p_pack:pack})}
function c86Err(e){const m=String(e?.message||e||"");return /qr_slip_adjust_save_v1199c86|schema cache|does not exist|404/.test(m)?"保存の仕組み（SQL 036）がまだ入っていません。管理者にSQLの実行を頼んでください。":m}
async function c86EditKg(i,j){
 const g=c84Tickets[i]?.lines[j];if(!g)return;
 try{for(const [k,x] of g.mv.entries()){
  const label=g.mv.length>1?`（${k+1}/${g.mv.length}回目の出庫）`:"";
  const v=prompt(`${g.name}${label}\\n${c84Num(x.count)}基の総重量（kg）を入れてください。\\n空欄にすると入力を消します。`,x.kgSet&&x.kg!=null?String(x.kg):"");
  if(v===null)return;const t=String(v).trim().replace(/[０-９．]/g,c=>String.fromCharCode(c.charCodeAt(0)-0xFEE0)).replace(/kg$/i,"");
  if(t===""){await c86Save(x.id,null,null);continue}
  const n=Number(t);if(!(n>0&&n<100000)){alert("総重量は0より大きい数字で入れてください。");return}
  await c86Save(x.id,n,null)}
  return c84SlipPage(c84Date)}catch(e){alert(c86Err(e))}
}
async function c86EditPack(i,j){
 const g=c84Tickets[i]?.lines[j];if(!g)return;
 const v=prompt(`${g.name}\\n入数を入れてください（例：12kg）。\\n空欄にすると、ロットに登録した量目に戻します。`,g.mv.some(x=>x)?g.pack:"");if(v===null)return;
 const t=String(v).trim();
 try{for(const x of g.mv)await c86Save(x.id,null,t?c84Pack(t):null);return c84SlipPage(c84Date)}catch(e){alert(c86Err(e))}
}
function c84DayBtn(label,d){return `<button class="btn btn2" style="flex:1;min-width:0;padding:8px 4px;font-size:14px" ${seikaEventAttrs("click","c84SlipPage",[d])}>${esc(label)}</button>`}
async function c84SlipPage(date){
 setScreen("c84SlipPage",[date]);if(!c84Can())return qrHome();
 c84Date=String(date||c84Date||c84Add(todayKey(),1)).slice(0,10);
 pageShell("伝票発行（埼玉・深谷・本社工場）","QR出庫から納品書・請求書を作る",`<div class="notice">読み込んでいます…</div>`);
 let items=[];try{items=await c84Collect(c84Date,new Map)}catch(e){return pageShell("伝票発行（埼玉・深谷・本社工場）","エラー",`<div class="err">読み込みに失敗しました。<br>${esc(e?.message||String(e))}</div>`)}
 if(currentScreen!=="c84SlipPage")return;
 c84Tickets=c84Build(items,c84Date);
 const today=todayKey(),sat=c84Dow(today)===6;
 const cards=c84Tickets.map((t,i)=>{const n=t.lines.length,f=t.lines.filter(g=>g.fwd).length,sun=t.lines.filter(g=>g.sun).length,miss=t.lines.filter(g=>g.big&&!(g.kgOk&&g.kg>0)).length;
  return `<div class="card"><div style="display:flex;justify-content:space-between;gap:8px;align-items:center"><b style="font-size:18px">${esc(c84Title(t))}</b><span class="badge">${n}行</span></div>
  <div class="small">伝票の日付：${esc(c84Jp(t.date))}${sun?`　／　日曜積込分 ${sun}行`:""}${f?`　／　先送り ${f}行`:""}　／　${c84Pages(t).length}枚</div>${miss?`<div class="warn" style="margin-top:6px">大型容器 ${miss}行は重さが分かりません。数量欄は空欄になります（手書きで記入してください）。</div>`:""}
  <div style="overflow:auto;margin-top:8px;border:1px solid #cbd5e1;border-radius:8px"><div style="width:561px;height:397px;overflow:hidden"><div style="transform:scale(.5);transform-origin:0 0">${c84TicketPages(t)[0]}</div></div></div>
  ${c86EditHtml(t,i)}<button class="btn homeBtnSlip" style="width:100%;margin-top:8px" ${seikaEventAttrs("click","c84Pdf",[i])}>この伝票を印刷（PDF）</button></div>`}).join("");
 pageShell("伝票発行（埼玉・深谷・本社工場）","QR出庫から納品書・請求書を作る",`<style>${C84_CSS}</style>
 <div class="card"><label class="label">伝票の日付（納品日）</label><input id="c84Date" type="date" class="input" value="${esc(c84Date)}" ${seikaEventAttrs("change","c84DateChanged",[])}>
 <div style="display:flex;gap:6px;margin-top:8px">${c84DayBtn("◀ 前の日",c84Add(c84Date,-1))}${c84DayBtn("今日",today)}${c84DayBtn("明日",c84Add(today,1))}${c84DayBtn("次の日 ▶",c84Add(c84Date,1))}</div>
 ${sat?`<div class="notice" style="margin-top:8px"><b>今日は土曜日です</b><div class="small">日曜日の伝票（今日積む分）と、月曜日の伝票（日曜積込分）を今日のうちに印刷できます。</div><div style="display:flex;gap:6px;margin-top:6px">${c84DayBtn("日曜日の伝票",c84Add(today,1))}${c84DayBtn("月曜日の伝票",c84Add(today,2))}</div></div>`:""}
 <div class="small" style="margin-top:6px">この日付の伝票に載る出庫（取消したものを除く）を集めます。<br>・埼玉・深谷：前の日の出庫。月曜日の伝票には、土曜日に「日曜積込分」で出庫した分も入ります（土曜日の「日曜積込分」は日曜日の伝票には入りません）。<br>・本社工場：本社入荷日（予定）がこの日の出庫。便ごとに1枚です。本社直接入荷（石岡経由）は載りません。</div></div>
 ${c84Tickets.length?`<div class="card"><button class="btn homeBtnSlip" style="width:100%" ${seikaEventAttrs("click","c84Pdf",[null])}>すべての伝票を印刷（PDF・${c84Tickets.length}件）</button><button class="btn btn2" style="width:100%;margin-top:8px" ${seikaEventAttrs("click","c84Excel",[])}>この日の伝票をExcelで出力</button><div id="c84Status" style="margin-top:8px"></div></div>${cards}`:`<div class="notice">この日付の埼玉・深谷・本社工場の伝票に載る出庫はありません。</div>`}
 <div class="card"><b>月の伝票の一覧（Excel）</b><div class="small">選んだ月の伝票（伝票の日付で集計）の中身を1つの表にまとめて出力します（事務所での確認用）。</div><input id="c84Month" type="month" class="input" style="margin-top:6px" value="${esc(c84Date.slice(0,7))}"><button class="btn btn2" style="width:100%;margin-top:8px" ${seikaEventAttrs("click","c84MonthExcel",[])}>月の一覧をExcelで出力</button><div id="c84MonthStatus" style="margin-top:8px"></div></div>`);
 c87FitAll(document);
}

function c84DateChanged(){const v=document.getElementById("c84Date")?.value;if(v)return c84SlipPage(v)}
Object.assign(window,{c87FitAll,c86EditKg,c86EditPack,c84SlipPage,c84DateChanged,c84Pdf,c84Excel,c84MonthExcel,c84Build,c84Collect,c84Title,c84TicketPages,C84_CSS});
const st=document.createElement("style");st.textContent='.homeBtnSlip{background:linear-gradient(90deg,#4a044e 0%,#a21caf 52%,#f0abfc 100%) !important;color:#fff !important;text-shadow:0 1px 2px rgba(0,0,0,.3) !important;border-color:transparent !important;}';document.head.appendChild(st);
const base=qrHome;
qrHome=async function(...a){
 const r=await base.apply(this,a);
 if(currentScreen==="qrHome"&&c84Can()&&!document.getElementById("c84SlipBtn")){
  const host=document.querySelector(".homePrimary");
  const html=`<button id="c84SlipBtn" type="button" class="btn homeBtnSlip" data-c73="1" ${seikaEventAttrs("click","c84SlipPage",[])}>伝票発行（埼玉・深谷・本社工場）<br><span style="font-size:15px;font-weight:800">QR出庫から納品書・請求書を印刷</span></button>`;
  const anchor=document.getElementById("c83ViaBtn")||host?.querySelector(".homeBtnQr");
  if(anchor)anchor.insertAdjacentHTML("afterend",html);else host?.insertAdjacentHTML("beforeend",html);
 }
 return r;
};
window.qrHome=qrHome;
try{
 const sec={title:"伝票（納品書・請求書）を発行する",where:"QR在庫管理 → 伝票発行（埼玉・深谷・本社工場）",
  steps:["「伝票の日付（納品日）」を選ぶと、その日付の伝票に載る出庫（取消したものを除く）から伝票ができます。「前の日」「今日」「明日」「次の日」でも選べます。",
   "埼玉・深谷は前の日の出庫を集めて1枚です。本社工場は本社入荷日（予定）がその日の出庫を集め、便（配送便・原料便・市場便）ごとに1枚です。",
   "土曜日は、埼玉・深谷へ日曜日に積む分を出庫するとき、出庫区分で「日曜積込分」（翌日発注分のときは「日曜積込分・先送り」）を選びます。この区分は土曜日に埼玉・深谷を選んだときだけ出ます。",
   "土曜日のうちに、日曜日の伝票（土曜日に積む分）と月曜日の伝票（日曜積込分）を印刷できます。土曜日の画面に出る「日曜日の伝票」「月曜日の伝票」を押します。",
   "伝票はA4横で、左が納品書、右が請求書です。品名・入数（例：10kg）・数量・産地・入荷日が入ります。品名の後ろには単協が入り、単協がないロットは仕入先が入ります。大型容器は入数が基数、数量が総重量（kg）になります。",
   "埼玉・深谷へ網コンテナ・鉄コンテナ・パレテーナを出庫するときは、総重量（kg）を必ず入れます。単発のQR出庫は画面の「総重量（kg）」欄、連続出庫・まとめ出庫は出庫のときに出る入力欄に入れます。入れた重さは伝票だけに使い、石岡の在庫の重さは変わりません。",
   "ロットの量目と違う入数で出すとき（例：白菜を12kgで出す）は、QR出庫の画面の「入数（量目と違うときだけ）」に入れます（埼玉・深谷・本社のとき。大型容器は除く）。本社は、本社移動用の貼り紙の量目にも同じ入数が入ります。在庫は入数に関係なく、出庫したケース数で減ります。",
   "本社工場の伝票は、本社入荷日（予定）が伝票の日付と同じ分を載せます。「翌日分先送り」で出した分も、本社に着く日の伝票に普通の行として入ります（「先送り」の欄は出ません）。",
   "埼玉・深谷の伝票は、品目・先送りの見出し・手書き用の2行を合わせて15行までなら1枚に入ります（当日分 → 手書き用2行 → 先送り分の順）。15行を超えるときだけ、当日分と先送り分の用紙を分けます。当日分だけで超えるときは2枚目に続きます。",
   "埼玉・深谷の伝票の品目は、いつもの納品書と同じ順番に並びます（同じ品目は入荷日の古い順。リストにない品目は最後に品名順）。",
   "本社工場の伝票は、原料発注書に近い形の「納品書」1枚です（請求書はつきません）。品名・入数・数量・産地（単協）・入荷日・備考（手書き用）・QRが入り、手書き用の2行を含めて15行までは1枚、超えるときだけ2枚目に続きます。",
   "品名が長くて行が高くなったときは、印刷の用紙に収まるように、手書き用の2行を残して空欄の行を減らし、それでも入らないときは文字と行を少し小さくします。",
   "出庫したあとで総重量や入数を入れる・直すときは、伝票の画面の「総重量・入数を入れる・直す」（本社工場の伝票は「入数を直す」）を開いてボタンを押します（管理者・青果社員）。本社へ出庫した分は、貼り紙の印刷画面の「入数（量目と違うとき）」からも直せます。",
   "同じロットを何回かに分けて出庫したときは1行にまとめます。先送り分は「【○/○ 納品分 先送り】」の下にまとめます。",
   "「この伝票を印刷」または「すべての伝票を印刷」でPDFを作り、開いて印刷します。Android端末は縦向きの紙に回したPDFになります。",
   "QR品目にないものは、表の下の空いた3行に手書きで書き足します。"],
  check:"納品書の各行の右端の小さなQRを読むと、そのロットの画面が開きます（ログインが必要です）。「この日の伝票をExcelで出力」「月の一覧をExcelで出力」で、事務所でパソコンに打ち込まずに使えます。",
  caution:"伝票はアプリに保存しません。出庫を取消・修正したあとは、もう一度印刷してください。本社直接入荷（石岡経由）は載りません。"};
 if(typeof V198_GUIDE_SECTIONS!=="undefined")V198_GUIDE_SECTIONS.c84Slip=sec;
 if(typeof V195_ROLE_GUIDES!=="undefined")for(const r of ["admin","worker","clerk"]){const g=V195_ROLE_GUIDES[r];if(g&&Array.isArray(g.sections)&&!g.sections.some(x=>x.title===sec.title))g.sections.push(sec)}
}catch(e){}
})();
