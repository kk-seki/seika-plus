"""c171 下処理：中断から、メンバーを入れ替えて再開する（SQL 074）を、019〜051・059・072・074の使い捨てPostgreSQLで確かめる。"""
import unittest
from pathlib import Path

import test_prep_edit_sql as prep_edit_sql
from test_prep_work_sql import WORKER, PREP, OTHER, STAFF_1, STAFF_2, STAFF_3

ROOT = Path(__file__).resolve().parents[1]
SQL_059 = ROOT / "db" / "059_本社下処理_作業終了で開始時刻を作業者に合わせる.sql"
SQL_072 = ROOT / "db" / "072_本社下処理_休憩からの再開を取り消す.sql"
SQL_074 = ROOT / "db" / "074_本社下処理_中断からメンバーを入れ替えて再開.sql"


class PrepResumeSwapSqlTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        prep_edit_sql.PrepEditSqlTests.setUpClass()
        cls.pg = prep_edit_sql.PrepEditSqlTests.pg
        for f in (SQL_059, SQL_072, SQL_074, SQL_074):  # 074は2回実行しても同じ
            cls.pg.file(f)

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

    def suspend(self, op, kind="中断"):
        work = self.start(op, STAFF_1); self.add_member(work, STAFF_2)
        self.sql(f"update public.hq_work_members_v1500 set start_at=now()-interval '60 minutes' where work_id='{work}'; update public.hq_works_v1500 set started_at=now()-interval '60 minutes', c120_flow=true, review_status='draft' where id='{work}'")
        self.assertTrue(self.call(PREP, "public.hq_work_pause_v1199c116", f"'{work}'::uuid", f"'{op[:-3]}901'::uuid", f"'{kind}'", "'{}'::uuid[]")["ok"])
        self.sql(f"update public.hq_work_pauses_v1199c116 set start_at=now()-interval '30 minutes' where work_id='{work}'; update public.hq_work_members_v1500 set end_at=now()-interval '30 minutes' where work_id='{work}'")
        return work

    def swap(self, role, work, op, back, new, at="now()-interval '10 minutes'"):
        arr = lambda ids: "array[" + ",".join(f"'{x}'::uuid" for x in ids) + "]::uuid[]"
        return self.call(role, "public.hq_work_resume_swap_v1199c171", f"'{work}'::uuid", f"'{op}'::uuid", arr(back), arr(new), at)

    def rows(self, work):
        return self.sql(f"""select string_agg(s.name||':'||coalesce(m.end_reason,'作業中'), ',' order by m.start_at, s.name)
          from public.hq_work_members_v1500 m join public.hq_staff_v1500 s on s.id=m.staff_id where m.work_id='{work}'""", True)

    def test_swap_back_one_and_add_new(self):
        self.reset(); work = self.suspend("92000000-0000-0000-0000-000000000010")
        op = "92000000-0000-0000-0000-000000000011"
        at = "'" + self.sql("select now()-interval '10 minutes'", True) + "'::timestamptz"
        r = self.swap(PREP, work, op, [STAFF_1], [STAFF_3], at)
        self.assertTrue(r["ok"], r)
        self.assertEqual(r["left_staff_ids"], [STAFF_2])
        self.assertEqual(self.sql(f"select pause_kind from public.hq_works_v1500 where id='{work}'", True), "")
        # 戻らない人は中断した時刻で抜けた扱い。中断の記録は戻った人だけ
        self.assertEqual(self.sql(f"select end_reason from public.hq_work_members_v1500 where work_id='{work}' and staff_id='{STAFF_2}'", True), "途中で抜けた")
        self.assertEqual(self.sql(f"select staff_ids::text, end_at is not null from public.hq_work_pauses_v1199c116 where work_id='{work}'", True), "{%s}|t" % STAFF_1)
        self.assertEqual(self.sql(f"select count(*) from public.hq_work_members_v1500 where work_id='{work}' and end_at is null", True), "2")
        # 同じ操作をもう一度送っても1回分だけ
        again = self.swap(PREP, work, op, [STAFF_1], [STAFF_3], at)
        self.assertTrue(again.get("already"))
        self.assertEqual(self.sql(f"select count(*) from public.hq_work_members_v1500 where work_id='{work}'", True), "4")
        self.assertIn("再開（入れ替え）", self.sql(f"select history::text from public.hq_works_v1500 where id='{work}'", True))
        # 作業終了できる
        end = self.call(PREP, "public.hq_prep_end_v1199c120", f"'{work}'::uuid", "'92000000-0000-0000-0000-000000000019'::uuid", f"'{self.updated(work)}'::timestamptz", "now()")
        self.assertTrue(end["ok"], end)

    def test_all_new_people_removes_pause(self):
        self.reset(); work = self.suspend("92000000-0000-0000-0000-000000000020")
        r = self.swap(WORKER, work, "92000000-0000-0000-0000-000000000021", [], [STAFF_3])
        self.assertTrue(r["ok"], r)
        self.assertEqual(r["deleted_pauses"], 1)
        self.assertEqual(self.sql(f"select count(*) from public.hq_work_pauses_v1199c116 where work_id='{work}'", True), "0")
        self.assertEqual(self.sql(f"select count(*) from public.hq_work_members_v1500 where work_id='{work}' and end_reason='途中で抜けた'", True), "2")

    def test_guards(self):
        self.reset(); work = self.suspend("92000000-0000-0000-0000-000000000030")
        self.denied(OTHER, "public.hq_work_resume_swap_v1199c171", f"'{work}'::uuid", "'92000000-0000-0000-0000-000000000031'::uuid", "'{}'::uuid[]", f"array['{STAFF_3}'::uuid]", "now()")
        bad = [
            ([], [], "now()"),                                   # だれもいない
            ([STAFF_3], [], "now()"),                            # 中断前にいない人を「戻る人」に
            ([], [STAFF_1], "now()"),                            # 中断前の人を「新しく入る人」に
            ([STAFF_1], [], "now()-interval '40 minutes'"),     # 中断より前の時刻
            ([STAFF_1], [], "now()+interval '10 minutes'"),     # 未来
        ]
        for i, (back, new, at) in enumerate(bad):
            with self.subTest(i=i), self.assertRaises(AssertionError):
                self.swap(PREP, work, f"92000000-0000-0000-0000-00000000004{i}", back, new, at)
        # 休憩のときは使えない（いつもの再開を使う）
        self.reset(); work = self.suspend("92000000-0000-0000-0000-000000000050", kind="休憩")
        with self.assertRaises(AssertionError):
            self.swap(PREP, work, "92000000-0000-0000-0000-000000000051", [STAFF_1], [])
        self.assertEqual(self.sql("select has_function_privilege('anon','public.hq_work_resume_swap_v1199c171(uuid,uuid,uuid[],uuid[],timestamptz)','execute')", True), "f")


if __name__ == "__main__":
    unittest.main()
