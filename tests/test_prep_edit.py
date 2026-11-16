"""c124 下処理の削除・休憩追加・作業者時刻をブラウザRPCモックで確認する。"""
import unittest

import test_prep_work as prep_work


SETUP = r"""()=>{
  const T=__T,clone=x=>JSON.parse(JSON.stringify(x)),w=id=>T.hq_works_v1500.find(x=>x.id===id),members=id=>T.hq_work_members_v1500.filter(x=>x.work_id===id);
  T.hq_work_pauses_v1199c116=[];T.hq_works_v1500.forEach(x=>{x.stock_applied=false});
  const base=callRpc;
  callRpc=async(n,a)=>{
    if(['hq_work_delete_v1199c124','hq_work_leave_v1199c124','hq_work_member_time_fix_v1199c124','hq_work_pause_add_v1199c124','hq_work_resume_v1199c124'].includes(n))__calls.push({n,a:clone(a)});
    if(n==='hq_work_delete_v1199c124'){T.hq_works_v1500=T.hq_works_v1500.filter(x=>x.id!==a.p_work_id);return {ok:true,restored:false}}
    if(n==='hq_work_leave_v1199c124'){const m=members(a.p_work_id).find(x=>x.staff_id===a.p_staff_id&&!x.end_at);if(!m)throw new Error('この人は、この作業に入っていません');m.end_at=a.p_leave_at;return {ok:true}}
    if(n==='hq_work_member_time_fix_v1199c124'){if(window.__fixError)throw new Error(window.__fixError);const m=T.hq_work_members_v1500.find(x=>x.id===a.p_member_id);m.start_at=a.p_start;m.end_at=a.p_end;return {ok:true}}
    if(n==='hq_work_pause_add_v1199c124'){
      const x=w(a.p_work_id),active=members(x.id).filter(m=>a.p_staff_ids.includes(m.staff_id)&&!m.end_at&&m.phase==='作業');
      if(active.length!==a.p_staff_ids.length)throw new Error('いま作業中の人だけ選べます');
      active.forEach(m=>{m.end_at=a.p_at;m.end_reason='休憩'});T.hq_work_pauses_v1199c116.push({id:'C124'+Date.now(),work_id:x.id,kind:'休憩',start_at:a.p_at,end_at:null,staff_ids:clone(a.p_staff_ids),resumed_staff_ids:[],excluded_staff_ids:[]});x.pause_kind='休憩';return {ok:true};
    }
    if(n==='hq_work_resume_v1199c124'){
      const x=w(a.p_work_id),open=T.hq_work_pauses_v1199c116.filter(p=>p.work_id===x.id&&!p.end_at);
      a.p_staff_ids.forEach((sid,i)=>{const p=open.find(q=>q.staff_ids.includes(sid)&&!(q.resumed_staff_ids||[]).includes(sid));if(!p)throw new Error('再開待ちではありません');p.resumed_staff_ids=[...(p.resumed_staff_ids||[]),sid];const s=T.hq_staff_v1500.find(q=>q.id===sid);T.hq_work_members_v1500.push({id:'C124R'+Date.now()+i,work_id:x.id,staff_id:sid,staff_name:s.name,team:s.team,phase:'作業',start_at:new Date().toISOString()})});
      open.forEach(p=>{if(p.staff_ids.every(sid=>p.resumed_staff_ids.includes(sid)))p.end_at=new Date().toISOString()});x.pause_kind=open.some(p=>!p.end_at)?'休憩':'';return {ok:true};
    }
    return base(n,a);
  };
}"""


