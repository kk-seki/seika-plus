"""実際の016・019・022・023・042・045を使い捨てPostgreSQLへ適用し検証します。"""
import json
import os
import pwd
import shutil
import subprocess
import tempfile
import threading
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DB = ROOT / "db"
SQL_045_CANDIDATES = tuple(sorted(DB.glob("045_本社下処理_*.sql")))
SQL_045 = SQL_045_CANDIDATES[0] if len(SQL_045_CANDIDATES) == 1 else None
BASE_MIGRATIONS = (
    DB / "016_本社_第1段階.sql",
    DB / "019_本社_第2段階.sql",
    DB / "022_本社_作業の削除と仕入れ価格表.sql",
    DB / "023_本社_使用期限とトレース表.sql",
    DB / "042_本社下処理_作業中の原料追加と使用量保存.sql",
)
SCRATCH = Path("/tmp/jai-scratch/c116-sql-tests")
TIMEOUT = 40
ADMIN = "00000000-0000-0000-0000-000000000001"
WORKER = "00000000-0000-0000-0000-000000000002"
PREP = "00000000-0000-0000-0000-000000000003"
OTHER = "00000000-0000-0000-0000-000000000004"
LOT_1 = "10000000-0000-0000-0000-000000000001"
LOT_2 = "10000000-0000-0000-0000-000000000002"
MASTER_1 = "20000000-0000-0000-0000-000000000001"
MASTER_2 = "20000000-0000-0000-0000-000000000002"
MASTER_3 = "20000000-0000-0000-0000-000000000003"
STAFF_1 = "30000000-0000-0000-0000-000000000001"
STAFF_2 = "30000000-0000-0000-0000-000000000002"
STAFF_3 = "30000000-0000-0000-0000-000000000003"


def find_pg_bin():
    path = shutil.which("initdb")
    if path:
        return Path(path).parent
    choices = sorted(Path("/usr/lib/postgresql").glob("*/bin/initdb"))
    return choices[-1].parent if choices else None


BIN = find_pg_bin()

PRE_016_SCHEMA = r'''
create extension if not exists pgcrypto;
create schema auth;
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('app.user', true), '')::uuid
$$;
create table public.profiles (
  id uuid primary key,
  role text not null,
  active boolean not null default true,
  display_name text
);
create table public.qr_lots (
  id uuid primary key default gen_random_uuid(),
  lot_no text unique,
  qr_key text unique,
  active boolean not null default true,
  status text,
  current_qty numeric not null default 0,
  received_qty numeric,
  total_weight numeric,
  received_date date,
  item_name text,
  origin text,
  supplier text,
  cooperative_name text,
  container_type text,
  pack_weight text,
  purchase_staff text,
  purchase_staff_profile_id uuid
);
create table public.qr_lot_movements (
  id uuid primary key default gen_random_uuid(),
  operation_id uuid unique,
  reversed_operation_id uuid,
  lot_id uuid references public.qr_lots(id),
  movement_type text,
  destination text,
  cancelled_at timestamptz,
  lot_no text,
  item_name text,
  origin text,
  supplier text,
  cooperative_name text,
  container_type text,
  qty numeric,
  weight numeric,
  occurred_at timestamptz not null default now(),
  user_name text,
  memo text,
  operation_meta jsonb not null default '{}'::jsonb
);
create table public.qr_storage_limits_v1250 (
  item_name text primary key,
  limit_days integer,
  sort_order integer
);
create table public.purchase_prices (
  item_name text,
  price_type text,
  supplier text,
  price_yen_per_kg numeric,
  week_start date
);
create table public.hq_normal_items_v1410 (
  name text primary key,
  active boolean not null default true,
  sort_order integer not null default 0
);
create table public.hq_normal_counts_v1410 (
  count_date date not null,
  item_name text not null,
  pack_weight_kg numeric,
  cases numeric,
  bara_kg numeric,
  total_kg numeric,
  user_id uuid,
  user_name text,
  updated_at timestamptz not null default now(),
  primary key (count_date, item_name)
);
create function public.seika_item_name_group_v1200(p_name text)
returns text[] language sql immutable as $$ select array[p_name] $$;
create role anon;
create role authenticated;
create role service_role;
insert into public.profiles(id, role, active, display_name) values
  ('00000000-0000-0000-0000-000000000001', 'admin', true, '管理者'),
  ('00000000-0000-0000-0000-000000000002', 'hq_worker', true, '本社社員'),
  ('00000000-0000-0000-0000-000000000003', 'hq_prep', true, '下処理班'),
  ('00000000-0000-0000-0000-000000000004', 'viewer', true, '閲覧者');
'''


