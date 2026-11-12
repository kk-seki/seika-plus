"""c120 下処理フローを実際の047 migrationで回帰検証する（ローカル使い捨てPostgreSQL）。"""
import json
import threading
import unittest
from pathlib import Path

import test_prep_report_sql as prep_report_sql
from test_prep_work_sql import ADMIN, OTHER, PREP, WORKER, LOT_1, LOT_2, MASTER_1, STAFF_1, STAFF_2

ROOT = Path(__file__).resolve().parents[1]
SQL_047 = ROOT / "db" / "047_本社下処理_確認と差し戻しと作業時刻.sql"


class PrepC120FlowSqlTests(unittest.TestCase):
    """047単体を046までの実migration上で確認する。"""

    @classmethod
    def setUpClass(cls):
        prep_report_sql.PrepReportSqlRuntimeTests.setUpClass()
        cls.pg = prep_report_sql.PrepReportSqlRuntimeTests.pg
        cls.pg.file(SQL_047)

    @classmethod
    def tearDownClass(cls):
        prep_report_sql.PrepReportSqlRuntimeTests.doClassCleanups()

    def sql(self, statement, tuples=False):
        return self.pg.sql(statement, tuples)

    def call(self, role, function, *args):
        output = self.sql(
            f"set app.\"user\" = '{role}'; select {function}({','.join(args)});", True
        )
        return json.loads(output.splitlines()[-1])

    def assert_denied(self, role, function, *args):
        with self.assertRaises(AssertionError):
            self.call(role, function, *args)

    def reset(self):
        # 047台帳は operation_id を意図して保持する表なので、fixture reset 時だけ明示的に空にする。
        self.sql("truncate public.hq_prep_operations_v1199c120, public.hq_prep_legacy_archives_v1199c120;")
        prep_report_sql.PrepReportSqlRuntimeTests.reset(self)

    def start(self, operation, outputs=None, started="now()-interval '2 hours'", staff=STAFF_1):
        rows = outputs or [(MASTER_1, "false", "皮むき人参")]
        output_json = ",".join(
            "jsonb_build_object('master_id','%s','custom',%s,'name','%s')" % row
            for row in rows
        )
        return self.call(
            PREP, "public.hq_prep_start_v1199c120", f"'{operation}'::uuid", "'下処理室①'",
            f"array['{LOT_1}'::uuid]", f"array['{staff}'::uuid]", started,
            f"jsonb_build_array({output_json})",
        )

    def end(self, work, updated, operation, ended="now()-interval '1 hour'"):
        return self.call(
            PREP, "public.hq_prep_end_v1199c120", f"'{work}'::uuid", f"'{operation}'::uuid",
            f"'{updated}'::timestamptz", ended,
        )

    def report_payload(
        self, *, qty=10, expected=20, use_mode="partial", yield_kg=8, outputs=None,
        reason=None, started="now()-interval '2 hours'", ended="now()-interval '1 hour'",
        work_date="((now()-interval '2 hours') at time zone 'Asia/Tokyo')::date::text",
        members=None, breaks=None, materials=None,
    ):
        outputs = outputs or [(MASTER_1, "false", "皮むき人参", yield_kg)]
        members = members or [(STAFF_1, started, ended)]
        breaks = breaks or []
        materials = materials or [(LOT_1, qty, use_mode, expected)]
        output_rows = ",".join(
            "jsonb_build_object('master_id','%s','custom',%s,'name','%s','yield_kg',%s)" % row
            for row in outputs
        )
        material_rows = ",".join(
            "jsonb_build_object('lot_id','%s','qty',%s,'use_mode','%s','expected_available_qty',%s)" % row
            for row in materials
        )
        member_rows = ",".join(
            "jsonb_build_object('staff_id','%s','phase','作業','start_at',%s,'end_at',%s)" % row
            for row in members
        )
        break_rows = ",".join(
            "jsonb_build_object('kind','%s','start_at',%s,'end_at',%s,'excluded_staff_ids',%s)" % (
                row[0], row[1], row[2], "'%s'::jsonb" % row[3].replace("'", "''") if row[3].lstrip().startswith('[') else row[3]
            )
            for row in breaks
        )
        return (
            "jsonb_build_object("
            f"'work_date',({work_date}),'started_at',({started}),'ended_at',({ended}),'place','下処理室①',"
            f"'correction_reason',{repr(reason) if reason is not None else 'null'},"
            f"'outputs',jsonb_build_array({output_rows}),'materials',jsonb_build_array({material_rows}),"
            f"'members',jsonb_build_array({member_rows}),'breaks',jsonb_build_array({break_rows}))"
        )

    def save(self, work, updated, operation, role=PREP, **kwargs):
        return self.call(
            role, "public.hq_prep_report_save_v1199c120",
            "null" if work is None else f"'{work}'::uuid", f"'{operation}'::uuid",
            "null" if updated is None else f"'{updated}'::timestamptz", self.report_payload(**kwargs),
        )

    def submit(self, work, updated, operation, role=PREP):
        return self.call(
            role, "public.hq_prep_submit_v1199c120", f"'{work}'::uuid",
            f"'{operation}'::uuid", f"'{updated}'::timestamptz",
        )

    def confirm(self, work, updated, operation, reason="null"):
        return self.call(
            ADMIN, "public.hq_prep_confirm_v1199c120", f"'{work}'::uuid",
            f"'{operation}'::uuid", f"'{updated}'::timestamptz", reason,
        )

    def return_work(self, work, updated, operation, reason="'確認してください'"):
        return self.call(
            ADMIN, "public.hq_prep_return_v1199c120", f"'{work}'::uuid",
            f"'{operation}'::uuid", f"'{updated}'::timestamptz", reason,
        )

    def available(self, work):
        return self.call(
            PREP, "public.hq_prep_available_lots_v1199c120",
            "null" if work is None else f"'{work}'::uuid",
        )

    @staticmethod
    def sql_time(value):
        return "'%s'::timestamptz" % value.replace("'", "''")

    def saved_report_args(self, work):
        started, ended, work_date = self.sql(
            f"select started_at::text||'|'||ended_at::text||'|'||work_date::text from public.hq_works_v1500 where id='{work}'", True
        ).split('|')
        members = self.sql(
            f"select coalesce(string_agg(staff_id::text||'|'||start_at::text||'|'||end_at::text, E'\n' order by staff_id,start_at),'') from public.hq_work_members_v1500 where work_id='{work}' and phase='作業'", True
        )
        pauses = self.sql(
            f"select coalesce(string_agg(kind||'|'||start_at::text||'|'||end_at::text||'|'||coalesce(to_json(excluded_staff_ids)::text,'[]'), E'\n' order by start_at),'') from public.hq_work_pauses_v1199c116 where work_id='{work}' and kind in ('休憩','中断')", True
        )
        member_rows = [line.split('|', 2) for line in members.splitlines() if line]
        break_rows = [line.split('|', 3) for line in pauses.splitlines() if line]
        return {
            'started': self.sql_time(started), 'ended': self.sql_time(ended),
            'work_date': f"'{work_date}'::date::text",
            'members': [(staff_id, self.sql_time(start_at), self.sql_time(end_at)) for staff_id, start_at, end_at in member_rows],
            'breaks': [(kind, self.sql_time(start_at), self.sql_time(end_at), excluded) for kind, start_at, end_at, excluded in break_rows],
        }

    def active_qty(self, work, material, qty, role=PREP):
        return self.call(
            role, "public.hq_work_save_material_qty_v1199c112",
            f"'{work}'::uuid", f"'{material}'::uuid", str(qty),
        )

    def completed_c120(self, seed=1, qty=9):
        # 末尾12桁を seed×100+段階で分け、後段テストのoperation_idと絶対に衝突させない。
        base = int(seed) * 100
        operation = lambda n: f"51000000-0000-0000-0000-{base + n:012d}"
        started = self.start(operation(1))
        ended = self.end(started["id"], started["updated_at"], operation(2))
        saved = self.save(started["id"], ended["updated_at"], operation(3), qty=qty)
        return started, ended, saved

    def test_schema_custom_outputs_and_new_report_without_fake_start(self):
        self.reset()
        started = self.start(
            "51000000-0000-0000-0000-000000000001",
            [(MASTER_1, "false", "皮むき人参"),
             ("20000000-0000-0000-0000-000000000099", "true", "特注人参"),
             ("20000000-0000-0000-0000-000000000098", "true", "細切り人参")],
        )
        self.assertTrue(started["ok"])
        self.assertEqual(self.sql("select count(*) from public.hq_prep_masters_v1500", True), "3")
        outputs = self.sql(f"select outputs::text from public.hq_works_v1500 where id='{started['id']}'", True)
        self.assertEqual(outputs.count('"expiry_days": 2'), 3)
        self.assertIn('"custom": true', outputs)

        self.reset()
        # p_work_id=NULL の後入力は、最初に架空の「開始作業」を作らず、成功時だけ一件を作る。
        created = self.save(None, None, "51000000-0000-0000-0000-000000000002")
        self.assertTrue(created["ok"])
        self.assertEqual(self.sql(
            "select count(*) from public.hq_prep_operations_v1199c120 "
            "where operation_id='51000000-0000-0000-0000-000000000002'::uuid and work_id is not null", True), "1")
        self.assertEqual(self.sql(
            f"select c120_flow::text||':'||review_status||':'||status from public.hq_works_v1500 where id='{created['id']}'", True),
            "true:draft:完了",
        )
        # 失敗時は台帳もworkも増えず、後続の部分保存が残らない。
        with self.assertRaises(AssertionError):
            self.save(None, None, "51000000-0000-0000-0000-000000000003", yield_kg=99)
        self.assertEqual(self.sql(
            "select count(*) from public.hq_prep_operations_v1199c120 "
            "where operation_id='51000000-0000-0000-0000-000000000003'::uuid", True), "0")

    def test_submitted_is_editable_until_employee_confirms_and_history_has_full_before_after(self):
        self.reset()
        s, _, saved = self.completed_c120(10)
        submitted = self.submit(s["id"], saved["updated_at"], "51000000-0000-0000-0000-000000000110")
        self.assertEqual(submitted["review_status"], "submitted")
        edited = self.save(
            s["id"], submitted["updated_at"], "51000000-0000-0000-0000-000000000111",
            started="'2026-11-10T08:00:00+00'::timestamptz",
            ended="'2026-11-10T10:00:00+00'::timestamptz",
            work_date="'2026-11-10'::date::text",
            qty=9,
        )
        self.assertEqual(edited["review_status"], "draft")
        row = self.sql(f"""
          select (history->-1->>'actor_id')='{PREP}'::text
              and (history->-1->'before') ? 'materials'
              and (history->-1->'before') ? 'members'
              and (history->-1->'before') ? 'breaks'
              and (history->-1->'before') ? 'outputs'
              and (history->-1->'after') ? 'materials'
              and (history->-1->'after') ? 'members'
              and (history->-1->'after') ? 'breaks'
              and (history->-1->'after') ? 'outputs'
              and (history->-1->'after'->>'started_at')::timestamptz='2026-11-10T08:00:00+00'::timestamptz
              and (history->-1->'after'->>'ended_at')::timestamptz='2026-11-10T10:00:00+00'::timestamptz
          from public.hq_works_v1500 where id='{s['id']}'
        """, True)
        self.assertEqual(row, "t")

    def test_returned_confirmed_prep_stages_stock_until_reconfirm_and_direct_employee_correction_is_immediate(self):
        self.reset()
        s, _, saved = self.completed_c120(20, qty=9)
        submitted = self.submit(s["id"], saved["updated_at"], "51000000-0000-0000-0000-000000000120")
        confirmed = self.confirm(s["id"], submitted["updated_at"], "51000000-0000-0000-0000-000000000121")
        self.assertEqual(self.sql(f"select current_qty from public.hq_lots_v1400 where id='{LOT_1}'", True), "11")

        returned = self.return_work(s["id"], confirmed["updated_at"], "51000000-0000-0000-0000-000000000122", "'再確認'")
        staged = self.save(s["id"], returned["updated_at"], "51000000-0000-0000-0000-000000000123", qty=10, expected=20)
        self.assertEqual(staged["review_status"], "returned")
        self.assertEqual(self.sql(f"select current_qty from public.hq_lots_v1400 where id='{LOT_1}'", True), "11")
        resubmitted = self.submit(s["id"], staged["updated_at"], "51000000-0000-0000-0000-000000000124")
        reconfirmed = self.confirm(s["id"], resubmitted["updated_at"], "51000000-0000-0000-0000-000000000125")
        self.assertEqual(reconfirmed["review_status"], "confirmed")
        self.assertEqual(self.sql(f"select current_qty from public.hq_lots_v1400 where id='{LOT_1}'", True), "10")

        # 差戻しを介さず社員が確定済み内容を訂正すると、baselineとの差を即時に反映する。
        direct = self.save(s["id"], reconfirmed["updated_at"], "51000000-0000-0000-0000-000000000126",
                           role=ADMIN, qty=8, expected=20, reason="社員直接訂正")
        self.assertEqual(direct["review_status"], "confirmed")
        self.assertEqual(self.sql(f"select current_qty from public.hq_lots_v1400 where id='{LOT_1}'", True), "12")
        self.assertEqual(self.sql(
            f"select (c120_applied_snapshot->'materials'->0->>'qty') from public.hq_works_v1500 where id='{s['id']}'", True), "8")

    def test_shortage_rejects_atomically_and_stale_confirm_cannot_clear_return(self):
        self.reset()
        s, _, saved = self.completed_c120(30, qty=10)
        submitted = self.submit(s["id"], saved["updated_at"], "51000000-0000-0000-0000-000000000130")
        # 先に在庫が減った場合の初回確定は、在庫移動もstatus変更も残さず失敗する。
        self.sql(f"update public.hq_lots_v1400 set current_qty=5 where id='{LOT_1}'")
        with self.assertRaises(AssertionError):
            self.confirm(s["id"], submitted["updated_at"], "51000000-0000-0000-0000-000000000131")
        self.assertEqual(self.sql(f"select current_qty||':'||confirm_status||':'||review_status from public.hq_lots_v1400 l join public.hq_works_v1500 w on true where l.id='{LOT_1}' and w.id='{s['id']}'", True), "5:未確定:submitted")
        self.assertEqual(self.sql(f"select count(*) from public.hq_lot_movements_v1400 where work_id='{s['id']}'", True), "0")

        # stale confirm は returned を confirmed に戻せない。
        self.sql(f"update public.hq_lots_v1400 set current_qty=20 where id='{LOT_1}'")
        current = self.sql(f"select updated_at from public.hq_works_v1500 where id='{s['id']}'", True)
        confirmed = self.confirm(s["id"], current, "51000000-0000-0000-0000-000000000132")
        returned = self.return_work(s["id"], confirmed["updated_at"], "51000000-0000-0000-0000-000000000133")
        stale = self.confirm(s["id"], confirmed["updated_at"], "51000000-0000-0000-0000-000000000134")
        self.assertTrue(stale["conflict"])
        self.assertEqual(self.sql(f"select review_status from public.hq_works_v1500 where id='{s['id']}'", True), "returned")
        self.assertEqual(returned["review_status"], "returned")

    def test_use_modes_expected_snapshot_own_reservation_and_stock_off(self):
        self.reset()
        # 自分の未確定予約は編集時のavailableから除外し、all/partialともexpected snapshotを照合する。
        first = self.save(None, None, "51000000-0000-0000-0000-000000000140", qty=5, expected=20, yield_kg=5)
        own = self.save(first["id"], first["updated_at"], "51000000-0000-0000-0000-000000000141", qty=12, expected=20)
        self.assertTrue(own["ok"])
        with self.assertRaises(AssertionError):
            self.save(first["id"], own["updated_at"], "51000000-0000-0000-0000-000000000142", qty=12, expected=19)
        all_work = self.save(None, None, "51000000-0000-0000-0000-000000000143", use_mode="all", expected=8, yield_kg=8, members=[(STAFF_2, "now()-interval '2 hours'", "now()-interval '1 hour'")] )
        self.assertEqual(self.sql(f"select qty from public.hq_work_materials_v1500 where work_id='{all_work['id']}'", True), "8")

        # stock-off の確定は在庫を減らさず、同じ数量の未確定日報を不当に拒否しない。
        self.reset()
        self.sql("update public.hq_settings_v1500 set value='false'::jsonb where key='stage2_stock'")
        s, _, saved = self.completed_c120(44, qty=10)
        submitted = self.submit(s["id"], saved["updated_at"], "51000000-0000-0000-0000-000000000144")
        confirmed = self.confirm(s["id"], submitted["updated_at"], "51000000-0000-0000-0000-000000000145")
        self.assertFalse(confirmed["stock_applied"])
        self.assertEqual(self.sql(f"select current_qty from public.hq_lots_v1400 where id='{LOT_1}'", True), "20")
        other = self.save(None, None, "51000000-0000-0000-0000-000000000146", qty=10, expected=20, members=[(STAFF_2, "now()-interval '2 hours'", "now()-interval '1 hour'")])
        self.assertTrue(other["ok"])

    def test_breaks_split_members_and_end_rejects_paused_or_invalid_member_intervals(self):
        self.reset()
        started = self.start("51000000-0000-0000-0000-000000000150", staff=STAFF_1)
        # 終了時は未解決pauseと不正区間を拒否する。
        self.sql(f"update public.hq_works_v1500 set pause_kind='休憩' where id='{started['id']}'")
        self.assert_denied(PREP, "public.hq_prep_end_v1199c120", f"'{started['id']}'::uuid", "'51000000-0000-0000-0000-000000000151'::uuid", f"'{started['updated_at']}'::timestamptz", "now()-interval '1 hour'")
        self.sql(f"update public.hq_works_v1500 set pause_kind='' where id='{started['id']}'")
        self.sql(f"update public.hq_work_members_v1500 set end_at=start_at where work_id='{started['id']}'")
        self.assert_denied(PREP, "public.hq_prep_end_v1199c120", f"'{started['id']}'::uuid", "'51000000-0000-0000-0000-000000000152'::uuid", f"'{started['updated_at']}'::timestamptz", "now()-interval '1 hour'")
        self.sql(f"update public.hq_work_members_v1500 set end_at=null where work_id='{started['id']}'")
        ended = self.end(started["id"], started["updated_at"], "51000000-0000-0000-0000-000000000153")
        report = self.save(
            started["id"], ended["updated_at"], "51000000-0000-0000-0000-000000000154",
            members=[(STAFF_1, "now()-interval '2 hours'", "now()-interval '1 hour'"),
                     (STAFF_2, "now()-interval '2 hours'", "now()-interval '1 hour'")],
            breaks=[("休憩", "now()-interval '105 minutes'", "now()-interval '90 minutes'", f"jsonb_build_array('{STAFF_2}')")],
        )
        self.assertTrue(report["ok"])
        self.assertEqual(self.sql(f"select count(*) from public.hq_work_members_v1500 where work_id='{started['id']}' and staff_id='{STAFF_1}'", True), "2")
        self.assertEqual(self.sql(f"select count(*) from public.hq_work_members_v1500 where work_id='{started['id']}' and staff_id='{STAFF_2}'", True), "1")
        self.assertEqual(self.sql(f"select staff_ids::text||':'||excluded_staff_ids::text from public.hq_work_pauses_v1199c116 where work_id='{started['id']}'", True), f"{{{STAFF_1}}}:{{{STAFF_2}}}")

    def test_standard_snapshots_custom_unset_and_legacy_adoption_preserves_history_and_expiry(self):
        self.reset()
        self.call(WORKER, "public.hq_prep_standard_save_v1199c117", f"array['{MASTER_1}'::uuid]", "80", "4")
        registered = self.save(None, None, "51000000-0000-0000-0000-000000000160")
        self.assertEqual(self.sql(f"select standard_rate||':'||tolerance_points from public.hq_works_v1500 where id='{registered['id']}'", True), "80:4")
        self.call(WORKER, "public.hq_prep_standard_save_v1199c117", f"array['{MASTER_1}'::uuid]", "70", "1")
        edited = self.save(registered["id"], registered["updated_at"], "51000000-0000-0000-0000-000000000161")
        self.assertTrue(edited["ok"])
        self.assertEqual(self.sql(f"select standard_rate||':'||tolerance_points from public.hq_works_v1500 where id='{registered['id']}'", True), "80:4")
        custom = self.save(None, None, "51000000-0000-0000-0000-000000000162", expected=10, outputs=[("20000000-0000-0000-0000-000000000199", "true", "特注人参", 8)], members=[(STAFF_2, "now()-interval '2 hours'", "now()-interval '1 hour'")] )
        self.assertEqual(self.sql(f"select coalesce(standard_rate::text,'null')||':'||coalesce(tolerance_points::text,'null') from public.hq_works_v1500 where id='{custom['id']}'", True), "null:null")

        self.reset()
        # 旧終了・清掃中の作業は明示保存時だけ採用し、archiveに旧清掃記録を残す。旧expiry snapshotも保存する。
        self.sql(f"update public.hq_prep_masters_v1500 set expiry_days=7 where id='{MASTER_1}'")
        legacy = self.call(PREP, "public.hq_work_start_v1199c116", "'51000000-0000-0000-0000-000000000163'::uuid", "'下処理'", "null", "'下処理室①'", f"array['{MASTER_1}'::uuid]", f"array['{LOT_1}'::uuid]", f"array['{STAFF_1}'::uuid]")
        self.call(PREP, "public.hq_work_end_v1500", f"'{legacy['id']}'::uuid")
        material = self.sql(f"select id from public.hq_work_materials_v1500 where work_id='{legacy['id']}'", True)
        self.call(PREP, "public.hq_work_save_inputs_v1199c116", f"'{legacy['id']}'::uuid", f"jsonb_build_array(jsonb_build_object('id','{material}','qty',10))", "2", f"jsonb_build_array(jsonb_build_object('master_id','{MASTER_1}','yield_kg',8))")
        self.call(PREP, "public.hq_work_to_clean_v1500", f"'{legacy['id']}'::uuid", "false")
        self.sql(f"update public.hq_prep_masters_v1500 set expiry_days=99 where id='{MASTER_1}'")
        old_updated = self.sql(f"select updated_at from public.hq_works_v1500 where id='{legacy['id']}'", True)
        adopted = self.save(legacy["id"], old_updated, "51000000-0000-0000-0000-000000000164", role=WORKER)
        self.assertTrue(adopted["ok"])
        self.assertEqual(self.sql(f"select c120_flow::text||':'||status||':'||(outputs->0->>'expiry_days') from public.hq_works_v1500 where id='{legacy['id']}'", True), "true:完了:7")
        self.assertEqual(self.sql(f"select (snapshot->'members') @> '[{{\"phase\":\"清掃\"}}]'::jsonb from public.hq_prep_legacy_archives_v1199c120 where work_id='{legacy['id']}'", True), "t")
        self.assertEqual(self.sql(f"select count(*) from public.hq_work_members_v1500 where work_id='{legacy['id']}' and phase='清掃'", True), "0")

    def test_old_public_routes_are_guarded_reapply_is_idempotent_and_confirm_is_concurrent_safe(self):
        self.reset()
        s, _, saved = self.completed_c120(70, qty=9)
        material = self.sql(f"select id from public.hq_work_materials_v1500 where work_id='{s['id']}'", True)
        self.assert_denied(PREP, "public.hq_work_save_inputs_v1199c116", f"'{s['id']}'::uuid", f"jsonb_build_array(jsonb_build_object('id','{material}','qty',9))", "1", f"jsonb_build_array(jsonb_build_object('master_id','{MASTER_1}','yield_kg',8))")
        self.assertEqual(self.sql("select has_function_privilege('authenticated','public.hq_c120_apply_stock_delta(uuid,jsonb,jsonb,boolean,text,public.profiles)','execute')", True), "f")

        submitted = self.submit(s["id"], saved["updated_at"], "51000000-0000-0000-0000-000000000170")
        results, errors = [], []
        def invoke():
            try:
                results.append(self.confirm(s["id"], submitted["updated_at"], "51000000-0000-0000-0000-000000000171"))
            except Exception as exc:  # pragma: no cover - asserted below
                errors.append(exc)
        threads = [threading.Thread(target=invoke), threading.Thread(target=invoke)]
        for thread in threads: thread.start()
        for thread in threads: thread.join()
        self.assertFalse(errors)
        self.assertEqual(len(results), 2)
        self.assertEqual(self.sql(f"select current_qty from public.hq_lots_v1400 where id='{LOT_1}'", True), "11")
        self.assertEqual(self.sql(f"select count(*) from public.hq_lot_movements_v1400 where work_id='{s['id']}'", True), "1")
        changed = self.call(ADMIN, "public.hq_prep_confirm_v1199c120", f"'{s['id']}'::uuid", "'51000000-0000-0000-0000-000000000171'::uuid", f"'{submitted['updated_at']}'::timestamptz", "'different'")
        self.assertTrue(changed["idempotency_conflict"])

        self.pg.file(SQL_047)
        self.assertEqual(self.sql("select count(*) from pg_proc p where p.prokind='f' and pg_get_functiondef(p.oid) like '%c120 legacy-route guard v1%'", True), "11")
        for procedure in (
            "hq_prep_start_v1199c120(uuid,text,uuid[],uuid[],timestamptz,jsonb)",
            "hq_prep_end_v1199c120(uuid,uuid,timestamptz,timestamptz)",
            "hq_prep_report_save_v1199c120(uuid,uuid,timestamptz,jsonb)",
            "hq_prep_confirm_v1199c120(uuid,uuid,timestamptz,text)",
        ):
            self.assertEqual(self.sql(f"select to_regprocedure('public.{procedure}') is not null", True), "t")


    def test_active_quantity_and_closed_route_guard(self):
        self.reset()
        started = self.start("51000000-0000-0000-0000-000000000180")
        material = self.sql(f"select id from public.hq_work_materials_v1500 where work_id='{started['id']}'", True)
        saved_qty = self.active_qty(started["id"], material, 7)
        self.assertEqual(saved_qty["qty"], 7)
        self.assertEqual(saved_qty["updated_at"], self.sql(f"select to_jsonb(updated_at) from public.hq_works_v1500 where id='{started['id']}'", True).strip('"'))
        self.call(PREP, "public.hq_work_add_material_v1199c112", f"'{started['id']}'::uuid", f"'{LOT_2}'::uuid")
        self.assertEqual(self.sql(f"select count(*) from public.hq_work_materials_v1500 where work_id='{started['id']}'", True), "2")
        refreshed = self.sql(f"select updated_at from public.hq_works_v1500 where id='{started['id']}'", True)
        ended = self.end(started["id"], refreshed, "51000000-0000-0000-0000-000000000181")
        with self.assertRaises(AssertionError):
            self.active_qty(started["id"], material, 8)
        self.assertTrue(ended["ok"])

    def test_confirmed_available_roundtrip_and_movement_direction(self):
        self.reset()
        started, _, saved = self.completed_c120(81, qty=9)
        submitted = self.submit(started["id"], saved["updated_at"], "51000000-0000-0000-0000-000000000182")
        confirmed = self.confirm(started["id"], submitted["updated_at"], "51000000-0000-0000-0000-000000000183")
        lots = self.available(started["id"])
        lot = next(row for row in lots if row["id"] == LOT_1)
        self.assertEqual(str(lot["available_qty"]), "20")
        self.assertEqual(self.sql(f"select qty from public.hq_lot_movements_v1400 where work_id='{started['id']}'", True), "9")
        corrected = self.save(started["id"], confirmed["updated_at"], "51000000-0000-0000-0000-000000000184", role=ADMIN, qty=9, expected=20, reason="表示どおり再保存")
        self.assertTrue(corrected["ok"])

    def test_start_rejects_closed_overlap_and_break_overlap(self):
        self.reset()
        prior = self.start("51000000-0000-0000-0000-000000000185", started="now()-interval '3 hours'")
        prior_end = self.end(prior["id"], prior["updated_at"], "51000000-0000-0000-0000-000000000186")
        with self.assertRaises(AssertionError):
            self.start("51000000-0000-0000-0000-000000000187", started="now()-interval '2 hours'")
        self.assertTrue(prior_end["ok"])

        self.reset()
        started, _, _ = self.completed_c120(82, qty=9)
        updated = self.sql(f"select updated_at from public.hq_works_v1500 where id='{started['id']}'", True)
        with self.assertRaises(AssertionError):
            self.save(started["id"], updated, "51000000-0000-0000-0000-000000000188", breaks=[
                ("休憩", "now()-interval '105 minutes'", "now()-interval '75 minutes'", "'[]'::jsonb"),
                ("中断", "now()-interval '90 minutes'", "now()-interval '60 minutes'", "'[]'::jsonb"),
            ])

    def test_custom_output_edit_and_changed_standard_snapshot(self):
        self.reset()
        self.call(WORKER, "public.hq_prep_standard_save_v1199c117", f"array['{MASTER_1}'::uuid]", "80", "4")
        work = self.save(None, None, "51000000-0000-0000-0000-000000000189")
        custom_id = "20000000-0000-0000-0000-000000000190"
        changed = self.save(work["id"], work["updated_at"], "51000000-0000-0000-0000-000000000191", expected=20,
            outputs=[(custom_id, "true", "訂正後の特注人参", 8)])
        self.assertTrue(changed["ok"])
        self.assertEqual(self.sql(f"select outputs->0->>'name' from public.hq_works_v1500 where id='{work['id']}'", True), "訂正後の特注人参")
        self.assertEqual(self.sql(f"select coalesce(standard_rate::text,'null') from public.hq_works_v1500 where id='{work['id']}'", True), "null")


    def test_partial_resume_pause_survives_two_report_saves(self):
        self.reset()
        started = self.start("51000000-0000-0000-0000-000000000200", started="now()-interval '2 hours'", staff=STAFF_1)
        self.call(PREP, "public.hq_work_join_v1500", f"'{started['id']}'::uuid", f"array['{STAFF_2}'::uuid]")
        self.call(PREP, "public.hq_work_pause_v1199c116", f"'{started['id']}'::uuid", "'51000000-0000-0000-0000-000000000201'::uuid", "'休憩'", "'{}'::uuid[]")
        self.sql("select pg_sleep(0.02)")
        self.call(PREP, "public.hq_work_resume_v1199c116", f"'{started['id']}'::uuid", "'51000000-0000-0000-0000-000000000202'::uuid", f"array['{STAFF_1}'::uuid]")
        self.sql("select pg_sleep(0.02)")
        self.call(PREP, "public.hq_work_resume_v1199c116", f"'{started['id']}'::uuid", "'51000000-0000-0000-0000-000000000203'::uuid", f"array['{STAFF_2}'::uuid]")
        updated = self.sql(f"select updated_at from public.hq_works_v1500 where id='{started['id']}'", True)
        self.end(started["id"], updated, "51000000-0000-0000-0000-000000000204", "clock_timestamp()")
        args = self.saved_report_args(started["id"])
        before = self.sql(f"select staff_id::text||':'||sum(extract(epoch from end_at-start_at))::numeric(20,6)::text from public.hq_work_members_v1500 where work_id='{started['id']}' group by staff_id order by staff_id", True)
        first = self.save(started["id"], self.sql(f"select updated_at from public.hq_works_v1500 where id='{started['id']}'", True), "51000000-0000-0000-0000-000000000205", qty=9, expected=20, **args)
        self.assertTrue(first["ok"])
        self.assertEqual(self.sql(f"select count(*) from public.hq_work_pauses_v1199c116 where work_id='{started['id']}' and end_at is null", True), "0")
        self.assertEqual(self.sql(f"select staff_id::text||':'||sum(extract(epoch from end_at-start_at))::numeric(20,6)::text from public.hq_work_members_v1500 where work_id='{started['id']}' group by staff_id order by staff_id", True), before)
        second_args = self.saved_report_args(started["id"])
        second = self.save(started["id"], first["updated_at"], "51000000-0000-0000-0000-000000000206", qty=9, expected=20, **second_args)
        self.assertTrue(second["ok"])
        self.assertEqual(self.sql(f"select count(*) from public.hq_work_pauses_v1199c116 where work_id='{started['id']}' and end_at is null", True), "0")
        self.assertEqual(self.sql(f"select staff_id::text||':'||sum(extract(epoch from end_at-start_at))::numeric(20,6)::text from public.hq_work_members_v1500 where work_id='{started['id']}' group by staff_id order by staff_id", True), before)

    def test_candidate_rpc_acl_and_confirmed_legacy_roundtrip(self):
        self.reset()
        legacy = self.call(PREP, "public.hq_work_start_v1199c116", "'51000000-0000-0000-0000-000000000207'::uuid", "'下処理'", "null", "'下処理室①'", f"array['{MASTER_1}'::uuid]", f"array['{LOT_1}'::uuid]", f"array['{STAFF_1}'::uuid]")
        self.call(PREP, "public.hq_work_end_v1500", f"'{legacy['id']}'::uuid")
        material = self.sql(f"select id from public.hq_work_materials_v1500 where work_id='{legacy['id']}'", True)
        self.call(PREP, "public.hq_work_save_inputs_v1199c116", f"'{legacy['id']}'::uuid", f"jsonb_build_array(jsonb_build_object('id','{material}','qty',10))", "2", f"jsonb_build_array(jsonb_build_object('master_id','{MASTER_1}','yield_kg',8))")
        self.call(ADMIN, "public.hq_prep_confirm_v1199c116", f"'{legacy['id']}'::uuid", f"jsonb_build_array(jsonb_build_object('id','{material}','qty',10))", "2", f"jsonb_build_array(jsonb_build_object('master_id','{MASTER_1}','yield_kg',8))", "'旧作業を確定'")
        legacy_available = self.available(legacy["id"])
        self.assertEqual(str(next(row["available_qty"] for row in legacy_available if row["id"] == LOT_1)), "20")
        old_updated = self.sql(f"select updated_at from public.hq_works_v1500 where id='{legacy['id']}'", True)
        adopted = self.save(legacy["id"], old_updated, "51000000-0000-0000-0000-000000000208", role=ADMIN, qty=10, expected=20, reason="旧確定作業を確認")
        self.assertTrue(adopted["ok"])
        self.assertEqual(self.sql(f"select c120_flow::text from public.hq_works_v1500 where id='{legacy['id']}'", True), "true")
        self.assertEqual(self.sql("select has_function_privilege('authenticated','public.hq_prep_available_lots_v1199c120(uuid)','execute')", True), "t")
        output = self.sql(f"set role authenticated; set app.\"user\" = '{PREP}'; select public.hq_prep_available_lots_v1199c120(null);", True)
        self.assertTrue(json.loads(output.splitlines()[-1]))

    def test_cancelled_submitted_report_cannot_be_confirmed(self):
        self.reset()
        work = self.save(None, None, "51000000-0000-0000-0000-000000000209")
        self.submit(work["id"], work["updated_at"], "51000000-0000-0000-0000-000000000210")
        self.call(ADMIN, "public.hq_work_cancel_v1500", f"'{work['id']}'::uuid", "'誤登録を取消'")
        updated = self.sql(f"select updated_at from public.hq_works_v1500 where id='{work['id']}'", True)
        self.assert_denied(ADMIN, "public.hq_prep_confirm_v1199c120", f"'{work['id']}'::uuid", "'51000000-0000-0000-0000-000000000211'::uuid", f"'{updated}'::timestamptz", "null")
        self.assertEqual(self.sql(f"select current_qty from public.hq_lots_v1400 where id='{LOT_1}'", True), "20")
        self.assertEqual(self.sql(f"select count(*) from public.hq_lot_movements_v1400 where work_id='{work['id']}'", True), "0")

    def test_c120_success_checks_include_submit_and_acl(self):
        self.assertEqual(self.sql("select count(*) from regexp_matches(pg_get_functiondef('public.hq_prep_available_lots_v1199c120(uuid)'::regprocedure), 'security definer', 'i')", True), "1")
        self.assertEqual(self.sql("select has_function_privilege('authenticated','public.hq_prep_submit_v1199c120(uuid,uuid,timestamptz)','execute')", True), "t")
        self.assertEqual(Path(SQL_047).read_text(encoding='utf-8').count('union all select'), 9)



if __name__ == "__main__":
    unittest.main()
