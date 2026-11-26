"""c169 下処理：休憩・中断からの「再開」を取り消す（SQL 072）を、019〜051・059・072の使い捨てPostgreSQLで確かめる。"""
import json
import unittest
from pathlib import Path

import test_prep_edit_sql as prep_edit_sql
from test_prep_work_sql import ADMIN, WORKER, PREP, OTHER, STAFF_1, STAFF_2

ROOT = Path(__file__).resolve().parents[1]
SQL_059 = ROOT / "db" / "059_本社下処理_作業終了で開始時刻を作業者に合わせる.sql"
SQL_072 = ROOT / "db" / "072_本社下処理_休憩からの再開を取り消す.sql"


class PrepResumeUndoSqlTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        prep_edit_sql.PrepEditSqlTests.setUpClass()
        cls.pg = prep_edit_sql.PrepEditSqlTests.pg
        cls.pg.file(SQL_059)
        cls.pg.file(SQL_072)
        cls.pg.file(SQL_072)  # 2回実行しても同じ

    @classmethod
    def tearDownClass(cls):
        prep_edit_sql.PrepEditSqlTests.doClassCleanups()

    sql = prep_edit_sql.PrepEditSqlTests.sql
    call = prep_edit_sql.PrepEditSqlTests.call
    denied = prep_edit_sql.PrepEditSqlTests.denied
    reset = prep_edit_sql.PrepEditSqlTests.reset
    start = prep_edit_sql.PrepEditSqlTests.start
    add_member = prep_edit_sql.PrepEditSqlTests.add_member

    def updated(self, work):
        return self.sql(f"select updated_at from public.hq_works_v1500 where id='{work}'", True)

    def member(self, work, staff):
        return self.sql(f"select id from public.hq_work_members_v1500 where work_id='{work}' and staff_id='{staff}' and end_at is null", True)

    def undo(self, role, work, member, updated=None):
        return self.call(role, "public.hq_work_resume_undo_v1199c169", f"'{work}'::uuid", f"'{member}'::uuid", f"'{updated or self.updated(work)}'::timestamptz")

    def setup_break(self, op):
        work = self.start(op, STAFF_1); self.add_member(work, STAFF_2)
        self.sql(f"update public.hq_work_members_v1500 set start_at=now()-interval '60 minutes' where work_id='{work}'; update public.hq_works_v1500 set started_at=now()-interval '60 minutes', c120_flow=true, review_status='draft' where id='{work}'")
        self.call(PREP, "public.hq_work_pause_add_v1199c124", f"'{work}'::uuid", f"'{op[:-3]}901'::uuid", f"array['{STAFF_1}'::uuid,'{STAFF_2}'::uuid]", "now()-interval '40 minutes'")
        return work

    def test_undo_all_reopens_break_and_end_marks_left(self):
        self.reset(); work = self.setup_break("91000000-0000-0000-0000-000000000010")
        self.call(PREP, "public.hq_work_resume_v1199c124", f"'{work}'::uuid", "'91000000-0000-0000-0000-000000000011'::uuid", f"array['{STAFF_1}'::uuid,'{STAFF_2}'::uuid]", "now()-interval '5 minutes'")
        self.assertEqual(self.sql(f"select pause_kind from public.hq_works_v1500 where id='{work}'", True), "")
        # 古い updated_at は取り消さない
        stale = self.undo(PREP, work, self.member(work, STAFF_1), "2000-01-01")
        self.assertTrue(stale.get("conflict"))
        r = self.undo(PREP, work, self.member(work, STAFF_1))
        self.assertTrue(r["ok"]); self.assertTrue(r["reopened"])
        self.assertEqual(self.sql(f"select pause_kind from public.hq_works_v1500 where id='{work}'", True), "休憩")
        self.assertEqual(self.sql(f"select end_at is null, array_length(resumed_staff_ids,1) from public.hq_work_pauses_v1199c116 where work_id='{work}'", True), "t|1")
        r2 = self.undo(WORKER, work, self.member(work, STAFF_2))
        self.assertTrue(r2["ok"]); self.assertFalse(r2["reopened"])
        self.assertEqual(self.sql(f"select count(*) from public.hq_work_members_v1500 where work_id='{work}' and end_at is null", True), "0")
        self.assertIn("再開の取り消し", self.sql(f"select history::text from public.hq_works_v1500 where id='{work}'", True))
        # 休憩より後・再開より前の時刻で作業終了できる。2人とも休憩に入った時刻で抜けた扱い
        end = self.call(PREP, "public.hq_prep_end_v1199c120", f"'{work}'::uuid", "'91000000-0000-0000-0000-000000000019'::uuid", f"'{self.updated(work)}'::timestamptz", "now()-interval '20 minutes'")
        self.assertTrue(end["ok"], end)
        self.assertEqual(self.sql(f"select string_agg(distinct end_reason,',') from public.hq_work_members_v1500 where work_id='{work}'", True), "途中で抜けた")

    def test_undo_one_while_others_still_on_break_and_guards(self):
        self.reset(); work = self.setup_break("91000000-0000-0000-0000-000000000020")
        self.call(PREP, "public.hq_work_resume_v1199c124", f"'{work}'::uuid", "'91000000-0000-0000-0000-000000000021'::uuid", f"array['{STAFF_1}'::uuid]", "now()-interval '5 minutes'")
        m1 = self.member(work, STAFF_1)
        self.denied(OTHER, "public.hq_work_resume_undo_v1199c169", f"'{work}'::uuid", f"'{m1}'::uuid", f"'{self.updated(work)}'::timestamptz")
        r = self.undo(ADMIN, work, m1)
        self.assertTrue(r["ok"]); self.assertFalse(r["reopened"])
        self.assertEqual(self.sql(f"select coalesce(array_length(resumed_staff_ids,1),0), end_at is null from public.hq_work_pauses_v1199c116 where work_id='{work}'", True), "0|t")
        self.assertEqual(self.sql(f"select pause_kind from public.hq_works_v1500 where id='{work}'", True), "休憩")
        # 戻し直せる
        self.assertTrue(self.call(PREP, "public.hq_work_resume_v1199c124", f"'{work}'::uuid", "'91000000-0000-0000-0000-000000000022'::uuid", f"array['{STAFF_1}'::uuid]", "now()-interval '2 minutes'")["ok"])
        # 最初から作業している人（休憩から戻った記録ではない）は取り消せない
        self.reset(); work = self.start("91000000-0000-0000-0000-000000000030", STAFF_1)
        self.sql(f"update public.hq_works_v1500 set c120_flow=true, review_status='draft' where id='{work}'")
        self.denied(PREP, "public.hq_work_resume_undo_v1199c169", f"'{work}'::uuid", f"'{self.member(work, STAFF_1)}'::uuid", f"'{self.updated(work)}'::timestamptz")
        # 抜けたあとの記録は取り消せない
        self.reset(); work = self.setup_break("91000000-0000-0000-0000-000000000040")
        self.call(PREP, "public.hq_work_resume_v1199c124", f"'{work}'::uuid", "'91000000-0000-0000-0000-000000000041'::uuid", f"array['{STAFF_1}'::uuid,'{STAFF_2}'::uuid]", "now()-interval '5 minutes'")
        m1 = self.member(work, STAFF_1)
        self.call(PREP, "public.hq_work_leave_v1199c124", f"'{work}'::uuid", f"'{STAFF_1}'::uuid", "now()-interval '1 minute'")
        self.denied(PREP, "public.hq_work_resume_undo_v1199c169", f"'{work}'::uuid", f"'{m1}'::uuid", f"'{self.updated(work)}'::timestamptz")
        self.assertEqual(self.sql("select has_function_privilege('anon','public.hq_work_resume_undo_v1199c169(uuid,uuid,timestamptz)','execute')", True), "f")


if __name__ == "__main__":
    unittest.main()
