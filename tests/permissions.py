"""SEIKA+ 権限の回帰チェック（架空のデータのみ）。

使い方：リポジトリ直下で ``python3 tests/permissions.py``。
localhost:8765 に既存サーバーがなければ、このファイルが一時サーバーを起動します。
外部通信と Service Worker を止めるため、本番データベースには接続しません。
"""
import asyncio
import os
import socket
import sys
import threading
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

from playwright.async_api import async_playwright

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
MOCK = (HERE / "mock_hq.js").read_text(encoding="utf-8")
URL = os.environ.get("SEIKA_URL", "http://127.0.0.1:8765/index.html")
ROLES = [
    "admin", "worker", "buyer", "sales", "clerk", "viewer", "office_viewer",
    "hq_worker", "hq_clerk", "hq_receiver", "hq_prep",
]
BLOCKED = {"hq_receiver", "hq_prep"}
TRACE_GUIDE_TITLES = {
    "トレース表を印刷する（監査用）",
    "ロットのトレースを画面で見る",
    "在庫・出庫の分析を見る",
}
EXCEL_KINDS = ["stock", "counts", "table", "waste", "yield", "usage", "quality", "worktime"]

SETUP = r"""(role)=>{
 const T=window.__T;
 const now=new Date().toISOString();
 T.qr_lots=[{id:'Q1',qr_key:'Q1',lot_no:'I261105-01',item_name:'キャベツ',status:'在庫あり',active:true,current_qty:5,received_qty:5,unit:'ケース',pack_weight:'10kg',supplier:'テスト農園',origin:'茨城県',received_date:now,created_at:now,user_name:'架空 太郎'}];
 T.qr_lot_movements=[{id:'QM1',lot_id:'Q1',qr_key:'Q1',lot_no:'I261105-01',movement_type:'出庫',qty:1,unit:'ケース',destination:'本社',occurred_at:now,user_name:'架空 太郎'}];
 T.hq_lot_movements_v1400=[{id:'HM1',lot_id:'L1',lot_no:'H261025-01',movement_type:'出庫',qty:1,unit:'case',destination:'原料出し',occurred_at:now,user_name:'本社 一郎'}];
 const selectBase=qrSelect;
 window.__perm={rpc:[],select:[],downloads:[],pdfs:[],alerts:[]};
 qrSelect=async(t,q)=>{window.__perm.select.push(String(t));return selectBase(t,q)};
 const rpcBase=callRpc;
 callRpc=async(n,a)=>{
   window.__perm.rpc.push(String(n));
   if(n==='get_lot_trace_v1600')return {
     printed_by:'テスト担当',start_kind:a.p_kind,start_hq_id:'L1',
     qr_lot:T.qr_lots[0],qr_moves:T.qr_lot_movements,
     hq_lots:[T.hq_lots_v1400[0]],hq_moves:T.hq_lot_movements_v1400,
     works:[],waste:[]
   };
   return rpcBase(n,a);
 };
 window.v163SelectAll=async(t)=>{
   window.__perm.select.push(String(t));
   return JSON.parse(JSON.stringify(T[t]||[]));
 };
 if(window.XLSX){
   XLSX.writeFile=(wb,name)=>window.__perm.downloads.push(String(name));
 }
 window.downloadWorkbookXlsx=(wb,name)=>window.__perm.downloads.push(String(name));
 if(window.__h2){
   window.__h2.h2MakePdf=(pages,css,name)=>{window.__perm.pdfs.push({pages,css,name});return Promise.resolve();};
 }
 window.alert=(m)=>window.__perm.alerts.push(String(m));
 window.confirm=()=>true;
 db.role=role;db.user=role==='hq_prep'?'下処理（架空）':role==='hq_receiver'?'荷受（架空）':'テスト担当';
 try{localStorage.setItem('seika_hq_site','honsha')}catch(e){}
}"""


class QuietThreadingHTTPServer(ThreadingHTTPServer):
    allow_reuse_address = True


