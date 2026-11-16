"""c124 削除・休憩追加・作業時刻を019〜051のローカル使い捨てPostgreSQLで検証する。"""
import json
import unittest
from pathlib import Path

import test_prep_box_sql as prep_box_sql
from test_prep_work_sql import ADMIN, WORKER, PREP, OTHER, LOT_1, MASTER_1, STAFF_1, STAFF_2, STAFF_3

ROOT = Path(__file__).resolve().parents[1]
SQL_051 = ROOT / "db" / "051_本社下処理_削除と休憩の追加と作業時刻の修正.sql"


class PrepEditSqlTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        prep_box_sql.PrepBoxSqlTests.setUpClass()
        cls.pg = prep_box_sql.PrepBoxSqlTests.pg
        cls.pg.file(SQL_051)
        cls.pg.file(SQL_051)

    @classmethod
    def tearDownClass(cls):
        prep_box_sql.PrepBoxSqlTests.doClassCleanups()

    def sql(self, statement, tuples=False):
        return self.pg.sql(statement, tuples)

    def call(self, role, function, *args):
        out = self.sql(f"set app.\"user\"='{role}'; select {function}({','.join(args)});", True)
        return json.loads(out.splitlines()[-1])

    def denied(self, role, function, *args):
        with self.assertRaises(AssertionError):
            self.call(role, function, *args)

    def reset(self):
        prep_box_sql.PrepBoxSqlTests.reset(self)
        self.sql("truncate public.hq_deleted_works_v1500, public.hq_prep_signatures_v1199c121, public.hq_prep_legacy_archives_v1199c120 restart identity cascade")

    def start(self, op, staff=STAFF_1):
        return self.call(ADMIN, "public.hq_work_start_v1199c116", f"'{op}'::uuid", "'下処理'", "null", "'下処理室①'", f"array['{MASTER_1}'::uuid]", f"array['{LOT_1}'::uuid]", f"array['{staff}'::uuid]")["id"]

    def add_member(self, work, staff):
        return self.call(ADMIN, "public.hq_work_join_v1500", f"'{work}'::uuid", f"array['{staff}'::uuid]")

    def set_c120(self, work, review, confirm='未確定', stock=False):
        self.sql(f"update public.hq_works_v1500 set c120_flow=true,review_status='{review}',confirm_status='{confirm}',stock_applied={'true' if stock else 'false'} where id='{work}'")

    def test_schema_acl_and_delete_permissions_with_c120_finality(self):
        self.assertEqual(self.sql("select to_regprocedure('public.hq_work_delete_v1199c124(uuid)') is not null", True), "t")
        self.assertEqual(self.sql("select has_function_privilege('anon','public.hq_work_delete_v1199c124(uuid)','execute')", True), "f")
        self.assertEqual(self.sql("select has_function_privilege('authenticated','public.hq_c124_delete_work_core(uuid,public.profiles)','execute')", True), "f")
        # c120 submitted/returned are pre-final even with a previous confirm_status=確定.
        for review in ('draft', 'submitted', 'returned'):
            self.reset(); work = self.start(f"81000000-0000-0000-0000-0000000000{10 + ('draft','submitted','returned').index(review)}")
            self.set_c120(work, review, '確定')
            self.assertTrue(self.call(PREP, "public.hq_work_delete_v1199c124", f"'{work}'::uuid")["ok"])
        self.reset(); work = self.start("81000000-0000-0000-0000-000000000020"); self.set_c120(work, 'confirmed', '確定')
        self.denied(PREP, "public.hq_work_delete_v1199c124", f"'{work}'::uuid")
        self.assertTrue(self.call(WORKER, "public.hq_work_delete_v1199c124", f"'{work}'::uuid")["ok"])
        self.reset(); work = self.start("81000000-0000-0000-0000-000000000021")
        self.sql(f"update public.hq_works_v1500 set stock_applied=true where id='{work}'")
        self.denied(PREP, "public.hq_work_delete_v1199c124", f"'{work}'::uuid")
        self.reset(); work = self.start("81000000-0000-0000-0000-000000000022")
        self.sql(f"update public.hq_works_v1500 set kind='作業' where id='{work}'")
        self.denied(PREP, "public.hq_work_delete_v1199c124", f"'{work}'::uuid")
        self.assertTrue(self.call(ADMIN, "public.hq_work_delete_v1199c124", f"'{work}'::uuid")["ok"])

    def test_delete_cascades_pause_pallet_signature_and_members(self):
        self.reset(); work = self.start("81000000-0000-0000-0000-000000000030", STAFF_1)
        p = self.call(PREP, "public.hq_work_pause_v1199c116", f"'{work}'::uuid", "'81000000-0000-0000-0000-000000000031'::uuid", "'休憩'", "'{}'::uuid[]")
        self.sql(f"insert into public.hq_prep_signatures_v1199c121(id,work_id,operation_id,signer_staff_id,signer_name,signature_png,signature_md5,content_hash,signed_by_profile_id,signed_by_account_name,submitted_updated_at) values(gen_random_uuid(),'{work}','81000000-0000-0000-0000-000000000032','{STAFF_1}','作業者1','x','x','x','{ADMIN}','管理者',now())")
        self.sql(f"insert into public.hq_work_material_units_v1199c122(work_id,material_id,lot_id,unit_total,mode,used_qty,remaining_qty,operation_id) select '{work}',id,lot_id,1,'半端',0,1,'81000000-0000-0000-0000-000000000033' from public.hq_work_materials_v1500 where work_id='{work}'")
        self.assertTrue(self.call(PREP, "public.hq_work_delete_v1199c124", f"'{work}'::uuid")["ok"])
        for table in ('hq_works_v1500','hq_work_members_v1500','hq_work_pauses_v1199c116','hq_prep_signatures_v1199c121','hq_work_material_units_v1199c122'):
            self.assertEqual(self.sql(f"select count(*) from public.{table} where {'id' if table=='hq_works_v1500' else 'work_id'}='{work}'", True), "0", table)
        self.assertEqual(self.sql(f"select count(*) from public.hq_deleted_works_v1500 where work_id='{work}'", True), "1")

    def test_pause_add_validation_idempotency_and_all_staff_pause(self):
        self.reset(); work = self.start("81000000-0000-0000-0000-000000000040", STAFF_1); self.add_member(work, STAFF_2)
        args = (f"'{work}'::uuid", "'81000000-0000-0000-0000-000000000041'::uuid", f"array['{STAFF_2}'::uuid]", "now()-interval '1 minute'")
        self.sql(f"update public.hq_work_members_v1500 set start_at=now()-interval '2 minutes' where work_id='{work}'")
        got = self.call(PREP, "public.hq_work_pause_add_v1199c124", *args)
        self.assertTrue(got["ok"])
        replay_args = args[:-1] + (f"'{got['start_at']}'::timestamptz",)
        self.assertTrue(self.call(PREP, "public.hq_work_pause_add_v1199c124", *replay_args)["already"])
        self.denied(PREP, "public.hq_work_pause_add_v1199c124", f"'{work}'::uuid", "'81000000-0000-0000-0000-000000000041'::uuid", f"array['{STAFF_1}'::uuid]", "now()-interval '1 minute'")
        self.denied(PREP, "public.hq_work_pause_add_v1199c124", f"'{work}'::uuid", "'81000000-0000-0000-0000-000000000042'::uuid", f"array['{STAFF_3}'::uuid]", "now()")
        self.denied(PREP, "public.hq_work_pause_add_v1199c124", f"'{work}'::uuid", "'81000000-0000-0000-0000-000000000043'::uuid", f"array['{STAFF_1}'::uuid]", "(select min(start_at)-interval '1 second' from public.hq_work_members_v1500 where work_id='%s' and staff_id='%s')" % (work, STAFF_1))
        self.assertTrue(self.call(PREP, "public.hq_work_pause_add_v1199c124", f"'{work}'::uuid", "'81000000-0000-0000-0000-000000000044'::uuid", f"array['{STAFF_1}'::uuid]", "now()")["ok"])
        self.assertEqual(self.sql(f"select count(*) from public.hq_work_members_v1500 where work_id='{work}' and end_at is null", True), "0")
        self.assertEqual(self.sql(f"select pause_kind from public.hq_works_v1500 where id='{work}'", True), "休憩")
        self.reset(); work=self.start("81000000-0000-0000-0000-000000000045")
        self.call(PREP, "public.hq_work_pause_v1199c116", f"'{work}'::uuid", "'81000000-0000-0000-0000-000000000046'::uuid", "'中断'", "'{}'::uuid[]")
        self.denied(PREP, "public.hq_work_pause_add_v1199c124", f"'{work}'::uuid", "'81000000-0000-0000-0000-000000000047'::uuid", f"array['{STAFF_1}'::uuid]", "now()")

    def test_resume_spans_multiple_pauses_partial_busy_and_end_guard(self):
        self.reset(); work=self.start("81000000-0000-0000-0000-000000000050", STAFF_1); self.add_member(work, STAFF_2)
        self.sql(f"update public.hq_work_members_v1500 set start_at=now()-interval '10 minutes' where work_id='{work}'")
        self.call(PREP, "public.hq_work_pause_add_v1199c124", f"'{work}'::uuid", "'81000000-0000-0000-0000-000000000051'::uuid", f"array['{STAFF_1}'::uuid]", "now()-interval '5 minutes'")
        self.call(PREP, "public.hq_work_pause_add_v1199c124", f"'{work}'::uuid", "'81000000-0000-0000-0000-000000000052'::uuid", f"array['{STAFF_2}'::uuid]", "now()-interval '4 minutes'")
        r = self.call(WORKER, "public.hq_work_resume_v1199c124", f"'{work}'::uuid", "'81000000-0000-0000-0000-000000000053'::uuid", f"array['{STAFF_1}'::uuid]", "now()-interval '2 minutes'")
        self.assertTrue(r["ok"]); self.assertEqual(self.sql(f"select pause_kind from public.hq_works_v1500 where id='{work}'", True), "休憩")
        self.denied(PREP, "public.hq_work_resume_v1199c124", f"'{work}'::uuid", "'81000000-0000-0000-0000-000000000054'::uuid", f"array['{STAFF_1}'::uuid]", "now()")
        self.denied(PREP, "public.hq_work_end_v1500", f"'{work}'::uuid")
        self.assertTrue(self.call(PREP, "public.hq_work_resume_v1199c124", f"'{work}'::uuid", "'81000000-0000-0000-0000-000000000055'::uuid", f"array['{STAFF_2}'::uuid]", "now()-interval '1 minute'")["ok"])
        # c116の後入力休憩も、c124の複数pauseをまたぐ再開時刻を重複として扱う。
        self.denied(PREP, "public.hq_work_break_add_v1199c116", f"'{work}'::uuid", "'81000000-0000-0000-0000-000000000056'::uuid", "now()-interval '4 minutes'", "now()-interval '3 minutes'", "'{}'::uuid[]")
        self.assertEqual(self.sql(f"select pause_kind from public.hq_works_v1500 where id='{work}'", True), "")
        self.assertTrue(self.call(PREP, "public.hq_work_end_v1500", f"'{work}'::uuid")["ok"])

    def test_leave_and_member_time_fix_permissions_overlap_pause_and_c120(self):
        self.reset(); work=self.start("81000000-0000-0000-0000-000000000060")
        self.sql(f"update public.hq_work_members_v1500 set start_at=now()-interval '2 hours' where work_id='{work}'")
        member=self.sql(f"select id from public.hq_work_members_v1500 where work_id='{work}'", True)
        before=self.sql(f"select updated_at from public.hq_works_v1500 where id='{work}'", True)
        left=self.call(PREP,"public.hq_work_leave_v1199c124",f"'{work}'::uuid",f"'{STAFF_1}'::uuid","now()-interval '1 minute'")
        self.assertTrue(left["ok"]); self.denied(PREP,"public.hq_work_leave_v1199c124",f"'{work}'::uuid",f"'{STAFF_1}'::uuid","now()-interval '3 hours'")
        self.assertGreater(self.sql(f"select updated_at from public.hq_works_v1500 where id='{work}'",True),before)
        self.assertTrue(self.call(WORKER,"public.hq_work_member_time_fix_v1199c124",f"'{member}'::uuid","now()-interval '90 minutes'","now()-interval '30 seconds'")["ok"])
        fixed = self.sql(f"select start_at::text||'|'||end_at::text from public.hq_work_members_v1500 where id='{member}'", True).split('|')
        self.assertTrue(self.call(ADMIN,"public.hq_work_member_time_fix_v1199c124",f"'{member}'::uuid",f"'{fixed[0]}'::timestamptz",f"'{fixed[1]}'::timestamptz")["unchanged"])
        self.denied(OTHER,"public.hq_work_member_time_fix_v1199c124",f"'{member}'::uuid","now()-interval '90 minutes'","now()-interval '30 seconds'")
        other=self.start("81000000-0000-0000-0000-000000000061",STAFF_2); self.sql(f"update public.hq_work_members_v1500 set start_at=now()-interval '2 hours' where work_id='{other}'"); self.call(ADMIN,"public.hq_work_leave_v1199c124",f"'{other}'::uuid",f"'{STAFF_2}'::uuid","now()-interval '1 minute'")
        other_member=self.sql(f"select id from public.hq_work_members_v1500 where work_id='{other}'",True)
        self.denied(PREP,"public.hq_work_member_time_fix_v1199c124",f"'{other_member}'::uuid","now()-interval '2 minutes'","now()+interval '2 minutes'")
        self.set_c120(work,'confirmed','確定'); self.denied(PREP,"public.hq_work_member_time_fix_v1199c124",f"'{member}'::uuid","now()-interval '90 minutes'","now()-interval '30 seconds'")
        self.reset(); work=self.start("81000000-0000-0000-0000-000000000062"); member=self.sql(f"select id from public.hq_work_members_v1500 where work_id='{work}'",True)
        self.call(PREP,"public.hq_work_pause_v1199c116",f"'{work}'::uuid","'81000000-0000-0000-0000-000000000063'::uuid","'休憩'","'{}'::uuid[]")
        self.denied(PREP,"public.hq_work_member_time_fix_v1199c124",f"'{member}'::uuid","now()-interval '2 minutes'","now()-interval '1 minute'")


if __name__ == "__main__":
    unittest.main()
