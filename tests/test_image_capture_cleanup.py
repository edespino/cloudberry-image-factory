from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


REPOSITORY = Path(__file__).resolve().parents[1]
SCRIPT = REPOSITORY / "vm-images/common/scripts/system_prepare_image_capture.sh"

# Fakes record every sudo call and never execute it, so the suite cannot touch
# the host. Each other command answers from environment switches.
FAKE_SUDO = """#!/usr/bin/env python3
import json, os, sys
with open(os.environ["FAKE_SUDO_LOG"], "a") as stream:
    stream.write(json.dumps(sys.argv[1:]) + "\\n")
if sys.argv[1] == "test":
    raise SystemExit(0 if os.environ.get("FAKE_SSM_DIRS") == "1" else 1)
if os.environ.get("FAKE_SUDO_FAIL") and os.environ["FAKE_SUDO_FAIL"] in " ".join(sys.argv[1:]):
    raise SystemExit(7)
"""
FAKE_SNAP = """#!/bin/sh
[ "$1" = list ] && [ "${FAKE_SNAP_AGENT:-}" = 1 ] && exit 0
exit 1
"""
FAKE_SYSTEMCTL = """#!/bin/sh
[ "$1" = cat ] && [ "${FAKE_SYSTEMD_AGENT:-}" = 1 ] && exit 0
exit 1
"""
FAKE_ID = """#!/bin/sh
[ "$1" = -u ] && case " ${FAKE_USERS:-} " in *" $2 "*) echo 1000; exit 0 ;; esac
exit 1
"""
FAKE_GETENT = """#!/bin/sh
echo "$2:x:1000:1000::/home/$2:/bin/bash"
"""
FAKE_CLOUD_INIT = """#!/bin/sh
if [ "$1" = clean ] && [ "$2" = --help ]; then
  echo "usage: cloud-init clean [-h] [-l] [--machine-id] [-r]" | {
    if [ "${FAKE_CLOUD_INIT_MACHINE_ID:-}" = 1 ]; then cat; else sed 's/ \\[--machine-id\\]//'; fi
  }
  exit 0
fi
exit 1
"""


class ImageCaptureCleanupTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.sudo_log = self.root / "sudo.jsonl"
        self._executable("sudo", FAKE_SUDO)
        # python3 runs the fake sudo; sed and cat back the fake cloud-init
        # help. The script itself needs nothing else from PATH.
        for tool in ("python3", "sed", "cat", "cut"):
            real = shutil.which(tool)
            self.assertIsNotNone(real, f"{tool} is required to run this suite")
            (self.bin / tool).symlink_to(real)

    def _executable(self, name: str, content: str) -> None:
        path = self.bin / name
        path.write_text(content)
        path.chmod(0o700)

    def _run(self, *installed: str, **switches: str) -> tuple[int, list[list[str]]]:
        for name, content in (
            ("snap", FAKE_SNAP),
            ("systemctl", FAKE_SYSTEMCTL),
            ("cloud-init", FAKE_CLOUD_INIT),
            ("id", FAKE_ID),
            ("getent", FAKE_GETENT),
        ):
            if name in installed:
                self._executable(name, content)
        environment = {
            "PATH": str(self.bin),
            "FAKE_SUDO_LOG": str(self.sudo_log),
            **switches,
        }
        result = subprocess.run(
            ["/bin/bash", str(SCRIPT)],
            env=environment,
            capture_output=True,
            text=True,
            check=False,
        )
        calls = (
            [json.loads(line) for line in self.sudo_log.read_text().splitlines()]
            if self.sudo_log.exists()
            else []
        )
        return result.returncode, calls

    def test_ubuntu_snap_agent_with_machine_id_support(self) -> None:
        status, calls = self._run(
            "snap", "systemctl", "cloud-init", "id", "getent",
            FAKE_SNAP_AGENT="1", FAKE_SSM_DIRS="1", FAKE_CLOUD_INIT_MACHINE_ID="1",
            FAKE_USERS="gpadmin cbadmin",
        )
        self.assertEqual(status, 0)
        dbadmin = []
        for user in ("gpadmin", "cbadmin"):
            dbadmin += [
                ["rm", "-f", f"/home/{user}/.ssh/id_ed25519", f"/home/{user}/.ssh/id_ed25519.pub"],
                ["test", "-f", f"/home/{user}/.ssh/authorized_keys"],
                ["truncate", "-s", "0", f"/home/{user}/.ssh/authorized_keys"],
            ]
        self.assertEqual(
            calls,
            [
                ["snap", "stop", "amazon-ssm-agent"],
                ["test", "-d", "/var/log/amazon/ssm"],
                ["find", "/var/log/amazon/ssm", "-mindepth", "1", "-delete"],
                ["test", "-d", "/var/lib/amazon/ssm"],
                ["find", "/var/lib/amazon/ssm", "-mindepth", "1", "-delete"],
                *dbadmin,
                ["rm", "-f", "/var/lib/cloudberry/dbadmin-ssh-keys.ready"],
                ["cloud-init", "clean", "--logs", "--machine-id"],
            ],
        )

    def test_systemd_agent_with_older_cloud_init_resets_machine_id_directly(self) -> None:
        status, calls = self._run(
            "systemctl", "cloud-init", FAKE_SYSTEMD_AGENT="1", FAKE_SSM_DIRS="1",
        )
        self.assertEqual(status, 0)
        self.assertEqual(calls[0], ["systemctl", "stop", "amazon-ssm-agent"])
        self.assertEqual(
            calls[-2:],
            [
                ["cloud-init", "clean", "--logs"],
                ["truncate", "-s", "0", "/etc/machine-id"],
            ],
        )

    def test_no_agent_and_no_cloud_init_still_resets_machine_id(self) -> None:
        status, calls = self._run()
        self.assertEqual(status, 0)
        self.assertEqual(
            calls,
            [
                ["test", "-d", "/var/log/amazon/ssm"],
                ["test", "-d", "/var/lib/amazon/ssm"],
                ["rm", "-f", "/var/lib/cloudberry/dbadmin-ssh-keys.ready"],
                ["truncate", "-s", "0", "/etc/machine-id"],
            ],
        )

    def test_state_is_deleted_under_sudo_not_by_an_unprivileged_glob(self) -> None:
        _, calls = self._run(FAKE_SSM_DIRS="1")
        for call in calls:
            with self.subTest(call=call):
                self.assertFalse(any("*" in argument for argument in call))

    def test_a_failing_cleanup_step_fails_the_build(self) -> None:
        for failing in ("snap stop", "find /var/lib/amazon/ssm", "cloud-init clean"):
            if self.sudo_log.exists():
                self.sudo_log.unlink()
            with self.subTest(failing=failing):
                status, _ = self._run(
                    "snap", "cloud-init",
                    FAKE_SNAP_AGENT="1", FAKE_SSM_DIRS="1",
                    FAKE_CLOUD_INIT_MACHINE_ID="1", FAKE_SUDO_FAIL=failing,
                )
                self.assertNotEqual(status, 0)

    def test_script_is_executable(self) -> None:
        self.assertTrue(os.access(SCRIPT, os.X_OK))


if __name__ == "__main__":
    unittest.main()
