import asyncio
import sys
import unittest
from pathlib import Path
from urllib.parse import urlparse

from playwright.async_api import async_playwright

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sync as sync_test


class RefreshDataTests(unittest.IsolatedAsyncioTestCase):
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
        self.assertTrue(await self.page.evaluate("()=>refreshData===window.refreshData"))
        await self.trace_refresh_dependencies()
        self.requests.clear()

    async def asyncTearDown(self):
        try:
            self.assertEqual(self.errors, [])
        finally:
            await self.context.close()
            await self.browser.close()
            await self.playwright.stop()

    async def trace_refresh_dependencies(self):
        await self.page.evaluate(
            """()=>{
                window.__refreshTrace={loads:0,renders:0};
                const actualLoad=loadCloud,actualRender=renderCurrent;
                loadCloud=async function(...args){
                    window.__refreshTrace.loads++;
                    return await actualLoad.apply(this,args);
                };
                renderCurrent=async function(...args){
                    window.__refreshTrace.renders++;
                    return await actualRender.apply(this,args);
                };
            }"""
        )

    async def refresh(self):
        return await self.page.evaluate(
            """async()=>{
                const result=await window.refreshData();
                return {result:result===undefined?null:result,trace:window.__refreshTrace,
                    queue:v161ReadQueue().length,sync:syncState,settings:db.settings||{}};
            }"""
        )

    async def load_cloud_request_count(self):
        await asyncio.sleep(0)
        return len(
            [
                request
                for request in self.requests
                if "/rest/v1/rpc/get_app_state_v187" in request.url
            ]
        )

    async def queue_local_settings(self, settings):
        await self.page.evaluate(
            """async value=>{
                db.settings={...(db.settings||{}),...value};
                v188QueueLatest();
                await v188IdbFlush();
            }""",
            settings,
        )

    async def queue_conflict(self, base, local, remote):
        self.server.data = {**self.server.data, "settings": remote}
        self.server.version = 2
        await self.page.evaluate(
            """async ([base,local])=>{
                db.settings={...(db.settings||{}),...base};
                v188WriteBase(v161Snapshot(),1);
                db.settings={...(db.settings||{}),...local};
                v188QueueLatest();
                await v188IdbFlush();
                syncState='競合';
            }""",
            [base, local],
        )

    async def test_dom_refresh_loads_renders_and_returns_true_when_no_data_is_pending(self):
        self.server.data = {**self.server.data, "settings": {"remote": "current"}}
        await self.page.evaluate(
            """()=>{
                home();
                window.__refreshTrace={loads:0,renders:0};
                const actual=window.refreshData;
                window.__refreshResults=[];
                window.refreshData=async function(...args){
                    const result=await actual.apply(this,args);
                    window.__refreshResults.push(result===undefined?null:result);
                    return result;
                };
            }"""
        )
        await self.page.locator('[data-seika-click-action="refreshData"]').click()
        await self.page.wait_for_function("()=>window.__refreshResults.length===1")
        state = await self.page.evaluate(
            """()=>({result:window.__refreshResults[0],trace:window.__refreshTrace,
                queue:v161ReadQueue().length,sync:syncState,remote:db.settings?.remote})"""
        )
        self.assertEqual(
            state,
            {
                "result": True,
                "trace": {"loads": 1, "renders": 1},
                "queue": 0,
                "sync": "保存済み",
                "remote": "current",
            },
        )

    async def test_pending_save_failure_keeps_queue_and_does_not_call_load_cloud(self):
        await self.queue_local_settings({"local": "keep"})
        self.server.mode = "fail"
        state = await self.refresh()
        self.assertEqual(state["result"], None)
        self.assertEqual(state["trace"]["loads"], 0)
        self.assertEqual(state["queue"], 1)
        self.assertEqual(state["settings"]["local"], "keep")
        self.assertEqual(await self.load_cloud_request_count(), 0)

    async def test_failed_pending_save_retries_then_loads_after_the_queue_is_cleared(self):
        await self.queue_local_settings({"local": "retry"})
        self.server.mode = "fail"
        first = await self.refresh()
        self.assertEqual((first["queue"], first["trace"]["loads"]), (1, 0))

        self.server.mode = "ok"
        second = await self.refresh()
        self.assertEqual(second["result"], True)
        self.assertEqual(second["queue"], 0)
        self.assertEqual(second["trace"], {"loads": 1, "renders": 2})
        self.assertEqual(self.server.data["settings"]["local"], "retry")

    async def test_conflict_with_different_settings_merges_then_reloads(self):
        await self.queue_conflict({"base": "same"}, {"local": "new"}, {"base": "same", "remote": "new"})
        state = await self.refresh()
        self.assertEqual(state["result"], True)
        self.assertEqual(state["queue"], 0)
        self.assertEqual(state["trace"], {"loads": 1, "renders": 2})
        self.assertEqual(self.server.data["settings"], {"base": "same", "local": "new", "remote": "new"})
        self.assertEqual(
            {key: state["settings"][key] for key in ("base", "local", "remote")},
            self.server.data["settings"],
        )

    async def test_conflict_on_same_setting_keeps_both_sides_protected_without_load_cloud(self):
        await self.queue_conflict({"shared": "base"}, {"shared": "local"}, {"shared": "remote"})
        state = await self.refresh()
        pending = await self.page.evaluate("()=>v161ReadQueue()[0]")
        self.assertEqual(state["result"], None)
        self.assertEqual(state["trace"]["loads"], 0)
        self.assertEqual(state["queue"], 1)
        self.assertEqual(state["sync"], "競合")
        self.assertEqual(state["settings"]["shared"], "local")
        self.assertEqual(pending["localPayload"]["settings"]["shared"], "local")
        self.assertEqual(self.server.data["settings"]["shared"], "remote")


if __name__ == "__main__":
    unittest.main()
