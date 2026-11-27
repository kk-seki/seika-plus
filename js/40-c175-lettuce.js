/* ===== v1.199-c175 レタスの重量のブレ =====
   重量を出している客先（プライムデリカ 相模原・龍ヶ崎、日本デリカ）のレタスについて、産地報告書（確定）の
   「使ったケース数（箱数）」と「客先で量った重さ（kg）」から、次を日ごと・客先ごとに出す。Excelにも出せる。
   ・本来のケース数：重さ ÷ 1ケースの重さ（8kg入れなら ÷8）。切り上げも出す
   ・ケースの差：使ったケース − 本来のケース（＋なら多く使った、−なら少なく使った）
   ・重さの差：使ったケース×1ケースの重さ − 量った重さ（kg）
   ・1ケースの平均：量った重さ ÷ 使ったケース
   ・予定（積み込み表）とのちがい：予定の重さ・ケース数と、量った重さ・使ったケース数の差（例：予定400kg＝50ケースのところ61ケース使った）
   データは産地報告書の取り込み（ship_actual_lines_v1199c142 の boxes・pack_kg・kg）と積み込み表（ship_plan_lines_v1199c140）。SQLなし。 */
(()=>{
const C175_CUSTOMERS=[/相模原/,/龍ヶ崎/,/日本デリカ/];
const C175_ITEM="レタス";
const canSee=()=>["admin","worker","buyer","sales"].includes(db?.role);
const T=()=>window.c140Lib?.T||{imp:"ship_plan_imports_v1199c140",line:"ship_plan_lines_v1199c140",aimp:"ship_actual_imports_v1199c142",aline:"ship_actual_lines_v1199c142"};
const r1=v=>Math.round(v*10)/10;
const jst=()=>new Date().toLocaleDateString("sv-SE",{timeZone:"Asia/Tokyo"});
const monthStart=d=>d.slice(0,8)+"01";
const short=c=>String(c||"").replace(/^\(株\)|^（株）|株式会社/g,"").replace(/プライムデリカ\s*/,"プライムデリカ ").trim();
let C175={from:"",to:"",rows:[]};

function c175Calc(l,plan=null){
 const boxes=Number(l.boxes),kg=Number(l.kg),pack=Number(l.pack_kg)||8;
 if(!(boxes>0)||!(kg>0))return null;
 const need=kg/pack,pk=plan&&Number(plan.kg)>0?Number(plan.kg):null,pc=pk===null?null:(Number(plan.cases)>0?Number(plan.cases):r1(pk/pack));
 return{date:l.delivery_date,customer:l.customer_name,item:l.item_name,pack,boxes,kg,need:r1(need),needCeil:Math.ceil(need-1e-9),
  diffCases:r1(boxes-need),diffKg:r1(boxes*pack-kg),avg:r1(kg/boxes),qty:l.qty_raw||"",
  planKg:pk,planCases:pc,vsPlanCases:pc===null?null:r1(boxes-pc),vsPlanKg:pk===null?null:r1(kg-pk)};
}
function c175Summary(rows){
 const mp=new Map;
 for(const r of rows){
  const o=mp.get(r.customer)||{customer:r.customer,days:0,boxes:0,kg:0,need:0,diffKg:0,over:0,under:0,planDays:0,planKg:0,planCases:0,planBoxes:0,planActKg:0};
  o.days++;o.boxes+=r.boxes;o.kg+=r.kg;o.need+=r.kg/r.pack;o.diffKg+=r.boxes*r.pack-r.kg;if(r.diffCases>0)o.over++;else if(r.diffCases<0)o.under++;
  if(r.planKg!==null){o.planDays++;o.planKg+=r.planKg;o.planCases+=r.planCases;o.planBoxes+=r.boxes;o.planActKg+=r.kg}mp.set(r.customer,o)}
 return [...mp.values()].map(o=>({...o,kg:r1(o.kg),need:r1(o.need),diffCases:r1(o.boxes-o.need),diffKg:r1(o.diffKg),avg:r1(o.kg/o.boxes),
  planKg:o.planDays?r1(o.planKg):null,planCases:o.planDays?r1(o.planCases):null,vsPlanCases:o.planDays?r1(o.planBoxes-o.planCases):null,vsPlanKg:o.planDays?r1(o.planActKg-o.planKg):null}))
  .sort((a,b)=>a.customer.localeCompare(b.customer,"ja"));
}
async function c175Load(from,to){
 const t=T();
 const lines=async(impT,lineT)=>{
  const imps=await qrSelect(impT,`select=id,delivery_date&status=eq.active&delivery_date=gte.${from}&delivery_date=lte.${to}&order=delivery_date.asc&limit=400`);
  const ids=(imps||[]).map(i=>i.id),all=[];
  for(let i=0;i<ids.length;i+=40){const ls=await qrSelect(lineT,`select=delivery_date,customer_name,item_name,qty_raw,boxes,pack_kg,kg,cases&import_id=in.(${ids.slice(i,i+40).join(",")})&item_name=eq.${encodeURIComponent(C175_ITEM)}&limit=5000`);
   for(const l of ls||[])if(C175_CUSTOMERS.some(re=>re.test(l.customer_name||"")))all.push(l)}
  return all};
 const [act,plan]=await Promise.all([lines(t.aimp,t.aline),lines(t.imp,t.line).catch(()=>[])]);
 /* 予定（積み込み表）は納品日×客先で足す */
 const pm=new Map;for(const p of plan){const k=`${p.delivery_date}|${p.customer_name}`;const o=pm.get(k)||{kg:0,cases:0};o.kg+=Number(p.kg)||0;o.cases+=Number(p.cases)||Number(p.boxes)||0;pm.set(k,o)}
 /* 確定も納品日×客先で足す（1客先に行が2つあるとき） */
 const am=new Map;for(const l of act){const k=`${l.delivery_date}|${l.customer_name}`;const o=am.get(k)||{...l,boxes:0,kg:0,qty_raw:""};o.boxes+=Number(l.boxes)||0;o.kg+=Number(l.kg)||0;o.qty_raw=[o.qty_raw,l.qty_raw].filter(Boolean).join(" / ");am.set(k,o)}
 const out=[];for(const [k,l] of am){const r=c175Calc(l,pm.get(k)||null);if(r)out.push(r)}
 return out.sort((a,b)=>a.date<b.date?1:a.date>b.date?-1:a.customer.localeCompare(b.customer,"ja"));
}
const sign=v=>v>0?`+${v}`:String(v);
const cls=v=>v>0?"c175Over":v<0?"c175Under":"";
async function c175LettucePage(from="",to=""){
 if(!canSee()){alert("仕入れ担当者・営業担当者・管理者・青果社員が使えます");return home()}
 const today=jst();from=from||C175.from||monthStart(today);to=to||C175.to||today;
 if(from>to)[from,to]=[to,from];
 setScreen("c175LettucePage",[from,to]);
 pageShell("レタスの重量のブレ","読み込んでいます",'<div class="card"><div class="notice">読み込んでいます。</div></div>');
 let rows;
 try{rows=await c175Load(from,to)}catch(e){if(currentScreen!=="c175LettucePage")return;return pageShell("レタスの重量のブレ","",`<div class="err">${esc(String(e?.message||e))}</div>`)}
 if(currentScreen!=="c175LettucePage")return;
 C175={from,to,rows};
 const sum=c175Summary(rows);
 const nav=`<div class="row" style="gap:8px;flex-wrap:wrap;align-items:center"><input id="c175From" type="date" value="${esc(from)}" style="font-size:17px;padding:6px"> 〜 <input id="c175To" type="date" value="${esc(to)}" style="font-size:17px;padding:6px">
  <button class="btn blue" ${seikaEventAttrs("click","c175Apply",[])}>表示</button><button class="btn btn2" ${seikaEventAttrs("click","c175Excel",[])}>Excelで出力</button></div>
  <div class="small" style="margin-top:6px">予定は積み込み表、使ったケース・量った重さは産地報告書（確定）です。本来のケース数＝量った重さ÷1ケースの重さ（8kg入れなら÷8）。<span class="c175Over">＋は多く使った</span>、<span class="c175Under">−は少なく使った</span>。対象：プライムデリカ 相模原・龍ヶ崎、日本デリカのレタス。</div>`;
 const ps=(v,u="")=>v===null||v===undefined?"－":`<span class="${cls(v)}">${sign(v)}${u}</span>`,pl=o=>o.planKg===null?"－":`${o.planKg}kg（${o.planCases}）`;
 const sumTbl=sum.length?`<div style="overflow:auto"><table class="table c175Tbl"><tr><th>客先</th><th>日数</th><th>予定<br><span class="small">（積み込み表）</span></th><th>使ったケース</th><th>量った重さ</th><th>予定より<br>ケース</th><th>予定より<br>重さ</th><th>本来のケース<br><span class="small">（重さ÷8kg）</span></th><th>多く使った<br>ケース</th><th>1ケース平均</th><th>多い日／少ない日</th></tr>${sum.map(o=>`<tr><td>${esc(short(o.customer))}</td><td>${o.days}</td><td>${pl(o)}</td><td>${o.boxes}</td><td>${o.kg}kg</td><td>${ps(o.vsPlanCases)}</td><td>${ps(o.vsPlanKg,"kg")}</td><td>${o.need}</td><td class="${cls(o.diffCases)}"><b>${sign(o.diffCases)}</b></td><td>${o.avg}kg</td><td>${o.over}日／${o.under}日</td></tr>`).join("")}</table></div>`:'<div class="small">この期間のデータはありません。</div>';
 const dayTbl=rows.length?`<div style="overflow:auto"><table class="table c175Tbl"><tr><th>納品日</th><th>客先</th><th>予定<br><span class="small">（積み込み表）</span></th><th>使ったケース</th><th>量った重さ</th><th>予定より<br>ケース</th><th>予定より<br>重さ</th><th>本来のケース<br><span class="small">（切り上げ）</span></th><th>多く使った<br>ケース</th><th>1ケース平均</th></tr>${rows.map(r=>`<tr><td>${esc(r.date.slice(5).replace("-","/"))}</td><td>${esc(short(r.customer))}</td><td>${pl(r)}</td><td>${r.boxes}<span class="small">（${r.pack}kg入れ）</span></td><td>${r.kg}kg</td><td>${ps(r.vsPlanCases)}</td><td>${ps(r.vsPlanKg,"kg")}</td><td>${r.need}<span class="small">（${r.needCeil}）</span></td><td class="${cls(r.diffCases)}"><b>${sign(r.diffCases)}</b></td><td>${r.avg}kg</td></tr>`).join("")}</table></div>`:"";
 pageShell("レタスの重量のブレ",`${from.replace(/-/g,"/")}〜${to.replace(/-/g,"/")}`,`<div class="card">${nav}</div>
  <div class="card"><b>客先ごとの合計</b>${sumTbl}</div>
  ${rows.length?`<div class="card"><b>日ごと（${rows.length}件）</b>${dayTbl}</div>`:""}
  <button class="btn btn2" style="width:100%;margin-top:8px" ${seikaEventAttrs("click","c153GapPage",["",""])}>出荷予定と確定のちがいへ</button>
  <button class="btn btn2" style="width:100%;margin-top:8px" ${seikaEventAttrs("click","home",[])}>ホームへ</button>`);
}
function c175Apply(){const f=document.getElementById("c175From")?.value||"",t=document.getElementById("c175To")?.value||"";if(!f||!t)return alert("期間を選んでください");C175.from=f;C175.to=t;return c175LettucePage(f,t)}
function c175Excel(){
 const {from,to,rows}=C175;if(!rows.length)return alert("この期間のデータはありません");
 if(typeof XLSX==="undefined")return alert("Excelを作る部品が読み込まれていません。通信を確認してください");
 const sum=c175Summary(rows),wb=XLSX.utils.book_new();
 const a1=[["レタスの重量のブレ（客先ごと）",`${from}〜${to}`],[],["客先","日数","予定の重さ(kg)（積み込み表）","予定のケース","使ったケース","量った重さ(kg)","予定よりケース","予定より重さ(kg)","本来のケース（重さ÷1ケース）","多く使ったケース（＋多い／−少ない）","ケースで出した重さとの差(kg)","1ケース平均(kg)","多く使った日","少なく使った日"],
  ...sum.map(o=>[o.customer,o.days,o.planKg??"",o.planCases??"",o.boxes,o.kg,o.vsPlanCases??"",o.vsPlanKg??"",o.need,o.diffCases,o.diffKg,o.avg,o.over,o.under])];
 const a2=[["レタスの重量のブレ（日ごと）",`${from}〜${to}`],[],["納品日","客先","1ケースの重さ(kg)","予定の重さ(kg)（積み込み表）","予定のケース","使ったケース","量った重さ(kg)","予定よりケース","予定より重さ(kg)","本来のケース","本来のケース（切り上げ）","多く使ったケース（＋多い／−少ない）","ケースで出した重さとの差(kg)","1ケース平均(kg)","産地報告書の書き方"],
  ...rows.slice().reverse().map(r=>[r.date,r.customer,r.pack,r.planKg??"",r.planCases??"",r.boxes,r.kg,r.vsPlanCases??"",r.vsPlanKg??"",r.need,r.needCeil,r.diffCases,r.diffKg,r.avg,r.qty])];
 const s1=XLSX.utils.aoa_to_sheet(a1),s2=XLSX.utils.aoa_to_sheet(a2);
 s1["!cols"]=[{wch:30},{wch:6},{wch:16},{wch:10},{wch:12},{wch:13},{wch:12},{wch:14},{wch:16},{wch:20},{wch:18},{wch:14},{wch:12},{wch:13}];
 s2["!cols"]=[{wch:11},{wch:30},{wch:12},{wch:16},{wch:10},{wch:12},{wch:13},{wch:12},{wch:14},{wch:12},{wch:16},{wch:20},{wch:18},{wch:14},{wch:24}];
 XLSX.utils.book_append_sheet(wb,s1,"客先ごと");XLSX.utils.book_append_sheet(wb,s2,"日ごと");
 XLSX.writeFile(wb,`レタスの重量のブレ_${from}_${to}.xlsx`);
}
/* 入口：「出荷予定と確定のちがい」の画面 */
try{
 const base=c153GapPage;
 c153GapPage=async function(...a){const r=await base.apply(this,a);
  if(currentScreen==="c153GapPage"&&canSee()&&!document.getElementById("c175Btn")){const card=document.querySelector("#app .card");
   card?.insertAdjacentHTML("afterend",`<button id="c175Btn" class="btn btn2" style="width:100%;margin-top:8px" ${seikaEventAttrs("click","c175LettucePage",["",""])}>レタスの重量のブレ（相模原・龍ヶ崎・日本デリカ）</button>`)}
  return r};
 window.c153GapPage=c153GapPage;
}catch(e){}
Object.assign(window,{c175LettucePage,c175Apply,c175Excel,c175Lib:{c175Calc,c175Summary,C175_CUSTOMERS}});
{const s=document.createElement("style");s.textContent=`.c175Tbl{font-size:14px}.c175Tbl td,.c175Tbl th{white-space:nowrap;text-align:right}.c175Tbl td:nth-child(-n+2),.c175Tbl th:nth-child(-n+2){text-align:left}.c175Over{color:#b45309}.c175Under{color:#1d4ed8}`;document.head.appendChild(s)}
})();
