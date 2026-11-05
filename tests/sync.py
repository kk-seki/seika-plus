"""SEIKA+ 保存・同期の自動チェック（現在の動作を記録するための回帰テスト）
使い方：python3 tests/sync.py   （自分でローカルサーバーを起動します）
別のローカルサーバーを使うとき：SEIKA_URL=http://localhost:8765/index.html python3 tests/sync.py
本番のデータベースには接続しません。supabase.co への通信は、すべてテスト用の擬似サーバーが受けます。"""
import asyncio
import functools
import json
import os
import sys
import threading
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

from playwright.async_api import async_playwright

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
URL = os.environ.get("SEIKA_URL", "")

STATE = "()=>({q:v161ReadQueue().length,sync:syncState,ver:stateVersion,hist:v188HistoryPending()})"
IDB = """async()=>{await v188IdbFlush();const b=await v188IdbGet(V188_IDB_BUNDLE_ID)||{};
return{q:(b.queue||[]).length,logs:((b.queue||[])[0]?.localPayload?.operationLogs||[]).map(x=>x.action)}}"""
ADD_LOG = "(k)=>{db.settings=db.settings||{};db.settings['syncTest_'+k]=k;addOperationLog(k,'前','後');save()}"
SAVED = "()=>v161ReadQueue().length===0&&!v161SyncRunning"


class Server:
    """Supabase の代わりに答える擬似サーバー（版番号の競合判定つき）。"""

    def __init__(self):
        self.version = 1
        self.data = {}
        self.accepted = []
        self.rpc_calls = []
        self.notice_calls = []
        self.token_calls = 0
        self.history_posts = 0
        self.mode = "ok"
        self.history_mode = "ok"
        self.release = asyncio.Event()
        self.held = asyncio.Event()
        self.jwt_expired_once = False

    def actions(self):
        settings = self.data.get("settings") or {}
        return [v for k, v in settings.items() if k.startswith("syncTest_")]

    def log_actions(self):
        return [x.get("action") for x in self.data.get("operationLogs", [])]

    async def handle(self, route):
        req = route.request
        path = urlparse(req.url).path
        if self.mode == "offline":
            return await route.abort("internetdisconnected")
        if "/auth/v1/token" in path:
            self.token_calls += 1
            return await self.json(route, {"access_token": "t2", "refresh_token": "r2", "expires_in": 3600})
        if "/rest/v1/rpc/" in path:
            name = path.rsplit("/", 1)[1]
            body = json.loads(req.post_data or "{}")
            if name == "get_app_state_v187":
                return await self.json(route, {"ok": True, "data": self.data, "version": self.version})
            if name == "update_app_state_partial_v188":
                self.rpc_calls.append(body.get("p_expected_version"))
                if self.jwt_expired_once:
                    self.jwt_expired_once = False
                    return await route.fulfill(status=401, body="JWT expired")
                if self.mode == "hold":
                    self.held.set()
                    await self.release.wait()
                if self.mode == "fail":
                    return await route.fulfill(status=500, body="サーバーエラー")
                if self.mode == "conflict" or body.get("p_expected_version") != self.version:
                    return await self.json(route, {"conflict": True, "message": "他端末更新との競合"})
                self.data.update(body.get("p_changes") or {})
                self.version += 1
                self.accepted.append(body)
                return await self.json(route, {"ok": True, "version": self.version})
            if name == "save_history_records_v188":
                self.history_posts += 1
                if self.history_mode == "fail":
                    return await route.fulfill(status=500, body="履歴テーブルのエラー")
                return await self.json(route, {"ok": True})
            if name == "save_admin_notices_v1147":
                self.notice_calls.append(body.get("p_expected_version"))
                if self.mode == "fail":
                    return await route.fulfill(status=500, body="サーバーエラー")
                if self.mode == "conflict" or body.get("p_expected_version") != self.version:
                    return await self.json(route, {"conflict": True, "message": "他端末更新との競合"})
                self.data["adminNotices"] = body.get("p_admin_notices")
                self.data["operationLogs"] = body.get("p_operation_logs")
                self.version += 1
                return await self.json(route, {"ok": True, "version": self.version})
            return await self.json(route, {})
        if "/rest/v1/" in path:
            if req.method == "POST":
                self.history_posts += 1
                if self.history_mode == "fail":
                    return await route.fulfill(status=500, body="履歴テーブルのエラー")
                return await route.fulfill(status=201, body="")
            return await self.json(route, [])
        return await self.json(route, {})

    @staticmethod
    async def json(route, value):
        await route.fulfill(status=200, content_type="application/json", body=json.dumps(value, ensure_ascii=False))


