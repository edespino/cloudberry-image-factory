from __future__ import annotations

import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import time
import unittest
import shutil


REPOSITORY = Path(__file__).resolve().parents[1]
SCRIPT = REPOSITORY / "vm-images/scripts/packer-build-and-test.sh"


class PackerBuildSecurityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.target = self.root / "vm-images/aws/synxdb-cloud/build/rocky9"
        self.target.mkdir(parents=True)
        (self.target / "main.pkr.hcl").write_text("# fake\n")
        (self.target / "tests").mkdir()
        (self.target / "tests/goss.yaml").write_text("file: {}\n")
        (self.root / "vm-images/common/tests").mkdir(parents=True)
        (self.root / "vm-images/common/tests/common.yaml").write_text("file: {}\n")
        self.scripts_dir = self.root / "vm-images/scripts"
        shutil.copytree(SCRIPT.parent, self.scripts_dir)
        self.script = self.scripts_dir / SCRIPT.name
        self.runtime = self.root / "runtime"
        self.runtime.mkdir(mode=0o700)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.aws_log = self.root / "aws.log"
        self.event_log = self.root / "events.log"
        self.packer_log = self.root / "packer.jsonl"
        self.ssh_log = self.root / "ssh.jsonl"
        self.scp_log = self.root / "scp.jsonl"
        self.timeout_log = self.root / "timeout.jsonl"
        self._write_fakes()

    def _executable(self, name: str, content: str) -> None:
        path = self.bin / name
        path.write_text(content)
        path.chmod(0o700)

    def _write_fakes(self) -> None:
        self._executable(
            "aws",
            """#!/usr/bin/env python3
import glob, json, os, shutil, sys, time
args = sys.argv[1:]
with open(os.environ["FAKE_AWS_LOG"], "a") as stream:
    stream.write(json.dumps(args) + "\\n")
operation = args[1] if len(args) > 1 else ""
with open(os.environ["FAKE_EVENT_LOG"], "a") as stream:
    stream.write("aws:" + operation + "\\n")
if operation == "create-key-pair":
    print("FAKE-PRIVATE-KEY-CANARY", flush=True)
    if os.environ.get("FAKE_REMOVE_KEY_DIRECTORY") == "1":
        for path in glob.glob(os.environ["XDG_RUNTIME_DIR"] + "/cloudberry-packer-*"):
            shutil.rmtree(path)
    if os.environ.get("FAKE_CREATE_KEY_FAILURE") == "1":
        raise SystemExit(42)
elif operation == "describe-images":
    if "Images[0].Architecture" in args:
        print(os.environ.get("FAKE_AMI_ARCHITECTURE", "x86_64"))
    elif any("BlockDeviceMappings" in value for value in args):
        if os.environ.get("FAKE_AMI_SNAPSHOT_LOOKUP_FAILURE") == "1":
            raise SystemExit(55)
        # real CLI --output text joins list values with tabs
        print(os.environ.get("FAKE_AMI_SNAPSHOTS", "snap-0123456789abcdef0\\tsnap-0fedcba9876543210"))
    else:
        print(os.environ.get("FAKE_AMI_METADATA", "synxdb-cloud-packer-rocky9-20260904-000000"))
elif operation == "deregister-image":
    if os.environ.get("FAKE_DEREGISTER_STALL") == "1":
        time.sleep(30)
    if os.environ.get("FAKE_DEREGISTER_FAILURE") == "1":
        raise SystemExit(53)
elif operation == "delete-snapshot" and os.environ.get("FAKE_SNAPSHOT_DELETE_FAILURE") == "1":
    raise SystemExit(54)
elif operation == "create-security-group":
    if os.environ.get("FAKE_SG_LOST_RESPONSE") == "1":
        raise SystemExit(48)
    if os.environ.get("FAKE_SECURITY_GROUP_FAILURE") == "1":
        raise SystemExit(46)
    print("sg-fake")
elif operation == "run-instances":
    if os.environ.get("FAKE_INSTANCE_LOST_RESPONSE") == "1":
        raise SystemExit(49)
    print("i-fake")
elif operation == "describe-instances":
    if "--filters" in args:
        discovery_count = sum(
            json.loads(line)[1] == "describe-instances"
            and "--filters" in json.loads(line)
            for line in open(os.environ["FAKE_AWS_LOG"])
            if len(json.loads(line)) > 1
        )
        if os.environ.get("FAKE_DISCOVERY_STALL") == "1":
            time.sleep(30)
        none_count = int(os.environ.get("FAKE_DISCOVERY_NONE_COUNT", "0"))
        print("None" if discovery_count <= none_count else "i-ambiguous")
    else:
        print("fake.example")
elif operation == "describe-security-groups":
    if (
        any("Name=group-name" in value for value in args)
        and os.environ.get("FAKE_SG_LOST_RESPONSE") == "1"
    ):
        discovery_count = sum(
            json.loads(line)[1] == "describe-security-groups"
            and any("Name=group-name" in value for value in json.loads(line))
            for line in open(os.environ["FAKE_AWS_LOG"])
            if len(json.loads(line)) > 1
        )
        if os.environ.get("FAKE_DISCOVERY_STALL") == "1":
            time.sleep(30)
        none_count = int(os.environ.get("FAKE_DISCOVERY_NONE_COUNT", "0"))
        print("None" if discovery_count <= none_count else "sg-ambiguous")
    elif any("Name=group-id" in value for value in args):
        print("0")
    else:
        raise SystemExit(255)
elif operation == "describe-key-pairs":
    raise SystemExit(45)
elif operation == "delete-key-pair" and os.environ.get("FAKE_DELETE_FAILURE") == "1":
    raise SystemExit(44)
elif operation == "delete-key-pair" and os.environ.get("FAKE_DELETE_STALL") == "1":
    time.sleep(30)
elif operation == "create-tags" and os.environ.get("FAKE_TAG_STALL") == "1":
    time.sleep(30)
elif operation == "terminate-instances":
    if os.environ.get("FAKE_TERMINATE_DELAY"):
        time.sleep(float(os.environ["FAKE_TERMINATE_DELAY"]))
    if os.environ.get("FAKE_TERMINATE_FAILURE") == "1":
        raise SystemExit(50)
elif (
    operation == "wait"
    and "instance-terminated" in args
    and os.environ.get("FAKE_WAIT_FAILURE") == "1"
):
    raise SystemExit(51)
elif operation == "delete-security-group":
    count = sum(
        json.loads(line)[1] == "delete-security-group"
        for line in open(os.environ["FAKE_AWS_LOG"])
        if len(json.loads(line)) > 1
    )
    if os.environ.get("FAKE_SG_DEPENDENCY_ONCE") == "1" and count == 1:
        raise SystemExit(52)
""",
        )
        self._executable(
            "packer",
            """#!/usr/bin/env python3
import json, os, pathlib, stat, sys
key = pathlib.Path(os.environ["PKR_VAR_PRIVATE_KEY_FILE"])
record = {
    "argv": sys.argv[1:],
    "key_path": str(key),
    "key_exists": key.exists(),
    "key_mode": stat.S_IMODE(key.stat().st_mode) if key.exists() else None,
    "key_parent_mode": stat.S_IMODE(key.parent.stat().st_mode),
    "key_value": key.read_text() if key.exists() else None,
    "cwd_pems": [str(path) for path in pathlib.Path.cwd().glob("*.pem")],
}
with open(os.environ["FAKE_PACKER_LOG"], "a") as stream:
    stream.write(json.dumps(record) + "\\n")
if os.environ.get("FAKE_PACKER_INIT_FAILURE") == "1" and sys.argv[1] == "init":
    raise SystemExit(43)
""",
        )
        self._executable("jq", "#!/bin/sh\nprintf '%s\\n' 'amazon-ebs:ami-fake'\n")
        self._executable(
            "curl", "#!/bin/sh\nprintf '%s\\n' \"${FAKE_PUBLIC_IP:-192.0.2.1}\"\n"
        )
        self._executable(
            "nc",
            "#!/bin/sh\n"
            "if [ \"${FAKE_SSH_UNREACHABLE:-}\" = 1 ]; then exit 1; fi\n"
            "printf '%s\\n' 'succeeded'\n",
        )
        for command in ("ssh", "scp"):
            self._executable(
                command,
                f"""#!/usr/bin/env python3
import json, os, sys
with open(os.environ["FAKE_{command.upper()}_LOG"], "a") as stream:
    stream.write(json.dumps(sys.argv[1:]) + "\\n")
if (
    "{command}" == "ssh"
    and os.environ.get("FAKE_GOSS_FAILURE") == "1"
    and any("goss" in value for value in sys.argv[1:])
):
    raise SystemExit(1)
""",
            )
        self._executable(
            "sleep",
            "#!/bin/sh\nexit 0\n",
        )
        self._executable(
            "timeout",
            """#!/usr/bin/env python3
import json, os, subprocess, sys
with open(os.environ["FAKE_TIMEOUT_LOG"], "a") as stream:
    stream.write(json.dumps(sys.argv[1:]) + "\\n")
raise SystemExit(subprocess.run([REAL_TIMEOUT, *sys.argv[1:]]).returncode)
""".replace("REAL_TIMEOUT", repr(self._real("timeout"))),
        )
        for command in ("rm", "rmdir"):
            self._executable(
                command,
                f"""#!/bin/sh
printf '%s\n' '{command}' >> "$FAKE_EVENT_LOG"
if [ "${{FAKE_LOCAL_REMOVE_FAILURE:-}}" = "1" ]; then
  exit 47
fi
exec {self._real(command)} "$@"
""",
            )

    def _real(self, command: str) -> str:
        # The fakes wrap the real GNU tools; their paths differ by platform
        # (/usr/bin on Linux, /bin or Homebrew's gnubin on macOS).
        executable = shutil.which(command)
        self.assertIsNotNone(executable, f"{command} is required to run this suite")
        return executable

    def _run(
        self,
        *arguments: str,
        runtime: Path | None = None,
        include_runtime: bool = True,
        extra_env: dict[str, str] | None = None,
        path: Path | None = None,
        script: Path | None = None,
        timeout: float = 20,
    ) -> subprocess.CompletedProcess[str]:
        script = script if script is not None else self.script
        environment = {
            "PATH": str(path) if path is not None else f"{self.bin}:/usr/bin:/bin",
            "FAKE_AWS_LOG": str(self.aws_log),
            "FAKE_EVENT_LOG": str(self.event_log),
            "FAKE_PACKER_LOG": str(self.packer_log),
            "FAKE_SSH_LOG": str(self.ssh_log),
            "FAKE_SCP_LOG": str(self.scp_log),
            "FAKE_TIMEOUT_LOG": str(self.timeout_log),
            "PKR_VAR_AMI_PUBLIC": "true",
        }
        if include_runtime:
            environment["XDG_RUNTIME_DIR"] = str(runtime or self.runtime)
        environment.update(extra_env or {})
        return subprocess.run(
            [str(script), *arguments],
            cwd=self.target,
            env=environment,
            text=True,
            capture_output=True,
            timeout=timeout,
            check=False,
        )

    def _path_without_packer(self) -> Path:
        restricted = self.root / "no-packer-bin"
        restricted.mkdir()
        for command in ("aws", "jq", "curl", "nc", "ssh", "scp", "rm", "rmdir"):
            (restricted / command).symlink_to(self.bin / command)
        for command in ("basename", "cut", "date", "dirname", "grep", "python3"):
            executable = shutil.which(command)
            self.assertIsNotNone(executable)
            (restricted / command).symlink_to(executable)
        for command in ("sleep", "timeout"):
            (restricted / command).symlink_to(self.bin / command)
        return restricted

    def _aws_calls(self) -> list[list[str]]:
        if not self.aws_log.exists():
            return []
        return [
            json.loads(line) for line in self.aws_log.read_text().splitlines()
        ]

    def _operations(self) -> list[str]:
        return [call[1] for call in self._aws_calls() if len(call) > 1]

    def _name_tags(self) -> list[str]:
        return [
            value
            for call in self._aws_calls()
            if call[:2] == ["ec2", "create-tags"]
            for value in call
            if value.startswith("Key=Name,Value=")
        ]

    def _delete_calls(self) -> list[list[str]]:
        return [
            call for call in self._aws_calls()
            if call[:2] == ["ec2", "delete-key-pair"]
        ]

    @staticmethod
    def _metadata(**changes: object) -> str:
        image: dict[str, object] = {
            "ImageId": "ami-03d2ffba2af95178a",
            "OwnerId": "703671893074",
            "State": "available",
            "Public": False,
            "Name": (
                "synxdb-cloud-packer-rocky9-"
                "20260727-120000-PASSED"
            ),
        }
        image.update(changes)
        return json.dumps({"Images": [image]})

    def test_key_exists_only_in_private_runtime_and_cleanup_removes_it(self) -> None:
        result = self._run()

        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        records = [
            json.loads(line) for line in self.packer_log.read_text().splitlines()
        ]
        for record in records:
            self.assertTrue(record["key_exists"])
            self.assertEqual(record["key_value"], "FAKE-PRIVATE-KEY-CANARY\n")
            self.assertLessEqual(record["key_mode"] & 0o777, 0o600)
            self.assertEqual(record["cwd_pems"], [])
            key_path = Path(record["key_path"])
            self.assertTrue(key_path.is_relative_to(self.runtime))
            self.assertEqual(record["key_parent_mode"], 0o700)
            self.assertFalse(key_path.parent.exists())
        self.assertFalse(Path(records[0]["key_path"]).exists())
        self.assertEqual(list(self.target.glob("*.pem")), [])
        self.assertEqual(len(self._delete_calls()), 1)

    def test_bad_xdg_runtime_fails_before_aws(self) -> None:
        bad_mode = self.root / "bad-mode"
        bad_mode.mkdir(mode=0o755)
        link = self.root / "runtime-link"
        link.symlink_to(self.runtime, target_is_directory=True)
        cases = (
            ("symlink", link, True),
            ("mode", bad_mode, True),
        )
        if os.geteuid() != 0:
            cases = (*cases, ("owner", Path("/root"), True))
        for name, runtime, included in cases:
            self.aws_log.unlink(missing_ok=True)
            with self.subTest(case=name):
                result = self._run(runtime=runtime, include_runtime=included)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.aws_log.exists())

    def test_absent_xdg_uses_private_runner_temp_and_cleans_it(self) -> None:
        runner_temp = self.root / "runner-temp"
        runner_temp.mkdir(mode=0o755)

        result = self._run(
            include_runtime=False,
            extra_env={"RUNNER_TEMP": str(runner_temp)},
        )

        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        records = [
            json.loads(line) for line in self.packer_log.read_text().splitlines()
        ]
        key_path = Path(records[0]["key_path"])
        self.assertTrue(key_path.is_relative_to(runner_temp))
        self.assertEqual(list(runner_temp.iterdir()), [])
        self.assertEqual(list(self.target.glob("*.pem")), [])

    def test_hostile_fallback_runtime_base_is_rejected_before_aws(self) -> None:
        writable = self.root / "writable-fallback"
        writable.mkdir()
        writable.chmod(0o777)
        self.assertNotEqual(writable.stat().st_mode & 0o022, 0)
        link = self.root / "fallback-link"
        link.symlink_to(writable, target_is_directory=True)
        for base in (writable, link):
            self.aws_log.unlink(missing_ok=True)
            with self.subTest(base=base):
                result = self._run(
                    include_runtime=False,
                    extra_env={"RUNNER_TEMP": str(base)},
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self._aws_calls(), [])

    def test_helpers_must_be_executable(self) -> None:
        copied_scripts = self.root / "copied-scripts"
        shutil.copytree(SCRIPT.parent, copied_scripts)
        copied_script = copied_scripts / SCRIPT.name
        helper = copied_scripts / "validate-ami-metadata.py"
        helper.chmod(0o600)

        result = self._run(script=copied_script)

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self._aws_calls(), [])

    def test_key_pipeline_and_first_post_create_failures_delete_once(self) -> None:
        cases = (
            {"FAKE_CREATE_KEY_FAILURE": "1"},
            {"FAKE_REMOVE_KEY_DIRECTORY": "1"},
            {"FAKE_PACKER_INIT_FAILURE": "1"},
        )
        for environment in cases:
            self.aws_log.unlink(missing_ok=True)
            with self.subTest(environment=environment):
                result = self._run(extra_env=environment)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(len(self._delete_calls()), 1)
                self.assertEqual(
                    list(self.runtime.glob("cloudberry-packer-*")), []
                )

    def test_malformed_public_ip_fails_before_security_group_mutation(self) -> None:
        values = (
            "192.0.2.1 198.51.100.2",
            "--help",
            "192.0.2.1;touch /tmp/not-executed",
            "192.0.2.1\n198.51.100.2",
            "999.0.2.1",
        )
        for value in values:
            self.aws_log.unlink(missing_ok=True)
            with self.subTest(value=value):
                result = self._run(extra_env={"FAKE_PUBLIC_IP": value})
                self.assertNotEqual(result.returncode, 0)
                operations = [call[1] for call in self._aws_calls() if len(call) > 1]
                self.assertNotIn("create-security-group", operations)
                self.assertNotIn("authorize-security-group-ingress", operations)
                self.assertEqual(len(self._delete_calls()), 1)

    def test_valid_public_ip_is_one_exact_cidr_argument(self) -> None:
        result = self._run(extra_env={"FAKE_PUBLIC_IP": "192.0.2.25"})

        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        authorize = [
            call for call in self._aws_calls()
            if call[:2] == ["ec2", "authorize-security-group-ingress"]
        ]
        self.assertEqual(len(authorize), 1)
        cidr_index = authorize[0].index("--cidr")
        self.assertEqual(authorize[0][cidr_index + 1], "192.0.2.25/32")

    def test_normal_packer_commands_receive_fixed_region_variable(self) -> None:
        result = self._run(extra_env={"AWS_REGION": "us-east-1"})

        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        records = [
            json.loads(line) for line in self.packer_log.read_text().splitlines()
        ]
        for operation in ("validate", "build"):
            argv = next(record["argv"] for record in records if record["argv"][0] == operation)
            self.assertIn("region=us-west-2", argv)

    def test_goss_ssh_and_scp_argv_are_recorded_exactly(self) -> None:
        result = self._run()

        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        ssh_calls = [json.loads(line) for line in self.ssh_log.read_text().splitlines()]
        scp_calls = [json.loads(line) for line in self.scp_log.read_text().splitlines()]
        self.assertTrue(any("/usr/local/bin/goss" in " ".join(call) for call in ssh_calls))
        self.assertTrue(any("goss.yaml" in " ".join(call) for call in scp_calls))
        self.assertTrue(any("goss-results.xml" in " ".join(call) for call in scp_calls))
        for call in (*ssh_calls, *scp_calls):
            self.assertIn("-i", call)
            key = call[call.index("-i") + 1]
            self.assertTrue(key.startswith(str(self.runtime)))

    def test_ssh_exhaustion_cleans_before_bounded_ami_discard(self) -> None:
        result = self._run(extra_env={"FAKE_SSH_UNREACHABLE": "1"})

        self.assertNotEqual(result.returncode, 0)
        events = self.event_log.read_text().splitlines()
        self.assertIn("aws:deregister-image", events)
        discard_index = events.index("aws:deregister-image")
        for operation in (
            "aws:delete-key-pair",
            "aws:terminate-instances",
            "aws:wait",
            "aws:delete-security-group",
        ):
            self.assertLess(events.index(operation), discard_index)
        self.assertNotIn("aws:create-tags", events)
        self.assertEqual(len(self._delete_calls()), 1)

    def test_failed_goss_discards_run_ami_and_its_snapshots(self) -> None:
        result = self._run(extra_env={"FAKE_GOSS_FAILURE": "1"})

        self.assertNotEqual(result.returncode, 0)
        operations = self._operations()
        self.assertIn("deregister-image", operations)
        calls = self._aws_calls()
        deregister = [call for call in calls if call[:2] == ["ec2", "deregister-image"]]
        self.assertEqual(len(deregister), 1)
        self.assertEqual(deregister[0][deregister[0].index("--image-id") + 1], "ami-fake")
        # snapshot ids are looked up while the image is still registered
        lookup_index = next(
            index for index, call in enumerate(calls)
            if call[:2] == ["ec2", "describe-images"]
            and any("BlockDeviceMappings" in value for value in call)
        )
        self.assertLess(lookup_index, operations.index("deregister-image"))
        snapshots = sorted(
            call[call.index("--snapshot-id") + 1]
            for call in calls if call[:2] == ["ec2", "delete-snapshot"]
        )
        self.assertEqual(snapshots, ["snap-0123456789abcdef0", "snap-0fedcba9876543210"])
        self.assertGreater(
            operations.index("delete-snapshot"), operations.index("deregister-image")
        )
        self.assertEqual(self._name_tags(), [])
        self.assertIn("ami-fake", result.stdout)

    def test_keep_failed_ami_tags_instead_of_discarding(self) -> None:
        for arguments, environment in (
            (("--keep-failed-ami",), {}),
            ((), {"KEEP_FAILED_AMI": "1"}),
        ):
            self.aws_log.unlink(missing_ok=True)
            with self.subTest(arguments=arguments, environment=environment):
                result = self._run(
                    *arguments, extra_env={"FAKE_GOSS_FAILURE": "1", **environment}
                )
                self.assertNotEqual(result.returncode, 0)
                operations = self._operations()
                self.assertNotIn("deregister-image", operations)
                self.assertNotIn("delete-snapshot", operations)
                tags = self._name_tags()
                self.assertEqual(len(tags), 1)
                self.assertTrue(tags[0].endswith("-FAILED"))

    def test_existing_ami_failure_tags_and_never_deregisters(self) -> None:
        result = self._run(
            "--existing-ami",
            "ami-03d2ffba2af95178a",
            extra_env={"FAKE_AMI_METADATA": self._metadata(), "FAKE_GOSS_FAILURE": "1"},
        )

        self.assertNotEqual(result.returncode, 0)
        operations = self._operations()
        self.assertNotIn("deregister-image", operations)
        self.assertNotIn("delete-snapshot", operations)
        tags = self._name_tags()
        self.assertEqual(len(tags), 1)
        self.assertTrue(tags[0].endswith("-FAILED"))

    def test_deregister_failure_falls_back_to_failed_tag(self) -> None:
        result = self._run(
            extra_env={"FAKE_GOSS_FAILURE": "1", "FAKE_DEREGISTER_FAILURE": "1"}
        )

        self.assertNotEqual(result.returncode, 0)
        operations = self._operations()
        self.assertIn("deregister-image", operations)
        self.assertNotIn("delete-snapshot", operations)
        tags = self._name_tags()
        self.assertEqual(len(tags), 1)
        self.assertTrue(tags[0].endswith("-FAILED"))
        self.assertIn("WARNING", result.stderr)

    def test_snapshot_delete_failure_warns_and_tries_every_snapshot(self) -> None:
        result = self._run(
            extra_env={"FAKE_GOSS_FAILURE": "1", "FAKE_SNAPSHOT_DELETE_FAILURE": "1"}
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self._operations().count("delete-snapshot"), 2)
        self.assertIn("WARNING", result.stderr)
        self.assertIn("snap-0123456789abcdef0", result.stderr)
        self.assertIn("snap-0fedcba9876543210", result.stderr)
        # the image is already deregistered; there is nothing left to tag
        self.assertEqual(self._name_tags(), [])

    def test_snapshot_lookup_failure_tags_instead_of_orphaning(self) -> None:
        result = self._run(
            extra_env={"FAKE_GOSS_FAILURE": "1", "FAKE_AMI_SNAPSHOT_LOOKUP_FAILURE": "1"}
        )

        self.assertNotEqual(result.returncode, 0)
        operations = self._operations()
        # Without the snapshot ids the image must not be deregistered: that
        # would orphan its snapshots silently. Tag it for the cleanup workflow.
        self.assertNotIn("deregister-image", operations)
        self.assertNotIn("delete-snapshot", operations)
        tags = self._name_tags()
        self.assertEqual(len(tags), 1)
        self.assertTrue(tags[0].endswith("-FAILED"))
        self.assertIn("WARNING", result.stderr)

    def test_ami_without_snapshots_is_deregistered_without_warnings(self) -> None:
        result = self._run(
            extra_env={"FAKE_GOSS_FAILURE": "1", "FAKE_AMI_SNAPSHOTS": "None"}
        )

        self.assertNotEqual(result.returncode, 0)
        operations = self._operations()
        self.assertIn("deregister-image", operations)
        self.assertNotIn("delete-snapshot", operations)
        self.assertNotIn("unexpected snapshot id", result.stderr)
        self.assertEqual(self._name_tags(), [])

    def test_discard_refuses_ami_outside_target_name_prefix(self) -> None:
        result = self._run(
            extra_env={"FAKE_GOSS_FAILURE": "1", "FAKE_AMI_METADATA": "untrusted-image"}
        )

        self.assertNotEqual(result.returncode, 0)
        operations = self._operations()
        self.assertNotIn("deregister-image", operations)
        self.assertNotIn("delete-snapshot", operations)
        tags = self._name_tags()
        self.assertEqual(len(tags), 1)
        self.assertTrue(tags[0].endswith("-FAILED"))
        self.assertIn("WARNING", result.stderr)

    def test_keep_failed_ami_env_is_case_insensitive(self) -> None:
        for value in ("TRUE", "True", "Yes"):
            self.aws_log.unlink(missing_ok=True)
            with self.subTest(value=value):
                result = self._run(
                    extra_env={"FAKE_GOSS_FAILURE": "1", "KEEP_FAILED_AMI": value}
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("deregister-image", self._operations())
                self.assertEqual(len(self._name_tags()), 1)

    def test_hung_ami_discard_cannot_block_critical_cleanup(self) -> None:
        started = time.monotonic()
        result = self._run(
            extra_env={
                "FAKE_SECURITY_GROUP_FAILURE": "1",
                "FAKE_DEREGISTER_STALL": "1",
            },
            timeout=28,
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertLess(time.monotonic() - started, 25)
        self.assertEqual(len(self._delete_calls()), 1)
        events = self.event_log.read_text().splitlines()
        self.assertIn("aws:deregister-image", events)
        self.assertLess(
            events.index("aws:delete-key-pair"),
            events.index("aws:deregister-image"),
        )

    def test_cleanup_waits_with_realistic_bound_and_retries_sg(self) -> None:
        result = self._run(
            extra_env={
                "FAKE_TERMINATE_DELAY": "0.2",
                "FAKE_SG_DEPENDENCY_ONCE": "1",
            }
        )

        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        timeout_calls = [
            json.loads(line) for line in self.timeout_log.read_text().splitlines()
        ]
        waits = [call for call in timeout_calls if "instance-terminated" in call]
        self.assertEqual(len(waits), 1)
        self.assertIn("300s", waits[0])
        operations = [call[1] for call in self._aws_calls() if len(call) > 1]
        self.assertEqual(operations.count("delete-security-group"), 2)
        self.assertGreater(
            operations.index("delete-security-group"),
            operations.index("wait"),
        )

    def test_cleanup_warns_instead_of_false_termination_success(self) -> None:
        result = self._run(
            extra_env={
                "FAKE_TERMINATE_FAILURE": "1",
                "FAKE_WAIT_FAILURE": "1",
            }
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("terminated successfully", result.stdout)
        self.assertNotIn("Cleanup completed", result.stdout)
        self.assertIn("WARNING", result.stderr)
        operations = [call[1] for call in self._aws_calls() if len(call) > 1]
        self.assertIn("delete-security-group", operations)

    def test_ambiguous_sg_and_instance_creates_are_recovered(self) -> None:
        for variable, expected in (
            ("FAKE_SG_LOST_RESPONSE", "sg-ambiguous"),
            ("FAKE_INSTANCE_LOST_RESPONSE", "i-ambiguous"),
        ):
            self.aws_log.unlink(missing_ok=True)
            with self.subTest(variable=variable):
                result = self._run(extra_env={variable: "1"})
                self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
                calls = self._aws_calls()
                run_call = next(
                    call for call in calls if call[:2] == ["ec2", "run-instances"]
                )
                self.assertIn("--client-token", run_call)
                self.assertIn("--tag-specifications", run_call)
                operations = [call[1] for call in calls if len(call) > 1]
                self.assertIn("describe-security-groups", operations)
                self.assertIn("describe-instances", operations)

    def test_run_instance_retries_same_token_before_discovery(self) -> None:
        result = self._run(extra_env={"FAKE_INSTANCE_LOST_RESPONSE": "1"})

        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        calls = [
            call for call in self._aws_calls()
            if call[:2] == ["ec2", "run-instances"]
        ]
        self.assertEqual(len(calls), 2)
        tokens = [call[call.index("--client-token") + 1] for call in calls]
        self.assertEqual(tokens[0], tokens[1])

    def test_discovery_retries_none_and_normalizes_no_match(self) -> None:
        eventual = self._run(
            extra_env={
                "FAKE_SG_LOST_RESPONSE": "1",
                "FAKE_DISCOVERY_NONE_COUNT": "1",
            }
        )
        self.assertEqual(eventual.returncode, 0, eventual.stderr + eventual.stdout)
        self.assertNotIn("--group-id None", self.aws_log.read_text())

        self.aws_log.unlink(missing_ok=True)
        missing = self._run(
            extra_env={
                "FAKE_INSTANCE_LOST_RESPONSE": "1",
                "FAKE_DISCOVERY_NONE_COUNT": "99",
            }
        )
        self.assertNotEqual(missing.returncode, 0)
        calls = self._aws_calls()
        for call in calls:
            self.assertNotIn("None", call)
        discoveries = [
            call for call in calls
            if call[:2] == ["ec2", "describe-instances"] and "--filters" in call
        ]
        self.assertEqual(len(discoveries), 2)

    def test_stalled_discovery_is_bounded_and_never_uses_none(self) -> None:
        started = time.monotonic()
        result = self._run(
            extra_env={
                "FAKE_SG_LOST_RESPONSE": "1",
                "FAKE_DISCOVERY_STALL": "1",
            },
            timeout=28,
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertLess(time.monotonic() - started, 30)
        for call in self._aws_calls():
            self.assertNotIn("None", call)
        discoveries = [
            call for call in self._aws_calls()
            if call[:2] == ["ec2", "describe-security-groups"]
            and any("Name=group-name" in value for value in call)
        ]
        self.assertEqual(len(discoveries), 2)
        timeout_calls = [
            json.loads(line) for line in self.timeout_log.read_text().splitlines()
        ]
        discovery_timeouts = [
            call for call in timeout_calls
            if "describe-security-groups" in call
            and any("Name=group-name" in value for value in call)
        ]
        self.assertEqual(len(discovery_timeouts), 2)
        self.assertTrue(all("10s" in call for call in discovery_timeouts))

    def test_run_identifiers_are_random_and_aws_safe(self) -> None:
        tokens = []
        for _ in range(2):
            self.aws_log.unlink(missing_ok=True)
            result = self._run()
            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            call = next(
                call for call in self._aws_calls()
                if call[:2] == ["ec2", "run-instances"]
            )
            tokens.append(call[call.index("--client-token") + 1])
        self.assertNotEqual(tokens[0], tokens[1])
        for token in tokens:
            self.assertRegex(token, r"^[A-Za-z0-9-]{1,64}$")

    def test_result_suffix_is_replaced_not_duplicated(self) -> None:
        cases = (
            ("PASSED", {}, "PASSED"),
            ("FAILED", {}, "PASSED"),
            ("PASSED", {"FAKE_SECURITY_GROUP_FAILURE": "1"}, "FAILED"),
        )
        for existing, extra, expected in cases:
            self.aws_log.unlink(missing_ok=True)
            metadata = self._metadata(
                Name=(
                    "synxdb-cloud-packer-rocky9-"
                    f"20260727-120000-{existing}"
                )
            )
            with self.subTest(existing=existing, expected=expected):
                result = self._run(
                    "--existing-ami",
                    "ami-03d2ffba2af95178a",
                    extra_env={"FAKE_AMI_METADATA": metadata, **extra},
                )
                self.assertEqual(result.returncode == 0, expected == "PASSED")
                tags = [
                    value
                    for call in self._aws_calls()
                    if call[:2] == ["ec2", "create-tags"]
                    for value in call
                    if value.startswith("Key=Name,Value=")
                ]
                self.assertEqual(len(tags), 1)
                self.assertTrue(tags[0].endswith(f"-{expected}"))
                self.assertNotRegex(tags[0], r"-(?:PASSED|FAILED)-(?:PASSED|FAILED)$")

    def test_stalled_cleanup_is_bounded_and_does_not_recurse(self) -> None:
        started = time.monotonic()
        result = self._run(extra_env={"FAKE_DELETE_STALL": "1"})

        self.assertNotEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertLess(time.monotonic() - started, 8)
        self.assertEqual(len(self._delete_calls()), 1)
        self.assertNotIn("Cleanup completed", result.stdout)

    def test_hung_failure_tagging_cannot_block_critical_cleanup(self) -> None:
        started = time.monotonic()
        result = self._run(
            "--keep-failed-ami",
            extra_env={
                "FAKE_SECURITY_GROUP_FAILURE": "1",
                "FAKE_TAG_STALL": "1",
            }
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertLess(time.monotonic() - started, 8)
        self.assertEqual(len(self._delete_calls()), 1)
        events = self.event_log.read_text().splitlines()
        self.assertLess(
            events.index("aws:delete-key-pair"),
            events.index("aws:create-tags"),
        )

    def test_local_removal_failure_cannot_block_remote_key_delete(self) -> None:
        result = self._run(
            extra_env={
                "FAKE_PACKER_INIT_FAILURE": "1",
                "FAKE_LOCAL_REMOVE_FAILURE": "1",
            }
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(self._delete_calls()), 1)
        events = self.event_log.read_text().splitlines()
        delete_index = events.index("aws:delete-key-pair")
        self.assertLess(delete_index, events.index("rm"))
        self.assertLess(delete_index, events.index("rmdir"))

    def test_default_and_private_flag_never_publish(self) -> None:
        for arguments in ((), ("--private",)):
            self.aws_log.unlink(missing_ok=True)
            with self.subTest(arguments=arguments):
                result = self._run(*arguments)
                self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
                aws_calls = self.aws_log.read_text()
                self.assertNotIn("modify-image-attribute", aws_calls)
                self.assertNotIn("disable-image-block-public-access", aws_calls)
                self.assertIn("remains private", result.stdout)

    def test_existing_ami_skips_packer_and_runs_private_test_flow(self) -> None:
        ami_id = "ami-03d2ffba2af95178a"
        result = self._run(
            "--existing-ami",
            ami_id,
            extra_env={
                "FAKE_AMI_METADATA": self._metadata(),
                "AWS_REGION": "us-east-1",
            },
        )

        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertFalse(self.packer_log.exists())
        calls = self._aws_calls()
        operations = [call[1] for call in calls if len(call) > 1]
        self.assertLess(
            operations.index("describe-images"),
            operations.index("create-security-group"),
        )
        run_instance = next(
            call for call in calls if call[:2] == ["ec2", "run-instances"]
        )
        self.assertEqual(run_instance[run_instance.index("--image-id") + 1], ami_id)
        self.assertEqual(
            run_instance[run_instance.index("--instance-type") + 1], "t3.medium"
        )
        describe = next(
            call for call in calls if call[:2] == ["ec2", "describe-images"]
        )
        self.assertEqual(describe[describe.index("--region") + 1], "us-west-2")
        passed_tag = [
            call for call in calls
            if call[:2] == ["ec2", "create-tags"]
            and any(value.endswith("-PASSED") for value in call)
        ]
        self.assertEqual(len(passed_tag), 1)
        self.assertEqual(len(self._delete_calls()), 1)
        self.assertEqual(list(self.runtime.glob("cloudberry-packer-*")), [])
        forbidden = {
            "modify-image-attribute",
            "deregister-image",
            "delete-snapshot",
        }
        self.assertTrue(forbidden.isdisjoint(operations))

    def test_arm64_ami_launches_graviton_test_instance(self) -> None:
        result = self._run(extra_env={"FAKE_AMI_ARCHITECTURE": "arm64"})

        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        run_instance = next(
            call for call in self._aws_calls()
            if call[:2] == ["ec2", "run-instances"]
        )
        self.assertEqual(
            run_instance[run_instance.index("--instance-type") + 1],
            "t4g.medium",
        )

    def test_x86_64_ami_keeps_t3_test_instance(self) -> None:
        result = self._run()

        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        run_instance = next(
            call for call in self._aws_calls()
            if call[:2] == ["ec2", "run-instances"]
        )
        self.assertEqual(
            run_instance[run_instance.index("--instance-type") + 1],
            "t3.medium",
        )

    def test_existing_ami_rejects_bad_id_before_key_creation(self) -> None:
        for ami_id in ("ami-xyz", "ami-03d2ffba2af95178a;echo", "--help", ""):
            self.aws_log.unlink(missing_ok=True)
            with self.subTest(ami_id=ami_id):
                result = self._run("--existing-ami", ami_id)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self._aws_calls(), [])

    def test_existing_ami_rejects_metadata_before_security_group(self) -> None:
        valid_image = json.loads(self._metadata())["Images"][0]
        cases = {
            "empty": json.dumps({"Images": []}),
            "multiple": json.dumps({"Images": [valid_image, valid_image]}),
            "wrong-id": self._metadata(ImageId="ami-00000000000000000"),
            "wrong-owner": self._metadata(OwnerId="000000000000"),
            "wrong-state": self._metadata(State="pending"),
            "public": self._metadata(Public=True),
            "wrong-name": self._metadata(Name="untrusted-image"),
            "malformed": "{not-json",
        }
        for name, metadata in cases.items():
            self.aws_log.unlink(missing_ok=True)
            with self.subTest(case=name):
                result = self._run(
                    "--existing-ami",
                    "ami-03d2ffba2af95178a",
                    extra_env={"FAKE_AMI_METADATA": metadata},
                )
                self.assertNotEqual(result.returncode, 0)
                calls = self._aws_calls()
                self.assertEqual(len(calls), 1)
                self.assertEqual(calls[0][:2], ["ec2", "describe-images"])
                self.assertEqual(
                    list(self.runtime.glob("cloudberry-packer-*")), []
                )

    def test_existing_ami_does_not_require_packer_executable(self) -> None:
        result = self._run(
            "--existing-ami",
            "ami-03d2ffba2af95178a",
            extra_env={"FAKE_AMI_METADATA": self._metadata()},
            path=self._path_without_packer(),
        )

        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertFalse(self.packer_log.exists())

    def test_shell_syntax_is_valid(self) -> None:
        result = subprocess.run(
            ["bash", "-n", str(SCRIPT)], capture_output=True, text=True, check=False
        )
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
