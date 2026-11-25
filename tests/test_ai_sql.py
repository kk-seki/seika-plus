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
SQL = (ROOT / 'db/068_AI導入.sql').read_text(encoding='utf-8')
SCRATCH = Path('/tmp/jai-scratch/c165')
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
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('app.user',true),'')::uuid$$;
create function auth.role() returns text language sql stable as $$select 'authenticated'::text$$;
create table public.profiles(id uuid primary key, role text not null, active boolean not null default true, display_name text);
create function public.current_app_role() returns text language sql stable security definer as $$select role from public.profiles where id=auth.uid() and active$$;
create function public.seika_require_role_v1240(p_roles text[]) returns void language plpgsql security definer as $$begin if not exists(select 1 from public.profiles where id=auth.uid() and active and role=any(p_roles)) then raise exception '権限がありません' using errcode='42501'; end if; end$$;
create table public.qr_lots(id uuid primary key default gen_random_uuid(), active boolean default true, item_name text, unit text, current_qty numeric, current_weight numeric, received_date date);
create table public.qr_lot_movements(id uuid primary key default gen_random_uuid(), movement_type text, item_name text, destination text, unit text, qty numeric, weight numeric, cancelled_at timestamptz, occurred_at timestamptz default now());
create table public.waste_records(id text primary key, waste_date date, item_name text, qty numeric, amount numeric);
create table public.ship_plan_imports_v1199c140(id uuid primary key, delivery_date date, status text);
create table public.ship_plan_lines_v1199c140(id bigserial primary key, import_id uuid, delivery_date date, customer_name text, item_name text, kg numeric, cases integer);
create table public.ship_actual_imports_v1199c142(id uuid primary key, delivery_date date, status text);
create table public.ship_actual_lines_v1199c142(id bigserial primary key, import_id uuid, delivery_date date, customer_name text, item_name text, kg numeric, cases integer);
create table public.trimming_jobs(id uuid primary key default gen_random_uuid(), work_date date, source_item_name text, input_weight_kg numeric, output_weight_kg numeric, loss_weight_kg numeric, waste_weight_kg numeric);
create table public.qr_quality_evaluations(id uuid primary key default gen_random_uuid(), item_name text, lot_no text, grade text, issues jsonb, memo text, evaluated_at timestamptz default now(), active boolean default true, invalidated_at timestamptz);
create table public.qr_gap_certs_v1199c130(coop_name text, item_name text, certification text, expires_on date);
create table public.purchase_prices(id uuid primary key default gen_random_uuid(), week_start date, item_name text, origin text, price_yen_per_kg numeric);
create role anon; create role authenticated; create role service_role;
insert into public.profiles values ('00000000-0000-0000-0000-000000000001','admin',true,'管理者'),('00000000-0000-0000-0000-000000000002','sales',true,'営業'),('00000000-0000-0000-0000-000000000003','clerk',true,'事務'),('00000000-0000-0000-0000-000000000004','buyer',true,'仕入');
'''

ADMIN, SALES, CLERK, BUYER = ('00000000-0000-0000-0000-00000000000' + str(i) for i in (1, 2, 3, 4))


class AiSqlStaticTests(unittest.TestCase):
    def test_read_only_and_roles(self):
        fn = SQL[SQL.index('create or replace function public.ai_data_v1199c165'):]
        fn = fn[:fn.index('$f$;')]
        for w in ('insert into', 'update public', 'delete from'):
            self.assertNotIn(w, fn.lower())
        self.assertIn("seika_require_role_v1240(array['admin','worker','buyer','sales'])", fn)
        self.assertIn("v_role not in ('admin','buyer')", fn)
        self.assertIn('grant all on public.ai_usage_v1199c165 to service_role', SQL)
        self.assertIn("revoke all on public.ai_usage_v1199c165 from public, anon, authenticated", SQL)


class AiSqlRuntimeTests(unittest.TestCase):
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
        cls.port = '55468'
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

    def q(self, user, sql):
        return self.psql(f"set app.\"user\"='{user}'; {sql}", True).splitlines()[-1]

    def ai(self, user, kind, a="null", b="null", item="null", cust="null"):
        return json.loads(self.q(user, f"select public.ai_data_v1199c165('{kind}',{a},{b},{item},{cust});"))

    def test_setup(self):
        self.psql("truncate public.qr_lots, public.qr_lot_movements, public.waste_records, public.ship_plan_imports_v1199c140, public.ship_plan_lines_v1199c140, public.ship_actual_imports_v1199c142, public.ship_actual_lines_v1199c142, public.purchase_prices")
        self.psql("""insert into public.qr_lots(item_name,unit,current_qty,current_weight,received_date) values ('キャベツ','CS',5,50,'2026-11-20'),('キャベツ','CS',3,30,'2026-11-18'),('人参','CS',0,0,'2026-11-18');
          insert into public.qr_lot_movements(movement_type,item_name,destination,unit,qty,weight,occurred_at) values ('出庫','キャベツ','埼玉','CS',2,20,now()),('出庫','キャベツ','埼玉','CS',1,10,now()),('出庫','キャベツ','埼玉','CS',9,90,now()-interval '1 day'),('廃棄','キャベツ',null,'CS',1,null,now());
          update public.qr_lot_movements set cancelled_at=now() where qty=9;
          insert into public.waste_records values ('w1',current_date,'キャベツ',4,800);
          insert into public.ship_plan_imports_v1199c140 values ('10000000-0000-0000-0000-000000000001',current_date,'active'),('10000000-0000-0000-0000-000000000002',current_date,'replaced');
          insert into public.ship_plan_lines_v1199c140(import_id,delivery_date,customer_name,item_name,kg,cases) values ('10000000-0000-0000-0000-000000000001',current_date,'美野里デリカ','キャベツ',100,10),('10000000-0000-0000-0000-000000000002',current_date,'美野里デリカ','キャベツ',999,99);
          insert into public.ship_actual_imports_v1199c142 values ('20000000-0000-0000-0000-000000000001',current_date,'active');
          insert into public.ship_actual_lines_v1199c142(import_id,delivery_date,customer_name,item_name,kg,cases) values ('20000000-0000-0000-0000-000000000001',current_date,'美野里デリカ','キャベツ',80,8);
          insert into public.purchase_prices(week_start,item_name,origin,price_yen_per_kg) values (current_date,'キャベツ','茨城',120);""")
        stock = self.ai(ADMIN, 'stock')['rows']
        self.assertEqual([(r['item'], r['qty'], r['lots'], r['oldest_received']) for r in stock], [('キャベツ', 8, 2, '2026-11-18')])
        out = self.ai(SALES, 'outbound', item="'キャ'")['rows']
        self.assertEqual([(r['destination'], r['qty'], r['times']) for r in out], [('埼玉', 3, 2)])  # 取消は入らない
        waste = {r['source']: r['qty'] for r in self.ai(ADMIN, 'waste')['rows']}
        self.assertEqual(waste, {'廃棄記録': 4, 'QR廃棄': 1})
        plan = self.ai(SALES, 'plan')['rows']
        self.assertEqual([(r['customer'], r['kg']) for r in plan], [('美野里デリカ', 100)])  # 置き換え済みは入らない
        pva = self.ai(SALES, 'plan_vs_actual')['rows']
        self.assertEqual([(r['plan_kg'], r['actual_kg'], r['diff_kg']) for r in pva], [(100, 80, -20)])
        self.assertEqual(self.ai(BUYER, 'prices')['rows'][0]['yen_per_kg'], 120)
        self.assertTrue(self.ai(SALES, 'prices').get('denied'))
        for bad in ((CLERK, "'stock'"), (ADMIN, "'unknown'")):
            with self.subTest(bad=bad), self.assertRaises(AssertionError):
                self.q(bad[0], f"select public.ai_data_v1199c165({bad[1]});")
        with self.assertRaises(AssertionError):
            self.q(ADMIN, "select public.ai_data_v1199c165('outbound','2026-01-01','2026-11-01');")
        with self.assertRaises(AssertionError):
            self.q(SALES, "select public.ai_usage_month_v1199c165();")
        self.psql("insert into public.ai_usage_v1199c165(action,cost_usd) values ('ask',0.01),('summary',0.02)")
        u = json.loads(self.q(ADMIN, "select public.ai_usage_month_v1199c165();"))
        self.assertEqual((u['calls'], float(u['cost_usd'])), (2, 0.03))


if __name__ == '__main__':
    unittest.main()
