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
SQL_043 = (ROOT / 'db/043_QR出庫数の当日訂正.sql').read_text(encoding='utf-8')
SQL_044 = (ROOT / 'db/044_QR出庫数の訂正_実数調整後も可能.sql').read_text(encoding='utf-8')
SQL = SQL_043 + '\n' + SQL_044
SCRATCH = Path('/tmp/jai-scratch/c113')
TIMEOUT = 30


def find_pg_bin():
    for executable in ('initdb',):
        path = shutil.which(executable)
        if path:
            return Path(path).parent
    candidates = sorted(Path('/usr/lib/postgresql').glob('*/bin/initdb'))
    return candidates[-1].parent if candidates else None


BIN = find_pg_bin()

SCHEMA = r'''
create extension if not exists pgcrypto;
create schema auth;
create function auth.uid() returns uuid language sql stable as $$select current_setting('app.user',true)::uuid$$;
create table public.profiles(id uuid primary key, role text not null, active boolean not null default true, display_name text);
create function public.seika_v1136_require_roles(p_roles text[]) returns public.profiles language plpgsql security definer as $$declare p public.profiles%rowtype; begin select * into p from public.profiles where id=auth.uid() and active; if not found or not(p.role=any(p_roles)) then raise exception '権限がありません'; end if; return p; end$$;
create table public.qr_lots(id uuid primary key default gen_random_uuid(), active boolean not null default true, current_qty numeric, current_weight numeric, status text, updated_at timestamptz default now(), container_type text, item_name text not null, storage_location text);
create table public.qr_lot_movements(id uuid primary key default gen_random_uuid(), movement_type text not null check(movement_type in ('出庫','取消','棚卸し調整増','棚卸し調整減','入庫','廃棄','出庫・調整減','入庫・調整増','差分なし','調整','重量確定','重量更新','ロット情報訂正','場所移動')), lot_id uuid not null, lot_no text, qr_key text, item_id text, item_name text, origin text, supplier text, cooperative_name text, qty numeric, unit text, destination text, storage_location text, user_id text, user_name text, memo text, container_type text, lot_manage_type text, weight numeric, before_quantity numeric, after_quantity numeric, before_weight numeric, after_weight numeric, weight_status text, reason text, operation_id uuid unique, reversed_operation_id uuid, cancelled_at timestamptz, cancelled_by text, device_meta jsonb default '{}'::jsonb, operation_meta jsonb default '{}'::jsonb, occurred_at timestamptz default now(), created_at timestamptz default now());
create table public.qr_lot_grades_v1300(lot_id uuid not null, grade text not null, current_qty numeric not null, updated_at timestamptz default now(), primary key(lot_id,grade));
create table public.qr_slip_adjust_v1199c86(movement_id uuid primary key, total_kg numeric, pack text, updated_by uuid, updated_by_name text, updated_at timestamptz);
create function public.seika_check_lot_grades_v1300() returns trigger language plpgsql as $$declare v_lot public.qr_lots%rowtype; v_sum numeric; v_cnt integer; begin select * into v_lot from public.qr_lots where id=new.id; if not found or coalesce(v_lot.active,true)=false or coalesce(v_lot.status,'')='削除' then return null; end if; select count(*),coalesce(sum(current_qty),0) into v_cnt,v_sum from public.qr_lot_grades_v1300 where lot_id=new.id; if v_cnt>0 and v_sum<>coalesce(v_lot.current_qty,0) then raise exception '規格別ロット（%）は、規格ごとの数量で操作してください。',v_lot.item_name using errcode='23514'; end if; return null; end$$;
create constraint trigger seika_check_lot_grades_v1300 after insert or update on public.qr_lots deferrable initially deferred for each row execute function public.seika_check_lot_grades_v1300();
create function public.seika_cancel_lot_grades_v1300() returns trigger language plpgsql as $$declare v_orig jsonb; v_rev jsonb; d jsonb; begin if new.reversed_operation_id is null or new.movement_type<>'取消' then return new; end if; select m.operation_meta->'grades' into v_orig from public.qr_lot_movements m where m.operation_id=new.reversed_operation_id and m.movement_type<>'取消' limit 1; if v_orig is null or jsonb_typeof(v_orig)<>'array' or jsonb_array_length(v_orig)=0 then return new; end if; select jsonb_agg(jsonb_build_object('grade',x->>'grade','delta',-((x->>'delta')::numeric))) into v_rev from jsonb_array_elements(v_orig) x; for d in select value from jsonb_array_elements(v_rev) loop update public.qr_lot_grades_v1300 set current_qty=current_qty+(d->>'delta')::numeric,updated_at=now() where lot_id=new.lot_id and grade=d->>'grade'; end loop; new.operation_meta:=coalesce(new.operation_meta,'{}'::jsonb)||jsonb_build_object('grades',v_rev); return new; end$$;
create trigger seika_cancel_lot_grades_v1300 before insert on public.qr_lot_movements for each row execute function public.seika_cancel_lot_grades_v1300();
create role anon; create role authenticated; create role service_role;
insert into public.profiles values ('00000000-0000-0000-0000-000000000001','admin',true,'管理者'),('00000000-0000-0000-0000-000000000002','buyer',true,'仕入');
'''