class PrepEditTests(unittest.TestCase):
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
        page.evaluate(SETUP)
        return page

    @staticmethod
    def calls(page, name):
        return page.evaluate("n=>__calls.filter(c=>c.n===n)", name)

    def work_page(self, page, work_id="W1"):
        page.evaluate("id=>hqWorkPage(id)", work_id)
        page.wait_for_timeout(80)

    def test_prep_can_delete_unconfirmed_only_and_uses_c124_rpc(self):
        page = self.app()
        self.work_page(page)
        page.get_by_text("この記録を完全に削除する", exact=True).click()
        delete = page.get_by_role("button", name="完全に削除する", exact=True)
        self.assertGreaterEqual(delete.bounding_box()["height"], 60)
        delete.click()
        page.wait_for_function("()=>__calls.some(c=>c.n==='hq_work_delete_v1199c124')")
        self.assertEqual(self.calls(page, "hq_work_delete_v1199c124")[0]["a"], {"p_work_id": "W1"})

        page = self.app()
        page.evaluate("()=>{const w=__T.hq_works_v1500.find(x=>x.id==='W1');w.confirm_status='確定';w.stock_applied=true}")
        self.work_page(page)
        self.assertEqual(page.get_by_text("この記録を完全に削除する", exact=True).count(), 0)

    def test_add_pause_then_resume_across_all_open_pauses(self):
        page = self.app()
        page.evaluate("""()=>{const w=__T.hq_works_v1500.find(x=>x.id==='W1');w.pause_kind='休憩';const s2=__T.hq_work_members_v1500.find(m=>m.id==='P2');s2.end_at='2026-11-15T01:00:00Z';s2.end_reason='休憩';__T.hq_work_pauses_v1199c116=[{id:'OLD',work_id:'W1',kind:'休憩',start_at:'2026-11-15T01:00:00Z',end_at:null,staff_ids:['S2'],resumed_staff_ids:[]}]}""")
        self.work_page(page)
        page.get_by_role("button", name="休憩に入る人を追加", exact=True).click()
        page.locator(".c116PausePerson[value='S1']").check()
        page.locator("#c124PauseAt").fill("2026-11-15T10:40")
        page.get_by_role("button", name="選んだ人を休憩にする", exact=True).click()
        page.wait_for_function("()=>__calls.some(c=>c.n==='hq_work_pause_add_v1199c124')")
        added = self.calls(page, "hq_work_pause_add_v1199c124")[0]["a"]
        self.assertEqual((added["p_staff_ids"], added["p_at"]), (["S1"], "2026-11-15T10:40:00+09:00"))
        page.get_by_role("button", name="休憩から再開する", exact=True).click()
        self.assertIn("佐藤 花子（10:40から）", page.locator("#c116PauseBox").inner_text())
        page.get_by_role("button", name="選んだ人で再開", exact=True).click()
        page.wait_for_function("()=>__calls.some(c=>c.n==='hq_work_resume_v1199c124')")
        resumed = self.calls(page, "hq_work_resume_v1199c124")[0]["a"]
        self.assertEqual(set(resumed["p_staff_ids"]), {"S1", "S2"})

    def test_leave_uses_selected_time_and_large_controls(self):
        page = self.app()
        self.work_page(page)
        page.get_by_role("button", name="抜ける", exact=True).first.click()
        field = page.locator("#c124LeaveAt")
        field.fill("2026-11-15T10:30")
        leave = page.get_by_role("button", name="この時刻で抜ける", exact=True)
        self.assertGreaterEqual(leave.bounding_box()["height"], 60)
        leave.click()
        page.wait_for_function("()=>__calls.some(c=>c.n==='hq_work_leave_v1199c124')")
        args = self.calls(page, "hq_work_leave_v1199c124")[0]["a"]
        self.assertEqual(args["p_leave_at"], "2026-11-15T10:30:00+09:00")

    def test_time_fix_preserves_input_on_error_and_pause_row_is_disabled(self):
        page = self.app()
        page.evaluate("""()=>{const m=__T.hq_work_members_v1500.find(x=>x.id==='P2');m.end_at='2026-11-15T01:00:00Z';m.end_reason='休憩'}""")
        self.work_page(page)
        pause_button = page.get_by_role("button", name="休憩から直してください", exact=True)
        self.assertTrue(pause_button.is_disabled())
        page.get_by_role("button", name="時間を直す", exact=True).first.click()
        page.locator("#c124MemberStart").fill("2026-11-15T09:00")
        page.locator("#c124MemberEnd").fill("2026-11-15T10:20")
        page.evaluate("()=>window.__fixError='別の作業と時間が重なっています'")
        page.get_by_role("button", name="この時間で保存", exact=True).click()
        page.wait_for_function("()=>__alerts.some(x=>x.includes('重な'))")
        self.assertEqual(page.locator("#c124MemberStart").input_value(), "2026-11-15T09:00")
        self.assertEqual(page.locator("#c124MemberEnd").input_value(), "2026-11-15T10:20")
        args = self.calls(page, "hq_work_member_time_fix_v1199c124")[0]["a"]
        self.assertEqual((args["p_start"], args["p_end"]), ("2026-11-15T09:00:00+09:00", "2026-11-15T10:20:00+09:00"))


if __name__ == "__main__":
    unittest.main()
