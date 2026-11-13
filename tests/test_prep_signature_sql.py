"""c121 入力者サインを019〜048のローカル使い捨てPostgreSQLで検証する。"""
import base64
import hashlib
import json
import struct
import unittest
import zlib
from pathlib import Path

import test_prep_flow_sql as prep_flow_sql
from test_prep_work_sql import ADMIN, OTHER, PREP, WORKER, STAFF_1, STAFF_2

ROOT = Path(__file__).resolve().parents[1]
SQL_048 = ROOT / "db" / "048_本社下処理_入力者サイン.sql"


def png_chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)


def signature_png():
    """600px白地に黒線を描いた、200KB未満で十分な大きさのPNG。"""
    width, height = 600, 200
    rows = []
    for y in range(height):
        row = bytearray(b"\xff\xff\xff" * width)
        x = 30 + y * 2
        for dx in range(-3, 4):
            if 0 <= x + dx < width:
                row[(x + dx) * 3:(x + dx + 1) * 3] = b"\x00\x00\x00"
        rows.append(b"\x00" + bytes(row))
    raw = b"".join(rows)
    data = b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    data += png_chunk(b"IDAT", zlib.compress(raw, 9)) + png_chunk(b"IEND", b"")
    assert 256 <= len(data) <= 204800
    return "data:image/png;base64," + base64.b64encode(data).decode()


SIGNATURE = signature_png()
EMPTY_PNG = "data:image/png;base64," + base64.b64encode(
    b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", struct.pack(">IIBBBBB", 600, 200, 8, 2, 0, 0, 0))
    + png_chunk(b"IDAT", zlib.compress((b"\x00" + b"\xff\xff\xff" * 600) * 200, 9)) + png_chunk(b"IEND", b"")
).decode()
assert 512 <= len(base64.b64decode(EMPTY_PNG.split(",", 1)[1])) < 700



class PrepSignatureSqlTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # 既存047テストと同じ019〜047 fixtureを再利用し、048だけを追加する。
        prep_flow_sql.PrepC120FlowSqlTests.setUpClass()
        cls.pg = prep_flow_sql.PrepC120FlowSqlTests.pg
        cls.pg.file(SQL_048)
        cls.pg.file(SQL_048)  # 再適用は既存データを変更せず成功する。

    @classmethod
    def tearDownClass(cls):
        prep_flow_sql.PrepC120FlowSqlTests.doClassCleanups()

    def sql(self, statement, tuples=False):
        return self.pg.sql(statement, tuples)

    def call(self, role, function, *args):
        rendered = ",".join(args)
        output = self.sql(f"set app.\"user\" = '{role}'; select {function}({rendered});", True)
        return json.loads(output.splitlines()[-1])

    def assert_denied(self, role, function, *args):
        with self.assertRaises(AssertionError):
            self.call(role, function, *args)

    def reset(self):
        self.sql("truncate public.hq_prep_signatures_v1199c121;")
        prep_flow_sql.PrepC120FlowSqlTests.reset(self)

    def saved_work(self, seed):
        base = int(seed) * 100
        operation = lambda n: f"61000000-0000-0000-0000-{base + n:012d}"
        started_at = f"now()-interval '8 hours' + interval '{seed * 20} minutes'"
        ended_at = f"now()-interval '8 hours' + interval '{seed * 20 + 10} minutes'"
        started = self.call(
            PREP, "public.hq_prep_start_v1199c120", f"'{operation(1)}'::uuid", "'下処理室①'",
            "array['10000000-0000-0000-0000-000000000001'::uuid]",
            "array['30000000-0000-0000-0000-000000000001'::uuid]", started_at,
            "jsonb_build_array(jsonb_build_object('master_id','20000000-0000-0000-0000-000000000001','custom',false,'name','皮むき人参'))",
        )
        ended = self.call(
            PREP, "public.hq_prep_end_v1199c120", f"'{started['id']}'::uuid", f"'{operation(2)}'::uuid",
            f"'{started['updated_at']}'::timestamptz", ended_at,
        )
        report = prep_flow_sql.PrepC120FlowSqlTests.report_payload(
            self, qty=10, expected=20, started=started_at, ended=ended_at,
            work_date="(now() at time zone 'Asia/Tokyo')::date::text",
        )
        saved = self.call(
            PREP, "public.hq_prep_report_save_v1199c120", f"'{started['id']}'::uuid", f"'{operation(3)}'::uuid",
            f"'{ended['updated_at']}'::timestamptz", report,
        )
        self.assertTrue(saved["ok"])
        return saved

    def submit121(self, role, work, operation, signer="null", image="null"):
        return self.call(
            role, "public.hq_prep_submit_v1199c121", f"'{work['id']}'::uuid", f"'{operation}'::uuid",
            f"'{work['updated_at']}'::timestamptz", signer, image,
        )

    @staticmethod
    def image_sql(image):
        return "'%s'" % image.replace("'", "''")

    def test_prep_rejects_missing_invalid_empty_large_and_non_active_staff(self):
        self.reset()
        work = self.saved_work(1)
        staff = f"'{STAFF_1}'::uuid"
        for number, signer, image in (
            (4, "null", "null"), (5, staff, "null"), (6, "null", self.image_sql(SIGNATURE)),
            (7, staff, "'data:image/png;base64,AAAA'"), (8, staff, self.image_sql(EMPTY_PNG)),
            (9, staff, "'data:image/png;base64,' || repeat('A',273100)"),
            (10, "'30000000-0000-0000-0000-000000000099'::uuid", self.image_sql(SIGNATURE)),
        ):
            self.assert_denied(PREP, "public.hq_prep_submit_v1199c121", f"'{work['id']}'::uuid",
                               f"'61000000-0000-0000-0000-000000000{number:03d}'::uuid",
                               f"'{work['updated_at']}'::timestamptz", signer, image)
        self.sql(f"update public.hq_staff_v1500 set deleted_at=now() where id='{STAFF_1}'")
        self.assert_denied(PREP, "public.hq_prep_submit_v1199c121", f"'{work['id']}'::uuid",
                           "'61000000-0000-0000-0000-000000000011'::uuid", f"'{work['updated_at']}'::timestamptz",
                           staff, self.image_sql(SIGNATURE))

    def test_valid_submit_audits_hash_and_idempotency_without_image_payload(self):
        self.reset()
        work = self.saved_work(2)
        hash_before = self.sql(f"select md5(public.hq_c120_work_snapshot('{work['id']}'::uuid)::text)", True)
        operation = "61000000-0000-0000-0000-000000000204"
        result = self.submit121(PREP, work, operation, f"'{STAFF_1}'::uuid", self.image_sql(SIGNATURE))
        self.assertTrue(result["ok"])
        self.assertEqual(result["signer_name"], "作業者1")
        self.assertEqual(self.sql("select count(*) from public.hq_prep_signatures_v1199c121", True), "1")
        row = self.sql("select signer_name||'|'||content_hash||'|'||signature_md5 from public.hq_prep_signatures_v1199c121", True)
        self.assertEqual(row.split("|")[0:2], ["作業者1", hash_before])
        self.assertEqual(row.split("|")[2], hashlib.md5(base64.b64decode(SIGNATURE.split(",", 1)[1])).hexdigest())
        history = self.sql(f"select history::text from public.hq_works_v1500 where id='{work['id']}'", True)
        self.assertIn("入力者サイン付き・社員確認待ち", history)
        self.assertIn(hash_before, history)
        self.assertNotIn(SIGNATURE, history)
        payload = self.sql(f"select payload::text from public.hq_prep_operations_v1199c120 where operation_id='{operation}'", True)
        self.assertIn("signature_md5", payload)
        self.assertNotIn(SIGNATURE, payload)
        replay = self.submit121(PREP, work, operation, f"'{STAFF_1}'::uuid", self.image_sql(SIGNATURE))
        self.assertTrue(replay["already"])
        self.assertEqual(self.sql("select count(*) from public.hq_prep_signatures_v1199c121", True), "1")
        conflict = self.submit121(PREP, work, operation, f"'{STAFF_2}'::uuid", self.image_sql(SIGNATURE))
        self.assertTrue(conflict["idempotency_conflict"])

    @staticmethod
    def browser_png():
        from playwright.sync_api import sync_playwright
        script = """()=>{const out=document.createElement('canvas');out.width=600;out.height=220;const ctx=out.getContext('2d');ctx.fillStyle='#fff';ctx.fillRect(0,0,600,220);ctx.strokeStyle='#111';ctx.lineWidth=3;ctx.lineCap='round';ctx.lineJoin='round';ctx.beginPath();ctx.moveTo(60,120);for(let i=1;i<50;i++)ctx.lineTo(60+i*8,110+30*Math.sin(i/2));ctx.stroke();return out.toDataURL('image/png')}"""
        with sync_playwright() as p:
            browser = p.chromium.launch()
            try:
                page = browser.new_page()
                page.set_content("<html></html>")
                return page.evaluate(script)
            finally:
                browser.close()

    def test_png_made_by_the_real_browser_is_accepted(self):
        self.reset()
        work = self.saved_work(3)
        image = self.browser_png()
        self.assertTrue(image.startswith("data:image/png;base64,"))
        result = self.submit121(PREP, work, "61000000-0000-0000-0000-000000000304", f"'{STAFF_1}'::uuid", self.image_sql(image))
        self.assertTrue(result["ok"])
        self.assertEqual(self.sql(f"select count(*) from public.hq_prep_signatures_v1199c121 where work_id='{work['id']}'", True), "1")

    def test_old_submit_prep_is_rejected_but_admin_and_worker_remain_compatible(self):
        self.reset()
        prep_work = self.saved_work(3)
        self.assert_denied(PREP, "public.hq_prep_submit_v1199c120", f"'{prep_work['id']}'::uuid",
                           "'61000000-0000-0000-0000-000000000304'::uuid", f"'{prep_work['updated_at']}'::timestamptz")
        for role, seed, operation in ((ADMIN, 4, "61000000-0000-0000-0000-000000000404"),
                                      (WORKER, 5, "61000000-0000-0000-0000-000000000504")):
            self.reset()
            work = self.saved_work(seed)
            result = self.call(role, "public.hq_prep_submit_v1199c120", f"'{work['id']}'::uuid", f"'{operation}'::uuid", f"'{work['updated_at']}'::timestamptz")
            self.assertTrue(result["ok"])
            self.assertIsNone(result["signature_id"])

    def test_employee_optional_signature_pair_and_return_requires_a_new_signature(self):
        self.reset()
        unsigned = self.saved_work(6)
        result = self.submit121(ADMIN, unsigned, "61000000-0000-0000-0000-000000000604")
        self.assertTrue(result["ok"])
        self.assertIsNone(result["signature_id"])
        for seed, role in ((7, ADMIN), (8, WORKER)):
            self.reset()
            work = self.saved_work(seed)
            self.assert_denied(role, "public.hq_prep_submit_v1199c121", f"'{work['id']}'::uuid",
                               f"'61000000-0000-0000-0000-000000000{seed}04'::uuid", f"'{work['updated_at']}'::timestamptz",
                               f"'{STAFF_1}'::uuid", "null")
            saved = self.submit121(role, work, f"61000000-0000-0000-0000-000000000{seed}05", f"'{STAFF_1}'::uuid", self.image_sql(SIGNATURE))
            self.assertTrue(saved["ok"])
            self.assertEqual(self.sql(f"select count(*) from public.hq_prep_signatures_v1199c121 where work_id='{work['id']}'", True), "1")
        self.reset()
        signed = self.saved_work(9)
        first = self.submit121(ADMIN, signed, "61000000-0000-0000-0000-000000000904", f"'{STAFF_1}'::uuid", self.image_sql(SIGNATURE))
        self.assertTrue(first["ok"])
        returned = self.call(ADMIN, "public.hq_prep_return_v1199c120", f"'{signed['id']}'::uuid",
                             "'61000000-0000-0000-0000-000000000905'::uuid", f"'{first['updated_at']}'::timestamptz", "'再確認'")
        self.assert_denied(PREP, "public.hq_prep_submit_v1199c121", f"'{signed['id']}'::uuid",
                           "'61000000-0000-0000-0000-000000000906'::uuid", f"'{returned['updated_at']}'::timestamptz", "null", "null")
        second = self.submit121(PREP, {"id": signed["id"], "updated_at": returned["updated_at"]},
                                "61000000-0000-0000-0000-000000000907", f"'{STAFF_2}'::uuid", self.image_sql(SIGNATURE))
        self.assertTrue(second["ok"])
        self.assertEqual(self.sql(f"select count(*) from public.hq_prep_signatures_v1199c121 where work_id='{signed['id']}'", True), "2")

    def test_signature_list_acl_direct_table_denial_and_reapply_checks(self):
        self.reset()
        work = self.saved_work(10)
        first = self.submit121(PREP, work, "61000000-0000-0000-0000-000000001004", f"'{STAFF_1}'::uuid", self.image_sql(SIGNATURE))
        returned = self.call(ADMIN, "public.hq_prep_return_v1199c120", f"'{work['id']}'::uuid",
                             "'61000000-0000-0000-0000-000000001005'::uuid", f"'{first['updated_at']}'::timestamptz", "'再確認'")
        self.sql("select pg_sleep(0.01)")
        self.submit121(PREP, {"id": work["id"], "updated_at": returned["updated_at"]},
                       "61000000-0000-0000-0000-000000001006", f"'{STAFF_2}'::uuid", self.image_sql(SIGNATURE))
        listed = self.call(PREP, "public.hq_prep_signatures_v1199c121", f"'{work['id']}'::uuid")
        self.assertEqual([row["signer_name"] for row in listed], ["作業者2", "作業者1"])
        self.assert_denied(OTHER, "public.hq_prep_signatures_v1199c121", f"'{work['id']}'::uuid")
        for statement in (
            "select count(*) from public.hq_prep_signatures_v1199c121",
            "insert into public.hq_prep_signatures_v1199c121(id,work_id,operation_id,signer_staff_id,signer_name,signature_png,signature_md5,content_hash,signed_by_profile_id,signed_by_account_name,submitted_updated_at) values(gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),'x','x','x','x',gen_random_uuid(),'x',now())",
            "update public.hq_prep_signatures_v1199c121 set signer_name='x'",
        ):
            with self.assertRaises(AssertionError):
                self.sql(f"set role authenticated; set app.\"user\" = '{PREP}'; {statement}")
        self.assertEqual(self.sql("select count(*) from public.hq_prep_signatures_v1199c121", True), "2")
        count_before = self.sql("select count(*) from public.hq_prep_signatures_v1199c121", True)
        checks = self.pg.file(SQL_048).splitlines()
        self.assertEqual(self.sql("select count(*) from public.hq_prep_signatures_v1199c121", True), count_before)
        self.assertEqual([line.split("|")[-1].strip() for line in checks if "|" in line][-5:], ["OK"] * 5)


if __name__ == "__main__":
    unittest.main()
