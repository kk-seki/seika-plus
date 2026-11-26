/* ===== v1.199-c168 アカウント別の利用状況 =====
   見られるのは平田 祐希さんのアカウントだけ（SQL 071 の usage_viewers_v1199c168。管理者のほかの人も見られない）。
   メニュー（アカウントのメニュー）に「アカウント別の利用状況」ボタン。サーバーで見られる人か確かめてから出す。
   中身（SQL 071 の usage_by_account_v1199c168。読むだけ）：
   ・最後に使った日、期間中に使った日数
   ・よく開いた画面（開いた日数の多い順）。画面の記録は「動作の重さの記録」からなので最大30日
   ・操作の件数（入荷・出庫・廃棄・棚卸し・スキャン・下処理の日報・本社の操作・返品・そのほか）
   期間は 7日／30日／90日。石岡・本社で絞れる。 */
(()=>{
const ROLE={admin:"管理者",worker:"青果社員",buyer:"仕入れ担当",sales:"営業",clerk:"事務",viewer:"閲覧",office_viewer:"事務所の閲覧",
 hq_worker:"本社 作業",hq_receiver:"本社 受け入れ",hq_prep:"本社 下処理",hq_clerk:"本社 事務"};
const SCREEN={home:"ホーム",hqHome:"本社ホーム",hqPrepHome:"本社 下処理ホーム",accountMenu:"メニュー",settings:"設定",changePasswordPage:"パスワード変更",
 qrHome:"QR",qrCameraPage:"QR読み取り",qrCreatePage:"QR作成（入荷）",qrEditLotPage:"ロットの修正",qrLotDetail:"ロットの詳細",qrLotListPage:"ロット一覧",
 qrManagedItemsPage:"QR管理品目",qrManualSearchPage:"ロットを探す",qrOperationCompletePage:"操作の完了",qrOperationLotPage:"ロットの操作",
 qrScannedLotActionPage:"読み取ったロットの操作",qrTotalsPage:"QR在庫の合計",v1144QrOutboundHistoryPage:"出庫の履歴",v1102QualityPage:"品質評価",
 inventory:"在庫表",inventoryManagementPage:"在庫の管理",weeklyData:"週のデータ",purchasePrices:"仕入れ価格",wasteListPage:"廃棄の一覧",wasteManagementPage:"廃棄の管理",
 meshContainerPage:"網コン",lineCopyPage:"LINE用コピー",v194DestinationsPage:"出庫先",c81AnalysisPage:"分析",c83ViaPage:"経由",c84SlipPage:"伝票",
 c113CorrectPage:"出庫の訂正",c117ReportList:"日報の一覧",c117ReportPage:"日報",c130GapPage:"GAP",c130BackfillPage:"GAPの後付け",c130MergePage:"GAPのまとめ",
 c140ShipPlanPage:"出荷予定（積み込み表）",c140AliasPage:"品目の読み替え",c142ImportPage:"産地報告書の取り込み",c142PreviewPage:"産地報告書の確認",
 c153GapPage:"出荷予定と確定のちがい",c154SalesCustomersPage:"営業担当の客先",c165AskPage:"AIに聞く",c168UsagePage:"利用状況",
 v1200ProductionHome:"生産ホーム",v1200Trimming:"下処理（トリミング）",v1200DailyReport:"下処理の日報",v1208CandidatePage:"候補",
 hqDirectPage:"本社 直送",hqHistoryPage:"本社 履歴",hqIshiokaPendingPage:"本社 石岡からの未受入",hqLotPage:"本社 ロット",hqNormalPage:"本社 通常在庫",
 hqPendingPage:"本社 未受入",hqPrepCheckPage:"本社 下処理の確認",hqPrepNew:"本社 下処理の登録",hqPricePage:"本社 価格",hqQualityPage:"本社 品質",
 hqScanPage:"本社 読み取り",hqSheetPage:"本社 表",hqStockHub:"本社 在庫",hqStockPage:"本社 在庫表",hqStocktakePage:"本社 棚卸し",hqTablePage:"本社 一覧",
 hqTraceView:"本社 トレース",hqUsagePage:"本社 使用量",hqWastePage:"本社 廃棄",hqWorkPage:"本社 作業",hqWorkTimePage:"本社 作業時間",hqYieldPage:"本社 歩留まり"};
const OPS=["入荷","出庫","廃棄","棚卸し","スキャン","下処理の日報","本社の操作","返品","そのほか"];
const st={can:null,checking:null,data:{},days:7,area:"all"};
const isHq=r=>String(r||"").startsWith("hq_");
const roleLabel=r=>ROLE[r]||r||"";
const screenLabel=s=>SCREEN[s]||s;
const jstDay=v=>v?new Date(v).toLocaleDateString("sv-SE",{timeZone:"Asia/Tokyo"}):"";
function ago(v){
 if(!v)return "期間中は使っていません";
 const d=jstDay(v),t=new Date().toLocaleDateString("sv-SE",{timeZone:"Asia/Tokyo"});
 const n=Math.round((new Date(t+"T00:00:00Z")-new Date(d+"T00:00:00Z"))/864e5);
 const hm=new Date(v).toLocaleTimeString("ja-JP",{timeZone:"Asia/Tokyo",hour:"2-digit",minute:"2-digit"});
 const md=new Date(v).toLocaleDateString("ja-JP",{timeZone:"Asia/Tokyo",month:"numeric",day:"numeric"});
 return n<=0?`今日 ${hm}`:n===1?`昨日 ${hm}`:`${n}日前（${md}）`;
}

async function c168CanView(force=false){
 if(db?.role!=="admin")return false;
 if(st.can!==null&&!force)return st.can;
 if(st.checking)return st.checking;
 st.checking=(async()=>{try{st.can=(await callRpc("can_view_usage_v1199c168",{}))===true}catch(_){st.can=false}return st.can})();
 try{return await st.checking}finally{st.checking=null}
}

function cardHtml(r,days){
 const ops=OPS.filter(k=>r.ops?.[k]).map(k=>`<span class="c168Op">${esc(k)} <b>${Number(r.ops[k]).toLocaleString()}</b></span>`).join("");
 const scr=(r.top_screens||[]).map(s=>`<span class="c168Scr">${esc(screenLabel(s.screen))}<span class="small">（${s.days}日）</span></span>`).join("");
 const none=!r.last_seen;
 return `<div class="card c168Card${none?" c168None":""}">
  <div class="c168Head"><b>${esc(r.name||"")}</b><span class="small">${esc(roleLabel(r.role))}</span></div>
  <div class="c168Row"><span>最後に使った</span><b class="${none?"c168Warn":""}">${esc(ago(r.last_seen))}</b></div>
  ${none?"":`<div class="c168Row"><span>使った日数</span><b>${r.days}日 / ${days}日</b></div>
  <div class="small" style="margin-top:6px">よく開いた画面${days>30?"（30日分）":""}</div><div class="c168Wrap">${scr||'<span class="small">記録なし</span>'}</div>
  <div class="small" style="margin-top:6px">操作の件数（合計 ${Number(r.ops_total||0).toLocaleString()}）</div><div class="c168Wrap">${ops||'<span class="small">操作なし（見るだけ）</span>'}</div>`}
 </div>`;
}

async function c168UsagePage(days,area){
 if(days)st.days=days;if(area)st.area=area;
 setScreen("c168UsagePage",[st.days,st.area]);
 pageShell("アカウント別の利用状況","読み込んでいます",'<div class="card"><div class="notice">読み込んでいます。</div></div>');
 if(!(await c168CanView())){
  if(currentScreen!=="c168UsagePage")return;
  return pageShell("アカウント別の利用状況","",`<div class="err">この画面は見られません。</div><button class="btn btn2" style="width:100%" ${seikaEventAttrs("click","home",[])}>ホームへ</button>`);
 }
 let d;
 try{d=await callRpc("usage_by_account_v1199c168",{p_days:st.days});st.data[st.days]=d}
 catch(e){if(currentScreen!=="c168UsagePage")return;
  const m=String(e?.message||e);
  return pageShell("アカウント別の利用状況","",`<div class="err">${esc(/usage_by_account|PGRST202/.test(m)?"利用状況の機能（SQL 071）がまだ実行されていません。":m)}</div><button class="btn btn2" style="width:100%" ${seikaEventAttrs("click","home",[])}>ホームへ</button>`)}
 if(currentScreen!=="c168UsagePage")return;
 const all=Array.isArray(d?.rows)?d.rows:[];
 const rows=all.filter(r=>st.area==="all"||(st.area==="hq"?isHq(r.role):!isHq(r.role)));
 const used=rows.filter(r=>r.last_seen),unused=rows.filter(r=>!r.last_seen);
 const btn=(label,on,fn,args)=>`<button class="btn ${on?"blue":"btn2"}" ${seikaEventAttrs("click",fn,args)}>${label}</button>`;
 const nav=`<div class="row" style="gap:6px;flex-wrap:wrap">${[7,30,90].map(n=>btn(`${n}日`,st.days===n,"c168UsagePage",[n,st.area])).join("")}</div>
  <div class="row" style="gap:6px;flex-wrap:wrap;margin-top:6px">${[["all","全員"],["ishioka","石岡"],["hq","本社"]].map(([k,l])=>btn(l,st.area===k,"c168UsagePage",[st.days,k])).join("")}</div>`;
 const sum=`<div class="c168Sum"><div><b>${used.length}</b><span class="small">人が使った</span></div><div><b class="${unused.length?"c168Warn":""}">${unused.length}</b><span class="small">人が使っていない</span></div></div>
  ${unused.length?`<div class="small c168Warn" style="margin-top:4px">使っていない：${esc(unused.map(r=>r.name).join("、"))}</div>`:""}`;
 const note=`<div class="small" style="margin-top:6px">${esc(d.from)}〜${esc(d.to)}。画面の記録は最大30日分（それより前は残っていません）。操作の件数は、入荷・出庫・廃棄・棚卸し・スキャン・下処理の日報・本社の操作・返品の記録から数えています。</div>`;
 pageShell("アカウント別の利用状況",`この${st.days}日間・あなただけが見られます`,`<div class="card">${nav}${sum}${note}</div>${rows.map(r=>cardHtml(r,st.days)).join("")||'<div class="card"><div class="small">アカウントがありません。</div></div>'}
  <button class="btn btn2" style="width:100%;margin-top:8px" ${seikaEventAttrs("click","home",[])}>ホームへ</button>`);
}

/* メニューにボタン（見られる人だけ） */
try{
 const menuBase=accountMenu;
 accountMenu=function(...a){const r=menuBase.apply(this,a);
  c168CanView().then(ok=>{const m=document.querySelector(".menu");if(!ok||!m||document.getElementById("c168MenuUsage"))return;
   m.insertAdjacentHTML("beforeend",`<button id="c168MenuUsage" class="btn btn2" ${seikaEventAttrs("click","c168UsagePage",[])}>アカウント別の利用状況</button>`)}).catch(()=>{});
  return r};
 window.accountMenu=accountMenu;
}catch(e){}

Object.assign(window,{c168UsagePage,c168CanView,c168Lib:{ago,screenLabel,roleLabel,isHq,state:st}});
{const s=document.createElement("style");s.textContent=`.c168Card .c168Head{display:flex;align-items:baseline;gap:8px;font-size:17px}
.c168Row{display:flex;justify-content:space-between;margin-top:4px}.c168Wrap{display:flex;flex-wrap:wrap;gap:4px;margin-top:2px}
.c168Op,.c168Scr{background:#f1f5f9;border-radius:6px;padding:2px 6px;font-size:14px}.c168None{opacity:.8;border-left:4px solid #dc2626}
.c168Warn{color:#dc2626}.c168Sum{display:flex;gap:16px;margin-top:10px}.c168Sum b{font-size:22px;margin-right:4px}`;document.head.appendChild(s)}
})();
