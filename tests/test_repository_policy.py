from __future__ import annotations

from pathlib import Path
import re
import unittest
import yaml


REPOSITORY = Path(__file__).resolve().parents[1]


class RepositoryPolicyTests(unittest.TestCase):
    def test_ci_runs_offline_unittest_before_build_script(self) -> None:
        for name in ("ami-build-manual.yml", "ami-build-on-change.yml"):
            workflow = (REPOSITORY / ".github/workflows" / name).read_text()
            with self.subTest(workflow=name):
                test_position = workflow.find(
                    "python3 -m unittest discover -s tests"
                )
                build_position = workflow.rfind("../../../../scripts/packer-build-and-test.sh")
                self.assertGreaterEqual(test_position, 0)
                self.assertGreater(build_position, test_position)
                self.assertIn("install -d -m 0700", workflow)
                self.assertIn("XDG_RUNTIME_DIR=", workflow)
                self.assertIn("GITHUB_ENV", workflow)

    def test_manual_workflow_has_no_publication_knob(self) -> None:
        workflow = (
            REPOSITORY / ".github/workflows/ami-build-manual.yml"
        ).read_text()
        self.assertNotIn("make_public", workflow)
        self.assertNotIn("MAKE_PUBLIC", workflow)

    def test_docs_describe_private_only_builds(self) -> None:
        for relative in ("README.md", ".github/workflows/README.md"):
            content = (REPOSITORY / relative).read_text().lower()
            with self.subTest(document=relative):
                self.assertNotIn("make ami public", content)
                self.assertNotIn("make public", content)
                self.assertIn("private", content)

    def test_hermes_directory_is_ignored(self) -> None:
        patterns = (REPOSITORY / ".gitignore").read_text().splitlines()
        self.assertIn(".hermes/", patterns)

    def test_all_workflows_are_fixed_to_us_west_2(self) -> None:
        for workflow_path in sorted(
            (REPOSITORY / ".github/workflows").glob("*.yml")
        ):
            workflow = workflow_path.read_text()
            with self.subTest(workflow=workflow_path.name):
                self.assertNotIn("aws_region:", workflow)
                self.assertNotIn("vars.AWS_REGION", workflow)
                self.assertIn("AWS_REGION: us-west-2", workflow)

    def test_change_detection_fetches_and_diffs_pull_request_shas(self) -> None:
        workflow = (
            REPOSITORY / ".github/workflows/ami-build-on-change.yml"
        ).read_text()
        self.assertIn("fetch-depth: 0", workflow)
        self.assertIn("github.event.pull_request.base.sha", workflow)
        self.assertIn("github.event.pull_request.head.sha", workflow)
        self.assertNotIn("origin/${{ github.base_ref }}...HEAD", workflow)

    def test_pull_requests_validate_without_building_or_cleaning_aws(self) -> None:
        workflow_path = REPOSITORY / ".github/workflows/ami-build-on-change.yml"
        workflow = yaml.safe_load(workflow_path.read_text())
        event_gate = "github.event_name != 'pull_request'"

        for job_name in ("build", "cleanup"):
            with self.subTest(job=job_name):
                job = workflow["jobs"][job_name]
                job_if = str(job.get("if", ""))
                self.assertIn(event_gate, job_if)

                for step in job.get("steps", []):
                    if "configure-aws-credentials" in str(step.get("uses", "")):
                        step_if = str(step.get("if", ""))
                        self.assertIn(
                            event_gate,
                            step_if,
                            f"{job_name} credential step must be gated on non-PR events",
                        )

    def test_retired_elastic_platform_is_not_an_active_target(self) -> None:
        # Split the retired name so this test does not count itself as an
        # active configuration reference.
        retired = "al2023" + "-synxdb-elastic"
        self.assertFalse(
            (REPOSITORY / "vm-images/aws/cloudberry/build" / retired).exists()
        )
        self.assertFalse(
            (REPOSITORY / "vm-images/aws/synxdb-cloud/build" / retired).exists()
        )
        active_configuration = (
            REPOSITORY
            / "vm-images/scripts/packer-build-and-test.sh"
        ).read_text()
        active_configuration += (
            REPOSITORY / "tests/test_packer_template_security.py"
        ).read_text()
        for workflow in (REPOSITORY / ".github/workflows").glob("*.yml"):
            active_configuration += workflow.read_text()
        self.assertNotIn(retired, active_configuration)

    def test_retired_rocky8_platform_is_not_an_active_target(self) -> None:
        # Split the retired name so this test does not count itself as an
        # active configuration reference.
        retired = "rocky" + "8"
        self.assertFalse(
            (REPOSITORY / "vm-images/aws/cloudberry/build" / retired).exists()
        )
        self.assertFalse(
            (REPOSITORY / "vm-images/aws/synxdb-cloud/build" / retired).exists()
        )

        active_surfaces = [
            REPOSITORY
            / "vm-images/scripts/packer-build-and-test.sh",
            REPOSITORY / "tests/test_packer_template_security.py",
            REPOSITORY / "README.md",
            REPOSITORY / "CLAUDE.md",
            REPOSITORY / ".github/workflows/README.md",
            REPOSITORY
            / "vm-images/common/tests/README.md",
            *(REPOSITORY / ".github/workflows").glob("*.yml"),
        ]
        # Deliberate retirement/history wording is allowed; stale operational
        # references anywhere else are not.
        allowed_indicators = (
            "retired",
            "archived",
            "recoverable",
            "history",
            "historical",
        )

        # Catch both "rocky8" and spaced forms like "Rocky 8/9/10".
        variants = (retired, "rocky 8")
        for surface in active_surfaces:
            for line_number, line in enumerate(surface.read_text().splitlines(), 1):
                lowered = line.lower()
                if any(variant in lowered for variant in variants) and not any(
                    indicator in lowered for indicator in allowed_indicators
                ):
                    self.fail(
                        f"stale active reference to {retired!r} at "
                        f"{surface}:{line_number}: {line!r}"
                    )

    def test_rocky10_claude_launcher_is_symlink(self) -> None:
        goss = (
            REPOSITORY
            / "vm-images/aws/cloudberry/build/rocky10/tests/goss.yaml"
        ).read_text()
        for user in ("gpadmin", "cbadmin"):
            with self.subTest(user=user):
                path = f"/home/{user}/.local/bin/claude"
                block = self._extract_yaml_block(goss, path)
                self.assertIn("exists: true", block)
                self.assertIn("filetype: symlink", block)

    @staticmethod
    def _extract_yaml_block(text: str, key: str) -> str:
        lines = text.splitlines()
        for index, line in enumerate(lines):
            if line.strip().startswith(key + ":"):
                start = index
                break
        else:
            raise AssertionError(f"key {key!r} not found")
        end = start + 1
        while end < len(lines) and (
            lines[end].startswith(" ") or lines[end].startswith("\t")
        ):
            end += 1
        return "\n".join(lines[start:end])

    def test_rocky10_has_no_nodejs(self) -> None:
        pkr = (
            REPOSITORY
            / "vm-images/aws/cloudberry/build/rocky10/main.pkr.hcl"
        ).read_text()
        for consumer in (
            "system_add_nodejs.sh",
            "system_add_pi.sh",
            "system_add_ai_toolchain.sh",
            "system_add_omnigent.sh",
        ):
            with self.subTest(consumer=consumer):
                self.assertNotIn(consumer, pkr)

        goss = (
            REPOSITORY
            / "vm-images/aws/cloudberry/build/rocky10/tests/goss.yaml"
        ).read_text()
        self.assertNotIn("nodejs:", goss)
        self.assertNotIn("node --version", goss)

    def test_synxdb_cloud_templates_require_no_cloudsmith_variables(self) -> None:
        templates = sorted(
            (REPOSITORY / "vm-images/aws/synxdb-cloud/build").glob(
                "*/main.pkr.hcl"
            )
        )
        self.assertGreater(len(templates), 0)
        for template in templates:
            content = template.read_text()
            with self.subTest(template=template.parent.name):
                self.assertNotIn('variable "cloudsmith_user"', content)
                self.assertNotIn('variable "cloudsmith_token"', content)
                self.assertNotIn("var.cloudsmith_user", content)
                self.assertNotIn("var.cloudsmith_token", content)

        for name in ("ami-build-manual.yml", "ami-build-on-change.yml"):
            workflow = (REPOSITORY / ".github/workflows" / name).read_text()
            with self.subTest(workflow=name):
                self.assertNotIn("PKR_VAR_cloudsmith_user", workflow)
                self.assertNotIn("PKR_VAR_cloudsmith_token", workflow)

    def test_ubuntu24_synxdb_cloud_rebuilds_when_shared_scripts_change(self) -> None:
        pkr = (
            REPOSITORY
            / "vm-images/aws/synxdb-cloud/build/ubuntu24/main.pkr.hcl"
        ).read_text()
        shared_scripts = sorted(
            set(re.findall(r"\.\./\.\./\.\./\.\./common/scripts/([a-z0-9_]+\.sh)", pkr))
        )
        self.assertTrue(shared_scripts)
        workflow = (
            REPOSITORY / ".github/workflows/ami-build-on-change.yml"
        ).read_text()
        for script in shared_scripts:
            with self.subTest(script=script):
                mapping = re.search(
                    r'\["' + re.escape(script) + r'"\]="([^"]*)"', workflow
                )
                self.assertIsNotNone(
                    mapping, f"{script} missing from COMMON_SCRIPT_DEPS"
                )
                self.assertIn(
                    "ubuntu24", mapping.group(1).split(",")
                )

    def test_ubuntu24_goss_covers_ai_toolchain_executables(self) -> None:
        toolchain = (
            REPOSITORY
            / "vm-images/common/scripts"
            / "system_add_ai_toolchain.sh"
        ).read_text()
        # The installer hard-fails unless every binary in this loop exists;
        # goss must verify each of them (and its version command) too.
        verification_loop = toolchain.split("for BIN in", 1)[1].split("do", 1)[0]
        suffixes = sorted(
            set(re.findall(r'"\$\{USER_HOME\}/([^"]+)"', verification_loop))
        )
        self.assertTrue(suffixes)
        goss = (
            REPOSITORY
            / "vm-images/aws/synxdb-cloud/build/ubuntu24/tests"
            / "goss.yaml"
        ).read_text()
        for suffix in suffixes:
            path = f"/home/ubuntu/{suffix}"
            with self.subTest(executable=path):
                self.assertIn(path, goss)
        # herdr installs system-wide via its own provisioner
        self.assertIn("/usr/local/bin/herdr", goss)

    def test_template_comments_explain_description_omission_without_version_pin(self) -> None:
        for template in sorted(
            REPOSITORY.glob("vm-images/aws/*/build/*/main.pkr.hcl")
        ):
            content = template.read_text()
            with self.subTest(template=template.parent.name):
                self.assertIn(
                    "Omit ami_description: it would call denied "
                    "ModifyImageAttribute.",
                    content,
                )
                self.assertNotIn("amazon v1.8.2", content)

    def test_metadata_helper_documents_not_publicly_shared_policy(self) -> None:
        helper = (
            REPOSITORY
            / "vm-images/scripts/validate-ami-metadata.py"
        ).read_text()
        self.assertIn("not-publicly-shared", helper.splitlines()[1])


if __name__ == "__main__":
    unittest.main()