class OutboundCorrectSqlStaticTests(unittest.TestCase):
    def test_static_safety_contract(self):
        self.assertIn("seika_v1136_require_roles(array['admin','worker'])", SQL)
        self.assertIn("v_original.destination not in ('埼玉','深谷')", SQL)
        self.assertIn('if p_qty=0 then return', SQL)
        self.assertIn('pg_advisory_xact_lock(hashtext(p_operation_id::text))', SQL)
        self.assertNotRegex(SQL, r'update public\.qr_lot_movements\s+set\s+qty\s*=')
        self.assertIn("current_setting('seika.c113_outbound_correction_cancel',true)", SQL)

    def test_044_allows_only_adjustment_move_and_info_changes_after_the_outbound(self):
        allowed = ('入庫・調整増', '出庫・調整減', '差分なし', '調整', '場所移動', '重量確定', '重量更新', 'ロット情報訂正')
        guard = SQL_044[SQL_044.index('m.movement_type not in (') : SQL_044.index(') then raise exception', SQL_044.index('m.movement_type not in ('))]
        for kind in allowed + ('出庫', '取消'):
            self.assertIn(f"'{kind}'", guard)
        for kind in ('棚卸し調整増', '棚卸し調整減', '入庫', '廃棄'):
            self.assertNotIn(f"'{kind}'", guard)
        self.assertNotRegex(SQL_044, r'update public\.qr_lot_movements\s+set\s+qty\s*=')


class OutboundCorrectSqlRuntimeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not BIN or not (BIN / 'initdb').exists() or not (BIN / 'pg_ctl').exists():
            raise unittest.SkipTest('PostgreSQL binaries unavailable')
        cls.runner = []
        if os.geteuid() == 0:
            if not shutil.which('runuser'):
                raise unittest.SkipTest('root requires runuser for disposable PostgreSQL')
            try:
                pwd.getpwnam('postgres')
            except KeyError:
                raise unittest.SkipTest('root requires a postgres OS user for disposable PostgreSQL')
            cls.runner = ['runuser', '-u', 'postgres', '--']
        SCRATCH.mkdir(parents=True, exist_ok=True)
        if cls.runner:
            os.chmod(SCRATCH, 0o777)
        cls.tmp = tempfile.TemporaryDirectory(prefix='pg-', dir=SCRATCH)
        cls.data = Path(cls.tmp.name) / 'data'
        cls.log = Path(cls.tmp.name) / 'postgres.log'
        if cls.runner:
            os.chmod(cls.tmp.name, 0o777)
        cls.addClassCleanup(cls.cleanup_postgres)
        cls.command(cls.runner + [str(BIN / 'initdb'), '-D', str(cls.data), '-A', 'trust', '-U', 'postgres'])
        cls.port = '55434'
        cls.command(cls.runner + [str(BIN / 'pg_ctl'), '-D', str(cls.data), '-l', str(cls.log), '-o', f'-p {cls.port} -h 127.0.0.1 -k {cls.tmp.name}', '-w', 'start'])
        cls.base = [str(BIN / 'psql'), '-h', '127.0.0.1', '-p', cls.port, '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-X']
        cls.psql(SCHEMA)
        cls.psql(SQL_043)
        cls.psql(SQL_044)

    @classmethod
    def command(cls, command):
        result = subprocess.run(command, text=True, capture_output=True, timeout=TIMEOUT)
        if result.returncode:
            log = cls.log.read_text(encoding='utf-8') if cls.log.exists() else ''
            raise AssertionError(f'PostgreSQL準備失敗: {command}\n{result.stdout}\n{result.stderr}\n{log}')
        return result

    @classmethod
    def cleanup_postgres(cls):
        try:
            if hasattr(cls, 'data'):
                subprocess.run(cls.runner + [str(BIN / 'pg_ctl'), '-D', str(cls.data), '-m', 'immediate', '-w', 'stop'], text=True, capture_output=True, timeout=TIMEOUT)
        finally:
            if hasattr(cls, 'tmp'):
                cls.tmp.cleanup()

    @classmethod
    def psql(cls, sql, tuples=False):
        result = subprocess.run(cls.base + (['-At'] if tuples else []) + ['-c', sql], text=True, capture_output=True, timeout=TIMEOUT)
        if result.returncode:
            raise AssertionError(result.stderr + '\nSQL:\n' + sql)
        return result.stdout.strip()

    def reset(self, destination='埼玉', grade=False, big=False, later=False, old_grades=True, occurred_at='now()', storage_location='現在棚', original_location='出庫時棚', original_weight=50):
        self.psql('truncate public.qr_lot_movements, public.qr_lot_grades_v1300, public.qr_lots, public.qr_slip_adjust_v1199c86')
        container = '網コンテナ' if big else 'ダンボール'
        self.psql(f"insert into public.qr_lots(id,current_qty,current_weight,status,container_type,item_name,storage_location) values('10000000-0000-0000-0000-000000000001',5,50,'在庫あり','{container}','テスト品','{storage_location}')")
        meta = json.dumps({'grades': [{'grade': 'A', 'delta': -3}, {'grade': 'B', 'delta': -2}]} if grade and old_grades else {})
        self.psql("insert into public.qr_lot_movements(id,movement_type,lot_id,qty,unit,destination,storage_location,container_type,weight,before_quantity,after_quantity,before_weight,after_weight,operation_id,operation_meta,occurred_at,created_at,memo) values ('20000000-0000-0000-0000-000000000001','出庫','10000000-0000-0000-0000-000000000001',5,'CS',%s,%s,%s,%s,10,5,100,50,'30000000-0000-0000-0000-000000000001',%s::jsonb,%s,%s,'当日分 / 元メモ')" % (repr(destination), repr(original_location), repr(container), repr(original_weight), repr(meta), occurred_at, occurred_at))
        if grade:
            self.psql("insert into public.qr_lot_grades_v1300 values('10000000-0000-0000-0000-000000000001','A',3),('10000000-0000-0000-0000-000000000001','B',2)")
        if later:
            self.psql("insert into public.qr_lot_movements(movement_type,lot_id,qty,operation_id,created_at) values('出庫','10000000-0000-0000-0000-000000000001',1,'30000000-0000-0000-0000-000000000009',now()+interval '1 second')")

    def call_sql(self, op, qty, expected=5, original='30000000-0000-0000-0000-000000000001', grades='[]', kg='null', role='00000000-0000-0000-0000-000000000001'):
        return f"set app.\"user\"='{role}'; select public.correct_qr_outbound_v1199c113('{op}','{original}',{qty},{expected},'{grades}'::jsonb,{kg},'{{}}'::jsonb);"

    def call(self, op='40000000-0000-0000-0000-000000000001', qty=3, expected=5, **kwargs):
        return json.loads(self.psql(self.call_sql(op, qty, expected, **kwargs), True).splitlines()[-1])

    def test_core_zero_later_outbound_and_recorrect(self):
        self.reset(later=True)
        self.assertTrue(self.call(qty=3)['ok'])
        self.assertEqual(self.psql('select current_qty from public.qr_lots', True), '7')
        self.assertEqual(self.psql("select memo from public.qr_lot_movements where operation_id='40000000-0000-0000-0000-000000000001'", True), '当日分 / 元メモ')
        self.assertTrue(self.call('40000000-0000-0000-0000-000000000002', 4, expected=7, original='40000000-0000-0000-0000-000000000001')['ok'])
        self.reset()
        self.assertTrue(self.call(qty=0)['ok'])
        self.assertEqual(self.psql("select count(*) from public.qr_lot_movements where movement_type='出庫'", True), '1')
        self.assertTrue(self.call(qty=0)['idempotent'])

    def add_later(self, kind, qty=1, before=5, after=6, seconds=1):
        self.psql(f"insert into public.qr_lot_movements(movement_type,lot_id,qty,before_quantity,after_quantity,operation_id,created_at,occurred_at) values('{kind}','10000000-0000-0000-0000-000000000001',{qty},{before},{after},gen_random_uuid(),now()+interval '{seconds} second',now()+interval '{seconds} second')")

    def test_correction_after_actual_count_adjustment_applies_only_the_difference(self):
        self.reset()
        self.add_later('入庫・調整増')
        self.psql("update public.qr_lots set current_qty=0,current_weight=0,status='在庫なし'")
        result = self.call(qty=3, expected=0)
        self.assertTrue(result['ok'], result)
        self.assertEqual(result['after_quantity'], 2)
        self.assertEqual(self.psql("select current_qty||':'||status from public.qr_lots", True), '2:在庫あり')
        self.assertEqual(self.psql("select string_agg(movement_type,',' order by created_at) from public.qr_lot_movements", True), '出庫,入庫・調整増,取消,出庫')
        self.assertEqual(self.psql("select count(*) from public.qr_lot_movements where movement_type='入庫・調整増' and qty=1", True), '1')
        self.assertTrue(self.call(qty=3, expected=0)['idempotent'])
        self.assertTrue(self.call('40000000-0000-0000-0000-000000000002', 0, expected=2, original='40000000-0000-0000-0000-000000000001')['ok'])
        self.assertEqual(self.psql('select current_qty from public.qr_lots', True), '5')

    def test_correction_after_each_allowed_operation_and_still_blocked_after_others(self):
        for kind in ('出庫・調整減', '差分なし', '調整', '場所移動', '重量確定', '重量更新', 'ロット情報訂正'):
            self.reset()
            self.add_later(kind, qty=0, before=5, after=5)
            self.assertTrue(self.call(qty=3)['ok'], kind)
            self.assertEqual(self.psql('select current_qty from public.qr_lots', True), '7', kind)
        for kind in ('棚卸し調整増', '棚卸し調整減', '入庫', '廃棄'):
            self.reset()
            self.add_later(kind)
            with self.assertRaises(AssertionError, msg=kind):
                self.call(qty=3)
            self.assertEqual(self.psql('select current_qty from public.qr_lots', True), '5', kind)
            self.assertEqual(self.psql("select count(*) from public.qr_lot_movements where movement_type='取消'", True), '0', kind)

    def test_correction_after_adjustment_still_rejects_insufficient_stock_and_keeps_grades_consistent(self):
        self.reset()
        self.add_later('入庫・調整増')
        self.psql("update public.qr_lots set current_qty=1")
        self.assertTrue(self.call(qty=7, expected=1)['insufficient_stock'])
        self.assertEqual(self.psql('select current_qty from public.qr_lots', True), '1')
        self.reset(grade=True)
        self.add_later('入庫・調整増')
        self.assertTrue(self.call(qty=4, grades='[{"grade":"A","qty":3},{"grade":"B","qty":1}]')['ok'])
        self.assertEqual(self.psql("select string_agg(grade||':'||current_qty::text,',' order by grade) from public.qr_lot_grades_v1300", True), 'A:3,B:3')

    def test_retry_and_concurrent_retry_are_idempotent(self):
        self.reset()
        op = '40000000-0000-0000-0000-000000000010'
        results = []
        def invoke():
            results.append(self.psql(self.call_sql(op, 3), True).splitlines()[-1])
        threads = [threading.Thread(target=invoke) for _ in range(2)]
        [thread.start() for thread in threads]
        [thread.join(TIMEOUT) for thread in threads]
        self.assertFalse(any(thread.is_alive() for thread in threads))
        decoded = [json.loads(value) for value in results]
        self.assertEqual(len(decoded), 2)
        self.assertTrue(all(value['ok'] for value in decoded))
        self.assertEqual(self.psql("select count(*) from public.qr_lot_movements where operation_id='40000000-0000-0000-0000-000000000010'", True), '1')
        self.assertTrue(self.call(op, 3)['idempotent'])

    def test_grade_zero_metadata_and_other_lot_are_isolated(self):
        self.reset(grade=True, old_grades=False)
        self.psql("update public.qr_lot_movements set operation_meta='{\"grades\":[{\"grade\":\"A\",\"delta\":-5},{\"grade\":\"B\",\"delta\":0}]}'::jsonb where id='20000000-0000-0000-0000-000000000001'")
        self.psql("insert into public.qr_lots(id,current_qty,current_weight,status,container_type,item_name) values('10000000-0000-0000-0000-000000000002',9,90,'在庫あり','ダンボール','別ロット')")
        self.psql("insert into public.qr_lot_grades_v1300 values('10000000-0000-0000-0000-000000000002','A',7),('10000000-0000-0000-0000-000000000002','B',2)")
        self.assertTrue(self.call(qty=3, grades='[{"grade":"A","qty":2},{"grade":"B","qty":1}]')['ok'])
        self.assertEqual(self.psql("select string_agg(grade||':'||current_qty::text,',' order by grade) from public.qr_lot_grades_v1300 where lot_id='10000000-0000-0000-0000-000000000001'", True), 'A:6,B:1')
        self.assertEqual(self.psql("select string_agg(grade||':'||current_qty::text,',' order by grade) from public.qr_lot_grades_v1300 where lot_id='10000000-0000-0000-0000-000000000002'", True), 'A:7,B:2')

    def test_invalid_numbers_and_null_destination_roll_back(self):
        for bad in ("'NaN'::numeric", "'Infinity'::numeric", "'-Infinity'::numeric"):
            self.reset()
            with self.assertRaises(AssertionError):
                self.call(qty=bad)
            self.assertEqual(self.psql("select current_qty||':'||current_weight from public.qr_lots", True), '5:50')
            self.assertEqual(self.psql("select count(*) from public.qr_lot_movements", True), '1')
        self.reset(destination='null')
        self.psql("update public.qr_lot_movements set destination=null")
        with self.assertRaises(AssertionError):
            self.call(qty=3)
        self.assertEqual(self.psql("select count(*) from public.qr_lot_movements", True), '1')

    def test_timestamp_snapshot_location_pack_and_weight_ratio(self):
        self.reset(storage_location='訂正時棚', original_location='元の棚', original_weight=777)
        self.psql("insert into public.qr_slip_adjust_v1199c86(movement_id,total_kg,pack) values('20000000-0000-0000-0000-000000000001',50,'10kg箱')")
        result = self.call(qty=3)
        self.assertTrue(result['ok'])
        rows = self.psql("select movement_type||':'||storage_location||':'||coalesce(weight::text,'')||':'||floor(extract(epoch from occurred_at)*1000)::bigint from public.qr_lot_movements where id<>'20000000-0000-0000-0000-000000000001' order by occurred_at", True).splitlines()
        self.assertEqual([row.split(':')[:3] for row in rows], [['取消', '訂正時棚', '777'], ['出庫', '訂正時棚', '30.000']])
        self.assertGreaterEqual(int(rows[1].rsplit(':', 1)[1]) - int(rows[0].rsplit(':', 1)[1]), 1)
        self.assertEqual(self.psql("select current_qty||':'||current_weight||':'||status from public.qr_lots", True), '7:70.000:在庫あり')
        self.assertEqual(self.psql("select pack from public.qr_slip_adjust_v1199c86 where movement_id='%s'" % result['movement_id'], True), '10kg箱')

    def test_later_inventory_yesterday_reapply_and_competing_operations(self):
        self.reset()
        self.psql("insert into public.qr_lot_movements(movement_type,lot_id,qty,operation_id,created_at) values('棚卸し調整増','10000000-0000-0000-0000-000000000001',1,'30000000-0000-0000-0000-000000000008',now()+interval '1 second')")
        with self.assertRaises(AssertionError): self.call(qty=3)
        self.reset(occurred_at="now()-interval '1 day'")
        with self.assertRaises(AssertionError): self.call(qty=3)
        self.psql(SQL_043)
        self.psql(SQL_044)
        self.reset()
        replies = []
        def invoke(op):
            result = subprocess.run(self.base + ['-At', '-c', self.call_sql(op, 3)], text=True, capture_output=True, timeout=TIMEOUT)
            replies.append(result)
        threads = [threading.Thread(target=invoke, args=(op,)) for op in ('40000000-0000-0000-0000-000000000021', '40000000-0000-0000-0000-000000000022')]
        [thread.start() for thread in threads]
        [thread.join(TIMEOUT) for thread in threads]
        self.assertFalse(any(thread.is_alive() for thread in threads))
        self.assertEqual(sum(result.returncode == 0 and json.loads(result.stdout.splitlines()[-1])['ok'] for result in replies), 1)
        self.assertEqual(self.psql("select count(*) from public.qr_lot_movements where movement_type='取消'", True), '1')
        self.assertEqual(self.psql("select count(*) from public.qr_lot_movements where movement_type='出庫'", True), '2')

    def test_grades_big_and_guards(self):
        self.reset(grade=True)
        self.assertTrue(self.call(qty='2.5', grades='[{"grade":"A","qty":1.5},{"grade":"B","qty":1}]')['ok'])
        self.assertEqual(self.psql("select string_agg(grade||':'||current_qty::text,',' order by grade) from public.qr_lot_grades_v1300", True), 'A:4.5,B:3')
        self.reset(grade=True, old_grades=False)
        with self.assertRaises(AssertionError): self.call(qty=2, grades='[{"grade":"A","qty":1},{"grade":"B","qty":1}]')
        self.reset(big=True)
        with self.assertRaises(AssertionError): self.call(qty=3)
        self.reset(big=True)
        self.assertTrue(self.call(qty=3, kg=999)['ok'])
        self.assertEqual(self.psql('select current_weight from public.qr_lots', True), '70.000')
        self.reset(destination='本社')
        with self.assertRaises(AssertionError): self.call(qty=3)
        self.reset()
        with self.assertRaises(AssertionError): self.call(qty=3, role='00000000-0000-0000-0000-000000000002')
        self.reset()
        self.psql('update public.qr_lots set current_qty=4')
        self.assertTrue(self.call(qty=3)['conflict'])
        self.reset()
        self.assertTrue(self.call(qty=3)['ok'])
        with self.assertRaises(AssertionError): self.psql("insert into public.qr_lot_movements(movement_type,lot_id,reversed_operation_id,operation_id) values('取消','10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000001')")


if __name__ == '__main__':
    unittest.main()
