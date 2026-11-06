
/* ===== v1.199-c74 在庫報告コピーに「先送り済み（翌日分）」を自動で追加 ===== */
(()=>{
const C74_DESTS=['本社','埼玉','深谷','荻沼'];
function c74Weight(r){
 if(r.weight!==null&&r.weight!==undefined&&r.weight!=='')return Number(r.weight);
 if(['網コンテナ','鉄コンテナ','パレテーナ'].includes(String(r.container_type||'')))return null;
 if(/(^|\s)(kg|㎏|キロ)(\s|$)/i.test(String(r.unit||'')))return Number(r.qty||0);
 const pack=Number(String(r.pack_weight??'').replace(/[^0-9.]/g,''));
 return String(r.pack_weight??'').replace(/[^0-9.]/g,'')&&Number.isFinite(pack)?Number(r.qty||0)*pack:null;
}
async function c74ForwardedRows(date){
 const rows=[];let offset=0,total=Infinity;
 while(offset<total){
  const ans=await callRpc('list_qr_outbound_history_v1144',{p_destination:null,p_work_date:date,p_include_cancelled:false,p_limit:500,p_offset:offset});
  const page=Array.isArray(ans?.rows)?ans.rows:[];total=Number(ans?.total_count||0);rows.push(...page);offset+=page.length;if(!page.length)break;
 }
 return rows.filter(r=>!r.is_cancelled&&C74_DESTS.includes(String(r.destination||''))&&v1144OutboundMemoParts(r.memo).timing==='翌日分先送り');
}
async function c74ForwardedText(){
 let rows;
 try{rows=await c74ForwardedRows(todayKey())}catch(e){return '\n\n■ 先送り済み（翌日分）\n読み込めませんでした。QR出庫履歴で確認してください。'}
 if(!rows.length)return '\n\n■ 先送り済み（翌日分）なし';
 const parts=['\n\n■ 先送り済み（翌日分）'];
 for(const dest of C74_DESTS){
  const groups=new Map;
  for(const r of rows.filter(x=>String(x.destination)===dest)){
   const key=`${r.item_name||'-'}\u0000${r.unit||''}`,g=groups.get(key)||{item:r.item_name||'-',unit:r.unit||'',qty:0,kg:0,kgOk:true};
   g.qty+=Number(r.qty||0);const w=c74Weight(r);if(w===null||!Number.isFinite(w))g.kgOk=false;else g.kg+=w;groups.set(key,g);
  }
  if(!groups.size)continue;
  parts.push(`【${dest}】`);
  for(const g of [...groups.values()].sort((a,b)=>a.item.localeCompare(b.item,'ja')))parts.push(`・${g.item}：${fmt(g.qty)}${g.unit}${g.kgOk&&g.kg>0&&!/kg|㎏|キロ/i.test(g.unit)?`（${fmt(g.kg)}kg）`:''}`);
 }
 return parts.join('\n');
}
const c74Base=makeLineCopyText;
makeLineCopyText=async function(){return (await c74Base())+(await c74ForwardedText())};
try{
 const sec={title:'在庫報告コピー（先送り済み）',where:'ホーム →「在庫報告コピー」（在庫入力のあとに自動で開くこともあります）',
  steps:['過多品目・不足品目の下に、「■ 先送り済み（翌日分）」が自動で入ります。','その日にQR出庫で「翌日分先送り」を選んで、本社・埼玉・深谷・荻沼へ出庫した分を、出庫先ごと・品目ごとにまとめます。','数量はケース数などの単位と重さ（kg）です。重さが分からないものは数量だけです。','先送りがない出庫先は書きません。1件もない日は「■ 先送り済み（翌日分）なし」と出ます。'],
  check:'取り消したQR出庫は入りません。先送りした分は出庫した時点で在庫から減っているため、過多・不足の判定には入りません。',
  caution:'通常在庫（QRで管理していない品目）の先送りは入りません。必要なら文面に書き足してから共有してください。'};
 if(typeof V198_GUIDE_SECTIONS!=='undefined')V198_GUIDE_SECTIONS.c74LineForwarded=sec;
 if(typeof V195_ROLE_GUIDES!=='undefined')for(const role of ['admin','worker']){const g=V195_ROLE_GUIDES[role];if(g&&Array.isArray(g.sections)&&!g.sections.some(x=>x.title===sec.title)){const i=g.sections.findIndex(x=>x.title==='ボタンの説明');g.sections.splice(i>=0?i+1:0,0,sec)}}
}catch(e){}
})();