class QuietRequestHandler(SimpleHTTPRequestHandler):
    def log_message(self, _format, *_args):
        pass


class LocalServer:
    """8765 が空いている場合だけ、リポジトリを配信する一時サーバー。"""

    def __init__(self):
        self.server = None
        self.thread = None

    def start(self):
        parsed = urlparse(URL)
        if parsed.hostname not in {"127.0.0.1", "localhost"} or not parsed.port:
            return
        host, port = "127.0.0.1", parsed.port
        probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            probe.bind((host, port))
        except OSError:
            return
        finally:
            probe.close()

        handler = lambda *args, **kwargs: QuietRequestHandler(*args, directory=str(ROOT), **kwargs)
        self.server = QuietThreadingHTTPServer((host, port), handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        for _ in range(20):
            try:
                with socket.create_connection((host, port), timeout=0.1):
                    return
            except OSError:
                import time
                time.sleep(0.05)
        raise RuntimeError("一時HTTPサーバーを起動できませんでした")

    def stop(self):
        if self.server:
            self.server.shutdown()
            self.server.server_close()
        if self.thread:
            self.thread.join(timeout=3)


def fail(fails, role, check, detail):
    fails.append(f"[{role}] {check}: {detail}")


async def value(page, expression):
    return await page.evaluate(expression)


async def prepare_page(browser, role):
    context = await browser.new_context(viewport={"width": 820, "height": 1180}, service_workers="block")
    local_origin = urlparse(URL).netloc

    async def route(route):
        if urlparse(route.request.url).netloc == local_origin:
            await route.continue_()
        else:
            await route.abort()

    await context.route("**/*", route)
    page = await context.new_page()
    errors = []
    page.on("pageerror", lambda error: errors.append(str(error)))
    await page.goto(URL, wait_until="load")
    await page.wait_for_timeout(800)
    if not await page.evaluate("()=>typeof ymdKey==='function'"):
        raise RuntimeError("アプリの初期化に失敗しました: ymdKey がありません")
    await page.evaluate(MOCK, role)
    await page.evaluate(SETUP, role)
    return context, page, errors


async def assert_entries(page, role, fails):
    """トレース追加の2入口を、実際の最終公開関数から確認する。"""
    await page.evaluate("()=>hqLotPage('K1')")
    await page.wait_for_timeout(250)
    hq_entry = await value(page, "()=>!!document.getElementById('hqTraceBtn')")
    qr_detail = await value(page, "async()=>{try{await qrLotDetail('Q1');return {text:document.body.innerText,entry:!!document.getElementById('qrTraceBtn')}}catch(e){return {error:String(e),text:document.body.innerText,entry:false}}}")
    await page.wait_for_timeout(250)
    qr_entry = qr_detail["entry"]
    expected = role not in BLOCKED
    if hq_entry != expected:
        fail(fails, role, "本社ロットのトレース入口", f"期待={expected} 実際={hq_entry}")
    if qr_entry != expected:
        extra = qr_detail.get("error") or qr_detail.get("text", "")[:300]
        fail(fails, role, "石岡QRロットのトレース入口", f"期待={expected} 実際={qr_entry}; {extra}")


async def assert_blocked(page, role, fails):
    """2役割は、入口・公開関数・Excel・ガイドのすべてで止まること。"""
    before_rpc = await value(page, "()=>__perm.rpc.length")
    await page.evaluate("()=>window.hqTracePrint('hq','K1')")
    await page.evaluate("()=>window.hqTraceView('hq','K1')")
    await page.evaluate("()=>window.hqTraceViewBack()")
    await page.wait_for_timeout(150)
    trace_rpc = await value(page, "()=>__perm.rpc.slice(%d)" % before_rpc)
    if await value(page, "()=>__perm.pdfs.length"):
        fail(fails, role, "トレース印刷ガード", "印刷用HTMLを生成しました")
    if "get_lot_trace_v1600" in trace_rpc:
        fail(fails, role, "公開トレース関数", "拒否役割でも get_lot_trace_v1600 を呼びました")
    in_trace = await value(page, "()=>currentScreen==='hqTraceView'")
    if in_trace:
        fail(fails, role, "トレース画面ガード", "hqTraceView に遷移しました")

    await page.evaluate("()=>{__perm.select=[];__perm.downloads=[]}")
    await page.evaluate("()=>c81AnalysisPage()")
    await page.evaluate("()=>c81Excel()")
    analysis_reads = await value(page, "()=>__perm.select.filter(x=>x==='qr_lots'||x==='qr_lot_movements')")
    analysis_downloads = await value(page, "()=>__perm.downloads.slice()")
    if analysis_reads:
        fail(fails, role, "在庫・出庫の分析ガード", f"読込が実行されました: {analysis_reads}")
    if analysis_downloads:
        fail(fails, role, "分析Excelガード", f"ダウンロードが実行されました: {analysis_downloads}")
    if await value(page, "()=>currentScreen==='c81AnalysisPage'"):
        fail(fails, role, "分析画面ガード", "c81AnalysisPage に遷移しました")

    await page.evaluate("()=>{__perm.select=[];__perm.downloads=[]}")
    await page.evaluate("()=>window.hqExcel('2026-11')")
    await page.evaluate("()=>window.hqExcelPage('2026-11')")
    await page.evaluate("async()=>{for(const k of %s)await window.h2ExcelOut(k,'2026-11');await window.h2ExcelWaste('2026-11');await window.h2ExcelYield('2026-11');await window.h2ExcelQuality('2026-11')}" % repr(EXCEL_KINDS).replace("'", '"'))
    await page.evaluate("async()=>{await window.h2ExcelWorkTime('2026-11');await window.h2ExcelUsage('2026-11');for(const k of ['stock','counts','table','waste','yield','usage','quality','worktime'])await window.__h2.excelOut(k,'2026-11')}")
    await page.wait_for_timeout(150)
    excel_downloads = await value(page, "()=>__perm.downloads.slice()")
    if excel_downloads:
        fail(fails, role, "公開本社Excelガード", f"ダウンロードが実行されました: {excel_downloads}")
    if await value(page, "()=>currentScreen==='hqExcelPage'"):
        fail(fails, role, "Excel画面ガード", "hqExcelPage に遷移しました")

    await page.evaluate("()=>hqHistoryPage('2026-11')")
    await page.wait_for_timeout(150)
    history_excel = await value(page, "()=>document.body.innerText.includes('この月のExcelを作る')")
    if history_excel:
        fail(fails, role, "入出庫履歴の旧Excel入口", "ボタンが表示されています")

    guide = await value(page, "()=>{const g=V195_ROLE_GUIDES[db.role];return {titles:g.sections.map(s=>s.title),text:JSON.stringify(g.sections)}}")
    present = sorted(TRACE_GUIDE_TITLES.intersection(guide["titles"]))
    if present:
        fail(fails, role, "操作ガイドの制限3節", f"残っています: {present}")
    if "Excel" in guide["text"]:
        fail(fails, role, "操作ガイドのExcel説明", "利用できないExcelの説明が残っています")
    await page.evaluate("()=>v195RoleGuidePage()")
    if await value(page, "()=>document.body.innerText.includes('Excel')"):
        fail(fails, role, "操作ガイド画面のExcel説明", "画面に説明が残っています")


async def assert_allowed_trace(page, role, fails):
    """残る9役割は、画面表示とPDF相当HTMLの生成まで可能であること。"""
    await page.evaluate("()=>{__perm.rpc=[];__perm.pdfs=[]}")
    await page.evaluate("()=>window.hqTraceView('hq','K1')")
    await page.wait_for_timeout(150)
    view_ok = await value(page, "()=>currentScreen==='hqTraceView'&&document.body.innerText.includes('ロットのトレース')")
    if not view_ok:
        fail(fails, role, "トレース画面", "許可役割で画面表示できません")
    await page.evaluate("()=>window.hqTracePrint('hq','K1')")
    await page.wait_for_timeout(100)
    result = await value(page, "()=>({rpc:__perm.rpc.filter(x=>x==='get_lot_trace_v1600').length,pdfs:__perm.pdfs})")
    if result["rpc"] < 2:
        fail(fails, role, "トレースRPC", f"表示・印刷での呼出回数={result['rpc']}（2回未満）")
    if len(result["pdfs"]) != 1:
        fail(fails, role, "トレース印刷", f"PDF作成スタブの呼出回数={len(result['pdfs'])}")
    elif "ロットのトレース表" not in "".join(result["pdfs"][0]["pages"]):
        fail(fails, role, "トレース印刷HTML", "表題がPDF相当HTMLにありません")

    titles = await value(page, "()=>V195_ROLE_GUIDES[db.role].sections.map(s=>s.title)")
    missing = sorted({"トレース表を印刷する（監査用）", "ロットのトレースを画面で見る"} - set(titles))
    if missing:
        fail(fails, role, "操作ガイド維持", f"不足: {missing}")


async def assert_allowed_analysis(page, role, fails):
    await page.evaluate("()=>{__perm.select=[];__perm.downloads=[]}")
    await page.evaluate("()=>window.c81AnalysisPage()")
    if not await value(page, "()=>currentScreen==='c81AnalysisPage'&&document.body.innerText.includes('在庫・出庫の分析')"):
        fail(fails, role, "分析画面の維持", "許可役割で画面表示できません")
    await page.evaluate("()=>window.c81Excel()")
    if not await value(page, "()=>__perm.downloads.some(n=>n.startsWith('在庫・出庫の分析_'))"):
        fail(fails, role, "分析Excelの維持", "許可役割でExcelを生成できません")


async def assert_receiver_operations(page, fails):
    """荷受け担当者の通常業務が、制限追加で消えていないこと。"""
    await page.evaluate("()=>hqHome()")
    await page.wait_for_timeout(150)
    home_text = await value(page, "()=>document.body.innerText")
    for label in ["入荷待ち原料", "QR読み取り", "在庫管理", "品質評価一覧"]:
        if label not in home_text:
            fail(fails, "hq_receiver", "荷受け通常業務", f"ホームに「{label}」がありません")
    await page.evaluate("()=>hqStockHub()")
    await page.wait_for_timeout(100)
    stock_text = await value(page, "()=>document.body.innerText")
    for label in ["在庫入力", "入出庫履歴"]:
        if label not in stock_text:
            fail(fails, "hq_receiver", "荷受け通常業務", f"在庫管理に「{label}」がありません")


async def main():
    if urlparse(URL).hostname not in {"127.0.0.1", "localhost"}:
        raise ValueError("検証URLはローカルサーバーだけを指定してください")
    fails = []
    server = LocalServer()
    server.start()
    try:
        async with async_playwright() as p:
            browser = await p.chromium.launch()
            for role in ROLES:
                context, page, errors = await prepare_page(browser, role)
                try:
                    await assert_entries(page, role, fails)
                    if role in BLOCKED:
                        await assert_blocked(page, role, fails)
                    else:
                        await assert_allowed_trace(page, role, fails)
                        await assert_allowed_analysis(page, role, fails)
                    if role == "hq_receiver":
                        await assert_receiver_operations(page, fails)
                    if errors:
                        for error in errors:
                            fail(fails, role, "ブラウザエラー", error[:300])
                except Exception as error:
                    fail(fails, role, "テスト実行", repr(error))
                finally:
                    await context.close()
                print(role, "OK" if not any(x.startswith(f"[{role}]") for x in fails) else "NG")
            await browser.close()
    finally:
        server.stop()
    if fails:
        print("\n".join(fails))
        sys.exit(1)
    print("権限回帰: すべてOK")


if __name__ == "__main__":
    asyncio.run(main())
