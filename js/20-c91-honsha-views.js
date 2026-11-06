
/* ===== v1.199-c91 本社アカウントで石岡の分析・メモ・価格表・品質・QR出庫履歴を見る／トレースを画面で見る／荷受け担当の下処理出庫 ===== */
(()=>{
const C91_VIEW=["hq_worker","hq_clerk"];
const c91Hq=()=>C91_VIEW.includes(db?.role);
const C91_BTNS=[["c91BtnOutHist","v1144QrOutboundHistoryPage","QR出庫履歴","出庫先・日付ごとのQR出庫"],["c91BtnQList","v1103QualityListPage","品質評価一覧","QRロットごとの品質評価と写真"],["c91BtnQRep","v136SupplierQualityPage","品質レポート","仕入先・品目・月ごとの良品率"],["c91BtnAna","c81AnalysisPage","在庫・出庫の分析","品目ごとの在庫の推移と出庫数量"],["c91BtnMemo","marketMemoPage","産地状況・市場動向メモ","仕入れ担当者のメモを見る"],["c91BtnPrice","purchasePricesPage","仕入れ価格表","週ごとの市場価格・契約価格"]];
window.c91IshiokaButtons=function(){if(!c91Hq())return"";return C91_BTNS.map(([c,a,l,d])=>`<button class="btn ${c}" ${seikaEventAttrs("click",a,[])}>${l}<br><span style="font-size:14px;font-weight:700">${d}</span></button>`).join("")};
const st=document.createElement("style");
st.textContent=`.c91BtnOutHist{background:linear-gradient(135deg,#3b82f6,#1e40af)!important;color:#fff!important}
.c91BtnQList{background:linear-gradient(135deg,#d946ef,#86198f)!important;color:#fff!important}
.c91BtnQRep{background:linear-gradient(135deg,#f472b6,#be185d)!important;color:#fff!important}
.c91BtnAna{background:linear-gradient(135deg,#22d3ee,#0e7490)!important;color:#fff!important}
.c91BtnMemo{background:linear-gradient(135deg,#84cc16,#3f6212)!important;color:#fff!important}
.c91BtnPrice{background:linear-gradient(135deg,#ca8a04,#854d0e)!important;color:#fff!important}
.c91Info{display:grid;grid-template-columns:1fr 1fr;gap:4px 12px}.c91Info div{border-bottom:1px solid #e2e8f0;padding:4px 0}.c91Info span{display:block;font-size:12px;color:#64748b}
.c91Ev{border-left:6px solid #3b82f6;background:#f8fafc;border-radius:10px;padding:8px 10px;margin:8px 0}.c91Ev.hq{border-left-color:#10b981}
.c91EvTop{display:flex;gap:8px;align-items:baseline;flex-wrap:wrap}.c91At{margin-left:auto;font-size:13px;color:#475569}
.c91Pl{font-size:12px;font-weight:800;color:#fff;background:#3b82f6;border-radius:6px;padding:1px 6px}.c91Ev.hq .c91Pl{background:#10b981}.c91EvBody{margin-top:4px}`;
document.head.appendChild(st);
const memoBase=canViewMemo;canViewMemo=function(){return memoBase.apply(this,arguments)||c91Hq()};window.canViewMemo=canViewMemo;
const backBase=goBack;goBack=function(...a){if(currentScreen==="hqTraceView")return window.hqTraceViewBack();return backBase.apply(this,a)};window.goBack=goBack;
try{
 const sec={title:"本社のアカウントで石岡の情報を見る",where:"本社ホーム →「石岡の画面へ」",steps:["上の「石岡の画面へ」を押すと、石岡青果センターの画面（確認のみ）になります。","QR品目別在庫量・QRロット一覧・在庫表のほか、QR出庫履歴・品質評価一覧・品質レポート・在庫・出庫の分析・産地状況・市場動向メモ・仕入れ価格表を見られます。","QR出庫履歴は、出庫先と日付を選んで「表示」を押します。「ロット詳細を見る」でそのロットが開きます。","「本社の画面へ」で本社に戻ります。"],check:"",caution:"見るだけです。価格の入力、メモの書き込み、品質評価の「確認済み」、出庫・取消などはできません。"};
 const tr={title:"ロットのトレースを画面で見る",where:"本社のロットの画面 または 石岡のQRロットの画面 → いちばん下「トレースを画面で見る」",steps:["「トレースを画面で見る」を押すと、そのロットの記録が古い順に並びます。","石岡の記録は青、本社の記録は緑で出ます（石岡の入荷・出庫・廃棄、本社への移動・受け入れ・使用出庫・下処理・廃棄）。","紙が必要なときは、上の「トレース表を印刷」を押します。"],check:"いちばん上に、品目・ロットNo.・仕入先・産地・入荷日・石岡と本社の残りが出ます。",caution:"本社 下処理班・本社 荷受け担当者のアカウントでは利用できません。本社在庫のロットからでも、石岡での出庫（埼玉・深谷など）まで追えます。"};
 const rv={title:"下処理へ出庫する（本社 荷受け担当者・在庫反映オフの間だけ）",where:"QR読み取り → ロットの画面 →「使用出庫」",steps:["原料のQRを読みます。","出庫先で「下処理」または「原料出し」を選びます。","数量を入れて（全部使うときは「全部」）、「出庫する」を押します。"],check:"このロットの履歴に「出庫 → 下処理」が残り、本社の在庫が減ります。",caution:"下処理の機能を使い始める（在庫反映をオンにする）までのつなぎです。オンにすると、出庫先は原料出しだけになります。間違えた出庫の取り消しは、本社社員に頼んでください。"};
 const put=(r,x,first)=>{const g=V195_ROLE_GUIDES[r];if(!g||!Array.isArray(g.sections)||g.sections.some(s=>s.title===x.title))return;first?g.sections.splice(1,0,x):g.sections.push(x)};
 for(const r of C91_VIEW)put(r,sec,true);
 for(const r of Object.keys(V195_ROLE_GUIDES))if(!["hq_prep","hq_receiver"].includes(r))put(r,tr,false);
 put("hq_receiver",rv,false);
 for(const r of ["hq_prep","hq_receiver"]){
  const guide=V195_ROLE_GUIDES[r];if(!guide||!Array.isArray(guide.sections))continue;
  guide.sections=guide.sections.map(s=>s?.title==="本社の在庫と履歴を見る・Excelを作る"?{...s,title:"本社の在庫と履歴を見る",steps:s.steps.filter(x=>!x.includes("Excel"))}:s?.title==="在庫表を見る（QR品目＋原料＋仕掛品）"?{...s,caution:"量目が分からないQRのロットは「kg不明」として別に出ます。"}:s);
 }
 const g=V195_ROLE_GUIDES.hq_receiver;if(g&&g.intro&&!g.intro.includes("下処理"))g.intro=g.intro.replace("原料出しと","原料出し・下処理への出庫（在庫反映オフの間）と");
}catch(e){}
})();
