const CACHE_NAME="seika-static-v1.134";
const APP_SHELL=["./","./index.html","./manifest.webmanifest","./icons/seika-192.png","./icons/seika-512.png"];
const CACHEABLE_PATHS=new Set(APP_SHELL.map(path=>new URL(path,self.registration.scope).pathname));
self.addEventListener("install",event=>{
  event.waitUntil(caches.open(CACHE_NAME).then(cache=>cache.addAll(APP_SHELL)));
});
self.addEventListener("activate",event=>{
  event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(key=>key.startsWith("seika-static-")&&key!==CACHE_NAME).map(key=>caches.delete(key)))).then(()=>self.clients.claim()));
});
self.addEventListener("message",event=>{
  if(event.data&&event.data.type==="SKIP_WAITING")self.skipWaiting();
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