async def boot(browser, srv, role="admin", uid="u1"):
    ctx = await browser.new_context(viewport={"width": 820, "height": 1180}, service_workers="block")
    await ctx.route("**/*supabase.co/**", srv.handle)
    page = await ctx.new_page()
    errors = []
    page.on("pageerror", lambda e: errors.append(str(e)))
    page.on("dialog", lambda d: asyncio.ensure_future(d.accept()))
    await page.goto(URL)
    await page.wait_for_timeout(1200)
    await prepare(page, role, uid)
    srv.data = await page.evaluate("()=>v188RolePayload(v161Snapshot())")
    return ctx, page, errors


async def prepare(page, role="admin", uid="u1"):
    await page.evaluate(
        """([role,uid])=>{authWriteSession({access_token:'t',refresh_token:'r',expires_at:Math.floor(Date.now()/1000)+3600});
db.role=role;db.userId=uid;db.user='テスト';cloudReady=true;stateVersion=1;historyTablesReady=false}""",
        [role, uid],
    )
    await page.evaluate("async()=>{await v188StorageInit();v188WriteBase(v161Snapshot(),stateVersion);await v188IdbFlush()}")


async def wait_state(page, sync, timeout=8000):
    await page.wait_for_function("(s)=>syncState===s", arg=sync, timeout=timeout)


def check(fails, name, cond, detail=""):
    if not cond:
        fails.append(f"{name} {detail}".strip())


async def s_success(browser):
    fails, srv = [], Server()
    ctx, page, errors = await boot(browser, srv)
    await page.evaluate(ADD_LOG, "入力A")
    await page.wait_for_function(SAVED, timeout=8000)
    st, idb = await page.evaluate(STATE), await page.evaluate(IDB)
    check(fails, "保存成功: 版番号が進む", st["ver"] == 2 and srv.version == 2, str(st))
    check(fails, "保存成功: 送信内容に入力が入る", "入力A" in srv.actions(), str(srv.actions()))
    check(fails, "保存成功: 未同期キューが空", st["q"] == 0 and idb["q"] == 0, f"{st} {idb}")
    check(fails, "保存成功: 期待版番号は1", srv.rpc_calls == [1], str(srv.rpc_calls))
    check(fails, "ブラウザのエラー", not errors, str(errors[:2]))
    await ctx.close()
    return fails


async def s_network_failure_and_retry(browser):
    fails, srv = [], Server()
    srv.mode = "fail"
    ctx, page, _ = await boot(browser, srv)
    await page.evaluate(ADD_LOG, "入力B")
    await wait_state(page, "失敗")
    st, idb = await page.evaluate(STATE), await page.evaluate(IDB)
    check(fails, "通信失敗: キューに残る", st["q"] == 1 and idb["q"] == 1, f"{st} {idb}")
    check(fails, "通信失敗: 端末側に入力が残る", "入力B" in idb["logs"], str(idb))
    check(fails, "通信失敗: サーバーは更新されない", srv.version == 1 and not srv.accepted)
    srv.mode = "ok"
    await page.evaluate("()=>retryPendingSync()")
    await page.wait_for_function(SAVED, timeout=8000)
    st, idb = await page.evaluate(STATE), await page.evaluate(IDB)
    check(fails, "再送: キューが空になる", st["q"] == 0 and idb["q"] == 0, f"{st} {idb}")
    check(fails, "再送: 同じ入力が送られる", srv.actions().count("入力B") == 1, str(srv.actions()))
    check(fails, "再送: 版番号が進む", srv.version == 2 and st["ver"] == 2, str(st))
    await ctx.close()
    return fails


