#!/usr/bin/env node
/* v1.199-c143 出荷予定・確定数量の自動取り込み用（アプリと同じ読み方で、登録する内容を JSON で出す）
   アプリの js/29-c140-ship-plan.js・js/30-c142-ship-actual.js を、画面なしでそのまま動かす。DBには書かない（書くのは呼び出す側）。

   使い方：
     node tools/ship_auto.js plan   --masters m.json --current cur.json [--today 2026-11-22] [--days 7] 積み込み表.xlsx …
     node tools/ship_auto.js actual --masters m.json --plan plan.json --calias calias.json [--actual act.json] 産地報告書.xlsx
   入力 JSON：
     m.json      {"aliases":[{raw_key,raw_name,item_name,in_master}], "std":[{item_name,case_kg}], "items":["キャベツ",…]}
     cur.json    {"imports":[{id,delivery_date,…}], "lines":[{import_id,customer_name,item_name,kg,…}]}   今有効な出荷予定
     plan.json   {"active":{…}|null, "lines":[…]}  その納品日の出荷予定 ／ calias.json [{raw_key,customer_name}] ／ act.json {"active":{…}|null}
   出力（標準出力）：
     plan   {"today","days":[{"date","state":"new|change|same|bad","open":要確認の数,"files":[…],"lines":[登録する行]}],"issues":[…],"errors":[…]}
     actual {"date","file","sheets","open":要確認の数,"issues":[…],"lines":[登録する行],"errors":[…],"already":今の確定があるか}
   要確認（知らない品名・客先、読めない数量）が1つでもある日は、呼び出す側で登録しないこと。 */
