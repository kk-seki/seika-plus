"""c122 パレット／基ごとの原料使用記録をブラウザRPCモックで確認する。"""
import unittest

import test_prep_work as prep_work


SETUP = r"""()=>{
  const T=__T, clone=x=>JSON.parse(JSON.stringify(x));
  const work=T.hq_works_v1500.find(w=>w.id==='W1');
  Object.assign(work,{c120_flow:true,review_status:'draft',updated_at:'2026-11-12T01:00:00Z'});
  const lot=T.hq_lots_v1400.find(l=>l.id==='L1');
  Object.assign(lot,{sheet_meta:{palletQtys:[42,30]},current_qty:72,unit:'case'});
  const mat=T.hq_work_materials_v1500.find(m=>m.id==='M1');
  Object.assign(mat,{qty:0,pack_kg:5});
  window.__palletEntries=[];
  window.__palletCandidate={ok:true,lot_id:'L1',lot_no:lot.lot_no,item_name:'キャベツ',qty_unit:'ケース',large:false,pack_kg:5,source:'sheet',units:[
    {no:1,total:42,used:0,remaining:42,mine:0,state:'unused'},
    {no:2,total:30,used:0,remaining:30,mine:0,state:'unused'}],next_no:1,lot_available:72};
  const base=callRpc;
  callRpc=async(n,a)=>{
    if(n.startsWith('hq_work_pallet_')||n==='hq_pallet_candidates_v1199c122')__calls.push({n,a:clone(a)});
    if(n==='hq_pallet_candidates_v1199c122')return clone(__palletCandidate);
    if(n==='hq_work_pallet_list_v1199c122')return clone(__palletEntries);
    if(n==='hq_work_pallet_use_v1199c123'){
      if(__palletFailOnce){__palletFailOnce=false;throw new Error('通信エラー')}
      const c=__palletCandidate, before=a.p_unit_no==null?Number(a.p_unit_total):Number(c.units.find(u=>u.no===a.p_unit_no).remaining);
      const remaining=a.p_mode==='全量'?0:(a.p_unopened_cases!=null?Number(a.p_unopened_cases)+Number(a.p_open_box_kg)/Number(c.pack_kg):Number(a.p_remaining));
      const used=before-remaining;
      const entry={entry_id:'E'+(__palletEntries.length+1),work_id:a.p_work_id,material_id:'M1',lot_id:a.p_lot_id,unit_no:a.p_unit_no,unit_total:before,mode:a.p_mode,used_qty:used,remaining_qty:remaining,unopened_cases:a.p_unopened_cases??null,open_box_kg:a.p_open_box_kg??null};
      __palletEntries.push(entry);mat.qty+=used;return {ok:true,...entry,material_qty:mat.qty};
    }
    if(n==='hq_work_pallet_cancel_v1199c122'){
      const i=__palletEntries.findIndex(e=>e.entry_id===a.p_entry_id);if(i>=0){mat.qty-=__palletEntries[i].used_qty;__palletEntries.splice(i,1)}return {ok:true,material_qty:mat.qty};
    }
    return base(n,a);
  };
}"""


