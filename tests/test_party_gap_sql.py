"""c130：単協・仕入先マスタの表記統一とGAP一覧（db/052）を、使い捨てのPostgreSQLで確認する。"""
import json
import os
import pwd
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SQL_010 = next((ROOT / 'db').glob('010_*.sql')).read_text(encoding='utf-8')
SQL_052 = next((ROOT / 'db').glob('052_*.sql')).read_text(encoding='utf-8')
SCRATCH = Path('/tmp/jai-scratch/c130')
TIMEOUT = 30
ADMIN = '00000000-0000-0000-0000-000000000001'
WORKER = '00000000-0000-0000-0000-000000000002'
BUYER = '00000000-0000-0000-0000-000000000003'


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
create table public.app_state(id text primary key, data jsonb);
create table public.qr_lots(id uuid primary key default gen_random_uuid(), lot_no text, item_name text, supplier text, cooperative_name text,
  certification text, received_date date, current_qty numeric, active boolean default true, updated_at timestamptz default now());
create table public.qr_lot_movements(id uuid primary key default gen_random_uuid(), lot_id uuid, supplier text, cooperative_name text, user_name text);
create table public.hq_lots_v1400(id uuid primary key default gen_random_uuid(), supplier text, cooperative_name text);
insert into public.profiles values ('00000000-0000-0000-0000-000000000001','admin',true,'管理者'),
 ('00000000-0000-0000-0000-000000000002','worker',true,'社員'),('00000000-0000-0000-0000-000000000003','buyer',true,'仕入');
