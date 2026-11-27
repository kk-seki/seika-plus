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
SQL = (ROOT / 'db/075_GAP一覧をJGAPサイトで自動更新.sql').read_text(encoding='utf-8')
SCRATCH = Path('/tmp/jai-scratch/c174')
TIMEOUT = 30


def find_pg_bin():
    for executable in ('initdb',):
        path = shutil.which(executable)
        if path:
            return Path(path).parent
    candidates = sorted(Path('/usr/lib/postgresql').glob('*/bin/initdb'))
    return candidates[-1].parent if candidates else None


BIN = find_pg_bin()
ADMIN = '00000000-0000-0000-0000-000000000001'

SCHEMA = r'''
create schema auth;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('app.user',true),'')::uuid$$;
create role anon; create role authenticated; create role service_role;
create table public.profiles(id uuid primary key, role text, active boolean default true, display_name text);
insert into public.profiles values ('00000000-0000-0000-0000-000000000001','admin',true,'平田 祐希');
create function public.seika_require_role_v1240(p text[]) returns void language plpgsql as $$begin if not exists(select 1 from public.profiles where id=auth.uid() and role=any(p)) then raise exception 'denied'; end if; end$$;
create function public.seika_party_norm_v1280(p text) returns text language sql immutable as $$select regexp_replace(normalize(coalesce(p,''),NFKC),'\s','','g')$$;
create table public.qr_gap_certs_v1199c130(coop_norm text not null, coop_name text not null, item_norm text not null, item_name text not null,
  certification text not null, expires_on date not null, note text not null default '', imported_by_name text not null default '', imported_at timestamptz not null default now(),
  primary key (coop_norm, item_norm));
'''


