import asyncio
import json
import sys
import unittest
from pathlib import Path
from urllib.parse import urlparse

from playwright.async_api import async_playwright

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sync as sync_test


class PriceServer(sync_test.Server):
    def __init__(self):
        super().__init__()
        self.price_requests = []
        self.price_results = []
        self.events = []
        self.price_hold = False
        self.price_held = asyncio.Event()
        self.price_release = asyncio.Event()
        self.price_release.set()

    async def handle(self, route):
        request = route.request
        path = urlparse(request.url).path
        if "/rest/v1/rpc/recalculate_qr_waste_price_v1162" in path:
            body = json.loads(request.post_data or "{}")
            self.price_requests.append(body)
            self.events.append(("price", body.get("p_movement_id")))
            if self.price_hold:
                self.price_held.set()
                await self.price_release.wait()
            result = self.price_results.pop(0) if self.price_results else {"ok": True}
            if result.get("status"):
                return await route.fulfill(status=result["status"], body=result.get("body", "price rpc failed"))
            return await self.json(route, result)
        if "/rest/v1/rpc/update_app_state_partial_v188" in path:
            self.events.append(("standard", None))
        return await super().handle(route)


class RetryBrowserTests(unittest.IsolatedAsyncioTestCase):
    @classmethod
    def setUpClass(cls):
        cls.previous_url = sync_test.URL
        cls.httpd = sync_test.start_local_server()
        cls.url = f"http://127.0.0.1:{cls.httpd.server_port}/index.html"
        if urlparse(cls.url).hostname not in {"127.0.0.1", "localhost"}:
            raise ValueError("検証URLはローカルサーバーだけを指定してください")
        sync_test.URL = cls.url

    @classmethod
    def tearDownClass(cls):
        sync_test.URL = cls.previous_url
        cls.httpd.shutdown()
        cls.httpd.server_close()

    async def asyncSetUp(self):
        self.playwright = await async_playwright().start()
        self.browser = await self.playwright.chromium.launch()
        self.server = PriceServer()
        self.context = await self.browser.new_context(service_workers="block")

        async def local_requests(route):
            if urlparse(route.request.url).netloc == urlparse(self.url).netloc:
                await route.continue_()
            else:
                await route.abort()

        await self.context.route("**/*", local_requests)
        await self.context.route("**/*supabase.co/**", self.server.handle)
        self.page = await self.context.new_page()
        self.errors = []
        self.page.on("pageerror", lambda error: self.errors.append(str(error)))
        self.page.on("dialog", lambda dialog: asyncio.ensure_future(dialog.accept()))
        await self.page.goto(self.url)
        await self.page.wait_for_timeout(1200)
        await sync_test.prepare(self.page)
        self.server.data = await self.page.evaluate("()=>v188RolePayload(v161Snapshot())")

    async def asyncTearDown(self):
        self.server.price_release.set()
        try:
            self.assertEqual(self.errors, [])
        finally:
            await self.context.close()
            await self.browser.close()
            await self.playwright.stop()

    async def set_price_queue(self, rows):
        await self.page.evaluate(
            """rows=>{
                v1163WriteWastePriceQueue(rows);
                if(JSON.parse(localStorage.getItem(V1163_WASTE_PRICE_QUEUE_KEY)||'[]').length!==rows.length){
                    throw new Error('廃棄単価キューを書き込めませんでした');
                }
            }""",
            rows,
        )

    async def price_queue(self):
        return await self.page.evaluate("()=>v1163ReadWastePriceQueue()")

    async def hold_price_requests(self):
        await self.page.evaluate("()=>{window.__retryAlert=window.alert;window.alert=()=>{}}")
        self.server.price_hold = True
        self.server.price_held.clear()
        self.server.price_release.clear()

    async def release_price_requests(self):
        self.server.price_release.set()
        self.server.price_hold = False

    async def wait_for_price_hold(self, timeout=8000):
        await asyncio.wait_for(self.server.price_held.wait(), timeout / 1000)

    async def retry_button(self):
        await self.page.evaluate("()=>home()")
        button = self.page.locator("#syncRetryBtn")
        await button.wait_for(state="visible")
        self.assertTrue(await self.page.evaluate("()=>document.getElementById('syncRetryBtn').onclick===window.retryPendingSync"))
        return button

    async def wait_for_prices(self, count, timeout=8000):
        await self.page.wait_for_function(
            "count=>window.__retryPriceCount>=count",
            arg=count,
            timeout=timeout,
        )

    async def click_retry_and_track_prices(self):
        await self.page.evaluate(
            """()=>{
                window.__retryPriceCount=0;
                const actual=window.callRpc;
                window.callRpc=async function(...args){
                    if(args[0]==='recalculate_qr_waste_price_v1162')window.__retryPriceCount++;
                    return await actual.apply(this,args);
                };
            }"""
        )
        button = await self.retry_button()
        await button.click()

    async def test_price_only_button_uses_final_entry_and_retries_actual_rpc(self):
        await self.set_price_queue([{"movementId": "price-1", "price": 120, "reason": "仮テスト"}])
        await self.click_retry_and_track_prices()
        await self.wait_for_prices(1)
        await self.page.wait_for_function("()=>v1163ReadWastePriceQueue().length===0")
        self.assertEqual(self.server.price_requests, [{"p_movement_id": "price-1", "p_manual_unit_price": 120, "p_reason": "仮テスト"}])
        self.assertEqual(await self.price_queue(), [])

    async def test_one_of_two_price_retries_fails_and_only_that_row_survives_reload(self):
        self.server.price_results = [{"ok": True}, {"status": 500, "body": "単価サーバー失敗"}]
        await self.set_price_queue(
            [
                {"movementId": "price-ok", "price": 100, "reason": "仮テスト"},
                {"movementId": "price-fail", "price": 200, "reason": "仮テスト", "attempts": 2},
            ]
        )
        await self.click_retry_and_track_prices()
        await self.wait_for_prices(2)
        await self.page.wait_for_function("()=>v1163ReadWastePriceQueue().length===1")
        before_reload = await self.price_queue()
        self.assertEqual([row["movementId"] for row in before_reload], ["price-fail"])
        self.assertEqual(before_reload[0]["attempts"], 3)
        self.assertTrue(before_reload[0]["lastError"])

        await self.page.reload()
        await self.page.wait_for_timeout(1200)
        await sync_test.prepare(self.page)
        self.assertEqual(await self.price_queue(), before_reload)

    async def test_successful_price_retry_keeps_a_different_request_added_while_the_rpc_waits(self):
        await self.set_price_queue([{"movementId": "price-sent", "price": 100, "reason": "開始時"}])
        await self.hold_price_requests()
        await self.page.evaluate("""()=>{
            window.__retryDone=false;
            window.__retryTask=window.retryPendingSync().finally(()=>{window.__retryDone=true});
        }""")
        await self.wait_for_price_hold()
        await self.page.evaluate("""()=>v1163QueueWastePrice({movementId:'price-added',price:200,reason:'再送中追加'},new Error('追加の通信失敗'))""")
        await self.release_price_requests()
        await self.page.wait_for_function("()=>window.__retryDone")
        remaining = await self.price_queue()
        self.assertEqual(len(remaining), 1)
        self.assertEqual(remaining[-1], {"movementId": "price-added", "price": 200, "reason": "再送中追加", "attempts": 0, "lastError": "追加の通信失敗"})
        self.assertEqual([request["p_movement_id"] for request in self.server.price_requests], ["price-sent"])

    async def test_failed_price_retry_keeps_a_different_request_added_while_the_rpc_waits(self):
        self.server.price_results = [{"status": 500, "body": "単価サーバー失敗"}]
        await self.set_price_queue([{"movementId": "price-sent", "price": 100, "reason": "開始時", "attempts": 2}])
        await self.hold_price_requests()
        await self.page.evaluate("""()=>{
            window.__retryDone=false;
            window.__retryTask=window.retryPendingSync().finally(()=>{window.__retryDone=true});
        }""")
        await self.wait_for_price_hold()
        await self.page.evaluate("""()=>v1163QueueWastePrice({movementId:'price-added',price:200,reason:'再送中追加'},new Error('追加の通信失敗'))""")
        await self.release_price_requests()
        await self.page.wait_for_function("()=>window.__retryDone")
        remaining = await self.price_queue()
        self.assertEqual(len(remaining), 2)
        self.assertEqual(remaining[0]["movementId"], "price-sent")
        self.assertEqual(remaining[0]["attempts"], 3)
        self.assertTrue(remaining[0]["lastError"])
        self.assertEqual(remaining[-1], {"movementId": "price-added", "price": 200, "reason": "再送中追加", "attempts": 0, "lastError": "追加の通信失敗"})
        self.assertEqual([request["p_movement_id"] for request in self.server.price_requests], ["price-sent"])

    async def test_retry_keeps_the_latest_version_of_the_same_movement_added_while_the_rpc_waits(self):
        original = {"movementId": "price-same", "price": 100, "reason": "開始時", "createdAt": "2026-11-07T09:00:00.000Z"}
        latest = {"movementId": "price-same", "price": 250, "reason": "再送中に修正", "createdAt": "2026-11-07T09:01:00.000Z"}
        await self.set_price_queue([original])
        await self.hold_price_requests()
        await self.page.evaluate("""()=>{
            window.__retryDone=false;
            window.__retryTask=window.retryPendingSync().finally(()=>{window.__retryDone=true});
        }""")
        await self.wait_for_price_hold()
        await self.set_price_queue([latest])
        await self.release_price_requests()
        await self.page.wait_for_function("()=>window.__retryDone")
        self.assertEqual(await self.price_queue(), [latest])
        self.assertEqual(self.server.price_requests[0]["p_manual_unit_price"], original["price"])

    async def test_failed_retry_does_not_restore_a_request_deleted_while_the_rpc_waits(self):
        self.server.price_results = [{"status": 500, "body": "単価サーバー失敗"}]
        await self.set_price_queue([{"movementId": "price-deleted", "price": 100, "reason": "開始時"}])
        await self.hold_price_requests()
        await self.page.evaluate("""()=>{
            window.__retryDone=false;
            window.__retryTask=window.retryPendingSync().finally(()=>{window.__retryDone=true});
        }""")
        await self.wait_for_price_hold()
        await self.set_price_queue([])
        await self.release_price_requests()
        await self.page.wait_for_function("()=>window.__retryDone")
        self.assertEqual(await self.price_queue(), [])

    async def test_two_public_retries_send_once_disable_the_button_and_allow_the_next_retry_after_release(self):
        self.server.price_results = [{"status": 500, "body": "単価サーバー失敗"}, {"ok": True}]
        await self.set_price_queue([{"movementId": "price-once", "price": 100, "reason": "二重開始防止"}])
        await self.retry_button()
        await self.hold_price_requests()
        await self.page.evaluate("""()=>{
            window.__retryFirst=window.retryPendingSync();
            window.__retrySecond=window.retryPendingSync();
        }""")
        await self.wait_for_price_hold()
        self.assertTrue(await self.page.evaluate("()=>document.getElementById('syncRetryBtn').disabled"))
        self.assertEqual(len(self.server.price_requests), 1)
        await self.release_price_requests()
        await self.page.evaluate("()=>Promise.all([window.__retryFirst,window.__retrySecond])")
        self.assertFalse(await self.page.evaluate("()=>document.getElementById('syncRetryBtn').disabled"))
        self.assertEqual([row["movementId"] for row in await self.price_queue()], ["price-once"])
        await self.page.evaluate("()=>window.retryPendingSync()")
        await self.page.wait_for_function("()=>v1163ReadWastePriceQueue().length===0")
        self.assertEqual(len(self.server.price_requests), 2)

    async def test_direct_price_retry_and_public_retry_share_the_same_running_guard(self):
        await self.set_price_queue([{"movementId": "price-direct", "price": 100, "reason": "直接呼出し"}])
        await self.hold_price_requests()
        await self.page.evaluate("""()=>{
            window.__directRetry=v1163RetryWastePrices();
            window.__publicRetry=window.retryPendingSync();
        }""")
        await self.wait_for_price_hold()
        self.assertEqual(len(self.server.price_requests), 1)
        await self.release_price_requests()
        await self.page.evaluate("()=>Promise.all([window.__directRetry,window.__publicRetry])")
        self.assertEqual(await self.price_queue(), [])

    async def test_queue_write_error_keeps_the_original_queue_and_allows_a_later_retry(self):
        row = {"movementId": "price-write-error", "price": 100, "reason": "端末保存例外"}
        await self.set_price_queue([row])
        await self.page.evaluate("()=>{window.__retryAlert=window.alert;window.alert=()=>{}}")
        await self.page.evaluate("""()=>{
            window.__priceQueueSetItem=Storage.prototype.setItem;
            Storage.prototype.setItem=function(key,value){
                if(key===V1163_WASTE_PRICE_QUEUE_KEY)throw new Error('テスト用の端末保存失敗');
                return window.__priceQueueSetItem.call(this,key,value);
            };
        }""")
        try:
            await self.page.evaluate("()=>window.retryPendingSync()")
            self.assertEqual(await self.price_queue(), [row])
        finally:
            await self.page.evaluate("()=>{Storage.prototype.setItem=window.__priceQueueSetItem;delete window.__priceQueueSetItem}")
        await self.page.evaluate("()=>window.retryPendingSync()")
        await self.page.wait_for_function("()=>v1163ReadWastePriceQueue().length===0")
        self.assertEqual(len(self.server.price_requests), 2)

    async def test_admin_clerk_and_sales_guides_explain_that_price_changes_during_retry_are_kept(self):
        for role in ("admin", "clerk", "sales"):
            with self.subTest(role=role):
                guide = await self.page.evaluate(
                    """role=>{
                        db.role=role;
                        db.user=`${role}テスト`;
                        v195RoleGuidePage();
                        for(const section of document.querySelectorAll('details'))section.open=true;
                        return {screen:currentScreen,text:document.getElementById('app').innerText};
                    }""",
                    role,
                )
                self.assertEqual(guide["screen"], "v195RoleGuidePage")
                self.assertIn("再送中に追加・変更した単価は端末に保持されます", guide["text"])

    async def test_failed_standard_retry_preserves_all_queues_and_skips_price_rpc(self):
        self.server.mode = "fail"
        await self.set_price_queue([{"movementId": "price-keep", "price": 120, "reason": "仮テスト"}])
        await self.page.evaluate(
            """async()=>{
                db.settings={...(db.settings||{}),retryBrowserStandard:'keep'};
                v188QueueLatest();
                await v188IdbFlush();
                window.__retryPriceCount=0;
                const actual=window.callRpc;
                window.callRpc=async function(...args){
                    if(args[0]==='recalculate_qr_waste_price_v1162')window.__retryPriceCount++;
                    return await actual.apply(this,args);
                };
                await window.retryPendingSync();
            }"""
        )
        self.assertEqual(await self.page.evaluate("()=>v161ReadQueue().length"), 1)
        self.assertEqual(await self.page.evaluate("()=>window.__retryPriceCount"), 0)
        self.assertEqual([row["movementId"] for row in await self.price_queue()], ["price-keep"])

    async def test_standard_retry_completes_before_price_retry(self):
        await self.set_price_queue([{"movementId": "price-after-standard", "price": 120, "reason": "仮テスト"}])
        await self.page.evaluate(
            """async()=>{
                db.settings={...(db.settings||{}),retryBrowserStandard:'send'};
                v188QueueLatest();
                await v188IdbFlush();
                await window.retryPendingSync();
            }"""
        )
        await self.page.wait_for_function("()=>v161ReadQueue().length===0&&v1163ReadWastePriceQueue().length===0")
        self.assertEqual(self.server.events, [("standard", None), ("price", "price-after-standard")])
        self.assertEqual(self.server.data["settings"]["retryBrowserStandard"], "send")
        self.assertEqual(self.server.version, 2)
        self.assertEqual(len(self.server.accepted), 1)


if __name__ == "__main__":
    unittest.main()
