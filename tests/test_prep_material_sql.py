import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
SQL = (ROOT / "db" / "042_本社下処理_作業中の原料追加と使用量保存.sql").read_text(encoding="utf-8")


class PrepMaterialSqlTests(unittest.TestCase):
    def test_both_fixed_rpc_signatures_exist(self):
        self.assertRegex(SQL, r"hq_work_add_material_v1199c112\s*\(p_work_id uuid, p_lot_id uuid\)")
        self.assertRegex(SQL, r"hq_work_save_material_qty_v1199c112\s*\(p_work_id uuid, p_material_id uuid, p_qty numeric\)")

    def test_add_requires_authorized_open_prep_and_matching_available_lot(self):
        for required in (
            "hq_actor_v1400(array['admin','hq_worker','hq_prep'])",
            "where id = p_work_id for update",
            "w.kind <> '下処理'",
            "w.status <> '作業中'",
            "w.confirm_status <> '未確定'",
            "where id = p_lot_id for update",
            "l.item_name <> w.raw_item_name",
            "l.status <> '在庫あり' or coalesce(l.current_qty, 0) <= 0",
        ):
            self.assertIn(required, SQL)

    def test_duplicate_is_idempotent_and_new_material_starts_without_qty(self):
        self.assertRegex(SQL, r"where work_id = w\.id and lot_id = l\.id;\s*if found then\s*return jsonb_build_object\('ok', true, 'already', true")
        insert = re.search(r"insert into public\.hq_work_materials_v1500\((.*?)\)\s*values", SQL, re.S)
        self.assertIsNotNone(insert)
        self.assertNotIn("qty", insert.group(1))

    def test_qty_save_is_limited_to_own_material_and_does_not_change_stock(self):
        self.assertIn("p_qty is null or p_qty < 0 or p_qty::text in ('NaN', 'Infinity', '-Infinity')", SQL)
        self.assertIn("where id = p_material_id and work_id = w.id for update", SQL)
        self.assertIn("update public.hq_work_materials_v1500 set qty = p_qty where id = mt.id", SQL)
        save = SQL[SQL.index("create or replace function public.hq_work_save_material_qty_v1199c112"):]
        self.assertNotIn("hq_lots_v1400 set current_qty", save)
        self.assertNotIn("hq_lot_movements_v1400", save)

    def test_history_updated_and_public_cannot_execute(self):
        self.assertGreaterEqual(SQL.count("history = history || jsonb_build_array"), 2)
        self.assertGreaterEqual(SQL.count("updated_at = now()"), 2)
        self.assertIn("revoke all on function public.hq_work_add_material_v1199c112(uuid,uuid) from public, anon", SQL)
        self.assertIn("revoke all on function public.hq_work_save_material_qty_v1199c112(uuid,uuid,numeric) from public, anon", SQL)
        self.assertIn("grant execute on function public.hq_work_add_material_v1199c112(uuid,uuid) to authenticated, service_role", SQL)
        self.assertIn("grant execute on function public.hq_work_save_material_qty_v1199c112(uuid,uuid,numeric) to authenticated, service_role", SQL)


if __name__ == "__main__":
    unittest.main()
