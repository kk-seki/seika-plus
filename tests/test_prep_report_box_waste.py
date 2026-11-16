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
    def test_case_and_open_box_kg_calculate_qty_and_save_manual_waste(self):
        page = self.open_app()
        self.open_new(page)
        page.locator('.c117CaseQty').fill('2')
        page.locator('.c117OpenBoxKg').fill('1.7')
        page.locator('[data-c117-output="P1"] input').fill('11')
        page.locator('#c117Waste').fill('0.7')
        page.evaluate('()=>c117WasteInput()')
        self.assertIn('使用合計 21.7 kg', page.locator('#c117Totals').inner_text())
        self.assertIn('計量差 10', page.locator('#c117Totals').inner_text())
        page.evaluate('()=>c120Review();c120SaveDraft()')
        payload = page.evaluate("()=>__calls.find(x=>x[0]==='hq_prep_report_save_v1199c120')[1].p_report")
        self.assertAlmostEqual(payload['materials'][0]['qty'], 2.17)
        self.assertEqual(payload['waste_kg'], .7)
        self.assertIn('廃棄 0.7 kg（手入力）', page.locator('body').inner_text())
        self.assertIn('計量差 10 kg', page.locator('body').inner_text())

    def test_auto_waste_is_omitted_and_negative_measurement_diff_blocks_review(self):
        page = self.open_app()
        self.open_new(page)
        page.locator('.c117CaseQty').fill('2')
        page.locator('.c117OpenBoxKg').fill('1.7')
        page.locator('[data-c117-output="P1"] input').fill('11')
        page.evaluate('()=>c117Input()')
        self.assertIn('自動にもどす（10.7 kg）', page.locator('#c117Totals').inner_text())
        page.evaluate('()=>c120Review();c120SaveDraft()')
        payload = page.evaluate("()=>__calls.find(x=>x[0]==='hq_prep_report_save_v1199c120')[1].p_report")
        self.assertNotIn('waste_kg', payload)
        page.evaluate('()=>c120Edit()')
        page.locator('#c117Waste').fill('12')
        page.evaluate('()=>c117WasteInput()')
        self.assertIn('出来高と廃棄の合計が、使用した原料の重さを超えています。', page.locator('#c117Totals').inner_text())
        page.evaluate('()=>c120Review()')
        self.assertIn('出来高と廃棄の合計が、使用した原料の重さを超えています。', page.locator('#c117Error').inner_text())

    def test_existing_report_with_non_auto_waste_opens_manual_mode(self):
        page = self.open_app()
        page.evaluate("""()=>{
          const original=window.__h2.h2Works;
          window.__h2.h2Works=async q=>(await original(q)).map(w=>w.id==='C120'?{...w,waste_kg:2}:w);
          window.__h2.h2Materials=async()=>[{id:'WM1',work_id:'C120',lot_id:'L1',lot_no:'LOT-1',item_name:'キャベツ',unit:'case',pack_kg:10,qty:5}];
        }""")
        page.evaluate("()=>c117ReportPage('C120')")
        page.locator('#c117Waste').wait_for()
        self.assertEqual(page.locator('#c117Waste').input_value(), '2')
        self.assertEqual(page.locator('#c117Waste').get_attribute('data-manual'), '1')
        self.assertIn('自動にもどす（20 kg）', page.locator('#c117Totals').inner_text())


if __name__ == '__main__':
    unittest.main()
