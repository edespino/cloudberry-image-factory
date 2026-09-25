from __future__ import annotations

import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import tempfile
import unittest


REPOSITORY = Path(__file__).resolve().parents[1]
INSTALLER = REPOSITORY / "vm-images/common/scripts/system_add_dbadmin_ssh_keygen.sh"

# id answers for users listed in FAKE_USERS; getent maps each user to a home
# under FAKE_HOMES; runuser drops "-u <user> --" and runs the command as the
# caller, so the suite never switches users. ssh-keygen and coreutils are real.
FAKE_ID = """#!/bin/sh
[ "$1" = -u ] && case " ${FAKE_USERS:-} " in *" $2 "*) echo "${FAKE_UID}"; exit 0 ;; esac
exit 1
"""
FAKE_GETENT = """#!/bin/sh
echo "$2:x:1000:1000::${FAKE_HOMES}/$2:/bin/bash"
"""
FAKE_RUNUSER = """#!/bin/sh
[ "$1" = -u ] && [ "$3" = -- ] || exit 64
shift 3
exec "$@"
"""
FAKE_HOSTNAME = """#!/bin/sh
echo node-a
"""


def embedded_keygen_script() -> str:
    """The first-boot script the installer writes to /usr/local/sbin."""
    content = INSTALLER.read_text()
    match = re.search(r"<<'SCRIPT'\n(.*?)\nSCRIPT\n", content, re.S)
    assert match, "installer no longer embeds the keygen script"
    return match.group(1) + "\n"


class DbadminSshKeygenTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.homes = self.root / "home"
        self.homes.mkdir()
        self.marker = self.root / "state/dbadmin-ssh-keys.ready"
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for name, content in (
            ("id", FAKE_ID),
            ("getent", FAKE_GETENT),
            ("runuser", FAKE_RUNUSER),
            ("hostname", FAKE_HOSTNAME),
        ):
            path = self.bin / name
            path.write_text(content)
            path.chmod(0o700)
        for tool in ("ssh-keygen", "install", "touch", "chmod", "cut", "dirname", "sh", "find"):
            real = shutil.which(tool)
            self.assertIsNotNone(real, f"{tool} is required to run this suite")
            (self.bin / tool).symlink_to(real)
        self.script = self.root / "cloudberry-dbadmin-ssh-keygen"
        self.script.write_text(embedded_keygen_script())
        self.script.chmod(0o700)

    def _run(
        self, users: str = "gpadmin cbadmin", uid: int | None = None
    ) -> subprocess.CompletedProcess[str]:
        for user in users.split():
            (self.homes / user).mkdir(exist_ok=True)
        return subprocess.run(
            ["/bin/bash", str(self.script)],
            env={
                "PATH": str(self.bin),
                "FAKE_USERS": users,
                "FAKE_HOMES": str(self.homes),
                "FAKE_UID": str(os.getuid() if uid is None else uid),
                "CLOUDBERRY_DBADMIN_SSH_MARKER": str(self.marker),
            },
            capture_output=True,
            text=True,
            check=False,
        )

    def _ssh(self, user: str) -> Path:
        return self.homes / user / ".ssh"

    def test_generates_keys_empty_authorized_keys_and_marker(self) -> None:
        result = self._run()

        self.assertEqual(result.returncode, 0, result.stderr)
        for user in ("gpadmin", "cbadmin"):
            with self.subTest(user=user):
                ssh = self._ssh(user)
                self.assertEqual(stat.S_IMODE(ssh.stat().st_mode), 0o700)
                private = ssh / "id_ed25519"
                public = ssh / "id_ed25519.pub"
                self.assertEqual(stat.S_IMODE(private.stat().st_mode), 0o600)
                self.assertTrue(public.is_file() and not public.is_symlink())
                self.assertTrue(public.read_text().startswith("ssh-ed25519 "))
                self.assertIn(f"{user}@node-a", public.read_text())
                authorized = ssh / "authorized_keys"
                self.assertEqual(stat.S_IMODE(authorized.stat().st_mode), 0o600)
                self.assertEqual(authorized.read_text(), "")
        self.assertTrue(self.marker.is_file())

    def test_never_rotates_an_existing_key(self) -> None:
        self.assertEqual(self._run().returncode, 0)
        before = (self._ssh("gpadmin") / "id_ed25519").read_bytes()
        (self._ssh("gpadmin") / "authorized_keys").write_text("ssh-ed25519 AAAA peer\n")

        result = self._run()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self._ssh("gpadmin") / "id_ed25519").read_bytes(), before)
        self.assertEqual(
            (self._ssh("gpadmin") / "authorized_keys").read_text(),
            "ssh-ed25519 AAAA peer\n",
        )

    def test_restores_a_missing_public_key_from_the_private_key(self) -> None:
        self.assertEqual(self._run().returncode, 0)
        public = self._ssh("cbadmin") / "id_ed25519.pub"
        original = public.read_text().split()[:2]
        public.unlink()

        result = self._run()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(public.read_text().split()[:2], original)

    def test_refuses_symlinked_ssh_paths(self) -> None:
        target = self.root / "elsewhere"
        target.mkdir()
        for relative in (".ssh", ".ssh/authorized_keys", ".ssh/id_ed25519.pub"):
            with self.subTest(path=relative):
                shutil.rmtree(self.homes, ignore_errors=True)
                self.homes.mkdir()
                (self.homes / "gpadmin").mkdir()
                path = self.homes / "gpadmin" / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.symlink_to(target)
                result = self._run("gpadmin")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("refusing symlink", result.stderr)
                self.assertFalse(self.marker.exists())

    def test_refuses_non_regular_paths(self) -> None:
        for relative, make in (
            (".ssh/authorized_keys", lambda path: path.mkdir()),
            (".ssh/id_ed25519.pub", lambda path: os.mkfifo(path)),
            (".ssh", lambda path: path.write_text("")),
        ):
            with self.subTest(path=relative):
                shutil.rmtree(self.homes, ignore_errors=True)
                self.homes.mkdir()
                (self.homes / "gpadmin").mkdir()
                path = self.homes / "gpadmin" / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                make(path)
                result = self._run("gpadmin")
                self.assertNotEqual(result.returncode, 0)
                self.assertRegex(result.stderr, "not a (regular file|directory)")
                self.assertFalse(self.marker.exists())

    def test_refuses_paths_not_owned_by_the_user(self) -> None:
        (self.homes / "gpadmin" / ".ssh").mkdir(parents=True)

        result = self._run("gpadmin", uid=os.getuid() + 1)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not owned by gpadmin", result.stderr)
        self.assertFalse(self.marker.exists())

    def test_missing_users_are_skipped(self) -> None:
        result = self._run("gpadmin")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self._ssh("gpadmin") / "id_ed25519").is_file())
        self.assertFalse((self.homes / "cbadmin").exists())
        self.assertIn("cbadmin does not exist", result.stdout)
        self.assertTrue(self.marker.is_file())

    def test_unit_runs_once_before_sshd(self) -> None:
        unit = re.search(
            r"<<'UNIT'\n(.*?)\nUNIT\n", INSTALLER.read_text(), re.S
        ).group(1)
        self.assertIn("Type=oneshot", unit)
        self.assertIn("After=local-fs.target cloud-init.service", unit)
        self.assertIn("Before=ssh.service sshd.service", unit)
        self.assertIn(
            "ConditionPathExists=!/var/lib/cloudberry/dbadmin-ssh-keys.ready", unit
        )
        self.assertIn("WantedBy=multi-user.target", unit)
        self.assertIn(
            "systemctl enable cloudberry-dbadmin-ssh-keygen.service",
            INSTALLER.read_text(),
        )

    def test_chained_builders_never_generate_keys(self) -> None:
        # A template built from our own image (owners = ["self"]) boots the
        # unit on its builder; its user_data must create the marker first,
        # since deleted key bytes could survive in the snapshot.
        for template in sorted(REPOSITORY.glob("vm-images/aws/*/build/*/main.pkr.hcl")):
            content = template.read_text()
            if 'owners      = ["self"]' not in content:
                continue
            with self.subTest(template=template):
                self.assertIn("user_data = <<-EOT\n    #cloud-config\n    bootcmd:", content)
                self.assertIn("touch /var/lib/cloudberry/dbadmin-ssh-keys.ready", content)

    def test_installer_is_executable(self) -> None:
        self.assertTrue(os.access(INSTALLER, os.X_OK))


if __name__ == "__main__":
    unittest.main()
