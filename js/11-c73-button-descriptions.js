
/* ===== v1.199-c73 石岡のボタンに説明を表示（本社と同じ形） ===== */
(()=>{
const C73_DESC=[
 ['ホーム','inventoryManagementPage','在庫管理','在庫入力・在庫表・在庫修正'],
 ['ホーム','qrHome','QR在庫管理','QR入庫・出庫・ロット一覧'],
 ['ホーム','lineCopyPage','在庫報告コピー','LINE用の在庫報告文を作成'],
 ['ホーム','itemsPage','品目設定','品目の追加・並び順・冷蔵庫'],
 ['ホーム','settings','適正在庫設定','品目ごとの適正在庫量'],
 ['ホーム','marketMemoPage','産地状況・市場動向メモ','産地・市場の情報を記録'],
 ['ホーム','meshContainerPage','網コンテナ在庫','網コンテナの数を記録'],
 ['ホーム','wasteManagementPage','廃棄管理','廃棄入力・廃棄一覧・週次レポート'],
 ['ホーム','v1200ProductionHome','製造・歩留まり','日報登録・歩留まり・入替品'],
 ['ホーム','purchasePricesPage','仕入れ価格表','週ごとの仕入れ価格を入力'],
 ['ホーム','inventoryCountHome','棚卸しモード','月末棚卸し・記入票・Excel'],
 ['ホーム（仕入れ担当）','orderCandidatePage','発注候補を見る','足りない担当品目'],
 ['ホーム（仕入れ担当）','excessCandidatePage','過多品目を見る','多すぎる担当品目'],
 ['QR在庫管理','qrCreatePage','QR入庫','ロットの登録・貼り紙の印刷'],
 ['QR在庫管理','qrLotListPage','QRロット一覧・検索','ロットを探す・まとめて出庫'],
 ['QR在庫管理','c83ViaPage','本社直接入荷（石岡経由）','石岡在庫に入れず本社へ・貼り紙'],
 ['QR在庫管理','c84SlipPage','伝票発行（埼玉・深谷・本社工場）','QR出庫から納品書・請求書を印刷'],
 ['QR在庫管理','qrManagedItemsPage','QR対象品目設定','QRで管理する品目・いつもの保管場所'],
 ['QR在庫管理','v194DestinationsPage','納品先マスタ','出庫先・客先の登録'],
 ['在庫管理','inventory','在庫入力','今日の在庫を入力'],
 ['在庫管理','weeklyData','在庫表','冷蔵庫ごとの在庫の一覧'],
 ['在庫管理','stocks','在庫修正','入力済みの在庫を直す'],
 ['廃棄管理','wasteEntryPage','廃棄入力','廃棄した品目・量を入力'],
 ['廃棄管理','wasteListPage','廃棄一覧','月ごとの廃棄と金額'],
 ['廃棄管理','v193WeeklyReportPage','週次廃棄レポート','週ごとの廃棄をまとめて出力']
];
const SCREENS=new Set(['home','qrHome','inventoryManagementPage','wasteManagementPage']);
function c73Apply(){
 if(!SCREENS.has(typeof currentScreen==='string'?currentScreen:''))return;
 for(const btn of document.querySelectorAll('#app button.btn:not([data-c73])')){
  if(btn.closest('.head')||btn.classList.contains('summaryBox')||btn.querySelector('br,span'))continue;
  const label=btn.textContent.trim(),action=btn.getAttribute('data-seika-click-action')||'';
  const hit=C73_DESC.find(([,a,l])=>l===label&&(!action||a===action));
  if(!hit)continue;
  btn.setAttribute('data-c73','1');
  btn.insertAdjacentHTML('beforeend','<br><span style="font-size:15px;font-weight:800">'+esc(hit[3])+'</span>');
 }
}
const app=document.getElementById('app');
if(app&&!window.c73Observer){window.c73Observer=new MutationObserver(c73Apply);window.c73Observer.observe(app,{childList:true,subtree:true})}
try{
 const groups=[...new Set(C73_DESC.map(x=>x[0]))];
 const sec={title:'ボタンの説明',where:'ホーム ／ QR在庫管理 ／ 在庫管理 ／ 廃棄管理',
  steps:['ボタン名の下に、そのボタンでできることを小さく書いています。押す前の目安にしてください。'].concat(groups.map(g=>'【'+g+'】'+C73_DESC.filter(x=>x[0]===g).map(x=>x[2]+'＝'+x[3]).join('、'))).concat(['【QR在庫管理（前から説明あり）】QR在庫処理＝出庫・廃棄・実数調整、品目別在庫量＝QR品目の在庫をkgで一覧、保管期限マスタ＝品目ごとの保管日数を確認・変更、規格別ロットの設定＝胡瓜など規格をまとめて1ロット、QR出庫履歴＝出庫先・日付ごとの全品目を確認、品質評価一覧＝評価済みロット・写真を確認、品質レポート＝仕入先・品目・月ごとの良品率','【製造・歩留まり（前から説明あり）】日報を登録＝使用原料・出来高を入力、製造日報＝使用原料・出来高・廃棄・歩留まり、歩留まり価格＝採用単価・歩留まり原価、入替品登録＝出来高（入替品）の候補']),
  check:'見えるボタンは、ログインした人の権限によって変わります。',
  caution:'ボタンの名前・色・並び順は前と同じです。'};
 if(typeof V198_GUIDE_SECTIONS!=='undefined')V198_GUIDE_SECTIONS.c73Buttons=sec;
 if(typeof V195_ROLE_GUIDES!=='undefined')for(const role of ['admin','worker','buyer','sales','clerk','viewer','office_viewer']){const g=V195_ROLE_GUIDES[role];if(g&&Array.isArray(g.sections)&&!g.sections.some(x=>x.title===sec.title))g.sections.unshift(sec)}
}catch(e){}
})();
