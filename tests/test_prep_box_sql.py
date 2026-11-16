"""c123 箱の半端と手入力廃棄を019〜050のローカル使い捨てPostgreSQLで検証する。"""
import json
import unittest
from pathlib import Path

import test_prep_pallet_sql as prep_pallet_sql
from test_prep_flow_sql import PrepC120FlowSqlTests
from test_prep_work_sql import ADMIN, LOT_1, LOT_2, OTHER, PREP, WORKER, MASTER_1, STAFF_1

ROOT = Path(__file__).resolve().parents[1]
SQL_050 = ROOT / "db" / "050_本社下処理_箱の半端と廃棄の手入力.sql"
W1 = "70000000-0000-0000-0000-000000000001"
W2 = "70000000-0000-0000-0000-000000000002"


class PrepBoxSqlTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        prep_pallet_sql.PrepPalletSqlTests.setUpClass()
        cls.pg = prep_pallet_sql.PrepPalletSqlTests.pg
        cls.pg.file(SQL_050)
        cls.pg.file(SQL_050)  # 再適用で既存データを変えず成功する。

    @classmethod
    def tearDownClass(cls):
        prep_pallet_sql.PrepPalletSqlTests.doClassCleanups()

    def sql(self, statement, tuples=False):
        return self.pg.sql(statement, tuples)

    def call(self, role, function, *args):
        output = self.sql(f"set app.\"user\" = '{role}'; select {function}({','.join(args)});", True)
        return json.loads(output.splitlines()[-1])

    def assert_rejected(self, role, function, *args):
        with self.assertRaises(AssertionError):
            self.call(role, function, *args)

    def reset(self):
        prep_pallet_sql.PrepPalletSqlTests.reset(self)

    def prepare_sheet_lot(self, qty=210):
        self.sql(f"""
          update public.hq_lots_v1400 set unit='ケース',current_qty={qty},received_qty={qty},planned_qty={qty},status='在庫あり',
            pack_weight='5kg',sheet_meta='{{"mode":"pallet","palletQtys":[42,42]}}'::jsonb,planned_count=null,unit_weight_kg=null
          where id='{LOT_1}';
        """)

    def use(self, work, lot, unit_no, mode, unopened, open_kg, remaining, total, operation, role=PREP):
        value = lambda item: "null" if item is None else str(item)
        return self.call(
            role, "public.hq_work_pallet_use_v1199c123", f"'{work}'::uuid", f"'{lot}'::uuid",
            value(unit_no), f"'{mode}'", value(unopened), value(open_kg), value(remaining), value(total), f"'{operation}'::uuid",
        )

    def start(self, operation):
        return self.call(
            PREP, "public.hq_prep_start_v1199c120", f"'{operation}'::uuid", "'下処理室①'",
            f"array['{LOT_1}'::uuid]", f"array['{STAFF_1}'::uuid]", "now()-interval '2 hours'",
            f"jsonb_build_array(jsonb_build_object('master_id','{MASTER_1}','custom',false,'name','皮むき人参'))",
        )

    def end(self, work, updated, operation):
        return self.call(PREP, "public.hq_prep_end_v1199c120", f"'{work}'::uuid", f"'{operation}'::uuid", f"'{updated}'::timestamptz", "now()-interval '1 hour'")

    def report(self, qty=10, yield_kg=8, waste=None, reason=None, expected=20):
        manual = "" if waste is None else f",'waste_kg',{waste}"
        correction = "null" if reason is None else repr(reason)
        return (
            "jsonb_build_object("
            "'work_date',((now()-interval '2 hours') at time zone 'Asia/Tokyo')::date::text,"
            "'started_at',now()-interval '2 hours','ended_at',now()-interval '1 hour','place','下処理室①',"
            f"'correction_reason',{correction},'outputs',jsonb_build_array(jsonb_build_object('master_id','{MASTER_1}','custom',false,'name','皮むき人参','yield_kg',{yield_kg})),"
            f"'materials',jsonb_build_array(jsonb_build_object('lot_id','{LOT_1}','qty',{qty},'use_mode','partial','expected_available_qty',{expected})),"
            f"'members',jsonb_build_array(jsonb_build_object('staff_id','{STAFF_1}','phase','作業','start_at',now()-interval '2 hours','end_at',now()-interval '1 hour')),'breaks','[]'::jsonb{manual})"
        )

    def save_report(self, work, updated, operation, report, role=PREP):
        return self.call(role, "public.hq_prep_report_save_v1199c120", "null" if work is None else f"'{work}'::uuid", f"'{operation}'::uuid", "null" if updated is None else f"'{updated}'::timestamptz", report)

    def test_schema_rpc_acl_and_box_remainder_example_followup(self):
        self.assertEqual(self.sql("select to_regprocedure('public.hq_work_pallet_use_v1199c123(uuid,uuid,integer,text,numeric,numeric,numeric,numeric,uuid)') is not null", True), "t")
        self.assertEqual(self.sql("select has_function_privilege('anon','public.hq_work_pallet_use_v1199c123(uuid,uuid,integer,text,numeric,numeric,numeric,numeric,uuid)','execute')", True), "f")
        self.reset(); self.prepare_sheet_lot()
        first = self.use(W1, LOT_1, 1, "半端", 39, 3.3, None, None, "72000000-0000-0000-0000-000000000001")
        self.assertEqual((first["used_qty"], first["remaining_qty"], first["unopened_cases"], first["open_box_kg"]), (2.34, 39.66, 39, 3.3))
        unit = self.call(PREP, "public.hq_pallet_candidates_v1199c122", f"'{W1}'::uuid", f"'{LOT_1}'::uuid")["units"][0]
        self.assertEqual((unit["state"], unit["remaining_unopened"], unit["remaining_open_kg"]), ("partial", 39, 3.3))
        second = self.use(W1, LOT_1, 1, "半端", 38, 4.8, None, None, "72000000-0000-0000-0000-000000000002")
        self.assertEqual((second["used_qty"], second["remaining_qty"]), (0.7, 38.96))
        entries = self.call(PREP, "public.hq_work_pallet_list_v1199c122", f"array['{W1}'::uuid]")
        self.assertEqual([(x["unopened_cases"], x["open_box_kg"]) for x in entries], [(39, 3.3), (38, 4.8)])

    def test_box_boundaries_idempotency_rollback_cancel_and_compatibility(self):
        self.reset(); self.prepare_sheet_lot(qty=210)
        invalid = ((39.5, 1, None), (39, 5, None), (0, 0, None), (42, 0, None))
        for n, kg, remaining in invalid:
            with self.subTest(unopened=n, open_kg=kg):
                self.assert_rejected(PREP, "public.hq_work_pallet_use_v1199c123", f"'{W1}'::uuid", f"'{LOT_1}'::uuid", "1", "'半端'", str(n), str(kg), "null", "null", f"'72000000-0000-0000-0000-000000000{10 + int(kg):03d}'::uuid")
        self.assertEqual(self.sql("select count(*) from public.hq_work_material_units_v1199c122", True), "0")
        first = self.use(W1, LOT_1, 1, "半端", 39, 3.3, None, None, "72000000-0000-0000-0000-000000000020")
        replay = self.use(W1, LOT_1, 1, "半端", 39, 3.3, None, None, "72000000-0000-0000-0000-000000000020")
        self.assertTrue(replay["already"])
        self.assert_rejected(PREP, "public.hq_work_pallet_use_v1199c123", f"'{W1}'::uuid", f"'{LOT_1}'::uuid", "1", "'半端'", "38", "3.3", "null", "null", "'72000000-0000-0000-0000-000000000020'::uuid")
        cancelled = self.call(PREP, "public.hq_work_pallet_cancel_v1199c122", f"'{W1}'::uuid", f"'{first['entry_id']}'::uuid")
        self.assertEqual(cancelled["material_qty"], 0)
        self.reset(); self.prepare_sheet_lot(qty=10)
        self.assert_rejected(PREP, "public.hq_work_pallet_use_v1199c123", f"'{W1}'::uuid", f"'{LOT_1}'::uuid", "1", "'全量'", "null", "null", "null", "null", "'72000000-0000-0000-0000-000000000021'::uuid")
        self.assertEqual(self.sql("select count(*) from public.hq_work_material_units_v1199c122", True), "0")
        self.reset(); self.prepare_sheet_lot()
        compat = self.use(W1, LOT_1, 1, "半端", None, None, 40, None, "72000000-0000-0000-0000-000000000022")
        self.assertEqual((compat["used_qty"], compat["remaining_qty"]), (2, 40))
        self.assert_rejected(OTHER, "public.hq_work_pallet_use_v1199c123", f"'{W1}'::uuid", f"'{LOT_1}'::uuid", "1", "'全量'", "null", "null", "null", "null", "'72000000-0000-0000-0000-000000000023'::uuid")

    def test_large_container_keeps_existing_remainder_behavior(self):
        self.reset()
        self.sql(f"update public.hq_lots_v1400 set unit='kg',current_qty=25,received_qty=25,planned_qty=25,status='在庫あり',planned_count=3,unit_weight_kg=10,sheet_meta='{{}}'::jsonb where id='{LOT_2}'")
        result = self.use(W1, LOT_2, 1, "半端", None, None, 4, None, "72000000-0000-0000-0000-000000000030")
        self.assertEqual((result["used_qty"], result["remaining_qty"], result["unopened_cases"], result["open_box_kg"]), (6, 4, None, None))

    def test_manual_waste_auto_and_range_across_c120_paths(self):
        self.reset()
        created = self.save_report(None, None, "72000000-0000-0000-0000-000000000040", self.report(qty=10, yield_kg=8, waste=1))
        work = created["id"]
        self.assertEqual(self.sql(f"select waste_kg::text||':'||report_waste_kg::text from public.hq_works_v1500 where id='{work}'", True), "1:1")
        submitted = self.call(WORKER, "public.hq_prep_submit_v1199c120", f"'{work}'::uuid", "'72000000-0000-0000-0000-000000000041'::uuid", f"'{created['updated_at']}'::timestamptz")
        confirmed = self.call(ADMIN, "public.hq_prep_confirm_v1199c120", f"'{work}'::uuid", "'72000000-0000-0000-0000-000000000042'::uuid", f"'{submitted['updated_at']}'::timestamptz", "null")
        self.assertEqual(self.sql(f"select kg from public.hq_waste_v1500 where work_id='{work}' and cancelled_at is null", True), "1")
        corrected = self.save_report(work, confirmed["updated_at"], "72000000-0000-0000-0000-000000000043", self.report(qty=10, yield_kg=8, waste=0.5, reason="訂正"), ADMIN)
        self.assertTrue(corrected["ok"])
        self.assertEqual(self.sql(f"select waste_kg::text||':'||report_waste_kg::text from public.hq_works_v1500 where id='{work}'", True), "0.5:0.5")
        self.assertEqual(self.sql(f"select kg from public.hq_waste_v1500 where work_id='{work}' and cancelled_at is null", True), "0.5")
        returned = self.call(ADMIN, "public.hq_prep_return_v1199c120", f"'{work}'::uuid", "'72000000-0000-0000-0000-000000000044'::uuid", f"'{corrected['updated_at']}'::timestamptz", "'再提出'")
        resaved = self.save_report(work, returned["updated_at"], "72000000-0000-0000-0000-000000000045", self.report(qty=10, yield_kg=8, waste=0.25))
        self.assertTrue(resaved["ok"])
        resubmitted = self.call(WORKER, "public.hq_prep_submit_v1199c120", f"'{work}'::uuid", "'72000000-0000-0000-0000-000000000046'::uuid", f"'{resaved['updated_at']}'::timestamptz")
        self.call(ADMIN, "public.hq_prep_confirm_v1199c120", f"'{work}'::uuid", "'72000000-0000-0000-0000-000000000047'::uuid", f"'{resubmitted['updated_at']}'::timestamptz", "null")
        self.assertEqual(self.sql(f"select waste_kg::text||':'||report_waste_kg::text from public.hq_works_v1500 where id='{work}'", True), "0.25:0.25")
        auto = self.save_report(None, None, "72000000-0000-0000-0000-000000000048", self.report(qty=10, yield_kg=8, expected=10).replace("now()-interval '2 hours'", "now()-interval '5 hours'").replace("now()-interval '1 hour'", "now()-interval '4 hours'"))
        self.assertEqual(self.sql(f"select waste_kg::text from public.hq_works_v1500 where id='{auto['id']}'", True), "2")

    def test_manual_waste_rejects_overage_negative_and_nan(self):
        self.reset()
        for waste in ("3", "-1", "'NaN'::numeric"):
            with self.subTest(waste=waste):
                self.assert_rejected(PREP, "public.hq_prep_report_save_v1199c120", "null", "'72000000-0000-0000-0000-000000000050'::uuid", "null", self.report(qty=10, yield_kg=8, waste=waste))
