"""c147：仕入れ担当者・営業担当者のホームの「出荷予定と確定」を、架空のデータで確かめる。
ホームの画面はページの中で小さく作り、js/31-c147-ship-home.js だけを読み込む（本番やクラウドには接続しない）。"""
import functools
import threading
import unittest
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parent.parent

SETUP = """role=>{
 window.db={role,userId:'U1'};window.currentScreen='home';
 window.esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 window.seikaEventAttrs=(e,a,args=[])=>`data-seika-${e}-action="${esc(a)}" data-seika-${e}-args="${esc(encodeURIComponent(JSON.stringify(args)))}"`;
 window.todayKey=()=>'2026-11-23';
 const add=(k,n)=>{const d=new Date(k+'T00:00:00Z');d.setUTCDate(d.getUTCDate()+n);return d.toISOString().slice(0,10)};
 const L=(customer,item,kg)=>({customer,item,kg});
 window.__plan={
  '2026-11-24':[L('A社','キャベツ',300),L('B社','キャベツ',100),L('A社','人参',90),L('A社','小松菜',40),L('埼玉','レタス',500)],
  '2026-11-23':[L('A社','キャベツ',200),L('A社','人参',100),L('A社','大葉',5),L('埼玉','レタス',400),L('A社','ほうれん草',100)],
 };
 window.__actual={'2026-11-23':[L('A社','キャベツ',260),L('A社','人参',105),L('A社','大葉',9),L('A社','トマト',40)]};
 window.c140Lib={addDays:add,canView:()=>true,sqlMissing:()=>false,
  loadPlan:async d=>{const ls=__plan[d];return {active:ls?{id:d}:null,lines:ls||[]}},
  loadActual:async d=>{const ls=__actual[d];return {active:ls?{id:d}:null,lines:ls||[]}}};
 window.v1153BuyerOptimalItems=()=>[{name:'キャベツ'},{name:'人参'},{name:'ほうれん草'},{name:'ごぼう'}];
 window.c134Load=async()=>({by:{'キャベツ':{kg:1200,days:new Set(['a','b','c','d'])},'人参':{kg:300,days:new Set(['a','b']),hqKg:60}}});
 document.getElementById('app').innerHTML='<main class="wrap"><div class="homeSummary">まとめ</div><div class="homePrimary"></div><div id="c134Daily"><div id="c134DailyBtns"><button class="c134Btn"><b>キャベツ</b><em>日量 300kg</em></button><button class="c134Btn"><b>ごぼう</b><em>出庫なし</em></button></div></div></main>';
}"""


class ShipHomeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        handler = type("Quiet", (SimpleHTTPRequestHandler,), {"log_message": lambda *args: None})
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(handler, directory=str(ROOT)))
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()
        cls.base = f"http://127.0.0.1:{cls.server.server_port}"
        cls.local = urlparse(cls.base).netloc
        cls.playwright = sync_playwright().start()
        cls.browser = cls.playwright.chromium.launch()

    @classmethod
    def tearDownClass(cls):
        cls.browser.close()
        cls.playwright.stop()
        cls.server.shutdown()
        cls.server.server_close()

    def open_home(self, role):
        context = self.browser.new_context(viewport={"width": 820, "height": 1180}, service_workers="block", timezone_id="Asia/Tokyo")
        self.addCleanup(context.close)
        context.route("**/*", lambda route: route.continue_() if urlparse(route.request.url).netloc == self.local else route.abort())
        page = context.new_page()
        errors = []
        page.on("pageerror", lambda err: errors.append(str(err)))
        self.addCleanup(lambda: self.assertEqual(errors, [], "browser errors"))
        page.set_content('<!doctype html><html><body><div id="app"></div></body></html>')
        page.evaluate(SETUP, role)
        page.add_script_tag(url=self.base + "/js/31-c147-ship-home.js")
        page.evaluate("()=>c147InjectHome()")
        return page

    def test_buyer_sees_my_items_with_daily_amount_and_big_differences(self):
        page = self.open_home("buyer")
        card = page.locator("#c147Ship")
        card.locator(".c147Sub").first.wait_for()
        text = card.inner_text()
        self.assertIn("（担当品目）", text)
        self.assertIn("明日（11/24納品）の出荷予定", text)
        # 担当品目だけ。キャベツ 400kg ÷ 日量300kg＝1.3倍（多い）、人参（90kg＋本社30kg）÷ 日量150kg＝0.8倍（少ない）
        self.assertIn("日量の1.3倍・多い", text)
        self.assertIn("日量の0.8倍・少ない", text)
        self.assertNotIn("小松菜", text)
        self.assertNotIn("レタス", text)
        self.assertIn("予定なし：ごぼう、ほうれん草", text)
        # 確定：キャベツ 200→260（+30%）は出す。人参 100→105（+5%）は2割未満なので出さない
        self.assertIn("11/23納品の確定と予定の違い（2割以上）", text)
        self.assertIn("+30%", text)
        self.assertNotIn("105kg", text)
        # ほうれん草は確定のある客先（A社）の予定にあり、確定にない → -100%
        self.assertIn("-100%", text)
        # 日量のボタンに明日の予定を書き足す
        page.locator("#c134DailyBtns .c147Add").first.wait_for()
        btns = page.locator("#c134DailyBtns").inner_text()
        self.assertIn("明日 400kg（1.3倍）", btns)
        self.assertIn("明日 予定なし", btns)
        # カードはホームの一番上（まとめの前）
        self.assertEqual(page.evaluate("()=>document.querySelector('main').firstElementChild.id"), "c147Ship")

    def test_sales_sees_all_items_and_differences(self):
        page = self.open_home("sales")
        card = page.locator("#c147Ship")
        card.locator(".c147Sub").first.wait_for()
        text = card.inner_text()
        self.assertNotIn("（担当品目）", text)
        self.assertNotIn("日量", text)
        for item in ("レタス", "キャベツ", "人参", "小松菜"):
            self.assertIn(item, text)
        # 埼玉は確定がない客先なので比べない（レタスは違いに出さない）。大葉は両方10kg以下なので出さない
        diff = card.locator(".c147Sec").nth(1).inner_text()
        self.assertNotIn("レタス", diff)
        self.assertNotIn("大葉", diff)
        self.assertIn("予定なし→確定あり", diff)  # トマト
        self.assertIn("キャベツ", diff)

    def test_other_roles_do_not_get_the_card(self):
        page = self.open_home("worker")
        page.wait_for_timeout(200)
        self.assertEqual(page.locator("#c147Ship").count(), 0)

    def test_no_actual_yet_and_no_plan(self):
        context = self.browser.new_context(service_workers="block")
        self.addCleanup(context.close)
        context.route("**/*", lambda route: route.continue_() if urlparse(route.request.url).netloc == self.local else route.abort())
        page = context.new_page()
        page.set_content('<!doctype html><html><body><div id="app"></div></body></html>')
        page.evaluate(SETUP, "sales")
        page.evaluate("()=>{__plan={};__actual={}}")
        page.add_script_tag(url=self.base + "/js/31-c147-ship-home.js")
        page.evaluate("()=>c147InjectHome()")
        page.locator("#c147Ship .c147Sub").first.wait_for()
        text = page.locator("#c147Ship").inner_text()
        self.assertIn("積み込み表はまだ取り込まれていません", text)
        self.assertIn("確定（産地報告書）はまだ取り込まれていません", text)

    def page_with(self, role, extra):
        context = self.browser.new_context(service_workers="block", timezone_id="Asia/Tokyo")
        self.addCleanup(context.close)
        context.route("**/*", lambda route: route.continue_() if urlparse(route.request.url).netloc == self.local else route.abort())
        page = context.new_page()
        page.set_content('<!doctype html><html><body><div id="app"></div></body></html>')
        page.evaluate(SETUP, role)
        page.evaluate(extra)
        page.add_script_tag(url=self.base + "/js/31-c147-ship-home.js")
        page.evaluate("()=>c147InjectHome()")
        page.locator("#c147Ship .c147Sub").first.wait_for()
        return page

    def test_actual_for_tomorrow_is_found_first(self):
        # c149：産地報告書は翌日の納品分。明日の確定がすでにあれば、それを比べる
        page = self.page_with("sales", "()=>{__actual['2026-11-24']=[{customer:'A社',item:'キャベツ',kg:150}]}")
        text = page.locator("#c147Ship").inner_text()
        self.assertIn("11/24納品の確定と予定の違い", text)
        self.assertIn("-50%", text)  # A社の予定 300kg → 確定 150kg
        self.assertIn("11/24の確定を開く", text)

    def test_buyer_without_items_sees_all_items(self):
        # c149：担当品目が1つもない仕入れ担当者は、何も出ないのではなく全品目を出す
        page = self.page_with("buyer", "()=>{window.v1153BuyerOptimalItems=()=>[]}")
        text = page.locator("#c147Ship").inner_text()
        self.assertIn("担当品目が未設定のため全品目", text)
        self.assertIn("レタス", text)
        self.assertNotIn("予定に担当品目はありません", text)

    def test_buyer_items_include_qr_items_from_the_buyer_list(self):
        # c149：人参はQRで管理する品目（適正在庫の担当品目ではない）。仕入れ担当者の一覧で荒木さんの品目なので入れる
        page = self.page_with("buyer", """()=>{db.userId='araki';window.v1153BuyerOptimalItems=()=>[];window.v1151CanonicalBuyerId=x=>x;
          window.qrAllowedItemNames=()=>['人参','キャベツ','小松菜'];
          window.v1144AutoPurchaseStaffForItemName=n=>n==='人参'?{legacy_user_id:'araki'}:{legacy_user_id:'saito_dai'}}""")
        self.assertEqual(page.evaluate("()=>c149BuyerItemNames()"), ["人参"])
        text = page.locator("#c147Ship").inner_text()
        self.assertIn("（担当品目）", text)
        self.assertIn("人参", text)
        self.assertNotIn("キャベツ", text.split("確定と予定の違い")[0])

    def test_card_comes_back_when_home_is_redrawn_while_loading(self):
        # c150：起動直後はホームが何度か描き直される。読み込み中に描き直されても、カードと日量ボタンの「明日」が出ること
        context = self.browser.new_context(service_workers="block", timezone_id="Asia/Tokyo")
        self.addCleanup(context.close)
        context.route("**/*", lambda route: route.continue_() if urlparse(route.request.url).netloc == self.local else route.abort())
        page = context.new_page()
        page.set_content('<!doctype html><html><body><div id="app"></div></body></html>')
        page.evaluate(SETUP, "buyer")
        page.evaluate("""()=>{const lp=c140Lib.loadPlan;c140Lib.loadPlan=async d=>{await new Promise(r=>setTimeout(r,300));return lp(d)};window.__home=document.getElementById('app').innerHTML}""")
        page.add_script_tag(url=self.base + "/js/31-c147-ship-home.js")
        page.evaluate("()=>{c147InjectHome()}")  # 待たずに次へ（読み込み中）
        page.wait_for_timeout(100)
        page.evaluate("()=>{document.getElementById('app').innerHTML=__home}")  # 読み込み中にホームを描き直す
        page.locator("#c147Ship .c147Sub").first.wait_for(timeout=5000)
        page.locator("#c134DailyBtns .c147Add").first.wait_for(timeout=5000)
        page.evaluate("()=>{document.getElementById('app').innerHTML=__home}")  # 読み込み済みのあとに描き直す
        page.locator("#c147Ship .c147Sub").first.wait_for(timeout=5000)
        page.locator("#c134DailyBtns .c147Add").first.wait_for(timeout=5000)
        self.assertEqual(page.locator("#c147Ship").count(), 1)

    def test_hq_share_from_shipping_history_is_added_to_tomorrow(self):
        # c151：本社は積み込み表に入らないので、本社への出庫（7日間 ÷ 出庫した日数）を明日の予定に足して日量と比べる
        page = self.open_home("buyer")
        page.locator("#c147Ship .c147Sub").first.wait_for()
        text = page.locator("#c147Ship").inner_text()
        # 人参：予定 90kg ＋ 本社 60kg÷2日＝30kg → 120kg、日量 150kg → 0.8倍（少ない）
        self.assertIn("＋本社 30kg", text)
        self.assertIn("＝120kg", text)
        self.assertIn("日量の0.8倍・少ない", text)
        self.assertIn("本社は積み込み表に入らないので", text)
        # キャベツは本社への出庫なし → 今までどおり 400kg ÷ 300kg
        self.assertIn("日量の1.3倍・多い", text)

    INHOUSE = """()=>{__plan['2026-11-23'].push({customer:'(株)せき 埼玉工場',item:'人参',kg:200},{customer:'(株)せき 深谷青果センター',item:'キャベツ',kg:100});
      __plan['2026-11-24'].push({customer:'(株)せき 埼玉工場',item:'人参',kg:50});
      window.__q=[];
      window.qrSelect=async(t,q)=>{__q.push([t,q]);if(t==='qr_lot_movements')return [
        {lot_id:'L1',qty:10,destination:'埼玉',movement_type:'出庫',occurred_at:'2026-11-22T01:00:00Z'},
        {lot_id:'L2',qty:3,destination:'深谷',movement_type:'出庫',occurred_at:'2026-11-22T02:00:00Z'},
        {lot_id:'L1',qty:5,destination:'埼玉',movement_type:'出庫',cancelled_at:'2026-11-22T03:00:00Z'}];
        if(t==='qr_lots')return [{id:'L1',item_name:'人参'},{id:'L2',item_name:'キャベツ'}];return []};
      window.v163LotKgAtQuantity=(l,q)=>q*10;window.qrResolveInventoryItem=l=>({item:{name:l.item_name}});}"""

    def test_inhouse_actual_comes_from_shipping_on_the_day_before(self):
        # c151：埼玉・深谷は、積み込み表の予定と、出荷日（納品日の前日）の出庫（QR）で比べる
        page = self.page_with("sales", self.INHOUSE)
        text = page.locator("#c147Ship").inner_text()
        q = page.evaluate("()=>__q.find(x=>x[0]==='qr_lot_movements')[1]")
        self.assertIn("2026-11-21T15%3A00%3A00.000Z", q)  # 11/22（日本時間）の0時から
        self.assertIn("destination=in.(%E5%9F%BC%E7%8E%89,%E6%B7%B1%E8%B0%B7)", q)
        # 人参：予定 A社100＋埼玉200＝300 → 確定 A社105＋埼玉100（10箱×10kg。取り消しは数えない）＝205
        self.assertIn("300kg → 205kg", text)
        self.assertIn("社外 100→105・埼玉 200→100", text)
        # キャベツ：予定 A社200＋深谷100＝300 → 確定 A社260＋深谷30＝290（2割未満なので出さない）
        diff = page.locator("#c147Ship .c147Sec").nth(1).inner_text()
        self.assertNotIn("キャベツ", diff)
        self.assertIn("埼玉・深谷は積み込み表の予定と、出荷日（納品日の前日）の出庫で比べます", text)
        # 明日の予定には埼玉・深谷も入っている
        self.assertIn("うち埼玉 50kg", text)

    def test_inhouse_shipped_a_day_early_is_not_shown_as_cancelled(self):
        # c154：翌日分を前の日に先送りしたとき。納品日11/23の人参（埼玉200kg）を、11/22分といっしょに11/21に出庫した。
        # 11/22（出荷日）の出庫には人参がないが、11/21の出庫のうち前日分（11/22の積み込み表 埼玉 人参100kg）を超えた200kgを足す
        extra = self.INHOUSE[:-1] + """
      __plan['2026-11-22']=[{customer:'(株)せき 埼玉工場',item:'人参',kg:100}];
      window.qrSelect=async(t,q)=>{__q.push([t,q]);if(t==='qr_lot_movements'){
        if(q.includes(encodeURIComponent('2026-11-20T15')))return [{lot_id:'L1',qty:30,destination:'埼玉',movement_type:'出庫'}];
        if(q.includes(encodeURIComponent('2026-11-21T15')))return [{lot_id:'L2',qty:3,destination:'深谷',movement_type:'出庫'}];
        return []}
        if(t==='qr_lots')return [{id:'L1',item_name:'人参'},{id:'L2',item_name:'キャベツ'}];return []};}"""
        page = self.page_with("sales", extra)
        text = page.locator("#c147Ship").inner_text()
        # 人参：予定 A社100＋埼玉200＝300 → 確定 A社105＋埼玉200（先送り分）＝305 → 2割未満なので違いに出ない
        diff = page.locator("#c147Ship .c147Sec").nth(1).inner_text()
        self.assertNotIn("人参", diff)
        self.assertIn("先送りした出庫も足します", text)
        merged = page.evaluate("""()=>{const r=c154AheadMerge({'埼玉':new Map([['人参',50]]),'深谷':new Map()},{'埼玉':new Map([['人参',300],['レタス',80]]),'深谷':new Map()},[{customer:'(株)せき 埼玉工場',item:'人参',kg:100},{customer:'(株)せき 埼玉工場',item:'レタス',kg:80}]);
          return [r['埼玉'].get('人参'),r['埼玉'].get('レタス')||0,r.ahead['埼玉'].get('人参')]}""")
        self.assertEqual(merged, [250, 0, 200])
        # 前日分の積み込み表がないときは足さない
        none = page.evaluate("()=>c154AheadMerge({'埼玉':new Map([['人参',50]])},{'埼玉':new Map([['人参',300]])},null)['埼玉'].get('人参')")
        self.assertEqual(none, 50)

    def test_card_shows_at_once_when_already_loaded(self):
        # c151：アプリを開いたときに先に読んでおけば、「読み込んでいます」を出さずに一度で出る
        context = self.browser.new_context(service_workers="block", timezone_id="Asia/Tokyo")
        self.addCleanup(context.close)
        context.route("**/*", lambda route: route.continue_() if urlparse(route.request.url).netloc == self.local else route.abort())
        page = context.new_page()
        page.set_content('<!doctype html><html><body><div id="app"></div></body></html>')
        page.evaluate(SETUP, "sales")
        page.add_script_tag(url=self.base + "/js/31-c147-ship-home.js")
        page.wait_for_function("()=>window.c147Load")
        page.evaluate("async()=>{await c147Load();document.getElementById('c147Ship')?.remove();window.__seen=[];new MutationObserver(()=>{const c=document.getElementById('c147Ship');if(c)__seen.push(c.innerText)}).observe(document.body,{childList:true,subtree:true,characterData:true})}")
        page.evaluate("()=>c147InjectHome()")
        page.locator("#c147Ship .c147Sub").first.wait_for()
        seen = page.evaluate("()=>__seen")
        self.assertTrue(seen)
        self.assertFalse(any("読み込んでいます" in t for t in seen), seen)

if __name__ == "__main__":
    unittest.main()
