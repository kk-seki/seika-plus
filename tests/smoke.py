"""SEIKA+ 自動チェック（架空のデータで主な画面を開き、エラーが出ないかを確かめる）
使い方：リポジトリの直下で  python3 -m http.server 8765  を動かしてから  python3 tests/smoke.py
本番のデータベースには接続しません（supabase.co への通信はすべて止めます）。"""
import asyncio,sys,os
from playwright.async_api import async_playwright
HERE=os.path.dirname(os.path.abspath(__file__))
MOCK=open(os.path.join(HERE,'mock_hq.js'),encoding='utf-8').read()
URL=os.environ.get('SEIKA_URL','http://localhost:8765/index.html')
EXTRA="""()=>{(()=>{const T=window.__T;if(!T||!T.hq_works_v1500)return;const w5=T.hq_works_v1500.find(w=>w.id==='W5');if(w5)w5.confirm_status='確定';T.hq_tasks_v1500.forEach(t=>t.kind=t.kind||'作業');
 const d=w5?w5.work_date:new Date().toISOString().slice(0,10),t0=new Date(Date.now()-3*864e5);const at=m=>new Date(t0.getTime()+m*60000).toISOString();
 T.hq_works_v1500.push({id:'W9',kind:'下処理',status:'完了',confirm_status:'確定',work_date:d,raw_item_name:'人参',product_name:'人参千切り',place:'作業台B',yield_kg:60,waste_kg:3});
 T.hq_work_members_v1500.push({id:'P91',work_id:'W9',staff_id:'S2',staff_name:'鈴木 美咲',team:'1班',phase:'作業',start_at:at(0),end_at:at(120)},{id:'P92',work_id:'W9',staff_id:'S3',staff_name:'高橋 由美',team:'2班',phase:'作業',start_at:at(0),end_at:at(60)},{id:'P93',work_id:'W9',staff_id:'S3',staff_name:'高橋 由美',team:'2班',phase:'清掃',start_at:at(60),end_at:at(90)})})();(window.__T.hq_staff_v1500||[]).forEach((x,i)=>{x.print_group=x.print_group||(i%3)+1;x.qr_key=x.qr_key||x.qr_code});const base=callRpc;const ym=(n)=>{const d=new Date();d.setMonth(d.getMonth()-n,1);return d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')};
window.__rpc=[];callRpc=async(n,a)=>{window.__rpc.push([n,a]);
 if(n==='seika_db_size_v1690')return{ok:true,bytes:380*1048576,limit_bytes:500*1048576};
 if(n==='hq_monthly_list_v1690')return{ok:true,rows:[{target_month:ym(1),status:'pending',counts:{movements:3,waste:2,works:4,counts:1},deletable:false},{target_month:ym(5),status:'excel_saved',counts:{movements:9,waste:5,works:7,counts:2},deletable:true,excel_saved_at:new Date().toISOString(),excel_saved_by_name:'管理 一郎'}]};
 if(n==='list_monthly_archives_v1101')return{archives:[{target_month:ym(1)+'-01',status:'pending',row_count:12}]};
 if(n==='list_monthly_quality_archives_v1166')return{archives:[]};
 if(n==='hq_reissue_staff_qr_v1690')return{ok:true,id:a.p_id,name:'山田 花子',team:'1班',qr_key:'HQST-new'};
 return base(n,a)}}"""
PLAN={
 'prep':('hq_prep',[('p01',"hqHome()"),('p02',"(async()=>{await hqPrepNew('下処理');h2NwAddLot('L1');})()"),('p03',"(async()=>{h2NwSet('masterId','PM1');h2NwSet('place','作業台A');h2NwAddStaff('S1');h2NwAddStaff('S2');})()"),('p04',"hqWorkPage('W1')"),('p05',"hqWorkPage('W2')"),('p06',"(async()=>{__T.hq_works_v1500[1].inputs_saved_at=new Date().toISOString();__T.hq_works_v1500[1].yield_kg=96;__T.hq_works_v1500[1].waste_kg=3;__T.hq_work_materials_v1500[1].qty=5;await hqWorkPage('W2')})()"),('p07',"hqWorkPage('W3')"),('p08',"hqPrepNew('作業')"),('p09',"hqPrepNew('清掃')"),('p10',"hqOpScanPage()")]),
 'worker':('hq_worker',[('w01',"hqHome()"),('w02',"hqPrepCheckPage()"),('w03',"hqPrepConfirmPage('W5')"),('w04',"hqPrepMasterPage()"),('w05',"hqStaffPage()"),('w06',"hqStaffPrintPage()"),('w07',"hqTaskPlacePage()"),('w08',"hqWorkTimePage()"),('w08c',"hqWorkComparePage(ymdKey(new Date(Date.now()-40*864e5)),ymdKey(new Date()))"),('w09',"hqStockHub()"),('w10',"hqNormalPage()"),('w11',"hqStocktakePage()"),('w12',"hqWastePage()"),('w13',"hqYieldPage()"),('w14',"hqQualityPage()"),('w15',"hqExcelPage()"),('w16',"hqLotPage('K1')")]),
 'recv':('hq_receiver',[('r01',"hqHome()"),('r02',"hqPendingPage()"),('r03',"hqLotPage('K1')"),('r04',"hqStockHub()"),('r05',"hqNormalPage()"),('r06',"hqWastePage('','原料出しロス')"),('r07',"hqQualityPage()")]),
}

