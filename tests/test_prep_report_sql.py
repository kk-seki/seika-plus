"""c117 本社下処理日報RPCを実際のSQLへローカルPostgreSQLだけで検証する。"""
import json
import threading
import unittest
from pathlib import Path

from test_prep_work_sql import (
    ADMIN,
    LOT_1,
    LOT_2,
    MASTER_1,
    MASTER_2,
    MASTER_3,
    OTHER,
    PREP,
    PRE_016_SCHEMA,
    STAFF_1,
    STAFF_2,
    STAFF_3,
    TIMEOUT,
    WORKER,
    IsolatedPostgres,
    BIN,
)

ROOT = Path(__file__).resolve().parents[1]
DB = ROOT / "db"
SQL_016 = DB / "016_本社_第1段階.sql"
MIGRATIONS_019_TO_045 = tuple(
    DB / f"{number:03d}_{name}.sql"
    for number, name in (
        (19, "本社_第2段階"),
        (20, "本社_スタッフ初期登録"),
        (21, "本社_下処理班①②の入れ替え"),
        (22, "本社_作業の削除と仕入れ価格表"),
        (23, "本社_使用期限とトレース表"),
        (24, "仕入れ価格を廃棄とトリミングに反映"),
        (25, "日報の廃棄を廃棄一覧へ自動反映"),
        (26, "入替品の候補"),
        (27, "スタッフQR作り直し_本社の月次管理_容量"),
        (28, "作業名と作業場所の削除"),
        (29, "棚卸し_規格別ロットの確定エラー修正"),
        (30, "自動バックアップの保存期間"),
        (31, "自動バックアップの容量を詰め直す"),
        (32, "本社入荷日を石岡の出庫時の日付にする"),
        (33, "本社直接入荷の入荷日を登録時の日付にする"),
        (34, "本社の品質写真を追加できるようにする"),
        (35, "本社直接入荷_石岡経由"),
        (36, "伝票_総重量と入数"),
        (37, "適正在庫の見直し記録を保存"),
        (38, "適正在庫の変更履歴を保存"),
        (39, "本社で石岡を見る_荷受けの下処理出庫"),
        (40, "本社下処理班と荷受け担当のトレース閲覧制限"),
        (41, "仕入れ担当者の変更を青果社員も保存できるようにする"),
        (42, "本社下処理_作業中の原料追加と使用量保存"),
        (43, "QR出庫数の当日訂正"),
        (44, "QR出庫数の訂正_実数調整後も可能"),
        (45, "本社下処理_訂正と休憩と同時製造"),
    )
)
SQL_046_CANDIDATES = tuple(sorted(DB.glob("046_本社下処理_*.sql")))

