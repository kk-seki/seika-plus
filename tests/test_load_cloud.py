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

    async def test_load_cloud_rejects_pending_data_for_another_user(self):
        await self.page.evaluate(
            """async()=>{
                db.settings={...(db.settings||{}),protected:'value'};
                v161QueueLatest();
                await v188IdbFlush();
                db.userId='u2';
            }"""
        )
        self.requests.clear()
        message = await self.page.evaluate(
            """async()=>{
                try{
                    await loadCloud();
                    return '';
                }catch(error){
                    return String(error.message||error);
                }
            }"""
        )
        state = await self.page.evaluate(
            """()=>({
                queue:v161ReadQueue().length,
                protected:db.settings?.protected
            })"""
        )
        self.assertIn("別の利用者", message)
        self.assertEqual(state, {"queue": 1, "protected": "value"})
        self.assertEqual(await self.load_cloud_requests(), [])


if __name__ == "__main__":
    unittest.main()
