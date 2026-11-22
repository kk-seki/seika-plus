/* ===== v1.199-c148 仕入れ価格表を「週間予想原料価格」のExcelから取り込む =====
   ・仕入れ価格表の画面に「週間予想原料価格から取り込む」ボタン（価格を登録できる人：管理者・青果社員・仕入れ担当者・事務員）。
   ・「週間」シートの、いちばん右の週の価格の列を読む。週はファイル名の日付（例：26.11.23 → 2026年11月23日の週）。
     ファイル名に日付がないときは、画面で週を選ぶ。見出しの週とずれていても、ファイル名の日付を使う（見出しの書き直し忘れがあるため）。
   ・今まで手で入れていた市場価格（仕入先「市場」・税抜・円/kg）と同じ読み方：
     名前の読み替え（サニーレタス→サニー など）、規格の行の選び方（胡瓜はB、大根は葉付き・切り など）、
     箱の値段はkgで割る（トマト4kg・ミニトマト3kg・レタス8kg）、「k/300」「市場/350」は数字だけ。
   ・値が空の品目は取り込まない（前の週の値も引き継がない）。値のすぐ下に注記（例：ニラ「社内売りは契約価格」）がある品目も取り込まず、手で入れる。読めない値・決まりにない品目は「取り込まない」として一覧に出す。
   ・登録の前に一覧で確かめる。登録は今までと同じ保存（upsert_purchase_price_v1117）を1品目ずつ。SQLは不要。 */
