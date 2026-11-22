/* ===== v1.199-c142 確定数量の取り込み（産地報告書） =====
   ・社外の客先の確定数量は産地報告書（プライム産地報告.xlsx）にだけあり、翌日には次の日の分で上書きされる。
     セット後に産地報告書を取り込み、客先×品目の確定数量（産地・単協名つき）を保存する（SQL 062）。出荷予定の画面で「予定」と並べて見る。
   ・Excelは端末の中で読む。各シートの1行目に納品日、客先ごとに「品目・産地・（単協名）・cs」の表（見出しの文字で列を探す）。
     客先名は表の2行上。数量は「10ｋ」の次の行に「6」、「15ｋ26」、「15ｋ13　5ｋ1」、「8ｋ193(1191ｋ)」（かっこは合計kg）。
     規格だけで数のない行は出していないものとして読まない。読めない書き方は要確認。
   ・「重量」の表（納品先・単協・kg）：レタスをケースでなく計量して出す客先（プライム龍ヶ崎・第二など。量目不足対策）。計量したkgを同じ客先・品目のケースの行の重さとして使う。
   ・品名は品名読み替えマスタ（061）、客先名は客先の読み替え（062）で、積み込み表の客先名にそろえる。ないものは推測しない（要確認）。
   ・同じ納品日をもう一度取り込んだら置き換え（前の分は「置き換え済み」で残る）。取り込み：管理者・青果社員・事務員。 */