# 019〜045を通しで適用するため、016以前の本番スキーマのうち対象migrationが参照する
# 周辺テーブルだけをローカルfixtureに補う。本番接続・認証情報は一切用いない。
PRE_019_COMPAT = r'''
create table public.trimming_jobs (
  id uuid primary key default gen_random_uuid(), item_name text, origin text, supplier text,
  received_date date, work_date date, input_weight_kg numeric, waste_weight_kg numeric,
  purchase_price numeric, purchase_price_yen_per_kg numeric, input_cost_yen numeric,
  price_match_summary text, updated_at timestamptz default now()
);
create table public.trimming_job_materials (id uuid primary key default gen_random_uuid(), job_id uuid, lot_id uuid);
create table public.trimming_job_lots (id uuid primary key default gen_random_uuid(), trimming_job_id uuid, qr_key text, item_name text, origin text, supplier text, used_weight_kg numeric, purchase_price_yen_per_kg numeric, purchase_price_week_start date, price_match_type text, price_match_reason text, price_source_supplier text, price_average_count integer);
create table public.trim_output_candidates_v1680 (id uuid primary key default gen_random_uuid(), name text unique, active boolean default true, sort integer default 0);
create table public.hq_monthly_archives_v1690 (month date primary key, file_name text, created_at timestamptz default now(), confirmed_at timestamptz);
create table public.qr_slip_adjust_v1199c86 (movement_id uuid primary key, total_kg numeric, pack text, updated_at timestamptz default now());
create table public.optimal_stock_change_logs_v1199c89 (id text primary key, item_id text not null, item_name text, old_min numeric, old_max numeric, new_min numeric, new_max numeric, changed_by text, changed_by_id text, role text, memo text, changed_at timestamptz default now(), saved_by uuid, saved_at timestamptz default now());
create table public.app_state (id text primary key, data jsonb not null default '{}'::jsonb, updated_at timestamptz default now());
create table public.app_state_backups (id uuid primary key default gen_random_uuid(), created_at timestamptz default now());
create table public.app_state_backup_slots_v1167 (slot_id bigint, state_id text, slot_kind text, slot_key text, content_hash text, state_version text, snapshot_updated_at timestamptz, captured_at timestamptz default now(), captured_by uuid, operation_id uuid, note text);
create table public.app_state_backup_blobs_v1167 (content_hash text primary key, snapshot_data jsonb, data_bytes bigint, first_seen_at timestamptz default now(), first_state_id text, first_state_version text);
create table public.seika_reprice_log_v1620 (id uuid primary key default gen_random_uuid(), note text, result jsonb, created_at timestamptz default now());
create table public.seika_item_rules_v1600 (item_name text primary key, limit_days integer, ng_sign text, aliases text[] default '{}');
create table public.qr_lot_grade_adjustments (id uuid primary key default gen_random_uuid());
create table public.waste_records (id uuid primary key default gen_random_uuid(), waste_date date, item_name text, data jsonb default '{}'::jsonb, updated_at timestamptz default now());
create table public.qr_outbound_corrections_v1199c113 (id uuid primary key default gen_random_uuid());
create table public.qr_outbound_correction_lines_v1199c113 (id uuid primary key default gen_random_uuid());
alter table public.qr_lot_movements add column created_at timestamptz default now();
alter table public.qr_lot_movements add constraint c117_qr_movement_types check (movement_type in ('入庫','出庫','廃棄','取消','入庫・調整増','出庫・調整減','差分なし','調整','場所移動','重量確定','重量更新','ロット情報訂正'));
create table public.qr_lot_grades_v1300 (lot_id uuid, grade text, current_qty numeric default 0, updated_at timestamptz default now(), primary key(lot_id,grade));
create or replace function public.guard_seika_qr_write_v187() returns trigger language plpgsql as $$ begin return new; end $$;
create or replace function public.seika_require_role_v1240(p_roles text[]) returns void language plpgsql as $$ begin null; end $$;
create or replace function public.is_active_user() returns boolean language sql stable as $$ select true $$;
create or replace function public.seika_v1136_require_roles(p_roles text[]) returns public.profiles language sql stable as $$ select p from public.profiles p limit 1 $$;
create or replace function public.seika_qr_operation_cancelled_v1162(p_operation_id text) returns boolean language sql as $$ select false $$;
create or replace function public.seika_parse_kg_v1162(p_value text) returns numeric language sql as $$ select nullif(regexp_replace(coalesce(p_value,''),'[^0-9.]','','g'),'')::numeric $$;
create or replace function public.trimming_week_start(p_date date) returns date language sql immutable as $$ select date_trunc('week', p_date)::date $$;
create or replace function public.trimming_normalize_supplier_v1117(p_value text) returns text language sql immutable as $$ select btrim(coalesce(p_value,'')) $$;
'''


