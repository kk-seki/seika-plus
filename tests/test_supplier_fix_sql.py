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
SQL = (ROOT / 'db/073_キャベツの仕入先_冨田農園.sql').read_text(encoding='utf-8')
SCRATCH = Path('/tmp/jai-scratch/c170')
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
create table public.qr_lots(id serial primary key, item_name text, supplier text, cooperative_name text, current_qty numeric);
create table public.qr_lot_movements(id serial primary key, item_name text, supplier text, cooperative_name text);
create table public.hq_lots_v1400(id serial primary key, item_name text, supplier text, cooperative_name text);
create table public.trimming_job_lots(id serial primary key, item_name text, supplier text);
insert into public.qr_lots(item_name,supplier,cooperative_name) values ('キャベツ','ヴィポート',null),('キャベツ','富田農園','ヴィポート'),('白菜','ヴィポート',null),('キャベツ','山田農園','JA');
insert into public.qr_lot_movements(item_name,supplier) values ('キャベツ','ヴィポート'),('白菜','ヴィポート');
insert into public.hq_lots_v1400(item_name,supplier) values ('キャベツ','ヴイポート');
insert into public.trimming_job_lots(item_name,supplier) values ('キャベツ','ｳﾞｨﾎﾟｰﾄ');
'''


class SupplierFixSqlTests(unittest.TestCase):
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
        cls.port = '55472'
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

    def rows(self, table, cols='item_name,supplier,coalesce(cooperative_name,\'\')'):
        return self.psql(f"select {cols} from public.{table} order by id", True).splitlines()

    def test_existing_rows_fixed(self):
        self.assertEqual(self.rows('qr_lots')[:4], ['キャベツ|冨田農園|ヴィポート', 'キャベツ|冨田農園|ヴィポート', '白菜|ヴィポート|', 'キャベツ|山田農園|JA'])
        self.assertEqual(self.rows('qr_lot_movements'), ['キャベツ|冨田農園|ヴィポート', '白菜|ヴィポート|'])
        self.assertEqual(self.rows('hq_lots_v1400'), ['キャベツ|冨田農園|ヴィポート'])
        self.assertEqual(self.rows('trimming_job_lots', 'item_name,supplier'), ['キャベツ|冨田農園'])

    def test_new_and_updated_lots_are_fixed(self):
        self.psql("insert into public.qr_lots(item_name,supplier,cooperative_name) values ('キャベツ','ヴイ ポート',null),('キャベツ','冨田農園',''),('白菜','ヴィポート',null)")
        self.assertEqual(self.rows('qr_lots')[-3:], ['キャベツ|冨田農園|ヴィポート', 'キャベツ|冨田農園|ヴィポート', '白菜|ヴィポート|'])
        self.psql("update public.qr_lots set supplier='ヴィポート', cooperative_name=null where supplier='山田農園'")
        self.assertIn('キャベツ|冨田農園|ヴィポート', self.rows('qr_lots')[3])
        # 数だけ変える更新では動かない（仕入先はそのまま）
        self.psql("update public.qr_lots set current_qty=1 where item_name='白菜'")
        self.assertEqual(self.psql("select count(*) from public.qr_lots where item_name='白菜' and supplier='ヴィポート'", True), '2')


if __name__ == '__main__':
    unittest.main()
