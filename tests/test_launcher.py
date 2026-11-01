"""Offline lifecycle tests: no OAuth, GUI, downloads, or real network requests."""

import os
from pathlib import Path
import subprocess
import shutil
import tempfile
import unittest


LAUNCHER = Path(__file__).resolve().parents[1] / "scripts/start-airi.sh"


class LauncherTests(unittest.TestCase):
    def run_launcher(self, *, config=True, proxy_fails=False, tts_fails=False, custom_ports=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            env = os.environ.copy()
            env.update(
                HOME=directory,
                XDG_STATE_HOME=str(root / "state"),
                XDG_CONFIG_HOME=str(root / "config"),
                MY_AIRI_PROXY_CONFIG=str(root / "proxy.yaml"),
                PATH=f"{directory}:{env['PATH']}",
            )
            if custom_ports:
                env.update(MY_AIRI_PROXY_PORT="18317", MY_AIRI_TTS_PORT="20101")
            else:
                env.pop("MY_AIRI_PROXY_PORT", None)
                env.pop("MY_AIRI_TTS_PORT", None)
            if config:
                (root / "proxy.yaml").write_text("{}")
            scripts = {
                "proxy": "exit 1" if proxy_fails else "exec sleep 60",
                "tts": "exit 1" if tts_fails else "exec sleep 60",
                "airi": 'echo "AIRI started"; exit 0',
                # Model listing is protected, whereas TTS version is public.
                "curl": 'case "${*: -1}" in */models) printf 401;; *) printf 200;; esac',
            }
            for name, script in scripts.items():
                path = root / name
                path.write_text(f"#!{shutil.which('bash')}\n{script}\n")
                path.chmod(0o700)
            env.update(
                CODEX_PROXY_BIN=str(root / "proxy"),
                AIVIS_BIN=str(root / "tts"),
                AIRI_BIN=str(root / "airi"),
            )
            result = subprocess.run(
                ["bash", str(LAUNCHER)], env=env, capture_output=True,
                text=True, timeout=10,
            )
            return result

    def test_protected_proxy_and_normal_shutdown(self):
        result = self.run_launcher()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("AIRI started", result.stdout)

    def test_missing_configuration(self):
        result = self.run_launcher(config=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("config not found", result.stderr)

    def test_custom_ports(self):
        result = self.run_launcher(custom_ports=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("http://127.0.0.1:18317/v1", result.stderr)
        self.assertIn("http://127.0.0.1:20101", result.stderr)

    def test_proxy_failure(self):
        result = self.run_launcher(proxy_fails=True)
        self.assertNotEqual(result.returncode, 0)

    def test_tts_failure(self):
        result = self.run_launcher(tts_fails=True)
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