(()=>{
/* 決まり：商品名（B列）・規格（D列）→ 仕入れ価格表の品目。div は箱の値段を割るkg。pick は1つのセルに2つの値があるときの取り出し方 */
const RULES=[
 {name:"小葱",to:"小葱"},{name:"水菜",to:"水菜"},{name:"小松菜",to:"小松菜"},{name:"ニラ",to:"ニラ"},{name:"青梗菜",to:"青梗菜"},
 {name:"茄子",pick:[["短茄子","茄子"],["長茄子","長茄子"]],plain:"茄子"},{name:"長茄子",to:"長茄子"},
 {name:"ゴーヤ",to:"ゴーヤ"},{name:"ズッキーニ",to:"ズッキーニ"},{name:"茗荷",to:"茗荷"},
 {name:"ピーマン",to:"ピーマン",first:true},
 {name:"胡瓜",spec:"B",to:"胡瓜"},
 {name:"トマト",to:"トマト",div:4},{name:"ミニトマト",to:"ミニトマト",div:3},
 {name:"南瓜",to:"南瓜",first:true},
 {name:"キャベツ",to:"キャベツ",first:true},{name:"紫キャベツ",to:"紫キャベツ"},
 {name:"長葱",spec:"加工用",to:"長葱"},
 {name:"大根",spec:"葉付き",to:"葉付き大根"},{name:"大根",spec:"切り",to:"カット大根"},
 {name:"国産人参",spec:"加工用",to:"人参"},
 {name:"レタス",to:"レタス",div:8,first:true},
 {name:"グリーンカール",to:"リーフ",first:true},{name:"サニーレタス",to:"サニー",first:true},{name:"ロメイン",to:"ロメイン",first:true},
 {name:"白菜",spec:"社内加工",to:"白菜"},
];
const norm=v=>String(v??"").normalize("NFKC").replace(/[\s　]/g,"");
const WEEK_RE=/^\d{1,2}\/\d{1,2}[～~〜-]\d{1,2}\/\d{1,2}$/;

/* 値の読み方："k/300"・"市場/350"・"ｋ/365" → 数字、数字だけ → そのまま。"2100/箱"・"青果用/750"・文章 → 読めない */
function c148Num(v){
 if(typeof v==="number"&&Number.isFinite(v))return v;
 const s=norm(v);if(!s)return null;
 let m=s.match(/^(?:k|kg|市場)\/(\d+(?:\.\d+)?)$/i);if(m)return Number(m[1]);
 m=s.match(/^(\d+(?:\.\d+)?)(?:円)?(?:\/(?:k|kg))?$/i);if(m)return Number(m[1]);
 return null;
}
/* ファイル名の日付："週間予想原料価格（26.11.23）.xlsx" → 2026-11-23 の週の月曜 */
function c148WeekFromName(name){
 const m=norm(name).match(/(\d{2,4})[.\-_/年](\d{1,2})[.\-_/月](\d{1,2})/);if(!m)return "";
 const y=m[1].length===2?2000+Number(m[1]):Number(m[1]),d=new Date(Date.UTC(y,Number(m[2])-1,Number(m[3])));
 if(Number.isNaN(d.getTime()))return "";
 const day=(d.getUTCDay()+6)%7;d.setUTCDate(d.getUTCDate()-day);return d.toISOString().slice(0,10);
}
function cellOf(ws,r,c){const a=ws[XLSX.utils.encode_cell({r,c})];return a?(a.v??null):null}
/* 読む（画面に依存しない。テストからも呼ぶ） */
function c148Parse(wb,fileName=""){
 const ws=wb.Sheets["週間"]||wb.Sheets[wb.SheetNames.find(n=>/週間/.test(n))||""];
 if(!ws)throw new Error("「週間」シートが見つかりません。週間予想原料価格のファイルか確かめてください。");
 const ref=XLSX.utils.decode_range(ws["!ref"]||"A1");
 let hr=-1;for(let r=0;r<=Math.min(ref.e.r,15);r++)if(norm(cellOf(ws,r,0))==="担当者"&&norm(cellOf(ws,r,1))==="商品名"){hr=r;break}
 if(hr<0)throw new Error("見出し（担当者・商品名）の行が見つかりません。");
 let col=-1;for(let c=ref.e.c;c>=4;c--){if(WEEK_RE.test(norm(cellOf(ws,hr,c)))){col=c;break}}
 if(col<0)throw new Error("週の価格の列（例：11/16～11/22）が見つかりません。");
 const header=String(cellOf(ws,hr,col)??"");
 const rows=[],skipped=[],seen=new Set;let name="",first=false;
 for(let r=hr+1;r<=ref.e.r;r++){
  const b=norm(cellOf(ws,r,1));if(b){name=b;first=true}else first=false;
  if(!name)continue;
  const spec=norm(cellOf(ws,r,3)),raw=cellOf(ws,r,col),rawText=String(raw??"").trim();
  const rules=RULES.filter(x=>norm(x.name)===name);
  const where=`${r+1}行目`;
  if(!rules.length){if(first&&rawText)skipped.push({name,spec,raw:rawText,why:"決まりにない品目",where});continue}
  /* 1つのセルに「長茄子500」「短茄子575」のように入っている品目 */
  const pr=rules.find(x=>x.pick);
  if(pr){const s=norm(raw),hit=pr.pick.find(([k])=>s.startsWith(norm(k)));
   if(hit){const v=c148Num(s.slice(norm(hit[0]).length));if(v!=null&&!seen.has(hit[1])){seen.add(hit[1]);rows.push({item:hit[1],price:Math.round(v),raw:rawText,name,spec,where})}else if(v==null)skipped.push({name,spec,raw:rawText,why:"値を読めません",where});continue}
   if(!first)continue}
  const rule=rules.find(x=>x.spec?spec.startsWith(norm(x.spec)):(x.first?first:true)&&!x.pick)||(pr&&first&&pr.plain?{to:pr.plain}:null);
  if(!rule||seen.has(rule.to)){if(rawText&&first&&!rule)skipped.push({name,spec,raw:rawText,why:"使う行ではありません",where});continue}
  if(!rawText){if(first||rule.spec)skipped.push({name,spec,raw:"",why:"値が空（取り込まない）",where,item:rule.to,empty:true});if(rule.spec||first)seen.add(rule.to);continue}
  const v=c148Num(raw);
  if(v==null){skipped.push({name,spec,raw:rawText,why:"値を読めません",where,item:rule.to});seen.add(rule.to);continue}
  /* すぐ下の行に「社内売りは契約価格」のような注記があるときは、値をそのまま使ってよいか分からないので取り込まない */
  const below=cellOf(ws,r+1,col),bText=String(below??"").trim();
  if(!norm(cellOf(ws,r+1,1))&&bText&&c148Num(below)==null&&!/^\D{1,4}\d/.test(norm(below))){skipped.push({name,spec,raw:`${rawText}（注記：${bText}）`,why:"注記があるので確認が必要（手で入れてください）",where,item:rule.to});seen.add(rule.to);continue}
  seen.add(rule.to);
  rows.push({item:rule.to,price:Math.round(rule.div?v/rule.div:v),raw:rawText+(rule.div?`（${rule.div}kgの箱）`:""),name,spec,where});
 }
 rows.sort((a,b)=>a.item.localeCompare(b.item,"ja"));
 return {week:c148WeekFromName(fileName),header,col:XLSX.utils.encode_col(col),rows,skipped};
}

/* ---------- 画面 ---------- */
let pending=null;
function canEdit(){return typeof v1115CanPriceEdit==="function"&&v1115CanPriceEdit()}
const ymd=k=>String(k||"").replaceAll("-","/");
function c148ImportPage(week=""){
 if(!canEdit()){alert("仕入れ価格を登録する権限がありません");return purchasePricesPage()}
 setScreen("c148ImportPage",[week]);
 pageShell("仕入れ価格表の取り込み","週間予想原料価格のExcelから、市場価格をまとめて登録します",`<div class="card">
  <input id="c148File" type="file" accept=".xlsx,.xls" style="display:none" ${seikaEventAttrs("change","c148ReadFile",[{__seikaElement:true}])}>
  <button class="btn c148Btn" style="width:100%" ${seikaEventAttrs("click","c148Pick",[])}>週間予想原料価格のファイルを選ぶ</button>
  <div class="small" style="margin-top:8px">「週間」シートの、いちばん右の週の価格を読みます。週はファイル名の日付で決めます（例：26.11.23 → 11/23の週）。値が空の品目は取り込みません。登録の前に一覧で確かめられます。ファイルはこの端末の中で読み、サーバーには送りません。</div></div>
  <button class="btn btn2" style="width:100%" ${seikaEventAttrs("click","purchasePricesPage",[week||v1115Monday(todayKey())])}>戻る</button>`);
}
function c148Pick(){const f=document.getElementById("c148File");if(f){f.value="";f.click()}}
async function c148ReadFile(input){
 const f=input?.files?.[0];if(!f)return;
 if(typeof XLSX==="undefined")return alert("Excelの部品が読み込まれていません。");
 try{v161ShowProcessing?.("価格表を読み込んでいます")}catch(_){}
 try{
  const wb=XLSX.read(await f.arrayBuffer(),{type:"array",cellDates:false});
  const p=c148Parse(wb,f.name);p.file=f.name;p.week=p.week||v1115Monday(todayKey());
  let cur=[];try{cur=await callRpc("get_purchase_prices",{p_week_start:null})||[]}catch(_){}
  pending={...p,current:Array.isArray(cur)?cur:[]};
  return c148PreviewPage();
 }catch(e){alert(`価格表を読み込めませんでした。\n${e?.message||e}`)}
 finally{try{v161HideProcessing?.()}catch(_){}}
}
function c148SetWeek(v){if(!pending)return;pending.week=v1115Monday(v||pending.week);c148PreviewPage()}
function marketOf(cur,week,item){return cur.find(r=>v1117PriceType(r)==="market"&&String(r.week_start||"")===week&&String(r.item_name||"").trim()===item)}
function prevWeek(week){const d=new Date(week+"T00:00:00Z");d.setUTCDate(d.getUTCDate()-7);return d.toISOString().slice(0,10)}
function c148PreviewPage(){
 const p=pending;if(!p)return c148ImportPage();
 setScreen("c148PreviewPage",[]);
 const pw=prevWeek(p.week),hd=String(p.header||"").replace(/[～~〜]/,"～");
 const hm=hd.match(/^(\d{1,2})\/(\d{1,2})/),hWeek=hm?v1115Monday(`${p.week.slice(0,4)}-${String(hm[1]).padStart(2,"0")}-${String(hm[2]).padStart(2,"0")}`):"";
 const warn=hWeek&&hWeek!==p.week?`<div class="notice" style="margin-top:8px">表の見出しは「${esc(hd)}」ですが、ファイル名の日付から <b>${esc(ymd(p.week))} の週</b>として取り込みます。違うときは下で週を選び直してください。</div>`:"";
 const rows=p.rows.map(r=>{const now=marketOf(p.current,p.week,r.item),prev=marketOf(p.current,pw,r.item),pv=prev?Number(prev.price_yen_per_kg):null,diff=pv!=null?r.price-pv:null;
  return `<tr><td><b>${esc(r.item)}</b><div class="small">${esc(r.name)}${r.spec?`（${esc(r.spec)}）`:""}・${esc(r.raw)}</div></td><td style="text-align:right"><b>${money(r.price)}円</b></td><td style="text-align:right">${pv!=null?`${money(pv)}円${diff?`<div class="c148D ${diff>0?"up":"down"}">${diff>0?"+":""}${money(diff)}</div>`:""}`:"－"}</td><td>${now?`<span class="c148Over">上書き（今 ${money(now.price_yen_per_kg)}円）</span>`:"新しく登録"}</td></tr>`}).join("");
 const sk=p.skipped.length?`<div class="card"><details><summary style="font-weight:800;cursor:pointer">取り込まないもの（${p.skipped.length}件）</summary><table class="table" style="font-size:13px"><tr><th>商品名</th><th>値</th><th>理由</th></tr>${p.skipped.map(s=>`<tr><td>${esc(s.name)}${s.spec?`（${esc(s.spec)}）`:""}${s.item?`<div class="small">→ ${esc(s.item)}</div>`:""}</td><td>${esc(s.raw||"（空）")}</td><td class="small">${esc(s.why)}・${esc(s.where)}</td></tr>`).join("")}</table></details></div>`:"";
 pageShell("仕入れ価格表の取り込み（確認）",`${esc(p.file||"")}`,`<div class="card">
   <div><b>${esc(ymd(p.week))} の週</b>の市場価格（仕入先「市場」・税抜・円/kg）として登録します。</div>
   <div class="small">読んだ列：${esc(p.col)}列（見出し「${esc(hd)}」）</div>${warn}
   <label class="label" style="margin-top:8px">週を選び直す（その週の月曜日になります）</label>
   <input type="date" class="input" value="${esc(p.week)}" ${seikaEventAttrs("change","c148SetWeek",[{__seikaValue:true}])}></div>
  <div class="card"><b>登録する価格（${p.rows.length}品目）</b><div style="overflow:auto"><table class="table" style="font-size:14px"><tr><th>品目</th><th>円/kg</th><th>前の週</th><th></th></tr>${rows||'<tr><td colspan="4" class="small">登録できる価格がありません。</td></tr>'}</table></div>
   <div class="small">箱の値段は、トマト4kg・ミニトマト3kg・レタス8kgで割って1円単位に丸めています。</div></div>${sk}
  ${p.rows.length?`<button id="c148SaveBtn" class="btn c148Btn" style="width:100%" ${seikaEventAttrs("click","c148Save",[])}>この内容で登録する（${p.rows.length}品目）</button>`:""}
  <button class="btn btn2" style="width:100%;margin-top:8px" ${seikaEventAttrs("click","c148ImportPage",[p.week])}>ファイルを選び直す</button>`);
}
let saving=false;
async function c148Save(){
 const p=pending;if(!p||saving)return;
 const over=p.rows.filter(r=>marketOf(p.current,p.week,r.item)).length;
 if(!confirm(`${ymd(p.week)} の週の市場価格を ${p.rows.length}品目 登録します。${over?`\nすでに入っている ${over}品目は上書きします。`:""}\nよろしいですか？`))return;
 saving=true;const b=document.getElementById("c148SaveBtn");if(b){b.disabled=true;b.textContent="登録しています…"}
 try{v161ShowProcessing?.("仕入れ価格を登録しています")}catch(_){}
 const done=[],failed=[];
 try{
  for(const r of p.rows){
   try{const a=await callRpc("upsert_purchase_price_v1117",{p_week_start:p.week,p_item_name:r.item,p_origin:"",p_supplier:"市場",p_price_yen_per_kg:r.price,p_price_type:"market"});if(!a?.ok)throw new Error(a?.message||"保存できませんでした");done.push(r.item)}
   catch(e){failed.push(`${r.item}：${e?.message||e}`)}
  }
 }finally{saving=false;try{v161HideProcessing?.()}catch(_){}}
 if(failed.length){alert(`登録できなかった品目があります（${failed.length}件）。\n${failed.join("\n")}\n\n登録できた ${done.length}品目はそのまま残ります。もう一度「登録する」を押すと、全部を登録し直します。`);if(b){b.disabled=false;b.textContent=`この内容で登録する（${p.rows.length}品目）`}return}
 const week=p.week;pending=null;
 return purchasePricesPage(week,`週間予想原料価格から ${done.length}品目の市場価格を登録しました（${ymd(week)} の週）。在庫・歩留まりの金額に反映するには、必要に応じて「価格を再計算」を押してください。`);
}

/* 仕入れ価格表の画面にボタン */
if(typeof v1117RenderPrices==="function"){
 const base=v1117RenderPrices;
 const wrapped=function(week,...rest){const r=base.call(this,week,...rest);
  try{if(canEdit()&&currentScreen==="purchasePrices"&&!document.getElementById("c148Entry")){const main=document.querySelector("#app main.wrap")||document.getElementById("app");
   const first=main.querySelector(".card");const html=`<div id="c148Entry" class="card"><b>週間予想原料価格から取り込む</b><div class="small">週間予想原料価格のExcelを選ぶと、その週の市場価格をまとめて登録できます（登録の前に確かめられます）。</div><button class="btn c148Btn" style="width:100%;margin-top:8px" ${seikaEventAttrs("click","c148ImportPage",[week])}>週間予想原料価格から取り込む</button></div>`;
   if(first)first.insertAdjacentHTML("beforebegin",html);else main.insertAdjacentHTML("afterbegin",html)}}catch(_){}
  return r};
 window.v1117RenderPrices=wrapped;try{v1117RenderPrices=wrapped}catch(_){}
}
{const st=document.createElement("style");st.textContent=".c148Btn{background:linear-gradient(90deg,#14532d 0%,#15803d 55%,#f59e0b 100%) !important;color:#fff !important;border-color:transparent !important}.c148Over{font-size:12px;font-weight:800;color:#b45309}.c148D{font-size:12px;font-weight:900}.c148D.up{color:#b91c1c}.c148D.down{color:#1d4ed8}";document.head.appendChild(st)}

Object.assign(window,{c148ImportPage,c148Pick,c148ReadFile,c148PreviewPage,c148SetWeek,c148Save,c148Lib:{c148Parse,c148Num,c148WeekFromName,RULES}});
})();
