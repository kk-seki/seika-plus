const CACHE_NAME="seika-static-v1.198";
const APP_VERSION="v1.198";
const APP_SHELL=["./","./index.html","./manifest.webmanifest","./icons/seika-192.png","./icons/seika-512.png","./vendor/exceljs-4.4.0.min.js","./vendor/html2canvas-1.4.1.min.js","./vendor/html5-qrcode-2.3.8.min.js","./vendor/jspdf-2.5.1.umd.min.js","./vendor/xlsx-js-style-1.2.0.bundle.js"];
const CACHEABLE_PATHS=new Set(APP_SHELL.map(path=>new URL(path,self.registration.scope).pathname));
self.addEventListener("install",event=>{
  event.waitUntil(caches.open(CACHE_NAME).then(cache=>cache.addAll(APP_SHELL)).then(()=>undefined));
});
self.addEventListener("activate",event=>{
  event.waitUntil((async()=>{
    const keys=await caches.keys();
    await Promise.all(keys.filter(key=>key.startsWith("seika-static-")&&key!==CACHE_NAME).map(key=>caches.delete(key)));
    await self.clients.claim();
    const windows=await self.clients.matchAll({type:"window",includeUncontrolled:true});
    windows.forEach(client=>client.postMessage({type:"SEIKA_VERSION_READY",version:APP_VERSION}));
  })());
});
self.addEventListener("message",event=>{
  if(event.data&&event.data.type==="SKIP_WAITING")self.skipWaiting();
  if(event.data&&event.data.type==="GET_VERSION"){
    const reply={type:"SEIKA_VERSION",version:APP_VERSION};
    if(event.ports&&event.ports[0])event.ports[0].postMessage(reply);
    else if(event.source)event.source.postMessage(reply);
  }
});
self.addEventListener("fetch",event=>{
  const request=event.request;
  if(request.method!=="GET")return;
  const url=new URL(request.url);
  if(url.origin!==self.location.origin)return;
  if(request.mode==="navigate"){
    event.respondWith(fetch(request,{cache:"no-store"}).then(response=>{
      if(response&&response.ok){const copy=response.clone();caches.open(CACHE_NAME).then(cache=>cache.put("./index.html",copy));}
      return response;
    }).catch(async()=>await caches.match("./index.html")||await caches.match("./")));
    return;
  }
  if(!CACHEABLE_PATHS.has(url.pathname))return;
  event.respondWith(fetch(request,{cache:"no-store"}).then(response=>{
    if(response&&response.ok){const copy=response.clone();caches.open(CACHE_NAME).then(cache=>cache.put(request,copy));}
    return response;
  }).catch(()=>caches.match(request)));
});
function qualityPushPayload(raw){
  let value={};try{value=JSON.parse(raw||"{}")}catch(e){}
  const id=typeof value.evaluationId==="string"&&/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value.evaluationId)?value.evaluationId:"";
  const title=typeof value.title==="string"?value.title.slice(0,80):"SEIKA＋ 品質評価";
  const body=typeof value.body==="string"?value.body.slice(0,180):"品質評価を確認してください";
  let url=typeof value.url==="string"?value.url:"./";
  try{const parsed=new URL(url,self.registration.scope);url=parsed.origin===self.location.origin?parsed.href:self.registration.scope}catch(e){url=self.registration.scope}
  return {id,title,body,url};
}
self.addEventListener("push",event=>{
  event.waitUntil((async()=>{
    const data=qualityPushPayload(event.data?event.data.text():"");
    await self.registration.showNotification(data.title,{body:data.body,icon:"./icons/seika-192.png",badge:"./icons/seika-192.png",tag:`quality-${data.id||"alert"}`,renotify:false,data:{url:data.url}});
  })());
});
self.addEventListener("notificationclick",event=>{
  event.notification.close();
  event.waitUntil((async()=>{
    let target=self.registration.scope;
    try{const parsed=new URL(event.notification.data?.url||"./",self.registration.scope);if(parsed.origin===self.location.origin)target=parsed.href}catch(e){}
    const clients=await self.clients.matchAll({type:"window",includeUncontrolled:true});
    for(const client of clients){
      if(client.url.startsWith(self.registration.scope)){if("navigate" in client)await client.navigate(target);await client.focus();return;}
    }
    await self.clients.openWindow(target);
  })());
});
