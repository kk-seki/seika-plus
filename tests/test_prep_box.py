"""c123 箱の半端表示をブラウザRPCモックで確認する。"""
import unittest

import test_prep_pallet as pallet


class PrepBoxTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        pallet.PrepPalletTests.setUpClass()
        cls.helper = pallet.PrepPalletTests()

    @classmethod
    def tearDownClass(cls):
        pallet.PrepPalletTests.tearDownClass()

    def test_case_kg_helper_is_public_and_formats_open_box_remainder(self):
        page = self.helper.app()
        self.addCleanup(self.helper.doCleanups)
        page.evaluate(pallet.SETUP)
        self.assertEqual(page.evaluate("()=>window.hqCaseKgText(39.66,5,'ケース')"), "39ケース＋開けた箱3.3kg")
        self.assertEqual(page.evaluate("()=>window.hqCaseKgText(39,5,'ケース')"), "39ケース")


if __name__ == '__main__':
    unittest.main()