async def s_offline_then_online(browser):
    fails, srv = [], Server()
    srv.mode = "offline"
    ctx, page, _ = await boot(browser, srv)
    await page.evaluate(ADD_LOG, "入力C")
    await wait_state(page, "失敗")
    check(fails, "オフライン: キューに残る", (await page.evaluate(STATE))["q"] == 1)
    srv.mode = "ok"
    await page.evaluate("()=>window.dispatchEvent(new Event('online'))")
    await page.wait_for_function(SAVED, timeout=8000)
    st = await page.evaluate(STATE)
    check(fails, "オンライン復帰: 自動で再送される", st["q"] == 0 and "入力C" in srv.actions(), f"{st} {srv.actions()}")
    await ctx.close()
    return fails


async def s_conflict_not_overwritten(browser):
    fails, srv = [], Server()
    srv.mode = "conflict"
    ctx, page, _ = await boot(browser, srv)
    before = json.dumps(srv.data, sort_keys=True)
    await page.evaluate(ADD_LOG, "入力D")
    await wait_state(page, "競合")
    st, idb = await page.evaluate(STATE), await page.evaluate(IDB)
    check(fails, "競合: 自動で上書きしない", json.dumps(srv.data, sort_keys=True) == before and not srv.accepted)
    check(fails, "競合: 端末側の入力を保持", st["q"] == 1 and "入力D" in idb["logs"], f"{st} {idb}")
    await ctx.close()
    return fails


async def s_conflict_merge(browser):
    fails, srv = [], Server()
    ctx, page, _ = await boot(browser, srv)
    srv.version = 5
    srv.data["adminNotices"] = [{"id": "remote-n1", "title": "他端末のお知らせ"}]
    await page.evaluate(ADD_LOG, "入力E")
    await wait_state(page, "競合")
    check(fails, "競合統合: 版が違うと拒否される", not srv.accepted and srv.rpc_calls == [1], str(srv.rpc_calls))
    await page.evaluate("()=>retryPendingSync()")
    await page.wait_for_function(SAVED, timeout=8000)
    st = await page.evaluate(STATE)
    check(fails, "競合統合: 別項目の変更どうしは統合して保存", len(srv.accepted) == 1, str(srv.rpc_calls))
    check(fails, "競合統合: 他端末の変更が消えない", srv.data.get("adminNotices") == [{"id": "remote-n1", "title": "他端末のお知らせ"}], str(srv.data.get("adminNotices")))
    check(fails, "競合統合: この端末の入力も入る", "入力E" in srv.actions() and "入力E" in srv.log_actions(), f"{srv.actions()} {srv.log_actions()}")
    check(fails, "競合統合: キューが空・版番号が進む", st["q"] == 0 and st["ver"] == 6, str(st))
    await ctx.close()
    return fails


async def s_conflict_same_item_stays(browser):
    fails, srv = [], Server()
    ctx, page, _ = await boot(browser, srv)
    srv.version = 5
    srv.data["settings"] = {**(srv.data.get("settings") or {}), "syncTestKey": "他端末の値"}
    await page.evaluate("()=>{db.settings=db.settings||{};db.settings.syncTestKey='この端末の値';save()}")
    await wait_state(page, "競合")
    await page.evaluate("()=>retryPendingSync()")
    await page.wait_for_function("()=>!v1111RetryPendingRunning", timeout=8000)
    st = await page.evaluate(STATE)
    check(fails, "同じ項目の競合: 自動で保存しない", not srv.accepted, str(srv.rpc_calls))
    check(fails, "同じ項目の競合: 他端末の値が残る", srv.data["settings"]["syncTestKey"] == "他端末の値")
    check(fails, "同じ項目の競合: 端末の入力を保持", st["q"] == 1 and st["sync"] == "競合", str(st))
    await ctx.close()
    return fails


