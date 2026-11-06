
/* ===== v1.199-c68 入替品登録（日報登録の出来高の候補を登録・並び替え・候補から外す） ===== */
(function(){
let c68Rows=[],c68Loaded=false,c68Err='';
const canEdit=()=>typeof v1115CanTrimmingEdit==='function'?v1115CanTrimmingEdit():false;
async function c68Fetch(){
 try{const a=await callRpc('list_trim_output_candidates_v1680',{p_include_hidden:true});if(!a||a.ok===false)throw new Error(a&&a.message||'読み込めませんでした');c68Rows=Array.isArray(a.rows)?a.rows:[];c68Err=''}
 catch(e){c68Err=e&&e.message||String(e)}
 c68Loaded=true;
}
function c68Render(){
 if(currentScreen!=='c68ExchangeRegPage')return;
 const edit=canEdit(),act=c68Rows.filter(r=>r.active!==false),hid=c68Rows.filter(r=>r.active===false);
 const row=(r,i,list)=>`<div class="card" style="margin:8px 0;padding:10px 12px"><div class="small">${r.active===false?'候補から外しています':`${i+1}番目`}</div>
${edit?`<input id="c68Name_${esc(r.id)}" class="input" value="${esc(r.name)}" autocomplete="off">
<div class="row" style="margin-top:6px;gap:6px;flex-wrap:wrap">
<button class="btn" style="padding:6px 10px" ${seikaEventAttrs('click','c68Save',[r.id])}>名前を保存</button>
${r.active===false?`<button class="btn" style="padding:6px 10px" ${seikaEventAttrs('click','c68SetActive',[r.id,true])}>候補に戻す</button>`:`<button class="btn" style="padding:6px 10px" ${i===0?'disabled':''} ${seikaEventAttrs('click','c68Move',[r.id,-1])}>↑ 上へ</button><button class="btn" style="padding:6px 10px" ${i===list.length-1?'disabled':''} ${seikaEventAttrs('click','c68Move',[r.id,1])}>↓ 下へ</button><button class="btn" style="padding:6px 10px" ${seikaEventAttrs('click','c68SetActive',[r.id,false])}>候補から外す</button>`}
</div>`:`<b>${esc(r.name)}</b>`}</div>`;
 pageShell('入替品登録','日報登録の出来高（入替品）の候補',`
<div class="notice"><b>ここで登録した品目が、日報登録の「③ 出来高」の▼に候補として出ます。</b><div class="small">上から順に▼に並びます。「候補から外す」と▼には出なくなりますが、消えないので「候補に戻す」で戻せます。在庫は変わりません。</div></div>
${c68Err?`<div class="warn">候補を読み込めませんでした。${esc(c68Err)}<br>SQL（db/026）が未実行の可能性があります。</div>`:''}
${edit?`<div class="card"><b>新しい候補を追加</b><label class="label" style="margin-top:6px">名前</label><input id="c68NewName" class="input" placeholder="例：白菜 15kg/入替品" autocomplete="off"><button class="btn green" style="width:100%;margin-top:8px" ${seikaEventAttrs('click','c68Add',[])}>追加する</button></div>`:'<div class="small">候補の登録は管理者・青果社員だけができます。</div>'}
<div class="card" style="padding:10px 14px"><b>候補（${act.length}件）</b></div>
${c68Loaded?(act.length?act.map((r,i)=>row(r,i,act)).join(''):'<div class="small">候補がありません。</div>'):'<div class="small">読み込み中です…</div>'}
${hid.length?`<div class="card" style="padding:10px 14px;margin-top:14px"><b>候補から外した品目（${hid.length}件）</b></div>${hid.map((r,i)=>row(r,i,hid)).join('')}`:''}`);
}
async function c68ExchangeRegPage(){
 setScreen('c68ExchangeRegPage',[]);c68Loaded=false;c68Render();
 await c68Fetch();c68Render();
}
async function c68Call(name,args){
 const a=await callRpc(name,args);
 if(!a||a.ok===false){alert(a&&a.message||'保存できませんでした');return false}
 if(window.c68ResetCands)window.c68ResetCands();
 await c68Fetch();c68Render();return true;
}
async function c68Add(){const el=document.getElementById('c68NewName'),v=String(el&&el.value||'').trim();if(!v)return alert('名前を入力してください');await c68Call('save_trim_output_candidate_v1680',{p_id:null,p_name:v,p_active:true})}
async function c68Save(id){const r=c68Rows.find(x=>String(x.id)===String(id));const v=String(document.getElementById(`c68Name_${id}`)?.value||'').trim();if(!v)return alert('名前を入力してください');if(r&&v===r.name)return;if(!confirm(`名前を「${v}」に変えます。\n\nこれまでに登録した日報の名前は変わりません。`))return;await c68Call('save_trim_output_candidate_v1680',{p_id:id,p_name:v,p_active:r?r.active!==false:true})}
async function c68SetActive(id,on){const r=c68Rows.find(x=>String(x.id)===String(id));if(!r)return;if(!on&&!confirm(`「${r.name}」を候補から外します。\n\n日報登録の▼に出なくなります（あとで戻せます）。`))return;await c68Call('save_trim_output_candidate_v1680',{p_id:id,p_name:r.name,p_active:!!on})}
async function c68Move(id,dir){await c68Call('move_trim_output_candidate_v1680',{p_id:id,p_dir:Number(dir)})}

const prodBase=v1200ProductionHome;
v1200ProductionHome=function(...args){
 const r=prodBase.apply(this,args);
 try{const box=document.querySelector('.homePrimary');if(box&&!box.querySelector('.homeBtnExchangeReg'))box.insertAdjacentHTML('beforeend',`<button class="btn homeBtnExchangeReg" ${seikaEventAttrs('click','c68ExchangeRegPage',[])}>入替品登録<br><span style="font-size:15px;font-weight:800">出来高（入替品）の候補</span></button>`)}catch(e){}
 return r;
};
window.v1200ProductionHome=v1200ProductionHome;
const trimBase=trimmingPage;
trimmingPage=function(...args){if(window.c68ResetCands)window.c68ResetCands();return trimBase.apply(this,args)};
window.trimmingPage=trimmingPage;

const st=document.createElement('style');
st.textContent='.homePrimary .btn.homeBtnExchangeReg,.viewerHome .btn.homeBtnExchangeReg{background:linear-gradient(90deg,#86198f 0%,#c026d3 48%,#f0abfc 100%) !important;color:#fff !important;border-color:transparent !important}';
document.head.appendChild(st);

try{
 const sec={title:'入替品を登録する（日報の出来高の候補）',where:'ホーム → 製造・歩留まり → 入替品登録',
  steps:['「新しい候補を追加」に名前を入れて「追加する」を押します。日報登録の「③ 出来高」の▼に出るようになります。',
   '名前を直すときは、欄を書き換えて「名前を保存」を押します。これまでに登録した日報の名前は変わりません。',
   '「↑ 上へ」「↓ 下へ」で▼に出る順番を変えます。',
   '使わなくなった品目は「候補から外す」を押します。消えないので、下の「候補から外した品目」から「候補に戻す」で戻せます。'],
  check:'日報登録を開き直し、「③ 出来高」の▼に候補が出るか確かめます。',
  caution:'登録・変更できるのは管理者・青果社員です。在庫は変わりません。'};
 if(typeof V198_GUIDE_SECTIONS!=='undefined')V198_GUIDE_SECTIONS.c68ExchangeReg=sec;
 if(typeof V195_ROLE_GUIDES!=='undefined')for(const role of ['admin','worker']){const g=V195_ROLE_GUIDES[role];if(!g||!Array.isArray(g.sections)||g.sections.some(x=>x.title===sec.title))continue;const i=g.sections.findIndex(x=>x.title==='日報を登録する');g.sections.splice(i<0?g.sections.length:i+1,0,sec)}
}catch(e){}
Object.assign(window,{c68ExchangeRegPage,c68Add,c68Save,c68SetActive,c68Move});
})();