'''


class PartyGapSqlStaticTests(unittest.TestCase):
    def test_admin_only_for_writes_and_no_lot_quantities_are_touched(self):
        for fn in ('replace_qr_gap_certs_v1199c130', 'qr_gap_backfill_v1199c130', 'qr_party_merge_v1199c130'):
            body = SQL_052[SQL_052.index(f'function public.{fn}'):]
            body = body[:body.index('$f$;')]
            self.assertIn("seika_require_role_v1240(array['admin'])", body, fn)
        self.assertNotRegex(SQL_052, r'set\s+current_qty')
        self.assertNotIn('delete from public.qr_lots', SQL_052)

    def test_tables_are_read_only_for_the_app(self):
        self.assertIn('grant select on public.qr_gap_certs_v1199c130 to authenticated', SQL_052)
        self.assertIn('revoke all on public.qr_gap_certs_v1199c130 from public, anon, authenticated', SQL_052)


class PartyGapSqlRuntimeTests(unittest.TestCase):
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
        cls.port = '55447'
        cls.command(cls.runner + [str(BIN / 'pg_ctl'), '-D', str(cls.data), '-l', str(cls.log), '-o', f'-p {cls.port} -h 127.0.0.1 -k {cls.tmp.name}', '-w', 'start'])
        cls.base = [str(BIN / 'psql'), '-h', '127.0.0.1', '-p', cls.port, '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-X']
        cls.psql(SCHEMA)
        cls.psql(SQL_010)
        cls.psql(SQL_052)
        cls.psql(SQL_052)  # 2回実行しても同じ

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
        self.psql('truncate public.qr_lots, public.qr_lot_movements, public.hq_lots_v1400, public.qr_gap_certs_v1199c130, public.qr_party_merge_log_v1199c130, public.qr_party_names_v1280')

    def gap(self, rows, user=ADMIN):
        return self.rpc(f"public.replace_qr_gap_certs_v1199c130('{json.dumps(rows, ensure_ascii=False)}'::jsonb)", user)

    def test_replace_is_admin_only_and_replaces_everything(self):
        rows = [{'coop_name': 'JA水戸', 'item_name': 'キャベツ', 'certification': 'jgap', 'expires_on': '2027-03-31', 'note': 'a'},
                {'coop_name': 'JA つくば', 'item_name': '白菜', 'certification': 'GGAP', 'expires_on': '2026-12-01'}]
        self.assertEqual(self.gap(rows)['count'], 2)
        self.assertEqual(self.val("select string_agg(coop_norm||'/'||item_name||'/'||certification,',' order by coop_norm) from public.qr_gap_certs_v1199c130"),
                         'JAつくば/白菜/GGAP,JA水戸/キャベツ/JGAP')
        self.assertEqual(self.gap(rows[:1])['count'], 1)
        self.assertEqual(self.val('select count(*) from public.qr_gap_certs_v1199c130'), '1')
        for user in (WORKER, BUYER):
            with self.assertRaises(AssertionError):
                self.gap(rows, user)
        self.assertEqual(self.val('select count(*) from public.qr_gap_certs_v1199c130'), '1')

    def test_replace_rejects_bad_rows_without_changing_the_list(self):
        self.gap([{'coop_name': 'JA水戸', 'item_name': 'キャベツ', 'certification': 'JGAP', 'expires_on': '2027-03-31'}])
        bad = [
            [{'coop_name': 'JA水戸', 'item_name': 'キャベツ', 'certification': 'ABC', 'expires_on': '2027-03-31'}],
            [{'coop_name': 'JA水戸', 'item_name': 'キャベツ', 'certification': 'JGAP', 'expires_on': 'あした'}],
            [{'coop_name': '', 'item_name': 'キャベツ', 'certification': 'JGAP', 'expires_on': '2027-03-31'}],
            [{'coop_name': 'JA水戸', 'item_name': '白菜', 'certification': 'JGAP', 'expires_on': '2027-03-31'},
             {'coop_name': 'JA 水戸', 'item_name': '白菜', 'certification': 'GGAP', 'expires_on': '2027-03-31'}],
        ]
        for rows in bad:
            with self.subTest(rows=rows), self.assertRaises(AssertionError):
                self.gap(rows)
        self.assertEqual(self.val("select item_name from public.qr_gap_certs_v1199c130"), 'キャベツ')

    def test_backfill_only_fills_empty_in_stock_lots_within_the_expiry(self):
        self.gap([{'coop_name': 'JA水戸', 'item_name': 'キャベツ', 'certification': 'JGAP', 'expires_on': '2026-11-30'}])
        self.psql("""insert into public.qr_lots(lot_no,item_name,cooperative_name,certification,received_date,current_qty,active) values
          ('A','キャベツ','JA水戸',null,'2026-11-10',5,true),
          ('B','キャベツ','JA 水戸','','2026-11-30',1,true),
          ('C','キャベツ','JA水戸','GGAP','2026-11-10',5,true),
          ('D','キャベツ','JA水戸',null,'2026-12-01',5,true),
          ('E','キャベツ','JA水戸',null,'2026-11-10',0,true),
          ('F','白菜','JA水戸',null,'2026-11-10',5,true),
          ('G','キャベツ','',null,'2026-11-10',5,true),
          ('H','キャベツ','JA水戸',null,'2026-11-10',5,false)""")
        dry = self.rpc('public.qr_gap_backfill_v1199c130(false)')
        self.assertEqual(dry['count'], 2)
        self.assertEqual(sorted(r['lot_no'] for r in dry['rows']), ['A', 'B'])
        self.assertEqual(self.val("select count(*) from public.qr_lots where certification='JGAP'"), '0')
        with self.assertRaises(AssertionError):
            self.rpc('public.qr_gap_backfill_v1199c130(true)', WORKER)
        done = self.rpc('public.qr_gap_backfill_v1199c130(true)')
        self.assertEqual(done['count'], 2)
        self.assertEqual(self.val("select string_agg(lot_no||':'||coalesce(certification,'-'),',' order by lot_no) from public.qr_lots"),
                         'A:JGAP,B:JGAP,C:GGAP,D:-,E:-,F:-,G:-,H:-')
        self.assertEqual(self.rpc('public.qr_gap_backfill_v1199c130(true)')['count'], 0)

    def test_backfill_applies_daikon_to_cut_and_leaf_daikon_and_prefers_the_exact_item(self):
        self.gap([{'coop_name': 'カルゲン会さしま', 'item_name': '大根', 'certification': 'JGAP', 'expires_on': '2028-03-27'},
                  {'coop_name': 'カルゲン会さしま', 'item_name': '葉付大根', 'certification': 'GGAP', 'expires_on': '2028-03-27'}])
        self.psql("""insert into public.qr_lots(lot_no,item_name,cooperative_name,received_date,current_qty) values
          ('A','カット大根','カルゲン会さしま','2026-11-10',5),('B','葉付大根','カルゲン会さしま','2026-11-10',5),
          ('C','葉付き大根','カルゲン会さしま','2026-11-10',5),('D','人参','カルゲン会さしま','2026-11-10',5)""")
        self.assertEqual(self.rpc('public.qr_gap_backfill_v1199c130(true)')['count'], 3)
        self.assertEqual(self.val("select string_agg(lot_no||':'||coalesce(certification,'-'),',' order by lot_no) from public.qr_lots"), 'A:JGAP,B:GGAP,C:JGAP,D:-')

    def test_usage_counts_active_lots_by_normalized_name(self):
        self.psql("""insert into public.qr_lots(item_name,supplier,cooperative_name,received_date,active) values
          ('キャベツ','水戸大同','JA水戸','2026-11-01',true),('白菜','水戸大同 ','JA 水戸','2026-11-05',true),
          ('人参','丸果','JA水戸','2026-11-07',false),('人参',null,'',null,true)""")
        coop = self.rpc("public.qr_party_usage_v1199c130('cooperative')", WORKER)
        self.assertEqual([(r['norm'], r['lots'], r['last_date']) for r in coop], [('JA水戸', 2, '2026-11-05')])
        sup = self.rpc("public.qr_party_usage_v1199c130('supplier')")
        self.assertEqual([(r['norm'], r['lots']) for r in sup], [('水戸大同', 2)])
        with self.assertRaises(AssertionError):
            self.rpc("public.qr_party_usage_v1199c130('cooperative')", BUYER)

    def test_merge_fixes_lots_history_and_hq_and_leaves_an_alias(self):
        self.psql("""insert into public.qr_lots(id,item_name,cooperative_name,received_date) values
          ('10000000-0000-0000-0000-000000000001','キャベツ','JA水戸市','2026-11-01'),('10000000-0000-0000-0000-000000000002','白菜','JA 水戸市','2026-11-02'),
          ('10000000-0000-0000-0000-000000000003','人参','JA水戸','2026-11-03');
          insert into public.qr_lot_movements(lot_id,cooperative_name,user_name) values
          ('10000000-0000-0000-0000-000000000001','JA水戸市','荷受 太郎'),('10000000-0000-0000-0000-000000000002','JA水戸','荷受 太郎');
          insert into public.hq_lots_v1400(cooperative_name,supplier) values ('JA水戸市','JA水戸市')""")
        with self.assertRaises(AssertionError):
            self.rpc("public.qr_party_merge_v1199c130('cooperative','JA水戸市','JA水戸')", WORKER)
        out = self.rpc("public.qr_party_merge_v1199c130('cooperative','JA水戸市','JA水戸')")
        self.assertEqual((out['lots'], out['movements'], out['hq_lots']), (2, 1, 1))
        self.assertEqual(self.val("select string_agg(distinct cooperative_name,',') from public.qr_lots"), 'JA水戸')
        self.assertEqual(self.val("select string_agg(distinct user_name,',') from public.qr_lot_movements"), '荷受 太郎')
        self.assertEqual(self.val("select cooperative_name||'/'||supplier from public.hq_lots_v1400"), 'JA水戸/JA水戸市')
        self.assertEqual(self.val("select string_agg(norm||':'||status||':'||coalesce(renamed_to,''),',' order by norm) from public.qr_party_names_v1280 where kind='cooperative'"),
                         'JA水戸:active:,JA水戸市:deleted:JA水戸')
        self.assertEqual(self.val("select from_name||'>'||to_name||':'||lots||'/'||movements||'/'||hq_lots||':'||done_by_name from public.qr_party_merge_log_v1199c130"),
                         'JA水戸市>JA水戸:2/1/1:管理者')
        self.assertFalse(self.rpc("public.qr_party_merge_v1199c130('cooperative','JA水戸','JA水戸')")['ok'])


if __name__ == '__main__':
    unittest.main()
