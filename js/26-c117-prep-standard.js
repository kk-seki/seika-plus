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
const shared={title:'下処理日報をあとから登録・確認・編集する',where:'下処理ホーム → 新規後入力／未確定一覧',steps:['端末を使えなかった作業は「新規後入力」で作業日・開始／終了時刻・場所・仕掛品・作業者を入れます。時刻は日本時間です。','原料は貼り紙のQRを読みます。各ロットで「使い切った」か「一部使用」を選びます。未使用なら入荷数量、以前使用したロットなら使用可能な残りが自動で入ります。一部使用だけ数量を入力します。','それぞれの出来高kgを入れると、合計使用原料kg・出来高・廃棄・歩留まり率が表示されます。廃棄は使用原料kg−合計出来高kgです。出来高の方が多いときは入力を確認してください。','休憩は開始・終了を入れ、休憩に入らなかった人だけを選びます。中断は全員を対象にします。参加者の時刻も同じ画面で直せます。','原料の産地・仕入先・単協・入荷日などを同じ画面で確認し、日報を保存します。終了後も社員の確定前なら、下処理班で全項目を確認・編集できます。'],check:'保存後は社員の確認待ちです。在庫は保存だけでは減らず、在庫反映オンのとき社員の確定で減ります。',caution:'ほかの日報に使用数が保存されている分は使えません。ほかの端末で更新された場合は再確認します。確定後の訂正は本社社員・管理者に依頼してください。'};
const standardGuide={title:'標準歩留まりを設定して日報を確認する',where:'下処理マスタ → 標準歩留まりの設定／下処理の確認',steps:['仕掛品ごとに標準歩留まり率と許容差を設定します。許容差の初期値は±5ポイントです。','キャベツ1/4芯＋1/4葉は、合計出来高の専用標準を設定します。','日報の歩留まりは、出来高÷合計使用原料kg×100です。範囲内は緑、範囲外は赤、未設定は灰色で説明も表示されます。','原料の詳細・入力内容・標準からの差を確認して確定します。標準範囲外でも自動で確定を禁止しません。'],check:'標準は日報の保存時に記録され、設定変更だけで過去の日報の基準は変わりません。',caution:'設定は本社社員・管理者だけが変更できます。この確認で使うのは歩留まり率で、歩留まり原価ではありません。'};
for(const role of ['admin','hq_worker','hq_prep']){
 const guide=V195_ROLE_GUIDES[role];if(!guide?.sections)continue;
 if(!guide.sections.some(s=>s.title===shared.title))guide.sections.push({...shared});
 if(role!=='hq_prep'&&!guide.sections.some(s=>s.title===standardGuide.title))guide.sections.push({...standardGuide});
 guide.sections=guide.sections.map(section=>{
  if(section.title==='下処理を終える（パートさん）')return {...section,steps:['「作業終了」を押します。','「日報を入力・編集」で原料ごとの使い切り・一部使用と出来高を確認します。廃棄と歩留まりは自動計算します。','保存後に清掃へ進み、清掃が終わったら「清掃終了」を押します。','未確定なら下処理班でも作業日・原料・出来高・作業者・時刻・休憩を編集できます。'],caution:'確定は本社社員がします。確定後の訂正は本社社員・管理者だけです。'};
  if(section.title==='下処理を確認して確定する（本社社員）')return {...section,steps:['「未確定」の一覧から、下処理の「確認して確定」を押します。','使用原料・出来高・自動計算された廃棄と歩留まり率を確認します。標準範囲外は赤、範囲内は緑、未設定は灰色です。','全体の編集が必要なら「日報全体を確認・編集する」を開いて保存します。','内容を確認して確定します。確定後の訂正は従来どおり理由を記録します。']};
  return section;
 });
}
})();