class PrepReportSqlRuntimeTests(unittest.TestCase):
    """046完成後に、019〜046を同じ使い捨てDBへ順に適用して契約を確認する。"""

    @classmethod
    def setUpClass(cls):
        if not BIN or not (BIN / "initdb").exists():
            raise unittest.SkipTest("PostgreSQL binaries unavailable")
        if len(SQL_046_CANDIDATES) != 1:
            raise unittest.SkipTest("DB046 is not available yet; c117 tests are ready for its migration")
        cls.sql_046 = SQL_046_CANDIDATES[0]
        cls.pg = IsolatedPostgres()
        cls.addClassCleanup(cls.pg.close)
        cls.pg.start()
        cls.pg.sql(PRE_016_SCHEMA)
        cls.pg.file(SQL_016)
        cls.pg.sql(PRE_019_COMPAT)
        for migration in MIGRATIONS_019_TO_045:
            cls.pg.file(migration)
        cls.pg.file(cls.sql_046)
        cls.pg.sql("grant select on public.profiles to authenticated")

    def sql(self, statement, tuples=False):
        return self.pg.sql(statement, tuples)

    def call(self, role, function, *args):
        rendered = ",".join(args)
        output = self.sql(
            f"set app.\"user\" = '{role}'; select {function}({rendered});", True
        )
        return json.loads(output.splitlines()[-1])

    def assert_denied(self, role, function, *args):
        with self.assertRaises(AssertionError):
            self.call(role, function, *args)

    def reset(self):
        self.sql("""
          truncate public.hq_prep_report_operations_v1199c117,
            public.hq_prep_standards_v1199c117,
            public.hq_work_pauses_v1199c116, public.hq_prep_operations_v1199c116,
            public.hq_work_members_v1500, public.hq_work_materials_v1500,
            public.hq_waste_v1500, public.hq_lot_movements_v1400,
            public.hq_works_v1500, public.hq_lots_v1400,
            public.hq_prep_masters_v1500, public.hq_staff_v1500 restart identity cascade;
          insert into public.hq_lots_v1400
            (id,lot_no,qr_key,source_kind,item_name,unit,current_qty,received_qty,planned_qty,status,pack_weight)
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

    def report(self, *, lot_id=LOT_1, qty=10, expected=20, materials=None, master_ids=None, outputs=None,
               members=None, breaks=None, start="'2026-11-10T08:00:00+00'::timestamptz", end="'2026-11-10T09:00:00+00'::timestamptz",
               work_date="'2026-11-10'::date"):
        master_ids = master_ids or [MASTER_1]
        materials = materials or [(lot_id, qty, "partial", expected)]
        outputs = outputs or [(MASTER_1, 8)]
        members = members or [(STAFF_1, "作業", start, end)]
        breaks = breaks or []
        masters = ",".join("'" + item + "'" for item in master_ids)
        material_rows = ",".join(
            "jsonb_build_object('lot_id','%s','qty',%s,'use_mode','%s','expected_available_qty',%s)"
            % (material_lot, material_qty, use_mode, available)
            for material_lot, material_qty, use_mode, available in materials
        )
        output_rows = ",".join(
            "jsonb_build_object('master_id','%s','yield_kg',%s)" % (item, value)
            for item, value in outputs
        )
        member_rows = ",".join(
            "jsonb_build_object('staff_id','%s','phase','%s','start_at',(%s),'end_at',(%s))"
            % (staff, phase, member_start, member_end)
            for staff, phase, member_start, member_end in members
        )
        break_rows = ",".join(
            "jsonb_build_object('kind','%s','start_at',(%s),'end_at',(%s),'excluded_staff_ids',%s)"
            % (kind, break_start, break_end, excluded)
            for kind, break_start, break_end, excluded in breaks
        )
        return "jsonb_build_object(" \
            f"'work_date',({work_date})::text,'started_at',({start}),'ended_at',({end}),'place','下処理室①'," \
            f"'master_ids',jsonb_build_array({masters}),'materials',jsonb_build_array({material_rows})," \
            f"'outputs',jsonb_build_array({output_rows}),'members',jsonb_build_array({member_rows})," \
            f"'breaks',jsonb_build_array({break_rows}))"

    def save(self, operation, report, work_id="null", expected="null", role=PREP):
        return self.call(
            role, "public.hq_prep_report_save_v1199c117",
            f"'{operation}'::uuid", work_id, expected, report,
        )

    def test_migrations_019_through_046_and_public_rpc_contracts_are_applied(self):
        self.assertEqual(len(MIGRATIONS_019_TO_045), 27)
        for procedure in (
            "hq_prep_available_lots_v1199c117(uuid)",
            "hq_prep_report_save_v1199c117(uuid,uuid,timestamptz,jsonb)",
            "hq_prep_standard_save_v1199c117(uuid[],numeric,numeric)",
        ):
            self.assertEqual(self.sql(f"select to_regprocedure('public.{procedure}') is not null", True), "t")

    def test_new_edit_full_report_and_history_audit(self):
        self.reset()
        created = self.save("41000000-0000-0000-0000-000000000001", self.report())
        self.assertTrue(created["ok"])
        work_id, updated = created["id"], created["updated_at"]
        self.assertEqual(self.sql(f"select status||':'||confirm_status from public.hq_works_v1500 where id='{work_id}'", True), "完了:未確定")
        changed = self.save("41000000-0000-0000-0000-000000000002", self.report(qty=9, outputs=[(MASTER_1, 7)]), f"'{work_id}'::uuid", f"'{updated}'::timestamptz")
        self.assertTrue(changed["ok"])
        history = self.sql(f"select history::text from public.hq_works_v1500 where id='{work_id}'", True)
        self.assertIn("作業者1", history)
        self.assertIn("before", history)
        self.assertIn("after", history)

    def test_acl_and_all_available_lots_include_zero_for_existing_edit_lot(self):
        self.reset()
        rows = self.call(PREP, "public.hq_prep_available_lots_v1199c117", "null")
        self.assertEqual({row["id"] for row in rows}, {LOT_1, LOT_2})
        self.assert_denied(OTHER, "public.hq_prep_available_lots_v1199c117", "null")
        self.assert_denied(OTHER, "public.hq_prep_report_save_v1199c117", "gen_random_uuid()", "null", "null", self.report())
        self.assert_denied(OTHER, "public.hq_prep_standard_save_v1199c117", f"array['{MASTER_1}'::uuid]", "90", "5")

    def test_reservation_concurrent_save_and_confirm_keep_remaining_stock_correct(self):
        self.reset()
        report = self.report(qty=15, expected=20, outputs=[(MASTER_1, 10)])
        results = []
        def invoke(operation):
            try:
                results.append(self.save(operation, report))
            except AssertionError as error:
                results.append({"error": str(error)})
        threads = [threading.Thread(target=invoke, args=(f"41000000-0000-0000-0000-00000000000{n}",)) for n in (3, 4)]
        for thread in threads: thread.start()
        for thread in threads: thread.join(TIMEOUT)
        self.assertFalse(any(thread.is_alive() for thread in threads))
        self.assertEqual(sum(bool(row.get("ok")) for row in results), 1, results)
        work = next(row["id"] for row in results if row.get("ok"))
        available = self.call(PREP, "public.hq_prep_available_lots_v1199c117", "null")
        self.assertEqual(next(row["available_qty"] for row in available if row["id"] == LOT_1), 5)
        material_id = self.sql(f"select id from public.hq_work_materials_v1500 where work_id='{work}'", True)
        self.call(ADMIN, "public.hq_prep_confirm_v1199c116", f"'{work}'::uuid", f"jsonb_build_array(jsonb_build_object('id','{material_id}','qty',15))", "5", "jsonb_build_array(jsonb_build_object('master_id','20000000-0000-0000-0000-000000000001','yield_kg',10))", "null")
        self.assertEqual(self.sql(f"select current_qty from public.hq_lots_v1400 where id='{LOT_1}'", True), "5")

    def test_invalid_raw_quantity_pair_and_times_are_rejected_without_writing(self):
        self.reset()
        invalid = (
            self.report(qty=-1),
            self.report(outputs=[(MASTER_1, 21)]),
            self.report(master_ids=[MASTER_1, MASTER_2]),
            self.report(start="now()+interval '1 day'", end="now()+interval '1 day 1 hour'"),
            self.report(members=[(STAFF_1, "作業", "now()-interval '2 hours'", "now()-interval '1 hour'"), (STAFF_1, "清掃", "now()-interval '90 minutes'", "now()-interval '30 minutes'")]),
        )
        for index, payload in enumerate(invalid, 1):
            with self.subTest(index=index):
                with self.assertRaises(AssertionError):
                    self.save(f"41000000-0000-0000-0000-0000000001{index:02d}", payload)
                self.assertEqual(self.sql("select count(*) from public.hq_works_v1500", True), "0")
        self.sql(f"update public.hq_lots_v1400 set unit='ケース', pack_weight=null where id='{LOT_1}'")
        with self.assertRaises(AssertionError):
            self.save("41000000-0000-0000-0000-000000000110", self.report(qty=1))

    def test_operation_replay_payload_change_and_updated_at_conflict_are_safe(self):
        self.reset()
        operation = "41000000-0000-0000-0000-000000000111"
        first = self.save(operation, self.report())
        replay = self.save(operation, self.report())
        self.assertTrue(replay["ok"])
        with self.assertRaises(AssertionError):
            self.save(operation, self.report(qty=9))
        stale = first["updated_at"]
        current = self.save("41000000-0000-0000-0000-000000000112", self.report(qty=9, outputs=[(MASTER_1, 7)]), f"'{first['id']}'::uuid", f"'{stale}'::timestamptz")
        self.assertTrue(current["ok"])
        conflict = self.save("41000000-0000-0000-0000-000000000113", self.report(qty=8, outputs=[(MASTER_1, 6)]), f"'{first['id']}'::uuid", f"'{stale}'::timestamptz")
        self.assertTrue(conflict.get("conflict"), conflict)

    def test_break_exclusion_cumulative_work_time_and_standard_snapshot_tolerance(self):
        self.reset()
        self.assertTrue(self.call(WORKER, "public.hq_prep_standard_save_v1199c117", f"array['{MASTER_1}'::uuid]", "80", "5")["ok"])
        payload = self.report(
            outputs=[(MASTER_1, 8)],
            breaks=[("休憩", "'2026-11-10T08:30:00+00'::timestamptz", "'2026-11-10T08:45:00+00'::timestamptz", f"array['{STAFF_2}'::uuid]")],
            members=[
                (STAFF_1, "作業", "'2026-11-10T08:00:00+00'::timestamptz", "'2026-11-10T09:00:00+00'::timestamptz"),
                (STAFF_2, "作業", "'2026-11-10T08:00:00+00'::timestamptz", "'2026-11-10T09:00:00+00'::timestamptz"),
            ],
        )
        saved = self.save("41000000-0000-0000-0000-000000000114", payload)
        self.assertTrue(saved["ok"])
        for staff, minutes in ((STAFF_1, 45), (STAFF_2, 60)):
            total = float(self.sql(f"select sum(extract(epoch from end_at-start_at))/60 from public.hq_work_members_v1500 where work_id='{saved['id']}' and staff_id='{staff}'", True))
            self.assertAlmostEqual(total, minutes, places=2)
        snapshot = self.sql(f"select standard_rate::text||':'||tolerance_points::text from public.hq_works_v1500 where id='{saved['id']}'", True)
        self.assertEqual(snapshot, "80:5")
        self.assertTrue(self.call(WORKER, "public.hq_prep_standard_save_v1199c117", f"array['{MASTER_1}'::uuid]", "70", "1")["ok"])
        self.assertEqual(self.sql(f"select standard_rate::text||':'||tolerance_points::text from public.hq_works_v1500 where id='{saved['id']}'", True), snapshot)

    def test_c116_split_break_edit_does_not_double_subtract_and_syncs_pause_history(self):
        self.reset()
        created = self.save("41000000-0000-0000-0000-000000000115", self.report())
        work_id = created["id"]
        break_start = "'2026-11-10T08:30:00+00'::timestamptz"
        break_end = "'2026-11-10T08:45:00+00'::timestamptz"
        self.sql(f"""
          delete from public.hq_work_members_v1500 where work_id='{work_id}';
          insert into public.hq_work_members_v1500(work_id,staff_id,staff_name,team,phase,start_at,end_at)
          select '{work_id}'::uuid,id,name,team,'作業','2026-11-10T08:00:00+00'::timestamptz,'2026-11-10T08:30:00+00'::timestamptz
          from public.hq_staff_v1500 where id='{STAFF_1}'
          union all
          select '{work_id}'::uuid,id,name,team,'作業','2026-11-10T08:45:00+00'::timestamptz,'2026-11-10T09:00:00+00'::timestamptz
          from public.hq_staff_v1500 where id='{STAFF_1}';
          insert into public.hq_work_pauses_v1199c116
            (operation_id,work_id,kind,start_at,end_at,staff_ids,resumed_staff_ids,by_name,excluded_staff_ids)
          values ('41000000-0000-0000-0000-000000000116','{work_id}','休憩',{break_start},{break_end},
            array['{STAFF_1}'::uuid],array['{STAFF_1}'::uuid],'下処理班',array[]::uuid[]);
          update public.hq_works_v1500 set updated_at=now() where id='{work_id}';
        """)
        expected = self.sql(f"select updated_at from public.hq_works_v1500 where id='{work_id}'", True)
        edited = self.save(
            "41000000-0000-0000-0000-000000000117",
            self.report(
                members=[
                    (STAFF_1, "作業", "'2026-11-10T08:00:00+00'::timestamptz", break_start),
                    (STAFF_1, "作業", break_end, "'2026-11-10T09:00:00+00'::timestamptz"),
                ],
                breaks=[("休憩", break_start, break_end, "array[]::uuid[]")],
            ),
            f"'{work_id}'::uuid", f"'{expected}'::timestamptz",
        )
        self.assertTrue(edited["ok"])
        self.assertEqual(self.sql(f"select coalesce(sum(extract(epoch from end_at-start_at))/60,0) from public.hq_work_members_v1500 where work_id='{work_id}' and phase='作業'", True), "45.0000000000000000")
        self.assertEqual(self.sql(f"select count(*) from public.hq_work_pauses_v1199c116 where work_id='{work_id}' and kind='休憩' and start_at={break_start} and end_at={break_end} and resumed_staff_ids @> array['{STAFF_1}'::uuid]", True), "1")

    def test_editing_break_removal_or_change_restores_member_time(self):
        self.reset()
        created = self.save("41000000-0000-0000-0000-000000000118", self.report(
            breaks=[("休憩", "'2026-11-10T08:30:00+00'::timestamptz", "'2026-11-10T08:45:00+00'::timestamptz", "array[]::uuid[]")],
        ))
        work_id, updated = created["id"], created["updated_at"]
        removed = self.save("41000000-0000-0000-0000-000000000119", self.report(), f"'{work_id}'::uuid", f"'{updated}'::timestamptz")
        self.assertTrue(removed["ok"])
        self.assertEqual(self.sql(f"select sum(extract(epoch from end_at-start_at))/60 from public.hq_work_members_v1500 where work_id='{work_id}' and phase='作業'", True), "60.0000000000000000")
        changed = self.save("41000000-0000-0000-0000-000000000120", self.report(
            breaks=[("休憩", "'2026-11-10T08:15:00+00'::timestamptz", "'2026-11-10T08:30:00+00'::timestamptz", "array[]::uuid[]")],
        ), f"'{work_id}'::uuid", f"'{removed['updated_at']}'::timestamptz")
        self.assertTrue(changed["ok"])
        self.assertEqual(self.sql(f"select sum(extract(epoch from end_at-start_at))/60 from public.hq_work_members_v1500 where work_id='{work_id}' and phase='作業'", True), "45.0000000000000000")
        self.assertEqual(self.sql(f"select start_at::text||':'||end_at::text from public.hq_work_pauses_v1199c116 where work_id='{work_id}' and kind='休憩'", True), "2026-11-10 08:15:00+00:2026-11-10 08:30:00+00")

    def test_cleaning_open_member_is_preserved_then_editable_after_clean_end(self):
        self.reset()
        created = self.save("41000000-0000-0000-0000-000000000121", self.report())
        work_id = created["id"]
        self.sql(f"""
          update public.hq_works_v1500 set status='清掃中',updated_at=now() where id='{work_id}';
          insert into public.hq_work_members_v1500(work_id,staff_id,staff_name,team,phase,start_at,end_at)
          select '{work_id}',id,name,team,'清掃','2026-11-10T09:00:00+00',null
          from public.hq_staff_v1500 where id='{STAFF_1}';
        """)
        expected = self.sql(f"select updated_at from public.hq_works_v1500 where id='{work_id}'", True)
        open_clean = self.save("41000000-0000-0000-0000-000000000122", self.report(
            members=[
                (STAFF_1, "作業", "'2026-11-10T08:00:00+00'::timestamptz", "'2026-11-10T09:00:00+00'::timestamptz"),
                (STAFF_1, "清掃", "'2026-11-10T09:00:00+00'::timestamptz", "null"),
            ],
        ), f"'{work_id}'::uuid", f"'{expected}'::timestamptz")
        self.assertTrue(open_clean["ok"])
        self.assertEqual(self.sql(f"select count(*) from public.hq_work_members_v1500 where work_id='{work_id}' and phase='清掃' and end_at is null", True), "1")
        self.call(PREP, "public.hq_work_clean_end_v1500", f"'{work_id}'::uuid")
        closed_expected = self.sql(f"select updated_at from public.hq_works_v1500 where id='{work_id}'", True)
        edited = self.save("41000000-0000-0000-0000-000000000123", self.report(
            members=[
                (STAFF_1, "作業", "'2026-11-10T08:00:00+00'::timestamptz", "'2026-11-10T09:00:00+00'::timestamptz"),
                (STAFF_1, "清掃", "'2026-11-10T09:00:00+00'::timestamptz", "'2026-11-10T09:30:00+00'::timestamptz"),
            ],
        ), f"'{work_id}'::uuid", f"'{closed_expected}'::timestamptz")
        self.assertTrue(edited["ok"])
        self.assertEqual(self.sql(f"select status||':'||count(*) filter(where phase='清掃' and end_at is not null) from public.hq_works_v1500 w join public.hq_work_members_v1500 m on m.work_id=w.id where w.id='{work_id}' group by status", True), "完了:1")

    def test_unconfirmed_report_creates_no_waste_and_confirm_creates_exactly_one(self):
        self.reset()
        created = self.save("41000000-0000-0000-0000-000000000124", self.report(qty=10, outputs=[(MASTER_1, 8)]))
        work_id = created["id"]
        self.assertEqual(self.sql(f"select count(*) from public.hq_waste_v1500 where work_id='{work_id}' and kind='下処理ロス' and cancelled_at is null", True), "0")
        material_id = self.sql(f"select id from public.hq_work_materials_v1500 where work_id='{work_id}'", True)
        self.assertTrue(self.call(ADMIN, "public.hq_prep_confirm_v1199c116", f"'{work_id}'::uuid", f"jsonb_build_array(jsonb_build_object('id','{material_id}','qty',10))", "2", f"jsonb_build_array(jsonb_build_object('master_id','{MASTER_1}','yield_kg',8))", "'日報確定'")["ok"])
        self.assertEqual(self.sql(f"select count(*) from public.hq_waste_v1500 where work_id='{work_id}' and kind='下処理ロス' and cancelled_at is null", True), "1")

    def test_material_swap_all_snapshot_and_legacy_reservation_protection(self):
        self.reset()
        first = self.save("41000000-0000-0000-0000-000000000125", self.report(qty=10, expected=20))
        work_id = first["id"]
        self.assertTrue(self.save("41000000-0000-0000-0000-000000000126", self.report(
            materials=[(LOT_2, 10, "all", 10)], expected=10,
        ), f"'{work_id}'::uuid", f"'{first['updated_at']}'::timestamptz")["ok"])
        self.assertEqual(self.sql(f"select lot_id||':'||qty from public.hq_work_materials_v1500 where work_id='{work_id}'", True), f"{LOT_2}:10")
        self.assert_denied(PREP, "public.hq_prep_report_save_v1199c117", "'41000000-0000-0000-0000-000000000127'::uuid", "null", "null", self.report(materials=[(LOT_1, 0, "all", 19)]))

        self.reset()
        old_work = self.call(ADMIN, "public.hq_work_start_v1199c116", "'41000000-0000-0000-0000-000000000128'::uuid", "'下処理'", "null", "'下処理室①'", f"array['{MASTER_1}'::uuid]", f"array['{LOT_1}'::uuid]", f"array['{STAFF_1}'::uuid]")["id"]
        old_material = self.sql(f"select id from public.hq_work_materials_v1500 where work_id='{old_work}'", True)
        self.assertTrue(self.call(PREP, "public.hq_work_save_material_qty_v1199c112", f"'{old_work}'::uuid", f"'{old_material}'::uuid", "12")["ok"])
        self.save("41000000-0000-0000-0000-000000000129", self.report(qty=8, expected=8, members=[(STAFF_2, "作業", "'2026-11-10T08:00:00+00'::timestamptz", "'2026-11-10T09:00:00+00'::timestamptz")]))
        self.assert_denied(PREP, "public.hq_work_save_material_qty_v1199c112", f"'{old_work}'::uuid", f"'{old_material}'::uuid", "13")

    def test_rls_rejects_outsider_direct_reads_of_private_report_operation_data(self):
        self.reset()
        self.save("41000000-0000-0000-0000-000000000130", self.report())
        with self.assertRaises(AssertionError):
            self.sql("set role authenticated; set app.\"user\" = '00000000-0000-0000-0000-000000000004'; select count(*) from public.hq_prep_report_operations_v1199c117;", True)
        self.sql("reset role;")
        self.call(WORKER, "public.hq_prep_standard_save_v1199c117", f"array['{MASTER_1}'::uuid]", "80", "5")
        outsider = self.sql(f"set role authenticated; set app.\"user\" = '{OTHER}'; select count(*) from public.hq_prep_standards_v1199c117;", True)
        self.assertEqual(outsider.splitlines()[-1], "0")
        allowed = self.sql(f"set role authenticated; set app.\"user\" = '{PREP}'; select count(*) from public.hq_prep_standards_v1199c117;", True)
        self.assertEqual(allowed.splitlines()[-1], "1")
        self.sql("reset role;")

    def test_c117_snapshots_follow_legacy_save_confirm_and_correction_with_stock_on_and_off(self):
        for stock_enabled, suffix in ((True, "140"), (False, "143")):
            with self.subTest(stock_enabled=stock_enabled):
                self.reset()
                if not stock_enabled:
                    self.sql("update public.hq_settings_v1500 set value='false'::jsonb where key='stage2_stock'")
                created = self.save(f"41000000-0000-0000-0000-000000000{suffix}", self.report(qty=10, outputs=[(MASTER_1, 8)]))
                work_id = created["id"]
                material_id = self.sql(f"select id from public.hq_work_materials_v1500 where work_id='{work_id}'", True)
                self.assertTrue(self.call(
                    PREP, "public.hq_work_save_inputs_v1199c116", f"'{work_id}'::uuid",
                    f"jsonb_build_array(jsonb_build_object('id','{material_id}','qty',12))", "3",
                    f"jsonb_build_array(jsonb_build_object('master_id','{MASTER_1}','yield_kg',9))",
                )["ok"])
                self.assertEqual(
                    self.sql(f"select report_raw_kg::text||':'||report_waste_kg::text from public.hq_works_v1500 where id='{work_id}'", True),
                    "12:3",
                )
                self.assertTrue(self.call(
                    ADMIN, "public.hq_prep_confirm_v1199c116", f"'{work_id}'::uuid",
                    f"jsonb_build_array(jsonb_build_object('id','{material_id}','qty',11))", "2",
                    f"jsonb_build_array(jsonb_build_object('master_id','{MASTER_1}','yield_kg',9))", "'日報の旧確定'",
                )["ok"])
                self.assertEqual(
                    self.sql(f"select report_raw_kg::text||':'||report_waste_kg::text from public.hq_works_v1500 where id='{work_id}'", True),
                    "11:2",
                )
                self.assertEqual(self.sql(f"select current_qty from public.hq_lots_v1400 where id='{LOT_1}'", True), "9" if stock_enabled else "20")
                expected = self.sql(f"select updated_at from public.hq_works_v1500 where id='{work_id}'", True)
                corrected = self.call(
                    ADMIN, "public.hq_prep_correct_v1199c116", f"'{work_id}'::uuid",
                    f"'41000000-0000-0000-0000-000000000{int(suffix) + 1:03d}'::uuid", f"'{expected}'::timestamptz",
                    f"jsonb_build_array(jsonb_build_object('lot_id','{LOT_1}','qty',10))", "1",
                    f"jsonb_build_array(jsonb_build_object('master_id','{MASTER_1}','yield_kg',9))", "'日報の確定後訂正'",
                )
                self.assertTrue(corrected["ok"])
                self.assertEqual(
                    self.sql(f"select report_raw_kg::text||':'||report_waste_kg::text from public.hq_works_v1500 where id='{work_id}'", True),
                    "10:1",
                )
                self.assertEqual(self.sql(f"select current_qty from public.hq_lots_v1400 where id='{LOT_1}'", True), "10" if stock_enabled else "20")

    def test_legacy_snapshot_and_confirm_keep_standard_and_waste_protections(self):
        self.reset()
        self.assertTrue(self.call(WORKER, "public.hq_prep_standard_save_v1199c117", f"array['{MASTER_1}'::uuid]", "80", "5")["ok"])
        legacy = self.call(ADMIN, "public.hq_work_start_v1199c116", "'41000000-0000-0000-0000-000000000131'::uuid", "'下処理'", "null", "'下処理室①'", f"array['{MASTER_1}'::uuid]", f"array['{LOT_1}'::uuid]", f"array['{STAFF_1}'::uuid]")["id"]
        self.call(PREP, "public.hq_work_end_v1500", f"'{legacy}'::uuid")
        material = self.sql(f"select id from public.hq_work_materials_v1500 where work_id='{legacy}'", True)
        self.assertTrue(self.call(PREP, "public.hq_work_save_inputs_v1199c116", f"'{legacy}'::uuid", f"jsonb_build_array(jsonb_build_object('id','{material}','qty',10))", "1", f"jsonb_build_array(jsonb_build_object('master_id','{MASTER_1}','yield_kg',9))")["ok"])
        self.assertEqual(self.sql(f"select standard_rate::text||':'||tolerance_points::text from public.hq_works_v1500 where id='{legacy}'", True), "80:5")
        self.assertTrue(self.call(WORKER, "public.hq_prep_standard_save_v1199c117", f"array['{MASTER_1}'::uuid]", "70", "1")["ok"])
        material = self.sql(f"select id from public.hq_work_materials_v1500 where work_id='{legacy}'", True)
        self.assertTrue(self.call(ADMIN, "public.hq_prep_confirm_v1199c116", f"'{legacy}'::uuid", f"jsonb_build_array(jsonb_build_object('id','{material}','qty',10))", "1", f"jsonb_build_array(jsonb_build_object('master_id','{MASTER_1}','yield_kg',9))", "'旧確定'")["ok"])
        self.assertEqual(self.sql(f"select standard_rate::text||':'||tolerance_points::text from public.hq_works_v1500 where id='{legacy}'", True), "80:5")
        self.assertEqual(self.sql(f"select count(*) from public.hq_waste_v1500 where work_id='{legacy}' and kind='下処理ロス' and cancelled_at is null", True), "1")

    def test_infinite_report_and_member_times_are_rejected(self):
        self.reset()
        for operation, payload in (
            ("41000000-0000-0000-0000-000000000132", self.report(start="'infinity'::timestamptz")),
            ("41000000-0000-0000-0000-000000000133", self.report(members=[(STAFF_1, "作業", "'2026-11-10T08:00:00+00'::timestamptz", "'infinity'::timestamptz")])),
        ):
            with self.subTest(operation=operation):
                self.assert_denied(PREP, "public.hq_prep_report_save_v1199c117", f"'{operation}'::uuid", "null", "null", payload)
                self.assertEqual(self.sql("select count(*) from public.hq_works_v1500", True), "0")

    def test_final_state_integrity_allows_edit_quantity_then_cancel_and_delete(self):
        self.reset()
        created = self.save("41000000-0000-0000-0000-000000000134", self.report())
        edited = self.save("41000000-0000-0000-0000-000000000135", self.report(qty=9, outputs=[(MASTER_1, 7)]), f"'{created['id']}'::uuid", f"'{created['updated_at']}'::timestamptz")
        self.assertTrue(edited["ok"])
        self.call(ADMIN, "public.hq_prep_cancel_v1500", f"'{created['id']}'::uuid", "'取消確認'")
        self.call(ADMIN, "public.hq_work_delete_v1500", f"'{created['id']}'::uuid")
        self.assertEqual(self.sql(f"select count(*) from public.hq_works_v1500 where id='{created['id']}'", True), "0")

    def test_employee_confirmation_rejects_stale_report_and_replays_current_result(self):
        self.reset()
        created = self.save("41000000-0000-0000-0000-000000000136", self.report())
        edited = self.save("41000000-0000-0000-0000-000000000137", self.report(qty=9, outputs=[(MASTER_1, 7)]), f"'{created['id']}'::uuid", f"'{created['updated_at']}'::timestamptz")
        work_id = created["id"]
        material_id = self.sql(f"select id from public.hq_work_materials_v1500 where work_id='{work_id}'", True)
        args = (f"'{work_id}'::uuid", f"'{created['updated_at']}'::timestamptz", f"jsonb_build_array(jsonb_build_object('id','{material_id}','qty',9))", "2", f"jsonb_build_array(jsonb_build_object('master_id','{MASTER_1}','yield_kg',7))", "null")
        stale = self.call(ADMIN, "public.hq_prep_confirm_v1199c117", *args)
        self.assertTrue(stale.get("conflict"), stale)
        self.assertEqual(self.sql(f"select current_qty from public.hq_lots_v1400 where id='{LOT_1}'", True), "20")
        current = (args[0], f"'{edited['updated_at']}'::timestamptz", *args[2:])
        self.assertTrue(self.call(ADMIN, "public.hq_prep_confirm_v1199c117", *current)["ok"])
        self.assertTrue(self.call(ADMIN, "public.hq_prep_confirm_v1199c117", *current).get("already"))
        self.assertEqual(self.sql(f"select current_qty from public.hq_lots_v1400 where id='{LOT_1}'", True), "11")
        self.assert_denied(PREP, "public.hq_prep_confirm_v1199c117", *current)

    def test_046_reapply_and_rpc_acl_are_idempotent(self):
        self.pg.file(self.sql_046)
        for function in (
            "hq_prep_available_lots_v1199c117(uuid)",
            "hq_prep_report_save_v1199c117(uuid,uuid,timestamptz,jsonb)",
            "hq_prep_standard_save_v1199c117(uuid[],numeric,numeric)",
        ):
            self.assertEqual(self.sql(f"select has_function_privilege('authenticated','public.{function}','execute')", True), "t")
            self.assertEqual(self.sql(f"select has_function_privilege('anon','public.{function}','execute')", True), "f")


if __name__ == "__main__":
    unittest.main()
