from __future__ import annotations

from pathlib import Path
import unittest


REPOSITORY = Path(__file__).resolve().parents[1]


class RepositoryPolicyTests(unittest.TestCase):
    def test_ci_runs_offline_unittest_before_build_script(self) -> None:
        for name in ("ami-build-manual.yml", "ami-build-on-change.yml"):
            workflow = (REPOSITORY / ".github/workflows" / name).read_text()
            with self.subTest(workflow=name):
                test_position = workflow.find(
                    "python3 -m unittest discover -s tests"
                )
                build_position = workflow.rfind("../../scripts/packer-build-and-test.sh")
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
        workflow = (
            REPOSITORY / ".github/workflows/ami-build-on-change.yml"
        ).read_text()
        event_gate = "github.event_name != 'pull_request'"
        build = workflow.index("\n  build:\n")
        cleanup = workflow.index("\n  cleanup:\n")
        summary = workflow.index("\n  summary:\n")
        self.assertIn(event_gate, workflow[build:cleanup])
        self.assertIn(event_gate, workflow[cleanup:summary])

    def test_retired_elastic_platform_is_not_an_active_target(self) -> None:
        # Split the retired name so this test does not count itself as an
        # active configuration reference.
        retired = "al2023" + "-synxdb-elastic"
        self.assertFalse(
            (REPOSITORY / "vm-images/aws/cloudberry/build" / retired).exists()
        )
        active_configuration = (
            REPOSITORY
            / "vm-images/aws/cloudberry/scripts/packer-build-and-test.sh"
        ).read_text()
        active_configuration += (
            REPOSITORY / "tests/test_packer_template_security.py"
        ).read_text()
        for workflow in (REPOSITORY / ".github/workflows").glob("*.yml"):
            active_configuration += workflow.read_text()
        self.assertNotIn(retired, active_configuration)

    def test_synxdb_cloud_templates_require_no_cloudsmith_variables(self) -> None:
        templates = sorted(
            (REPOSITORY / "vm-images/aws/cloudberry/build").glob(
                "*-synxdb-cloud/main.pkr.hcl"
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

    def test_template_comments_explain_description_omission_without_version_pin(self) -> None:
        for template in sorted(
            (REPOSITORY / "vm-images/aws/cloudberry/build").glob(
                "*/main.pkr.hcl"
            )
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
            / "vm-images/aws/cloudberry/scripts/validate-ami-metadata.py"
        ).read_text()
        self.assertIn("not-publicly-shared", helper.splitlines()[1])


if __name__ == "__main__":
    unittest.main()