"use strict";
const fs=require("fs"),path=require("path"),vm=require("vm");
const ROOT=path.resolve(__dirname,"..");
function args(){const a=process.argv.slice(2),o={_:[]};for(let i=0;i<a.length;i++){if(a[i].startsWith("--"))o[a[i].slice(2)]=a[++i];else o._.push(a[i])}return o}
function jst(d){return new Date(d).toLocaleDateString("sv-SE",{timeZone:"Asia/Tokyo"})}
function load(o){
 const items=o.items||[],today=o.today||jst(new Date);
 const ctx={console,Date,Math,JSON,Map,Set,Promise,Uint8Array,ArrayBuffer,Intl,setTimeout,clearTimeout};
 ctx.window=ctx;ctx.self=ctx;ctx.globalThis=ctx;
 ctx.document={getElementById:()=>null,querySelector:()=>null,createElement:()=>({}),head:{appendChild(){}},activeElement:null};
 ctx.MutationObserver=class{observe(){}};
 ctx.db={role:"admin"};ctx.currentScreen="";
 Object.assign(ctx,{esc:s=>String(s??""),ymdKey:d=>jst(d),todayKey:()=>today,qrAllowedItemNames:()=>items,activeItems:()=>[],
  SPECIAL_STOCK_TABLES:{auto:{}},specialItems:()=>[],setScreen(){},pageShell(){},okHtml:()=>"",seikaEventAttrs:()=>"",canAdmin:()=>true,home(){},
  qrSelect:async()=>[],callRpc:async()=>({ok:true}),crypto:require("crypto").webcrypto});
 vm.createContext(ctx);
 for(const f of ["vendor/xlsx-js-style-1.2.0.bundle.js","js/29-c140-ship-plan.js","js/30-c142-ship-actual.js"])
  vm.runInContext(fs.readFileSync(path.join(ROOT,f),"utf8"),ctx,{filename:f});
 return ctx;
}
function masters(m){
 return{alias:new Map((m.aliases||[]).map(a=>[a.raw_key,a])),std:new Map((m.std||[]).map(s=>[s.item_name,Number(s.case_kg)])),aliasRows:m.aliases||[],stdRows:m.std||[]};
}
const readJson=f=>f?JSON.parse(fs.readFileSync(f,"utf8")):null;
function book(ctx,f){return{name:path.basename(f),wb:ctx.XLSX.read(fs.readFileSync(f),{type:"buffer",cellDates:false})}}
function issuesOf(lines){
 const out=[];for(const l of lines)for(const w of (l.open||[]))out.push({date:l.date,customer:l.customer||l.customerRaw||"",name:l.raw,qty:l.qtyRaw,what:w,where:`${l.file||""} ${l.sheet||""} ${l.cell||((l.col||"")+(l.row||""))}`.trim()});
 return out;
}
/* 積み込み表：明日から --days 日先（初期7日）までの納品日。範囲外のシートは読む前に外す */
function plan(o){
 // 選ぶ日のしぼり込みは c140Prepare に日付を渡せないため、読む前に範囲外のシートを外す
 const m=readJson(o.masters)||{},ctx=load({items:m.items,today:o.today});
 const t=new Date(ctx.todayKey()+"T00:00:00+09:00");t.setDate(t.getDate()+Number(o.days||7));const last=jst(t);
 const cur=readJson(o.current)||{imports:[],lines:[]};
 const books=o._.map(f=>book(ctx,f));
 for(const b of books){const keep=b.wb.SheetNames.filter(sn=>{const d=ctx.c140Lib.cellDate(b.wb.Sheets[sn],0,1);return !d||d<=last});b.wb={...b.wb,SheetNames:keep}}
 const curMap=new Map;
 for(const i of cur.imports||[])curMap.set(i.delivery_date,{active:i,lines:[]});
 const byId=new Map((cur.imports||[]).map(i=>[i.id,i.delivery_date]));
 for(const l of cur.lines||[]){const d=byId.get(l.import_id);if(d&&curMap.has(d))curMap.get(d).lines.push({...l,item:l.item_name,customer:l.customer_name,kg:l.kg===null?null:Number(l.kg)})}
 /* 月ごとの2ファイル（「11月.xlsx」「11月-埼玉・フジ　他.xlsx」）を組にして読む。月をまたぐ週は2組になる */
 const groups=new Map;for(const b of books){const g=(b.name.match(/^(\d+)月/)||[,b.name])[1];if(!groups.has(g))groups.set(g,[]);groups.get(g).push(b)}
 const tomorrow=(()=>{const x=new Date(ctx.todayKey()+"T00:00:00+09:00");x.setDate(x.getDate()+1);return jst(x)})();
 const out={today:ctx.todayKey(),last,days:[],issues:[],errors:[],missing:[]};
 for(const [,bs] of groups){
  const pend=ctx.c140Prepare(bs,null,masters(m),curMap);
  const days=ctx.c140Auto.dayStates(),eff=ctx.c140Auto.effective();
  out.days.push(...days.map(d=>({date:d.date,state:d.state,open:d.open,lines:(d.state==="new"||d.state==="change")&&!d.open?ctx.c140Auto.payload(d.lines):[],
   files:pend.sheets.filter(s=>s.date===d.date).map(s=>({file:s.file,sheet:s.sheet})),diff:d.diff?{add:d.diff.add.length,chg:d.diff.chg.length,del:d.diff.del.length}:null})));
  out.issues.push(...issuesOf(eff));out.errors.push(...pend.errors);
  out.missing.push(...pend.dates.filter(x=>x.missing.length&&x.date>=tomorrow&&x.date<=last).map(x=>({date:x.date,missing:x.missing})));
 }
 out.days.sort((a,b)=>a.date<b.date?-1:1);
 return out;
}
function actual(o){
 const m=readJson(o.masters)||{},pl=readJson(o.plan)||{active:null,lines:[]},ca=readJson(o.calias)||[],act=readJson(o.actual)||{active:null};
 const ctx=load({items:m.items,today:o.today});
 const b=book(ctx,o._[0]);
 const rep=ctx.c142Parse.readReport(b.wb,b.name);
 const p=ctx.c142Prepare(rep,masters(m),pl,ca,act);
 const lines=ctx.c142Auto.eff();
 const payload=lines.map(l=>({customer_raw:l.customerRaw,customer_name:l.customer,customer_norm:ctx.c140Lib.key(l.customer),item_name:l.item,item_in_master:l.inMaster!==false,item_raw:l.raw,
  origin:l.origin,coop:l.coop,qty_raw:l.qtyRaw,boxes:l.boxes,pack_kg:l.pack,kg:l.kg,note:l.note||"",source_sheet:l.sheet,source_cell:l.cell}));
 return{date:p.date,file:p.file,sheets:p.sheets,open:lines.filter(l=>l.open.length).length,issues:issuesOf(lines),lines:payload,errors:p.errors,already:!!act?.active};
}
if(require.main===module){
 const o=args(),cmd=o._.shift();
 try{
  let out;
  if(cmd==="plan")out=plan(o);
else if(cmd==="actual")out=actual(o);
  else throw new Error("使い方：node tools/ship_auto.js plan|actual …（ファイルの先頭の説明を見てください）");
  process.stdout.write(JSON.stringify(out));
 }catch(e){process.stderr.write(String(e&&e.stack||e)+"\n");process.exit(1)}
}
module.exports={load,masters};
