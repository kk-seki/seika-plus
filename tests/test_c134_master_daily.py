"""c134：マスタの入口とタブ・候補から外す、仕入れ担当者の日量ボタン、送った荷物の明細Excelを、架空データで確認する。"""
import unittest

import test_party_gap as base


class C134Tests(base.PartyGapBrowserTests):
    pass


for _name in [n for n in dir(base.PartyGapBrowserTests) if n.startswith("test_")]:
    setattr(C134Tests, _name, None)


def _t(fn):
    setattr(C134Tests, fn.__name__, fn)
    return fn


@_t
def test_party_page_has_tabs_and_hide_button(self):
    page = self.open_app(parties=[{"kind": "cooperative", "name": "JA水戸", "status": "active"}])
    page.evaluate("()=>v1208CandidatePage('cooperative','')")
    page.wait_for_selector("text=マスタにない単協名（ロットに入っている表記・1件）")
    self.assertTrue(page.is_visible("button:has-text('納品先')"))
    page.click("button:has-text('候補から外す')")
    page.wait_for_function("()=>window.__x.rpc.some(x=>x[0]==='set_qr_party_name_v1280'&&x[1].p_status==='hidden')")
    page.wait_for_selector("text=マスタにない単協名（ロットに入っている表記・0件）")
    self.assertIn("JA水戸市", page.inner_text("#app"))  # 非表示の一覧に出る
    page.evaluate("()=>v194DestinationsPage('')")
    page.wait_for_selector("#c134DestTabs")
    self.assertEqual(page.eval_on_selector("#c134DestTabs button.blue", "e=>e.textContent"), "納品先")
    worker = self.open_app("worker", parties=[{"kind": "cooperative", "name": "JA水戸", "status": "active"}])
    worker.evaluate("()=>v1208CandidatePage('cooperative','')")
    worker.wait_for_selector("text=マスタにない単協名")
    self.assertFalse(worker.is_visible("button:has-text('納品先')"))


@_t
def test_buyer_daily_buttons_average_by_shipping_days(self):
    page = self.open_app("buyer")
    page.evaluate("""()=>{const T=window.__T,now=Date.now(),day=k=>new Date(now-k*864e5).toISOString();
      T.qr_lots=[{id:'L1',item_name:'キャベツ',pack_weight:'10kg',container_type:'ダンボール'},{id:'L2',item_name:'人参',pack_weight:'',container_type:'ダンボール'}];
      T.qr_lot_movements=[
        {id:'a',lot_id:'L1',movement_type:'出庫',qty:3,weight:30,destination:'埼玉',occurred_at:day(1)},
        {id:'b',lot_id:'L1',movement_type:'出庫',qty:5,weight:50,destination:'本社',occurred_at:day(1)},
        {id:'c',lot_id:'L1',movement_type:'出庫',qty:4,weight:40,destination:'深谷',occurred_at:day(3)},
        {id:'d',lot_id:'L1',movement_type:'出庫',qty:9,weight:90,destination:'廃棄',occurred_at:day(2)},
        {id:'e',lot_id:'L1',movement_type:'出庫',qty:9,weight:90,destination:'埼玉',occurred_at:day(2),cancelled_at:day(2)},
        {id:'f',lot_id:'L2',movement_type:'出庫',qty:2,weight:null,destination:'埼玉',occurred_at:day(2)}];
      const base=qrSelect;qrSelect=async(t,q)=>{if(t==='qr_lot_movements')return T.qr_lot_movements.filter(m=>m.movement_type==='出庫');
        if(t==='qr_lots'){const ids=decodeURIComponent(String(q).match(/id=in\\.\\(([^)]*)\\)/)[1]).split(',');return T.qr_lots.filter(l=>ids.includes(l.id))}return base(t,q)};
      v1153BuyerOptimalItems=()=>[{id:'i1',name:'キャベツ'},{id:'i2',name:'人参'},{id:'i3',name:'白菜'}];
      v163LotKgAtQuantity=(l,q)=>l.pack_weight==='10kg'?10*q:0;}""")
    page.evaluate("()=>{currentScreen='home';document.getElementById('c134Daily')?.remove();document.querySelector('#app').insertAdjacentHTML('afterbegin','<div class=\"homeSummary\"></div>');c134ResetCache();return c134InjectBuyer()}")  # c151：アプリを開いたときの先読みの結果は使わない
    page.wait_for_selector("#c134DailyBtns button")
    texts = page.eval_on_selector_all("#c134DailyBtns button", "els=>els.map(e=>{let t=e.innerText;for(const x of e.querySelectorAll('.c147Add'))t=t.replace(x.innerText,'');return t.replace(/\\s+/g,' ').trim()})")  # c147 が書き足す「明日の予定」は除いて比べる
    self.assertEqual(texts, ["キャベツ 日量 60kg 出庫2日", "人参 日量 － 出庫1日・重さ不明1件", "白菜 出庫なし"])
    page.click("#c134DailyBtns button:has-text('キャベツ')")
    page.wait_for_selector("text=在庫・出庫の分析")


