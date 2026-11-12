#!/usr/bin/env python3
"""Verify the hub-and-spoke lab after `terraform apply`.

Checks:
  1. Both Transit Gateway attachments are in the "available" state.
  2. The VPC route tables contain the expected routes through the Transit Gateway.
  3. (Optional) Centralized egress: the spoke test instance, reached through SSM,
     must leave to the Internet with the public IP of the hub NAT Gateway.

Usage (from the repository root, with AWS credentials configured):
    pip install -r scripts/requirements.txt
    python scripts/verify_connectivity.py

Exit code is 0 when every executed check passes, 1 otherwise.
"""

import json
import subprocess
import sys
import time
from pathlib import Path

import boto3
from botocore.exceptions import ClientError

TF_DIR = Path(__file__).resolve().parent.parent / "cloud-infrastructure"
SSM_WAIT_SECONDS = 300
COMMAND_WAIT_SECONDS = 60


class Report:
    """Collects check results and prints them as a small table."""

    def __init__(self):
        self.rows = []

    def add(self, name, ok, detail=""):
        self.rows.append(("PASS" if ok else "FAIL", name, detail))

    def skip(self, name, detail=""):
        self.rows.append(("SKIP", name, detail))

    def print(self):
        width = max(len(name) for _, name, _ in self.rows)
        for status, name, detail in self.rows:
            print(f"[{status}] {name.ljust(width)}  {detail}")

    @property
    def failed(self):
        return any(status == "FAIL" for status, _, _ in self.rows)


def terraform_outputs():
    """Read the Terraform outputs of the lab as a plain dictionary."""
    result = subprocess.run(
        ["terraform", "output", "-json"],
        cwd=TF_DIR,
        capture_output=True,
        text=True,
        check=True,
    )
    outputs = {key: item["value"] for key, item in json.loads(result.stdout).items()}
    if not outputs:
        sys.exit("No Terraform outputs found. Run `terraform apply` first.")
    return outputs


def check_attachments(ec2, report, attachment_ids):
    response = ec2.describe_transit_gateway_vpc_attachments(
        TransitGatewayAttachmentIds=attachment_ids
    )
    for attachment in response["TransitGatewayVpcAttachments"]:
        report.add(
            f"TGW attachment {attachment['TransitGatewayAttachmentId']}",
            attachment["State"] == "available",
            f"state={attachment['State']}",
        )


def has_tgw_route(ec2, route_table_id, cidr, tgw_id):
    """True if the route table has an active route for `cidr` through the Transit Gateway."""
    tables = ec2.describe_route_tables(RouteTableIds=[route_table_id])["RouteTables"]
    return any(
        route.get("DestinationCidrBlock") == cidr
        and route.get("TransitGatewayId") == tgw_id
        and route.get("State") == "active"
        for table in tables
        for route in table["Routes"]
    )


def check_routes(ec2, report, out):
    tgw_id = out["tgw_id"]
    expected = [
        ("spoke -> hub", out["spoke_private_route_table_id"], out["hub_vpc_cidr"]),
        ("hub -> spoke", out["hub_public_route_table_id"], out["spoke_vpc_cidr"]),
    ]
    if out["nat_enabled"]:
        expected.append(
            ("spoke default route -> TGW", out["spoke_private_route_table_id"], "0.0.0.0/0")
        )
    for label, route_table_id, cidr in expected:
        ok = has_tgw_route(ec2, route_table_id, cidr, tgw_id)
        report.add(f"Route {label}", ok, f"{cidr} via {tgw_id} in {route_table_id}")


def wait_for_ssm(ssm, instance_id):
    """Wait until the instance is registered and online in SSM."""
    deadline = time.time() + SSM_WAIT_SECONDS
    while time.time() < deadline:
        info = ssm.describe_instance_information(
            Filters=[{"Key": "InstanceIds", "Values": [instance_id]}]
        )["InstanceInformationList"]
        if info and info[0]["PingStatus"] == "Online":
            return True
        time.sleep(10)
    return False


def run_shell(ssm, instance_id, command):
    """Run a shell command on the instance through SSM and return (status, stdout)."""
    command_id = ssm.send_command(
        InstanceIds=[instance_id],
        DocumentName="AWS-RunShellScript",
        Parameters={"commands": [command]},
    )["Command"]["CommandId"]
    deadline = time.time() + COMMAND_WAIT_SECONDS
    while time.time() < deadline:
        time.sleep(3)
        try:
            result = ssm.get_command_invocation(CommandId=command_id, InstanceId=instance_id)
        except ClientError as error:
            if error.response["Error"]["Code"] == "InvocationDoesNotExist":
                continue
            raise
        if result["Status"] in ("Success", "Failed", "Cancelled", "TimedOut"):
            return result["Status"], result["StandardOutputContent"].strip()
    return "TimedOut", ""


def check_egress(ssm, report, out):
    instance_id = out.get("spoke_test_instance_id")
    nat_ip = out.get("hub_nat_public_ip")
    if not instance_id or not nat_ip:
        report.skip(
            "Centralized egress",
            "needs deploy_test_instance=true and enable_nat_gateway=true",
        )
        return
    if not wait_for_ssm(ssm, instance_id):
        report.add("SSM registration", False, f"{instance_id} not online after {SSM_WAIT_SECONDS}s")
        return
    report.add("SSM registration", True, instance_id)
    status, observed_ip = run_shell(
        ssm, instance_id, "curl -s --max-time 10 https://checkip.amazonaws.com"
    )
    report.add(
        "Centralized egress via hub NAT",
        status == "Success" and observed_ip == nat_ip,
        f"spoke exits as {observed_ip or 'n/a'}, NAT EIP is {nat_ip}",
    )


def main():
    out = terraform_outputs()
    session = boto3.Session(region_name=out["region"])
    ec2 = session.client("ec2")
    ssm = session.client("ssm")

    report = Report()
    check_attachments(ec2, report, [out["hub_attachment_id"], out["spoke_attachment_id"]])
    check_routes(ec2, report, out)
    check_egress(ssm, report, out)
    report.print()
    return 1 if report.failed else 0


if __name__ == "__main__":
    sys.exit(main())