async def s_change_during_save(browser):
    fails, srv = [], Server()
    srv.mode = "hold"
    ctx, page, _ = await boot(browser, srv)
    await page.evaluate(ADD_LOG, "入力F1")
    await asyncio.wait_for(srv.held.wait(), 8)
    await page.evaluate(ADD_LOG, "入力F2")
    srv.mode = "ok"
    srv.release.set()
    await page.wait_for_function(
        "()=>v161ReadQueue().length===0&&!v161SyncRunning&&syncState==='保存済み'", timeout=10000
    )
    st = await page.evaluate(STATE)
    check(fails, "保存中の追加変更: 2回に分けて送られる", len(srv.accepted) == 2, str(srv.rpc_calls))
    check(fails, "保存中の追加変更: 後の入力も届く", "入力F1" in srv.actions() and "入力F2" in srv.actions(), str(srv.actions()))
    check(fails, "保存中の追加変更: 版番号が進む", srv.version == 3 and st["ver"] == 3, str(st))
    await ctx.close()
    return fails


async def s_restart_restores(browser):
    fails, srv = [], Server()
    srv.mode = "fail"
    ctx, page, _ = await boot(browser, srv)
    await page.evaluate(ADD_LOG, "入力G")
    await wait_state(page, "失敗")
    await page.evaluate("async()=>{await v188IdbFlush();localStorage.removeItem(AUTH_STORAGE_KEY)}")
    await page.reload()
    await page.wait_for_timeout(1200)
    await page.evaluate(
        "()=>{authWriteSession({access_token:'t',refresh_token:'r',expires_at:Math.floor(Date.now()/1000)+3600});db.role='admin';db.userId='u1';cloudReady=true;stateVersion=1}"
    )
    await page.evaluate("()=>v188StorageInit()")
    st = await page.evaluate(STATE)
    restored = await page.evaluate("()=>(db.operationLogs||[]).some(x=>x.action==='入力G')")
    check(fails, "再起動: 未同期キューが戻る", st["q"] == 1, str(st))
    check(fails, "再起動: 入力した内容が画面側にも戻る", restored)
    srv.mode = "ok"
    await page.evaluate("()=>saveCloudNow()")
    st = await page.evaluate(STATE)
    check(fails, "再起動: 戻したデータを再送できる", st["q"] == 0 and "入力G" in srv.actions(), f"{st} {srv.actions()}")
    await ctx.close()
    return fails


async def s_other_user_not_sent(browser):
    fails, srv = [], Server()
    srv.mode = "fail"
    ctx, page, _ = await boot(browser, srv, uid="u1")
    await page.evaluate(ADD_LOG, "入力H")
    await wait_state(page, "失敗")
    await page.evaluate("async()=>{await v188IdbFlush();localStorage.removeItem(AUTH_STORAGE_KEY)}")
    await page.reload()
    await page.wait_for_timeout(1200)
    await page.evaluate(
        "()=>{authWriteSession({access_token:'t',refresh_token:'r',expires_at:Math.floor(Date.now()/1000)+3600});db.role='admin';db.userId='u2';cloudReady=true;stateVersion=1}"
    )
    await page.evaluate("()=>v188StorageInit()")
    srv.mode = "ok"
    calls_before = len(srv.rpc_calls)
    message = await page.evaluate("async()=>{try{await saveCloudNow();return ''}catch(e){return String(e.message)}}")
    st = await page.evaluate(STATE)
    check(fails, "別の利用者: 再送を拒否する", "別の利用者" in message, message)
    check(fails, "別の利用者: サーバーへ送らない", len(srv.rpc_calls) == calls_before and not srv.accepted)
    check(fails, "別の利用者: データは保持", st["q"] == 1, str(st))
    await ctx.close()
    return fails


