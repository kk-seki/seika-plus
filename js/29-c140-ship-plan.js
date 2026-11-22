/* ===== v1.199-c140 出荷予定の取り込み（積み込み表） =====
   ・積み込み表（月ごとのExcel・納品日ごとのシート・同じ月に2ファイル）から、選んだ納品日のシートを読み、客先×品目の数量を保存する（SQL 061）。
   ・Excelは端末の中で読む（ファイルはサーバーへ送らない）。積み込み表は見出しのない決まった形（5列×3ブロック：品名・数量・単位・メモ・番号）。
     形が違う（納品日・単位の列が見つからない）ときは、間違った数字で登録せず「この形は読めません」で止める。
   ・数量：「12」＝品名の規格のケース数（キャベツ 10kg × 12）、「15kg*4」＝15kgの箱4つ、「15kg*3,5kg*1」＝合計、単位が kg ならそのままkg。
   ・品名は「品名読み替えマスタ」でSEIKA＋の品目に置き換える。マスタにない品名は推測しない（要確認 → 確認画面で選ぶ・マスタに追加）。
   ・ケース数＝kg ÷ 標準ケース（マスタ。なければ積み込み表の1箱の重さ）を切り上げ。割り切れないときは「端数あり」。
     全客先を合わせても10kg以下の品目は、ケースではなく重さ（kg・g）で表示する。
   ・出荷日＝納品日の前日。同じ納品日をもう一度取り込んだら置き換え（前の分は「置き換え済み」で残る）。
   ・取り込み：管理者・青果社員・事務員。見る：石岡の役割（営業・仕入れ担当者を含む）。
   ・c141：ファイルに入っている何日分もまとめて取り込む（はじめは明日以降の日。中身が変わらない日は登録し直さない。1日ずつ順に登録し、途中で止まっても続きから）。 */
