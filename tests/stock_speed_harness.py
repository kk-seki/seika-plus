import functools
import json
import re
import threading
import time
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse, parse_qs, unquote

import asyncio

from playwright.async_api import async_playwright

ROOT = Path(__file__).resolve().parent.parent
DELAY = 0.3
RPC_DELAY = 1.5
N_LOTS = 2500
N_GRADE_LOTS = 130


class Quiet(SimpleHTTPRequestHandler):
    def log_message(self, *_a):
        pass


def make_lots():
    lots = []
    for i in range(N_LOTS):
        lots.append({"id": f"lot{i}", "qr_key": f"K{i:05d}", "lot_no": f"L{i}", "item_name": "キャベツ" if i % 2 else "人参", "item_id": "i1" if i % 2 else "i2", "pack_weight": "10", "unit": "ケース",
                     "storage_location": "第2冷蔵庫", "current_qty": 3, "received_qty": 5, "active": i % 3 != 0,
                     "container_type": "ダンボール", "unit_weight": 10, "created_at": "2026-10-01T00:00:00Z", "memo": ""})
    return lots


def run(url_root, label):
    lots = make_lots()
    grades = []
    for i in range(N_GRADE_LOTS):
        for g, (name) in enumerate(["L", "M"]):
            grades.append({"lot_id": f"lot{i}", "qr_key": f"K{i:05d}", "grade": name, "sort_order": g, "received_qty": 3, "current_qty": 2})
    log = []
    t0 = [0.0]

    async def handler(route):
        req = route.request
        u = urlparse(req.url)
        if u.netloc != urlparse(url_root).netloc and "supabase" not in u.netloc:
            return await route.abort()
        if "supabase" not in u.netloc:
            return await route.continue_()
        path = u.path.replace("/rest/v1/", "")
        q = parse_qs(u.query, keep_blank_values=True)
        start = time.time() - t0[0]
        body = []
        delay = DELAY
        status = 200
        if req.method != "GET" and not path.startswith("rpc/"):
            return await route.fulfill(status=200, body="[]", content_type="application/json")
        if path == "rpc/qr_lot_daily_state_v1211":
            delay = RPC_DELAY
            body = {"ok": True, "lots": [{"id": f"lot{i}", "from": "2026-10-01", "ch": [["2026-10-01", 5, "第2冷蔵庫", False]]} for i in range(0, N_LOTS, 3)]}
        elif path.startswith("rpc/"):
            body = {"ok": True}
        elif path == "qr_lots":
            sel = q.get("select", ["*"])[0]
            if sel == "synced_at":
                status = 400
                body = {"message": "column synced_at does not exist"}
            else:
                rows = lots
                if "active" in q and q["active"][0] == "eq.true":
                    rows = [r for r in rows if r["active"]]
                if "id" in q and q["id"][0].startswith("in."):
                    ids = set(q["id"][0][4:-1].split(","))
                    rows = [r for r in rows if r["id"] in ids]
                off = int(q.get("offset", ["0"])[0]); lim = int(q.get("limit", ["1000"])[0])
                body = rows[off:off + lim]
        elif path == "qr_lot_grades_v1300":
            off = int(q.get("offset", ["0"])[0]); lim = int(q.get("limit", ["1000"])[0])
            body = grades[off:off + lim]
        elif path == "qr_lot_movements":
            body = []
            if "lot_id" in q and q["lot_id"][0].startswith("in."):
                ids = q["lot_id"][0][4:-1].split(",")
                body = [{"id": f"m{i}", "lot_id": i, "qr_key": "", "movement_type": "入庫", "qty": 5, "created_at": "2026-10-01T00:00:00Z", "occurred_at": "2026-10-01T00:00:00Z", "location_after": "第2冷蔵庫"} for i in ids]
        else:
            body = []
        await asyncio.sleep(delay)
        log.append((round(start, 2), path.split("?")[0], q.get("lot_id", q.get("id", [""]))[0][:12], q.get("offset", [""])[0]))
        await route.fulfill(status=status, body=json.dumps(body), content_type="application/json", headers={"content-range": "0-0/1"})

    return handler, log, t0


FIXED_NOW = "2026-11-09T03:00:00Z"


async def amain(label):
    srv = ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(Quiet, directory=str(ROOT)))
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    url = f"http://127.0.0.1:{srv.server_port}/index.html"
    async with async_playwright() as p:
        b = await p.chromium.launch()
        c = await b.new_context(viewport={"width": 820, "height": 1180}, service_workers="block", timezone_id="Asia/Tokyo")
        handler, log, t0 = run(url, label)
        await c.route("**/*", handler)
        await c.clock.set_fixed_time(FIXED_NOW)
        pg = await c.new_page()
        pg.on("pageerror", lambda e: print("PAGEERR", e))
        await pg.goto(url, wait_until="load")
        await pg.wait_for_function("()=>typeof weeklyData==='function'&&typeof ymdKey==='function'")
        await pg.wait_for_timeout(1500)
        await pg.evaluate("""()=>{db.user='テスト';db.userId='hirata';db.role='admin';db.items=[{id:'i1',name:'キャベツ',pack:10,sort:1,active:true,room:'第2冷蔵庫'},{id:'i2',name:'人参',pack:10,sort:2,active:true,room:'第2冷蔵庫'}];authWriteSession({access_token:'x',refresh_token:'y',expires_at:9999999999,user:{id:'u'}});window.v1209ClearQrCache&&v1209ClearQrCache()}""")
        log.clear(); t0[0] = time.time()
        t = time.time()
        await pg.evaluate("async()=>{await weeklyData()}")
        total = time.time() - t
        logged = sorted(log)
        digest = await pg.evaluate("""async()=>{v1209ClearQrCache();const r=await qrInventoryKgByItemForRoomByDay('room2',v163DayKeys(14));
          const j=JSON.stringify(r,(k,v)=>Array.isArray(v)&&k==='unconvertible'?v.length:v);let h=0;for(const ch of j)h=(h*31+ch.charCodeAt(0))>>>0;
          return{hash:h,len:j.length,totals:Object.keys(r.totals||{}).length,standalone:Object.keys(r.standaloneTotals||{}).length,specs:Object.keys(r.specs||{}).length+Object.keys(r.standaloneSpecs||{}).length,days:(r.activeDayKeys||[]).length}}""")
        await b.close()
    srv.shutdown()
    return {"seconds": total, "log": logged, "digest": digest}


def measure(label="x"):
    return asyncio.run(amain(label))


def main(label):
    r = measure(label)
    print(label, "weeklyData秒:", round(r["seconds"], 2), "通信回数:", len(r["log"]))
    for row in r["log"]:
        print("  ", row)
    print("RESULT", r["digest"])


if __name__ == "__main__":
    import sys
    main(sys.argv[1] if len(sys.argv) > 1 else "x")
