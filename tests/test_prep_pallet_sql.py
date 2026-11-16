"""c122 パレット／基ごとの原料使用RPCを019〜049のローカル使い捨てPostgreSQLで検証する。"""
import json
import unittest
from pathlib import Path

import test_prep_signature_sql as prep_signature_sql
from test_prep_work_sql import ADMIN, LOT_1, LOT_2, OTHER, PREP, WORKER

ROOT = Path(__file__).resolve().parents[1]
SQL_049 = ROOT / "db" / "049_本社下処理_パレットと基ごとの使用記録.sql"
W1 = "70000000-0000-0000-0000-000000000001"
W2 = "70000000-0000-0000-0000-000000000002"
W3 = "70000000-0000-0000-0000-000000000003"


class PrepPalletSqlTests(unittest.TestCase):
    """既存019〜048 fixtureへ049だけを追加して、物理単位の使用記録を確認する。"""

    @classmethod
    def setUpClass(cls):
        prep_signature_sql.PrepSignatureSqlTests.setUpClass()
        cls.pg = prep_signature_sql.PrepSignatureSqlTests.pg
        cls.pg.file(SQL_049)
        cls.pg.file(SQL_049)  # 再適用で既存データを変えず成功する。

    @classmethod
    def tearDownClass(cls):
        prep_signature_sql.PrepSignatureSqlTests.doClassCleanups()

    def sql(self, statement, tuples=False):
        return self.pg.sql(statement, tuples)

    def call(self, role, function, *args):
        output = self.sql(f"set app.\"user\" = '{role}'; select {function}({','.join(args)});", True)
        return json.loads(output.splitlines()[-1])

    def assert_denied(self, role, function, *args):
        with self.assertRaises(AssertionError):
            self.call(role, function, *args)

    def reset(self):
        prep_signature_sql.PrepSignatureSqlTests.reset(self)
        self.sql(f"""
          insert into public.hq_works_v1500
            (id,kind,task_name,work_date,status,raw_item_name,confirm_status,history)
          values
            ('{W1}','下処理','c122作業1',current_date,'作業中','人参','未確定','[]'),
            ('{W2}','下処理','c122作業2',current_date,'作業中','人参','未確定','[]'),
            ('{W3}','下処理','c122確定済み作業',current_date,'完了','人参','確定','[]');
        """)

    def candidates(self, work=W1, lot=LOT_1, role=PREP):
        return self.call(role, "public.hq_pallet_candidates_v1199c122", f"'{work}'::uuid", f"'{lot}'::uuid")

    def use(self, work, lot, unit_no, mode, remaining, total, operation, role=PREP):
        return self.call(
            role, "public.hq_work_pallet_use_v1199c122", f"'{work}'::uuid", f"'{lot}'::uuid",
            "null" if unit_no is None else str(unit_no), f"'{mode}'", "null" if remaining is None else str(remaining),
            "null" if total is None else str(total), f"'{operation}'::uuid",
        )

    def prepare_sheet_lot(self, qty=100):
        self.sql(f"""
          update public.hq_lots_v1400 set unit='ケース',current_qty={qty},received_qty={qty},planned_qty={qty},
            status='在庫あり',sheet_meta='{{"mode":"pallet","palletQtys":[30,30]}}'::jsonb,
            planned_count=null,unit_weight_kg=null where id='{LOT_1}';
        """)

    def test_049_schema_rpcs_reapply_and_acl_are_present(self):
        for procedure in (
            "hq_pallet_candidates_v1199c122(uuid,uuid)",
            "hq_work_pallet_use_v1199c122(uuid,uuid,integer,text,numeric,numeric,uuid)",
            "hq_work_pallet_cancel_v1199c122(uuid,uuid)",
            "hq_work_pallet_list_v1199c122(uuid[])",
        ):
            self.assertEqual(self.sql(f"select to_regprocedure('public.{procedure}') is not null", True), "t")
        self.assertEqual(self.sql("select relrowsecurity from pg_class where oid='public.hq_work_material_units_v1199c122'::regclass", True), "t")
        self.assertEqual(self.sql("select has_table_privilege('authenticated','public.hq_work_material_units_v1199c122','select,insert,update,delete')", True), "f")
        self.assertEqual(self.sql("select has_function_privilege('anon','public.hq_pallet_candidates_v1199c122(uuid,uuid)','execute')", True), "f")
        for role in (PREP, WORKER, ADMIN):
            self.reset()
            self.prepare_sheet_lot()
            self.assertTrue(self.candidates(role=role)["ok"])
        self.reset()
        self.prepare_sheet_lot()
        self.assert_denied(OTHER, "public.hq_pallet_candidates_v1199c122", f"'{W1}'::uuid", f"'{LOT_1}'::uuid")

    def test_candidates_cover_sheet_container_manual_and_cross_work_partial_priority(self):
        self.reset()
        self.prepare_sheet_lot()
        first = self.use(W1, LOT_1, 1, "半端", 20, None, "71000000-0000-0000-0000-000000000001")
        self.assertEqual((first["used_qty"], first["remaining_qty"], first["material_qty"]), (10, 20, 10))
        # 確定済みの他作業の物理使用も候補残数から引く（在庫予約とは別の物理記録）。
        material = self.sql(f"insert into public.hq_work_materials_v1500(work_id,lot_id,lot_no,item_name,unit,qty) values('{W3}','{LOT_1}','H-001','人参','ケース',10) returning id", True).splitlines()[0]
        self.sql(f"""
          insert into public.hq_work_material_units_v1199c122
            (work_id,material_id,lot_id,unit_no,unit_total,mode,used_qty,remaining_qty,operation_id)
          values ('{W3}','{material}','{LOT_1}',2,30,'半端',10,20,'71000000-0000-0000-0000-000000000002');
        """)
        answer = self.candidates()
        self.assertEqual(answer["source"], "sheet")
        self.assertEqual(answer["qty_unit"], "ケース")
        self.assertEqual(answer["next_no"], 1)  # partial を unused より優先する。
        self.assertEqual([(x["no"], x["used"], x["remaining"], x["mine"], x["state"]) for x in answer["units"]],
                         [(1, 10, 20, 10, "partial"), (2, 10, 20, 0, "partial")])

        self.sql(f"""
          update public.hq_lots_v1400 set unit='kg',current_qty=25,planned_qty=25,planned_count=3,unit_weight_kg=10,
            sheet_meta='{{}}'::jsonb,status='在庫あり' where id='{LOT_2}';
        """)
        container = self.candidates(lot=LOT_2)
        self.assertEqual((container["source"], container["large"], container["qty_unit"]), ("container", True, "kg"))
        self.assertEqual([x["total"] for x in container["units"]], [10, 10, 5])
        self.sql(f"update public.hq_lots_v1400 set unit='ケース',current_qty=20,planned_count=null,unit_weight_kg=null,sheet_meta='{{}}'::jsonb where id='{LOT_2}'")
        manual = self.candidates(lot=LOT_2)
        self.assertEqual((manual["source"], manual["units"], manual["next_no"]), ("manual", [], None))

    def test_partial_followup_full_idempotency_and_cancel_restore_material_qty(self):
        self.reset()
        self.prepare_sheet_lot()
        first = self.use(W1, LOT_1, 1, "半端", 12, None, "71000000-0000-0000-0000-000000000011")
        self.assertEqual((first["used_qty"], first["remaining_qty"]), (18, 12))
        second = self.use(W1, LOT_1, 1, "全量", None, None, "71000000-0000-0000-0000-000000000012")
        self.assertEqual((second["used_qty"], second["remaining_qty"], second["material_qty"]), (12, 0, 30))
        replay = self.use(W1, LOT_1, 1, "全量", None, None, "71000000-0000-0000-0000-000000000012")
        self.assertTrue(replay["already"])
        with self.assertRaises(AssertionError):
            self.use(W1, LOT_1, 1, "半端", 1, None, "71000000-0000-0000-0000-000000000012")
        entries = self.call(PREP, "public.hq_work_pallet_list_v1199c122", f"array['{W1}'::uuid]")
        self.assertEqual([x["used_qty"] for x in entries], [18, 12])
        cancelled = self.call(PREP, "public.hq_work_pallet_cancel_v1199c122", f"'{W1}'::uuid", f"'{second['entry_id']}'::uuid")
        self.assertEqual(cancelled["material_qty"], 18)
        self.assertTrue(self.call(PREP, "public.hq_work_pallet_cancel_v1199c122", f"'{W1}'::uuid", f"'{second['entry_id']}'::uuid")["already"])

    def test_manual_existing_qty_validation_state_item_and_reservation_rollback(self):
        self.reset()
        self.prepare_sheet_lot(qty=100)
        # 既存手入力数量へパレット記録の使用量を加算する。
        material = self.sql(f"insert into public.hq_work_materials_v1500(work_id,lot_id,lot_no,item_name,unit,qty) values('{W1}','{LOT_1}','H-001','人参','ケース',3) returning id", True).splitlines()[0]
        answer = self.use(W1, LOT_1, 2, "半端", 25, None, "71000000-0000-0000-0000-000000000021")
        self.assertEqual(answer["material_id"], material)
        self.assertEqual(answer["material_qty"], 8)
        for mode, remaining in (("半端", 0), ("半端", 30), ("不正", 1)):
            with self.subTest(mode=mode, remaining=remaining):
                with self.assertRaises(AssertionError):
                    self.use(W1, LOT_1, 1, mode, remaining, None, f"71000000-0000-0000-0000-0000000000{30 + remaining:02d}")
        self.sql(f"update public.hq_works_v1500 set status='完了' where id='{W1}'")
        with self.assertRaises(AssertionError):
            self.use(W1, LOT_1, 1, "全量", None, None, "71000000-0000-0000-0000-000000000040")
        self.sql(f"update public.hq_works_v1500 set status='作業中' where id='{W1}'; update public.hq_lots_v1400 set item_name='キャベツ' where id='{LOT_1}'")
        with self.assertRaises(AssertionError):
            self.use(W1, LOT_1, 1, "全量", None, None, "71000000-0000-0000-0000-000000000041")

        self.reset()
        self.prepare_sheet_lot(qty=10)
        self.sql(f"insert into public.hq_work_materials_v1500(work_id,lot_id,lot_no,item_name,unit,qty) values('{W1}','{LOT_1}','H-001','人参','ケース',2)")
        with self.assertRaises(AssertionError):
            self.use(W1, LOT_1, 1, "全量", None, None, "71000000-0000-0000-0000-000000000042")
        self.assertEqual(self.sql("select count(*) from public.hq_work_material_units_v1199c122", True), "0")
        self.assertEqual(self.sql(f"select qty from public.hq_work_materials_v1500 where work_id='{W1}' and lot_id='{LOT_1}'", True), "2")

    def test_manual_delete_cascade_and_no_double_take_other_work(self):
        self.reset()
        self.sql(f"update public.hq_lots_v1400 set unit='ケース',current_qty=20,status='在庫あり',sheet_meta='{{}}'::jsonb where id='{LOT_1}'")
        manual = self.use(W1, LOT_1, None, "半端", 7, 10, "71000000-0000-0000-0000-000000000051")
        self.assertEqual((manual["used_qty"], manual["remaining_qty"], manual["unit_no"]), (3, 7, None))
        self.sql(f"delete from public.hq_work_materials_v1500 where id='{manual['material_id']}'")
        self.assertEqual(self.sql("select count(*) from public.hq_work_material_units_v1199c122", True), "0")

        self.reset()
        self.prepare_sheet_lot(qty=100)
        self.assertEqual(self.use(W1, LOT_1, 1, "全量", None, None, "71000000-0000-0000-0000-000000000052")["used_qty"], 30)
        with self.assertRaises(AssertionError):
            self.use(W2, LOT_1, 1, "全量", None, None, "71000000-0000-0000-0000-000000000053")
        # 親作業の削除時も、記録がFK違反を起こさず連鎖削除される。
        self.assertTrue(self.call(ADMIN, "public.hq_work_delete_v1500", f"'{W1}'::uuid")["ok"])
        self.assertEqual(self.sql("select count(*) from public.hq_work_material_units_v1199c122", True), "0")
