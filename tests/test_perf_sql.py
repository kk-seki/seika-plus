"""c152：動作の重さの記録（db/063）を、使い捨てのPostgreSQLで確認する。"""
import json
import os
import pwd
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SQL_063 = next((ROOT / 'db').glob('063_*.sql')).read_text(encoding='utf-8')
SCRATCH = Path('/tmp/jai-scratch/c152')
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


class PerfSqlRuntimeTests(unittest.TestCase):
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
        cls.port = '55463'
        cls.command(cls.runner + [str(BIN / 'pg_ctl'), '-D', str(cls.data), '-l', str(cls.log), '-o', f'-p {cls.port} -h 127.0.0.1 -k {cls.tmp.name}', '-w', 'start'])
        cls.base = [str(BIN / 'psql'), '-h', '127.0.0.1', '-p', cls.port, '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-X']
        cls.psql(SCHEMA)
        cls.psql(SQL_063)
        cls.psql(SQL_063)  # 2回実行しても同じ

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
        self.psql('truncate public.app_perf_logs_v1199c152')

    def send(self, rows, user=WORKER):
        return int(self.val(f"set app.\"user\"='{user}'; select public.log_app_perf_v1199c152('{json.dumps(rows, ensure_ascii=False)}'::jsonb);"))

    def test_any_signed_in_user_can_send_only_their_own(self):
        n = self.send([{'kind': 'net', 'name': 'rest:app_state', 'ms': 1234.5, 'bytes': 2500000, 'screen': 'home', 'role': 'worker', 'extra': {'status': 200}},
                       {'kind': 'page', 'name': 'weeklyData', 'ms': '800', 'screen': 'weekly'}], HQ)
        self.assertEqual(n, 2)
        self.assertEqual(self.val("select count(*) from public.app_perf_logs_v1199c152 where user_id='" + HQ + "'"), '2')
        self.assertEqual(self.val("select name||'/'||ms||'/'||bytes from public.app_perf_logs_v1199c152 where kind='net'"), 'rest:app_state/1234.5/2500000')

    def test_not_signed_in_cannot_send_and_bad_values_are_cut(self):
        with self.assertRaises(AssertionError):
            self.send([{'kind': 'net'}], '')
        self.send([{'kind': 'x' * 50, 'name': 'n' * 500, 'ms': 'abc', 'bytes': '-5', 'extra': {'a': 'b' * 3000}}])
        self.assertEqual(self.val("select length(kind)||'/'||length(name)||'/'||coalesce(ms::text,'空')||'/'||coalesce(bytes::text,'空')||'/'||extra::text from public.app_perf_logs_v1199c152"), '20/200/空/空/{}')

    def test_at_most_200_per_call_and_old_rows_are_removed(self):
        self.psql("insert into public.app_perf_logs_v1199c152(at,kind) values (now()-interval '40 days','old')")
        self.assertEqual(self.send([{'kind': 'net', 'name': str(i)} for i in range(250)]), 200)
        self.assertEqual(self.val("select count(*) from public.app_perf_logs_v1199c152 where kind='old'"), '0')

    def test_only_admin_reads_and_nobody_writes_directly(self):
        sql = SQL_063
        self.assertIn("has_any_role(array['admin'])", sql)
        self.assertIn('revoke insert, update, delete on public.app_perf_logs_v1199c152 from anon, authenticated', sql)
        self.assertNotIn('app_state', sql[sql.index('begin;'):].replace("'rest:app_state'", ''))


if __name__ == '__main__':
    unittest.main()
