/* ===== v1.199-c156 在庫報告コピーに「明日出荷のサンプル」を足す =====
   原料手配のため、翌日に出すサンプルを前日のうちに仕入れ担当へ知らせる。
   ・c159：明日出荷＝報告を作る日（日本時間）の翌日に出荷する分＝その次の日（報告日＋2日）の納品日の行。
     積み込み表の日付は納品日で、出荷日はその前日（11/24の報告なら、11/25出荷＝11/26納品の分）。見出しの日付は出荷日
   ・その納品日の出荷予定（status='active'）のうち、メモ（note）に「サンプル」を含む行。
   ・客先ごとに1行、積み込み表の順（line_no）。品目マスタにない品も書いてある名前のまま。
   ・今の文章（過多・不足・先送り済み）の後ろに足すだけ。サンプルがない日は「なし」。読むだけで、在庫・QR・伝票には触らない。 */
(()=>{
const L=()=>window.c140Lib;
const r2=v=>Math.round(Number(v)*100)/100;
const fmtKg=v=>r2(v).toLocaleString("ja-JP");
function addDay(k){const d=new Date(k+"T00:00:00Z");d.setUTCDate(d.getUTCDate()+1);return d.toISOString().slice(0,10)}
const md=k=>`${Number(k.slice(5,7))}/${Number(k.slice(8,10))}`;

/* 文面を作る（画面に依存しない。テストからも呼ぶ）。plan＝loadPlan の結果、null なら読み込めなかった */
function c156SampleText(date,plan){
 /* date＝納品日。見出しは出荷日（納品日の前日） */
 const ship=(()=>{const d=new Date(date+"T00:00:00Z");d.setUTCDate(d.getUTCDate()-1);return d.toISOString().slice(0,10)})();
 const head=`■ 明日（${md(ship)}）出荷のサンプル`;
 if(plan===null)return `\n\n${head}\n読み込めませんでした。出荷予定（積み込み表）の画面で確認してください。`;
 if(!plan?.active)return `\n\n${head}\n積み込み表がまだ取り込まれていません。`;
 const rows=(plan.lines||[]).filter(l=>/サンプル/.test(String(l.note||""))).slice().sort((a,b)=>(Number(a.line_no)||0)-(Number(b.line_no)||0));
 if(!rows.length)return `\n\n${head} なし`;
 const by=new Map;
 for(const l of rows){const c=String(l.customer_name||l.customer||"").trim()||"客先不明";if(!by.has(c))by.set(c,[]);
  const name=String(l.item_name||l.item||l.item_raw||"").trim()||String(l.item_raw||"-");
  const kg=l.kg===null||l.kg===undefined||l.kg===""?null:Number(l.kg);
  by.get(c).push(`${name} ${kg!==null&&Number.isFinite(kg)?`${fmtKg(kg)}kg`:String(l.qty_raw||"").trim()||"数量不明"}`)}
 return `\n\n${head}\n`+[...by].map(([c,items])=>`・${c}：${items.join("／")}`).join("\n");
}
async function c156SampleSection(){
 const date=addDay(addDay(todayKey()));  /* c159：明日出荷＝明後日納品 */
 let plan;try{plan=await L().loadPlan(date)}catch(_){plan=null}
 return c156SampleText(date,plan);
}
const base=makeLineCopyText;
makeLineCopyText=async function(){
 const [text,extra]=await Promise.all([base(),L()?.loadPlan?c156SampleSection().catch(()=>""):Promise.resolve("")]);
 return text+extra;
};
Object.assign(window,{c156SampleText,c156SampleSection});
try{
 const sec={title:'在庫報告コピー（明日出荷のサンプル）',where:'ホーム →「在庫報告コピー」',
  steps:['文章のいちばん最後に、「■ 明日（月/日）出荷のサンプル」が自動で入ります。','明日出荷する分（積み込み表では明後日の納品日の分。取り込み済みのもの）のうち、メモ欄に「サンプル」と書いてある行を、客先ごとに1行、積み込み表の順に並べます。','品目マスタにない品も、積み込み表に書いてある名前のままです。','サンプルがない日は「■ 明日（月/日）出荷のサンプル なし」と出ます。'],
  check:'見出しの日付は出荷日です（在庫報告を作る日の翌日。納品日はその次の日）。積み込み表がまだ取り込まれていないときは、その旨が出ます。',
  caution:'取り込んだあとに積み込み表を直したときは、取り込み直してから在庫報告を作ってください。'};
 if(typeof V198_GUIDE_SECTIONS!=='undefined')V198_GUIDE_SECTIONS.c156LineSample=sec;
 if(typeof V195_ROLE_GUIDES!=='undefined')for(const role of ['admin','worker']){const g=V195_ROLE_GUIDES[role];if(g&&Array.isArray(g.sections)&&!g.sections.some(x=>x.title===sec.title)){const i=g.sections.findIndex(x=>x.title==='在庫報告コピー（先送り済み）');g.sections.splice(i>=0?i+1:0,0,sec)}}
}catch(e){}
})();