(()=>{
const L=window.c140Lib;if(!L)return;
const {T,N,key,md,addDays,num,busy,uuid,loadMasters,seikaItems,resolveItem,casesOf,baseName,cellDate,loadPlan,loadActual,sqlMissing,canImport}=L;
const NEED_SQL="この機能の準備がまだです（SQL 062 の実行が必要です）。";
/* 客先名の照合キー：空白・全角半角・大文字小文字に加えて「ヶ・ケ」「ヵ・カ」の違いもそろえる */
const ckey=v=>key(v).replace(/ヶ/g,"ケ").replace(/ヵ/g,"カ");
const tx=(ws,r,c)=>{const x=ws[XLSX.utils.encode_cell({r,c})];if(!x||x.v===null||x.v===undefined)return"";return N(x.v)};
const raw=(ws,r,c)=>{const x=ws[XLSX.utils.encode_cell({r,c})];return x?x.v:undefined};

/* 数量：{boxes,kg,pack,override} ／ null（数がない＝出していない）／ {bad:true} */
function parseReportQty(v){
 let s=N(v).toLowerCase();if(!s)return null;
 s=s.replace(/[×x＊*]/g," ");
 let override=null;const om=s.match(/\((\d+(?:\.\d+)?)\s*kg?\)/);if(om)override=Number(om[1]);
 s=s.replace(/\([^)]*\)/g," ");
 const re=/(\d+(?:\.\d+)?)\s*kg?(?![a-z])\s*(\d+(?:\.\d+)?)?|(\d+(?:\.\d+)?)/g;
 const left=s.replace(re,"").replace(/[\s,、\/]/g,"");if(left)return{bad:true};
 const pairs=[];let pending=null,m;
 while((m=re.exec(s))){
  if(m[1]!==undefined&&/k/.test(m[0])){if(m[2]!==undefined)pairs.push([Number(m[1]),Number(m[2])]);else pending=Number(m[1])}
  else{const n=Number(m[3]??m[1]);if(pending!==null){pairs.push([pending,n]);pending=null}else return{bad:true}}
 }
 if(!pairs.length)return override?{boxes:null,kg:override,pack:null,override}:null;
 let kg=0,boxes=0;const packs=new Set;for(const [p,c] of pairs){kg+=p*c;boxes+=c;packs.add(p)}
 kg=Math.round(kg*1000)/1000;
 return{boxes,kg:override??kg,pack:packs.size===1?[...packs][0]:null,override,calcKg:kg};
}
const LABELS={"産地":"origin","単協名":"coop","単協":"coop","仕入先":"supplier","入荷日":"recv","cs":"cs","c/s":"cs","ケース":"cs"};
/* 重量の表（納品先・単協・kg）：レタスをケースでなく計量して出す客先（プライム龍ヶ崎・第二など）。
   行＝納品先・単協・重さ（数字の右に「kg」）。次の行に品名（例「剝きレタス」）があればその品名、なければレタス。 */
function readWeight(ws,sn,date,h,heads,range,out){
 const next=heads.filter(x=>x.c===h.c&&x.r>h.r).map(x=>x.r-2);const end=next.length?Math.min(...next):range.e.r+1;
 let n=0;
 for(let r=h.r+1;r<end;r++){
  const dest=tx(ws,r,h.c);if(!dest)continue;
  let kg=null;for(let cc=h.c+1;cc<=Math.min(h.c+10,range.e.c);cc++){const v=raw(ws,r,cc);if(typeof v==="number"&&kg===null&&/^kg$/i.test(tx(ws,r,cc+1)))kg=v}
  if(kg===null){const v2=[...Array(8)].map((_,i)=>raw(ws,r,h.c+1+i)).find(v=>typeof v==="number");if(v2!==undefined)kg=v2}
  if(kg===null)continue;                                 // 重さのない行（品名だけの行など）
  const lab=r+1<end?tx(ws,r+1,h.c):"",labHasKg=lab&&[...Array(8)].some((_,i)=>typeof raw(ws,r+1,h.c+1+i)==="number");
  const item=lab&&!labHasKg?lab:"レタス";
  const coop=h.cols.coop!==undefined?tx(ws,r,h.cols.coop):"";
  out.lines.push({date,file:out.file,sheet:sn,cell:XLSX.utils.encode_cell({r,c:h.c}),customerRaw:dest,raw:item,base:baseName(item),qtyRaw:`${kg}kg（計量）`,origin:"",coop,issues:[],boxes:null,pack:null,kg:Number(kg),weight:true,note:""});
  n++;
 }
 return n;
}
/* ブック全体を読む */
function readReport(wb,fileName){
 const out={file:fileName,lines:[],sheets:[],skipped:[],dates:new Set,errors:[]};
 for(const sn of wb.SheetNames){
  const ws=wb.Sheets[sn];if(!ws||!ws["!ref"])continue;
  const range=XLSX.utils.decode_range(ws["!ref"]);
  let date="";for(let c=0;c<=Math.min(range.e.c,20)&&!date;c++)date=cellDate(ws,0,c);
  if(!date)continue;                                    // 「計算用」など日付のないシートは読まない
  const heads=[];
  for(let r=0;r<=range.e.r;r++)for(let c=0;c<=range.e.c;c++){const k=key(tx(ws,r,c));
   if(k==="品目"){const cols={};for(let cc=c+1;cc<=Math.min(c+10,range.e.c);cc++){const kk=key(tx(ws,r,cc));if(kk==="品目")break;if(LABELS[kk]&&cols[LABELS[kk]]===undefined)cols[LABELS[kk]]=cc}heads.push({r,c,cols})}
   else if(k==="納品先"){const cols={};for(let cc=c+1;cc<=Math.min(c+10,range.e.c);cc++){const kk=key(tx(ws,r,cc));if(kk==="品目"||kk==="納品先")break;if(LABELS[kk]&&cols[LABELS[kk]]===undefined)cols[LABELS[kk]]=cc}heads.push({r,c,cols,weight:true})}
  }
  let count=0;
  for(const h of heads){
   if(h.weight){count+=readWeight(ws,sn,date,h,heads,range,out);continue}
   if(h.cols.cs===undefined){out.skipped.push(`${sn}：${XLSX.utils.encode_cell({r:h.r,c:h.c})} の表（cs の列がありません）`);continue}
   let title="";for(const dr of [2,1,3]){const t=h.r-dr>=0?tx(ws,h.r-dr,h.c):"";if(t&&key(t)!=="品目"){title=t;break}}
   /* 2列に分けて書いてある客先（プライムの右半分など）は、同じ行の左にある客先名を使う */
   if(!title)for(const dr of [2,1]){if(h.r-dr<0)break;for(let cc=h.c-1;cc>=0&&!title;cc--){const t=tx(ws,h.r-dr,cc);if(t&&key(t)!=="品目")title=t}if(title)break}
   const next=heads.filter(x=>x.c===h.c&&x.r>h.r).map(x=>x.r-2);const end=next.length?Math.min(...next):range.e.r+1;
   for(let r=h.r+1;r<end;r++){
    const it=tx(ws,r,h.c);if(!it)continue;
    const cont=r+1<end&&!tx(ws,r+1,h.c);
    const q=[raw(ws,r,h.cols.cs),cont?raw(ws,r+1,h.cols.cs):undefined].filter(v=>v!==undefined&&v!==null&&N(v)!=="");
    const qtyRaw=q.map(v=>N(v)).join(" ");
    const qq=parseReportQty(qtyRaw);
    if(!qq)continue;                                     // 数がない＝出していない
    const o=h.cols.origin!==undefined?[tx(ws,r,h.cols.origin),cont?tx(ws,r+1,h.cols.origin):""].filter(Boolean).join(""):"";
    const cp=h.cols.coop!==undefined?[tx(ws,r,h.cols.coop),cont?tx(ws,r+1,h.cols.coop):""].filter(Boolean).join(""):"";
    const line={date,file:fileName,sheet:sn,cell:XLSX.utils.encode_cell({r,c:h.c}),customerRaw:title,raw:it,base:baseName(it),qtyRaw,origin:o,coop:cp,issues:[],
     boxes:qq.bad?null:qq.boxes,pack:qq.bad?null:qq.pack,kg:qq.bad?null:qq.kg,note:qq.override&&qq.calcKg!==qq.override?`合計${qq.override}kgと書いてあります（箱から計算すると${qq.calcKg}kg）`:""};
    if(qq.bad)line.issues.push("qty");if(!title)line.issues.push("customer");
    out.lines.push(line);count++;
   }
  }
  out.dates.add(date);out.sheets.push({sheet:sn,date,count});
 }
 if(out.dates.size>1)out.errors.push(`シートごとに納品日が違います（${[...out.dates].map(md).join("・")}）。同じ日の産地報告書か確かめてください。`);
 if(!out.dates.size)out.errors.push("1行目に納品日のあるシートがありません。産地報告書か確かめてください。");
 return out;
}

/* ---------- 取り込み ---------- */
let pend=null;
function c142ImportPage(){
 if(!canImport()){alert("取り込みは管理者・青果社員・事務員だけが使えます");return c140ShipPlanPage()}
 setScreen("c142ImportPage",[]);
 pageShell("産地報告書の取り込み（確定数量）","セット後、翌日に上書きされる前に取り込みます",`<div class="card">
  <input id="c142File" type="file" accept=".xlsx,.xls" style="display:none" ${seikaEventAttrs("change","c142ReadFile",[{__seikaElement:true}])}>
  <button class="btn c142Btn" style="width:100%" ${seikaEventAttrs("click","c142PickFile",[])}>産地報告書を選ぶ</button>
  <div class="small" style="margin-top:8px">納品日は産地報告書の1行目から読みます。確定数量を書き終えて保存してから選んでください。ファイルはこの端末の中で読み、サーバーには送りません。同じ納品日をもう一度取り込むと置き換わります（前の分は残ります）。</div></div>
  <button class="btn btn2" style="width:100%" ${seikaEventAttrs("click","c140ShipPlanPage",["",""])}>戻る</button>`);
}
function c142PickFile(){const f=document.getElementById("c142File");if(f){f.value="";f.click()}}
async function c142ReadFile(input){
 const f=input?.files?.[0];if(!f)return;
 if(typeof XLSX==="undefined")return alert("Excelの部品が読み込まれていません。");
 busy(true,"産地報告書を読み込んでいます");
 try{
  const wb=XLSX.read(await f.arrayBuffer(),{type:"array",cellDates:false});
  const rep=readReport(wb,f.name);
  const date=[...rep.dates][0]||"";
  const [m,plan,ca,actual]=await Promise.all([loadMasters(true),date?loadPlan(date).catch(()=>({active:null,lines:[]})):{active:null,lines:[]},qrSelect(T.calias,"select=*&limit=2000"),date?loadActual(date):null]);
  c142Prepare(rep,m,plan,ca||[],actual);
  return c142PreviewPage();
 }catch(e){alert(sqlMissing(e)?NEED_SQL:`産地報告書を読み込めませんでした。\n${e?.message||e}`)}finally{busy(false)}
}
/* 品目・客先を当てはめる（テストからも呼ぶ） */
function c142Prepare(rep,m,plan,calias,actual){
 const date=[...rep.dates][0]||"";
 const planCust=[...new Set((plan?.lines||[]).map(l=>l.customer_name||l.customer).filter(Boolean))].sort((a,b)=>a.localeCompare(b,"ja"));
 const cmap=new Map((calias||[]).map(a=>[a.raw_key,a.customer_name]));
 for(const l of rep.lines){
  const it=resolveItem(l.base,m);if(it){l.item=it.item;l.inMaster=it.inMaster}else{l.item="";l.inMaster=true;l.issues.push("item")}
  const ck=ckey(l.customerRaw);
  if(cmap.has(ck))l.customer=cmap.get(ck);
  else{const hit=planCust.find(c=>ckey(c)===ck);if(hit)l.customer=hit;else if(l.customerRaw){l.customer="";l.issues.push("cmap")}}
 }
 pend={...rep,date,planCust,plan,actual,m,picks:{},cpicks:{},kgFix:{},addAlias:{},addCAlias:{},importId:uuid()};
 return pend;
}
function effRaw(){
 const p=pend;if(!p)return[];
 return p.lines.map(l=>{const o={...l};
  if(l.issues.includes("item")){const pk=p.picks[key(l.base)];if(pk){o.item=pk.item;o.inMaster=pk.inMaster}}
  if(l.issues.includes("cmap")){const cp=p.cpicks[ckey(l.customerRaw)];if(cp)o.customer=cp.name}
  if(l.issues.includes("qty")&&p.kgFix[l.cell+"|"+l.sheet]>0)o.kg=p.kgFix[l.cell+"|"+l.sheet];
  if(o.kg===null&&o.boxes>0&&o.item){const sd=p.m?.std?.get(o.item);if(sd){o.kg=Math.round(o.boxes*sd*1000)/1000;o.pack=sd}}
  o.open=[];if(!o.item)o.open.push("品目");if(!o.customer)o.open.push("客先");if(l.issues.includes("qty")&&!(p.kgFix[l.cell+"|"+l.sheet]>0))o.open.push("数量");
  return o});
}
/* 重量の表の行（計量したkg）は、同じ客先・同じ品目（単協が同じものを先に）のケースの行の重さとして使い、重量の行そのものは出さない。
   ケースの行がないときは、重量の行をそのまま1行として使う。 */
function eff(){
 const ls=effRaw(),used=new Set;
 for(const w of ls.filter(l=>l.weight&&!l.open.length)){
  const cands=ls.filter(l=>!l.weight&&!l.open.length&&l.customer===w.customer&&l.item===w.item&&!used.has(l));
  const hit=cands.find(l=>w.coop&&key(l.coop).includes(key(w.coop).replace(/\(.*$/,"")))||cands[0];
  if(hit){used.add(hit);hit.note=`計量 ${num(w.kg)}kg（重量の表）。ケースからだと ${num(hit.kg)}kg`;hit.kg=w.kg;w.merged=true}
 }
 return ls.filter(l=>!l.merged);
}
function c142PreviewPage(){
 const p=pend;if(!p)return c142ImportPage();
 setScreen("c142PreviewPage",[]);
 const lines=eff(),open=lines.filter(l=>l.open.length),items=seikaItems();
 const errs=p.errors.length?`<div class="card err">${p.errors.map(e=>`<div>${esc(e)}</div>`).join("")}<div class="small">間違った数字で登録しないよう、ここで止めています。</div></div>`:"";
 if(p.errors.length||!p.lines.length)return pageShell("産地報告書の取り込み（確認）","",`${errs}${p.lines.length?"":'<div class="card err">確定数量の行が見つかりませんでした。</div>'}<button class="btn btn2" style="width:100%" ${seikaEventAttrs("click","c142ImportPage",[])}>選び直す</button>`);
 const sk=p.skipped.length?`<div class="card notice"><b>読まなかった表</b>${p.skipped.map(s=>`<div class="small">${esc(s)}</div>`).join("")}</div>`:"";
 const noPlan=!p.plan?.active?`<div class="card warn">この納品日（${md(p.date)}）の出荷予定（積み込み表）がまだ取り込まれていません。先に積み込み表を取り込むと、客先名を予定の客先から選べます。</div>`:"";
 const needC=new Map;for(const l of p.lines)if(l.issues.includes("cmap")){const k=ckey(l.customerRaw);if(!needC.has(k))needC.set(k,{raw:l.customerRaw,n:0});needC.get(k).n++}
 const cOpt=sel=>`<option value="">選んでください</option>${p.planCust.map(c=>`<option value="${esc(c)}" ${sel===c?"selected":""}>${esc(c)}</option>`).join("")}<option value="__raw__" ${sel==="__raw__"?"selected":""}>予定にない客先（この名前で保存）</option>`;
 const cCard=needC.size?`<div class="card warn"><b>要確認：積み込み表と書き方が違う客先（${needC.size}件）</b><div class="small">産地報告書の客先名が、この日の積み込み表のどの客先か選んでください。選んだ対応は「客先の読み替え」に追加され、次から自動で当てはまります。</div>
  ${[...needC].map(([k,v])=>{const cp=p.cpicks[k],sel=cp?(cp.raw?"__raw__":cp.name):"";return `<div style="border-top:1px solid #e2e8f0;margin-top:8px;padding-top:8px"><b>${esc(v.raw)}</b><span class="small">（${v.n}行）</span><div class="row" style="gap:8px;flex-wrap:wrap;margin-top:4px"><select style="font-size:16px;padding:6px;min-width:12em;max-width:100%" ${seikaEventAttrs("change","c142PickCustomer",[k,{__seikaValue:true}])}>${cOpt(sel)}</select>
   <label class="small"><input type="checkbox" ${p.addCAlias[k]!==false?"checked":""} ${seikaEventAttrs("change","c142ToggleCAlias",[k,{__seikaChecked:true}])}> 客先の読み替えに追加する</label></div></div>`}).join("")}</div>`:"";
 const needI=new Map;for(const l of p.lines)if(l.issues.includes("item")){const k=key(l.base);if(!needI.has(k))needI.set(k,{base:l.base,rows:[]});needI.get(k).rows.push(l)}
 const iOpt=sel=>`<option value="">選んでください</option>${items.map(x=>`<option value="${esc(x)}" ${sel===x?"selected":""}>${esc(x)}</option>`).join("")}<option value="__raw__" ${sel==="__raw__"?"selected":""}>SEIKA＋の品目にない（この名前で保存）</option>`;
 const iCard=needI.size?`<div class="card warn"><b>要確認：知らない品名（${needI.size}種類）</b><div class="small">品名読み替えマスタにない書き方です。推測はしません。「大根」などは取り違えないよう特に注意してください。</div>
  ${[...needI].map(([k,v])=>{const pk=p.picks[k],sel=pk?(pk.inMaster?pk.item:"__raw__"):"";return `<div style="border-top:1px solid #e2e8f0;margin-top:8px;padding-top:8px"><b>${esc(v.base)}</b><span class="small">（${v.rows.length}行：${esc([...new Set(v.rows.map(r=>r.raw))].slice(0,3).join("、"))}）</span><div class="row" style="gap:8px;flex-wrap:wrap;margin-top:4px"><select style="font-size:16px;padding:6px;min-width:12em" ${seikaEventAttrs("change","c142PickItem",[k,{__seikaValue:true}])}>${iOpt(sel)}</select>
   <label class="small"><input type="checkbox" ${p.addAlias[k]!==false?"checked":""} ${seikaEventAttrs("change","c142ToggleAlias",[k,{__seikaChecked:true}])}> 品名読み替えマスタに追加する</label></div></div>`}).join("")}</div>`:"";
 const qRows=lines.filter(l=>l.issues.includes("qty"));
 const qCard=qRows.length?`<div class="card warn"><b>要確認：数量の書き方が読めない行（${qRows.length}行）</b><div class="small">書き方を見て、合計のkgを入れてください。</div>${qRows.map(l=>`<div class="row" style="gap:8px;flex-wrap:wrap;align-items:center;border-top:1px solid #e2e8f0;margin-top:6px;padding-top:6px"><div style="flex:1;min-width:14em">${esc(l.customerRaw)}・${esc(l.raw)}<div class="small">書き方：「${esc(l.qtyRaw)}」・シート「${esc(l.sheet)}」${esc(l.cell)}</div></div><input type="number" inputmode="decimal" min="0" step="0.1" placeholder="kg" value="${esc(p.kgFix[l.cell+"|"+l.sheet]??"")}" style="width:7em;font-size:16px;padding:6px" ${seikaEventAttrs("change","c142FixKg",[l.cell+"|"+l.sheet,{__seikaValue:true}])}> kg</div>`).join("")}</div>`:"";
 const ready=lines.filter(l=>!l.open.length),byC=new Map;for(const l of ready){if(!byC.has(l.customer))byC.set(l.customer,[]);byC.get(l.customer).push(l)}
 const pl=new Map;for(const l of (p.plan?.lines||[])){const k=`${l.customer_name||l.customer}｜${l.item_name||l.item}`;pl.set(k,(pl.get(k)||0)+(Number(l.kg)||0))}
 const sum=`<div class="card"><b>客先ごとの確定数量（${byC.size}件）</b>${open.length?`<div class="small">要確認の行（${open.length}行）は入っていません。</div>`:""}${[...byC].map(([c,ls])=>`<details style="margin-top:6px"><summary style="font-weight:800;cursor:pointer">${esc(c)}<span class="small">（${ls.length}行）</span></summary><div style="overflow:auto"><table class="table" style="font-size:13px"><tr><th>品目</th><th>確定</th><th>予定</th></tr>${ls.map(l=>{const pk=pl.get(`${c}｜${l.item}`);const cs=casesOf(l.item,l.kg,l.pack,p.m);return `<tr><td>${esc(l.item)}<div class="small">${esc(l.raw)}・${esc([l.origin,l.coop].filter(Boolean).join("・"))}</div></td><td>${l.kg===null?`${num(l.boxes)}箱`:`${cs.cases!==null?`${cs.cases}ケース`:""}<span class="small">（${num(l.kg)}kg）</span>`}${l.note?`<div class="small">${esc(l.note)}</div>`:""}</td><td>${pk===undefined?'<span class="small">予定なし</span>':`<span class="small">${num(pk)}kg</span>`}${pk!==undefined&&l.kg!==null&&Math.abs(pk-l.kg)>0.001?'<span class="c142Diff">違い</span>':""}</td></tr>`}).join("")}</table></div></details>`).join("")}</div>`;
 const rep=p.actual?.active?`<div class="card notice">この納品日の確定数量は ${esc(String(p.actual.active.imported_at).slice(0,16).replace("T"," "))} に取り込み済みです。登録すると置き換わります（前の分は残ります）。</div>`:"";
 const ok=!open.length&&ready.length>0;
 pageShell("産地報告書の取り込み（確認）",`納品日 ${md(p.date)} ／ 出荷日 ${md(addDays(p.date,-1))}`,`<div class="card"><b>${esc(p.file||"")}</b>${p.sheets.map(s=>`<div class="small">シート「${esc(s.sheet)}」${s.count}行</div>`).join("")}
  <div class="row" style="margin-top:8px;flex-wrap:wrap"><div class="box">確定の行<b>${p.lines.length}</b></div><div class="box">要確認<b>${open.length}</b></div><div class="box">客先<b>${byC.size}</b></div></div></div>
  ${noPlan}${rep}${sk}${cCard}${iCard}${qCard}${sum}
  <div class="card">${ok?`<button class="btn green" style="width:100%" ${seikaEventAttrs("click","c142Save",[])}>この内容で確定数量を登録する（${ready.length}行）</button>`:`<div class="err">要確認の行（${open.length}行）を直すと登録できます。</div>`}
  <button class="btn btn2" style="width:100%;margin-top:8px" ${seikaEventAttrs("click","c142Cancel",[])}>登録せずに戻る</button></div>`);
}
function rer(){try{document.activeElement?.blur?.()}catch(_){}setTimeout(()=>{if(currentScreen==="c142PreviewPage")c142PreviewPage()},0)}
function c142PickCustomer(k,v){if(!pend)return;if(!v)delete pend.cpicks[k];else pend.cpicks[k]=v==="__raw__"?{name:pend.lines.find(l=>ckey(l.customerRaw)===k)?.customerRaw||k,raw:true}:{name:v,raw:false};return rer()}
function c142ToggleCAlias(k,on){if(pend)pend.addCAlias[k]=!!on}
function c142PickItem(k,v){if(!pend)return;if(!v)delete pend.picks[k];else pend.picks[k]=v==="__raw__"?{item:pend.lines.find(l=>key(l.base)===k)?.base||k,inMaster:false}:{item:v,inMaster:true};return rer()}
function c142ToggleAlias(k,on){if(pend)pend.addAlias[k]=!!on}
function c142FixKg(k,v){if(!pend)return;const n=Number(v);if(v===""||!(n>0))delete pend.kgFix[k];else pend.kgFix[k]=n;return rer()}
function c142Cancel(){const d=pend?.date;pend=null;return c140ShipPlanPage(d||"","")}
let saving=false;
async function c142Save(){
 const p=pend;if(!p||!canImport()||saving)return;
 const lines=eff();if(lines.some(l=>l.open.length))return alert("要確認の行が残っています。");
 saving=true;busy(true,"確定数量を登録しています");
 try{
  for(const [k,pk] of Object.entries(p.picks)){if(p.addAlias[k]===false)continue;const base=p.lines.find(l=>key(l.base)===k)?.base||k;
   await callRpc("save_ship_plan_alias_v1199c140",{p_key:k,p_raw:base,p_item:pk.item,p_in_master:pk.inMaster})}
  for(const [k,cp] of Object.entries(p.cpicks)){if(p.addCAlias[k]===false)continue;const rawName=p.lines.find(l=>ckey(l.customerRaw)===k)?.customerRaw||k;
   await callRpc("save_ship_customer_alias_v1199c142",{p_key:k,p_raw:rawName,p_customer:cp.name})}
  const payload=lines.map(l=>({customer_raw:l.customerRaw,customer_name:l.customer,customer_norm:key(l.customer),item_name:l.item,item_in_master:l.inMaster!==false,item_raw:l.raw,
   origin:l.origin,coop:l.coop,qty_raw:l.qtyRaw,boxes:l.boxes,pack_kg:l.pack,kg:l.kg,note:l.note||"",source_sheet:l.sheet,source_cell:l.cell}));
  const a=await callRpc("replace_ship_actual_v1199c142",{p_import_id:p.importId,p_delivery_date:p.date,p_file:p.file||"",p_sheets:p.sheets,p_lines:payload});
  if(a&&a.ok===false)throw new Error(a.message||"登録できませんでした");
  const d=p.date;pend=null;
  await c140ShipPlanPage(d,`納品日 ${md(d)} の確定数量を${a?.count??payload.length}行で登録しました${a?.replaced?"（前の取り込みは置き換え済みとして残しました）":""}。`);
 }catch(e){alert(sqlMissing(e)?NEED_SQL:`登録できませんでした。\n${e?.message||e}`)}
 finally{saving=false;busy(false)}
}
async function c142DeleteCustomerAlias(k,name){
 if(!canAdmin()||!confirm(`「${name}」の客先の読み替えを削除します。よろしいですか？`))return;
 try{await callRpc("delete_ship_customer_alias_v1199c142",{p_key:k});await c140AliasPage(`「${name}」の客先の読み替えを削除しました。`)}catch(e){alert(e?.message||e)}
}
Object.assign(window,{c142ImportPage,c142PickFile,c142ReadFile,c142Prepare,c142PreviewPage,c142PickCustomer,c142ToggleCAlias,c142PickItem,c142ToggleAlias,c142FixKg,c142Cancel,c142Save,c142DeleteCustomerAlias,
 c142Parse:{parseReportQty,readReport,ckey}});

/* ---------- 操作ガイド ---------- */
try{
 const g={title:"産地報告書から確定数量を取り込む",where:"ホーム →「出荷予定（積み込み表）」→「産地報告書を取り込む（確定数量）」",
  steps:["セットが終わり、産地報告書に確定数量を書いて保存したら取り込みます（翌日に次の日の分で上書きされる前に）。",
   "「産地報告書を選ぶ」でファイルを選びます。納品日は産地報告書の1行目から読みます。シートごとに日付が違うときは止まります。",
   "確認画面に、積み込み表と書き方が違う客先・知らない品名・読めない数量が「要確認」で出ます。客先はこの日の積み込み表の客先から選びます（選んだ対応は次から自動で当てはまります）。",
   "「この内容で確定数量を登録する」を押します。出荷予定の画面に「予定」と「確定」が並び、kgが違う品目に「違い」が付きます。"],
  check:"規格だけ書いてあって数のない行は、出していないものとして読みません。「重量」の表（レタスを計量して出す客先）は、計量したkgをその客先のレタスの重さとして使います。",
  caution:"確定数量があるのは産地報告書にある社外の客先だけです。埼玉・深谷・本社はQR出庫と伝票で確認します。"};
 if(typeof V195_ROLE_GUIDES!=="undefined")for(const r of ["admin","worker","clerk"]){const gg=V195_ROLE_GUIDES[r];if(gg&&Array.isArray(gg.sections)&&!gg.sections.some(x=>x&&x.title===g.title))gg.sections.push(g)}
}catch(e){}
})();
