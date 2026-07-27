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
