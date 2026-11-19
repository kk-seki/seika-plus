/* 関数の「最後に効いている定義」を調べる道具（v1.199-c135）
   使い方：node tools/function_map.js            → DOCS/関数の最終定義一覧.md を作り直す
          node tools/function_map.js --dead     → 完全に置き換わって使われていない古い定義を一覧（JSON）
   index.html の読み込み順で js/ を読み、トップレベルの function 宣言と「名前 = function…」の上書きを並べる。
   上書きした関数が元の関数を受け取って呼ぶ（const base=名前 など、読み込み時に元を読む）ものは「上乗せ」、
   元を読まないものは「置き換え」とする。 */
const fs=require('fs'),path=require('path');
const req=m=>{for(const p of ['/opt/npm-tools/node_modules/','/opt/node-tools/node_modules/','']){try{return require(p+m)}catch(e){}}throw new Error(m+' が見つかりません（npm i acorn acorn-walk）')};
const acorn=req('acorn'),walk=req('acorn-walk');
const ROOT=path.resolve(__dirname,'..');
const order=[...fs.readFileSync(path.join(ROOT,'index.html'),'utf8').matchAll(/<script src="\.\/(js\/[^"]+)"/g)].map(m=>m[1]);
const files=order.map(f=>({f,src:fs.readFileSync(path.join(ROOT,f),'utf8')}));
const lineOf=(src,pos)=>src.slice(0,pos).split('\n').length;

/* 読み込み時に実行される場所か（関数の中ではない。ただしその場で呼ぶ即時関数の中は読み込み時） */
function loadTime(ancestors){
 for(let i=ancestors.length-2;i>=0;i--){const a=ancestors[i];
  if(/Function/.test(a.type)){const p=ancestors[i-1];if(p&&p.type==='CallExpression'&&p.callee===a)continue;return false}}
 return true}
function unconditional(ancestors){
 for(let i=ancestors.length-2;i>=0;i--){const a=ancestors[i];
  if(/Function/.test(a.type)){const p=ancestors[i-1];if(p&&p.type==='CallExpression'&&p.callee===a)continue;return false}
  if(['IfStatement','ConditionalExpression','LogicalExpression','SwitchStatement','ForStatement','ForOfStatement','ForInStatement','WhileStatement','CatchClause'].includes(a.type))return false}
 return true}