(()=>{
const IMPORT_ROLES=["admin","worker","clerk"],VIEW_ROLES=["admin","worker","buyer","sales","clerk","office_viewer","viewer"];
const SMALL_KG=10;
const T={imp:"ship_plan_imports_v1199c140",line:"ship_plan_lines_v1199c140",alias:"ship_plan_item_aliases_v1199c140",std:"ship_plan_case_std_v1199c140",aimp:"ship_actual_imports_v1199c142",aline:"ship_actual_lines_v1199c142",calias:"ship_customer_aliases_v1199c142"};
const sqlMissing=e=>/PGRST202|PGRST205|schema cache|does not exist|404|_v1199c140/.test(String(e?.message||e||""));
const NEED_SQL="この機能の準備がまだです（SQL 061 の実行が必要です）。";
const canImport=()=>IMPORT_ROLES.includes(db?.role);
const canView=()=>VIEW_ROLES.includes(db?.role);
const N=v=>String(v??"").normalize("NFKC").trim();
const key=v=>N(v).replace(/\s+/g,"").toLowerCase();
function busy(on,msg){try{on?v161ShowProcessing?.(msg||"処理しています"):v161HideProcessing?.()}catch(_){}}
function addDays(k,d){const t=new Date(k+"T00:00:00+09:00");t.setDate(t.getDate()+d);return ymdKey(t)}
function md(k){const t=new Date(k+"T00:00:00+09:00");return `${t.getMonth()+1}/${t.getDate()}（${"日月火水木金土"[t.getDay()]}）`}
function num(v){const s=Math.round(Number(v)*100)/100;return s.toLocaleString("ja-JP")}

/* ---------- 読み取り（純粋な関数。テストでも使う） ---------- */
function unitOf(v){const s=key(v).replace(/[ｃ]/g,"c");if(s==="cs"||s==="c/s")return"cs";if(s==="kg")return"kg";if(s==="p/c"||s==="pc")return"pc";return""}
function specKg(name){const m=[...N(name).toLowerCase().matchAll(/(\d+(?:\.\d+)?)\s*kg/g)];return m.length?Number(m[m.length-1][1]):null}
function baseName(name){
 let s=N(name).replace(/^※/,"");
 s=s.replace(/【[^】]*】/g,"").replace(/\([^)]*\)/g,"");
 s=s.replace(/\d+(?:\.\d+)?\s*(?:kg|g)\b/gi,"").replace(/\d+(?:\.\d+)?\s*kg/gi,"");
 s=s.replace(/[A-Za-z0-9\/・.\-\s]+$/,"").trim();
 return s.replace(/[\s\/]+$/,"")||N(name);
}
/* 数量：{kind:"n",n} 数字だけ ／ {kind:"mix",kg,boxes,pack} 「15kg*3,5kg*1」 ／ {kind:"bad"} 読めない ／ null 空 */
function parseQty(v){
 if(v===null||v===undefined||N(v)==="")return null;
 if(typeof v==="number")return Number.isFinite(v)?{kind:"n",n:v}:{kind:"bad"};
 const s=N(v).toLowerCase().replace(/\s/g,"").replace(/[×x＊]/g,"*").replace(/[、，]/g,",");
 if(/^\d+(\.\d+)?$/.test(s))return{kind:"n",n:Number(s)};
 let kg=0,boxes=0;const packs=new Set;
 for(const p of s.split(",")){const m=p.match(/^(\d+(?:\.\d+)?)kg\*(\d+(?:\.\d+)?)$/);if(!m)return{kind:"bad"};kg+=Number(m[1])*Number(m[2]);boxes+=Number(m[2]);packs.add(Number(m[1]))}
 return{kind:"mix",kg:Math.round(kg*1000)/1000,boxes,pack:packs.size===1?[...packs][0]:null};
}
function cellV(ws,r,c){const x=ws[XLSX.utils.encode_cell({r,c})];return x?x.v:undefined}
function cellDate(ws,r,c){const x=ws[XLSX.utils.encode_cell({r,c})];if(!x)return"";
 if(x.v instanceof Date)return ymdKey(x.v);
 if(typeof x.v==="number"&&x.v>30000&&x.v<80000){const d=XLSX.SSF.parse_date_code(x.v);if(d)return `${d.y}-${String(d.m).padStart(2,"0")}-${String(d.d).padStart(2,"0")}`}
 if(typeof x.v==="string"){const m=N(x.v).match(/^(\d{4})[\/\-](\d{1,2})[\/\-](\d{1,2})/);if(m)return `${m[1]}-${m[2].padStart(2,"0")}-${m[3].padStart(2,"0")}`}
 return"";
}
const COLS=["A","F","K"];
/* 1枚のシートを読む。戻り値：{date, lines:[...], ok, why} */
function readSheet(ws,fileName,sheetName){
 const date=cellDate(ws,0,1);
 if(!ws["!ref"])return{date,lines:[],ok:false,why:"シートが空です"};
 const range=XLSX.utils.decode_range(ws["!ref"]);
 const merged=new Map;(ws["!merges"]||[]).forEach(m=>merged.set(`${m.s.r},${m.s.c}`,{rows:m.e.r-m.s.r+1,cols:m.e.c-m.s.c+1}));
 const lines=[];let unitCells=0;
 [0,5,10].forEach((c0,bi)=>{
  let cust="",route="";
  for(let r=1;r<=range.e.r;r++){
   const rawName=cellV(ws,r,c0),q=cellV(ws,r,c0+1),u=unitOf(cellV(ws,r,c0+2)),note=N(cellV(ws,r,c0+3)??"");
   if(u)unitCells++;
   const nameOk=rawName!==undefined&&rawName!==null&&typeof rawName!=="number"&&!(rawName instanceof Date)&&N(rawName)!=="";
   if(!nameOk)continue;
   const name=N(rawName);
   const base={file:fileName,sheet:sheetName,row:r+1,col:COLS[bi],route,customer:cust,raw:name,base:baseName(name),qtyRaw:q===undefined?"":String(q),note,issues:[]};
   if(u){
    const qq=parseQty(q);
    if(!qq||(qq.kind==="n"&&qq.n===0))continue;
    const spec=specKg(name);let kg=null,boxes=null,pack=null;
    if(qq.kind==="bad")base.issues.push("qty");
    else if(u==="kg"){kg=qq.kind==="n"?qq.n:qq.kg}
    else if(qq.kind==="n"){boxes=qq.n;pack=spec;kg=spec?Math.round(spec*qq.n*1000)/1000:null}
    else{boxes=qq.boxes;pack=qq.pack;kg=qq.kg}
    lines.push({...base,unit:u,boxes,pack,kg,spec});
    continue;
   }
   if(name.startsWith("※")||name.startsWith("/"))continue;
   const m=merged.get(`${r},${c0}`);
   if(m&&m.rows>=2&&m.cols>=4){route=name;cust="";continue}
   if(m&&m.cols>=3){if(/引き?取り/.test(name)||/便$/.test(name))route=name;else cust=name;continue}
   const qq=parseQty(q);
   if(qq&&!(qq.kind==="n"&&qq.n===0)){lines.push({...base,unit:"",boxes:null,pack:null,kg:null,spec:specKg(name),issues:["unit"]});continue}
   cust=name;
  }
 });
 for(const l of lines)if(!l.customer)l.issues.push("customer");
 return{date,lines,ok:!!date&&unitCells>0,why:!date?"B1に納品日がありません":unitCells?"":"単位（cs・kg）の列が見つかりません"};
}
/* ブック（複数）から納品日のシートを探して読む */
function readBooks(books,dateKey){
 const out={lines:[],sheets:[],errors:[]};
 for(const {wb,name} of books){
  let found=null;
  for(const sn of wb.SheetNames){const d=cellDate(wb.Sheets[sn],0,1);if(d===dateKey){found=sn;break}}
  if(!found){out.errors.push(`${name}：納品日 ${md(dateKey)} のシートが見つかりません（シートのB1の日付で探しています）`);continue}
  const res=readSheet(wb.Sheets[found],name,found);
  if(!res.ok){out.errors.push(`${name}（シート ${found}）：この形は読めません。${res.why}`);continue}
  out.sheets.push({file:name,sheet:found,count:res.lines.length});out.lines.push(...res.lines);
 }
 return out;
}

/* ---------- マスタ ---------- */
let masters=null;
async function loadMasters(force=false){
 if(masters&&!force)return masters;
 const [al,st]=await Promise.all([qrSelect(T.alias,"select=*&limit=5000"),qrSelect(T.std,"select=*&limit=1000")]);
 masters={alias:new Map((al||[]).map(a=>[a.raw_key,a])),std:new Map((st||[]).map(s=>[s.item_name,Number(s.case_kg)])),aliasRows:al||[],stdRows:st||[]};
 return masters;
}
function seikaItems(){
 const set=new Map;
 const add=n=>{const s=String(n||"").trim();if(s&&!set.has(key(s)))set.set(key(s),s)};
 try{qrAllowedItemNames().forEach(add)}catch(_){}
 try{activeItems().forEach(i=>add(i?.name))}catch(_){}
 /* 通常在庫の「その他」などの品目（トレビスなど）も選べるようにする */
 try{Object.keys(SPECIAL_STOCK_TABLES).forEach(t=>specialItems(t).forEach(i=>add(i?.name)))}catch(_){}
 return[...set.values()].sort((a,b)=>a.localeCompare(b,"ja"));
}
/* 品名 → SEIKA＋の品目。アリアス → 品目名と同じ名前（そのまま） → なし（要確認） */
function resolveItem(base,m){
 const k=key(base),a=m?.alias?.get(k);
 if(a)return{item:a.item_name,inMaster:a.in_master!==false,how:"alias"};
 const hit=seikaItems().find(x=>key(x)===k);
 if(hit)return{item:hit,inMaster:true,how:"same"};
 return null;
}
function casesOf(item,kg,pack,m){
 const std=(m?.std?.get(item))||(pack>0?pack:null);
 if(kg===null||kg===undefined||!std)return{std:std||null,exact:null,cases:null,frac:false};
 const exact=Math.round(kg/std*10000)/10000,cases=Math.ceil(exact-0.00001);
 return{std,exact,cases,frac:exact!==cases};
}
function uuid(){if(window.crypto?.randomUUID)return crypto.randomUUID();const b=new Uint8Array(16);crypto.getRandomValues(b);b[6]=b[6]&15|64;b[8]=b[8]&63|128;const h=[...b].map(x=>x.toString(16).padStart(2,"0")).join("");return `${h.slice(0,8)}-${h.slice(8,12)}-${h.slice(12,16)}-${h.slice(16,20)}-${h.slice(20)}`}
function weightText(kg){return kg<1?`${Math.round(kg*1000)}g`:`${num(kg)}kg`}
/* 品目ごとの合計（少量は重さで表示） */
function itemTotals(lines,m){
 const by=new Map;
 for(const l of lines){if(!l.item)continue;const o=by.get(l.item)||{item:l.item,kg:0,unknown:0,cases:0,frac:false,inMaster:l.inMaster,lines:0};
  o.lines++;if(l.kg===null||l.kg===undefined)o.unknown++;else o.kg+=l.kg;by.set(l.item,o)}
 for(const o of by.values()){o.kg=Math.round(o.kg*1000)/1000;o.small=o.kg<=SMALL_KG;const c=casesOf(o.item,o.kg,null,m);o.std=c.std;o.cases=c.cases;o.frac=c.frac;
  o.lineCases=0;o.noCase=0;for(const l of lines)if(l.item===o.item){const lc=casesOf(l.item,l.kg,l.pack,m);if(lc.cases)o.lineCases+=lc.cases;else if(l.kg!==null&&l.kg!==undefined)o.noCase++;if(lc.frac)o.frac=true}
  /* 標準ケースのない品目は、書いてある箱の重さ×箱数のまま（例：5kg×120、6kg×100）。合計はkgで、箱は重さごとに分けて出す */
  o.noStd=!m?.std?.get(o.item);o.packs=packBreakdown(lines.filter(l=>l.item===o.item))}
 return[...by.values()].sort((a,b)=>a.item.localeCompare(b.item,"ja"));
}
function qtyText(l,tot,m){
 if(l.kg===null||l.kg===undefined)return l.boxes?`${num(l.boxes)}箱（重さ不明）`:"－";
 if(tot?.small)return weightText(l.kg);
 const c=casesOf(l.item,l.kg,l.pack,m);
 return c.cases!==null?`${c.cases}ケース${c.frac?'<span class="c140Frac">端数あり</span>':""}<span class="small">（${num(l.kg)}kg）</span>`:`${num(l.kg)}kg`;
}
/* 箱の内訳：{"5":120,"8":14,"":17}（"" は1行に重さが混ざっている箱） */
function packBreakdown(ls){const mp=new Map;for(const l of ls){if(!(l.boxes>0))continue;const k=l.pack>0?String(Number(l.pack)):"";mp.set(k,(mp.get(k)||0)+Number(l.boxes))}return mp}
function packText(mp){return [...mp].sort((a,b)=>(a[0]===""?1:0)-(b[0]===""?1:0)||Number(b[0])-Number(a[0])).map(([k,n])=>k?`${num(k)}kg×${num(n)}`:`重さ混在${num(n)}箱`).join("・")}
function totalText(o){
 if(o.small)return `<b>${weightText(o.kg)}</b><span class="small">（少量のため重さ）</span>`;
 const cs=o.lineCases||o.cases;
 if(o.noStd&&o.packs?.size)return `<b>${num(o.kg)}kg</b><span class="small">（${packText(o.packs)}）</span>`;
 return cs?`<b>${cs}ケース</b>${o.frac?'<span class="c140Frac">端数あり</span>':""}<span class="small">（${num(o.kg)}kg${o.std?`・1ケース${num(o.std)}kg`:""}${o.unknown?`・重さ不明${o.unknown}行`:""}）</span>`:`<b>${num(o.kg)}kg</b>${o.unknown?`<span class="small">（重さ不明${o.unknown}行）</span>`:""}`;
}


/* ---------- 保存済みの出荷予定 ---------- */
async function loadPlan(dateKey){
 const imps=await qrSelect(T.imp,`select=*&delivery_date=eq.${dateKey}&order=imported_at.desc&limit=20`);
 const act=(imps||[]).find(i=>i.status==="active")||null;
 const lines=act?await qrSelect(T.line,`select=*&import_id=eq.${act.id}&order=line_no.asc&limit=5000`):[];
 return{imports:imps||[],active:act,lines:(lines||[]).map(l=>({...l,item:l.item_name,inMaster:l.item_in_master,kg:l.kg===null?null:Number(l.kg),pack:l.pack_kg===null?null:Number(l.pack_kg),customer:l.customer_name}))};
}
/* c142：確定数量（産地報告書）。表がまだない（SQL 062 前）ときは null */
async function loadActual(dateKey){
 try{
  const imps=await qrSelect(T.aimp,`select=*&delivery_date=eq.${dateKey}&order=imported_at.desc&limit=20`);
  const act=(imps||[]).find(i=>i.status==="active")||null;
  const lines=act?await qrSelect(T.aline,`select=*&import_id=eq.${act.id}&order=line_no.asc&limit=5000`):[];
  return{imports:imps||[],active:act,lines:(lines||[]).map(l=>({...l,item:l.item_name,customer:l.customer_name,kg:l.kg===null?null:Number(l.kg),pack:l.pack_kg===null?null:Number(l.pack_kg)}))};
 }catch(e){return null}
}
function sumBy(lines){const mp=new Map;for(const l of lines){const k=`${l.customer}｜${l.item}`;const o=mp.get(k)||{customer:l.customer,item:l.item,kg:0,unknown:0,lines:[]};if(l.kg===null||l.kg===undefined)o.unknown++;else o.kg+=l.kg;o.lines.push(l);mp.set(k,o)}for(const o of mp.values())o.kg=Math.round(o.kg*1000)/1000;return mp}
function shortQty(o,small,m){
 if(!o)return'<span class="small">－</span>';
 if(small)return weightText(o.kg);
 let cs=0,frac=false,unk=false;for(const l of o.lines){const c=casesOf(l.item,l.kg,l.pack,m);if(c.cases===null)unk=true;else{cs+=c.cases;if(c.frac)frac=true}}
 if(!m?.std?.get(o.item)){const pb=packBreakdown(o.lines);return `${num(o.kg)}kg${pb.size?`<span class="small">（${packText(pb)}）</span>`:""}`}  // 標準ケースのない品目は、書いてある箱の重さ×箱数のまま・kgで比べる
 return unk&&!cs?`${num(o.kg)}kg`:`${cs}ケース${frac?'<span class="c140Frac">端数あり</span>':""}<span class="small">（${num(o.kg)}kg）</span>`;
}
let viewDate="";
async function c140ShipPlanPage(dateKey="",msg=""){
 if(!canView()){alert("出荷予定を見る権限がありません");return home()}
 viewDate=dateKey||viewDate||addDays(todayKey(),1);
 setScreen("c140ShipPlanPage",[viewDate,msg]);
 pageShell("出荷予定（積み込み表）","読み込んでいます",'<div class="card"><div class="notice">読み込んでいます。</div></div>');
 let plan,m,actual;
 try{[plan,m,actual]=await Promise.all([loadPlan(viewDate),loadMasters(true),loadActual(viewDate)])}
 catch(e){return pageShell("出荷予定（積み込み表）","",`<div class="err">${esc(sqlMissing(e)?NEED_SQL:(e?.message||e))}</div><button class="btn btn2" style="width:100%" ${seikaEventAttrs("click","home",[])}>ホームへ</button>`)}
 if(currentScreen!=="c140ShipPlanPage")return;
 const d=viewDate,nav=`<div class="row" style="gap:8px;flex-wrap:wrap;align-items:center"><button class="btn btn2" ${seikaEventAttrs("click","c140ShipPlanPage",[addDays(d,-1),""])}>前の日</button><input id="c140Date" type="date" value="${esc(d)}" ${seikaEventAttrs("change","c140ShipPlanPage",[{__seikaValue:true},""])} style="font-size:18px;padding:6px"><button class="btn btn2" ${seikaEventAttrs("click","c140ShipPlanPage",[addDays(d,1),""])}>次の日</button></div>
  <div class="small" style="margin-top:6px">納品日 <b>${md(d)}</b> ／ 出荷日（セット日） <b>${md(addDays(d,-1))}</b></div>`;
 const tools=canImport()?`<button class="btn c140Btn" style="width:100%;margin-top:10px" ${seikaEventAttrs("click","c140ImportPage",[d])}>積み込み表を取り込む（予定）</button>${typeof window.c142ImportPage==="function"?`<button class="btn c142Btn" style="width:100%;margin-top:8px" ${seikaEventAttrs("click","c142ImportPage",[])}>産地報告書を取り込む（確定数量）</button>`:""}<button class="btn btn2" style="width:100%;margin-top:8px" ${seikaEventAttrs("click","c140AliasPage",[""])}>品名・客先の読み替え・標準ケース</button>`:"";
 const hasA=!!actual?.active,act=hasA?actual.lines:[];
 const stamp=(i)=>`${esc(String(i.imported_at).slice(0,16).replace("T"," "))}（${esc(i.imported_by_name||"-")}）`;
 const status=`<div class="card"><div><b>予定（積み込み表）：</b>${plan.active?`${stamp(plan.active)}・${plan.active.line_count}行`:"まだ取り込まれていません"}</div>
  ${actual?`<div style="margin-top:4px"><b>確定（産地報告書）：</b>${hasA?`${stamp(actual.active)}・${actual.active.line_count}行`:"まだ取り込まれていません"}</div>`:""}
  ${plan.active?`<div class="small">${(plan.active.files||[]).map(f=>`${esc(f.file)}（シート ${esc(f.sheet)}）`).join("、")}</div>`:""}</div>`;
 let body="";
 if(plan.active||hasA){
  const P=plan.lines,pt=itemTotals(P,m),at=itemTotals(act,m),ptm=new Map(pt.map(o=>[o.item,o])),atm=new Map(at.map(o=>[o.item,o]));
  /* 確定があるのは産地報告書の客先（社外）だけ。比べるのは、確定のある客先の予定だけにする（埼玉・深谷などは除く） */
  const aCust=new Set(act.map(l=>l.customer)),pc=itemTotals(P.filter(l=>aCust.has(l.customer)),m),pcm=new Map(pc.map(o=>[o.item,o]));
  const items=[...new Set([...pt.map(o=>o.item),...at.map(o=>o.item)])].sort((a,b)=>a.localeCompare(b,"ja"));
  const small=it=>((ptm.get(it)?.kg||0)<=SMALL_KG&&(atm.get(it)?.kg||0)<=SMALL_KG);
  const diffMark=(p,a)=>hasA&&plan.active&&Math.abs((p?.kg||0)-(a?.kg||0))>0.001?'<span class="c142Diff">違い</span>':"";
  const cmpNote=it=>{const p=ptm.get(it),q=pcm.get(it);if(!hasA||!p||Math.abs((p.kg||0)-(q?.kg||0))<0.001)return"";return `<div class="small">確定のある客先の予定：${q?totalText(q):"なし"}</div>`};
  const tot=`<div class="card"><b>品目ごとの合計（${items.length}品目）</b><div style="overflow:auto"><table class="table" style="font-size:14px"><tr><th>品目</th><th>予定</th>${hasA?"<th>確定</th>":""}</tr>${items.map(it=>{const p=ptm.get(it),a=atm.get(it);return `<tr><td>${esc(it)}${diffMark(pcm.get(it),a)}</td><td>${p?totalText(p):"－"}${cmpNote(it)}</td>${hasA?`<td>${a?totalText(a):"－"}</td>`:""}</tr>`}).join("")}</table></div>
   <div class="small">ケース数は、1行ずつ標準ケースで割って切り上げた数の合計です。全客先を合わせて${SMALL_KG}kg以下の品目は、ケースではなく重さで出します。${hasA?"「違い」は、確定のある客先（産地報告書にある社外の客先）の予定と確定のkgが違う品目です。埼玉・深谷など確定のない客先は比べません。比べるのはkgです（1箱の重さが違うとケースの数は変わるため）。標準ケースのない品目は、書いてある箱の重さ×箱数（例：5kg×120）のまま出し、合計はkgで比べます。":""}</div></div>`;
  const ps=sumBy(P),as=sumBy(act),custs=new Map;
  for(const o of [...ps.values(),...as.values()]){if(!custs.has(o.customer))custs.set(o.customer,new Set);custs.get(o.customer).add(o.item)}
  const route=c=>P.find(l=>l.customer===c)?.route||"";
  const cust=`<div class="card"><b>客先ごと（${custs.size}件）</b>${[...custs].map(([c,its])=>{const rows=[...its].sort((a,b)=>a.localeCompare(b,"ja")).map(it=>{const p=ps.get(`${c}｜${it}`),a=as.get(`${c}｜${it}`);
    const raw=(p?.lines||[]).map(l=>`${l.item_raw}${l.qty_raw?`（${l.qty_raw}）`:""}`).join("、"),orig=(a?.lines||[]).map(l=>[l.origin,l.coop].filter(Boolean).join("・")).filter(Boolean).join("、");
    return `<tr><td>${esc(it)}${aCust.has(c)?diffMark(p,a):""}<div class="small">${esc(raw)}</div></td><td>${shortQty(p,small(it),m)}</td>${hasA?`<td>${shortQty(a,small(it),m)}${orig?`<div class="small">${esc(orig)}</div>`:""}</td>`:""}</tr>`}).join("");
    const nd=hasA&&plan.active&&aCust.has(c)?[...its].filter(it=>Math.abs((ps.get(`${c}｜${it}`)?.kg||0)-(as.get(`${c}｜${it}`)?.kg||0))>0.001).length:0;
    return `<details style="margin-top:6px"><summary style="font-weight:800;cursor:pointer">${esc(c)}<span class="small">（${its.size}品目${route(c)?`・${esc(route(c))}`:""}${nd?`・違い${nd}`:""}）</span></summary><div style="overflow:auto"><table class="table" style="font-size:13px"><tr><th>品目</th><th>予定</th>${hasA?"<th>確定</th>":""}</tr>${rows}</table></div></details>`}).join("")}</div>`;
  body=tot+cust;
 }else body=`<div class="card notice">この納品日の出荷予定はまだ取り込まれていません。</div>`;
 const old=[...plan.imports.filter(i=>i.status==="replaced").map(i=>["予定",i]),...(actual?.imports||[]).filter(i=>i.status==="replaced").map(i=>["確定",i])];
 const hist=old.length?`<div class="card"><details><summary style="font-weight:800;cursor:pointer">前の取り込み（置き換え済み・${old.length}件）</summary>${old.map(([k,i])=>`<div class="small">${k}：${stamp(i)}・${i.line_count}行・${num(i.total_kg)}kg</div>`).join("")}</details></div>`:"";
 pageShell("出荷予定（積み込み表）","客先ごとの出荷予定と確定数量",`${okHtml(msg)}<div class="card">${nav}${tools}</div>${status}${body}${hist}`);
}

/* ---------- 取り込み（c141：ファイルに入っている何日分もまとめて） ---------- */
let pending=null;
function c140ImportPage(dateKey=""){
 if(!canImport()){alert("取り込みは管理者・青果社員・事務員だけが使えます");return c140ShipPlanPage()}
 setScreen("c140ImportPage",[dateKey]);
 pageShell("積み込み表の取り込み","その月の積み込み表を選ぶと、入っている納品日が一覧で出ます",`<div class="card">
  <input id="c140Files" type="file" accept=".xlsx,.xls" multiple style="display:none" ${seikaEventAttrs("change","c140ReadFiles",[{__seikaElement:true}])}>
  <button class="btn c140Btn" style="width:100%" ${seikaEventAttrs("click","c140PickFiles",[])}>積み込み表を選ぶ（同じ月の2ファイル）</button>
  <div class="small" style="margin-top:8px">2つのファイルを一度に選びます（スマホは長押しで複数選べます）。ファイルの中の何日分もまとめて取り込めます。はじめは明日以降の納品日が選ばれていて、中身が変わらない日は登録し直しません。ファイルはこの端末の中で読み、サーバーには送りません。積み込み表は保存してから選んでください。</div></div>
  <button class="btn btn2" style="width:100%" ${seikaEventAttrs("click","c140ShipPlanPage",[dateKey,""])}>戻る</button>`);
}
function c140PickFiles(){const f=document.getElementById("c140Files");if(f){f.value="";f.click()}}
async function c140ReadFiles(input){
 const files=[...(input?.files||[])];if(!files.length)return;
 if(typeof XLSX==="undefined")return alert("Excelの部品が読み込まれていません。");
 busy(true,"積み込み表を読み込んでいます");
 try{
  const books=[];for(const f of files)books.push({name:f.name,wb:XLSX.read(await f.arrayBuffer(),{type:"array",cellDates:false})});
  const dates=listDates(books);
  if(!dates.length)return alert("積み込み表の形のシートが見つかりませんでした（シートのB1に納品日がありません）。ファイルを確かめてください。");
  const [m,cur]=await Promise.all([loadMasters(true),loadPlans(dates.map(d=>d.date))]);
  c140Prepare(books,null,m,cur);
  return c140PreviewPage();
 }catch(e){alert(sqlMissing(e)?NEED_SQL:`積み込み表を読み込めませんでした。\n${e?.message||e}`)}finally{busy(false)}
}
/* ブックに入っている納品日（シートのB1）の一覧。2ファイルのどちらかにしかない日は missing に名前が入る */
function listDates(books){
 const by=new Map;
 for(const {wb,name} of books)for(const sn of wb.SheetNames){const d=cellDate(wb.Sheets[sn],0,1);if(!d)continue;if(!by.has(d))by.set(d,new Set);by.get(d).add(name)}
 return[...by].sort((a,b)=>a[0]<b[0]?-1:1).map(([date,fs])=>({date,files:[...fs],missing:books.map(b=>b.name).filter(n=>!fs.has(n))}));
}
/* 保存済みの出荷予定（今有効なもの）を何日分もまとめて読む：日付 → {active, lines} */
async function loadPlans(dates){
 const out=new Map(dates.map(d=>[d,{active:null,lines:[]}]));if(!dates.length)return out;
 const imps=await qrSelect(T.imp,`select=*&status=eq.active&delivery_date=in.(${dates.join(",")})&limit=500`);
 const ids=(imps||[]).map(i=>i.id);
 const lines=ids.length?await qrSelect(T.line,`select=*&import_id=in.(${ids.join(",")})&order=line_no.asc&limit=50000`):[];
 for(const i of imps||[])out.set(i.delivery_date,{active:i,lines:[]});
 const byId=new Map((imps||[]).map(i=>[i.id,i.delivery_date]));
 for(const l of lines||[]){const d=byId.get(l.import_id);if(d&&out.has(d))out.get(d).lines.push({...l,item:l.item_name,customer:l.customer_name,kg:l.kg===null?null:Number(l.kg)})}
 return out;
}
const lk=l=>`${l.file}|${l.sheet}|${l.col}${l.row}`;
/* 読んだ行に品目・ケースを付ける（テストからも呼ぶ）。dateKey を渡すとその日だけ選ぶ（なければ明日以降の日を選ぶ） */
function c140Prepare(books,dateKey,m,cur){
 masters=m||masters;
 const dates=listDates(books),tomorrow=addDays(todayKey(),1);
 const curMap=cur instanceof Map?cur:new Map(dateKey?[[dateKey,cur||{active:null,lines:[]}]]:[]);
 const selected=new Set(dateKey?[dateKey]:dates.filter(d=>d.date>=tomorrow&&!d.missing.length).map(d=>d.date));
 pending={books,dates,selected,current:curMap,picks:{},kgFix:{},custFix:{},addAlias:{},importIds:{},done:{},date:dateKey||[...selected][0]||""};
 readSelected();
 return pending;
}
function readSelected(){
 const p=pending,lines=[],sheets=[],errors=[],bad=new Set;
 for(const d of [...p.selected].sort()){
  const r=readBooks(p.books.filter(b=>p.dates.find(x=>x.date===d)?.files.includes(b.name)),d);
  if(r.errors.length){errors.push(...r.errors.map(e=>`${md(d)}：${e}`));bad.add(d)}
  for(const l of r.lines){l.date=d;const it=resolveItem(l.base,masters);if(it){l.item=it.item;l.inMaster=it.inMaster}else{l.item="";l.inMaster=true;l.issues.push("item")}lines.push(l)}
  sheets.push(...r.sheets.map(s=>({...s,date:d})));
 }
 Object.assign(p,{lines,sheets,errors,bad});
}
function c140ToggleDate(d,on){if(!pending)return;on?pending.selected.add(d):pending.selected.delete(d);readSelected();return rerender()}
function effective(){
 const p=pending;if(!p)return[];
 return p.lines.map(l=>{const o={...l},k=lk(l);
  if(l.issues.includes("item")){const pk=p.picks[key(l.base)];if(pk){o.item=pk.item;o.inMaster=pk.inMaster}}
  if((l.issues.includes("qty")||l.issues.includes("unit")||l.kg===null)&&p.kgFix[k]!==undefined&&p.kgFix[k]!==""){o.kg=Number(p.kgFix[k]);if(!o.unit)o.unit="kg"}
  if(l.issues.includes("customer")&&p.custFix[k])o.customer=p.custFix[k];
  /* ケースの数だけで規格（kg）が書いていない行は、標準ケースの重さで kg にする */
  if(o.unit==="cs"&&(o.kg===null||o.kg===undefined)&&o.boxes>0&&o.item){const sd=masters?.std?.get(o.item);if(sd){o.kg=Math.round(o.boxes*sd*1000)/1000;o.pack=sd}}
  o.open=[];if(!o.item)o.open.push("品目を選んでください");
  if((l.issues.includes("qty")||l.issues.includes("unit"))&&!(p.kgFix[k]>0))o.open.push("数量（kg）を入れてください");
  if(!o.customer)o.open.push("客先を入れてください");
  if(!o.unit)o.unit="kg";
  return o});
}
function diffOf(now,cur){
 const sum=ls=>{const mp=new Map;for(const l of ls){const k=`${l.customer}｜${l.item}`;mp.set(k,(mp.get(k)||0)+(Number(l.kg)||0))}return mp};
 const a=sum(now),b=sum(cur||[]),add=[],chg=[],del=[];
 for(const [k,v] of a){if(!b.has(k))add.push([k,v]);else if(Math.abs(b.get(k)-v)>0.001)chg.push([k,b.get(k),v])}
 for(const [k,v] of b)if(!a.has(k))del.push([k,v]);
 return{add,chg,del};
}
/* 日ごとの状態：new 新しく登録 ／ change 変わる ／ same 変わらない（登録し直さない） ／ bad 読めない */
/* 「11月.xlsx」と「11月-埼玉・フジ　他.xlsx」のように、同じ月のファイルが1つしか選ばれていないときの「足りない側」の説明 */
function monthPartnerMissing(selected,nowF){
 const out=[];for(const f of nowF){const m=N(f).match(/^(\d+)月/);if(!m)continue;const same=selected.filter(x=>(N(x).match(/^(\d+)月/)||[])[1]===m[1]);if(same.length<2)out.push(`${m[1]}月のもう1つのファイル`)}
 return out;
}
function dayStates(){
 const p=pending,eff=effective(),out=[];
 for(const d of [...p.selected].sort()){
  const ls=eff.filter(l=>l.date===d),cur=p.current.get(d)||{active:null,lines:[]},open=ls.filter(l=>l.open.length).length;
  if(p.bad.has(d)||!ls.length){out.push({date:d,state:"bad",lines:ls,open});continue}
  /* ファイルが足りない日は登録しない（1ファイルずつ取り込むと、もう片方の分が消えてしまうため）：
     ・同じ月の2ファイル（「11月.xlsx」「11月-埼玉・フジ　他.xlsx」）の片方しか選んでいない
     ・前の取り込みにあったファイルが今回ない */
  const nowF=p.sheets.filter(x=>x.date===d).map(x=>x.file),prevF=(cur.active?.files||[]).map(f=>f.file).filter(Boolean);
  const lack=[...new Set([...prevF.filter(f=>!nowF.includes(f)),...monthPartnerMissing(p.books.map(b=>b.name),nowF)])];
  if(lack.length){out.push({date:d,state:"short",lines:ls,open,lack});continue}
  const df=diffOf(ls,cur.lines);
  const st=p.done[d]?"done":!cur.active?"new":(df.add.length||df.chg.length||df.del.length)?"change":"same";
  out.push({date:d,state:st,lines:ls,open,diff:df,cur});
 }
 return out;
}
function c140PreviewPage(){
 const p=pending;if(!p)return c140ImportPage();
 setScreen("c140PreviewPage",[]);
 const items=seikaItems(),days=dayStates(),eff=days.flatMap(d=>d.lines),open=eff.filter(l=>l.open.length);
 const tomorrow=addDays(todayKey(),1);
 const stTxt={new:"新しく登録",change:"変わる",same:"変わらない（登録しません）",bad:"読めません（登録しません）",short:"ファイルが足りません（登録しません）",done:"登録済み"};
 const dayInfo=new Map(days.map(d=>[d.date,d]));
 const dateRow=x=>{const on=p.selected.has(x.date),di=dayInfo.get(x.date);let info="";
  if(on&&di){info=`<b class="c140St c140St_${di.state}">${stTxt[di.state]}</b>`;if(di.state==="change")info+=`<span class="small">（追加${di.diff.add.length}・変更${di.diff.chg.length}・なくなる${di.diff.del.length}）</span>`;if(di.state!=="bad")info+=` <span class="small">${di.lines.length}行${di.open?`・要確認${di.open}`:""}</span>`}
  const lk2=di?.state==="short"?`<div class="small" style="color:#b91c1c">⚠ ${esc(di.lack.join("、"))} がありません。同じ月の2ファイルを一緒に選んでください（片方だけで登録すると、もう片方の客先の分が消えます）</div>`:"";
  const warn=lk2+(x.missing.length?`<div class="small" style="color:#b45309">⚠ ${esc(x.missing.join("、"))} にこの日のシートがありません（片方だけで登録すると数が足りなくなります）</div>`:"");
  return `<label style="display:flex;gap:8px;align-items:flex-start;border-top:1px solid #e2e8f0;padding:6px 0;cursor:pointer"><input type="checkbox" style="width:20px;height:20px;margin-top:2px;flex:none" ${on?"checked":""} ${seikaEventAttrs("change","c140ToggleDate",[x.date,{__seikaChecked:true}])}><span><b>${md(x.date)}</b>${x.date<tomorrow?'<span class="small">（過去の日）</span>':""} ${info}${warn}</span></label>`};
 const dateCard=`<div class="card"><b>取り込む納品日を選ぶ</b><div class="small">ファイルに入っている納品日です。はじめは明日（${md(tomorrow)}）以降が選ばれています。出荷日は納品日の前日です。</div>
  ${p.dates.filter(x=>x.date>=tomorrow).map(dateRow).join("")||'<div class="small">明日以降の納品日のシートはありません。</div>'}
  ${p.dates.some(x=>x.date<tomorrow)?`<details ${p.dates.some(x=>x.date<tomorrow&&p.selected.has(x.date))?"open":""} style="margin-top:6px"><summary style="cursor:pointer" class="small">過去の日（${p.dates.filter(x=>x.date<tomorrow).length}日）も取り込むときは開く</summary>${p.dates.filter(x=>x.date<tomorrow).map(dateRow).join("")}</details>`:""}</div>`;
 const errs=p.errors.length?`<div class="card err"><b>読めなかったシート</b>${p.errors.map(e=>`<div class="small">${esc(e)}</div>`).join("")}</div>`:"";
 const needItem=new Map;for(const l of p.lines)if(l.issues.includes("item")){const k=key(l.base);if(!needItem.has(k))needItem.set(k,{base:l.base,rows:[]});needItem.get(k).rows.push(l)}
 const opt=(sel)=>`<option value="">選んでください</option>${items.map(x=>`<option value="${esc(x)}" ${sel===x?"selected":""}>${esc(x)}</option>`).join("")}<option value="__raw__" ${sel==="__raw__"?"selected":""}>SEIKA＋の品目にない（この名前で保存）</option>`;
 const itemCard=needItem.size?`<div class="card warn"><b>要確認：知らない品名（${needItem.size}種類）</b><div class="small">品名読み替えマスタにない書き方です。推測はしません。SEIKA＋のどの品目か選んでください（何日分あっても同じ品名は1回で全部に当たります）。「大根」とだけ書いてあるものは、カット大根・葉付き大根などを取り違えないよう特に注意してください。</div>
  ${[...needItem].map(([k,v])=>{const pk=p.picks[k],sel=pk?(pk.inMaster?pk.item:"__raw__"):"";return `<div style="border-top:1px solid #e2e8f0;margin-top:8px;padding-top:8px"><b>${esc(v.base)}</b><span class="small">（${v.rows.length}行：${esc([...new Set(v.rows.map(r=>r.raw))].slice(0,3).join("、"))}${v.rows.length>3?"…":""}）</span>
   <div class="row" style="gap:8px;flex-wrap:wrap;margin-top:4px"><select style="font-size:16px;padding:6px;min-width:12em" ${seikaEventAttrs("change","c140PickItem",[k,{__seikaValue:true}])}>${opt(sel)}</select>
   <label class="small"><input type="checkbox" ${p.addAlias[k]!==false?"checked":""} ${seikaEventAttrs("change","c140ToggleAlias",[k,{__seikaChecked:true}])}> 品名読み替えマスタに追加する</label></div></div>`}).join("")}</div>`:"";
 const qtyRows=eff.filter(l=>l.issues.includes("qty")||l.issues.includes("unit"));
 const qtyCard=qtyRows.length?`<div class="card warn"><b>要確認：数量の書き方が読めない行（${qtyRows.length}行）</b><div class="small">積み込み表の書き方を見て、合計のkgを入れてください（例：「15kg*13.5kg*1」→ 15kg×13箱＋5kg×1箱なら 200）。</div>
  ${qtyRows.map(l=>`<div class="row" style="gap:8px;flex-wrap:wrap;align-items:center;border-top:1px solid #e2e8f0;margin-top:6px;padding-top:6px"><div style="flex:1;min-width:14em">${md(l.date)}・${esc(l.customer||"-")}・${esc(l.raw)}<div class="small">書き方：「${esc(l.qtyRaw)}」${l.unit&&!l.issues.includes("unit")?"":"（単位なし）"}・${esc(l.file)} シート${esc(l.sheet)} ${esc(l.col)}${l.row}</div></div><input type="number" inputmode="decimal" min="0" step="0.1" value="${esc(p.kgFix[lk(l)]??"")}" placeholder="kg" style="width:7em;font-size:16px;padding:6px" ${seikaEventAttrs("change","c140FixKg",[lk(l),{__seikaValue:true}])}> kg</div>`).join("")}</div>`:"";
 const custRows=eff.filter(l=>l.issues.includes("customer"));
 const custCard=custRows.length?`<div class="card warn"><b>要確認：客先が分からない行（${custRows.length}行）</b>${custRows.map(l=>`<div class="row" style="gap:8px;flex-wrap:wrap;align-items:center;margin-top:6px"><div style="flex:1;min-width:14em">${md(l.date)}・${esc(l.raw)}（${esc(l.qtyRaw)}）<div class="small">${esc(l.file)} シート${esc(l.sheet)} ${esc(l.col)}${l.row}</div></div><input type="text" value="${esc(p.custFix[lk(l)]||"")}" placeholder="客先" style="width:12em;font-size:16px;padding:6px" ${seikaEventAttrs("change","c140FixCust",[lk(l),{__seikaValue:true}])}></div>`).join("")}</div>`:"";
 const dayCards=days.filter(d=>d.state!=="bad").map((d,i)=>{const ready=d.lines.filter(l=>l.item&&!l.open.length),tots=itemTotals(ready,masters);
  const df=d.diff,cur=d.cur;
  const diff=cur?.active&&d.state==="change"?`<div style="margin:6px 0">${df.chg.length?`<div class="small"><b>数量が変わる</b>：${df.chg.map(([k,a,b])=>`${esc(k)} ${num(a)}→<b>${num(b)}</b>kg`).join("、")}</div>`:""}${df.add.length?`<div class="small"><b>追加</b>：${df.add.map(([k,v])=>`${esc(k)} ${num(v)}kg`).join("、")}</div>`:""}${df.del.length?`<div class="small"><b>なくなる</b>：${df.del.map(([k,v])=>`${esc(k)} ${num(v)}kg`).join("、")}</div>`:""}</div>`:"";
  return `<details ${i===0&&days.length<=1?"open":""} style="margin-top:6px"><summary style="font-weight:800;cursor:pointer">${md(d.date)}　${stTxt[d.state]}<span class="small">（${d.lines.length}行・${tots.length}品目）</span></summary>${diff}<div style="overflow:auto"><table class="table" style="font-size:14px"><tr><th>品目</th><th>数量</th></tr>${tots.map(o=>`<tr><td>${esc(o.item)}</td><td>${totalText(o)}</td></tr>`).join("")}</table></div></details>`}).join("");
 const toSave=days.filter(d=>d.state==="new"||d.state==="change"),same=days.filter(d=>d.state==="same").length;
 const ok=!open.length&&toSave.length>0;
 const sheets=p.sheets.length?`<div class="small">${[...new Set(p.sheets.map(s=>s.file))].map(f=>esc(f)).join("、")}</div>`:"";
 pageShell("積み込み表の取り込み（確認）",`選んだ納品日：${p.selected.size}日`,`${dateCard}${errs}
  <div class="card"><b>読んだ行：${p.lines.length}行</b>${sheets}
  <div class="row" style="margin-top:8px;flex-wrap:wrap"><div class="box">要確認<b>${open.length}</b></div><div class="box">登録する日<b>${toSave.length}</b></div><div class="box">変わらない日<b>${same}</b></div></div></div>
  ${itemCard}${qtyCard}${custCard}
  ${dayCards?`<div class="card"><b>日ごとの品目の合計</b>${open.length?`<div class="small">要確認の行（${open.length}行）は入っていません。</div>`:""}${dayCards}<div class="small" style="margin-top:6px">登録すると、その日の今の出荷予定は「置き換え済み」として残り、この内容に置き換わります（足し算はしません）。</div></div>`:""}
  <div class="card">${ok?`<button class="btn green" style="width:100%" ${seikaEventAttrs("click","c140Save",[])}>選んだ日を登録する（${toSave.length}日分${same?`・変わらない${same}日は登録しません`:""}）</button>`:open.length?`<div class="err">要確認の行（${open.length}行）を直すと登録できます。</div>`:`<div class="notice">登録する日がありません（選んだ日はどれも変わっていないか、読めません）。</div>`}
  <button class="btn btn2" style="width:100%;margin-top:8px" ${seikaEventAttrs("click","c140CancelImport",[])}>登録せずに戻る</button></div>`);
}
/* 入力欄の変更で画面を描き直すときは、先にフォーカスを外してから（描き直しの途中で blur が走らないように） */
function rerender(){try{document.activeElement?.blur?.()}catch(_){}setTimeout(()=>{if(currentScreen==="c140PreviewPage")c140PreviewPage()},0)}
function c140PickItem(k,v){if(!pending)return;if(!v)delete pending.picks[k];else pending.picks[k]=v==="__raw__"?{item:pending.lines.find(l=>key(l.base)===k)?.base||k,inMaster:false}:{item:v,inMaster:true};return rerender()}
function c140ToggleAlias(k,on){if(pending)pending.addAlias[k]=!!on}
function c140FixKg(k,v){if(!pending)return;const n=Number(v);if(v===""||!(n>0))delete pending.kgFix[k];else pending.kgFix[k]=n;return rerender()}
function c140FixCust(k,v){if(!pending)return;const s=N(v);if(s)pending.custFix[k]=s;else delete pending.custFix[k];return rerender()}
function c140CancelImport(){const d=[...(pending?.selected||[])].sort()[0];pending=null;return c140ShipPlanPage(d||"","")}
function payload(lines){
 return lines.map(l=>({customer_name:l.customer,customer_norm:key(l.customer),route:l.route||"",item_name:l.item,item_in_master:l.inMaster!==false,item_raw:l.raw,qty_raw:l.qtyRaw,unit:l.unit||"kg",
  boxes:l.boxes,pack_kg:l.pack,kg:l.kg,note:l.note||"",source_file:l.file,source_sheet:l.sheet,source_row:l.row,source_col:l.col}));
}
let saving=false;
/* 1日ずつ順に登録。途中で止まっても、もう一度押せば登録済みの日は飛ばして続きから（取り込みIDは日ごとに固定） */
async function c140Save(){
 const p=pending;if(!p||!canImport()||saving)return;
 const days=dayStates();if(days.some(d=>d.open))return alert("要確認の行が残っています。");
 const todo=days.filter(d=>d.state==="new"||d.state==="change");if(!todo.length)return alert("登録する日がありません。");
 saving=true;const saved=[];
 try{
  busy(true,"品名の読み替えを保存しています");
  for(const [k,pk] of Object.entries(p.picks)){if(p.addAlias[k]===false||p.aliasDone?.[k])continue;const base=p.lines.find(l=>key(l.base)===k)?.base||k;
   await callRpc("save_ship_plan_alias_v1199c140",{p_key:k,p_raw:base,p_item:pk.item,p_in_master:pk.inMaster});(p.aliasDone||(p.aliasDone={}))[k]=true}
  for(const d of todo){
   busy(true,`${md(d.date)} の出荷予定を登録しています（${saved.length+1}/${todo.length}）`);
   p.importIds[d.date]=p.importIds[d.date]||uuid();
   const files=p.sheets.filter(s=>s.date===d.date).map(s=>({file:s.file,sheet:s.sheet}));
   const a=await callRpc("replace_ship_plan_v1199c140",{p_import_id:p.importIds[d.date],p_delivery_date:d.date,p_files:files,p_lines:payload(d.lines)});
   if(a&&a.ok===false)throw new Error(a.message||"登録できませんでした");
   p.done[d.date]=true;saved.push(d.date);
  }
  const first=todo[0].date,same=days.filter(d=>d.state==="same").length;pending=null;masters=null;
  await c140ShipPlanPage(first,`${todo.map(d=>md(d.date)).join("・")} の出荷予定を登録しました（${todo.length}日分${same?`・変わらない${same}日はそのまま`:""}）。前の取り込みは置き換え済みとして残しています。`);
 }catch(e){
  alert(`${saved.length?`${saved.map(md).join("・")} は登録できました。\n`:""}登録できなかった日があります。もう一度「登録する」を押すと、残りの日から続けます。\n${sqlMissing(e)?NEED_SQL:(e?.message||e)}`);
  if(pending)c140PreviewPage();
 }
 finally{saving=false;busy(false)}
}

/* ---------- 品名の読み替え・標準ケース ---------- */
async function c140AliasPage(msg=""){
 if(!canImport())return c140ShipPlanPage();
 setScreen("c140AliasPage",[msg]);
 pageShell("品名の読み替え・標準ケース","読み込んでいます",'<div class="card"><div class="notice">読み込んでいます。</div></div>');
 let m;try{m=await loadMasters(true)}catch(e){return pageShell("品名の読み替え・標準ケース","",`<div class="err">${esc(sqlMissing(e)?NEED_SQL:(e?.message||e))}</div>`)}
 let ca=null;try{ca=await qrSelect(T.calias,"select=*&limit=2000")}catch(_){ca=null}
 if(currentScreen!=="c140AliasPage")return;
 const admin=canAdmin(),items=seikaItems();
 const caCard=ca?`<div class="card"><b>客先の読み替え（産地報告書 → 積み込み表・${ca.length}件）</b><div class="small">産地報告書の取り込みで選んだ対応がここに増えます。${admin?"「削除」すると、次の取り込みで要確認に戻ります。":""}</div>
  <div style="overflow:auto"><table class="table" style="font-size:14px"><tr><th>産地報告書の書き方</th><th>積み込み表の客先</th>${admin?"<th></th>":""}</tr>${[...ca].sort((a,b)=>String(a.raw_name).localeCompare(String(b.raw_name),"ja")).map(a=>`<tr><td>${esc(a.raw_name)}</td><td>${esc(a.customer_name)}</td>${admin?`<td><button class="btn btn2" ${seikaEventAttrs("click","c142DeleteCustomerAlias",[a.raw_key,a.raw_name])}>削除</button></td>`:""}</tr>`).join("")}</table></div></div>`:"";
 const al=[...m.aliasRows].sort((a,b)=>String(a.raw_name).localeCompare(String(b.raw_name),"ja"));
 const st=[...m.stdRows].sort((a,b)=>String(a.item_name).localeCompare(String(b.item_name),"ja"));
 pageShell("品名・客先の読み替え・標準ケース","積み込み表の書き方とSEIKA＋の品目の対応、ケース数を出す重さ、産地報告書の客先名",`${okHtml(msg)}
 <div class="card"><b>品名読み替えマスタ（${al.length}件）</b><div class="small">取り込みの確認画面で選んだ対応がここに増えます。${admin?"品目を選び直すと、次の取り込みからその品目になります（馬鈴薯のように時期で使う品種が変わるものはここで切り替え）。「削除」すると、次の取り込みで要確認に戻ります。":"直すときは管理者に頼んでください。"}</div>
  <div style="overflow:auto"><table class="table" style="font-size:14px"><tr><th>積み込み表の書き方</th><th>SEIKA＋の品目</th><th>更新</th>${admin?"<th></th>":""}</tr>${al.map(a=>`<tr><td>${esc(a.raw_name)}</td><td>${admin?`<select style="font-size:15px;padding:4px;max-width:11em" ${seikaEventAttrs("change","c140ChangeAlias",[a.raw_key,a.raw_name,{__seikaValue:true}])}>${(items.includes(a.item_name)?items:[a.item_name,...items]).map(x=>`<option value="${esc(x)}" ${x===a.item_name?"selected":""}>${esc(x)}</option>`).join("")}</select>`:esc(a.item_name)}${a.in_master===false?'<span class="small">（マスタ外）</span>':""}</td><td class="small">${esc(a.updated_by_name||"")}</td>${admin?`<td><button class="btn btn2" ${seikaEventAttrs("click","c140DeleteAlias",[a.raw_key,a.raw_name])}>削除</button></td>`:""}</tr>`).join("")}</table></div></div>
 <div class="card"><b>標準ケースの重さ（${st.length}品目）</b><div class="small">ケース数＝kg ÷ この重さ を切り上げます。ない品目は、積み込み表に書いてある1箱の重さで割ります。</div>
  <div style="overflow:auto"><table class="table" style="font-size:14px"><tr><th>品目</th><th>1ケース</th>${admin?"<th></th>":""}</tr>${st.map(s=>`<tr><td>${esc(s.item_name)}</td><td>${admin?`<input type="number" min="0.1" step="0.1" value="${esc(s.case_kg)}" style="width:6em;font-size:16px;padding:4px" ${seikaEventAttrs("change","c140SaveStd",[s.item_name,{__seikaValue:true}])}> kg`:`${num(s.case_kg)}kg`}</td>${admin?`<td><button class="btn btn2" ${seikaEventAttrs("click","c140SaveStd",[s.item_name,""])}>削除</button></td>`:""}</tr>`).join("")}</table></div>
  ${admin?`<div class="row" style="gap:8px;flex-wrap:wrap;margin-top:8px"><select id="c140StdItem" style="font-size:16px;padding:6px"><option value="">品目を選ぶ</option>${items.map(x=>`<option>${esc(x)}</option>`).join("")}</select><input id="c140StdKg" type="number" min="0.1" step="0.1" placeholder="kg" style="width:6em;font-size:16px;padding:6px"><button class="btn blue" ${seikaEventAttrs("click","c140AddStd",[])}>追加</button></div>`:""}</div>
 ${caCard}
 <button class="btn btn2" style="width:100%" ${seikaEventAttrs("click","c140ShipPlanPage",["",""])}>出荷予定へ戻る</button>`);
}
async function c140ChangeAlias(k,name,item){
 if(!canAdmin()||!item)return;
 try{await callRpc("save_ship_plan_alias_v1199c140",{p_key:k,p_raw:name,p_item:item,p_in_master:seikaItems().includes(item)});masters=null;await c140AliasPage(`「${name}」を「${item}」に読み替えるようにしました（次の取り込みから）。`)}catch(e){alert(e?.message||e)}
}
async function c140DeleteAlias(k,name){
 if(!canAdmin()||!confirm(`「${name}」の読み替えを削除します。よろしいですか？`))return;
 try{await callRpc("delete_ship_plan_alias_v1199c140",{p_key:k});masters=null;await c140AliasPage(`「${name}」の読み替えを削除しました。`)}catch(e){alert(e?.message||e)}
}
async function c140SaveStd(item,v){
 if(!canAdmin())return;
 if(v===""){if(!confirm(`${item}の標準ケースを削除します。よろしいですか？`))return}
 else if(!(Number(v)>0))return alert("重さは0より大きい数字で入れてください。");
 try{await callRpc("save_ship_plan_case_std_v1199c140",{p_item:item,p_kg:v===""?null:Number(v)});masters=null;await c140AliasPage(`${item}の標準ケースを${v===""?"削除":"保存"}しました。`)}catch(e){alert(e?.message||e)}
}
function c140AddStd(){const it=document.getElementById("c140StdItem")?.value||"",kg=document.getElementById("c140StdKg")?.value||"";if(!it)return alert("品目を選んでください。");return c140SaveStd(it,kg)}

/* ---------- 入口：ホーム ---------- */
function c140InjectHome(){
 if(currentScreen!=="home"||!canView()||document.getElementById("c140HomeBtn"))return;
 const box=document.querySelector("#app .homePrimary");if(!box)return;
 box.insertAdjacentHTML("beforeend",`<button id="c140HomeBtn" type="button" class="btn homeBtnShipPlan" ${seikaEventAttrs("click","c140ShipPlanPage",["",""])}>出荷予定（積み込み表）<br><span style="font-size:15px;font-weight:800">${canImport()?"明日の出荷予定を見る・取り込む":"明日の出荷予定を見る"}</span></button>`);
}
const app=document.getElementById("app");
if(app)new MutationObserver(()=>{if(currentScreen==="home"&&!document.getElementById("c140HomeBtn")&&document.querySelector("#app .homePrimary"))c140InjectHome()}).observe(app,{childList:true,subtree:true});
{const st=document.createElement("style");st.textContent=".homeBtnShipPlan,.c140Btn{background:linear-gradient(90deg,#1e293b 0%,#1d4ed8 55%,#f59e0b 100%) !important;color:#fff !important;border-color:transparent !important;}.c140St{margin-left:6px;font-size:13px}.c140St_new,.c140St_change{color:#1d4ed8}.c140St_same{color:#64748b}.c140St_bad,.c140St_short{color:#b91c1c}.c140St_done{color:#15803d}.c142Diff{display:inline-block;margin-left:6px;padding:0 6px;border-radius:8px;background:#fee2e2;color:#991b1b;font-size:12px;font-weight:800;border:1px solid #f87171}.c142Btn{background:linear-gradient(90deg,#14532d 0%,#15803d 55%,#facc15 100%) !important;color:#fff !important;border-color:transparent !important}.c140Frac{display:inline-block;margin-left:6px;padding:0 6px;border-radius:8px;background:#fef3c7;color:#92400e;font-size:12px;font-weight:800;border:1px solid #f59e0b}";document.head.appendChild(st)}

Object.assign(window,{c140ShipPlanPage,c140ImportPage,c140PickFiles,c140ReadFiles,c140Prepare,c140PreviewPage,c140ToggleDate,c140PickItem,c140ToggleAlias,c140FixKg,c140FixCust,c140CancelImport,c140Save,
 c140AliasPage,c140ChangeAlias,c140DeleteAlias,c140SaveStd,c140AddStd,c140InjectHome,
 c140Auto:{dayStates,effective,payload,listDates,pending:()=>pending},
 c140Lib:{T,N,key,md,addDays,num,busy,uuid,esc:(v)=>esc(v),loadMasters,getMasters:()=>masters,seikaItems,resolveItem,casesOf,itemTotals,weightText,totalText,baseName,cellDate,loadPlan,loadActual,sqlMissing,canImport,canView,SMALL_KG},
 c140Parse:{unitOf,specKg,baseName,parseQty,readSheet,readBooks,listDates,casesOf,itemTotals,resolveItem,weightText}});

/* ---------- 操作ガイド ---------- */
try{
 const imp={title:"積み込み表から出荷予定を取り込む",where:"ホーム →「出荷予定（積み込み表）」→「積み込み表を取り込む」",
  steps:["前日の夕方、積み込み表（同じ月の2ファイル）を保存してから取り込みます。",
   "「積み込み表を選ぶ」で、同じ月の2つのファイルを一度に選びます。ファイルは端末の中で読み、サーバーには送りません。",
   "ファイルに入っている納品日（シートのB1の日付）が一覧で出ます。はじめは明日以降の日が選ばれています。チェックで日を足したり外したりできます。片方のファイルにしかない日・形が違うシートは、登録しないよう止めます。",
   "確認画面に、知らない品名・読めない数量・客先が分からない行が「要確認」で出ます。品名はSEIKA＋の品目を選び（同じ品名はまとめて1回）、数量は合計のkgを入れます。選んだ品名は「品名読み替えマスタ」に追加され、次から自動で当てはまります。",
   "日ごとに「新しく登録」「変わる（追加・変更・なくなる）」「変わらない」が出ます。要確認がなくなったら「選んだ日を登録する」を押します。変わらない日は登録し直しません。変わった日は足し算せず置き換わります（前の取り込みは「置き換え済み」で残ります）。",
   "途中で通信が切れて止まったときは、もう一度「登録する」を押すと残りの日から続きます（同じ日が二重に入ることはありません）。"],
  check:"出荷日（セット日）は納品日の前日で保存します。ケース数は標準ケースで割って切り上げ、割り切れないときは「端数あり」が付きます。",
  caution:"「大根」とだけ書いてある品名は、カット大根・葉付き大根などを取り違えないよう、選ぶときに特に注意してください。"};
 const view={title:"出荷予定を見る",where:"ホーム →「出荷予定（積み込み表）」",
  steps:["はじめは明日の納品日の出荷予定が出ます。「前の日」「次の日」や日付で切り替えます。",
   "「品目ごとの合計」にケース数（端数ありの印つき）とkgが出ます。全客先を合わせて10kg以下の品目は、ケースではなく重さ（kg・g）で出ます。",
   "「客先ごと」を開くと、客先ごとの品目と数量、積み込み表の書き方が見られます。"],
  check:"いつ・だれが取り込んだかは、画面の上に出ます。",caution:"まだ取り込まれていない日は「まだ取り込まれていません」と出ます。"};
 const alias={title:"品名の読み替え・標準ケースを直す",where:"ホーム →「出荷予定（積み込み表）」→「品名の読み替え・標準ケース」",
  steps:["積み込み表の書き方と、SEIKA＋の品目の対応が一覧で出ます。管理者は品目を選び直せます（成城石井の「馬鈴薯」のように、時期で使う品種が変わるものはここで切り替えます）。「削除」すると、次の取り込みで要確認に戻ります。",
   "標準ケースの重さ（キャベツ10kg、葉付き大根・人参・カット大根15kgなど）は管理者が直せます。ない品目は、積み込み表の1箱の重さで割ります。"],
  check:"直した内容は、次に取り込んだときから使われます。",caution:"すでに登録した出荷予定は、取り込み直すまで変わりません。"};
 if(typeof V195_ROLE_GUIDES!=="undefined"){
  const add=(r,list)=>{const g=V195_ROLE_GUIDES[r];if(!g||!Array.isArray(g.sections))return;for(const s of list)if(!g.sections.some(x=>x&&x.title===s.title))g.sections.push(s)};
  for(const r of IMPORT_ROLES)add(r,[imp,view,alias]);
  for(const r of ["buyer","sales","office_viewer","viewer"])add(r,[view]);
 }
}catch(e){}
})();
