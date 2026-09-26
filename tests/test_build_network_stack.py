from __future__ import annotations

import ast
from pathlib import Path
import unittest

import yaml


REPOSITORY = Path(__file__).resolve().parents[1]
STACK = REPOSITORY / "infra/engineering-ami-build.cfn.yaml"
ALLOWED_ENVIRONMENTS = {"production", "staging", "development", "sandbox", "shared"}


class _CloudFormationLoader(yaml.SafeLoader):
    """Loads intrinsic functions (!Ref, !Sub, ...) as {"!Tag": value}."""


def _intrinsic(loader: yaml.SafeLoader, suffix: str, node: yaml.Node) -> object:
    if isinstance(node, yaml.ScalarNode):
        value: object = loader.construct_scalar(node)
    elif isinstance(node, yaml.SequenceNode):
        value = loader.construct_sequence(node, deep=True)
    else:
        value = loader.construct_mapping(node, deep=True)
    return {f"!{suffix}": value}


_CloudFormationLoader.add_multi_constructor("!", _intrinsic)


def load_stack() -> dict:
    return yaml.load(STACK.read_text(), Loader=_CloudFormationLoader)


def resources(stack: dict, resource_type: str) -> dict[str, dict]:
    return {
        name: body
        for name, body in stack["Resources"].items()
        if body["Type"] == resource_type
    }


def lambda_inbound_entries(stack: dict) -> list[tuple]:
    code = stack["Resources"]["DefaultNetworkControlsFunction"]["Properties"]["Code"]["ZipFile"]
    tree = ast.parse(code)
    for node in tree.body:
        if isinstance(node, ast.Assign) and node.targets[0].id == "INBOUND":
            return ast.literal_eval(node.value)
    raise AssertionError("INBOUND not found in the default-network-controls function")


class BuildNetworkStackTests(unittest.TestCase):
    def setUp(self) -> None:
        self.stack = load_stack()

    def _inbound_entries(self) -> list[dict]:
        return [
            body["Properties"]
            for body in resources(self.stack, "AWS::EC2::NetworkAclEntry").values()
            if body["Properties"]["Egress"] is False
        ]

    def test_no_inbound_allow_covers_ssh_or_rdp(self) -> None:
        # Drata test 227 ignores rule order: an allow from 0.0.0.0/0 that
        # covers 22 or 3389 fails even behind a deny.
        entries = self._inbound_entries()
        self.assertTrue(entries)
        for entry in entries:
            with self.subTest(rule=entry["RuleNumber"]):
                self.assertEqual(entry["RuleAction"], "allow")
                self.assertNotEqual(str(entry["Protocol"]), "-1", "no all-protocol allow")
                if str(entry["Protocol"]) == "6":
                    low, high = entry["PortRange"]["From"], entry["PortRange"]["To"]
                    for port in (22, 3389):
                        self.assertFalse(low <= port <= high, f"covers {port}")
        # The ranges still cover every other TCP port (ephemeral return traffic).
        covered = set()
        for entry in entries:
            if str(entry["Protocol"]) == "6":
                covered.update(range(entry["PortRange"]["From"], entry["PortRange"]["To"] + 1))
        self.assertEqual(set(range(0, 65536)) - covered, {22, 3389})

    def test_default_acl_gets_the_same_inbound_entries(self) -> None:
        stack_entries = sorted(
            (
                entry["RuleNumber"],
                str(entry["Protocol"]),
                entry.get("PortRange", {}).get("From"),
                entry.get("PortRange", {}).get("To"),
            )
            for entry in self._inbound_entries()
        )
        self.assertEqual(sorted(lambda_inbound_entries(self.stack)), stack_entries)

    def test_every_subnet_uses_the_build_acl(self) -> None:
        subnets = set(resources(self.stack, "AWS::EC2::Subnet"))
        associated = {
            body["Properties"]["SubnetId"]["!Ref"]
            for body in resources(self.stack, "AWS::EC2::SubnetNetworkAclAssociation").values()
        }
        self.assertEqual(associated, subnets)

    def test_nat_exists_only_while_enabled(self) -> None:
        stack_resources = self.stack["Resources"]
        for name in ("NatGateway", "NatElasticIp", "DefaultRoute"):
            with self.subTest(resource=name):
                self.assertEqual(stack_resources[name].get("Condition"), "NatOn")
        self.assertEqual(self.stack["Parameters"]["NatEnabled"]["Default"], "false")
        self.assertEqual(
            stack_resources["DefaultRoute"]["Properties"]["NatGatewayId"], {"!Ref": "NatGateway"}
        )

    def test_build_subnets_are_private(self) -> None:
        stack_resources = self.stack["Resources"]
        for name in ("SubnetA", "SubnetB", "NatSubnet"):
            with self.subTest(subnet=name):
                self.assertIs(stack_resources[name]["Properties"]["MapPublicIpOnLaunch"], False)
        # Only the NAT subnet's route table points at the internet gateway.
        igw_routes = [
            body["Properties"]["RouteTableId"]["!Ref"]
            for body in resources(self.stack, "AWS::EC2::Route").values()
            if "GatewayId" in body["Properties"]
        ]
        self.assertEqual(igw_routes, ["NatRouteTable"])

    def test_builder_security_group_has_no_inbound_rules(self) -> None:
        group = self.stack["Resources"]["BuilderSecurityGroup"]["Properties"]
        self.assertEqual(group["GroupName"], "ami-build-builder")
        self.assertNotIn("SecurityGroupIngress", group)
        self.assertFalse(resources(self.stack, "AWS::EC2::SecurityGroupIngress"))

    def test_builder_role_is_session_manager_only(self) -> None:
        role = self.stack["Resources"]["BuilderRole"]["Properties"]
        self.assertEqual(
            role["ManagedPolicyArns"],
            ["arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"],
        )
        self.assertNotIn("Policies", role)
        profile = self.stack["Resources"]["BuilderInstanceProfile"]["Properties"]
        self.assertEqual(profile["InstanceProfileName"], "ami-build-ssm")

    def test_environment_tags_use_allowed_values(self) -> None:
        for name, body in self.stack["Resources"].items():
            tags = body.get("Properties", {}).get("Tags", [])
            for tag in tags:
                if tag.get("Key") == "Environment":
                    with self.subTest(resource=name):
                        self.assertIn(tag["Value"], ALLOWED_ENVIRONMENTS)


if __name__ == "__main__":
    unittest.main()
