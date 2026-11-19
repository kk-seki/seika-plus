/* ===== v1.199-c130 単協・仕入先マスタの正式化／GAP一覧の取り込み・QR入庫での自動入力・さかのぼり・期限一覧 =====
   ・入力候補は「仕入先・単協マスタ」の正式名だけにする（過去のロットの表記は候補に出さない）。
   ・マスタにない名前で保存するときは確認し、マスタに登録してから保存する。別名（直した元の表記）は自動で正式名に直す。
   ・管理者は、ロットに入っている表記を正式名にまとめ、過去のロット・履歴の表記も直せる（SQL 052）。
   ・GAP一覧（単協＋品目、認証区分、有効期限）をExcelで取り込む（全部置き換え）。QR入庫で認証区分を自動で入れる。 */
(()=>{
const CERTS=["JGAP","GGAP","ASIAGAP"],SOON_DAYS=30,HEAD=["単協名","品目","認証区分","有効期限","備考"];
const KIND_LABEL={supplier:"仕入先",cooperative:"単協名"};
const sqlMissing=e=>/PGRST202|PGRST205|schema cache|does not exist|404|qr_gap_certs_v1199c130|_v1199c130/.test(String(e?.message||e||""));
const NEED_SQL="この機能の準備がまだです（SQL 052 の実行が必要です）。";
const n=v=>qrNormalizeName(String(v??""));
const loose=v=>n(String(v??"").normalize("NFKC")).toLowerCase();
function c130Busy(on,msg){try{on?v161ShowProcessing?.(msg||"処理しています"):v161HideProcessing?.()}catch(_){}}

/* ---------- マスタ ---------- */
let master=null,masterAt=0;
async function c130Master(force=false){
 if(!force&&master&&Date.now()-masterAt<20000)return master;
 try{
  const rows=await qrSelect("qr_party_names_v1280","select=kind,norm,name,status,renamed_to&limit=5000");
  const m={supplier:new Map,cooperative:new Map};
  for(const r of rows||[])if(m[r.kind])m[r.kind].set(n(r.name),{name:r.name,status:r.status,renamed_to:r.renamed_to||""});
  master=m;masterAt=Date.now();
 }catch(e){if(force||!master)master=null}
 return master;
}
function c130Forget(){master=null;masterAt=0}
function c130ActiveNames(m,kind){return[...(m?.[kind]?.values()||[])].filter(v=>v.status==="active").map(v=>v.name).sort((a,b)=>a.localeCompare(b,"ja"))}
/* 入力された名前を正式名に直す。ok:false はマスタにない名前 */
function c130ResolveIn(m,kind,name){
 const raw=String(name??"").trim();if(!raw)return{name:"",ok:true};
 const map=m?.[kind];if(!map)return{name:raw,ok:true};
 let r=map.get(n(raw)),hops=0;
 while(r&&r.status!=="active"&&r.renamed_to&&hops<6){const next=map.get(n(r.renamed_to));if(!next)return{name:r.renamed_to,ok:true,alias:true};r=next;hops++}
 if(r&&r.status==="active")return{name:r.name,ok:true,alias:r.name!==raw};
 const k=loose(raw);
 for(const v of map.values())if(v.status==="active"&&loose(v.name)===k)return{name:v.name,ok:true,alias:true};
 return{name:raw,ok:false};
}
async function c130Resolve(kind,name){return c130ResolveIn(await c130Master(),kind,name)}

/* 入力候補：マスタの正式名だけ（マスタが読めないときは今までどおり） */
if(typeof v1280Candidates==="function"){
 const candBase=v1280Candidates;
 window.v1280Candidates=async function(kind,limit){
  const m=await c130Master();if(!m)return candBase.apply(this,arguments);
  return c130ActiveNames(m,kind!=="cooperative"?"supplier":"cooperative");
 };
}

/* 保存の前に、仕入先・単協名をマスタと照らし合わせる */
async function c130CheckParties(fields){
 const m=await c130Master(true);if(!m)return true;
 for(const [kind,id] of fields){
  const el=document.getElementById(id);if(!el)continue;
  const v=String(el.value||"").trim();if(!v)continue;
  const r=c130ResolveIn(m,kind,v);
  if(r.ok){if(r.name!==el.value)el.value=r.name;continue}
  const label=KIND_LABEL[kind];
  if(!confirm(`${label}「${v}」は、仕入先・単協マスタにありません。\n\nOK：マスタに登録して、このまま保存します\nキャンセル：保存しないで入力に戻ります（候補から選び直せます）`)){try{el.focus()}catch(_){}return false}
  try{await v1280Set(kind,v,"active");c130Forget()}
  catch(e){alert(`マスタに登録できませんでした。\n${e?.message||e}`);return false}
 }
 return true;
}
function c130WrapSave(name,fields){
 const base=window[name];if(typeof base!=="function")return;
 const wrapped=async function(...a){if(!(await c130CheckParties(fields)))return;return base.apply(this,a)};
 window[name]=wrapped;try{if(name==="qrSaveLot")qrSaveLot=wrapped;else if(name==="qrSaveLotEdit")qrSaveLotEdit=wrapped}catch(_){}
}
c130WrapSave("qrSaveLot",[["supplier","qrSupplier"],["cooperative","qrCooperativeName"]]);
c130WrapSave("qrSaveLotEdit",[["supplier","qrEditSupplier"],["cooperative","qrEditCooperativeName"]]);

/* ---------- マスタの画面（管理者・青果社員） ---------- */
async function c130Usage(kind){try{const a=await callRpc("qr_party_usage_v1199c130",{p_kind:kind});return Array.isArray(a)?a:null}catch(e){return null}}
const btn=(cls,action,args,text)=>`<button class="btn ${cls}" style="padding:6px 12px;width:auto" ${seikaEventAttrs("click",action,args)}>${text}</button>`;
const line=(main,btns)=>`<div style="display:flex;align-items:center;gap:6px;padding:7px 0;border-bottom:1px solid #eee;flex-wrap:wrap"><div style="flex:1;min-width:140px">${main}</div>${btns}</div>`;
let c130LastUsage={supplier:null,cooperative:null};
async function c130PartyPage(kind="supplier",msg=""){
 setScreen("v1208CandidatePage",[kind,msg]);
 if(!canQrOperate()){alert("仕入先・単協マスタを編集できるのは管理者・青果社員です");return qrHome()}
 const k=kind!=="cooperative"?"supplier":"cooperative",label=KIND_LABEL[k],admin=canAdmin();
 pageShell("仕入先・単協マスタ","読み込んでいます",'<div class="card"><div class="notice">読み込んでいます。</div></div>');
 const [m,usage]=await Promise.all([c130Master(true),c130Usage(k)]);c130LastUsage[k]=usage;
 if(currentScreen!=="v1208CandidatePage")return;
 const map=m?.[k]||new Map,count=new Map((usage||[]).map(u=>[u.norm,u]));
 const active=c130ActiveNames(m,k),aset=new Set(active.map(n));
 const alias=[...map.values()].filter(v=>v.status==="deleted"&&v.renamed_to).sort((a,b)=>a.name.localeCompare(b.name,"ja"));
 const hidden=[...map.values()].filter(v=>v.status==="hidden").map(v=>v.name).sort((a,b)=>a.localeCompare(b,"ja"));
 const loose2=(usage||[]).filter(u=>!aset.has(u.norm)&&!(map.get(u.norm)?.status==="deleted"&&map.get(u.norm)?.renamed_to));
 const pending=(usage||[]).filter(u=>map.get(u.norm)?.status==="deleted"&&map.get(u.norm)?.renamed_to);
 const tabs=`<div class="card"><div class="row"><button class="btn ${k==="supplier"?"blue":"btn2"}" ${seikaEventAttrs("click","v1208CandidatePage",["supplier",""])}>仕入先</button><button class="btn ${k==="cooperative"?"blue":"btn2"}" ${seikaEventAttrs("click","v1208CandidatePage",["cooperative",""])}>単協名</button></div>${m?"":'<div class="err" style="margin-top:8px">マスタを読み込めませんでした（SQL 010 の実行が必要です）。</div>'}${usage?"":`<div class="notice" style="margin-top:8px">ロットの表記の件数は、${NEED_SQL}</div>`}</div>`;
 const add=`<div class="card"><b>${label}を追加</b><div class="small">ここに登録した正式名だけが、QR入庫・ロット編集の入力候補に出ます。</div><input id="v1208AddName" class="input" placeholder="例：${k==="supplier"?"中央園芸":"茨城中央"}" autocomplete="off"><button class="btn blue" style="width:100%;margin-top:10px" ${seikaEventAttrs("click","v1208AddCandidate",[k])}>追加する</button></div>`;
 const cnt=nm=>{const u=count.get(n(nm));return u?`<span class="small">（ロット ${u.lots}件）</span>`:'<span class="small">（ロットなし）</span>'};
 const list=`<div class="card"><b>マスタの${label}（正式名・${active.length}件）</b><div class="small">「名称修正」で正しい名前に直せます${admin?"（過去のロット・履歴の表記もまとめて直せます）":""}。「非表示」は候補から外します（あとで戻せます）。</div>${active.length?active.map(nm=>line(`${esc(nm)} ${cnt(nm)}`,btn("btn2","v1208RenameCandidate",[k,nm],"名称修正")+btn("btn2","v1208HideCandidate",[k,nm],"非表示"))).join(""):'<div class="small">登録がありません。</div>'}</div>`;
 const bulk=admin&&loose2.length?`<button class="btn btn2" style="width:100%;margin-top:8px" ${seikaEventAttrs("click","c130RegisterAll",[k])}>表示中の${loose2.length}件をすべてマスタに登録</button>`:"";
 const looseBox=usage?`<div class="card warn"><b>マスタにない${label}（ロットに入っている表記・${loose2.length}件）</b><div class="small">間違えて入れた表記は「正式名にまとめる」で、過去のロット・履歴の表記も正式名に直します（管理者）。正しい名前なら「マスタに登録」を押します。</div>${loose2.length?loose2.map(u=>line(`${esc(u.name)} <span class="small">（ロット ${u.lots}件・最後の入荷 ${esc(u.last_date||"-")}）</span>`,btn("btn2","c130RegisterOne",[k,u.name],"マスタに登録")+(admin?btn("blue","c130MergePage",[k,u.name,""],"正式名にまとめる"):""))).join(""):'<div class="small">ありません。ロットの表記はすべてマスタの正式名です。</div>'}${bulk}</div>`:"";
 const pendBox=admin&&pending.length?`<div class="card warn"><b>名称修正したが、ロットに元の表記が残っているもの（${pending.length}件）</b>${pending.map(u=>{const to=map.get(u.norm).renamed_to;return line(`${esc(u.name)} → ${esc(to)} <span class="small">（ロット ${u.lots}件）</span>`,btn("blue","c130MergeRun",[k,u.name,to],"ロットの表記も直す"))}).join("")}</div>`:"";
 const aliasBox=`<div class="card"><b>自動で正式名に直す表記（${alias.length}件）</b><div class="small">この表記で入力されたときは、保存のときに正式名に直します。</div>${alias.length?alias.map(v=>line(`${esc(v.name)} → <b>${esc(v.renamed_to)}</b>`,"")).join(""):'<div class="small">ありません。</div>'}</div>`;
 const hidBox=`<div class="card"><b>非表示にした${label}（${hidden.length}件）</b>${hidden.length?hidden.map(nm=>line(esc(nm),btn("btn2","v1208ShowCandidate",[k,nm],"戻す")+btn("danger","v1280DeleteCandidate",[k,nm],"削除"))).join(""):'<div class="small">ありません。</div>'}</div>`;
 pageShell("仕入先・単協マスタ","正式名の登録・名称修正・表記の統一（全員の端末に反映）",okHtml(msg)+tabs+add+looseBox+pendBox+list+aliasBox+hidBox);
}
async function c130RegisterOne(kind,name){
 try{c130Busy(true,"保存しています");await v1280Set(kind,name,"active");c130Forget();await c130PartyPage(kind,`「${name}」をマスタに登録しました`)}
 catch(e){alert(e?.message||e)}finally{c130Busy(false)}
}
async function c130RegisterAll(kind){
 if(!canAdmin())return;
 const m=await c130Master(true),aset=new Set(c130ActiveNames(m,kind).map(n)),map=m?.[kind]||new Map;
 const list=(c130LastUsage[kind]||[]).filter(u=>!aset.has(u.norm)&&!(map.get(u.norm)?.status==="deleted"&&map.get(u.norm)?.renamed_to)).map(u=>u.name);
 if(!list.length)return;
 if(!confirm(`${list.length}件をすべてマスタに登録します。\n間違えて入れた表記が混ざっていないか、先に確認してください。よろしいですか？`))return;
 c130Busy(true,"登録しています");let done=0;
 try{for(const nm of list){await v1280Set(kind,nm,"active");done++}}catch(e){alert(`${done}件まで登録しました。\n${e?.message||e}`)}finally{c130Busy(false);c130Forget()}
 return c130PartyPage(kind,`${done}件をマスタに登録しました`);
}
async function c130MergePage(kind,from,q=""){
 if(!canAdmin())return alert("表記をまとめるのは管理者だけです");
 setScreen("c130MergePage",[kind,from,q]);
 const m=await c130Master(),list=c130ActiveNames(m,kind).filter(nm=>n(nm)!==n(from)&&(!q||loose(nm).includes(loose(q))));
 const u=(c130LastUsage[kind]||[]).find(x=>x.norm===n(from));
 pageShell("正式名にまとめる",`「${from}」をどの正式名にまとめるか選びます`,`<div class="card"><div>まとめる表記：<b>${esc(from)}</b>${u?`（ロット ${u.lots}件）`:""}</div><div class="small" style="margin-top:6px">選んだ正式名に、過去のロット・入出庫の履歴・本社の入荷記録の表記も直します。元の表記は「自動で正式名に直す表記」になります。</div><input id="c130MergeQ" class="input" style="margin-top:10px" placeholder="正式名を検索" value="${esc(q)}" ${seikaEventAttrs("change","c130MergeSearch",[kind,from])}></div><div class="card">${list.length?list.slice(0,200).map(nm=>line(esc(nm),btn("blue","c130MergeRun",[kind,from,nm],"これにまとめる"))).join(""):'<div class="small">正式名がありません。先にマスタに登録してください。</div>'}</div><button class="btn btn2" style="width:100%" ${seikaEventAttrs("click","v1208CandidatePage",[kind,""])}>戻る</button>`);
}
function c130MergeSearch(kind,from){return c130MergePage(kind,from,document.getElementById("c130MergeQ")?.value||"")}
async function c130MergeRun(kind,from,to){
 if(!canAdmin())return;
 if(!confirm(`「${from}」を「${to}」にまとめます。\n過去のロット・履歴の表記も「${to}」に直ります（元に戻すには、もう一度まとめ直します）。\nよろしいですか？`))return;
 c130Busy(true,"表記を直しています");
 try{const a=await callRpc("qr_party_merge_v1199c130",{p_kind:kind,p_from:from,p_to:to});if(a&&a.ok===false)throw new Error(a.message||"まとめられませんでした");
  c130Forget();await c130PartyPage(kind,`「${from}」を「${to}」にまとめました（ロット ${a?.lots??0}件・履歴 ${a?.movements??0}件・本社 ${a?.hq_lots??0}件）`)}
 catch(e){alert(sqlMissing(e)?NEED_SQL:(e?.message||e))}finally{c130Busy(false)}
}
/* 名称修正：管理者は、ロットに同じ表記があれば過去の表記もまとめて直せる */
const renameBase=window.v1208RenameCandidate;
async function c130Rename(kind,name){
 if(!canAdmin())return renameBase?.(kind,name);
 const u=(c130LastUsage[kind]||[]).find(x=>x.norm===n(name));
 const next=prompt(`「${name}」の正しい名称を入力してください。`,name);if(next===null)return;
 const fixed=String(next).trim();if(!fixed)return alert("名称が空です");
 if(fixed===name)return;
 if(u&&u.lots>0&&confirm(`ロット ${u.lots}件に「${name}」と入っています。\n過去のロット・履歴の表記も「${fixed}」に直しますか？\n\nOK：ロットの表記も直す\nキャンセル：マスタの名前だけ直す`)){
  c130Busy(true,"表記を直しています");
  try{const a=await callRpc("qr_party_merge_v1199c130",{p_kind:kind,p_from:name,p_to:fixed});if(a&&a.ok===false)throw new Error(a.message);c130Forget();return c130PartyPage(kind,`「${name}」を「${fixed}」に直しました（ロット ${a?.lots??0}件・履歴 ${a?.movements??0}件・本社 ${a?.hq_lots??0}件）`)}
  catch(e){alert(sqlMissing(e)?NEED_SQL:(e?.message||e))}finally{c130Busy(false)}
  return;
 }
 try{c130Busy(true,"保存しています");
  if(n(fixed)===n(name))await v1280Set(kind,fixed,"active");else await v1280Set(kind,name,"deleted",fixed);
  c130Forget();return c130PartyPage(kind,`「${name}」を「${fixed}」に修正しました`)}
 catch(e){alert(e?.message||e)}finally{c130Busy(false)}
}
window.v1208CandidatePage=c130PartyPage;try{v1208CandidatePage=c130PartyPage}catch(_){}
window.v1208RenameCandidate=c130Rename;try{v1208RenameCandidate=c130Rename}catch(_){}
/* 既存の追加・非表示・戻す・削除のあとも、この画面に戻る（v1280Do が v1208CandidatePage を呼ぶ） */

/* ---------- GAP一覧 ---------- */
let gap=null,gapAt=0;
async function c130Gap(force=false){
 if(!force&&gap&&Date.now()-gapAt<60000)return gap;
 try{gap=await qrSelect("qr_gap_certs_v1199c130","select=coop_norm,coop_name,item_norm,item_name,certification,expires_on,note,imported_by_name,imported_at&order=coop_name.asc,item_name.asc&limit=5000")||[];gapAt=Date.now()}
 catch(e){if(force||!gap)gap=null}
 return gap;
}
function c130AddDays(d,k){const t=new Date(String(d).slice(0,10)+"T00:00:00");t.setDate(t.getDate()+k);return ymdKey(t)}
function c130Find(rows,coop,item,date){
 if(!rows||!coop||!item)return null;
 const c=n(coop),i=n(c130Item(item)||item),g=rows.find(r=>r.coop_norm===c&&r.item_norm===i);
 if(!g)return null;
 const d=String(date||todayKey()).slice(0,10);
 return{...g,valid:d<=String(g.expires_on).slice(0,10)};
}
function c130Status(g,today=todayKey()){const e=String(g.expires_on).slice(0,10);return e<today?"expired":e<=c130AddDays(today,SOON_DAYS)?"soon":"ok"}
function c130Md(d){if(!d)return"";const t=new Date(String(d).slice(0,10)+"T00:00:00");return`${t.getFullYear()}/${t.getMonth()+1}/${t.getDate()}`}

/* QR入庫：単協＋品目がGAP一覧にあり、入荷日が有効期限内なら、認証区分を自動で入れる */
let autoSeq=0;
async function c130GapAuto(){
 const sel=document.getElementById("qrCertification");if(!sel)return;
 const seq=++autoSeq;
 const item=document.getElementById("qrItemName")?.value||"",coopRaw=document.getElementById("qrCooperativeName")?.value||"",date=document.getElementById("qrReceivedDate")?.value||todayKey();
 let note=document.getElementById("c130GapNote");
 if(!note){sel.insertAdjacentHTML("afterend",'<div id="c130GapNote" class="small" style="margin-top:5px"></div>');note=document.getElementById("c130GapNote")}
 if(!coopRaw.trim()||!item){if(sel.dataset.c130Auto==="1"){sel.value="";sel.dataset.c130Auto=""}note.textContent="";return}
 const [rows,res]=await Promise.all([c130Gap(),c130Resolve("cooperative",coopRaw)]);
 if(seq!==autoSeq||!document.getElementById("qrCertification"))return;
 const g=c130Find(rows,res.name,item,date);
 if(g&&g.valid){
  if(sel.value===""||sel.dataset.c130Auto==="1"){sel.value=g.certification;sel.dataset.c130Auto="1";note.textContent=`GAP一覧から「${g.certification}」を自動で入れました（有効期限 ${c130Md(g.expires_on)}）。違うときは選び直してください。`}
  else note.textContent=`GAP一覧では「${g.certification}」です（有効期限 ${c130Md(g.expires_on)}）。`;
  return;
 }
 if(sel.dataset.c130Auto==="1"){sel.value="";sel.dataset.c130Auto=""}
 note.textContent=g?`GAP一覧ではこの単協・品目の有効期限が ${c130Md(g.expires_on)} で切れているため、自動では入れていません。`:"";
}
document.addEventListener("change",e=>{const id=e.target?.id;if(id==="qrCertification"){e.target.dataset.c130Auto="";const nt=document.getElementById("c130GapNote");if(nt)nt.textContent=""}else if(id==="qrItemName"||id==="qrReceivedDate"||id==="qrCooperativeName")c130GapAuto()},true);
document.addEventListener("focusout",e=>{if(e.target?.id==="qrCooperativeName")c130GapAuto()},true);
if(typeof qrUpdateCooperativeSuggestions==="function"){
 const sugBase=qrUpdateCooperativeSuggestions;
 const sug=async function(...a){const r=await sugBase.apply(this,a);if(document.getElementById("qrCertification"))c130GapAuto();return r};
 window.qrUpdateCooperativeSuggestions=sug;try{qrUpdateCooperativeSuggestions=sug}catch(_){}
}

/* Excel：ひな形・読み込み */
function c130Template(){
 if(typeof XLSX==="undefined")return alert("Excel出力の部品が読み込まれていません。");
 const wb=XLSX.utils.book_new();
 const ws=XLSX.utils.aoa_to_sheet([HEAD]);ws["!cols"]=[{wch:24},{wch:16},{wch:10},{wch:13},{wch:30}];
 const hs={font:{bold:true,color:{rgb:"FFFFFF"}},fill:{fgColor:{rgb:"1F4E78"}},alignment:{horizontal:"center"}};
 HEAD.forEach((_,i)=>{const c=XLSX.utils.encode_cell({r:0,c:i});if(ws[c])ws[c].s=hs});
 XLSX.utils.book_append_sheet(wb,ws,"GAP一覧");
 const how=XLSX.utils.aoa_to_sheet([["GAP一覧の書き方（このシートは取り込みません）"],[],["列","書き方"],["単協名","SEIKA＋の「仕入先・単協マスタ」の単協名と同じ名前で書く（マスタにない名前の行は取り込みません）"],["品目","SEIKA＋の品目マスタと同じ名前で書く（例：キャベツ、さつま芋）"],["認証区分","JGAP・GGAP・ASIAGAP（AGAP と書いても可）"],["有効期限","日付で書く（例：2027/3/31）。入荷日がこの日までなら、QR入庫で自動で入ります"],["備考","自由に書く（取り込みます）"],[],["・1行に「単協＋品目」1つ。同じ単協・品目を2行書かない"],["・取り込むと、今の一覧は全部この内容に置き換わります（取り込む前に、追加・変更・削除の件数を確認できます）"],["・仕入先ではひも付けません（市場の仕入先は複数の単協を扱うため）"],[],["記入例"],HEAD,["JA新ひたち野","キャベツ","JGAP","2027/3/31","第三者認証"]]);
 how["!cols"]=[{wch:24},{wch:80},{wch:10},{wch:13},{wch:20}];
 XLSX.utils.book_append_sheet(wb,how,"書き方");
 XLSX.writeFile(wb,"GAP一覧_取り込み用ひな形.xlsx");
}
function c130Date(v){
 if(v instanceof Date&&!isNaN(v))return ymdKey(new Date(v.getFullYear(),v.getMonth(),v.getDate()));
 if(typeof v==="number"&&v>20000&&v<80000){const t=new Date(Math.round((v-25569)*86400000));return ymdKey(new Date(t.getUTCFullYear(),t.getUTCMonth(),t.getUTCDate()))}
 const s=String(v??"").normalize("NFKC").trim();if(!s)return"";
 let m=s.match(/^(\d{4})\s*[\/\-.年]\s*(\d{1,2})\s*[\/\-.月]\s*(\d{1,2})\s*日?$/);
 if(!m){const r=s.match(/^R\s*(\d{1,2})\s*[\/\-.年]\s*(\d{1,2})\s*[\/\-.月]\s*(\d{1,2})\s*日?$/i)||s.match(/^令和\s*(\d{1,2})\s*年\s*(\d{1,2})\s*月\s*(\d{1,2})\s*日?$/);if(r)m=[0,String(2018+Number(r[1])),r[2],r[3]]}
 if(!m)return"";
 const y=Number(m[1]),mo=Number(m[2]),d=Number(m[3]),t=new Date(y,mo-1,d);
 return t.getFullYear()===y&&t.getMonth()===mo-1&&t.getDate()===d?ymdKey(t):"";
}
function c130Cert(v){const s=String(v??"").normalize("NFKC").toUpperCase().replace(/[\s\-.・]/g,"");if(s==="GLOBALGAP")return"GGAP";if(s==="AGAP")return"ASIAGAP";return CERTS.includes(s)?s:""}
/* 品目：QR対象品目、または品目設定の品目（名前の書き方の違いは吸収） */
function c130Item(v){const raw=String(v??"").trim();if(!raw)return"";const q=qrStrictItemName(raw);if(q)return q;const k=loose(raw);try{for(const it of activeItems()){const nm=String(it?.name||"").trim();if(nm&&loose(nm)===k)return nm}}catch(_){}return""}
/* 行（配列の配列）を調べる。単協はマスタの正式名、品目は品目マスタの名前に直す */
function c130Check(aoa,m){
 const rows=[],errors=[];
 let h=-1,col={};
 for(let i=0;i<Math.min(aoa.length,20);i++){const r=(aoa[i]||[]).map(x=>String(x??"").normalize("NFKC").replace(/\s/g,""));if(r.includes("単協名")&&r.includes("品目")){h=i;HEAD.forEach(k=>col[k]=r.indexOf(k));break}}
 if(h<0)return{rows,errors:[{line:"-",reason:"見出しの行（単協名・品目・認証区分・有効期限・備考）が見つかりません。ひな形を使ってください。"}]};
 for(const k of ["認証区分","有効期限"])if(col[k]<0)return{rows,errors:[{line:"-",reason:`見出し「${k}」の列がありません。`}]};
 const seen=new Map;
 for(let i=h+1;i<aoa.length;i++){
  const r=aoa[i]||[],get=k=>col[k]>=0?r[col[k]]:"";
  const coopIn=String(get("単協名")??"").trim(),itemIn=String(get("品目")??"").trim(),certIn=get("認証区分"),expIn=get("有効期限"),note=String(get("備考")??"").trim();
  if(!coopIn&&!itemIn&&!String(certIn??"").trim()&&!String(expIn??"").trim())continue;
  const line=i+1,why=[],res=coopIn?c130ResolveIn(m,"cooperative",coopIn):{ok:false},item=itemIn?c130Item(itemIn):"";
  if(!coopIn)why.push("単協名が空です");else if(!m)why.push("単協マスタを読み込めません");else if(!res.ok)why.push("単協名がマスタにありません");
  if(!itemIn)why.push("品目が空です");else if(!item)why.push("品目がSEIKA＋の品目（品目設定・QR対象品目）にありません");
  const cert=c130Cert(certIn);if(!cert)why.push("認証区分は JGAP・GGAP・ASIAGAP（AGAP）のどれかで書いてください");
  const exp=c130Date(expIn);if(!exp)why.push("有効期限が日付ではありません");
  if(!why.length){const key=n(res.name)+"|"+n(item);if(seen.has(key))why.push(`同じ単協・品目が${seen.get(key)}行目にもあります`);else seen.set(key,line)}
  const base={line,coop:coopIn,item:itemIn,cert:String(certIn??""),exp:String(expIn instanceof Date?c130Date(expIn):expIn??"")};
  if(why.length)errors.push({...base,reason:why.join("／")});
  else rows.push({line,coop_name:res.name,item_name:item,certification:cert,expires_on:exp,note,renamed:(res.name!==coopIn||item!==itemIn)?`${coopIn}・${itemIn} → ${res.name}・${item}`:""});
 }
 return{rows,errors};
}
function c130Diff(cur,rows){
 const old=new Map((cur||[]).map(g=>[g.coop_norm+"|"+g.item_norm,g])),now=new Map(rows.map(r=>[n(r.coop_name)+"|"+n(r.item_name),r]));
 const add=[],chg=[],del=[],same=[];
 for(const [k,r] of now){const o=old.get(k);if(!o)add.push(r);else if(o.certification!==r.certification||String(o.expires_on).slice(0,10)!==r.expires_on||String(o.note||"")!==String(r.note||""))chg.push({r,o});else same.push(r)}
 for(const [k,o] of old)if(!now.has(k))del.push(o);
 return{add,chg,del,same};
}
let c130Pending=null;
function c130PickFile(){const f=document.getElementById("c130File");if(f){f.value="";f.click()}}
async function c130ReadFile(input){
 const file=input?.files?.[0];if(!file)return;
 if(typeof XLSX==="undefined")return alert("Excelの部品が読み込まれていません。");
 c130Busy(true,"Excelを読み込んでいます");
 try{
  const wb=XLSX.read(await file.arrayBuffer(),{type:"array",cellDates:false});
  const name=wb.SheetNames.includes("GAP一覧")?"GAP一覧":wb.SheetNames.find(s=>s!=="書き方")||wb.SheetNames[0];
  const aoa=XLSX.utils.sheet_to_json(wb.Sheets[name],{header:1,raw:true,defval:""});
  const [m,cur]=await Promise.all([c130Master(true),c130Gap(true)]);
  const chk=c130Check(aoa,m);
  c130Pending={file:file.name,sheet:name,...chk,diff:c130Diff(cur,chk.rows)};
  return c130PreviewPage();
 }catch(e){alert(`Excelを読み込めませんでした。\n${e?.message||e}`)}finally{c130Busy(false)}
}
function c130PreviewPage(){
 if(!canAdmin())return home();
 const p=c130Pending;if(!p)return c130GapPage();
 setScreen("c130GapPage",[]);
 const d=p.diff,row=(r,extra="")=>`<tr><td>${esc(r.coop_name)}</td><td>${esc(r.item_name)}</td><td>${esc(r.certification)}</td><td>${esc(c130Md(r.expires_on))}</td><td>${extra}</td></tr>`;
 const tbl=(title,body,open=false)=>`<details ${open?"open":""} style="margin-top:8px"><summary style="font-weight:800;cursor:pointer">${title}</summary><div style="overflow:auto"><table class="table" style="font-size:13px"><tr><th>単協名</th><th>品目</th><th>認証</th><th>有効期限</th><th></th></tr>${body}</table></div></details>`;
 const errs=p.errors.length?`<div class="card err"><b>取り込まない行（${p.errors.length}件）</b><div class="small">単協名・品目がSEIKA＋のマスタと合わない行などです。マスタに登録するか、Excelを直してから取り込み直してください。</div><div style="overflow:auto;margin-top:6px"><table class="table" style="font-size:13px"><tr><th>行</th><th>単協名</th><th>品目</th><th>理由</th></tr>${p.errors.map(e=>`<tr><td>${esc(e.line)}</td><td>${esc(e.coop||"")}</td><td>${esc(e.item||"")}</td><td>${esc(e.reason)}</td></tr>`).join("")}</table></div></div>`:"";
 const renamed=p.rows.filter(r=>r.renamed);
 const ren=renamed.length?`<div class="card"><b>表記を正式名に直して取り込む行（${renamed.length}件）</b>${renamed.map(r=>`<div class="small">${esc(r.line)}行目：${esc(r.renamed)}</div>`).join("")}</div>`:"";
 const ok=p.rows.length>0;
 pageShell("GAP一覧の取り込み（確認）",`${p.file}（シート：${p.sheet}）`,`<div class="card"><b>取り込む行：${p.rows.length}件</b><div class="row" style="margin-top:8px;flex-wrap:wrap"><div class="box">追加<b>${d.add.length}</b></div><div class="box">変更<b>${d.chg.length}</b></div><div class="box">削除<b>${d.del.length}</b></div><div class="box">変わらない<b>${d.same.length}</b></div></div>
 ${tbl(`追加（${d.add.length}件）`,d.add.map(r=>row(r)).join(""),d.add.length<=20)}
 ${tbl(`変更（${d.chg.length}件）`,d.chg.map(x=>row(x.r,`前：${esc(x.o.certification)}・${esc(c130Md(x.o.expires_on))}`)).join(""),d.chg.length<=20)}
 ${tbl(`削除（${d.del.length}件）※新しい一覧にないもの`,d.del.map(o=>row(o)).join(""),d.del.length<=20)}</div>${errs}${ren}
 <div class="card">${ok?`<div class="small">取り込むと、今のGAP一覧は全部この内容に置き換わります${p.errors.length?"（取り込まない行の単協・品目は、一覧からなくなります）":""}。すでに入庫したロットの認証区分は変わりません。</div><button class="btn green" style="width:100%;margin-top:10px" ${seikaEventAttrs("click","c130Import",[])}>この内容で置き換える（${p.rows.length}件）</button>`:'<div class="err">取り込める行がありません。</div>'}<button class="btn btn2" style="width:100%;margin-top:8px" ${seikaEventAttrs("click","c130CancelImport",[])}>取り込まずに戻る</button></div>`);
}
function c130CancelImport(){c130Pending=null;return c130GapPage()}
async function c130Import(){
 const p=c130Pending;if(!p||!canAdmin())return;
 c130Busy(true,"GAP一覧を保存しています");
 try{const a=await callRpc("replace_qr_gap_certs_v1199c130",{p_rows:p.rows.map(r=>({coop_name:r.coop_name,item_name:r.item_name,certification:r.certification,expires_on:r.expires_on,note:r.note||""}))});
  if(a&&a.ok===false)throw new Error(a.message||"保存できませんでした");
  c130Pending=null;gap=null;await c130GapPage(`GAP一覧を${a?.count??p.rows.length}件で置き換えました。在庫が残っているロットに入れるときは「在庫が残るロットに入れる」を押してください。`)}
 catch(e){alert(sqlMissing(e)?NEED_SQL:`保存できませんでした。\n${e?.message||e}`)}finally{c130Busy(false)}
}
/* さかのぼり（在庫が残るロット） */
async function c130BackfillPage(){
 if(!canAdmin())return home();
 setScreen("c130BackfillPage",[]);
 pageShell("在庫が残るロットにGAPを入れる","読み込んでいます",'<div class="card"><div class="notice">対象のロットを探しています。</div></div>');
 let a;try{a=await callRpc("qr_gap_backfill_v1199c130",{p_apply:false})}catch(e){return pageShell("在庫が残るロットにGAPを入れる","エラー",`<div class="err">${esc(sqlMissing(e)?NEED_SQL:(e?.message||e))}</div><button class="btn btn2" style="width:100%" ${seikaEventAttrs("click","c130GapPage",[""])}>戻る</button>`)}
 const rows=Array.isArray(a?.rows)?a.rows:[];
 pageShell("在庫が残るロットにGAPを入れる",`対象 ${rows.length}件`,`<div class="card"><div class="small">在庫が残っていて、認証区分が空のロットのうち、単協＋品目がGAP一覧にあり、入荷日が有効期限内のものに入れます。認証区分がすでに入っているロットは変えません。</div></div>${rows.length?`<div class="card" style="overflow:auto"><table class="table" style="font-size:13px"><tr><th>品目</th><th>ロット番号</th><th>単協名</th><th>入荷日</th><th>入れる認証</th></tr>${rows.map(r=>`<tr><td>${esc(r.item_name)}</td><td>${esc(r.lot_no||"")}</td><td>${esc(r.cooperative_name)}</td><td>${esc(r.received_date||"")}</td><td><b>${esc(r.certification)}</b></td></tr>`).join("")}</table></div><button class="btn green" style="width:100%" ${seikaEventAttrs("click","c130BackfillRun",[rows.length])}>この${rows.length}件に入れる</button>`:'<div class="notice">入れるロットはありません。</div>'}<button class="btn btn2" style="width:100%;margin-top:8px" ${seikaEventAttrs("click","c130GapPage",[""])}>戻る</button>`);
}
async function c130BackfillRun(cnt){
 if(!canAdmin()||!confirm(`${cnt}件のロットに認証区分を入れます。よろしいですか？`))return;
 c130Busy(true,"認証区分を入れています");
 try{const a=await callRpc("qr_gap_backfill_v1199c130",{p_apply:true});await c130GapPage(`${a?.count??0}件のロットに認証区分を入れました。`)}
 catch(e){alert(sqlMissing(e)?NEED_SQL:(e?.message||e))}finally{c130Busy(false)}
}
/* 一覧・期限 */
async function c130GapPage(msg=""){
 if(!canAdmin()){alert("GAP一覧は管理者だけが使えます");return home()}
 setScreen("c130GapPage",[msg]);
 pageShell("GAP一覧（認証）","読み込んでいます",'<div class="card"><div class="notice">読み込んでいます。</div></div>');
 const rows=await c130Gap(true);if(currentScreen!=="c130GapPage")return;
 if(rows===null)return pageShell("GAP一覧（認証）","",`<div class="err">${NEED_SQL}</div>`);
 const today=todayKey(),exp=rows.filter(g=>c130Status(g,today)==="expired"),soon=rows.filter(g=>c130Status(g,today)==="soon");
 const last=rows.reduce((a,g)=>!a||String(g.imported_at)>String(a.imported_at)?g:a,null);
 const tr=(g,cls="")=>`<tr class="${cls}"><td>${esc(g.coop_name)}</td><td>${esc(g.item_name)}</td><td>${esc(g.certification)}</td><td>${esc(c130Md(g.expires_on))}</td><td>${esc(g.note||"")}</td></tr>`;
 const tbl=list=>`<div style="overflow:auto"><table class="table" style="font-size:13px"><tr><th>単協名</th><th>品目</th><th>認証</th><th>有効期限</th><th>備考</th></tr>${list.map(g=>tr(g)).join("")}</table></div>`;
 pageShell("GAP一覧（認証）","単協＋品目ごとの認証区分と有効期限。QR入庫で自動で入ります",`${okHtml(msg)}
 <div class="card"><b>登録 ${rows.length}件</b>${last?`<div class="small">最後の取り込み：${esc(String(last.imported_at).slice(0,16).replace("T"," "))}（${esc(last.imported_by_name||"-")}）</div>`:""}
  <input id="c130File" type="file" accept=".xlsx,.xls" style="display:none" ${seikaEventAttrs("change","c130ReadFile",[{__seikaElement:true}])}>
  <button class="btn blue" style="width:100%;margin-top:10px" ${seikaEventAttrs("click","c130PickFile",[])}>Excelを取り込む（全部置き換え）</button>
  <button class="btn btn2" style="width:100%;margin-top:8px" ${seikaEventAttrs("click","c130Template",[])}>取り込み用のひな形をダウンロード</button>
  <button class="btn btn2" style="width:100%;margin-top:8px" ${seikaEventAttrs("click","c130BackfillPage",[])}>在庫が残るロットに入れる</button></div>
 <div class="card ${exp.length?"err":""}"><b>期限切れ（${exp.length}件）</b><div class="small">QR入庫で自動では入りません。更新後の一覧を取り込んでください。</div>${exp.length?tbl(exp):""}</div>
 <div class="card ${soon.length?"warn":""}"><b>${SOON_DAYS}日以内に期限が切れる（${soon.length}件）</b>${soon.length?tbl(soon):""}</div>
 <div class="card"><details><summary style="font-weight:800;cursor:pointer">すべて見る（${rows.length}件）</summary>${tbl(rows)}</details></div>`);
}
/* 入口：QR在庫管理ホーム（管理者）とメニュー */
async function c130InjectHome(tries=0){
 if(currentScreen!=="qrHome"||!canAdmin())return;
 const box=document.querySelector(".homePrimary");
 if(!box){if(tries<40)setTimeout(()=>c130InjectHome(tries+1),100);return}
 if(document.getElementById("c130GapBtn"))return;
 const after=document.getElementById("v1280PartyBtn");
 const html=`<button id="c130GapBtn" type="button" class="btn homeBtnGap" ${seikaEventAttrs("click","c130GapPage",[""])}>GAP一覧（認証）<br><span id="c130GapSub" style="font-size:15px;font-weight:800">取り込み・有効期限の確認</span></button>`;
 if(after)after.insertAdjacentHTML("afterend",html);else box.insertAdjacentHTML("beforeend",html);
 const rows=await c130Gap();const sub=document.getElementById("c130GapSub");
 if(rows&&sub){const t=todayKey(),e=rows.filter(g=>c130Status(g,t)==="expired").length,s=rows.filter(g=>c130Status(g,t)==="soon").length;if(e||s)sub.textContent=`期限切れ ${e}件・${SOON_DAYS}日以内 ${s}件`}
}
const homeBase=qrHome;
qrHome=async function(...a){const r=await homeBase.apply(this,a);setTimeout(()=>c130InjectHome(),0);return r};window.qrHome=qrHome;
const menuBase=accountMenu;
accountMenu=function(...a){const r=menuBase.apply(this,a);const add=()=>{const m=document.querySelector(".menu");if(!m||!canAdmin()||document.getElementById("c130MenuGap"))return;const p=document.getElementById("v1280MenuParty");const h=`<button id="c130MenuGap" class="btn btn2" ${seikaEventAttrs("click","c130GapPage",[""])}>GAP一覧（認証）</button>`;if(p)p.insertAdjacentHTML("afterend",h);else m.insertAdjacentHTML("afterbegin",h)};add();setTimeout(add,320);return r};window.accountMenu=accountMenu;
{const st=document.createElement("style");st.textContent=".homeBtnGap{background:linear-gradient(90deg,#14532d 0%,#15803d 52%,#86efac 100%) !important;color:#fff !important;border-color:transparent !important;}";document.head.appendChild(st)}

Object.assign(window,{c130Master,c130Resolve,c130ResolveIn,c130CheckParties,c130PartyPage,c130RegisterOne,c130RegisterAll,c130MergePage,c130MergeSearch,c130MergeRun,
 c130Gap,c130Find,c130GapAuto,c130Template,c130Date,c130Cert,c130Check,c130Diff,c130PickFile,c130ReadFile,c130PreviewPage,c130CancelImport,c130Import,
 c130BackfillPage,c130BackfillRun,c130GapPage});

/* ---------- 操作ガイド ---------- */
try{
 const party={title:"仕入先・単協マスタ（正式名）を整える",where:"QR在庫管理 → 仕入先・単協マスタ（メニューからも開けます）",
  steps:["QR入庫・ロット編集の仕入先・単協名の候補には、このマスタに登録した正式名だけが出ます。",
   "マスタにない名前のまま保存しようとすると確認が出ます。「OK」でマスタに登録して保存、「キャンセル」で入力に戻って候補から選び直します。",
   "「名称修正」で直した元の表記は、次からは保存のときに自動で正式名に直ります（「自動で正式名に直す表記」に出ます）。",
   "「マスタにない○○（ロットに入っている表記）」に、過去のロットに入っている表記のうちマスタにないものが件数つきで出ます。正しい名前は「マスタに登録」を押します。",
   "管理者は、間違えて入れた表記を「正式名にまとめる」で正式名を選ぶと、過去のロット・入出庫の履歴・本社の入荷記録の表記もまとめて直せます。「名称修正」でも、ロットに同じ表記があれば、ロットの表記も直すか聞かれます。"],
  check:"GAP一覧は、ここに登録した単協の正式名でひも付けます。先に単協名を整えておくと、GAPが正しく入ります。",
  caution:"表記をまとめると、過去の伝票・Excel・品質評価の集計に出る名前も正式名に変わります。元に戻すときは、もう一度まとめ直します。"};
 const gapSec={title:"GAP一覧を取り込む・有効期限を確認する",where:"QR在庫管理 → GAP一覧（認証）（管理者）",
  steps:["「取り込み用のひな形をダウンロード」でExcelのひな形を出し、単協名・品目・認証区分（JGAP／GGAP）・有効期限・備考を1行ずつ書きます。ひも付けは単協＋品目です（仕入先ではひも付けません）。",
   "「Excelを取り込む（全部置き換え）」でファイルを選ぶと、追加・変更・削除の件数と中身が出ます。確認して「この内容で置き換える」を押します。",
   "単協名が仕入先・単協マスタにない行、品目が品目マスタにない行、認証区分や有効期限が正しくない行は取り込まず、「取り込まない行」に理由つきで出ます。",
   "QR入庫で単協名と品目を入れると、GAP一覧にあり入荷日が有効期限内なら、認証区分が自動で入ります。違うときは選び直せます。単協がないロット、一覧にないもの、期限が切れたものには入りません。",
   "取り込む前に入庫したロットに入れるときは「在庫が残るロットに入れる」を押し、対象を確認してから「この○件に入れる」を押します（認証区分が空で、在庫が残っているロットだけ）。",
   "画面の上に「期限切れ」と「30日以内に期限が切れる」ものが出ます。QR在庫管理のボタンにも件数が出ます。"],
  check:"伝票（埼玉・深谷・本社工場・荻沼）には、ロットの認証区分が出ます。",
  caution:"取り込むと今の一覧は全部置き換わります。すでに入庫したロットの認証区分は、取り込んだだけでは変わりません。"};
 if(typeof V195_ROLE_GUIDES!=="undefined"){
  for(const [r,list] of [["admin",[party,gapSec]],["worker",[party]]]){const g=V195_ROLE_GUIDES[r];if(!g||!Array.isArray(g.sections))continue;
   for(const s of list)if(!g.sections.some(x=>x&&x.title===s.title))g.sections.push(s)}
 }
}catch(e){}
})();