class PrepPalletTests(unittest.TestCase):
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
        page.evaluate("()=>hqWorkPage('W1')")
        page.locator("#c112Materials").wait_for()
        return page

    @staticmethod
    def calls(page, name):
        return page.evaluate("n=>__calls.filter(c=>c.n===n)", name)

    def open(self, page):
        page.evaluate("()=>h2PalletOpen('W1',__T.hq_lots_v1400.find(l=>l.id==='L1'))")
        page.locator(".c122Panel").wait_for()

    def test_first_unused_and_partial_are_auto_selected(self):
        page = self.app(); self.open(page)
        self.assertIn("パレット 1 / 2", page.locator(".c122Unit").inner_text())
        page.evaluate("()=>{__palletCandidate.units[0]={no:1,total:30,used:12,remaining:18,mine:24,state:'partial'};__palletCandidate.next_no=1;return h2PalletOpen('W1',__T.hq_lots_v1400.find(l=>l.id==='L1'))}")
        self.assertIn("18ケース（90kg）", page.locator(".c122Unit").inner_text())

    def test_choose_other_pallet_and_full_use_sends_contract_arguments(self):
        page = self.app(); self.open(page)
        page.get_by_role("button", name="別のパレットにする", exact=True).click()
        page.get_by_role("button", name="2　30ケース　未使用", exact=True).click()
        page.get_by_role("button", name="全部使った", exact=True).click()
        self.assertIn("30ケース（150kg）を使いました", page.locator(".c122Confirm").inner_text())
        page.get_by_role("button", name="これで記録する", exact=True).click()
        page.wait_for_function("()=>__calls.some(c=>c.n==='hq_work_pallet_use_v1199c123')")
        args = self.calls(page, "hq_work_pallet_use_v1199c123")[0]["a"]
        self.assertEqual((args["p_work_id"], args["p_lot_id"], args["p_unit_no"], args["p_mode"]), ("W1", "L1", 2, "全量"))
        self.assertIsNone(args["p_remaining"])
        self.assertRegex(args["p_operation_id"], r"^[0-9a-f-]{36}$")

    def test_partial_case_uses_unopened_and_open_box_kg(self):
        page = self.app(); self.open(page)
        page.get_by_role("button", name="半端が残った", exact=True).click()
        page.locator("#c122UnopenedCases").fill("39")
        page.locator("#c122OpenBoxKg").fill("3.3")
        self.assertIn("使った量＝2.34ケース（11.7kg）", page.locator(".c122Used").inner_text())
        self.assertIn("残り　39ケース＋開けた箱3.3kg", page.locator(".c122Used").inner_text())
        page.get_by_role("button", name="これで記録する", exact=True).click()
        page.wait_for_function("()=>__calls.some(c=>c.n==='hq_work_pallet_use_v1199c123')")
        args = self.calls(page, "hq_work_pallet_use_v1199c123")[0]["a"]
        self.assertEqual((args["p_mode"], args["p_unopened_cases"], args["p_open_box_kg"], args["p_remaining"]), ("半端", 39, 3.3, None))

    def test_public_case_kg_helper_and_partial_choice(self):
        page = self.app(); self.open(page)
        self.assertEqual(page.evaluate("()=>hqCaseKgText(39.66,5,'ケース')"), "39ケース＋開けた箱3.3kg")
        page.evaluate("()=>{__palletCandidate.units[0]={no:1,total:42,used:2.34,remaining:39.66,remaining_unopened:39,remaining_open_kg:3.3,state:'partial'};return h2PalletOpen('W1',__T.hq_lots_v1400.find(l=>l.id==='L1'))}")
        page.get_by_role("button", name="別のパレットにする", exact=True).click()
        self.assertIn("使いかけ　残り39ケース＋開けた箱3.3kg", page.locator(".c122Choices").inner_text())

    def test_partial_case_rejects_zero_fractional_case_and_open_box_at_pack(self):
        page = self.app(); self.open(page)
        page.get_by_role("button", name="半端が残った", exact=True).click()
        page.locator("#c122UnopenedCases").fill("0"); page.locator("#c122OpenBoxKg").fill("0")
        self.assertTrue(page.get_by_role("button", name="これで記録する", exact=True).is_disabled())
        page.locator("#c122UnopenedCases").fill("1.5"); page.locator("#c122OpenBoxKg").fill("1")
        self.assertTrue(page.get_by_role("button", name="これで記録する", exact=True).is_disabled())
        page.locator("#c122UnopenedCases").fill("1"); page.locator("#c122OpenBoxKg").fill("5")
        self.assertTrue(page.get_by_role("button", name="これで記録する", exact=True).is_disabled())

    def test_large_container_manual_and_all_done(self):
        page = self.app()
        page.evaluate("""()=>{__palletCandidate={ok:true,lot_id:'L1',lot_no:'H-C',item_name:'キャベツ',qty_unit:'kg',large:true,pack_kg:null,source:'container',units:[{no:1,total:300,used:0,remaining:300,mine:0,state:'unused'}],next_no:1,lot_available:300};return h2PalletOpen('W1',__T.hq_lots_v1400.find(l=>l.id==='L1'))}""")
        self.assertIn("1基目　300kg", page.locator(".c122Unit").inner_text())
        page.get_by_role("button", name="半端が残った", exact=True).click(); page.locator("#c122Remaining").fill("20")
        self.assertIn("使った量＝280kg", page.locator(".c122Used").inner_text())
        page.evaluate("""()=>{__palletCandidate={ok:true,lot_id:'L1',lot_no:'H-M',item_name:'キャベツ',qty_unit:'ケース',pack_kg:10,source:'manual',units:[],next_no:null,lot_available:99};return h2PalletOpen('W1',__T.hq_lots_v1400.find(l=>l.id==='L1'))}""")
        page.locator("#c122ManualTotal").fill("12")
        page.get_by_role("button", name="全部使った", exact=True).click()
        self.assertIn("12ケース（120kg）を使いました", page.locator(".c122Confirm").inner_text())
        page.evaluate("""()=>{__palletCandidate={ok:true,lot_id:'L1',lot_no:'H-D',item_name:'キャベツ',qty_unit:'ケース',pack_kg:10,source:'sheet',units:[{no:1,total:30,used:30,remaining:0,mine:0,state:'done'}],next_no:null,lot_available:0};return h2PalletOpen('W1',__T.hq_lots_v1400.find(l=>l.id==='L1'))}""")
        self.assertIn("すべてのパレット（基）が使用済み", page.locator(".c122Done").inner_text())
        self.assertEqual(page.get_by_role("button", name="これで記録する", exact=True).count(), 0)

    def test_cancel_confirms_and_retry_reuses_operation_id(self):
        page = self.app(); self.open(page)
        page.get_by_role("button", name="全部使った", exact=True).click()
        page.evaluate("()=>window.__palletFailOnce=true")
        page.get_by_role("button", name="これで記録する", exact=True).click()
        page.wait_for_function("()=>__calls.filter(c=>c.n==='hq_work_pallet_use_v1199c123').length===1")
        first = self.calls(page, "hq_work_pallet_use_v1199c123")[0]["a"]
        page.get_by_role("button", name="これで記録する", exact=True).click()
        page.wait_for_function("()=>__calls.filter(c=>c.n==='hq_work_pallet_use_v1199c123').length===2")
        self.assertEqual(self.calls(page, "hq_work_pallet_use_v1199c123")[1]["a"]["p_operation_id"], first["p_operation_id"])
        page.wait_for_selector(".c122Cancel")
        page.locator(".c122Cancel").click(); page.locator("#h2CfYes").click()
        page.wait_for_function("()=>__calls.some(c=>c.n==='hq_work_pallet_cancel_v1199c122')")

    def test_dirty_qr_rejection_and_accessible_dimensions(self):
        page = self.app()
        read = page.get_by_role("button", name="原料のQRを読む（1パレット・1基ずつ）", exact=True)
        box = read.bounding_box(); self.assertGreaterEqual(box["height"], 64)
        self.assertGreaterEqual(float(read.evaluate("el=>getComputedStyle(el).fontSize").replace("px", "")), 20)
        page.locator("details.c122Manual").locator("summary").click(); page.locator("#c112Qty_M1").fill("2")
        read.click(); self.assertIn("先に", page.evaluate("()=>__alerts.at(-1)"))
        page.locator("#c112Qty_M1").fill("")
        page.evaluate("()=>{delete document.getElementById('c112Materials').dataset.dirty;return h2PalletOpenReader('W1')}")
        page.wait_for_function("()=>typeof __reader==='function'")
        page.evaluate("()=>__reader('HQST-S1')")
        page.wait_for_selector("#h2ScanNotice")
        self.assertIn("スタッフ（人の名前）のQRを読みました", page.locator("#h2ScanNotice").inner_text())


if __name__ == "__main__":
    unittest.main()
