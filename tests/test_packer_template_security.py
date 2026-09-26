from __future__ import annotations

from pathlib import Path
import re
import unittest


REPOSITORY = Path(__file__).resolve().parents[1]
SOURCE_HEADER = re.compile(r'\bsource\s+"amazon-ebs"\s+"[^"]+"\s*\{')
AMI_DESCRIPTION = re.compile(r"(?m)^\s*ami_description\s*=")
AMI_NAME = re.compile(r"(?m)^\s*ami_name\s*=\s*(.+)$")
# amazon-ebs settings that would bypass the checked SDK identity or share an
# image or snapshot outside the build account.
FORBIDDEN_SOURCE_SETTINGS = re.compile(
    r"(?m)^\s*(access_key|secret_key|token|profile|assume_role|"
    r"shared_credentials_file|vault_aws_engine|"
    r"ami_users|ami_groups|ami_org_arns|ami_ou_arns|"
    r"snapshot_users|snapshot_groups|ami_regions)\s*[={]"
)
WORLD_OPEN_CIDR = re.compile(r'(?<![0-9A-Fa-f:.])(?:0\.0\.0\.0/0|::/0)(?![0-9])')


PROVISIONER_HEADER = re.compile(r'\bprovisioner\s+"[^"]+"\s*\{')
PROVISIONER_SCRIPT = re.compile(r'(?m)^\s*script\s*=\s*"([^"]*)"')


def strip_hcl_comments(content: str) -> str:
    """Drop full-line # and // comments (the templates use no inline ones)."""
    return "\n".join(
        "" if line.lstrip().startswith(("#", "//")) else line
        for line in content.splitlines()
    )


def provisioner_blocks(content: str) -> list[str]:
    """Top-level provisioner blocks, in order, with comments removed."""
    content = strip_hcl_comments(content)
    blocks: list[str] = []
    for match in PROVISIONER_HEADER.finditer(content):
        depth = 0
        for index in range(match.end() - 1, len(content)):
            if content[index] == "{":
                depth += 1
            elif content[index] == "}":
                depth -= 1
                if depth == 0:
                    blocks.append(content[match.start() : index + 1])
                    break
        else:
            raise AssertionError("unterminated provisioner block")
    return blocks


def amazon_ebs_blocks(content: str) -> list[str]:
    blocks: list[str] = []
    for match in SOURCE_HEADER.finditer(content):
        depth = 0
        quoted = False
        escaped = False
        for index in range(match.end() - 1, len(content)):
            character = content[index]
            if quoted:
                if escaped:
                    escaped = False
                elif character == "\\":
                    escaped = True
                elif character == '"':
                    quoted = False
                continue
            if character == '"':
                quoted = True
            elif character == "{":
                depth += 1
            elif character == "}":
                depth -= 1
                if depth == 0:
                    blocks.append(content[match.start() : index + 1])
                    break
        else:
            raise AssertionError("unterminated amazon-ebs source block")
    return blocks


