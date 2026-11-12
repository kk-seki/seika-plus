import unittest

import test_prep_work as prep_work


class PrepStaffStandardTests(unittest.TestCase):
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
        page.evaluate("""()=>{
          __T.hq_staff_v1500.forEach((s,i)=>{s.print_group=1;s.qr_key='HQST-'+s.id});
          window.__scanners=[];window.__starts=0;window.__stops=0;
          window.Html5Qrcode=class {
            constructor(id){this.id=id;__scanners.push(this)}
            async start(_camera,_config,cb){__starts++;this.cb=cb}
            async stop(){__stops++;this.stopped=true}
            clear(){}
          };
          window.__standards=[];
          const selectBase=qrSelect;
          qrSelect=async(t,q)=>t==='hq_prep_standards_v1199c117'?__standards:selectBase(t,q);
          const base=callRpc;
          callRpc=async(n,a)=>{
            if(n==='hq_prep_standard_save_v1199c117'){__calls.push({n,a});return {ok:true}}
            return base(n,a);
          };
        }""")
        return page

    def test_staff_selected_without_camera_and_staff_camera_stops_before_callback(self):
        page = self.app()
        page.evaluate("()=>hqPrepNew('清掃')")
        self.assertEqual(page.evaluate("()=>__starts"), 0)
        page.evaluate("()=>h2NwAddStaff('S1')")
        self.assertIn("佐藤 花子", page.locator("#h2NwBody").inner_text())
        page.evaluate("()=>h2NwStaffCamera()")
        self.assertEqual(page.evaluate("()=>__starts"), 1)
        page.evaluate("async()=>{const s=__scanners.at(-1);await Promise.all([s.cb('HQST-S2'),s.cb('HQST-S2')])}")
        self.assertEqual(page.evaluate("()=>__stops"), 1)
        self.assertEqual(page.locator("#h2NwBody .h2Chip").count(), 2)
        page.evaluate("()=>__scanners.at(-1).cb('HQST-S3')")
        self.assertEqual(page.locator("#h2NwBody .h2Chip").count(), 2)

    def test_material_camera_ignores_staff_and_switching_selection_stops_camera(self):
        page = self.app()
        page.evaluate("()=>hqPrepNew('下処理')")
        self.assertEqual(page.evaluate("()=>__starts"), 1)
        page.evaluate("()=>__scanners.at(-1).cb('HQST-S1')")
        self.assertNotIn("佐藤 花子", page.locator("#h2NwBody .h2Chip").all_text_contents())
        page.evaluate("()=>h2NwAddStaff('S2')")
        page.wait_for_function("()=>__stops===1")
        self.assertIn("鈴木 美咲", page.locator("#h2NwBody").inner_text())

    def test_join_selection_opens_no_camera_and_qr_failure_still_stops(self):
        page = self.app()
        page.evaluate("()=>hqWorkPage('W1')")
        page.evaluate("()=>h2WorkJoinOpen('W1')")
        self.assertEqual(page.evaluate("()=>__starts"), 0)
        page.evaluate("()=>h2JoinStaffCamera('W1')")
        page.evaluate("()=>__scanners.at(-1).cb('HQST-NOT-REGISTERED')")
        self.assertEqual(page.evaluate("()=>__stops"), 1)
        self.assertIn("登録されていません", page.evaluate("()=>__alerts.at(-1)"))

    def test_operation_screen_selects_staff_and_scanner_is_single_shot(self):
        page = self.app()
        page.evaluate("()=>hqOpScanPage()")
        self.assertEqual(page.evaluate("()=>__starts"), 0)
        page.select_option("#h2OpStaff", "S1")
        self.assertIn("佐藤 花子", page.locator("#h2OpInfo").inner_text())
        page.evaluate("()=>h2OpStaffCamera()")
        page.evaluate("()=>__scanners.at(-1).cb('HQST-S2')")
        self.assertEqual(page.evaluate("()=>__stops"), 1)
        self.assertIn("鈴木 美咲", page.locator("#h2OpInfo").inner_text())
        self.assertNotIn("佐藤 花子", page.locator("#h2OpInfo").inner_text())

    def test_standard_setting_permissions_pair_and_api(self):
        page = self.app("hq_worker")
        page.evaluate("()=>hqPrepMasterPage()")
        page.locator("#c117Standards").wait_for()
        forms = page.locator(".c117StandardForm")
        self.assertEqual(forms.count(), 7)
        pair = forms.last
        self.assertIn("1/4芯＋1/4葉", pair.inner_text())
        pair.locator(".c117StandardRate").fill("85")
        self.assertEqual(pair.locator(".c117StandardTolerance").input_value(), "5")
        pair.get_by_role("button", name="標準歩留まりを保存").click()
        args = page.evaluate("()=>__calls.find(c=>c.n==='hq_prep_standard_save_v1199c117').a")
        self.assertEqual(args, {"p_master_ids": ["PMC", "PML"], "p_standard_rate": 85, "p_tolerance_points": 5})
        page.evaluate("()=>db.role='hq_prep'")
        page.evaluate("()=>c117StandardSave(['PMC','PML'])")
        self.assertEqual(page.evaluate("()=>__calls.filter(c=>c.n==='hq_prep_standard_save_v1199c117').length"), 1)

    def test_standard_badge_uses_raw_weight_and_inclusive_tolerance(self):
        page = self.app()
        for rate, label in [(80, "標準範囲内"), (90, "標準範囲内"), (79.9, "標準範囲外"), (90.1, "標準範囲外")]:
            html = page.evaluate("""rate=>c117StandardBadge({yield_kg:rate,waste_kg:999,standard_rate:85,tolerance_points:5},[{qty:10,unit:'case',pack_kg:10}])""", rate)
            self.assertIn(label, html)
            self.assertIn(f"{rate}%", html)
        unset = page.evaluate("()=>c117StandardBadge({yield_kg:80},[{qty:100,unit:'kg'}])")
        self.assertIn("標準未設定", unset)

    def test_employee_list_and_confirmation_recalculate_auto_waste(self):
        page = self.app("hq_worker")
        page.evaluate("()=>Object.assign(__T.hq_works_v1500.find(w=>w.id==='W3'),{standard_rate:85,tolerance_points:5})")
        page.evaluate("()=>hqPrepCheckPage()")
        self.assertGreater(page.locator(".c117StandardBadge").count(), 0)
        page.evaluate("()=>hqPrepConfirmPage('W3')")
        self.assertTrue(page.locator("#h2CfW").evaluate("el=>el.readOnly"))
        fields = page.locator(".h2OutputQty")
        fields.nth(0).fill("30")
        fields.nth(1).fill("30")
        self.assertEqual(page.locator("#h2CfW").input_value(), "20")
        self.assertIn("75%", page.locator(".c117StandardBadge").inner_text())
        self.assertIn("標準範囲外", page.locator(".c117StandardBadge").inner_text())
        fields.nth(0).fill("100")
        self.assertEqual(page.locator("#h2CfW").input_value(), "")

    def test_failed_standard_save_is_not_reported_as_success(self):
        page = self.app("hq_worker")
        page.evaluate("()=>hqPrepMasterPage()")
        page.locator(".c117StandardForm").first.wait_for()
        page.locator(".c117StandardRate").first.fill("80")
        page.evaluate("""()=>{const base=callRpc;callRpc=async(n,a)=>n==='hq_prep_standard_save_v1199c117'?{ok:false,message:'保存失敗'}:base(n,a)}""")
        page.locator(".c117StandardForm").first.get_by_role("button", name="標準歩留まりを保存").click()
        self.assertEqual(page.evaluate("()=>__alerts.at(-1)"), "保存失敗")
        self.assertFalse(page.evaluate("()=>__alerts.some(m=>m.includes('保存しました'))"))

    def test_confirmation_sends_screen_version_and_keeps_inputs_on_conflict(self):
        page = self.app("hq_worker")
        page.evaluate("()=>hqPrepConfirmPage('W3')")
        page.locator("#h2CfW").wait_for()
        version = page.evaluate("()=>__T.hq_works_v1500.find(w=>w.id==='W3').updated_at")
        page.evaluate("""()=>{const base=callRpc;callRpc=async(n,a)=>{if(n==='hq_prep_confirm_v1199c117'){__calls.push({n,a});return {ok:false,conflict:true,message:'他の操作で内容が変わりました'}}return base(n,a)}}""")
        page.get_by_role("button", name="この内容で確定する", exact=True).click()
        page.wait_for_function("()=>__calls.some(c=>c.n==='hq_prep_confirm_v1199c117')")
        args = page.evaluate("()=>__calls.find(c=>c.n==='hq_prep_confirm_v1199c117').a")
        self.assertEqual(args["p_expected_updated_at"], version)
        self.assertEqual(len(args["p_outputs"]), 2)
        self.assertIn("変わりました", page.evaluate("()=>__alerts.at(-1)"))
        self.assertEqual(page.locator(".h2OutputQty").first.input_value(), "40")

    def test_role_guides_match_selection_report_and_standard_workflow(self):
        page = self.app()
        sections = page.evaluate("()=>V195_ROLE_GUIDES.hq_prep.sections")
        report = next(s for s in sections if s["title"] == "下処理日報をあとから登録・確認・編集する")
        self.assertIn("下処理班で全項目", " ".join(report["steps"]))
        start = next(s for s in sections if s["title"] == "下処理を始める（パートさん）")
        self.assertIn("一覧から選びます", " ".join(start["steps"]))
        self.assertNotIn("標準歩留まりを設定して日報を確認する", [s["title"] for s in sections])
        boss_titles = page.evaluate("()=>V195_ROLE_GUIDES.hq_worker.sections.map(s=>s.title)")
        self.assertIn("標準歩留まりを設定して日報を確認する", boss_titles)


if __name__ == "__main__":
    unittest.main()
