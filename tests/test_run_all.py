import contextlib
import io
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch
from urllib.request import urlopen

import run_all


class RunAllTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.here = self.root / "tests"
        self.here.mkdir()
        (self.root / "index.html").write_text("架空のアプリ", encoding="utf-8")
        for name in run_all.BASE_CHECKS:
            (self.here / name).write_text("", encoding="utf-8")
        self.patchers = [
            patch.object(run_all, "ROOT", self.root),
            patch.object(run_all, "HERE", self.here),
            patch.dict(os.environ),
        ]
        for patcher in self.patchers:
            patcher.start()
            self.addCleanup(patcher.stop)
        os.environ.pop(run_all.CHILD_KEY, None)

    def unit_file(self, name, assertion="True"):
        path = self.here / name
        path.write_text(
            "import unittest\nclass Example(unittest.TestCase):\n"
            f"    def test_example(self):\n        self.assertTrue({assertion})\n",
            encoding="utf-8",
        )
        return path

    def quiet_main(self):
        with contextlib.redirect_stdout(io.StringIO()):
            return run_all.main()

    def test_existing_checks_and_new_tests_are_discovered(self):
        self.unit_file("test_z.py")
        self.unit_file("test_a.py")
        (self.here / "helper.py").write_text("", encoding="utf-8")
        (self.here / "run_all.py").write_text("", encoding="utf-8")
        (self.here / "test_directory.py").mkdir()
        names = [name for name, _ in run_all.discover_checks()]
        self.assertEqual(names, [*run_all.BASE_CHECKS, "test_a.py", "test_z.py"])

    def test_required_check_cannot_be_silently_skipped(self):
        with patch.object(run_all, "BASE_CHECKS", ("missing.py",)):
            with self.assertRaisesRegex(FileNotFoundError, "必須のテスト"):
                run_all.discover_checks()

    def test_symlink_is_not_a_new_test(self):
        path = self.unit_file("test_real.py")
        (self.here / "test_link.py").symlink_to(path)
        names = [name for name, _ in run_all.discover_checks()]
        self.assertNotIn("test_link.py", names)

    def test_new_unit_tests_actually_run_and_failures_are_reported(self):
        self.unit_file("test_pass.py")
        self.unit_file("test_fail.py", "False")
        commands = dict(run_all.discover_checks())
        for name, expected in [("test_pass.py", 0), ("test_fail.py", 1)]:
            result = subprocess.run(commands[name], cwd=self.root, capture_output=True, text=True)
            self.assertEqual(result.returncode, expected, result.stderr)
            self.assertIn("Ran 1 test", result.stderr)

    def test_empty_unit_file_is_not_reported_as_success(self):
        (self.here / "test_empty.py").write_text("def test_unused():\n    assert False\n", encoding="utf-8")
        command = dict(run_all.discover_checks())["test_empty.py"]
        result = subprocess.run(command, cwd=self.root, capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn("実行するテストがありません", result.stdout)

    def test_failure_does_not_skip_later_checks(self):
        with patch.object(run_all, "run_check", side_effect=[0, 1, 0]) as run:
            self.assertEqual(self.quiet_main(), 1)
            self.assertEqual(run.call_count, 3)

    def test_all_success_returns_zero(self):
        with patch.object(run_all, "run_check", return_value=0):
            self.assertEqual(self.quiet_main(), 0)

    def test_start_failure_is_reported_and_later_checks_run(self):
        with patch.object(run_all, "run_check", side_effect=[OSError("架空の起動失敗"), 0, 0]) as run:
            self.assertEqual(self.quiet_main(), 1)
            self.assertEqual(run.call_count, 3)

    def test_external_url_is_replaced_with_own_local_server(self):
        os.environ["SEIKA_URL"] = "https://invalid.example/index.html"
        urls = []

        def verify(_command, env):
            url = env["SEIKA_URL"]
            self.assertTrue(url.startswith("http://127.0.0.1:"))
            self.assertEqual(env[run_all.CHILD_KEY], "1")
            with urlopen(url, timeout=3) as response:
                self.assertEqual(response.read().decode("utf-8"), "架空のアプリ")
            urls.append(url)
            return 0

        with patch.object(run_all, "run_check", side_effect=verify):
            self.assertEqual(self.quiet_main(), 0)
        self.assertEqual(len(set(urls)), 1)

    def test_recursion_is_rejected_before_discovery(self):
        os.environ[run_all.CHILD_KEY] = "1"
        with patch.object(run_all, "discover_checks") as discover:
            self.assertEqual(self.quiet_main(), 1)
            discover.assert_not_called()

    def test_child_process_runs_in_repository_and_keeps_exit_code(self):
        script = "import os,sys;from pathlib import Path;assert Path.cwd()==Path(sys.argv[1]);assert os.environ['SEIKA_URL']=='local';sys.exit(7)"
        code = run_all.run_check(
            [sys.executable, "-c", script, str(self.root)],
            {**os.environ, "SEIKA_URL": "local"},
        )
        self.assertEqual(code, 7)

    def test_timeout_is_not_success(self):
        with contextlib.redirect_stdout(io.StringIO()):
            code = run_all.run_check(
                [sys.executable, "-c", "import time;time.sleep(30)"],
                dict(os.environ),
                timeout=0.2,
            )
        self.assertEqual(code, 124)

    def test_timeout_stops_child_processes(self):
        script = "import subprocess,sys,time;from pathlib import Path;p=subprocess.Popen([sys.executable,'-c','import time;time.sleep(30)']);Path(sys.argv[1]).write_text(str(p.pid));time.sleep(30)"
        pid_file = self.root / "child.pid"
        with contextlib.redirect_stdout(io.StringIO()):
            code = run_all.run_check(
                [sys.executable, "-c", script, str(pid_file)],
                dict(os.environ),
                timeout=1,
            )
        self.assertEqual(code, 124)
        self.assertTrue(pid_file.is_file())
        status = Path(f"/proc/{pid_file.read_text()}/stat")
        for _ in range(100):
            if not status.exists() or status.read_text().split(") ", 1)[1].startswith("Z "):
                return
            time.sleep(0.01)
        self.fail("テストが起動した子プロセスが停止していません")


if __name__ == "__main__":
    unittest.main()
