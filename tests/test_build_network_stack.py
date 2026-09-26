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
                # Drata treats 22 and 3389 as administrative in any protocol.
                if str(entry["Protocol"]) in ("6", "17"):
                    low, high = entry["PortRange"]["From"], entry["PortRange"]["To"]
                    for port in (22, 3389):
                        self.assertFalse(low <= port <= high, f"covers {port}")
        # The ranges still cover every other tcp and udp port (ephemeral return
        # traffic).
        for protocol in ("6", "17"):
            covered = set()
            for entry in entries:
                if str(entry["Protocol"]) == protocol:
                    covered.update(range(entry["PortRange"]["From"], entry["PortRange"]["To"] + 1))
            with self.subTest(protocol=protocol):
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

    def test_every_lambda_has_an_errors_alarm_with_actions(self) -> None:
        # Drata test 300: each function needs an alarm on AWS/Lambda Errors
        # whose actions publish to a subscribed SNS topic.
        functions = resources(self.stack, "AWS::Lambda::Function")
        self.assertTrue(functions)
        alarmed = {}
        for body in resources(self.stack, "AWS::CloudWatch::Alarm").values():
            alarm = body["Properties"]
            if (alarm.get("Namespace"), alarm.get("MetricName")) != ("AWS/Lambda", "Errors"):
                continue
            for dimension in alarm.get("Dimensions", []):
                if dimension["Name"] == "FunctionName":
                    alarmed[dimension["Value"].get("!Ref")] = body
        for name in functions:
            with self.subTest(function=name):
                self.assertIn(name, alarmed, "no AWS/Lambda Errors alarm")
                self.assertTrue(alarmed[name]["Properties"].get("AlarmActions"), "alarm has no AlarmActions")
                self.assertIsNone(alarmed[name].get("Condition"), "alarm must always exist")
        self.assertEqual(
            self.stack["Parameters"]["AlertTopicArn"]["Default"],
            "arn:aws:sns:us-west-2:260369602265:synx-engineering-alerts",
        )

    def test_environment_tags_use_allowed_values(self) -> None:
        for name, body in self.stack["Resources"].items():
            tags = body.get("Properties", {}).get("Tags", [])
            for tag in tags:
                if tag.get("Key") == "Environment":
                    with self.subTest(resource=name):
                        self.assertIn(tag["Value"], ALLOWED_ENVIRONMENTS)



# ---------------------------------------------------------------------------
# Runtime tests of the DefaultNetworkControls function, executed against fake
# EC2 / SSM / cfnresponse modules.

import copy  # noqa: E402
import json  # noqa: E402
import sys  # noqa: E402
import types  # noqa: E402

VPC = "vpc-0123456789abcdef0"
PRIOR_ACL = [
    {"RuleNumber": 100, "Protocol": "-1", "RuleAction": "allow", "Egress": False, "CidrBlock": "0.0.0.0/0"},
    {"RuleNumber": 32767, "Protocol": "-1", "RuleAction": "deny", "Egress": False, "CidrBlock": "0.0.0.0/0"},
    {"RuleNumber": 100, "Protocol": "-1", "RuleAction": "allow", "Egress": True, "CidrBlock": "0.0.0.0/0"},
    {"RuleNumber": 32767, "Protocol": "-1", "RuleAction": "deny", "Egress": True, "CidrBlock": "0.0.0.0/0"},
]
PRIOR_INGRESS = [{"IpProtocol": "-1", "UserIdGroupPairs": [{"GroupId": "sg-default", "UserId": "260369602265"}],
                  "IpRanges": [], "Ipv6Ranges": [], "PrefixListIds": []}]
PRIOR_EGRESS = [{"IpProtocol": "-1", "IpRanges": [{"CidrIp": "0.0.0.0/0"}],
                 "UserIdGroupPairs": [], "Ipv6Ranges": [], "PrefixListIds": []}]


def _by_rule(entries):
    return sorted(entries, key=lambda entry: (entry["Egress"], entry["RuleNumber"]))


class _ParameterNotFound(Exception):
    pass


