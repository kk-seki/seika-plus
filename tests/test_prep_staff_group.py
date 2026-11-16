import unittest

import test_prep_work as prep_work

TEAMS = {
    "S1": "下処理班①",
    "S2": "下処理班②",
    "S3": "ライン班",
    "S4": "手切班",
    "S5": "機械班",
    "S6": "人参班",
}


class PrepStaffGroupTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        prep_work.PrepWorkTests.setUpClass()
        cls.helper = prep_work.PrepWorkTests()

    @classmethod
    def tearDownClass(cls):
        prep_work.PrepWorkTests.tearDownClass()

    def app(self, role="hq_prep"):
        page = self.helper.app(role)
        self.addCleanup(self.helper.doCleanups)
        page.evaluate(
            "t=>{__T.hq_staff_v1500.forEach(s=>{s.team=t[s.id];s.qr_key='HQST-'+s.id})}",
            TEAMS,
        )
        return page

    def groups(self, page, root="#h2NwBody"):
        return page.evaluate(
            "r=>[...document.querySelectorAll(r+' details[data-h2g]')].map(d=>[d.dataset.h2g,d.querySelectorAll('.h2PickChk').length,d.open])",
            root,
        )

    def test_start_screen_groups_are_folded_and_multi_select_adds_once(self):
        page = self.app()
        page.evaluate("()=>hqPrepNew('清掃')")
        page.wait_for_selector("#h2NwBody details[data-h2g]")
        self.assertEqual(
            self.groups(page),
            [["下処理班", 2, False], ["ライン班", 1, False], ["手切班", 1, False], ["機械班", 1, False], ["その他", 1, False]],
        )
        self.assertTrue(page.get_by_role("button", name="選んだ人を追加する（0名）", exact=True).is_disabled())
        page.locator("summary", has_text="下処理班").click()
        page.locator('.h2PickChk[data-id="S1"]').check()
        page.locator('.h2PickChk[data-id="S2"]').check()
        self.assertEqual(self.groups(page)[0], ["下処理班", 2, True])
        page.get_by_role("button", name="選んだ人を追加する（2名）", exact=True).click()
        chips = page.locator("#h2NwBody .h2Chip").all_text_contents()
        self.assertTrue(any("佐藤 花子" in c for c in chips) and any("鈴木 美咲" in c for c in chips))
        self.assertNotIn("下処理班", [g[0] for g in self.groups(page)])

    def test_open_group_and_checks_survive_removing_a_chip(self):
        page = self.app()
        page.evaluate("()=>hqPrepNew('清掃')")
        page.evaluate("()=>h2NwAddStaff('S3')")
        page.locator("summary", has_text="手切班").click()
        page.locator('.h2PickChk[data-id="S4"]').check()
        page.locator("#h2NwBody .h2Chip button").first.click()
        self.assertTrue(dict((g[0], g[2]) for g in self.groups(page))["手切班"])
        self.assertTrue(page.locator('.h2PickChk[data-id="S4"]').is_checked())

    def test_join_adds_selected_people_in_one_call_and_hides_people_already_working(self):
        page = self.app()
        page.evaluate("()=>hqWorkPage('W1')")
        page.wait_for_timeout(80)
        page.get_by_role("button", name="途中から入る人を追加", exact=True).click()
        page.wait_for_selector("#h2JoinBox details[data-h2g]")
        shown = page.evaluate("()=>[...document.querySelectorAll('#h2JoinBox .h2PickChk')].map(c=>c.dataset.id)")
        working = page.evaluate("()=>__T.hq_work_members_v1500.filter(m=>m.work_id==='W1'&&!m.end_at).map(m=>m.staff_id)")
        self.assertTrue(working)
        for sid in working:
            self.assertNotIn(sid, shown)
        pick = [s for s in shown if s not in working][:2]
        self.assertEqual(len(pick), 2)
        for g in page.locator("#h2JoinBox summary").all():
            g.click()
        for sid in pick:
            page.locator(f'#h2JoinBox .h2PickChk[data-id="{sid}"]').check()
        page.get_by_role("button", name="選んだ人を追加する（2名）", exact=True).click()
        page.wait_for_function("()=>__calls.some(c=>c.n==='hq_work_join_v1500')")
        calls = self.helper.calls(page, "hq_work_join_v1500")
        self.assertEqual(len(calls), 1)
        self.assertEqual(sorted(calls[0]["a"]["p_staff_ids"]), sorted(pick))

    def test_touch_targets_are_large_for_older_users(self):
        page = self.app()
        page.evaluate("()=>hqPrepNew('清掃')")
        page.locator("summary", has_text="下処理班").click()
        sizes = page.evaluate(
            "()=>({s:document.querySelector('.h2PickG summary').getBoundingClientRect().height,r:document.querySelector('.h2PickRow').getBoundingClientRect().height,f:parseFloat(getComputedStyle(document.querySelector('.h2PickRow')).fontSize)})"
        )
        self.assertGreaterEqual(sizes["s"], 56)
        self.assertGreaterEqual(sizes["r"], 56)
        self.assertGreaterEqual(sizes["f"], 20)


if __name__ == "__main__":
    unittest.main()