class PackerTemplateSecurityTests(unittest.TestCase):
    def test_all_amazon_ebs_sources_use_session_manager_without_inbound(self) -> None:
        # Builders are reached only through Session Manager: no public IP, the
        # stack's instance profile, and the stack's no-inbound security group,
        # never a Packer temporary security group (which opens port 22).
        required = (
            "associate_public_ip_address = false",
            'ssh_interface               = "session_manager"',
            'iam_instance_profile        = "ami-build-ssm"',
            '"group-name" = "ami-build-builder"',
        )
        forbidden = (
            "temporary_security_group_source",
            "security_group_id ",
            "security_group_ids",
            "temporary_iam_instance_profile",
            "ssh_interface = \"public",
        )
        templates = sorted(REPOSITORY.glob("vm-images/aws/*/build/*/main.pkr.hcl"))
        self.assertTrue(templates)
        for template in templates:
            blocks = amazon_ebs_blocks(strip_hcl_comments(template.read_text()))
            self.assertTrue(blocks, f"{template} has no amazon-ebs source")
            for position, block in enumerate(blocks):
                with self.subTest(template=template, source=position):
                    for line in required:
                        self.assertEqual(block.count(line), 1, line)
                    for setting in forbidden:
                        self.assertNotIn(setting, block)
                    self.assertIsNone(
                        WORLD_OPEN_CIDR.search(block),
                        "amazon-ebs source contains a world-open SSH CIDR",
                    )
                    self.assertIsNone(
                        AMI_DESCRIPTION.search(block),
                        "ami_description triggers denied ModifyImageAttribute",
                    )

    def test_template_ami_name_prefix_matches_target_policy(self) -> None:
        for template in sorted(REPOSITORY.glob("vm-images/aws/*/build/*/main.pkr.hcl")):
            family = template.parents[2].name
            for position, block in enumerate(
                amazon_ebs_blocks(template.read_text())
            ):
                with self.subTest(template=template, family=family, source=position):
                    assignments = AMI_NAME.findall(block)
                    self.assertEqual(len(assignments), 1)
                    self.assertIn(
                        'format("%s-packer-%s-%s", var.family, var.os_name',
                        assignments[0],
                    )

    def test_templates_take_build_subnet_from_harness(self) -> None:
        # The build account has no default VPC; packer-build-and-test.sh
        # passes the Purpose=ami-build subnet. Its SCP denies launches
        # that do not require IMDSv2.
        expected = (
            "subnet_id                   = var.subnet_id",
            'http_tokens                 = "required"',
        )
        for template in sorted(REPOSITORY.glob("vm-images/aws/*/build/*/main.pkr.hcl")):
            content = template.read_text()
            with self.subTest(template=template):
                self.assertIn('variable "subnet_id"', content)
                self.assertNotIn("kms_key_id", content)
                for block in amazon_ebs_blocks(content):
                    for line in expected:
                        self.assertEqual(block.count(line), 1, line)

    def test_templates_take_no_credentials_and_never_share(self) -> None:
        # Credentials come only from the SDK chain the harness checks against
        # the build account; images and snapshots stay in that account.
        forbidden_settings = FORBIDDEN_SOURCE_SETTINGS
        for template in sorted(REPOSITORY.glob("vm-images/aws/*/build/*/main.pkr.hcl")):
            content = template.read_text()
            with self.subTest(template=template):
                for variable in ("aws_access_key", "aws_secret_key", "aws_session_token"):
                    self.assertNotIn(f'variable "{variable}"', content)
                for block in amazon_ebs_blocks(content):
                    self.assertIsNone(forbidden_settings.search(block))

    def test_forbidden_source_settings_are_detected(self) -> None:
        for setting in (
            'shared_credentials_file = "~/.aws/credentials"',
            "vault_aws_engine {",
            'profile = "other"',
            'ami_users = ["111122223333"]',
            'snapshot_groups = ["all"]',
        ):
            with self.subTest(setting=setting):
                self.assertIsNotNone(FORBIDDEN_SOURCE_SETTINGS.search(f"  {setting}\n"))
        self.assertIsNone(
            FORBIDDEN_SOURCE_SETTINGS.search('    http_tokens                 = "required"\n')
        )

    def test_image_capture_cleanup_is_the_last_provisioner(self) -> None:
        # Build-instance SSM agent logs/registration, cloud-init instance data
        # and the machine ID must not ship in the image.
        for template in sorted(REPOSITORY.glob("vm-images/aws/*/build/*/main.pkr.hcl")):
            blocks = provisioner_blocks(template.read_text())
            with self.subTest(template=template):
                self.assertTrue(blocks)
                self.assertEqual(
                    PROVISIONER_SCRIPT.findall(blocks[-1]),
                    ["../../../../common/scripts/system_prepare_image_capture.sh"],
                )

    def test_provisioner_parser_ignores_comments(self) -> None:
        content = (
            'build {\n'
            '  provisioner "shell" {\n'
            '    # script = "../../../../common/scripts/system_prepare_image_capture.sh"\n'
            '    script = "other.sh"\n'
            '  }\n'
            '  # provisioner "shell" { script = "x.sh" }\n'
            '}\n'
        )
        blocks = provisioner_blocks(content)
        self.assertEqual(len(blocks), 1)
        self.assertEqual(PROVISIONER_SCRIPT.findall(blocks[-1]), ["other.sh"])

    def test_sources_clear_packer_authorized_keys(self) -> None:
        for template in sorted(REPOSITORY.glob("vm-images/aws/*/build/*/main.pkr.hcl")):
            with self.subTest(template=template):
                for block in amazon_ebs_blocks(strip_hcl_comments(template.read_text())):
                    self.assertEqual(
                        re.findall(r"(?m)^\s*ssh_clear_authorized_keys\s*=\s*(\S+)", block),
                        ["true"],
                    )

    def test_images_bake_no_ssh_key_pairs(self) -> None:
        # A key generated at build time is shared by every instance. Only the
        # first-boot unit installer may call ssh-keygen, and nothing may carry
        # private-key material.
        allowed = {"vm-images/common/scripts/system_add_dbadmin_ssh_keygen.sh"}
        keygen_call = re.compile(r"(?<![\w-])ssh-keygen\s+-")
        private_key = re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")
        sources = [
            *REPOSITORY.glob("vm-images/common/scripts/*.sh"),
            *REPOSITORY.glob("vm-images/aws/*/build/*/scripts/*.sh"),
            *REPOSITORY.glob("vm-images/aws/*/build/*/main.pkr.hcl"),
            *REPOSITORY.glob("vm-images/scripts/*"),
        ]
        self.assertTrue(sources)
        for source in sorted(sources):
            relative = str(source.relative_to(REPOSITORY))
            content = source.read_text()
            with self.subTest(source=relative):
                self.assertIsNone(private_key.search(content))
                if relative not in allowed:
                    self.assertIsNone(keygen_call.search(content))
                self.assertNotIn("GENERATE_SSH_KEYPAIR", content)

    def test_dbadmin_templates_install_first_boot_keys_before_cleanup(self) -> None:
        for template in sorted(REPOSITORY.glob("vm-images/aws/*/build/*/main.pkr.hcl")):
            scripts = [
                found[0]
                for found in (
                    PROVISIONER_SCRIPT.findall(block)
                    for block in provisioner_blocks(template.read_text())
                )
                if found
            ]
            if not any(path.endswith("dbadmin_configure_environment.sh") for path in scripts):
                continue
            with self.subTest(template=template):
                self.assertEqual(
                    scripts[-2:],
                    [
                        "../../../../common/scripts/system_add_dbadmin_ssh_keygen.sh",
                        "../../../../common/scripts/system_prepare_image_capture.sh",
                    ],
                )

    def test_os_default_users_are_checked_for_baked_keys(self) -> None:
        defaults = {"ubuntu": "ubuntu", "rocky": "rocky", "al2023": "ec2-user"}
        for goss in sorted(REPOSITORY.glob("vm-images/aws/*/build/*/tests/goss.yaml")):
            os_name = goss.parents[1].name
            user = next(value for key, value in defaults.items() if os_name.startswith(key))
            with self.subTest(target=os_name):
                self.assertIn(
                    f"  /home/{user}/.ssh/id_ed25519:\n    exists: false\n",
                    goss.read_text(),
                )

    def test_sources_without_a_preinstalled_ssm_agent_bootstrap_it(self) -> None:
        # Rocky Linux AMIs (owner 792107900819) ship without the SSM agent;
        # Session Manager is the only way in, so their user data installs it.
        # Canonical (snap) and Amazon Linux AMIs include it.
        agent_included = {"099720109477", "137112412989", "self"}
        for template in sorted(REPOSITORY.glob("vm-images/aws/*/build/*/main.pkr.hcl")):
            content = strip_hcl_comments(template.read_text())
            owners = set(re.findall(r'owners\s*=\s*\["([^"]+)"\]', content))
            with self.subTest(template=template):
                self.assertTrue(owners)
                if owners <= agent_included:
                    continue
                self.assertEqual(owners, {"792107900819"}, "unknown AMI publisher")
                self.assertIn(
                    'user_data_file              = "../../../../common/cloud-init/ssm-agent-rpm.yaml"',
                    content,
                )
                self.assertTrue(
                    (template.parent / "tests/goss.yaml").read_text().count("amazon-ssm-agent:")
                )
                # Packer opens the SSM session once, after pause_before_ssm;
                # the first-boot install must have registered the agent by then.
                self.assertIn('pause_before_ssm            = "2m"', content)

    def test_ssm_agent_bootstrap_installs_enables_and_starts_it(self) -> None:
        import yaml

        bootstrap = yaml.safe_load(
            (REPOSITORY / "vm-images/common/cloud-init/ssm-agent-rpm.yaml").read_text()
        )
        script = bootstrap["runcmd"][0][-1]
        self.assertIn(
            "https://s3.us-west-2.amazonaws.com/amazon-ssm-us-west-2/latest/linux_amd64/amazon-ssm-agent.rpm",
            script,
        )
        self.assertIn("systemctl enable --now amazon-ssm-agent", script)
        self.assertIn("exit 1", script)

if __name__ == "__main__":
    unittest.main()