class FakeEc2:
    def __init__(self, acl=None, ingress=None, egress=None, fail_on=None):
        self.acl = copy.deepcopy(PRIOR_ACL if acl is None else acl)
        self.ingress = copy.deepcopy(PRIOR_INGRESS if ingress is None else ingress)
        self.egress = copy.deepcopy(PRIOR_EGRESS if egress is None else egress)
        self.fail_on = fail_on

    def _check(self, name):
        if self.fail_on == name:
            raise RuntimeError(f"{name} failed")

    def describe_network_acls(self, Filters):
        self._check("describe_network_acls")
        return {"NetworkAcls": [{"NetworkAclId": "acl-default", "Entries": copy.deepcopy(self.acl)}]}

    def describe_security_groups(self, Filters):
        return {"SecurityGroups": [{"GroupId": "sg-default", "IpPermissions": copy.deepcopy(self.ingress),
                                    "IpPermissionsEgress": copy.deepcopy(self.egress)}]}

    def delete_network_acl_entry(self, NetworkAclId, RuleNumber, Egress):
        before = len(self.acl)
        self.acl = [e for e in self.acl if not (e["RuleNumber"] == RuleNumber and e["Egress"] == Egress)]
        assert len(self.acl) == before - 1, "deleted a missing entry"

    def create_network_acl_entry(self, NetworkAclId, Egress, **entry):
        self._check("create_network_acl_entry")
        assert not any(e["RuleNumber"] == entry["RuleNumber"] and e["Egress"] == Egress for e in self.acl)
        self.acl.append({"Egress": Egress, **entry})

    def revoke_security_group_ingress(self, GroupId, IpPermissions):
        assert IpPermissions == self.ingress
        self.ingress = []

    def revoke_security_group_egress(self, GroupId, IpPermissions):
        assert IpPermissions == self.egress
        self.egress = []

    def authorize_security_group_ingress(self, GroupId, IpPermissions):
        self.ingress = copy.deepcopy(IpPermissions)

    def authorize_security_group_egress(self, GroupId, IpPermissions):
        self.egress = copy.deepcopy(IpPermissions)

    def inbound(self):
        return sorted(
            (e["RuleNumber"], e["Protocol"], e.get("PortRange", {}).get("From"), e.get("PortRange", {}).get("To"))
            for e in self.acl if not e["Egress"] and e["RuleNumber"] < 32767
        )


class FakeSsm:
    exceptions = types.SimpleNamespace(ParameterNotFound=_ParameterNotFound)

    def __init__(self):
        self.parameters = {}

    def get_parameter(self, Name):
        if Name not in self.parameters:
            raise _ParameterNotFound(Name)
        return {"Parameter": {"Value": self.parameters[Name]}}

    def put_parameter(self, Name, Value, Type, Overwrite, Tier="Standard"):
        assert not Overwrite and Name not in self.parameters
        self.parameters[Name] = Value

    def delete_parameter(self, Name):
        del self.parameters[Name]