class IsolatedPostgres:
    """root・一般ユーザーの両方で使えるローカル専用の一時PostgreSQL。"""

    def __init__(self):
        self.runner = []
        if os.geteuid() == 0:
            if not shutil.which("runuser"):
                raise unittest.SkipTest("root requires runuser for disposable PostgreSQL")
            try:
                pwd.getpwnam("postgres")
            except KeyError:
                raise unittest.SkipTest("root requires a postgres OS user for disposable PostgreSQL")
            self.runner = ["runuser", "-u", "postgres", "--"]
        SCRATCH.mkdir(parents=True, exist_ok=True)
        if self.runner:
            os.chmod(SCRATCH, 0o777)
        self.tmp = tempfile.TemporaryDirectory(prefix="pg-", dir=SCRATCH)
        self.root = Path(self.tmp.name)
        self.data = self.root / "data"
        self.log = self.root / "postgres.log"
        if self.runner:
            os.chmod(self.root, 0o777)
        self.socket = str(self.root)
        self.port = "55445"
        self.base = []

    def command(self, command):
        result = subprocess.run(command, text=True, capture_output=True, timeout=TIMEOUT)
        if result.returncode:
            log = self.log.read_text(encoding="utf-8") if self.log.exists() else ""
            raise AssertionError(f"PostgreSQL準備失敗: {command}\n{result.stdout}\n{result.stderr}\n{log}")
        return result

    def start(self):
        self.command(self.runner + [str(BIN / "initdb"), "-D", str(self.data), "-A", "trust", "-U", "postgres"])
        self.command(self.runner + [
            str(BIN / "pg_ctl"), "-D", str(self.data), "-l", str(self.log),
            "-o", f"-p {self.port} -h '' -k {self.socket}", "-w", "start",
        ])
        self.base = [
            str(BIN / "psql"), "-h", self.socket, "-p", self.port, "-U", "postgres",
            "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-X",
        ]

    def close(self):
        try:
            if self.data.exists():
                subprocess.run(self.runner + [str(BIN / "pg_ctl"), "-D", str(self.data), "-m", "immediate", "-w", "stop"],
                               text=True, capture_output=True, timeout=TIMEOUT)
        finally:
            self.tmp.cleanup()

    def sql(self, sql, tuples=False):
        result = subprocess.run(self.base + (["-At"] if tuples else []) + ["-c", sql], text=True,
                                capture_output=True, timeout=TIMEOUT)
        if result.returncode:
            raise AssertionError(result.stderr + "\nSQL:\n" + sql)
        return result.stdout.strip()

    def file(self, path):
        result = subprocess.run(self.base + ["-f", str(path)], text=True, capture_output=True, timeout=TIMEOUT)
        if result.returncode:
            raise AssertionError(result.stderr + f"\nMigration: {path}")
        return result.stdout


class PrepWorkSqlRuntimeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not BIN or not (BIN / "initdb").exists() or not (BIN / "pg_ctl").exists():
            raise unittest.SkipTest("PostgreSQL binaries unavailable")
        if SQL_045 is None:
            raise unittest.SkipTest("DB045 is not available yet; this test is ready for its migration")
        cls.pg = IsolatedPostgres()
        cls.addClassCleanup(cls.pg.close)
        cls.pg.start()
        cls.pg.sql(PRE_016_SCHEMA)
        for migration in BASE_MIGRATIONS:
            cls.pg.file(migration)
        cls.pg.file(SQL_045)

    def sql(self, sql, tuples=False):
        return self.pg.sql(sql, tuples)

    def call(self, role, function, *args):
        rendered = ",".join(args)
        return json.loads(self.sql(f"set app.\"user\" = '{role}'; select {function}({rendered});", True).splitlines()[-1])

    def reset(self):
        self.sql("""
          truncate public.hq_work_pauses_v1199c116,
            public.hq_prep_operations_v1199c116, public.hq_work_members_v1500,
            public.hq_work_materials_v1500,
            public.hq_waste_v1500, public.hq_lot_movements_v1400,
            public.hq_works_v1500, public.hq_lots_v1400,
            public.hq_prep_masters_v1500, public.hq_staff_v1500 restart identity cascade;
          insert into public.hq_lots_v1400(id, lot_no, qr_key, source_kind, item_name, unit,
              current_qty, received_qty, planned_qty, status, pack_weight)
          values
            ('10000000-0000-0000-0000-000000000001','H-001','HQ-001','本社直接入荷','人参','kg',20,20,20,'在庫あり',null),
            ('10000000-0000-0000-0000-000000000002','H-002','HQ-002','本社直接入荷','人参','kg',10,10,10,'在庫あり',null);
          insert into public.hq_prep_masters_v1500(id,item_name,name,default_pack_kg,expiry_days,active)
          values
            ('20000000-0000-0000-0000-000000000001','人参','皮むき人参',10,2,true),
            ('20000000-0000-0000-0000-000000000002','キャベツ','1/4芯',10,2,true),
            ('20000000-0000-0000-0000-000000000003','キャベツ','1/4葉',10,2,true);
          insert into public.hq_staff_v1500(id,qr_key,team,name,print_group) values
            ('30000000-0000-0000-0000-000000000001','S-001','下処理班①','作業者1',1),
            ('30000000-0000-0000-0000-000000000002','S-002','下処理班①','作業者2',1),
            ('30000000-0000-0000-0000-000000000003','S-003','下処理班②','作業者3',2);
          update public.hq_settings_v1500 set value='true'::jsonb where key='stage2_stock';
        """)

    def start(self, operation="40000000-0000-0000-0000-000000000001", master=MASTER_1, lots="array['10000000-0000-0000-0000-000000000001'::uuid]", staff="array['30000000-0000-0000-0000-000000000001'::uuid]"):
        return self.call(ADMIN, "public.hq_work_start_v1199c116", f"'{operation}'::uuid", "'下処理'", "null", "'下処理室①'", f"array['{master}'::uuid]", lots, staff)

    def material_json(self, work_id, qtys=(10,)):
        ids = self.sql(f"select id from public.hq_work_materials_v1500 where work_id='{work_id}' order by lot_id", True).splitlines()
        self.assertEqual(len(ids), len(qtys), "fixture quantities must cover every work material")
        return "jsonb_build_array(" + ",".join(
            f"jsonb_build_object('id','{material_id}','qty',{qty})" for material_id, qty in zip(ids, qtys)
        ) + ")"

    def correction_material_json(self, work_id, qtys=(8,)):
        lots = self.sql(f"select lot_id from public.hq_work_materials_v1500 where work_id='{work_id}' order by lot_id", True).splitlines()
        self.assertEqual(len(lots), len(qtys), "fixture quantities must cover every work material")
        return "jsonb_build_array(" + ",".join(
            f"jsonb_build_object('lot_id','{lot_id}','qty',{qty})" for lot_id, qty in zip(lots, qtys)
        ) + ")"

    def finish_inputs(self, work_id, outputs="jsonb_build_array(jsonb_build_object('master_id','20000000-0000-0000-0000-000000000001','yield_kg',8))", qtys=(10,)):
        materials = self.material_json(work_id, qtys)
        self.call(PREP, "public.hq_work_end_v1500", f"'{work_id}'::uuid")
        return self.call(PREP, "public.hq_work_save_inputs_v1199c116", f"'{work_id}'::uuid", materials, "1", outputs)

    def confirm(self, work_id, operation="40000000-0000-0000-0000-000000000010", outputs="jsonb_build_array(jsonb_build_object('master_id','20000000-0000-0000-0000-000000000001','yield_kg',8))", qtys=(10,), reason="'確認'"):
        return self.call(ADMIN, "public.hq_prep_confirm_v1199c116", f"'{work_id}'::uuid", self.material_json(work_id, qtys), "1", outputs, reason)

    def assert_denied(self, role, function, *args):
        with self.assertRaises(AssertionError):
            self.call(role, function, *args)

    def test_real_baseline_and_045_are_applied_with_api_contracts(self):
        for procedure in (
            "hq_work_start_v1199c116(uuid,text,text,text,uuid[],uuid[],uuid[])",
            "hq_work_save_inputs_v1199c116(uuid,jsonb,numeric,jsonb)",
            "hq_prep_confirm_v1199c116(uuid,jsonb,numeric,jsonb,text)",
            "hq_prep_correct_v1199c116(uuid,uuid,timestamptz,jsonb,numeric,jsonb,text)",
            "hq_work_pause_v1199c116(uuid,uuid,text,uuid[])",
            "hq_work_resume_v1199c116(uuid,uuid,uuid[])",
            "hq_work_break_add_v1199c116(uuid,uuid,timestamptz,timestamptz,uuid[])",
        ):
            self.assertEqual(self.sql(f"select to_regprocedure('public.{procedure}') is not null", True), "t")
        columns = self.sql("select string_agg(column_name,',' order by ordinal_position) from information_schema.columns where table_schema='public' and table_name='hq_work_pauses_v1199c116'", True).split(',')
        self.assertEqual(columns[:10], ["id", "operation_id", "work_id", "kind", "start_at", "end_at", "staff_ids", "resumed_staff_ids", "by_name", "excluded_staff_ids"])

    def test_045_reapply_preserves_existing_movement_types_and_adds_only_correction_types(self):
        self.reset()
        before = self.sql("select pg_get_constraintdef(oid) from pg_constraint where conrelid='public.hq_lot_movements_v1400'::regclass and conname='hq_lot_movements_v1400_movement_type_check'", True)
        self.pg.file(SQL_045)
        self.assertEqual(self.sql("select pg_get_constraintdef(oid) from pg_constraint where conrelid='public.hq_lot_movements_v1400'::regclass and conname='hq_lot_movements_v1400_movement_type_check'", True), before)
        for kind in ('入庫確定', '出庫', '実数調整', '取消', '出庫取消', '受入取消', '下処理使用', '下処理取消', '廃棄', '廃棄取消', '下処理訂正', '下処理訂正取消'):
            self.sql(f"insert into public.hq_lot_movements_v1400(operation_id,lot_id,movement_type,qty,unit) values(gen_random_uuid(),'{LOT_1}','{kind}',1,'kg')")
        self.assertEqual(self.sql("select count(*) from public.hq_lot_movements_v1400", True), "12")

    def test_prep_start_and_outputs_support_allowed_multiple_masters_and_legacy_single_master(self):
        self.reset()
        self.sql(f"update public.hq_lots_v1400 set item_name='キャベツ' where id in ('{LOT_1}','{LOT_2}')")
        work = self.call(ADMIN, "public.hq_work_start_v1199c116", "'40000000-0000-0000-0000-000000000002'::uuid", "'下処理'", "null", "'下処理室①'", f"array['{MASTER_2}'::uuid,'{MASTER_3}'::uuid]", f"array['{LOT_1}'::uuid,'{LOT_2}'::uuid]", f"array['{STAFF_2}'::uuid]")["id"]
        self.assertEqual(self.sql(f"select coalesce(pause_kind,'')||':'||jsonb_array_length(outputs) from public.hq_works_v1500 where id='{work}'", True), ":2")
        outputs = f"jsonb_build_array(jsonb_build_object('master_id','{MASTER_2}','yield_kg',5),jsonb_build_object('master_id','{MASTER_3}','yield_kg',3))"
        self.finish_inputs(work, outputs, qtys=(10, 10))
        self.confirm(work, outputs=outputs, qtys=(10, 10))
        self.assertEqual(self.sql(f"select current_qty from public.hq_lots_v1400 where id='{LOT_1}'", True), "10")
        self.assertEqual(self.sql(f"select jsonb_array_length(outputs) from public.hq_works_v1500 where id='{work}'", True), "2")
        self.reset()
        legacy = self.start()["id"]
        self.finish_inputs(legacy)
        self.assertTrue(self.confirm(legacy)["ok"])
        self.assertEqual(self.sql(f"select jsonb_array_length(outputs) from public.hq_works_v1500 where id='{legacy}'", True), "1")

    def test_correct_after_confirm_reverses_and_reapplies_stock_audits_reason_and_is_idempotent(self):
        self.reset()
        work = self.start()["id"]
        self.finish_inputs(work)
        self.confirm(work)
        expected = self.sql(f"select updated_at from public.hq_works_v1500 where id='{work}'", True)
        args = (f"'{work}'::uuid", "'40000000-0000-0000-0000-000000000020'::uuid", f"'{expected}'::timestamptz", self.correction_material_json(work, (8,)), "2", "jsonb_build_array(jsonb_build_object('master_id','20000000-0000-0000-0000-000000000001','yield_kg',6))", "'数量訂正'")
        corrected = self.call(ADMIN, "public.hq_prep_correct_v1199c116", *args)
        self.assertTrue(corrected["ok"])
        self.assertEqual(self.sql(f"select current_qty from public.hq_lots_v1400 where id='{LOT_1}'", True), "12")
        self.assertEqual(self.sql(f"select count(*) from public.hq_lot_movements_v1400 where work_id='{work}' and movement_type='下処理訂正'", True), "1")
        self.assertIn("数量訂正", self.sql(f"select history::text from public.hq_works_v1500 where id='{work}'", True))
        self.assertTrue(self.call(ADMIN, "public.hq_prep_correct_v1199c116", *args).get("idempotent"))
        self.assert_denied(PREP, "public.hq_prep_correct_v1199c116", *args)
        self.assert_denied(OTHER, "public.hq_prep_correct_v1199c116", *args)

    def test_correct_requires_reason_and_current_expected_updated_at(self):
        self.reset()
        work = self.start()["id"]
        self.finish_inputs(work)
        self.confirm(work)
        stale = self.sql(f"select updated_at from public.hq_works_v1500 where id='{work}'", True)
        self.sql(f"update public.hq_works_v1500 set updated_at = updated_at + interval '1 second' where id='{work}'")
        common = (f"'{work}'::uuid", "'40000000-0000-0000-0000-000000000021'::uuid", f"'{stale}'::timestamptz", self.correction_material_json(work), "1", "jsonb_build_array(jsonb_build_object('master_id','20000000-0000-0000-0000-000000000001','yield_kg',8))")
        stale_result = self.call(ADMIN, "public.hq_prep_correct_v1199c116", *common, "'理由'")
        self.assertTrue(stale_result.get("conflict"), stale_result)
        expected = self.sql(f"select updated_at from public.hq_works_v1500 where id='{work}'", True)
        self.assert_denied(ADMIN, "public.hq_prep_correct_v1199c116", f"'{work}'::uuid", "'40000000-0000-0000-0000-000000000022'::uuid", f"'{expected}'::timestamptz", self.correction_material_json(work), "1", "jsonb_build_array(jsonb_build_object('master_id','20000000-0000-0000-0000-000000000001','yield_kg',8))", "''")

    def test_correction_failure_is_atomic_and_can_change_lot_without_inventory_effect_when_stock_is_off(self):
        self.reset()
        work = self.start()["id"]
        self.finish_inputs(work)
        self.confirm(work)
        expected = self.sql(f"select updated_at from public.hq_works_v1500 where id='{work}'", True)
        before = self.sql(f"select current_qty from public.hq_lots_v1400 where id='{LOT_1}'", True)
        self.assert_denied(ADMIN, "public.hq_prep_correct_v1199c116", f"'{work}'::uuid", "'40000000-0000-0000-0000-000000000023'::uuid", f"'{expected}'::timestamptz", "jsonb_build_array(jsonb_build_object('lot_id','10000000-0000-0000-0000-000000000001','qty',1000))", "1", "jsonb_build_array(jsonb_build_object('master_id','20000000-0000-0000-0000-000000000001','yield_kg',8))", "'不足確認'")
        self.assertEqual(self.sql(f"select current_qty from public.hq_lots_v1400 where id='{LOT_1}'", True), before)
        self.assertEqual(self.sql(f"select qty from public.hq_work_materials_v1500 where work_id='{work}' and lot_id='{LOT_1}'", True), "10")

        self.reset()
        self.sql("update public.hq_settings_v1500 set value='false'::jsonb where key='stage2_stock'")
        work = self.start()["id"]
        self.finish_inputs(work)
        self.confirm(work)
        expected = self.sql(f"select updated_at from public.hq_works_v1500 where id='{work}'", True)
        self.assertTrue(self.call(ADMIN, "public.hq_prep_correct_v1199c116", f"'{work}'::uuid", "'40000000-0000-0000-0000-000000000024'::uuid", f"'{expected}'::timestamptz", f"jsonb_build_array(jsonb_build_object('lot_id','{LOT_2}','qty',8))", "1", "jsonb_build_array(jsonb_build_object('master_id','20000000-0000-0000-0000-000000000001','yield_kg',8))", "'ロット変更'")["ok"])
        self.assertEqual(self.sql(f"select current_qty from public.hq_lots_v1400 where id='{LOT_1}'", True), "20")
        self.assertEqual(self.sql(f"select current_qty from public.hq_lots_v1400 where id='{LOT_2}'", True), "10")

    def test_correction_accepts_inactive_historical_master_and_delete_leaves_no_fk_blocker(self):
        self.reset()
        work = self.start()["id"]
        self.finish_inputs(work)
        self.confirm(work)
        self.sql(f"update public.hq_prep_masters_v1500 set active=false where id='{MASTER_1}'")
        expected = self.sql(f"select updated_at from public.hq_works_v1500 where id='{work}'", True)
        self.assertTrue(self.call(ADMIN, "public.hq_prep_correct_v1199c116", f"'{work}'::uuid", "'40000000-0000-0000-0000-000000000025'::uuid", f"'{expected}'::timestamptz", self.correction_material_json(work, (8,)), "1", "jsonb_build_array(jsonb_build_object('master_id','20000000-0000-0000-0000-000000000001','yield_kg',7))", "'停止マスタ訂正'")["ok"])
        self.assertTrue(self.call(ADMIN, "public.hq_work_delete_v1500", f"'{work}'::uuid")["ok"])
        self.assertEqual(self.sql(f"select count(*) from public.hq_work_pauses_v1199c116 where work_id='{work}'", True), "0")
        self.assertEqual(self.sql("select count(*) from public.hq_prep_operations_v1199c116 where work_id is null and operation_id='40000000-0000-0000-0000-000000000025'::uuid", True), "1")

    def test_partial_resume_keeps_pause_until_every_paused_member_returns_and_rejects_end(self):
        self.reset()
        work = self.start(staff=f"array['{STAFF_1}'::uuid,'{STAFF_2}'::uuid]")["id"]
        pause_args = (f"'{work}'::uuid", "'40000000-0000-0000-0000-000000000030'::uuid", "'休憩'", "'{}'::uuid[]")
        self.assertTrue(self.call(WORKER, "public.hq_work_pause_v1199c116", *pause_args)["ok"])
        self.assertTrue(self.call(ADMIN, "public.hq_work_resume_v1199c116", f"'{work}'::uuid", "'40000000-0000-0000-0000-000000000031'::uuid", f"array['{STAFF_1}'::uuid]")["ok"])
        self.assertEqual(self.sql(f"select pause_kind from public.hq_works_v1500 where id='{work}'", True), "休憩")
        self.assertEqual(self.sql(f"select resumed_staff_ids::text from public.hq_work_pauses_v1199c116 where work_id='{work}'", True), "{30000000-0000-0000-0000-000000000001}")
        self.assert_denied(PREP, "public.hq_work_end_v1500", f"'{work}'::uuid")
        self.assert_denied(PREP, "public.hq_work_resume_v1199c116", f"'{work}'::uuid", "'40000000-0000-0000-0000-000000000032'::uuid", f"array['{STAFF_1}'::uuid]")
        self.assertTrue(self.call(PREP, "public.hq_work_resume_v1199c116", f"'{work}'::uuid", "'40000000-0000-0000-0000-000000000033'::uuid", f"array['{STAFF_2}'::uuid]")["ok"])
        self.assertEqual(self.sql(f"select pause_kind from public.hq_works_v1500 where id='{work}'", True), "")
        self.assertTrue(self.call(PREP, "public.hq_work_end_v1500", f"'{work}'::uuid")["ok"])

    def test_resume_replays_are_safe_and_reject_changed_payload_or_busy_staff(self):
        self.reset()
        work = self.start(staff=f"array['{STAFF_1}'::uuid,'{STAFF_2}'::uuid]")["id"]
        self.call(WORKER, "public.hq_work_pause_v1199c116", f"'{work}'::uuid", "'40000000-0000-0000-0000-000000000034'::uuid", "'中断'", "'{}'::uuid[]")
        resume = (f"'{work}'::uuid", "'40000000-0000-0000-0000-000000000035'::uuid", f"array['{STAFF_1}'::uuid,'{STAFF_2}'::uuid]")
        self.assertTrue(self.call(PREP, "public.hq_work_resume_v1199c116", *resume)["ok"])
        replay = self.call(PREP, "public.hq_work_resume_v1199c116", *resume)
        self.assertTrue(replay.get("already") or replay.get("idempotent"), replay)
        changed = self.call(PREP, "public.hq_work_resume_v1199c116", f"'{work}'::uuid", "'40000000-0000-0000-0000-000000000035'::uuid", f"array['{STAFF_1}'::uuid]")
        self.assertTrue(changed.get("idempotency_conflict"), changed)

        self.reset()
        work = self.start(staff=f"array['{STAFF_1}'::uuid,'{STAFF_2}'::uuid]")["id"]
        self.call(WORKER, "public.hq_work_pause_v1199c116", f"'{work}'::uuid", "'40000000-0000-0000-0000-000000000036'::uuid", "'中断'", "'{}'::uuid[]")
        other = self.start(operation="40000000-0000-0000-0000-000000000037", master=MASTER_1, staff=f"array['{STAFF_3}'::uuid]")["id"]
        self.call(ADMIN, "public.hq_work_leave_v1500", f"'{other}'::uuid", f"'{STAFF_3}'::uuid")
        self.call(ADMIN, "public.hq_work_join_v1500", f"'{other}'::uuid", f"array['{STAFF_1}'::uuid]")
        self.assert_denied(WORKER, "public.hq_work_resume_v1199c116", f"'{work}'::uuid", "'40000000-0000-0000-0000-000000000038'::uuid", f"array['{STAFF_1}'::uuid]")

    def test_backdated_break_accepts_hq_prep_replays_safely_and_limits_to_overlap(self):
        self.reset()
        work = self.start(staff=f"array['{STAFF_1}'::uuid]")["id"]
        midpoint = f"(select started_at + interval '1 microsecond' from public.hq_works_v1500 where id='{work}')"
        start = midpoint
        end = f"(select started_at + interval '2 microseconds' from public.hq_works_v1500 where id='{work}')"
        args = (f"'{work}'::uuid", "'40000000-0000-0000-0000-000000000039'::uuid", start, end, "'{}'::uuid[]")
        self.assertTrue(self.call(PREP, "public.hq_work_break_add_v1199c116", *args)["ok"])
        self.assertTrue(self.call(PREP, "public.hq_work_break_add_v1199c116", *args).get("already"))
        self.assert_denied(PREP, "public.hq_work_break_add_v1199c116", f"'{work}'::uuid", "'40000000-0000-0000-0000-000000000039'::uuid", start, f"(select started_at + interval '3 microseconds' from public.hq_works_v1500 where id='{work}')", "'{}'::uuid[]")
        self.assertEqual(self.sql(f"select count(*) from public.hq_work_members_v1500 where work_id='{work}' and staff_id='{STAFF_1}'", True), "2")

        self.reset()
        work = self.start(staff=f"array['{STAFF_1}'::uuid]")["id"]
        joined = self.start(operation="40000000-0000-0000-0000-000000000041", master=MASTER_1, staff=f"array['{STAFF_2}'::uuid]")["id"]
        self.call(ADMIN, "public.hq_work_leave_v1500", f"'{joined}'::uuid", f"'{STAFF_2}'::uuid")
        self.call(ADMIN, "public.hq_work_join_v1500", f"'{work}'::uuid", f"array['{STAFF_2}'::uuid]")
        self.assertTrue(self.call(PREP, "public.hq_work_break_add_v1199c116", f"'{work}'::uuid", "'40000000-0000-0000-0000-000000000042'::uuid", f"(select started_at + interval '1 microsecond' from public.hq_works_v1500 where id='{work}')", f"(select started_at + interval '2 microseconds' from public.hq_works_v1500 where id='{work}')", "'{}'::uuid[]")["ok"])
        self.assertEqual(self.sql(f"select staff_ids::text from public.hq_work_pauses_v1199c116 where work_id='{work}' and kind='後入力休憩'", True), "{30000000-0000-0000-0000-000000000001}")
        self.assert_denied(PREP, "public.hq_work_break_add_v1199c116", f"'{work}'::uuid", "'40000000-0000-0000-0000-000000000043'::uuid", f"(select started_at + interval '1 microsecond' from public.hq_works_v1500 where id='{work}')", f"(select started_at + interval '2 microseconds' from public.hq_works_v1500 where id='{work}')", "'{}'::uuid[]")
        self.assert_denied(PREP, "public.hq_work_break_add_v1199c116", f"'{work}'::uuid", "'40000000-0000-0000-0000-000000000044'::uuid", "now()+interval '1 minute'", "now()+interval '2 minutes'", "'{}'::uuid[]")

    def test_pause_permissions_duplicate_operations_and_break_validation(self):
        self.reset()
        work = self.start()["id"]
        args = (f"'{work}'::uuid", "'40000000-0000-0000-0000-000000000040'::uuid", "'中断'", "'{}'::uuid[]")
        self.assertTrue(self.call(PREP, "public.hq_work_pause_v1199c116", *args)["ok"])
        self.assert_denied(OTHER, "public.hq_work_pause_v1199c116", *args)
        self.assertTrue(self.call(ADMIN, "public.hq_work_pause_v1199c116", *args).get("already"))
        self.assert_denied(PREP, "public.hq_work_break_add_v1199c116", f"'{work}'::uuid", "'40000000-0000-0000-0000-000000000043'::uuid", "now()-interval '2 minutes'", "now()-interval '1 minute'", "'{}'::uuid[]")
        self.assert_denied(OTHER, "public.hq_work_break_add_v1199c116", f"'{work}'::uuid", "'40000000-0000-0000-0000-000000000041'::uuid", "now()-interval '2 minutes'", "now()-interval '1 minute'", "'{}'::uuid[]")
        self.assert_denied(ADMIN, "public.hq_work_break_add_v1199c116", f"'{work}'::uuid", "'40000000-0000-0000-0000-000000000042'::uuid", "now()", "now()-interval '1 minute'", "'{}'::uuid[]")

    def test_concurrent_same_correction_operation_has_one_stock_effect(self):
        self.reset()
        work = self.start()["id"]
        self.finish_inputs(work)
        self.confirm(work)
        expected = self.sql(f"select updated_at from public.hq_works_v1500 where id='{work}'", True)
        statement = (
            f"set app.\"user\"='{ADMIN}'; select public.hq_prep_correct_v1199c116("
            f"'{work}'::uuid,'40000000-0000-0000-0000-000000000050'::uuid,'{expected}'::timestamptz,"
            f"{self.correction_material_json(work, (8,))},2,jsonb_build_array(jsonb_build_object('master_id','{MASTER_1}','yield_kg',6)),'同時再送');"
        )
        results = []
        def invoke():
            results.append(self.pg.sql(statement, True).splitlines()[-1])
        threads = [threading.Thread(target=invoke) for _ in range(2)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(TIMEOUT)
        self.assertFalse(any(thread.is_alive() for thread in threads))
        self.assertEqual(sum(json.loads(result)["ok"] for result in results), 2)
        self.assertEqual(self.sql(f"select current_qty from public.hq_lots_v1400 where id='{LOT_1}'", True), "12")
        self.assertEqual(self.sql("select count(*) from public.hq_lot_movements_v1400 where work_id='%s' and movement_type='下処理訂正'" % work, True), "1")


    def outputs(self, value=8):
        return f"jsonb_build_array(jsonb_build_object('master_id','{MASTER_1}','yield_kg',{value}))"

    def correction_args(self, work, materials=None, outputs=None):
        expected = self.sql(f"select updated_at from public.hq_works_v1500 where id='{work}'", True)
        return (f"'{work}'::uuid", "gen_random_uuid()", f"'{expected}'::timestamptz",
                materials or self.correction_material_json(work), "1", outputs or self.outputs(), "'訂正理由'")

    def test_first_confirmation_needs_no_reason_and_same_retry_does_not_move_stock_twice(self):
        self.reset()
        work = self.start()["id"]
        self.finish_inputs(work)
        self.assertTrue(self.confirm(work, reason="null")["ok"])
        self.assertTrue(self.confirm(work, reason="null").get("already"))
        self.assertEqual(self.sql(f"select current_qty from public.hq_lots_v1400 where id='{LOT_1}'", True), "10")
        self.assertEqual(self.sql(f"select count(*) from public.hq_lot_movements_v1400 where work_id='{work}'", True), "1")
        self.assert_denied(ADMIN, "public.hq_prep_confirm_v1199c116", f"'{work}'::uuid", self.material_json(work), "1", self.outputs(7), "null")

    def test_input_waiting_correction_does_not_create_waste_or_apply_inventory(self):
        self.reset()
        work = self.start()["id"]
        self.finish_inputs(work)
        self.assertTrue(self.call(WORKER, "public.hq_prep_correct_v1199c116", *self.correction_args(work, outputs=self.outputs(7)))["ok"])
        self.assertEqual(self.sql(f"select current_qty from public.hq_lots_v1400 where id='{LOT_1}'", True), "20")
        self.assertEqual(self.sql(f"select count(*) from public.hq_waste_v1500 where work_id='{work}'", True), "0")
        self.assertTrue(self.confirm(work, outputs=self.outputs(7), qtys=(8,))["ok"])
        self.assertEqual(self.sql(f"select current_qty from public.hq_lots_v1400 where id='{LOT_1}'", True), "12")
        self.assertEqual(self.sql(f"select count(*) from public.hq_waste_v1500 where work_id='{work}' and cancelled_at is null", True), "1")

    def test_correction_changes_lot_then_cancel_restores_net_quantity(self):
        self.reset()
        work = self.start()["id"]
        self.finish_inputs(work)
        self.confirm(work)
        materials = f"jsonb_build_array(jsonb_build_object('lot_id','{LOT_2}','qty',8))"
        self.assertTrue(self.call(WORKER, "public.hq_prep_correct_v1199c116", *self.correction_args(work, materials))["ok"])
        self.assertEqual(self.sql(f"select current_qty from public.hq_lots_v1400 where id='{LOT_1}'", True), "20")
        self.assertEqual(self.sql(f"select current_qty from public.hq_lots_v1400 where id='{LOT_2}'", True), "2")
        self.assertTrue(self.call(WORKER, "public.hq_prep_cancel_v1500", f"'{work}'::uuid", "'取消理由'")["ok"])
        self.assertEqual(self.sql(f"select current_qty from public.hq_lots_v1400 where id='{LOT_1}'", True), "20")
        self.assertEqual(self.sql(f"select current_qty from public.hq_lots_v1400 where id='{LOT_2}'", True), "10")
        self.assertEqual(self.sql(f"select count(*) from public.hq_waste_v1500 where work_id='{work}' and cancelled_at is null", True), "0")

    def test_missing_ids_and_nonfinite_numbers_are_rejected_atomically(self):
        self.reset()
        work = self.start()["id"]
        self.finish_inputs(work)
        self.confirm(work)
        base = self.correction_args(work)
        before = self.sql(f"select to_jsonb(w)::text from public.hq_works_v1500 w where id='{work}'", True)
        for materials in ("null", "'[]'::jsonb", "jsonb_build_array(jsonb_build_object('lot_id',null,'qty',1))"):
            with self.subTest(materials=materials):
                args = list(base)
                args[3] = materials
                self.assert_denied(ADMIN, "public.hq_prep_correct_v1199c116", *args)
        for outputs in ("null", "jsonb_build_array(jsonb_build_object('master_id',null,'yield_kg',8))",
                        f"jsonb_build_array(jsonb_build_object('master_id','{MASTER_1}','yield_kg','NaN'))"):
            with self.subTest(outputs=outputs):
                args = list(base)
                args[5] = outputs
                self.assert_denied(ADMIN, "public.hq_prep_correct_v1199c116", *args)
        self.assertEqual(self.sql(f"select to_jsonb(w)::text from public.hq_works_v1500 w where id='{work}'", True), before)

    def test_correction_preserves_historical_names_and_expiry_when_master_changes(self):
        self.reset()
        work = self.start()["id"]
        self.finish_inputs(work)
        self.confirm(work)
        snapshot = self.sql(f"select outputs->0->>'name'||':'||(outputs->0->>'expiry_days') from public.hq_works_v1500 where id='{work}'", True)
        self.sql(f"update public.hq_prep_masters_v1500 set name='変更後の名前',expiry_days=100,active=false where id='{MASTER_1}'")
        self.assertTrue(self.call(WORKER, "public.hq_prep_correct_v1199c116", *self.correction_args(work))["ok"])
        self.assertEqual(self.sql(f"select outputs->0->>'name'||':'||(outputs->0->>'expiry_days') from public.hq_works_v1500 where id='{work}'", True), snapshot)

    def test_break_splits_intersection_without_changing_excluded_staff_minutes(self):
        self.reset()
        work = self.start(staff=f"array['{STAFF_1}'::uuid,'{STAFF_2}'::uuid,'{STAFF_3}'::uuid]")["id"]
        self.sql(f"""update public.hq_works_v1500 set started_at=now()-interval '2 hours',ended_at=now(),status='入力待ち' where id='{work}';
          update public.hq_work_members_v1500 set start_at=now()-interval '2 hours',end_at=now() where work_id='{work}';
          update public.hq_work_members_v1500 set start_at=start_at+interval '70 minutes' where work_id='{work}' and staff_id='{STAFF_3}'""")
        args = (f"'{work}'::uuid", "gen_random_uuid()", f"(select started_at+interval '60 minutes' from public.hq_works_v1500 where id='{work}')",
                f"(select started_at+interval '75 minutes' from public.hq_works_v1500 where id='{work}')", f"array['{STAFF_2}'::uuid]")
        self.assertTrue(self.call(PREP, "public.hq_work_break_add_v1199c116", *args)["ok"])
        for staff, minutes in ((STAFF_1, 105), (STAFF_2, 120), (STAFF_3, 45)):
            total = float(self.sql(f"select sum(extract(epoch from end_at-start_at))/60 from public.hq_work_members_v1500 where work_id='{work}' and staff_id='{staff}'", True))
            self.assertAlmostEqual(total, minutes, places=2)

    def test_internal_helpers_are_not_callable_by_authenticated_or_anon(self):
        for function in ("hq_c116_nonnegative(text,text)", "hq_c116_work_outputs(public.hq_works_v1500,jsonb)",
                         "hq_prep_unapply_v1500(uuid,public.profiles)"):
            for role in ("authenticated", "anon"):
                self.assertEqual(self.sql(f"select has_function_privilege('{role}','public.{function}','execute')", True), "f")
        self.assertEqual(self.sql("select has_function_privilege('authenticated','public.hq_prep_correct_v1199c116(uuid,uuid,timestamptz,jsonb,numeric,jsonb,text)','execute')", True), "t")


if __name__ == "__main__":
    unittest.main()
