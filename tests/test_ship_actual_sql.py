"""c142：確定数量の取り込み（db/062）を、使い捨てのPostgreSQLで確認する。"""
import json
import os
import pwd
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SQL_061 = next((ROOT / 'db').glob('061_*.sql')).read_text(encoding='utf-8')
SQL_062 = next((ROOT / 'db').glob('062_*.sql')).read_text(encoding='utf-8')
SCRATCH = Path('/tmp/jai-scratch/c142')
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
'''


class ShipActualSqlStaticTests(unittest.TestCase):
    def test_writes_go_through_functions_with_roles(self):
        for fn, roles in (('replace_ship_actual_v1199c142', "array['admin','worker','clerk']"), ('save_ship_customer_alias_v1199c142', "array['admin','worker','clerk']"),
                          ('delete_ship_customer_alias_v1199c142', "array['admin']")):
            body = SQL_062[SQL_062.index(f'function public.{fn}'):]
            body = body[:body.index('$f$;')]
            self.assertIn(f'seika_require_role_v1240({roles})', body, fn)
        self.assertNotIn('qr_lots', SQL_062)
        self.assertNotIn('app_state', SQL_062)


class ShipActualSqlRuntimeTests(unittest.TestCase):
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
        cls.port = '55462'
        cls.command(cls.runner + [str(BIN / 'pg_ctl'), '-D', str(cls.data), '-l', str(cls.log), '-o', f'-p {cls.port} -h 127.0.0.1 -k {cls.tmp.name}', '-w', 'start'])
        cls.base = [str(BIN / 'psql'), '-h', '127.0.0.1', '-p', cls.port, '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-X']
        cls.psql(SCHEMA)
        cls.psql(SQL_061)
        cls.psql(SQL_062)
        cls.psql(SQL_062)  # 2回実行しても同じ

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

    def setUp(self):
        self.psql('truncate public.ship_actual_lines_v1199c142, public.ship_actual_imports_v1199c142 cascade')

    def actual(self, iid, date, lines, user=WORKER):
        return self.rpc(f"public.replace_ship_actual_v1199c142('{iid}'::uuid,'{date}'::date,'産地報告.xlsx','[]'::jsonb,'{json.dumps(lines, ensure_ascii=False)}'::jsonb)", user)

    L1 = [{'customer_raw': '架空デリカ 龍ケ崎工場', 'customer_name': '架空デリカ 龍ヶ崎工場', 'item_name': '人参', 'item_raw': '人参', 'kg': 200, 'boxes': 14, 'origin': '北海道', 'coop': 'JA道央'},
          {'customer_raw': '架空フーズ', 'customer_name': '架空フーズ', 'item_name': 'キャベツ', 'item_raw': 'キャベツ', 'kg': 120, 'pack_kg': 10},
          {'customer_raw': '架空フーズ', 'customer_name': '架空フーズ', 'item_name': '大葉', 'item_raw': '大葉', 'kg': 3, 'pack_kg': 3}]

    def test_saves_and_replaces_keeping_the_old_one(self):
        out = self.actual('11111111-1111-1111-1111-111111111111', '2026-12-01', self.L1)
        self.assertEqual((out['count'], out['replaced']), (3, False))
        self.assertEqual(self.psql("select item_name||'/'||cases||'/'||has_fraction||'/'||origin||'/'||customer_raw from public.ship_actual_lines_v1199c142 order by line_no limit 1", True), '人参/14/true/北海道/架空デリカ 龍ケ崎工場')
        self.assertEqual(self.val("select ship_date from public.ship_actual_imports_v1199c142"), '2026-11-30')
        out = self.actual('22222222-2222-2222-2222-222222222222', '2026-12-01', self.L1[:1], CLERK)
        self.assertTrue(out['replaced'])
        self.assertEqual(self.psql("select string_agg(status,',' order by imported_at, id) from public.ship_actual_imports_v1199c142", True), 'replaced,active')
        self.assertTrue(self.actual('22222222-2222-2222-2222-222222222222', '2026-12-01', self.L1)['again'])
        self.assertEqual(self.val("select count(*) from public.ship_actual_lines_v1199c142"), '4')

    def test_roles_bad_rows_and_read_policy(self):
        for user in (BUYER, HQ):
            with self.subTest(user=user), self.assertRaises(AssertionError):
                self.actual('33333333-3333-3333-3333-333333333333', '2026-12-02', self.L1, user)
        for bad in ([{'customer_name': '', 'item_name': '人参', 'kg': 1}], [{'customer_name': 'a', 'item_name': '', 'kg': 1}], [{'customer_name': 'a', 'item_name': '人参', 'kg': -1}], []):
            with self.subTest(bad=bad), self.assertRaises(AssertionError):
                self.actual('33333333-3333-3333-3333-333333333333', '2026-12-02', bad)
        self.rpc("public.save_ship_customer_alias_v1199c142('架空フーズ','架空フーズ','架空フーズ(八千代)')", WORKER)
        self.assertEqual(self.val("select customer_name from public.ship_customer_aliases_v1199c142"), '架空フーズ(八千代)')
        with self.assertRaises(AssertionError):
            self.rpc("public.delete_ship_customer_alias_v1199c142('架空フーズ')", CLERK)
        self.rpc("public.delete_ship_customer_alias_v1199c142('架空フーズ')", ADMIN)
        self.assertEqual(self.val("select count(*) from public.ship_customer_aliases_v1199c142"), '0')
        self.actual('44444444-4444-4444-4444-444444444444', '2026-12-03', self.L1)
        self.psql("grant usage on schema public to authenticated; grant execute on function public.has_any_role(text[]), public.current_app_role() to authenticated")
        seen = lambda user: self.val(f"set app.\"user\"='{user}'; set role authenticated; select count(*) from public.ship_actual_lines_v1199c142")
        self.assertEqual(seen(BUYER), '3')
        self.assertEqual(seen(HQ), '0')


if __name__ == '__main__':
    unittest.main()
