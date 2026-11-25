import asyncio
import sys
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import urlparse

from playwright.async_api import async_playwright

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sync as sync_test


class LoadCloudTests(unittest.IsolatedAsyncioTestCase):
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
        self.server = sync_test.Server()
        self.context = await self.browser.new_context(service_workers="block")

        async def local_requests(route):
            if urlparse(route.request.url).netloc == urlparse(self.url).netloc:
                await route.continue_()
            else:
                await route.abort()

        await self.context.route("**/*", local_requests)
        await self.context.route("**/*supabase.co/**", self.server.handle)
        self.page = await self.context.new_page()
        self.errors, self.requests = [], []
        self.page.on("pageerror", lambda error: self.errors.append(str(error)))
        self.page.on("dialog", lambda dialog: asyncio.ensure_future(dialog.accept()))
        self.page.on("request", lambda request: self.requests.append(request))
        await self.page.goto(self.url)
        await self.page.wait_for_timeout(1200)
        await sync_test.prepare(self.page)
        self.server.data = await self.page.evaluate("()=>v188RolePayload(v161Snapshot())")
        self.assertTrue(await self.page.evaluate("()=>loadCloud===window.loadCloud"))
        self.requests.clear()

    async def asyncTearDown(self):
        try:
            self.assertEqual(self.errors, [])
        finally:
            await self.context.close()
            await self.browser.close()
            await self.playwright.stop()

    async def load_cloud_requests(self):
        await asyncio.sleep(0)
        return [
            request.url
            for request in self.requests
            if "/rest/v1/rpc/get_app_state_v187" in request.url
        ]

    async def test_load_cloud_restores_empty_remote_candidates_prunes_expired_and_prefers_remote(self):
        now = datetime.now(timezone.utc)
        expired = (now - timedelta(days=125)).isoformat()
        current = (now - timedelta(days=45)).isoformat()
        self.server.data["qrSupplierHidden"] = []
        self.server.data["inventoryCounts"] = {
            "sessions": [
                {"id": "expired", "status": "confirmed", "confirmedAt": expired},
                {"id": "current", "status": "confirmed", "confirmedAt": current},
                {"id": "active", "status": "in_progress", "updatedAt": expired},
            ]
        }
        await self.page.evaluate(
            """()=>{
                db.qrSupplierHidden=['local-supplier'];
                return loadCloud();
            }"""
        )
        first = await self.page.evaluate(
            """()=>({
                suppliers:db.qrSupplierHidden,
                sessions:(db.inventoryCounts?.sessions||[]).map(session=>session.id)
            })"""
        )
        self.assertEqual(first["suppliers"], ["local-supplier"])
        self.assertEqual(first["sessions"], ["current", "active"])

        self.server.data["qrSupplierHidden"] = ["remote-supplier"]
        await self.page.evaluate(
            """()=>{
                db.qrSupplierHidden=['new-local-supplier'];
                return loadCloud();
            }"""
        )
        self.assertEqual(await self.page.evaluate("()=>db.qrSupplierHidden"), ["remote-supplier"])

    async def test_load_cloud_keeps_pending_queue_without_reading_remote(self):
        self.server.data["settings"] = {"remote": "value"}
        await self.page.evaluate(
            """()=>{
                db.settings={...(db.settings||{}),local:'value'};
                v161QueueLatest();
            }"""
        )
        self.requests.clear()
        await self.page.evaluate("()=>loadCloud()")
        state = await self.page.evaluate(
            """()=>({
                queue:v161ReadQueue().length,
                local:db.settings?.local,
                remote:db.settings?.remote
            })"""
        )
        self.assertEqual(state, {"queue": 1, "local": "value", "remote": None})
        self.assertEqual(await self.load_cloud_requests(), [])

    async def test_load_cloud_marks_conflicting_pending_queue_without_reading_remote(self):
        await self.page.evaluate(
            """async()=>{
                db.settings={...(db.settings||{}),local:'protected-value'};
                v188WriteBase(v161Snapshot(),37);
                v161QueueLatest();
                const pending=v161ReadQueue()[0];
                pending.attempts=1;
                pending.lastError='他端末更新との競合';
                v161WriteQueue([pending]);
                await v188IdbFlush();
                stateVersion=999;
            }"""
        )
        self.requests.clear()
        await self.page.evaluate("()=>loadCloud()")
        state = await self.page.evaluate(
            """()=>{
                const pending=v161ReadQueue()[0]||{};
                return {
                    queue:v161ReadQueue().length,
                    attempts:pending.attempts,
                    lastError:pending.lastError,
                    sync:syncState,
                    version:stateVersion,
                    local:db.settings?.local,
                    remote:db.settings?.remote
                };
            }"""
        )
        self.assertEqual(
            state,
            {
                "queue": 1,
                "attempts": 1,
                "lastError": "他端末更新との競合",
                "sync": "競合",
                "version": 37,
                "local": "protected-value",
                "remote": None,
            },
        )
        self.assertEqual(await self.load_cloud_requests(), [])

    async def test_load_cloud_keeps_local_data_and_base_when_remote_read_fails_then_recovers(self):
        self.server.data["settings"] = {"remote": "recovered-value"}
        before = await self.page.evaluate(
            """async()=>{
                db.settings={...(db.settings||{}),local:'protected-value'};
                v188WriteBase(v161Snapshot(),41);
                await v188IdbFlush();
                return v188ReadBase();
            }"""
        )

        async def fail_get_app_state(route):
            if "/rest/v1/rpc/get_app_state_v187" in route.request.url:
                await route.fulfill(status=500, body="read failure")
            else:
                await self.server.handle(route)

        await self.context.route("**/*supabase.co/**", fail_get_app_state)
        self.requests.clear()
        failure = await self.page.evaluate(
            """async()=>{
                try{
                    await loadCloud();
                    return '';
                }catch(error){
                    return String(error.message||error);
                }
            }"""
        )
        after_failure = await self.page.evaluate(
            """()=>({local:db.settings?.local,base:v188ReadBase()})"""
        )
        self.assertIn("read failure", failure)
        self.assertEqual(after_failure["local"], "protected-value")
        self.assertEqual(after_failure["base"], before)

        await self.context.unroute("**/*supabase.co/**", fail_get_app_state)
        await self.page.evaluate("()=>loadCloud()")
        recovered = await self.page.evaluate(
            """()=>({remote:db.settings?.remote,base:v188ReadBase()})"""
        )
        self.assertEqual(recovered["remote"], "recovered-value")
        self.assertEqual(recovered["base"]["version"], self.server.version)
        self.assertEqual(recovered["base"]["payload"]["settings"]["remote"], "recovered-value")

    async def park_for_user_b(self):
        # Aさん（u1）が未送信データを残した端末で、Bさん（u2）がログインする
        await self.page.evaluate(
            """async()=>{
                db.userId='u1';db.user='利用者A';
                db.settings={...(db.settings||{}),protected:'value'};
                v161QueueLatest();
                await v188IdbFlush();
                db.userId='u2';db.user='利用者B';
            }"""
        )
        self.requests.clear()
        return await self.page.evaluate(
            """async()=>{
                try{
                    await loadCloud();
                    return '';
                }catch(error){
                    return String(error.message||error);
                }
            }"""
        )

    async def test_load_cloud_parks_pending_data_for_another_user(self):
        # c163：Aさんの未送信データが残った共用の端末に、Bさんがログインできる。Aさんの分は消さずに分けて保管する
        message = await self.park_for_user_b()
        state = await self.page.evaluate(
            """async()=>{
                await v188IdbFlush();
                const parked=await c163ParkedRead('u1'),bundle=await v188IdbGet(V188_IDB_BUNDLE_ID);
                return{
                    queue:v161ReadQueue().length,
                    protected:db.settings?.protected??null,
                    user:db.userId,
                    parked:parked.items.length,
                    parkedProtected:parked.items[0]?.queue?.[0]?.localPayload?.settings?.protected??null,
                    parkedName:parked.items[0]?.ownerName,
                    bundleQueue:(bundle?.queue||[]).length,
                    summary:await c163ParkedSummary(),
                    notice:c163SwitchMessage(c163LastSwitch)
                }
            }"""
        )
        self.assertEqual(message, "")
        self.assertEqual(state["queue"], 0)
        self.assertIsNone(state["protected"])
        self.assertEqual(state["user"], "u2")
        self.assertEqual(state["parked"], 1)
        self.assertEqual(state["parkedProtected"], "value")
        self.assertEqual(state["parkedName"], "利用者A")
        self.assertEqual(state["bundleQueue"], 0)
        self.assertEqual(state["summary"], [{"owner": "u1", "name": "利用者A", "count": 1}])
        self.assertIn("利用者Aさん", state["notice"])
        self.assertFalse(self.server.accepted)

        # Bさんの保存にはAさんの未送信の内容が入らない
        await self.page.evaluate("()=>{db.adminNotices=[...(db.adminNotices||[]),{id:'from-b',title:'Bさんのお知らせ'}];save()}")
        await self.page.wait_for_function("()=>v161ReadQueue().length===0&&!v161SyncRunning", timeout=10000)
        self.assertIn("from-b", [n.get("id") for n in self.server.data.get("adminNotices", [])])
        self.assertNotEqual(self.server.data.get("settings", {}).get("protected"), "value")

    async def test_parked_pending_data_returns_when_the_owner_logs_in_again(self):
        # Aさんがこの端末でもう一度ログインすると、Aさんの未送信データが戻り、再送できる
        self.assertEqual(await self.park_for_user_b(), "")
        restored = await self.page.evaluate(
            """async()=>{
                db.userId='u1';db.user='利用者A';
                await loadCloud();
                await v188IdbFlush();
                const parked=await c163ParkedRead('u1');
                return{queue:v161ReadQueue().length,owner:v188PendingOwner(),protected:db.settings?.protected??null,parked:parked.items.length,
                    index:await c163ParkedIndex(),notice:c163SwitchMessage(c163LastSwitch)}
            }"""
        )
        self.assertEqual(restored["queue"], 1)
        self.assertEqual(restored["owner"], "u1")
        self.assertEqual(restored["protected"], "value")
        self.assertEqual(restored["parked"], 0)
        self.assertEqual(restored["index"], [])
        self.assertIn("未同期データを再送", restored["notice"])
        # 画面の「未同期データを再送」と同じ処理
        await self.page.evaluate("()=>retryPendingSync()")
        self.assertEqual(self.server.data.get("settings", {}).get("protected"), "value")
        self.assertEqual(await self.page.evaluate("()=>v161ReadQueue().length"), 0)

    async def test_pending_data_of_the_same_user_is_not_parked(self):
        await self.page.evaluate(
            """async()=>{
                db.userId='u1';db.user='利用者A';
                db.settings={...(db.settings||{}),protected:'value'};
                v161QueueLatest();
                await v188IdbFlush();
            }"""
        )
        await self.page.evaluate("()=>loadCloud()")
        state = await self.page.evaluate(
            "async()=>({queue:v161ReadQueue().length,parked:(await c163ParkedRead('u1')).items.length,protected:db.settings?.protected})"
        )
        self.assertEqual(state, {"queue": 1, "parked": 0, "protected": "value"})


if __name__ == "__main__":
    unittest.main()