async def s_history_only_failure(browser):
    fails, srv = [], Server()
    srv.history_mode = "fail"
    ctx, page, _ = await boot(browser, srv)
    await page.evaluate(
        """()=>{historyTablesReady=true;db.records=db.records||[];
db.records.push({id:'sync-test-record',itemId:'i1',date:'2026-11-05',createdAt:nowIso(),value:1});db.settings=db.settings||{};db.settings.syncTest_I='入力I';addOperationLog('入力I','前','後');save()}"""
    )
    await page.wait_for_function("()=>v188HistoryPending()", timeout=10000)
    await page.wait_for_function(SAVED, timeout=5000)
    st = await page.evaluate(STATE)
    check(fails, "履歴だけ失敗: 本体データは保存される", "入力I" in srv.actions() and st["q"] == 0, f"{st} {srv.actions()}")
    check(fails, "履歴だけ失敗: 履歴の再送状態が残る", st["hist"] is True and st["sync"] == "未同期", str(st))
    check(fails, "履歴だけ失敗: 履歴の送信を試した", srv.history_posts >= 1, str(srv.history_posts))
    srv.history_mode = "ok"
    await page.evaluate("()=>retryPendingSync()")
    await page.wait_for_function("()=>!v188HistoryPending()", timeout=8000)
    check(fails, "履歴の再送: 再送状態が消える", (await page.evaluate(STATE))["hist"] is False)
    await ctx.close()
    return fails


async def s_login_expired_refresh(browser):
    fails, srv = [], Server()
    ctx, page, _ = await boot(browser, srv)
    srv.jwt_expired_once = True
    await page.evaluate(ADD_LOG, "入力J")
    await page.wait_for_function(SAVED, timeout=8000)
    st = await page.evaluate(STATE)
    check(fails, "ログイン期限切れ: 認証を更新する", srv.token_calls == 1, str(srv.token_calls))
    check(fails, "ログイン期限切れ: 更新後に再送されて保存", st["q"] == 0 and "入力J" in srv.actions(), f"{st} {srv.actions()}")
    await ctx.close()
    return fails


SCENARIOS = [
    ("保存成功", s_success),
    ("通信失敗→再送", s_network_failure_and_retry),
    ("オフライン→オンライン復帰", s_offline_then_online),
    ("競合は自動で上書きしない", s_conflict_not_overwritten),
    ("競合：別項目は統合", s_conflict_merge),
    ("競合：同じ項目は保留", s_conflict_same_item_stays),
    ("保存中に追加された変更", s_change_during_save),
    ("再起動後の復元", s_restart_restores),
    ("別の利用者の未同期データ", s_other_user_not_sent),
    ("履歴テーブルだけ失敗", s_history_only_failure),
    ("ログイン期限切れ", s_login_expired_refresh),
]


def start_local_server():
    handler = type("Quiet", (SimpleHTTPRequestHandler,), {"log_message": lambda *a: None})
    httpd = ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(handler, directory=ROOT))
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return httpd


async def main():
    global URL
    httpd = None
    if not URL:
        httpd = start_local_server()
        URL = f"http://127.0.0.1:{httpd.server_port}/index.html"
    if urlparse(URL).hostname not in {"127.0.0.1", "localhost"}:
        raise ValueError("検証URLはローカルサーバーだけを指定してください")
    fails = []
    try:
        async with async_playwright() as p:
            browser = await p.chromium.launch()
            for title, scenario in SCENARIOS:
                try:
                    result = await asyncio.wait_for(scenario(browser), 40)
                except Exception as error:
                    result = [f"実行できませんでした: {error!r}"[:300]]
                print(title, "OK" if not result else "NG")
                fails += [f"[{title}] {x}" for x in result]
            await browser.close()
    finally:
        if httpd:
            httpd.shutdown()
    if fails:
        print("\n".join(fails))
        sys.exit(1)
    print("保存・同期: すべてOK")


if __name__ == "__main__":
    asyncio.run(main())
