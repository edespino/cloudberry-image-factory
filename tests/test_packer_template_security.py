from __future__ import annotations

from pathlib import Path
import re
import unittest


REPOSITORY = Path(__file__).resolve().parents[1]
BUILD_ROOT = REPOSITORY / "vm-images/aws/cloudberry/build"
SOURCE_HEADER = re.compile(r'\bsource\s+"amazon-ebs"\s+"[^"]+"\s*\{')
PUBLIC_IP_SETTING = re.compile(
    r"(?m)^\s*temporary_security_group_source_public_ip\s*=\s*([^\s#]+)"
)
AMI_DESCRIPTION = re.compile(r"(?m)^\s*ami_description\s*=")
AMI_NAME = re.compile(r"(?m)^\s*ami_name\s*=\s*(.+)$")
WORLD_OPEN_CIDR = re.compile(r'(?<![0-9A-Fa-f:.])(?:0\.0\.0\.0/0|::/0)(?![0-9])')


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
    def test_all_amazon_ebs_sources_restrict_temporary_sg_to_public_ip(self) -> None:
        templates = sorted(BUILD_ROOT.glob("*/main.pkr.hcl"))
        self.assertTrue(templates)
        for template in templates:
            blocks = amazon_ebs_blocks(template.read_text())
            self.assertTrue(blocks, f"{template} has no amazon-ebs source")
            for position, block in enumerate(blocks):
                with self.subTest(template=template, source=position):
                    settings = PUBLIC_IP_SETTING.findall(block)
                    self.assertEqual(
                        settings,
                        ["true"],
                        "setting must occur exactly once and be literal true",
                    )
                    self.assertIsNone(
                        WORLD_OPEN_CIDR.search(block),
                        "amazon-ebs source contains a world-open SSH CIDR",
                    )
                    self.assertIsNone(
                        AMI_DESCRIPTION.search(block),
                        "ami_description triggers denied ModifyImageAttribute",
                    )

    def test_template_ami_name_prefix_matches_target_policy(self) -> None:
        for template in sorted(BUILD_ROOT.glob("*/main.pkr.hcl")):
            target = template.parent.name
            if target == "al2023-synxdb-cloud":
                prefix = "synx-cloud-packer-"
            elif target == "al2023-synxdb-elastic":
                prefix = "synx-elastic-packer-"
            elif target.endswith("-synxdb-cloud"):
                prefix = "synxdb-cloud-packer-"
            else:
                prefix = "cloudberry-packer-"
            for position, block in enumerate(
                amazon_ebs_blocks(template.read_text())
            ):
                with self.subTest(template=template, source=position):
                    assignments = AMI_NAME.findall(block)
                    self.assertEqual(len(assignments), 1)
                    self.assertIn(f'"{prefix}', assignments[0])


if __name__ == "__main__":
    unittest.main()
