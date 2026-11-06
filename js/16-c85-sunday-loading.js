
/* ===== v1.199-c85 土曜日の「日曜積込分」：土曜日に埼玉・深谷へ出庫するときだけ出庫区分に追加 ===== */
(()=>{
const OPTS=[["日曜積込分","日曜積込分（日曜日に積む分）"],["日曜積込分・先送り","日曜積込分・先送り（日曜日に積む翌日発注分）"]];
const PAIRS=[["qrMoveDestination","qrShipTiming"],["v135Destination","v135ShipTiming"]];
function isSat(){return new Date(todayKey()+"T00:00:00").getDay()===6}
function sync(){
 for(const [d,t] of PAIRS){const dest=document.getElementById(d),sel=document.getElementById(t);if(!sel)continue;
  const on=isSat()&&["埼玉","深谷"].includes(dest?.value||"");
  for(const [v,l] of OPTS){let o=[...sel.options].find(x=>x.value===v);
   if(on&&!o){o=document.createElement("option");o.value=v;o.textContent=l;sel.appendChild(o)}
   if(!on&&o){if(sel.value===v)sel.value="";o.remove()}}}
}
document.addEventListener("change",e=>{if(PAIRS.some(([d])=>e.target?.id===d))sync()},true);
let q=0;new MutationObserver(()=>{if(q)return;q=1;requestAnimationFrame(()=>{q=0;if(PAIRS.some(([,t])=>document.getElementById(t)))sync()})}).observe(document.documentElement,{childList:true,subtree:true});
window.c85SyncSunday=sync;
})();