@_t
def test_hq_share_counts_honsha_and_oginuma_carrot_radish(self):
    # c151：本社への出庫は本社の分。荻沼（本社管轄の協力工場）への人参・大根も本社からの発注なので本社の分。玉葱は入れない
    page = self.open_app("buyer")
    by = page.evaluate("""async()=>{const now=Date.now(),day=k=>new Date(now-k*864e5).toISOString();
      const lots=[{id:'L1',item_name:'人参'},{id:'L2',item_name:'カット大根'},{id:'L3',item_name:'玉葱'},{id:'L4',item_name:'キャベツ'}];
      const moves=[
        {id:'a',lot_id:'L1',movement_type:'出庫',qty:1,weight:100,destination:'荻沼',occurred_at:day(1)},
        {id:'b',lot_id:'L1',movement_type:'出庫',qty:1,weight:40,destination:'現場作業',occurred_at:day(2)},
        {id:'c',lot_id:'L2',movement_type:'出庫',qty:1,weight:60,destination:'荻沼',occurred_at:day(1)},
        {id:'d',lot_id:'L3',movement_type:'出庫',qty:1,weight:70,destination:'荻沼',occurred_at:day(1)},
        {id:'e',lot_id:'L4',movement_type:'出庫',qty:1,weight:30,destination:'本社',occurred_at:day(1)}];
      qrSelect=async(t,q)=>t==='qr_lot_movements'?moves:t==='qr_lots'?lots:[];
      c134ResetCache();const r=(await c134Load()).by;const o={};for(const k in r)o[k]=[r[k].kg,r[k].hqKg,r[k].days.size];return o}""")
    self.assertEqual(by["人参"], [140, 100, 2])
    self.assertEqual(by["カット大根"], [60, 60, 1])
    self.assertEqual(by["玉葱"], [70, 0, 1])
    self.assertEqual(by["キャベツ"], [30, 30, 1])


@_t
def test_big_container_uses_slip_measured_kg_c158(self):
    # c158：大型容器（基）の出庫は伝票の実測kgを使う。伝票で直した実測 → 出庫画面の実測（operation_meta.slip.kg） → 出庫の重さ
    page = self.open_app("buyer")
    by = page.evaluate("""async()=>{const now=Date.now(),day=k=>new Date(now-k*864e5).toISOString();
      const lots=[{id:'L1',item_name:'キャベツ',unit:'基',container_type:'網コンテナ'},{id:'L2',item_name:'人参',unit:'ケース',container_type:'ダンボール'}];
      const moves=[
        {id:'a',lot_id:'L1',movement_type:'出庫',qty:4,weight:1625.75,destination:'深谷',occurred_at:day(1),operation_meta:{slip:{kg:1560}}},
        {id:'b',lot_id:'L1',movement_type:'出庫',qty:2,weight:777.25,destination:'埼玉',occurred_at:day(1),operation_meta:{slip:{kg:770}}},
        {id:'c',lot_id:'L1',movement_type:'出庫',qty:1,weight:388.6,destination:'深谷',occurred_at:day(2)},
        {id:'d',lot_id:'L2',movement_type:'出庫',qty:3,weight:60,destination:'深谷',occurred_at:day(1),operation_meta:{slip:{kg:999}}}];
      window.__adjq=[];
      qrSelect=async(t,q)=>{if(t==='qr_slip_adjust_v1199c86'){__adjq.push(q);return [{movement_id:'b',total_kg:766}]}return t==='qr_lot_movements'?moves:t==='qr_lots'?lots:[]};
      c134ResetCache();const r=(await c134Load()).by;return {cab:r['キャベツ'].kg,car:r['人参'].kg,q:__adjq.join('|')}}""")
    self.assertAlmostEqual(by["cab"], 1560 + 766 + 388.6, places=3)  # a＝出庫画面の実測、b＝伝票で直した実測、c＝実測なしは出庫の重さ
    self.assertEqual(by["car"], 60)  # ケースは出庫の重さのまま
    self.assertNotIn("d", by["q"].split("in.(")[1])  # 伝票の訂正はケースの出庫では読まない


@_t
def test_range_excel_splits_by_destination_and_can_pick_one(self):
    lots, moves, history = self.slip_data()
    page = self.open_app(lots=lots, moves=moves, history=history)
    page.evaluate("()=>c84SlipPage(ymdKey(new Date()))")
    page.wait_for_selector("#c84From")
    page.evaluate("""()=>{window.__wb=[];XLSX.writeFile=(wb,name)=>window.__wb.push({name,sheets:wb.SheetNames.map(n=>({n,rows:XLSX.utils.sheet_to_json(wb.Sheets[n],{header:1,defval:''})}))})}""")
    page.fill("#c84From", self.yday)
    page.fill("#c84To", self.today)
    page.click("button:has-text('明細をExcelで出力')")
    page.wait_for_function("()=>window.__wb.length===1")
    out = page.evaluate("()=>window.__wb[0]")
    self.assertEqual([s["n"] for s in out["sheets"]], ["本社工場", "埼玉", "深谷", "荻沼"])
    ogi = next(s for s in out["sheets"] if s["n"] == "荻沼")["rows"]
    self.assertEqual(ogi[2][:7], ["伝票の日付", "出庫先", "便", "区分", "品名", "単協・仕入先", "GAP"])
    body = [r for r in ogi[3:] if r and r[0] and r[0] != "合計"]
    self.assertEqual(sorted((r[2], r[4], r[6], r[10]) for r in body), [("原料便", "キャベツ", "JGAP", 30), ("配送便", "人参", "", 5), ("配送便", "人参", "", 10)])
    page.select_option("#c84XDest", "埼玉")
    page.click("button:has-text('明細をExcelで出力')")
    page.wait_for_function("()=>window.__wb.length===2")
    one = page.evaluate("()=>window.__wb[1]")
    self.assertEqual([s["n"] for s in one["sheets"]], ["埼玉"])
    self.assertIn("埼玉_", one["name"])


if __name__ == "__main__":
    unittest.main()