const defs={},reads={},refs={};
const bodyRefs=(node)=>{const set=new Set;walk.full(node,x=>{if(x.type==='Identifier')set.add(x.name)});return set};
let seq=0;const loadReads={};
for(const {f,src} of files){
 const ast=acorn.parse(src,{ecmaVersion:'latest',locations:false});
 for(const n of ast.body)if(n.type==='FunctionDeclaration'){(defs[n.id.name]=defs[n.id.name]||[]).push({kind:'decl',f,src,start:n.start,end:n.end,seq:seq++,stmt:n,uncond:true});const r=refs[n.id.name]=refs[n.id.name]||new Set;for(const x of bodyRefs(n.body))r.add(x)}
 walk.ancestor(ast,{
  AssignmentExpression(n,st,anc){let name=null;
   if(n.left.type==='Identifier')name=n.left.name;else if(n.left.type==='MemberExpression'&&!n.left.computed&&n.left.object.type==='Identifier'&&n.left.object.name==='window')name=n.left.property.name;
   if(!name||!/Function/.test(n.right.type)||!loadTime(anc))return;
   const parent=anc[anc.length-2],stmt=parent&&parent.type==='ExpressionStatement'&&parent.expression===n?parent:null;
   (defs[name]=defs[name]||[]).push({kind:'assign',f,src,start:n.start,end:n.end,seq:seq++,stmt,uncond:unconditional(anc),body:n.right});const r=refs[name]=refs[name]||new Set;for(const x of bodyRefs(n.right))r.add(x)},
  Identifier(n,st,anc){if(!loadTime(anc))return;const p=anc[anc.length-2];
   if(p&&p.type==='AssignmentExpression'&&p.left===n)return;
   if(p&&p.type==='MemberExpression'&&p.property===n&&!p.computed&&!(p.object.type==='Identifier'&&p.object.name==='window'))return;
   if(p&&(p.type==='Property'&&p.key===n&&!p.computed&&!p.shorthand))return;
   if(p&&p.type==='FunctionDeclaration'&&p.id===n)return;
   (reads[n.name]=reads[n.name]||[]).push({f,pos:n.start,seq:seq++});(loadReads[f]=loadReads[f]||[]).push({name:n.name,pos:n.start})},
  MemberExpression(n,st,anc){if(!loadTime(anc))return;if(n.object.type==='Identifier'&&n.object.name==='window'&&!n.computed){const p=anc[anc.length-2];if(p&&p.type==='AssignmentExpression'&&p.left===n)return;(reads[n.property.name]=reads[n.property.name]||[]).push({f,pos:n.start,seq:seq++})}}
 });
}
/* 順番は「ファイルの読み込み順 → ファイル内の位置」で比べる */
const fi=Object.fromEntries(order.map((f,i)=>[f,i]));
const key=d=>fi[d.f]*1e9+d.start, rkey=r=>fi[r.f]*1e9+r.pos;
const dead=[],rows=[];
/* 読み込み時に呼ばれる関数から、たどって呼ばれる名前（同じファイルの中で、置き換えより前） */
function reach(names){const seen=new Set,st=[...names];while(st.length){const n=st.pop();if(seen.has(n))continue;seen.add(n);for(const x of refs[n]||[])if(!seen.has(x))st.push(x)}return seen}
for(const [name,list] of Object.entries(defs)){
 if(list.length<2)continue;list.sort((a,b)=>key(a)-key(b));
 const rd=(reads[name]||[]).map(rkey).sort((a,b)=>a-b);
 // 後ろから見て、無条件の「置き換え」より前で、その間に読み込み時の読み取りがないものは使われない
 for(let j=list.length-1;j>0;j--){const P=list[j];if(P.kind!=='assign'||!P.uncond)continue;
  for(let i=j-1;i>=0;i--){const D=list[i];const from=fi[D.f]*1e9;  // 宣言はファイルの先頭から有効（巻き上げ）
   const lo=D.kind==='decl'?from:key(D);if(rd.some(x=>x>=lo&&x<key(P)))break;
   if(D.kind==='assign'&&!D.stmt)continue;
   if(D.f!==P.f)continue;  // 安全のため、同じファイルの中で置き換わるものだけ
   const before=(loadReads[P.f]||[]).filter(r=>r.pos<P.start).map(r=>r.name);if(reach(before).has(name))continue;
   dead.push({name,f:D.f,kind:D.kind,start:D.start,end:(D.kind==='assign'?D.stmt.end:D.end),line:lineOf(D.src,D.start),by:`${P.f}:${lineOf(P.src,P.start)}`})}
  break}
 rows.push({name,list});
}
if(process.argv.includes('--dead')){process.stdout.write(JSON.stringify(dead.sort((a,b)=>a.f.localeCompare(b.f)||b.start-a.start),null,1));process.exit(0)}
const deadSet=new Set(dead.map(d=>d.f+':'+d.start));
let md=`# 関数の最終定義一覧（自動生成）\n\n作り直し：\`node tools/function_map.js\`（index.html の読み込み順で js/ を読む）\n\n同じ名前の関数が何度も定義・上書きされているものだけを載せます。**いちばん下の行が、実際に動いている定義**です。\n「上乗せ」は元の関数を受け取って呼ぶもの、「置き換え」は元を呼ばないもの、「条件つき」は if などの中で上書きするものです。\n\n| 関数 | 回数 | 定義の場所（読み込み順） |\n|---|---|---|\n`;
for(const {name,list} of rows.sort((a,b)=>b.list.length-a.list.length||a.name.localeCompare(b.name))){
 const cells=list.map((d,i)=>{const tag=d.kind==='decl'?'宣言':(!d.uncond?'条件つき':(d.body&&JSON.stringify(d.body).includes('"name":"'+name+'"')||(reads[name]||[]).some(r=>rkey(r)<key(d)&&rkey(r)>=(i?key(list[i-1]):0))?'上乗せ':'置き換え'));return `${i===list.length-1?'**':''}${d.f.replace('js/','')}:${lineOf(d.src,d.start)}（${tag}）${i===list.length-1?'**':''}`});
 md+=`| \`${name}\` | ${list.length} | ${cells.join(' → ')} |\n`}
fs.writeFileSync(path.join(ROOT,'DOCS','関数の最終定義一覧.md'),md);
console.log(`関数 ${rows.length} 個を DOCS/関数の最終定義一覧.md に書きました。使われていない古い定義：${dead.length} 個（--dead で一覧）`);
