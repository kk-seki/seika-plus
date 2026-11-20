import unittest

from tests import test_prep_report as prep_report


class PrepReportBoxWasteBrowserTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        prep_report.PrepReportBrowserTests.setUpClass.__func__(cls)

    @classmethod
    def tearDownClass(cls):
        prep_report.PrepReportBrowserTests.tearDownClass.__func__(cls)

    open_app = prep_report.PrepReportBrowserTests.open_app
    open_new = prep_report.PrepReportBrowserTests.open_new
    MEASURED = "()=>{window.hqItemRuleOf=()=>null}"  # 品目ルールにない品目＝廃棄を量る

    def test_measured_item_requires_waste_weight_and_hides_unknown_loss_for_prep(self):
        page = self.open_app()
        page.evaluate(self.MEASURED)
        self.open_new(page)
        page.locator('.c117CaseQty').fill('2')
        page.locator('.c117OpenBoxKg').fill('1.7')
        page.locator('[data-c117-output="P1"] input').fill('11')
        page.evaluate('()=>c117Input()')
        self.assertIn('廃棄の重さ（kg）', page.locator('#c117Totals').inner_text())
        self.assertNotIn('自動にもどす', page.locator('#c117Totals').inner_text())
        page.evaluate('()=>c120Review()')
        self.assertIn('廃棄の重さを量って入れてください。', page.locator('#c117Error').inner_text())
        page.locator('#c117Waste').fill('0.7')
        page.evaluate('()=>c117WasteInput()')
        totals = page.locator('#c117Totals').inner_text()
        self.assertIn('使用合計 21.7 kg', totals)
        self.assertNotIn('不明ロス', totals)
        page.evaluate('()=>c120Review();c120SaveDraft()')
        payload = page.evaluate("()=>__calls.find(x=>x[0]==='hq_prep_report_save_v1199c120')[1].p_report")
        self.assertAlmostEqual(payload['materials'][0]['qty'], 2.17)
        self.assertEqual(payload['waste_kg'], .7)
        body = page.locator('body').inner_text()
        self.assertIn('廃棄 0.7 kg（量った重さ）', body)
        self.assertNotIn('不明ロス', body)

    def test_unknown_loss_is_shown_to_employee_for_measured_item(self):
        page = self.open_app('hq_worker')
        page.evaluate(self.MEASURED)
        self.open_new(page)
        page.locator('.c117CaseQty').fill('2')
        page.locator('.c117OpenBoxKg').fill('1.7')
        page.locator('[data-c117-output="P1"] input').fill('11')
        page.locator('#c117Waste').fill('0.7')
        page.evaluate('()=>c117WasteInput()')
        self.assertIn('不明ロス 10 kg', page.locator('#c117Totals').inner_text())
        page.locator('#c117Waste').fill('12')
        page.evaluate('()=>c117WasteInput()')
        self.assertIn('出来高と廃棄の合計が、使用した原料の重さを超えています。', page.locator('#c117Totals').inner_text())
        page.evaluate('()=>c120Review()')
        self.assertIn('出来高と廃棄の合計が、使用した原料の重さを超えています。', page.locator('#c117Error').inner_text())

    def test_unmeasured_item_has_no_waste_input_and_omits_waste(self):
        page = self.open_app()
        self.open_new(page)
        page.locator('.c117CaseQty').fill('2')
        page.locator('.c117OpenBoxKg').fill('1.7')
        page.locator('[data-c117-output="P1"] input').fill('11')
        page.evaluate('()=>c117Input()')
        self.assertEqual(page.locator('#c117Waste').count(), 0)
        self.assertIn('廃棄は自動で計算します（推定）：10.7 kg', page.locator('#c117Totals').inner_text())
        self.assertIn('（推定：量目で計算した原料があります）', page.locator('#c117Totals').inner_text())
        page.evaluate('()=>c120Review();c120SaveDraft()')
        payload = page.evaluate("()=>__calls.find(x=>x[0]==='hq_prep_report_save_v1199c120')[1].p_report")
        self.assertNotIn('waste_kg', payload)
        self.assertIn('（自動計算・推定）', page.locator('body').inner_text())

    def test_measured_case_weight_is_used_and_not_estimated(self):
        page = self.open_app()
        page.evaluate("()=>{window.__h2.r2=(o=>async(n,a)=>{const r=await o(n,a);return n.startsWith('hq_prep_available_lots')?r.map(l=>l.id==='L1'?{...l,case_measured_kg:10.5}:l):r})(window.__h2.r2)}")
        self.open_new(page)
        page.locator('.c117CaseQty').fill('2')
        page.locator('.c117OpenBoxKg').fill('0')
        page.evaluate('()=>c117Input()')
        totals = page.locator('#c117Totals').inner_text()
        self.assertIn('使用合計 21 kg', totals)
        self.assertNotIn('推定：量目', totals)
        self.assertIn('入荷時に量った重さ', page.locator('[data-c117-material="L1"]').inner_text())

    def test_saved_manual_waste_of_unmeasured_item_stays_for_employee_only(self):
        for role, has_input in (('hq_worker', True), ('hq_prep', False)):
            page = self.open_app(role)
            page.evaluate("""()=>{
              const original=window.__h2.h2Works;
              window.__h2.h2Works=async q=>(await original(q)).map(w=>w.id==='C120'?{...w,waste_kg:2}:w);
              window.__h2.h2Materials=async()=>[{id:'WM1',work_id:'C120',lot_id:'L1',lot_no:'LOT-1',item_name:'キャベツ',unit:'case',pack_kg:10,qty:5}];
            }""")
            page.evaluate("()=>c117ReportPage('C120')")
            page.locator('#c117Totals').wait_for()
            self.assertEqual(page.locator('#c117Waste').count(), 1 if has_input else 0, role)
            if has_input:
                self.assertEqual(page.locator('#c117Waste').input_value(), '2')
                self.assertIn('自動にもどす（20 kg）', page.locator('#c117Totals').inner_text())


if __name__ == '__main__':
    unittest.main()
