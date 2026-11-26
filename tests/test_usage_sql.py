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
SQL = (ROOT / 'db/071_アカウント別の利用状況.sql').read_text(encoding='utf-8')
SCRATCH = Path('/tmp/jai-scratch/c168')
TIMEOUT = 30


def find_pg_bin():
    for executable in ('initdb',):
        path = shutil.which(executable)
        if path:
            return Path(path).parent
    candidates = sorted(Path('/usr/lib/postgresql').glob('*/bin/initdb'))
    return candidates[-1].parent if candidates else None


BIN = find_pg_bin()
HIRATA = '58b4e90d-43cf-48ad-970f-ef1a884467dd'
ADMIN = '00000000-0000-0000-0000-000000000001'
WORKER = '00000000-0000-0000-0000-000000000002'

SCHEMA = r'''
create extension if not exists pgcrypto;
create schema auth;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('app.user',true),'')::uuid$$;
create table public.profiles(id uuid primary key, role text not null, active boolean not null default true, display_name text, legacy_user_id text);
create table public.app_perf_logs_v1199c152(id bigserial primary key, at timestamptz, user_id uuid, kind text, screen text);
create table public.qr_lots(id uuid primary key default gen_random_uuid(), user_id text, created_at timestamptz default now());
create table public.qr_lot_movements(id uuid primary key default gen_random_uuid(), movement_type text, user_id text, occurred_at timestamptz default now());
create table public.qr_scan_logs(id uuid primary key default gen_random_uuid(), user_id text, scanned_at timestamptz default now());
create table public.waste_records(id text primary key, user_id text, created_at timestamptz default now());
create table public.trimming_jobs(id uuid primary key default gen_random_uuid(), created_by uuid, created_at timestamptz default now());
create table public.hq_lot_movements_v1400(id uuid primary key default gen_random_uuid(), user_id uuid, occurred_at timestamptz default now());
create table public.qr_returns_v1199c163(id uuid primary key default gen_random_uuid(), created_by uuid, created_at timestamptz default now());
create role anon; create role authenticated; create role service_role;
insert into public.profiles values ('58b4e90d-43cf-48ad-970f-ef1a884467dd','admin',true,'平田 祐希','hirata'),
 ('00000000-0000-0000-0000-000000000001','admin',true,'ほかの管理者','admin2'),
 ('00000000-0000-0000-0000-000000000002','worker',true,'青果社員','furenki'),
 ('00000000-0000-0000-0000-000000000003','worker',false,'やめた人','old');
'''


class UsageSqlTests(unittest.TestCase):
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
        cls.port = '55471'
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

    def q(self, user, sql):
        return self.psql(f"set app.\"user\"='{user}'; {sql}", True).splitlines()[-1]

    def test_only_hirata_can_view(self):
        self.assertEqual(self.q(HIRATA, 'select public.can_view_usage_v1199c168()'), 't')
        self.assertEqual(self.q(ADMIN, 'select public.can_view_usage_v1199c168()'), 'f')
        for who in (ADMIN, WORKER):
            with self.assertRaises(AssertionError) as e:
                self.q(who, 'select public.usage_by_account_v1199c168(7)')
            self.assertIn('この画面は見られません', str(e.exception))

    def test_counts_per_account(self):
        self.psql(f"""truncate public.app_perf_logs_v1199c152, public.qr_lots, public.qr_lot_movements, public.qr_scan_logs, public.waste_records, public.trimming_jobs, public.hq_lot_movements_v1400, public.qr_returns_v1199c163;
          insert into public.app_perf_logs_v1199c152(at,user_id,kind,screen) values
            (now(),'{WORKER}','net','qrHome'),(now(),'{WORKER}','net','qrHome'),(now()-interval '1 day','{WORKER}','net','qrHome'),(now(),'{WORKER}','net','home'),
            (now(),'{WORKER}','net','login'),(now()-interval '20 days','{WORKER}','net','weeklyData');
          insert into public.qr_lots(user_id) values ('furenki'),('furenki');
          insert into public.qr_lot_movements(movement_type,user_id) values ('出庫','furenki'),('廃棄','furenki'),('棚卸し調整増','furenki'),('場所移動','furenki'),('出庫','hirata');
          insert into public.qr_scan_logs(user_id) values ('furenki');
          insert into public.waste_records values ('w1','furenki',now());
          insert into public.trimming_jobs(created_by) values ('{WORKER}');
          insert into public.hq_lot_movements_v1400(user_id) values ('{WORKER}');
          insert into public.qr_returns_v1199c163(created_by,created_at) values ('{WORKER}',now()-interval '40 days');""")
        r = json.loads(self.q(HIRATA, 'select public.usage_by_account_v1199c168(7)'))
        self.assertEqual(r['days'], 7)
        rows = {x['name']: x for x in r['rows']}
        self.assertNotIn('やめた人', rows)  # 無効のアカウントは出さない
        w = rows['青果社員']
        self.assertEqual(w['screen_days'], 2)
        self.assertEqual(w['screens'], 3)  # qrHome・home・login（20日前の weeklyData は入らない）
        self.assertEqual([s['screen'] for s in w['top_screens']], ['qrHome', 'home'])  # login は出さない
        self.assertEqual(w['top_screens'][0]['days'], 2)
        self.assertEqual(w['ops'], {'入荷': 2, '出庫': 1, '廃棄': 2, '棚卸し': 1, 'そのほか': 1, 'スキャン': 1, '下処理の日報': 1, '本社の操作': 1})
        self.assertEqual(w['ops_total'], 10)
        self.assertEqual(rows['平田 祐希']['ops'], {'出庫': 1})
        self.assertIsNone(rows['ほかの管理者']['last_seen'])
        self.assertEqual(rows['ほかの管理者']['days'], 0)
        # 30日にすると20日前の画面も入る。返品（40日前）は90日で入る
        r30 = {x['name']: x for x in json.loads(self.q(HIRATA, 'select public.usage_by_account_v1199c168(30)'))['rows']}
        self.assertEqual(r30['青果社員']['screens'], 4)
        r90 = {x['name']: x for x in json.loads(self.q(HIRATA, 'select public.usage_by_account_v1199c168(500)'))['rows']}
        self.assertEqual(r90['青果社員']['ops'].get('返品'), 1)
        self.assertEqual(json.loads(self.q(HIRATA, 'select public.usage_by_account_v1199c168(500)'))['days'], 90)

    def test_read_only(self):
        fn = SQL[SQL.index('create or replace function public.usage_by_account_v1199c168'):]
        fn = fn[:fn.index('$u$;')]
        for w in ('insert into', 'update public', 'delete from'):
            self.assertNotIn(w, fn.lower())
        self.assertIn('revoke all on public.usage_viewers_v1199c168 from public, anon, authenticated', SQL)


if __name__ == '__main__':
    unittest.main()
