"""c135：完全に置き換わって使われない古い関数の定義が、また増えていないかを確かめる（tools/function_map.js）。"""
import json
import shutil
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class FunctionMapTests(unittest.TestCase):
    def run_tool(self, *args):
        if not shutil.which("node"):
            self.skipTest("node がありません")
        r = subprocess.run(["node", str(ROOT / "tools" / "function_map.js"), *args], capture_output=True, text=True, cwd=ROOT, timeout=120)
        if r.returncode and "が見つかりません" in r.stderr:
            self.skipTest("acorn がありません")
        self.assertEqual(r.returncode, 0, r.stderr)
        return r.stdout

    def test_no_dead_definitions(self):
        dead = json.loads(self.run_tool("--dead"))
        self.assertEqual(dead, [], "使われていない古い定義があります。node tools/function_map.js --dead で確認し、削除してください。")


if __name__ == "__main__":
    unittest.main()
