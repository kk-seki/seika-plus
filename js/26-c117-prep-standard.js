(()=>{
'use strict';
const X=window.__h2;
const {r2,sel2,h2CanBoss,h2Masters,h2Materials,h2Works,h2Err,h2Val,num2,btnAttr,h2UsedKg}=X;
const key=ids=>[...ids].sort().join(',');
let standards=[],masters=[];
function c117StandardBadge(w,mats){
 const used=h2UsedKg(mats),rate=!used.unknown&&used.kg>0&&w.yield_kg!=null?Number(w.yield_kg)/used.kg*100:null;
 const standard=w.standard_rate==null?null:Number(w.standard_rate),tolerance=Number(w.tolerance_points??5);
 const known=standard!=null&&Number.isFinite(standard),outside=known&&rate!=null&&Math.abs(rate-standard)>tolerance+1e-9;
 const color=!known||rate==null?'#64748b':outside?'#b91c1c':'#15803d';
 const label=!known?'標準未設定':rate==null?'歩留まり未計算':outside?'標準範囲外':'標準範囲内';
 return `<div class="c117StandardBadge" style="padding:10px;border:2px solid ${color};border-radius:10px;margin-top:8px;color:${color}"><b>歩留まり ${rate==null?'—':`${Math.round(rate*10)/10}%`} ／ ${label}</b>${known?`<div class="small">標準 ${standard}% ／ 許容差 ±${tolerance}ポイント（${Math.max(0,standard-tolerance)}〜${Math.min(100,standard+tolerance)}%）</div>`:''}</div>`;
}
function standardForm(ids,title){
 const saved=standards.find(s=>key(s.master_ids)===key(ids));
 return `<div class="card c117StandardForm" data-masters="${esc(JSON.stringify(ids))}"><b>${esc(title)}</b><div class="row" style="margin-top:8px"><div><label class="label">標準歩留まり率（%・空欄は未設定）</label><input class="input c117StandardRate" inputmode="decimal" value="${saved?.standard_rate==null?'':esc(String(saved.standard_rate))}"></div><div><label class="label">許容差（ポイント）</label><input class="input c117StandardTolerance" inputmode="decimal" value="${esc(String(saved?.tolerance_points??5))}"></div></div><button class="btn btn2" style="width:100%;margin-top:8px" ${btnAttr('c117StandardSave',[ids])}>標準歩留まりを保存</button></div>`;
}
async function c117StandardSave(ids){
 if(!h2CanBoss()||X.H2.busy)return;
 const host=[...document.querySelectorAll('.c117StandardForm')].find(el=>key(JSON.parse(el.dataset.masters))===key(ids));if(!host)return;
 const raw=host.querySelector('.c117StandardRate').value.trim(),rate=raw?num2(raw):null,tolerance=num2(host.querySelector('.c117StandardTolerance').value);
 if(rate!=null&&(!Number.isFinite(rate)||rate<0||rate>100)||!Number.isFinite(tolerance)||tolerance<0||tolerance>100)return alert('標準歩留まり率と許容差は0〜100の数字で入れてください');
 X.H2.busy=true;
 try{const result=await r2('hq_prep_standard_save_v1199c117',{p_master_ids:ids,p_standard_rate:rate,p_tolerance_points:tolerance});if(!result?.ok)throw new Error(result?.message||'標準歩留まりを保存できませんでした');alert('標準歩留まりを保存しました。次に日報を保存すると、この標準が記録されます。')}
 catch(e){alert(h2Err(e))}finally{X.H2.busy=false}
}
const masterBase=hqPrepMasterPage;
hqPrepMasterPage=async function(...args){
 const result=await masterBase.apply(this,args);if(!h2CanBoss()||currentScreen!=='hqPrepMasterPage')return result;
 const host=document.querySelector('main.wrap');if(!host)return result;
 const panel=document.createElement('section');panel.id='c117Standards';host.append(panel);
 try{
  [masters,standards]=await Promise.all([h2Masters(true),sel2('hq_prep_standards_v1199c117','select=*')]);
  if(currentScreen!=='hqPrepMasterPage'||!panel.isConnected)return result;
  const pair=masters.filter(m=>m.active&&m.item_name==='キャベツ'&&['1/4芯','1/4葉'].includes(String(m.name).replace(/[\s　]/g,'')));
  panel.innerHTML=`<div class="card"><b>標準歩留まりの設定</b><div class="small">本社社員・管理者が仕掛品ごとに設定します。範囲内は緑、範囲外は赤、未設定は灰色です。範囲外でも内容を確認して確定できます。標準は日報の保存時に記録し、設定変更だけで過去の日報の基準は変えません。</div></div>${masters.filter(m=>m.active).map(m=>standardForm([m.id],`${m.item_name} → ${m.name}`)).join('')}${pair.length===2?standardForm(pair.map(m=>m.id),'キャベツ → 1/4芯＋1/4葉（合計出来高の標準）'):''}`;
 }catch(e){panel.innerHTML=`<div class="err">標準歩留まりを読み込めません：${esc(h2Err(e))}</div>`}
 return result;
};
window.hqPrepMasterPage=hqPrepMasterPage;
const confirmBase=hqPrepConfirmPage;
hqPrepConfirmPage=async function(id,...args){
 try{const probe=(await h2Works(`select=id,c120_flow&id=eq.${id}&limit=1`))[0];if(probe?.c120_flow===true)return typeof window.c117ReportPage==='function'?window.c117ReportPage(id):undefined}catch(e){return typeof window.c117ReportPage==='function'?window.c117ReportPage(id):undefined}
 const result=await confirmBase.call(this,id,...args);if(currentScreen!=='hqPrepConfirmPage'||!h2CanBoss())return result;
 const [works,mats]=await Promise.all([h2Works(`select=*&id=eq.${id}`),h2Materials([id])]);
 if(!works[0]||currentScreen!=='hqPrepConfirmPage')return result;
 const work=works[0],host=document.querySelector('main.wrap');if(!host)return result;
 host.insertAdjacentHTML('afterbegin',`${c117StandardBadge(work,mats)}<button class="btn btn2" style="width:100%;margin-top:8px" ${btnAttr('c117ReportPage',[id])}>日報全体を確認・編集する</button>`);
 const waste=document.getElementById('h2CfW');if(waste)waste.readOnly=true;
 const update=()=>{
  const changed=mats.map(m=>({...m,qty:document.querySelector(`.h2CfQty[data-id="${CSS.escape(m.id)}"]`)?.value.trim()?num2(document.querySelector(`.h2CfQty[data-id="${CSS.escape(m.id)}"]`).value):NaN}));
  const inputs=[...document.querySelectorAll('.h2OutputQty')],yieldKg=inputs.length?inputs.reduce((n,el)=>n+num2(el.value),0):num2(h2Val('h2CfY'));
  const used=h2UsedKg(changed),difference=used.kg-yieldKg;
  if(waste)waste.value=!used.unknown&&Number.isFinite(difference)&&difference>=0?String(Math.round(difference*1000000)/1000000):'';
  const badge=host.querySelector('.c117StandardBadge');if(badge)badge.outerHTML=c117StandardBadge({...work,yield_kg:yieldKg},changed);
 };
 host.querySelectorAll('.h2CfQty,.h2OutputQty,#h2CfY').forEach(el=>el.addEventListener('input',update));update();
 return result;
};
window.hqPrepConfirmPage=hqPrepConfirmPage;
Object.assign(window,{c117StandardBadge,c117StandardSave});
const shared={title:'下処理日報を確認して社員へ送る',where:'下処理の作業終了後 → 日報を入力・編集',steps:['作業終了後に、作業日・開始／終了時刻・場所・原料・仕掛品・出来高・作業者を確認します。時刻は日本時間です。','仕掛品は、選んだ原料と同じ品目から複数選べます。マスタにない仕掛品は名前を入力できます。手入力した仕掛品は今回の作業だけに使われ、使用期限は2日です。','出来高kgを入れると、使用原料kg・出来高・廃棄・歩留まり率が表示されます。廃棄は使用原料kg−出来高kgです。出来高の方が多いときは入力を確認してください。','確認画面で時刻、全作業者、原料ロットとkg、出来高、廃棄、歩留まり、差し戻し理由を確認します。「戻って編集する」なら入力内容は残ります。','まず「下書きを保存する」を押し、内容が正しければ「この内容で社員の確認待ちにする」を押します。下処理班は入力した人の氏名を選び、サインを書いてから送ります。社員は入力者サインを確認し、確認または理由付きで差し戻します。'],check:'下処理班は社員の確認前と差し戻し後に編集できます。差し戻し後は同じ確認手順で再送します。在庫は社員の確定時にだけ反映されます。',caution:'清掃時間は日報の対象外です。休憩・中断と後から入力した休憩は日報で確認・保存します。確定後の訂正と差し戻しは本社社員・管理者が行います。'};
const standardGuide={title:'標準歩留まりを設定して日報を確認する',where:'下処理マスタ → 標準歩留まりの設定／下処理の確認',steps:['仕掛品ごとに標準歩留まり率と許容差を設定します。許容差の初期値は±5ポイントです。','キャベツ1/4芯＋1/4葉は、合計出来高の専用標準を設定します。','日報の歩留まりは、出来高÷合計使用原料kg×100です。範囲内は緑、範囲外は赤、未設定は灰色で説明も表示されます。','原料の詳細・入力内容・標準からの差を確認して確定します。標準範囲外でも自動で確定を禁止しません。'],check:'標準は日報の保存時に記録され、設定変更だけで過去の日報の基準は変わりません。',caution:'設定は本社社員・管理者だけが変更できます。この確認で使うのは歩留まり率で、歩留まり原価ではありません。'};
for(const role of ['admin','hq_worker','hq_prep']){
 const guide=V195_ROLE_GUIDES[role];if(!guide?.sections)continue;
 if(!guide.sections.some(s=>s.title===shared.title))guide.sections.push({...shared});
 if(role!=='hq_prep'&&!guide.sections.some(s=>s.title===standardGuide.title))guide.sections.push({...standardGuide});
 guide.sections=guide.sections.map(section=>{
  if(section.title==='下処理を終える（パートさん）')return {...section,steps:['使用数を保存し、終了時刻を確認して「作業終了して日報へ」を押します。','日報で原料ごとの使い切り・一部使用と出来高を確認します。廃棄と歩留まりは自動計算します。','「内容を確認する」から下書きを保存し、「この内容で社員の確認待ちにする」を押します。清掃時間は日報に記録しません。','社員の確定前と差し戻し後は、下処理班でも作業日・原料・出来高・作業者・時刻・休憩を編集できます。'],caution:'確定は本社社員がします。確定後の訂正は本社社員・管理者だけです。'};
  if(section.title==='下処理を確認して確定する（本社社員）')return {...section,steps:['下処理の確認待ちの作業を開き、日報の時刻・原料・出来高・廃棄・歩留まり率を確認します。','不備は日報を編集して保存するか、理由を入れて下処理班へ差し戻します。','提出された内容が正しければ「確認済みにする」を押します。','確定後も本社社員・管理者は理由を入れて時刻と内容を訂正できます。差し戻し後は下処理班が訂正して再提出します。']};
  return section;
 });
}
})();
