(()=>{
if(typeof Html5Qrcode!=='function'||Html5Qrcode.prototype.__c115CameraRetry)return;
const proto=Html5Qrcode.prototype,originalStart=proto.start,DENIED=/NotAllowedError|PermissionDeniedError|Permission denied|Permission dismissed/i;
const errorText=e=>String(e?.message||e||'');
const queryState=async()=>{try{return(await navigator.permissions.query({name:'camera'})).state}catch(_){return''}};
function panelFor(host){
  const id=`c115CameraHelp_${host.id}`;document.getElementById(id)?.remove();
  const panel=document.createElement('div');panel.id=id;panel.className='card c115CameraHelp';panel.setAttribute('role','alert');
  panel.innerHTML=`<div style="font-weight:900;font-size:1.05em">カメラが許可されていません</div>
    <div class="small" style="margin-top:6px">一度「許可しない」にすると、このタブレット・スマホがカメラを止めたままになり、アプリからは許可し直せません。次のどれかで許可してください。</div>
    <div class="small" style="margin-top:8px"><b>■ ホーム画面のアイコンから開いている場合</b><br>アイコンを長押し →「アプリ情報」→「権限」→「カメラ」→「アプリの使用中のみ許可」</div>
    <div class="small" style="margin-top:8px"><b>■ Chromeなどのブラウザで開いている場合</b><br>アドレス欄の左の鍵マーク（または右上「︙」→「設定」）→「権限」→「カメラ」→「許可」</div>
    <div class="small" style="margin-top:8px"><b>■ iPhone・iPad</b><br>「設定」アプリ → Safari → カメラ →「確認」または「許可」</div>
    <div class="small" style="margin-top:8px">許可できたら、下のボタンを押してください。画面を開き直す必要はありません。許可を待つ間も、下の一覧から選べます。</div>
    <button type="button" class="btn green c115CameraRetry" style="width:100%;margin-top:10px">許可したので、カメラを起動する</button>
    <div class="c115CameraNote small" role="status" style="margin-top:8px;font-weight:800"></div>`;
  host.insertAdjacentElement('afterend',panel);return panel;
}
function waitForPermission(reader,args,firstError){
  const host=document.getElementById(reader.elementId);
  if(!host)throw firstError;
  const panel=panelFor(host),button=panel.querySelector('.c115CameraRetry'),note=panel.querySelector('.c115CameraNote');
  return new Promise((resolve,reject)=>{
    let finished=false,trying=false,timer=null,status=null;
    const stop=()=>{finished=true;clearInterval(timer);document.removeEventListener('visibilitychange',onVisible);if(status)status.onchange=null;panel.remove()};
    const gone=()=>!host.isConnected||!panel.isConnected;
    const attempt=async manual=>{
      if(finished||trying)return;
      if(gone()){stop();return reject(firstError)}
      trying=true;button.disabled=true;
      try{await originalStart.apply(reader,args);stop();resolve(null)}
      catch(e){
        trying=false;button.disabled=false;
        if(!DENIED.test(errorText(e))){stop();return reject(e)}
        if(manual)note.textContent='まだ許可されていません。上の手順で「カメラ」を許可してから、もう一度押してください。'
      }
    };
    const onVisible=async()=>{if(document.visibilityState==='visible'&&await queryState()==='granted')attempt(false)};
    button.addEventListener('click',()=>attempt(true));
    document.addEventListener('visibilitychange',onVisible);
    navigator.permissions?.query({name:'camera'}).then(s=>{if(finished)return;status=s;s.onchange=()=>{if(s.state==='granted')attempt(false)}}).catch(()=>{});
    timer=setInterval(async()=>{if(finished)return;if(gone()){stop();return reject(firstError)}if(await queryState()==='granted')attempt(false)},1000);
  });
}
proto.start=function(...args){
  const reader=this;
  return originalStart.apply(reader,args).catch(e=>{if(!DENIED.test(errorText(e)))throw e;return waitForPermission(reader,args,e)});
};
proto.__c115CameraRetry=true;
const guide={title:'カメラを許可していないとき（QRが読み取れない）',where:'QR読み取りの画面に「カメラが許可されていません」と出たとき',
  steps:['画面の案内どおりに、端末の設定でこのアプリ（またはブラウザ）の「カメラ」を「許可」にします。','許可できたら、画面の「許可したので、カメラを起動する」を押します。画面を開き直したり、選んだ内容をやり直したりする必要はありません。','設定を許可して画面へ戻ると、自動でカメラが起動することもあります。','許可を待つ間は、各画面の一覧から選んで進められます。'],
  check:'カメラの映像が出て、QRを読み取れることを確認します。',
  caution:'一度「許可しない」を選ぶと、端末がカメラを止めたままにするため、アプリ側からは許可し直せません。端末の設定で許可してください。'};
if(typeof V195_ROLE_GUIDES==='object')for(const g of Object.values(V195_ROLE_GUIDES))if(g?.sections&&!g.sections.some(x=>x.title===guide.title))g.sections.push({...guide});
})();