PLAN['admin']=('admin',[('a01',"home()"),('a02',"monthlyArchivePage()")])
CHECKS={
 'w07':("document.querySelectorAll('[data-seika-click-action=h2DeletePlace]').length>0&&document.querySelectorAll('[data-seika-click-action=h2DeleteTask]').length>0","作業名・作業場所に「削除」がない"),
 'w08c':("document.body.innerText.includes('人参千切り')&&document.body.innerText.includes('20kg')&&document.body.innerText.includes('個人の比較')","個人の比較が正しく出ない"),
 'w05':("document.querySelectorAll('.c69Reissue').length>0","スタッフ登録に「QRを作り直す」がない"),
 'a01':("!!document.querySelector('#c69AdminNotice')&&document.querySelector('#c69AdminNotice').innerText.includes('保管していない月')","管理者ホームに保管のお知らせが出ない"),
 'a02':("!!document.querySelector('#c69HqArchive .box')&&!!document.querySelector('#c69DbSize b')","月次Excel・履歴管理に本社のデータ・容量が出ない"),
}
async def main():
  fails=[]
  async with async_playwright() as p:
    b=await p.chromium.launch()
    for key,(role,steps) in PLAN.items():
      ctx=await b.new_context(viewport={'width':820,'height':1180})
      await ctx.route('**/*supabase.co/**',lambda r:r.abort())
      pg=await ctx.new_page();errs=[];pg.on('pageerror',lambda e:errs.append(str(e)))
      await pg.goto(URL);await pg.wait_for_timeout(1500)
      await pg.evaluate("()=>{try{localStorage.setItem('seika_hq_site','honsha')}catch(e){}}")
      await pg.evaluate(MOCK,role);await pg.evaluate(EXTRA)
      for name,js in steps:
        before=len(errs)
        try:
          await pg.evaluate(js);await pg.wait_for_timeout(900)
        except Exception as e:
          errs.append(f'{name}: {e}')
        ok=await pg.evaluate("()=>document.querySelector('#app')&&document.querySelector('#app').innerText.trim().length>20")
        if not ok:fails.append(f'[{key}] {name} 画面が空です')
        if name in CHECKS:
          cond,msg=CHECKS[name]
          if not await pg.evaluate(f"()=>{cond}"):fails.append(f'[{key}] {name} {msg}')
        for e in errs[before:]:fails.append(f'[{key}] {name} エラー: {e[:200]}')
      if key=='recv':
        await pg.evaluate("hqLotPage('K1')");await pg.wait_for_timeout(900)
        await pg.evaluate("hqRpc('hq_outbound_v1400',{p_operation_id:'x',p_lot_id:'L1',p_qty:1,p_destination:'原料出し'})");await pg.wait_for_timeout(1200)
        if not await pg.evaluate("()=>!!document.getElementById('c69RawAsk')"):fails.append('[recv] 原料出しのあとにロスの案内が出ない')
        else:
          await pg.click('#c69RawAsk >> text=ロスを入力する');await pg.wait_for_timeout(1200)
          v=await pg.evaluate("()=>document.getElementById('h2WsI')&&document.getElementById('h2WsI').value")
          if v!='キャベツ':fails.append(f'[recv] 原料出しロスの品目が入らない（{v}）')
      print(key,'OK' if not [f for f in fails if f.startswith(f'[{key}]')] else 'NG')
      await ctx.close()
    await b.close()
  if fails:
    print('\n'.join(fails));sys.exit(1)
  print('すべてOK')
asyncio.run(main())
