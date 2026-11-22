"""c140：出荷予定の取り込み（db/061）を、使い捨てのPostgreSQLで確認する。"""
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
SCRATCH = Path('/tmp/jai-scratch/c140')
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


class ShipPlanSqlStaticTests(unittest.TestCase):
    def test_writes_go_through_functions_with_roles(self):
        for fn, roles in (('replace_ship_plan_v1199c140', "array['admin','worker','clerk']"), ('save_ship_plan_alias_v1199c140', "array['admin','worker','clerk']"),
                          ('delete_ship_plan_alias_v1199c140', "array['admin']"), ('save_ship_plan_case_std_v1199c140', "array['admin']")):
            body = SQL_061[SQL_061.index(f'function public.{fn}'):]
            body = body[:body.index('$f$;')]
            self.assertIn(f'seika_require_role_v1240({roles})', body, fn)
        self.assertNotIn('qr_lots', SQL_061)
        self.assertNotIn('app_state', SQL_061)


class ShipPlanSqlRuntimeTests(unittest.TestCase):
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
        cls.port = '55461'
        cls.command(cls.runner + [str(BIN / 'pg_ctl'), '-D', str(cls.data), '-l', str(cls.log), '-o', f'-p {cls.port} -h 127.0.0.1 -k {cls.tmp.name}', '-w', 'start'])
        cls.base = [str(BIN / 'psql'), '-h', '127.0.0.1', '-p', cls.port, '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-X']
        cls.psql(SCHEMA)
        cls.psql(SQL_061)
        cls.psql(SQL_061)  # 2回実行しても同じ

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
        self.psql('truncate public.ship_plan_lines_v1199c140, public.ship_plan_imports_v1199c140 cascade')

    def plan(self, iid, date, lines, user=WORKER):
        return self.rpc(f"public.replace_ship_plan_v1199c140('{iid}'::uuid,'{date}'::date,'[]'::jsonb,'{json.dumps(lines, ensure_ascii=False)}'::jsonb)", user)

    L1 = [{'customer_name': '架空デリカ', 'item_name': '人参', 'item_raw': '人参 10kg', 'unit': 'cs', 'kg': 50, 'boxes': 4},
          {'customer_name': '架空デリカ', 'item_name': 'キャベツ', 'item_raw': 'キャベツ 10kg', 'unit': 'cs', 'kg': 120, 'pack_kg': 10},
          {'customer_name': '架空フーズ', 'item_name': '大葉', 'item_raw': '大葉 3kg', 'unit': 'cs', 'kg': 6, 'pack_kg': 3},
          {'customer_name': '架空フーズ', 'item_name': '牛蒡', 'item_raw': '牛蒡', 'unit': 'kg', 'kg': 250}]

    def test_saves_lines_with_ship_date_and_rounded_up_cases(self):
        out = self.plan('11111111-1111-1111-1111-111111111111', '2026-12-01', self.L1)
        self.assertEqual((out['count'], out['replaced']), (4, False))
        self.assertEqual(self.val("select ship_date from public.ship_plan_imports_v1199c140"), '2026-11-30')  # 月をまたいでも前日
        rows = self.psql("select item_name||'/'||coalesce(cases::text,'-')||'/'||has_fraction||'/'||coalesce(case_std_kg::text,'-') from public.ship_plan_lines_v1199c140 order by line_no", True).splitlines()
        self.assertEqual(rows, ['人参/4/true/15', 'キャベツ/12/false/10', '大葉/2/false/3', '牛蒡/-/false/-'])
        self.assertEqual(self.val("select total_kg from public.ship_plan_imports_v1199c140"), '426')

    def test_same_date_replaces_and_keeps_the_old_import(self):
        self.plan('11111111-1111-1111-1111-111111111111', '2026-12-01', self.L1)
        out = self.plan('22222222-2222-2222-2222-222222222222', '2026-12-01', self.L1[:1], CLERK)
        self.assertTrue(out['replaced'])
        self.assertEqual(self.psql("select id||'/'||status||'/'||coalesce(replaced_by::text,'-') from public.ship_plan_imports_v1199c140 order by imported_at, id", True).splitlines(),
                         ['11111111-1111-1111-1111-111111111111/replaced/22222222-2222-2222-2222-222222222222', '22222222-2222-2222-2222-222222222222/active/-'])
        self.assertEqual(self.val("select count(*) from public.ship_plan_lines_v1199c140"), '5')   # 前の明細も残る
        again = self.plan('22222222-2222-2222-2222-222222222222', '2026-12-01', self.L1)  # 二重押し
        self.assertTrue(again['again'])
        self.assertEqual(self.val("select count(*) from public.ship_plan_imports_v1199c140"), '2')

    def test_roles_and_bad_rows(self):
        for user in (BUYER, HQ):
            with self.subTest(user=user), self.assertRaises(AssertionError):
                self.plan('33333333-3333-3333-3333-333333333333', '2026-12-02', self.L1, user)
        for bad in ([{'customer_name': '', 'item_name': '人参', 'unit': 'cs', 'kg': 1}], [{'customer_name': 'a', 'item_name': '', 'unit': 'cs', 'kg': 1}],
                    [{'customer_name': 'a', 'item_name': '人参', 'unit': 'cs', 'kg': -1}], [{'customer_name': 'a', 'item_name': '人参', 'unit': '箱', 'kg': 1}], []):
            with self.subTest(bad=bad), self.assertRaises(AssertionError):
                self.plan('33333333-3333-3333-3333-333333333333', '2026-12-02', bad)
        self.assertEqual(self.val("select count(*) from public.ship_plan_imports_v1199c140"), '0')

    def test_masters_and_read_policy(self):
        self.rpc("public.save_ship_plan_alias_v1199c140('大根','大根','カット大根',true)", WORKER)
        self.assertEqual(self.val("select item_name from public.ship_plan_item_aliases_v1199c140 where raw_key='大根'"), 'カット大根')
        with self.assertRaises(AssertionError):
            self.rpc("public.delete_ship_plan_alias_v1199c140('大根')", WORKER)
        with self.assertRaises(AssertionError):
            self.rpc("public.save_ship_plan_case_std_v1199c140('白菜',15)", CLERK)
        self.rpc("public.save_ship_plan_case_std_v1199c140('白菜',15)", ADMIN)
        self.rpc("public.delete_ship_plan_alias_v1199c140('大根')", ADMIN)
        self.assertEqual(self.val("select string_agg(item_name||'='||case_kg,',' order by item_name) from public.ship_plan_case_std_v1199c140"), 'カット大根=15,キャベツ=10,人参=15,白菜=15,葉付き大根=15')
        self.plan('44444444-4444-4444-4444-444444444444', '2026-12-03', self.L1)
        self.psql("grant usage on schema public to authenticated; grant execute on function public.has_any_role(text[]), public.current_app_role() to authenticated")
        seen = lambda user: self.val(f"set app.\"user\"='{user}'; set role authenticated; select count(*) from public.ship_plan_lines_v1199c140")
        self.assertEqual(seen(BUYER), '4')
        self.assertEqual(seen(HQ), '0')
        with self.assertRaises(AssertionError):
            self.psql(f"set app.\"user\"='{ADMIN}'; set role authenticated; delete from public.ship_plan_lines_v1199c140 where true")


if __name__ == '__main__':
    unittest.main()