class DefaultNetworkControlsFunctionTests(unittest.TestCase):
    def setUp(self):
        self.responses = []
        self.ec2 = FakeEc2()
        self.ssm = FakeSsm()
        self.module = self._load()

    def _load(self, ec2=None):
        clients = {"ec2": ec2 or self.ec2, "ssm": self.ssm}
        boto3 = types.ModuleType("boto3")
        boto3.client = lambda name: clients[name]
        cfnresponse = types.ModuleType("cfnresponse")
        cfnresponse.SUCCESS, cfnresponse.FAILED = "SUCCESS", "FAILED"

        def send(event, context, status, data, physicalResourceId=None, reason=None):
            self.responses.append({"status": status, "data": data, "id": physicalResourceId, "reason": reason})

        cfnresponse.send = send
        code = load_stack()["Resources"]["DefaultNetworkControlsFunction"]["Properties"]["Code"]["ZipFile"]
        saved = {name: sys.modules.get(name) for name in ("boto3", "cfnresponse")}
        sys.modules.update({"boto3": boto3, "cfnresponse": cfnresponse})
        try:
            namespace: dict = {}
            exec(compile(code, "default_network_controls", "exec"), namespace)
        finally:
            for name, module in saved.items():
                if module is None:
                    sys.modules.pop(name, None)
                else:
                    sys.modules[name] = module
        return namespace

    def _event(self, request, physical_id=None, **properties):
        event = {"RequestType": request, "ResourceProperties": {"VpcId": VPC, **properties}}
        if physical_id:
            event["PhysicalResourceId"] = physical_id
        self.module["handler"](event, None)
        return self.responses[-1]

    def _wanted(self):
        return sorted(lambda_inbound_entries(load_stack()))

    def test_create_applies_rules_and_saves_prior_defaults(self):
        response = self._event("Create")

        self.assertEqual(response["status"], "SUCCESS", response["reason"])
        self.assertEqual(response["id"], f"default-network-controls-{VPC}")
        self.assertEqual(self.ec2.inbound(), self._wanted())
        self.assertEqual((self.ec2.ingress, self.ec2.egress), ([], []))
        egress = [e for e in self.ec2.acl if e["Egress"]]
        self.assertEqual(egress, [e for e in PRIOR_ACL if e["Egress"]])
        saved = json.loads(self.ssm.parameters[f"/ami-build/default-network-controls/{VPC}"])
        self.assertEqual(saved["ingress"], PRIOR_INGRESS)
        self.assertEqual(saved["egress"], PRIOR_EGRESS)

    def test_repeated_updates_are_idempotent(self):
        self._event("Create")
        saved = dict(self.ssm.parameters)
        for nat in ("true", "false", "true"):
            response = self._event("Update", f"default-network-controls-{VPC}", NatEnabled=nat)
            self.assertEqual(response["status"], "SUCCESS", response["reason"])
            self.assertEqual(self.ec2.inbound(), self._wanted())
            self.assertEqual((self.ec2.ingress, self.ec2.egress), ([], []))
        self.assertEqual(self.ssm.parameters, saved)

    def test_update_corrects_drift(self):
        self._event("Create")
        self.ec2.acl.append({"RuleNumber": 90, "Protocol": "6", "RuleAction": "allow", "Egress": False,
                             "CidrBlock": "0.0.0.0/0", "PortRange": {"From": 22, "To": 22}})
        self.ec2.ingress = copy.deepcopy(PRIOR_INGRESS)

        self._event("Update", f"default-network-controls-{VPC}", NatEnabled="false")

        self.assertEqual(self.ec2.inbound(), self._wanted())
        self.assertEqual(self.ec2.ingress, [])

    def test_delete_restores_the_prior_defaults_exactly(self):
        prior_acl = copy.deepcopy(self.ec2.acl)
        self._event("Create")

        response = self._event("Delete", f"default-network-controls-{VPC}")

        self.assertEqual(response["status"], "SUCCESS", response["reason"])
        self.assertEqual(_by_rule(self.ec2.acl), _by_rule(prior_acl))
        self.assertEqual(self.ec2.ingress, PRIOR_INGRESS)
        self.assertEqual(self.ec2.egress, PRIOR_EGRESS)
        self.assertEqual(self.ssm.parameters, {})

    def test_partial_prior_state_is_restored_too(self):
        self.ec2 = FakeEc2(ingress=[], acl=PRIOR_ACL + [
            {"RuleNumber": 90, "Protocol": "6", "RuleAction": "deny", "Egress": False,
             "CidrBlock": "0.0.0.0/0", "PortRange": {"From": 22, "To": 22}}])
        self.module = self._load(self.ec2)
        prior_acl = copy.deepcopy(self.ec2.acl)
        self._event("Create")
        self._event("Delete", f"default-network-controls-{VPC}")
        self.assertEqual(_by_rule(self.ec2.acl), _by_rule(prior_acl))
        self.assertEqual(self.ec2.ingress, [])

    def test_create_retry_never_overwrites_the_saved_prior_state(self):
        self._event("Create")
        saved = dict(self.ssm.parameters)
        self._event("Create")
        self.assertEqual(self.ssm.parameters, saved)

    def test_delete_of_a_foreign_physical_id_or_without_saved_state_is_a_no_op(self):
        before = copy.deepcopy(self.ec2.acl)
        for physical_id in ("something-else", f"default-network-controls-{VPC}"):
            response = self._event("Delete", physical_id)
            self.assertEqual(response["status"], "SUCCESS")
            self.assertEqual(self.ec2.acl, before)

    def test_failures_are_reported_to_cloudformation(self):
        self.ec2 = FakeEc2(fail_on="create_network_acl_entry")
        self.module = self._load(self.ec2)
        response = self._event("Create")
        self.assertEqual(response["status"], "FAILED")
        self.assertIn("create_network_acl_entry failed", response["reason"])
        # A rollback Delete after the failed Create restores the saved state.
        self.ec2.fail_on = None
        self._event("Delete", response["id"])
        self.assertEqual(_by_rule(self.ec2.acl), _by_rule(PRIOR_ACL))

    def test_toggling_nat_changes_the_custom_resource_properties(self):
        properties = load_stack()["Resources"]["DefaultNetworkControls"]["Properties"]
        self.assertEqual(properties["NatEnabled"], {"!Ref": "NatEnabled"})


if __name__ == "__main__":
    unittest.main()