class GapJgapSqlTests(unittest.TestCase):
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
        cls.port = '55473'
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

    def seed(self):
        rows = [("エプロン","玉葱","JGAP","2026-07-05"),("JA香川県","ロメイン","JGAP","2023-10-18"),("中村農園","青梗菜","JGAP","2026-10-11"),
                ("佐賀東部青果","玉葱","JGAP","2026-11-21"),("オヌマファーム","水菜","JGAP","2026-12-22"),("オヌマファーム","人参","JGAP","2026-12-22"),
                ("タスパス","キャベツ","JGAP","2026-12-01"),("SYC協同組合","レタス","JGAP","2026-10-21"),("JA茨城","白菜","GGAP","2026-12-01"),
                ("遠い農園","人参","JGAP","2030-01-01"),("サニー農場","サニー","ASIAGAP","2026-12-01")]
        vals = ",".join(f"('{a}','{a}','{b}','{b}','{c}','{d}')" for a, b, c, d in rows)
        self.psql(f"truncate public.qr_gap_certs_v1199c130; truncate public.qr_gap_auto_updates_v1199c174 cascade; insert into public.qr_gap_certs_v1199c130(coop_norm,coop_name,item_norm,item_name,certification,expires_on) values {vals}")

    def results(self):
        r = lambda name, items, exp, ver="JGAP青果物2022", no="1": {"name": name, "no": no, "pref": "", "ver": ver, "items": items, "expires": exp}
        return [
            {"coop_name": "エプロン", "query": "エプロン", "rows": [r("株式会社エプロン", "（栽培・収穫・取扱い） たまねぎ", "2028/07/05", no="010000155")]},
            {"coop_name": "JA香川県", "query": "JA香川県", "rows": [r("JA香川県豊南地区GAP研究会", "（栽培・収穫・取扱い） レタス、ロメインレタス、たまねぎ", "2027/10/18")]},
            {"coop_name": "中村農園", "query": "中村農園", "rows": [r("中村 広樹(中村農園)", "（栽培・収穫・取扱い） ちんげんさい、ミニトマト", "2028/10/11"),
                                                             r("株式会社中村農園", "（栽培・収穫・取扱い） キャベツ、たまねぎ", "2027/12/05")]},
            {"coop_name": "佐賀東部青果", "query": "佐賀東部青果", "rows": [r("有限会社佐賀東部青果", "（栽培・収穫・取扱い） れんこん、たまねぎ、リーフレタス（グリーンリーフ）", "2026/11/21")]},
            {"coop_name": "オヌマファーム", "query": "オヌマファーム", "rows": [r("株式会社オヌマファーム", "（栽培・収穫・取扱い） みずな、ほうれんそう", "2027/12/22")]},
            {"coop_name": "タスパス", "query": "タスパス", "rows": [r("田原タスパス部会", "（栽培・収穫・取扱い） キャベツ", "2027/01/30"), r("タスパスくまもと JGAP部会", "（栽培・収穫・取扱い） レタス、キャベツ", "2027/01/12")]},
            {"coop_name": "SYC協同組合", "query": "SYC協同組合", "rows": []},
            {"coop_name": "サニー農場", "query": "サニー農場", "rows": [r("サニー農場", "（栽培・収穫） サニーレタス", "2028/01/01", ver="JGAP青果物2022")]},
        ]

    def apply(self, res, user=None):
        sql = "select public.gap_jgap_apply_v1199c174($j$" + json.dumps(res, ensure_ascii=False) + "$j$::jsonb, 60)"
        if user:
            sql = f"set role authenticated; set app.\"user\"='{user}'; " + sql
        return json.loads(self.psql(sql, True).splitlines()[-1])

    def exp(self, coop, item):
        return self.psql(f"select expires_on from public.qr_gap_certs_v1199c130 where coop_name='{coop}' and item_name='{item}'", True)

    def test_targets(self):
        self.seed()
        t = json.loads(self.psql("select public.gap_jgap_targets_v1199c174(60)", True))
        names = [x["coop_name"] for x in t]
        self.assertIn("エプロン", names); self.assertNotIn("JA茨城", names); self.assertNotIn("遠い農園", names)  # GGAP・期限が先のものは調べない

    def test_apply_rules(self):
        self.seed()
        out = self.apply(self.results())
        st = {(x["coop_name"], x["item_name"]): x["status"] for x in out["report"]}
        self.assertEqual(st[("エプロン", "玉葱")], "updated")
        self.assertEqual(st[("JA香川県", "ロメイン")], "updated")
        self.assertEqual(st[("中村農園", "青梗菜")], "updated")       # 名前の候補は2つでも、品目で1つに絞れる
        self.assertEqual(st[("佐賀東部青果", "玉葱")], "same")
        self.assertEqual(st[("オヌマファーム", "水菜")], "updated")
        self.assertEqual(st[("オヌマファーム", "人参")], "item_missing")  # 認証の品目にない
        self.assertEqual(st[("タスパス", "キャベツ")], "ambiguous")      # 2つの部会にキャベツ
        self.assertEqual(st[("SYC協同組合", "レタス")], "not_found")
        self.assertEqual(st[("サニー農場", "サニー")], "cert_missing")    # ASIAGAPなのにサイトはJGAP
        self.assertEqual(self.exp("エプロン", "玉葱"), "2028-07-05")
        self.assertEqual(self.exp("中村農園", "青梗菜"), "2028-10-11")
        self.assertEqual(self.exp("タスパス", "キャベツ"), "2026-12-01")
        self.assertEqual(self.psql("select count(*) from public.qr_gap_auto_updates_v1199c174", True), "4")
        self.assertEqual(self.psql("select jgap_no from public.qr_gap_auto_updates_v1199c174 where coop_name='エプロン'", True), "010000155")
        self.assertEqual(json.loads(self.psql("select summary from public.qr_gap_jgap_runs_v1199c174 order by id desc limit 1", True))["updated"], 4)
        # 調べられなかった単協（結果に入っていない）は not_searched
        self.seed()
        out2 = self.apply(self.results()[:1])
        self.assertEqual({x["status"] for x in out2["report"] if x["coop_name"] != "エプロン"}, {"not_searched"})

    def test_app_cannot_call_apply_and_import_keeps_newer(self):
        self.seed()
        with self.assertRaises(AssertionError):
            self.apply(self.results(), ADMIN)
        self.apply(self.results())
        # Excelを取り込み直しても（古い期限のまま）、自動反映した新しい期限は残る。Excelのほうが新しければExcel
        rows = [{"coop_name": "エプロン", "item_name": "玉葱", "certification": "JGAP", "expires_on": "2026-07-05"},
                {"coop_name": "JA香川県", "item_name": "ロメイン", "certification": "JGAP", "expires_on": "2029-01-01"}]
        r = json.loads(self.psql(f"set app.\"user\"='{ADMIN}'; select public.replace_qr_gap_certs_v1199c130($j${json.dumps(rows, ensure_ascii=False)}$j$::jsonb)", True).splitlines()[-1])
        self.assertEqual(r["kept_auto"], 1)
        self.assertEqual(self.exp("エプロン", "玉葱"), "2028-07-05")
        self.assertEqual(self.exp("JA香川県", "ロメイン"), "2029-01-01")


if __name__ == '__main__':
    unittest.main()
