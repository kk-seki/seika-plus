"""c154：営業担当の客先（db/064）を、使い捨てのPostgreSQLで確認する。"""
import json
import os
import pwd
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SQL_064 = next((ROOT / 'db').glob('064_*.sql')).read_text(encoding='utf-8')
SCRATCH = Path('/tmp/jai-scratch/c154')
TIMEOUT = 30
ADMIN = '00000000-0000-0000-0000-000000000001'
WORKER = '00000000-0000-0000-0000-000000000002'
BUYER = '00000000-0000-0000-0000-000000000003'
CLERK = '00000000-0000-0000-0000-000000000004'
HQ = '00000000-0000-0000-0000-000000000005'


def find_pg_bin():
    path = shutil.which('initdb')
    if path:
        return Path(path).parent
    candidates = sorted(Path('/usr/lib/postgresql').glob('*/bin/initdb'))
    return candidates[-1].parent if candidates else None


BIN = find_pg_bin()

SCHEMA = r'''
create extension if not exists pgcrypto;
create schema auth;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('app.user',true),'')::uuid$$;
create function auth.role() returns text language sql stable as $$select 'authenticated'$$;
create role anon; create role authenticated; create role service_role;
create table public.profiles(id uuid primary key, role text not null, active boolean not null default true, display_name text);
create function public.seika_require_role_v1240(p_roles text[]) returns void language plpgsql security definer as $$
declare v text; begin select role into v from public.profiles where id=auth.uid() and active;
if v is null or not (v = any(p_roles)) then raise exception '権限がありません' using errcode='42501'; end if; end $$;
create function public.current_app_role() returns text language sql stable security definer as $$select role from public.profiles where id=auth.uid() and active$$;
create function public.has_any_role(allowed_roles text[]) returns boolean language sql stable security definer as $$select coalesce(public.current_app_role() = any(allowed_roles), false)$$;
insert into public.profiles values ('00000000-0000-0000-0000-000000000001','admin',true,'管理者'),
 ('00000000-0000-0000-0000-000000000002','worker',true,'社員'),('00000000-0000-0000-0000-000000000003','buyer',true,'仕入'),
 ('00000000-0000-0000-0000-000000000004','clerk',true,'事務'),('00000000-0000-0000-0000-000000000005','hq_prep',true,'下処理');
alter table public.profiles add column legacy_user_id text;
insert into public.profiles(id,role,active,display_name,legacy_user_id) values
 ('00000000-0000-0000-0000-000000000011','buyer',true,'斎藤 大明','saito_dai'),('00000000-0000-0000-0000-000000000012','sales',true,'斎藤 綾香','sales_saito_ayaka'),
 ('00000000-0000-0000-0000-000000000013','sales',true,'蕨岡 愛姫','sales_warabioka_aki'),('00000000-0000-0000-0000-000000000014','buyer',true,'坂本 美穂','sakamoto'),
 ('00000000-0000-0000-0000-000000000015','buyer',true,'吉田 智彦','yoshida'),('00000000-0000-0000-0000-000000000016','sales',false,'退職 太郎','old'),
 ('00000000-0000-0000-0000-000000000017','viewer',true,'閲覧者','viewer1');
'''


class SalesCustomersSqlRuntimeTests(unittest.TestCase):
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
        cls.port = '55464'
        cls.command(cls.runner + [str(BIN / 'pg_ctl'), '-D', str(cls.data), '-l', str(cls.log), '-o', f'-p {cls.port} -h 127.0.0.1 -k {cls.tmp.name}', '-w', 'start'])
        cls.base = [str(BIN / 'psql'), '-h', '127.0.0.1', '-p', cls.port, '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-X']
        cls.psql(SCHEMA)
        cls.psql(SQL_064)
        cls.psql(SQL_064)  # 2回実行しても同じ

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

    def val(self, sql):
        return self.psql(sql, True).splitlines()[-1]

    def rpc(self, call, user=ADMIN):
        return json.loads(self.val(f"set app.\"user\"='{user}'; select {call};"))

    def call(self, sql, user):
        return self.val(f"set app.\"user\"='{user}'; {sql}")

    def test_seeded_from_card_and_idempotent(self):
        self.assertEqual(self.val("select count(*) from public.ship_sales_customers_v1199c154"), '27')
        self.assertEqual(self.val("select count(*) from public.ship_sales_customers_v1199c154 where staff_profile_id is null"), '0')
        self.assertEqual(self.val("select p.display_name from public.ship_sales_customers_v1199c154 r join public.profiles p on p.id=r.staff_profile_id where keyword='虎昭'"), '斎藤 大明')
        self.assertEqual(self.val("select p.display_name from public.ship_sales_customers_v1199c154 r join public.profiles p on p.id=r.staff_profile_id where keyword='東部アシード'"), '蕨岡 愛姫')

    def test_list_returns_rules_and_only_active_buyer_sales(self):
        out = json.loads(self.call("select public.list_sales_customers_v1199c154()::text;", BUYER))
        names = sorted(s['display_name'] for s in out['staff'])
        self.assertIn('蕨岡 愛姫', names)
        self.assertIn('斎藤 大明', names)
        self.assertNotIn('退職 太郎', names)
        self.assertNotIn('閲覧者', names)
        self.assertEqual(len(out['rules']), 27)
        with self.assertRaises(AssertionError):
            self.call("select public.list_sales_customers_v1199c154();", HQ)

    def test_worker_saves_and_deletes_buyer_cannot(self):
        sales = '00000000-0000-0000-0000-000000000013'
        self.call(f"select public.save_sales_customer_v1199c154(null,'  ティキュー シー ','{sales}');", WORKER)
        self.assertEqual(self.val("select keyword||'/'||updated_by_name from public.ship_sales_customers_v1199c154 where keyword like 'ティキュー%'"), 'ティキュー シー/社員')
        rid = self.val("select id from public.ship_sales_customers_v1199c154 where keyword='虎昭'")
        self.call(f"select public.save_sales_customer_v1199c154({rid},'虎昭産業','{sales}');", ADMIN)
        self.assertEqual(self.val(f"select keyword from public.ship_sales_customers_v1199c154 where id={rid}"), '虎昭産業')
        with self.assertRaises(AssertionError):
            self.call(f"select public.save_sales_customer_v1199c154(null,'X','{sales}');", BUYER)
        with self.assertRaises(AssertionError):  # 担当者は有効な仕入れ・営業担当者だけ
            self.call("select public.save_sales_customer_v1199c154(null,'Y','00000000-0000-0000-0000-000000000017');", WORKER)
        with self.assertRaises(AssertionError):  # 同じ言葉は2つ作れない
            self.call(f"select public.save_sales_customer_v1199c154({rid},'成城石井','{sales}');", WORKER)
        self.call(f"select public.delete_sales_customer_v1199c154({rid});", WORKER)
        self.assertEqual(self.val(f"select count(*) from public.ship_sales_customers_v1199c154 where id={rid}"), '0')
        self.call("select public.save_sales_customer_v1199c154(null,'虎昭',(select id from public.profiles where display_name='斎藤 大明'));", WORKER)

    def test_no_direct_writes_and_nothing_else_touched(self):
        self.assertIn('revoke all on public.ship_sales_customers_v1199c154 from public, anon, authenticated', SQL_064)
        for word in ('qr_lots', 'app_state', 'ship_plan_lines', 'ship_actual_lines'):
            self.assertNotIn(word, SQL_064)


if __name__ == '__main__':
    unittest.main()
