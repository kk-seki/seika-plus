
/* ===== v1.199-c55 QR入庫の貼り紙：行の高さを固定して最後の行（仕入先）が枠からはみ出さないようにする ===== */
(function(){
const c55FitBase=qrFitPosterText;
qrFitPosterText=function(root){
 for(const poster of root.querySelectorAll(".pdfPoster")){
  const left=poster.querySelector(".posterLeft"),rows=poster.querySelector(".posterRows"),brand=poster.querySelector(".posterBrand");
  if(!left||!rows)continue;
  const ps=getComputedStyle(poster),bs=brand?getComputedStyle(brand):null;
  const inner=poster.clientHeight-parseFloat(ps.paddingTop||0)-parseFloat(ps.paddingBottom||0);
  const brandH=brand?brand.offsetHeight+parseFloat(bs.marginTop||0)+parseFloat(bs.marginBottom||0):0;
  const list=[...rows.querySelectorAll(":scope > .posterRow")],n=list.length;if(!n)continue;
  const gap=3,avail=Math.max(100,Math.floor(inner-brandH-2)),h=Math.floor((avail-gap*(n-1))/n);
  left.style.height=inner+"px";left.style.overflow="hidden";
  rows.style.display="flex";rows.style.flexDirection="column";rows.style.flex="none";rows.style.gap=gap+"px";rows.style.height=avail+"px";
  for(const r of list){r.style.height=h+"px";r.style.flex="none";r.style.minHeight="0"}
 }
 c55FitBase(root);
 for(const r of root.querySelectorAll(".posterRow")){
  const lab=r.querySelector(".posterLabel"),val=r.querySelector(".posterValue");
  if(lab){let size=parseFloat(getComputedStyle(lab).fontSize)||40;for(let i=0;i<40&&size>14&&lab.scrollHeight>r.clientHeight;i++){size-=2;lab.style.fontSize=size+"px"}}
  if(val){let size=parseFloat(getComputedStyle(val).fontSize)||40;for(let i=0;i<60&&size>14&&(val.offsetHeight>r.clientHeight||val.scrollHeight>val.clientHeight+size*0.35||r.scrollHeight>r.clientHeight+size*0.35);i++){size-=2;val.style.fontSize=size+"px"}}
 }
};
window.qrFitPosterText=qrFitPosterText;
})();
