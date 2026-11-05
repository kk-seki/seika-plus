import functools
import os
import signal
import subprocess
import sys
import threading
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
BASE_CHECKS = ("smoke.py", "permissions.py", "sync.py")
CHILD_KEY = "SEIKA_RUN_ALL_CHILD"
CHECK_TIMEOUT = 480
UNIT_CHECK = """import sys, unittest
suite = unittest.defaultTestLoader.discover(sys.argv[1], pattern=sys.argv[2])
if not suite.countTestCases():
    print('NG: 実行するテストがありません', flush=True)
    sys.exit(1)
result = unittest.TextTestRunner(verbosity=2).run(suite)
sys.exit(0 if result.wasSuccessful() else 1)
"""


class QuietRequestHandler(SimpleHTTPRequestHandler):
    def log_message(self, _format, *_args):
        pass


def discover_checks():
    checks = []
    for name in BASE_CHECKS:
        path = HERE / name
        if not path.is_file():
            raise FileNotFoundError(f"必須のテストがありません: tests/{name}")
        checks.append((name, [sys.executable, "-u", str(path)]))
    for path in sorted(HERE.glob("test_*.py")):
        if not path.is_file() or path.is_symlink():
            continue
        checks.append((path.name, [
            sys.executable, "-u", "-c", UNIT_CHECK, str(HERE), path.name,
        ]))
    return checks


def run_check(command, env, timeout=CHECK_TIMEOUT):
    process = subprocess.Popen(command, cwd=ROOT, env=env, start_new_session=True)
    try:
        try:
            return process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            print("NG: テストの実行上限を超えました", flush=True)
            return 124
    finally:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait()


def main():
    if os.environ.get(CHILD_KEY):
        print("NG: テストから共通入口を再び起動することはできません", flush=True)
        return 1
    checks = discover_checks()
    handler = functools.partial(QuietRequestHandler, directory=str(ROOT))
    server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    env = {
        **os.environ,
        "SEIKA_URL": f"http://127.0.0.1:{server.server_port}/index.html",
        CHILD_KEY: "1",
        "PYTHONUNBUFFERED": "1",
    }
    failures = []
    try:
        for name, command in checks:
            print(f"\n--- {name} ---", flush=True)
            try:
                code = run_check(command, env)
            except OSError as error:
                print(f"NG: テストを起動できません（{error}）", flush=True)
                code = 1
            print(f"{name}: {'OK' if code == 0 else f'NG（終了コード {code}）'}", flush=True)
            if code:
                failures.append(name)
    finally:
        server.shutdown()
        server.server_close()
        thread.join()
    if failures:
        print(f"\n自動チェック: NG（{', '.join(failures)}）", flush=True)
        return 1
    print(f"\n自動チェック: すべてOK（{len(checks)}本）", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
