/* ===== v1.199-c110 品目設定：仕入れ担当者の変更（担当者ごとの一括交代・品目ごとの変更・QR品目を含む／青果社員も保存できる） ===== */
(function(){
const norm=v=>qrNormalizeName(v);
const canon=id=>v1151CanonicalBuyerId(id);

function buyers(){
  const seen=new Set(),out=[];
  for(const u of buyerUsers()){
    const c=canon(u.id);
    if(!c||seen.has(c))continue;
    seen.add(c);
    const cand=v1179ReferenceCandidate(u.id);
    out.push({id:u.id,canon:c,name:cand?.display_name||u.name});
  }
  return out;
}
function nameOf(c){
  const b=buyers().find(x=>x.canon===c);if(b)return b.name;
  const u=(db.users||[]).find(x=>canon(x.id)===c);if(u?.name)return u.name;
  const cand=v1179ReferenceCandidate(c);return cand?.display_name||c;
}
function isActive(c){return buyers().some(x=>x.canon===c)}
function label(c){return isActive(c)?nameOf(c):`${nameOf(c)}（利用停止など）`}

function normalIds(item){return[...new Set(assignedBuyerIds(item.id).map(canon).filter(Boolean))]}
function setNormal(itemId,ids){
  db.buyerAssignments=db.buyerAssignments||{};
  for(const uid of Object.keys(db.buyerAssignments)){
    const list=db.buyerAssignments[uid];
    if(Array.isArray(list)&&list.some(x=>String(x)===String(itemId)))db.buyerAssignments[uid]=list.filter(x=>String(x)!==String(itemId));
  }
  const bs=buyers();
  for(const c of ids){
    const key=(bs.find(b=>b.canon===c)||{id:c}).id;
    db.buyerAssignments[key]=db.buyerAssignments[key]||[];
    db.buyerAssignments[key].push(itemId);
  }
}

function ruleNames(rule){
  const names=[rule.name,...(rule.aliases||[])].filter(Boolean);
  if(rule.match==='group'&&/じゃが/.test(rule.name))names.push(...QR_POTATO_VARIETIES);
  return[...new Set(names)];
}
function ruleKeys(rule){
  const names=ruleNames(rule),set=new Set(names.map(norm)),keys=new Set(names);
  for(const k of Object.keys(qrPurchaseStaffMaster()))if(set.has(norm(k)))keys.add(k);
  return[...keys];
}
function masterBuyer(name){
  const master=qrPurchaseStaffMaster(),n=norm(name);let ref='';
  for(const[k,v]of Object.entries(master))if(norm(k)===n){ref=v;break}
  if(!ref&&qrIsPotatoVarietyName(name))ref=master['じゃが芋']||ITEM_BUYER_MASTER['じゃが芋']||'';
  const cand=v1179ReferenceCandidate(ref);
  return cand?canon(cand.legacy_user_id):'';
}
function ruleBuyer(rule){
  for(const n of [rule.name,...(rule.aliases||[])]){const id=masterBuyer(n);if(id)return id}
  return'';
}
function ruleMatchesName(rule,name){
  const set=new Set([rule.name,...(rule.aliases||[])].filter(Boolean).map(norm));
  return set.has(norm(name));
}
function ruleHasNormalItem(rule){return allSortedItems().some(it=>ruleMatchesName(rule,it.name))}
function setQr(rule,buyer){
  db.purchaseStaffByItem=db.purchaseStaffByItem||{};
  for(const k of ruleKeys(rule))db.purchaseStaffByItem[k]=buyer.name;
}
function ruleLabel(rule){return rule.match==='group'?`${rule.name}（品種すべて）`:rule.name}

function collect(from){
  return{
    normal:allSortedItems().filter(it=>normalIds(it).includes(from)),
    qr:qrManagedItemList().filter(rule=>ruleBuyer(rule)===from)
  };
}
function fromChoices(){
  const set=new Set(buyers().map(b=>b.canon));
  for(const it of allSortedItems())for(const c of normalIds(it))set.add(c);
  for(const rule of qrManagedItemList()){const c=ruleBuyer(rule);if(c)set.add(c)}
  return[...set];
}
function previewText(from){
  if(!from)return'交代前の担当者を選ぶと、対象の品目がここに出ます。';
  const t=collect(from);
  if(!t.normal.length&&!t.qr.length)return`${esc(nameOf(from))}の担当品目はありません。`;
  return`<b>${esc(nameOf(from))}の担当品目：${t.normal.length+t.qr.length}件</b><br>通常在庫（${t.normal.length}品目）：${t.normal.map(it=>esc(it.name)+(it.active===false?'（停止中）':'')).join('、')||'なし'}<br>QR品目（${t.qr.length}品目）：${t.qr.map(r=>esc(ruleLabel(r))).join('、')||'なし'}`;
}

function selectHtml(id,currentIds){
  const bs=buyers(),one=currentIds.length===1?currentIds[0]:'';
  const current=one&&bs.some(b=>b.canon===one)?one:'__keep__';
  const keepText=currentIds.length?`現在：${currentIds.map(label).join('・')}`:'現在：未設定';
  return`<select id="${esc(id)}" class="input">${current==='__keep__'?`<option value="__keep__" selected>${esc(keepText)}</option>`:''}${bs.map(b=>`<option value="${esc(b.canon)}" ${b.canon===current?'selected':''}>${esc(b.name)}</option>`).join('')}</select>`;
}
function rowHtml(kind,key,title,badge,currentIds){
  const sid=`c110Sel_${kind}_${key}`;
  return`<div class="card"><div class="itemHead"><div><b>${esc(title)}</b><div class="small">現在：${currentIds.length?currentIds.map(x=>esc(label(x))).join('、'):'未設定'}</div></div><span class="badge normal">${esc(badge)}</span></div><div style="display:flex;gap:8px;align-items:center;margin-top:8px">${selectHtml(sid,currentIds)}<button class="btn green" style="white-space:nowrap" ${seikaEventAttrs('click','c110ChangeItem',[kind,String(key)])}>変更</button></div></div>`;
}

function panelHtml(){
  const bs=buyers();
  if(!bs.length)return`<div class="card notice" id="c110Panel"><b>仕入れ担当者の変更</b><div class="small">仕入れ担当者が登録されていません。先に「ユーザー登録・管理」で登録してください。</div></div>`;
  const items=allSortedItems(),rules=qrManagedItemList().filter(r=>!ruleHasNormalItem(r));
  const froms=fromChoices();
  const normalRows=items.map(it=>rowHtml('n',it.id,`${it.sort}. ${it.name}`,it.active===false?'通常在庫・停止中':'通常在庫',normalIds(it))).join('');
  const qrRows=rules.map(r=>{const idx=qrManagedItemList().indexOf(r),c=ruleBuyer(r);return rowHtml('q',idx,ruleLabel(r),'QR品目',c?[c]:[])}).join('');
  return`<div class="card notice" id="c110Panel"><b>仕入れ担当者の変更</b><div class="small">担当者が代わったときに、通常在庫とQR品目の担当者をここで変更します。新しく入庫するロットから、新しい担当者が自動で入ります。過去に入庫したロット・品質評価に記録された担当者は変わりません。</div>
<div style="margin-top:12px"><b>担当者ごとにまとめて交代</b></div>
<label class="label">交代前の担当者</label><select id="c110From" class="input" ${seikaEventAttrs('change','c110Preview',[])}><option value="">選択してください</option>${froms.map(c=>`<option value="${esc(c)}">${esc(label(c))}</option>`).join('')}</select>
<label class="label" style="margin-top:8px">交代後の担当者</label><select id="c110To" class="input"><option value="">選択してください</option>${bs.map(b=>`<option value="${esc(b.canon)}">${esc(b.name)}</option>`).join('')}</select>
<div id="c110Preview" class="memo small" style="margin-top:8px">${previewText('')}</div>
<button class="btn green" style="width:100%;margin-top:10px" ${seikaEventAttrs('click','c110Handover',[])}>担当品目をまとめて交代</button>
<details style="margin-top:14px"><summary><b>品目ごとに担当者を変更</b>（通常在庫 ${items.length}品目・QR品目 ${rules.length}品目）</summary><div style="margin-top:8px"><div class="small">QRの品目で通常在庫にも同じ名前の品目がある場合は、通常在庫の担当者を変えるとQR入庫の自動入力も同じ担当者になります。複数人の担当にしたい通常在庫の品目は、各品目の「編集」から設定します。</div>${normalRows}${qrRows}</div></details></div>`;
}

const itemsPageCore=itemsPage;
itemsPage=function(msg=''){
  itemsPageCore(msg);
  if(!canManageItems())return;
  const wrap=document.querySelector('main.wrap');if(!wrap)return;
  const flash=wrap.querySelector('.ok.flash'),html=panelHtml();
  if(flash)flash.insertAdjacentHTML('afterend',html);else wrap.insertAdjacentHTML('afterbegin',html);
};
window.itemsPage=itemsPage;

window.c110Preview=function(){
  const box=document.getElementById('c110Preview');if(!box)return;
  box.innerHTML=previewText(document.getElementById('c110From')?.value||'');
};

window.c110Handover=function(){
  if(!canManageItems())return;
  const from=document.getElementById('c110From')?.value||'',to=document.getElementById('c110To')?.value||'';
  if(!from||!to)return alert('交代前と交代後の担当者を選んでください');
  if(from===to)return alert('交代前と交代後が同じです');
  const target=buyers().find(b=>b.canon===to);
  if(!target)return alert('交代後の担当者が見つかりません');
  const t=collect(from),total=t.normal.length+t.qr.length;
  if(!total)return alert(`${nameOf(from)}の担当品目はありません`);
  if(!confirm(`${nameOf(from)}の担当品目 ${total}件（通常在庫 ${t.normal.length}・QR品目 ${t.qr.length}）を、${target.name}に交代します。\n過去に入庫したロット・品質評価の担当者は変わりません。よろしいですか？`))return;
  for(const it of t.normal){
    const next=[...new Set(normalIds(it).map(c=>c===from?to:c))];
    setNormal(it.id,next);
  }
  for(const rule of t.qr)setQr(rule,target);
  save();
  itemsPage(`${nameOf(from)}の担当品目 ${total}件を${target.name}に交代しました`);
};

window.c110ChangeItem=function(kind,key){
  if(!canManageItems())return;
  const v=document.getElementById(`c110Sel_${kind}_${key}`)?.value||'';
  if(!v||v==='__keep__')return alert('変更後の担当者を選んでください');
  const target=buyers().find(b=>b.canon===v);
  if(!target)return alert('担当者が見つかりません');
  if(kind==='n'){
    const it=(db.items||[]).find(x=>x.id===key&&x.deleted!==true);
    if(!it)return alert('品目が見つかりません');
    setNormal(it.id,[target.canon]);
    for(const rule of qrManagedItemList())if(ruleMatchesName(rule,it.name))setQr(rule,target);
    save();
    return itemsPage(`${it.name}の仕入れ担当者を${target.name}に変更しました`);
  }
  const rule=qrManagedItemList()[Number(key)];
  if(!rule)return alert('品目が見つかりません');
  setQr(rule,target);
  save();
  itemsPage(`${ruleLabel(rule)}の仕入れ担当者を${target.name}に変更しました`);
};

const rolePayloadCore=v188RolePayload;
v188RolePayload=function(payload,role=db?.role){
  const out=rolePayloadCore(payload,role);
  if(role==='worker'&&out&&Object.prototype.hasOwnProperty.call(payload||{},'buyerAssignments'))out.buyerAssignments=v188Clone(payload.buyerAssignments);
  return out;
};
window.v188RolePayload=v188RolePayload;

{
  const section={title:'仕入れ担当者を変更する',where:'ホーム → 品目設定 → 一番上の「仕入れ担当者の変更」',
    steps:['担当者が代わるときは「担当者ごとにまとめて交代」を使います。交代前と交代後の担当者を選ぶと、対象の品目が下に出ます。','内容を確認して「担当品目をまとめて交代」を押し、確認画面で「OK」を押します。通常在庫とQR品目が一緒に交代されます。','1つの品目だけ変えるときは「品目ごとに担当者を変更」を開き、品目の担当者を選んで「変更」を押します。','通常在庫の品目を複数人の担当にしたいときは、従来どおり各品目の「編集」から設定します。'],
    check:'品目設定の各品目の担当者、発注候補、QR入庫の担当者の自動入力が新しい担当者になっていることを確認します。上部が「クラウド保存済み」になるまで待ちます。',
    caution:'過去に入庫したロットや品質評価に記録された担当者は変わりません。すでに在庫があるロットの品質評価の確認は、これまでの担当者のままです。担当者の登録・停止は「ユーザー登録・管理」で行います。'};
  for(const role of ['admin','worker']){
    const guide=V195_ROLE_GUIDES[role];
    if(guide&&Array.isArray(guide.sections)&&!guide.sections.some(x=>x.title===section.title))guide.sections.push({...section});
  }
}
})();
