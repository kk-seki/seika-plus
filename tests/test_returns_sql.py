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
SQL = (ROOT / 'db/067_返品_仕入先へと石岡への戻し.sql').read_text(encoding='utf-8')
SCRATCH = Path('/tmp/jai-scratch/c163')
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
create function public.trimming_require_role(p_roles text[]) returns public.profiles language plpgsql security definer as $$declare p public.profiles%rowtype; begin select * into p from public.profiles where id=auth.uid() and active; if not found or not(p.role=any(p_roles)) then raise exception '権限がありません'; end if; return p; end$$;
create function public.seika_require_role_v1240(p_roles text[]) returns public.profiles language plpgsql security definer as $$declare p public.profiles%rowtype; begin select * into p from public.profiles where id=auth.uid() and active; if not found or not(p.role=any(p_roles)) then raise exception '権限がありません'; end if; return p; end$$;
create table public.qr_lots(id uuid primary key default gen_random_uuid(), active boolean not null default true, lot_no text, qr_key text, item_id text, item_name text not null, origin text, supplier text, cooperative_name text, unit text, received_date date, current_qty numeric, current_weight numeric, status text, updated_at timestamptz default now(), container_type text, lot_manage_type text, weight_status text, storage_location text);
create table public.qr_lot_movements(id uuid primary key default gen_random_uuid(), movement_type text not null check(movement_type in ('出庫','取消','棚卸し調整増','棚卸し調整減','入庫','廃棄','出庫・調整減','入庫・調整増','差分なし','調整','重量確定','重量更新','ロット情報訂正','場所移動')), lot_id uuid not null, lot_no text, qr_key text, item_id text, item_name text, origin text, supplier text, cooperative_name text, qty numeric, unit text, destination text, storage_location text, user_id text, user_name text, memo text, container_type text, lot_manage_type text, weight numeric, before_quantity numeric, after_quantity numeric, before_weight numeric, after_weight numeric, weight_status text, reason text, operation_id uuid unique, reversed_operation_id uuid, cancelled_at timestamptz, cancelled_by text, device_meta jsonb default '{}'::jsonb, operation_meta jsonb default '{}'::jsonb, occurred_at timestamptz default now(), created_at timestamptz default now());
create table public.qr_lot_grades_v1300(lot_id uuid not null, grade text not null, current_qty numeric not null, updated_at timestamptz default now(), primary key(lot_id,grade));
create function public.seika_check_lot_grades_v1300() returns trigger language plpgsql as $$declare v_lot public.qr_lots%rowtype; v_sum numeric; v_cnt integer; begin select * into v_lot from public.qr_lots where id=new.id; if not found or coalesce(v_lot.active,true)=false or coalesce(v_lot.status,'')='削除' then return null; end if; select count(*),coalesce(sum(current_qty),0) into v_cnt,v_sum from public.qr_lot_grades_v1300 where lot_id=new.id; if v_cnt>0 and v_sum<>coalesce(v_lot.current_qty,0) then raise exception '規格別ロット（%）は、規格ごとの数量で操作してください。',v_lot.item_name using errcode='23514'; end if; return null; end$$;
create constraint trigger seika_check_lot_grades_v1300 after insert or update on public.qr_lots deferrable initially deferred for each row execute function public.seika_check_lot_grades_v1300();
create function public.seika_cancel_lot_grades_v1300() returns trigger language plpgsql as $$declare v_orig jsonb; v_rev jsonb; d jsonb; begin if new.reversed_operation_id is null or new.movement_type<>'取消' then return new; end if; select m.operation_meta->'grades' into v_orig from public.qr_lot_movements m where m.operation_id=new.reversed_operation_id and m.movement_type<>'取消' limit 1; if v_orig is null or jsonb_typeof(v_orig)<>'array' or jsonb_array_length(v_orig)=0 then return new; end if; select jsonb_agg(jsonb_build_object('grade',x->>'grade','delta',-((x->>'delta')::numeric))) into v_rev from jsonb_array_elements(v_orig) x; for d in select value from jsonb_array_elements(v_rev) loop update public.qr_lot_grades_v1300 set current_qty=current_qty+(d->>'delta')::numeric,updated_at=now() where lot_id=new.lot_id and grade=d->>'grade'; end loop; new.operation_meta:=coalesce(new.operation_meta,'{}'::jsonb)||jsonb_build_object('grades',v_rev); return new; end$$;
create trigger seika_cancel_lot_grades_v1300 before insert on public.qr_lot_movements for each row execute function public.seika_cancel_lot_grades_v1300();
create table public.hq_lots_v1400(id uuid primary key default gen_random_uuid(), lot_no text not null unique, qr_key text not null unique, source_movement_id uuid unique, item_name text not null, unit text not null default 'ケース', planned_qty numeric not null default 0, received_qty numeric not null default 0, current_qty numeric not null default 0, status text not null default '入荷待ち' check (status in ('入荷待ち','在庫あり','在庫なし','取消')), memo text, planned_count numeric, unit_weight_kg numeric, updated_at timestamptz not null default now());
create table public.hq_lot_movements_v1400(id uuid primary key default gen_random_uuid(), operation_id uuid not null unique, lot_id uuid not null references public.hq_lots_v1400(id), movement_type text not null check (movement_type in ('入庫確定','出庫','実数調整','取消','出庫取消','受入取消')), qty numeric not null default 0, unit text, before_qty numeric, after_qty numeric, destination text, reason text, memo text, item_name text, lot_no text, user_id uuid, user_name text, occurred_at timestamptz not null default now(), cancelled_at timestamptz, cancelled_by_name text, reversed_movement_id uuid);
create table public.hq_reserve_stub(lot_id uuid, qty numeric);
create function public.hq_c117_available_qty(p_lot_id uuid, p_work_id uuid default null) returns numeric language sql stable as $$select l.current_qty-coalesce((select sum(qty) from public.hq_reserve_stub r where r.lot_id=l.id),0) from public.hq_lots_v1400 l where l.id=p_lot_id$$;
create table public.dest_master_v1199c160(name text primary key, formal text not null default '', kind text not null default '内', group_name text not null default '', outbound boolean not null default true, weight boolean not null default false, active boolean not null default true, sort_order integer not null default 1000);
create role anon; create role authenticated; create role service_role;
insert into public.profiles values ('00000000-0000-0000-0000-000000000001','admin',true,'管理者'),('00000000-0000-0000-0000-000000000002','buyer',true,'仕入');
'''


LOT = '10000000-0000-0000-0000-000000000001'
OUT = '20000000-0000-0000-0000-000000000001'
ADMIN = '00000000-0000-0000-0000-000000000001'
BUYER = '00000000-0000-0000-0000-000000000002'


class ReturnsSqlStaticTests(unittest.TestCase):
    def test_static_contract(self):
        self.assertIn("trimming_require_role(array['admin','worker'])", SQL)
        self.assertIn("not in ('', '廃棄', '返品')", SQL)
        self.assertIn("values ('返品', '仕入先・産地への返品', '内', '社内', true, false, 10)", SQL)
        self.assertIn("'返品入庫'", SQL)
        self.assertIn('hq_c117_available_qty', SQL)
        # 取消のときの規格の戻しは 013 のトリガーに任せる（二重に引かない）
        cancel = SQL[SQL.index('create or replace function public.cancel_qr_return_v1199c163'):SQL.index('-- 7)')]
        self.assertNotIn('update public.qr_lot_grades_v1300', cancel)


class ReturnsSqlRuntimeTests(unittest.TestCase):
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
        cls.port = '55467'
        cls.command(cls.runner + [str(BIN / 'pg_ctl'), '-D', str(cls.data), '-l', str(cls.log), '-o', f'-p {cls.port} -h 127.0.0.1 -k {cls.tmp.name}', '-w', 'start'])
        cls.base = [str(BIN / 'psql'), '-h', '127.0.0.1', '-p', cls.port, '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-X']
        cls.psql(SCHEMA)
        cls.psql(SQL)
        cls.psql(SQL)  # 2回実行しても同じ

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

    def reset(self, destination='埼玉', grade=False, hq=None, lot_qty=5, out_qty=5, weight=None, occurred_at="now() - interval '1 day'"):
        self.psql('truncate public.qr_returns_v1199c163, public.hq_lot_movements_v1400, public.hq_reserve_stub, public.hq_lots_v1400, public.qr_lot_movements, public.qr_lot_grades_v1300, public.qr_lots cascade')
        self.psql(f"insert into public.qr_lots(id,lot_no,qr_key,item_name,unit,received_date,current_qty,current_weight,status,container_type,storage_location) values('{LOT}','L-1','QR-1','テスト品','CS','2026-11-20',{lot_qty},null,'在庫あり','ダンボール','A棚')")
        meta = json.dumps({'grades': [{'grade': 'A', 'delta': -3}, {'grade': 'B', 'delta': -2}]} if grade else {})
        w = 'null' if weight is None else weight
        self.psql(f"insert into public.qr_lot_movements(id,movement_type,lot_id,lot_no,qr_key,item_name,qty,unit,destination,weight,before_quantity,after_quantity,operation_id,operation_meta,occurred_at,created_at) values ('{OUT}','出庫','{LOT}','L-1','QR-1','テスト品',{out_qty},'CS','{destination}',{w},10,5,'30000000-0000-0000-0000-000000000001','{meta}'::jsonb,{occurred_at},{occurred_at})")
        if grade:
            self.psql(f"insert into public.qr_lot_grades_v1300(lot_id,grade,current_qty) values('{LOT}','A',3),('{LOT}','B',{lot_qty-3})")
        if hq:
            status, unit, current, planned, count, per = hq
            self.psql(f"insert into public.hq_lots_v1400(id,lot_no,qr_key,source_movement_id,item_name,unit,planned_qty,current_qty,status,planned_count,unit_weight_kg) values('50000000-0000-0000-0000-000000000001','H-1','HQ-1','{OUT}','テスト品','{unit}',{planned},{current},'{status}',{count},{per})")

    def ret(self, op='40000000-0000-0000-0000-000000000001', qty=2, day=None, memo='傷み', grades='[]', role=ADMIN, movement=OUT):
        d = f"'{day}'::date" if day else "(now() at time zone 'Asia/Tokyo')::date"
        out = self.psql(f"set app.\"user\"='{role}'; select public.return_qr_to_ishioka_v1199c163('{op}','{movement}',{qty},{d},'{memo}','{grades}'::jsonb);", True)
        return json.loads(out.splitlines()[-1])

    def cancel(self, rid, op='60000000-0000-0000-0000-000000000001', reason='入れ間違い'):
        out = self.psql(f"set app.\"user\"='{ADMIN}'; select public.cancel_qr_return_v1199c163('{op}','{rid}','{reason}');", True)
        return json.loads(out.splitlines()[-1])

    def q(self, sql):
        return self.psql(sql, True)

    def returnable(self, dest='', key=''):
        out = self.psql(f"set app.\"user\"='{ADMIN}'; select public.list_qr_returnable_v1199c163('{dest}',null,null,'{key}');", True)
        return json.loads(out.splitlines()[-1])

    def test_setup_adds_return_movement_type_and_destination(self):
        self.assertIn('返品入庫', self.q("select pg_get_constraintdef(oid) from pg_constraint where conname='qr_lot_movements_movement_type_check'"))
        self.assertEqual(self.q("select kind||':'||group_name||':'||outbound from public.dest_master_v1199c160 where name='返品'"), '内:社内:true')

    def test_return_from_saitama_goes_back_to_the_original_lot(self):
        self.reset(lot_qty=0, weight=50)
        r = self.ret(qty=2)
        self.assertTrue(r['ok'], r)
        self.assertEqual((r['before_quantity'], r['after_quantity'], r['received_date']), (0, 2, '2026-11-20'))
        self.assertEqual(self.q('select current_qty||\':\'||status from public.qr_lots'), '2:在庫あり')
        row = self.q("select movement_type||'|'||destination||'|'||qty||'|'||weight||'|'||reason from public.qr_lot_movements where operation_id='40000000-0000-0000-0000-000000000001'")
        self.assertEqual(row, '返品入庫|埼玉|2|20.0|返品')
        self.assertIn('埼玉から返品', self.q("select memo from public.qr_lot_movements where movement_type='返品入庫'"))
        self.assertTrue(self.ret(qty=2)['idempotent'])
        self.assertFalse(self.ret(qty=3)['ok'])
        lst = self.returnable('埼玉')
        self.assertEqual((lst[0]['returned'], lst[0]['left']), (2, 3))
        with self.assertRaises(AssertionError):
            self.ret(op='40000000-0000-0000-0000-000000000002', qty=4)  # 残り3まで
        self.assertTrue(self.ret(op='40000000-0000-0000-0000-000000000002', qty=3)['ok'])
        self.assertEqual(self.q('select current_qty from public.qr_lots'), '5')

    def test_rejects_bad_input_and_buyer(self):
        self.reset()
        for kwargs in ({'qty': 0}, {'day': '2099-01-01'}, {'day': '2000-01-01'}, {'role': BUYER}):
            with self.subTest(**kwargs), self.assertRaises(AssertionError):
                self.ret(**kwargs)
        self.assertEqual(self.q('select count(*) from public.qr_returns_v1199c163'), '0')
        for dest in ('廃棄', '返品'):
            self.reset(destination=dest)
            self.assertEqual(self.returnable(), [])
            with self.subTest(dest=dest), self.assertRaises(AssertionError):
                self.ret()

    def test_grade_lot_returns_per_grade_and_cancel_restores_once(self):
        self.reset(grade=True, lot_qty=3)
        with self.assertRaises(AssertionError):
            self.ret(qty=2)  # 規格ごとの数が必要
        with self.assertRaises(AssertionError):
            self.ret(qty=2, grades='[{"grade":"A","qty":1}]')  # 合計が合わない
        with self.assertRaises(AssertionError):
            self.ret(qty=3, grades='[{"grade":"B","qty":3}]')  # Bは2しか出していない
        r = self.ret(qty=2, grades='[{"grade":"A","qty":1},{"grade":"B","qty":1}]')
        self.assertTrue(r['ok'], r)
        self.assertEqual(self.q("select string_agg(grade||'='||current_qty,',' order by grade) from public.qr_lot_grades_v1300"), 'A=4,B=1')
        self.assertEqual(self.q('select current_qty from public.qr_lots'), '5')
        c = self.cancel(r['return_id'])
        self.assertTrue(c['ok'], c)
        self.assertEqual(self.q("select string_agg(grade||'='||current_qty,',' order by grade) from public.qr_lot_grades_v1300"), 'A=3,B=0')
        self.assertEqual(self.q('select current_qty from public.qr_lots'), '3')
        self.assertEqual(self.q("select count(*) from public.qr_lot_movements where movement_type='返品入庫' and cancelled_at is not null"), '1')
        self.assertTrue(self.cancel(r['return_id'])['idempotent'])
        self.assertEqual(self.returnable('埼玉')[0]['left'], 5)

    def test_cancel_is_blocked_when_the_returned_stock_is_already_used(self):
        self.reset(lot_qty=0)
        r = self.ret(qty=2)
        self.psql("update public.qr_lots set current_qty=1")
        with self.assertRaises(AssertionError):
            self.cancel(r['return_id'])
        self.assertEqual(self.q('select count(*) from public.qr_returns_v1199c163 where cancelled_at is null'), '1')

    def test_return_from_hq_received_reduces_hq_stock_and_respects_reservations(self):
        self.reset(destination='本社', lot_qty=0, hq=('在庫あり', 'ケース', 5, 5, 'null', 'null'))
        self.psql("insert into public.hq_reserve_stub values('50000000-0000-0000-0000-000000000001',4)")
        with self.assertRaises(AssertionError):
            self.ret(qty=2)  # 下処理の予約で使えるのは1
        self.psql('truncate public.hq_reserve_stub')
        self.assertEqual(self.returnable(key='HQ-1')[0]['movement_id'], OUT)  # 本社のQRでも探せる
        r = self.ret(qty=2)
        self.assertEqual((r['hq_action'], r['hq_qty']), ('在庫から減らす', 2))
        self.assertEqual(self.q("select current_qty||':'||status from public.hq_lots_v1400"), '3:在庫あり')
        self.assertEqual(self.q("select movement_type||'|'||destination||'|'||qty from public.hq_lot_movements_v1400"), '出庫|石岡へ返品|2')
        self.assertTrue(self.cancel(r['return_id'])['ok'])
        self.assertEqual(self.q("select current_qty from public.hq_lots_v1400"), '5')
        self.assertEqual(self.q("select string_agg(movement_type||(cancelled_at is not null),',' order by occurred_at) from public.hq_lot_movements_v1400"), '出庫true,出庫取消false')

    def test_return_from_hq_waiting_reduces_the_plan_in_kg(self):
        self.reset(destination='本社', lot_qty=0, hq=('入荷待ち', 'kg', 0, 50, 5, 10))
        r = self.ret(qty=2)
        self.assertEqual((r['hq_action'], r['hq_qty'], r['hq_unit']), ('入荷予定を減らす', 20, 'kg'))
        self.assertEqual(self.q("select planned_qty::float||':'||planned_count||':'||status from public.hq_lots_v1400"), '30:3:入荷待ち')
        r2 = self.ret(op='40000000-0000-0000-0000-000000000002', qty=3)
        self.assertEqual(self.q("select planned_qty::float||':'||status from public.hq_lots_v1400"), '0:取消')
        self.assertTrue(self.cancel(r2['return_id'])['ok'])
        self.assertEqual(self.q("select planned_qty::float||':'||planned_count||':'||status from public.hq_lots_v1400"), '30:3:入荷待ち')

    def test_list_of_returns(self):
        self.reset(lot_qty=0)
        self.ret(qty=1, memo='品質不良')
        out = json.loads(self.psql(f"set app.\"user\"='{BUYER}'; select public.list_qr_returns_v1199c163(10);", True).splitlines()[-1])
        self.assertEqual((out[0]['from'], out[0]['qty'], out[0]['memo'], out[0]['received_date']), ('埼玉', 1, '品質不良', '2026-11-20'))


if __name__ == '__main__':
    unittest.main()
