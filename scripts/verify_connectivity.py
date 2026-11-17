#!/usr/bin/env python3
"""Verify the hub-and-spoke lab after `terraform apply`.

Checks:
  1. All Transit Gateway attachments (hub and every spoke) are in the "available" state.
  2. The VPC route tables contain the expected routes through the Transit Gateway.
  3. Transit Gateway segmentation: each attachment is associated with the right route table
     and the spokes route table holds the expected routes (blackholes or propagated routes).
  4. VPC Flow Logs are active on every VPC.
  5. (Optional) Centralized egress: every spoke test instance, reached through SSM, must
     leave to the Internet with the public IP of the hub NAT Gateway.
  6. (Optional) Spoke isolation: a ping between two spoke instances must be blocked, or
     succeed when allow_spoke_to_spoke is true.
     
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
    expected = []
    for name, spoke in out["spokes"].items():
        rtb = spoke["private_route_table_id"]
        expected.append((f"spoke {name} -> hub", rtb, out["hub_vpc_cidr"]))
        expected.append((f"hub -> spoke {name}", out["hub_public_route_table_id"], spoke["cidr"]))
        if out["nat_enabled"]:
            expected.append((f"spoke {name} default route -> TGW", rtb, "0.0.0.0/0"))
    for label, route_table_id, cidr in expected:
        ok = has_tgw_route(ec2, route_table_id, cidr, tgw_id)
        report.add(f"Route {label}", ok, f"{cidr} via {tgw_id} in {route_table_id}")


def tgw_routes(ec2, route_table_id):
    """Routes of a Transit Gateway route table as {cidr: (state, type)}."""
    response = ec2.search_transit_gateway_routes(
        TransitGatewayRouteTableId=route_table_id,
        Filters=[{"Name": "state", "Values": ["active", "blackhole"]}],
    )
    return {
        route["DestinationCidrBlock"]: (route["State"], route["Type"])
        for route in response["Routes"]
    }


def associated_attachments(ec2, route_table_id):
    """IDs of the attachments associated with a Transit Gateway route table."""
    response = ec2.get_transit_gateway_route_table_associations(
        TransitGatewayRouteTableId=route_table_id
    )
    return {
        association["TransitGatewayAttachmentId"]
        for association in response["Associations"]
        if association["State"] == "associated"
    }


def check_tgw_segmentation(ec2, report, out):
    hub_rt = out["tgw_hub_route_table_id"]
    spokes_rt = out["tgw_spokes_route_table_id"]
    spokes = out["spokes"]

    # 1. Each attachment is associated with exactly the route table it should use
    report.add(
        "TGW hub attachment -> hub route table",
        associated_attachments(ec2, hub_rt) == {out["hub_attachment_id"]},
        f"{out['hub_attachment_id']} in {hub_rt}",
    )
    spoke_attachments = {spoke["attachment_id"] for spoke in spokes.values()}
    report.add(
        "TGW spoke attachments -> spokes route table",
        associated_attachments(ec2, spokes_rt) == spoke_attachments,
        f"{len(spoke_attachments)} attachments in {spokes_rt}",
    )

    # 2. Routes of the spokes route table: the hub is reachable, other spokes depend on the policy
    routes = tgw_routes(ec2, spokes_rt)
    hub_state = routes.get(out["hub_vpc_cidr"], ("missing", ""))[0]
    report.add("TGW spokes table has the hub route", hub_state == "active", f"{out['hub_vpc_cidr']}: {hub_state}")

    wanted = "active" if out["allow_spoke_to_spoke"] else "blackhole"
    for name, spoke in spokes.items():
        state = routes.get(spoke["cidr"], ("missing", ""))[0]
        report.add(
            f"TGW spokes table, route to spoke {name}",
            state == wanted,
            f"{spoke['cidr']}: {state} (expected {wanted})",
        )

    # 3. The hub route table must know every spoke (return traffic)
    hub_routes = tgw_routes(ec2, hub_rt)
    for name, spoke in spokes.items():
        state = hub_routes.get(spoke["cidr"], ("missing", ""))[0]
        report.add(f"TGW hub table, route to spoke {name}", state == "active", f"{spoke['cidr']}: {state}")
        
        
def check_flow_logs(ec2, report, vpc_ids):
    """Each VPC must have an active flow log that is not failing to deliver."""
    response = ec2.describe_flow_logs(Filters=[{"Name": "resource-id", "Values": vpc_ids}])
    by_vpc = {log["ResourceId"]: log for log in response["FlowLogs"]}
    for vpc_id in vpc_ids:
        log = by_vpc.get(vpc_id)
        ok = (
            log is not None
            and log["FlowLogStatus"] == "ACTIVE"
            and log.get("DeliverLogsStatus") != "FAILED"
        )
        detail = f"status={log['FlowLogStatus']}" if log else "no flow log found"
        report.add(f"Flow logs {vpc_id}", ok, detail)
     
        
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
    """Every spoke instance must exit to the Internet with the hub NAT public IP.

    Returns {spoke name: instance} for the instances that are online in SSM.
    """
    nat_ip = out.get("hub_nat_public_ip")
    instances = {
        name: spoke["test_instance_id"]
        for name, spoke in out["spokes"].items()
        if spoke.get("test_instance_id")
    }
    if not instances or not nat_ip:
        report.skip(
            "Centralized egress",
            "needs deploy_test_instance=true and enable_nat_gateway=true",
        )
        return {}
    online = {}
    for name, instance_id in instances.items():
        if not wait_for_ssm(ssm, instance_id):
            report.add(
                f"SSM registration spoke {name}",
                False,
                f"{instance_id} not online after {SSM_WAIT_SECONDS}s",
            )
            continue
        report.add(f"SSM registration spoke {name}", True, instance_id)
        online[name] = instance_id
        status, observed_ip = run_shell(
            ssm, instance_id, "curl -s --max-time 10 https://checkip.amazonaws.com"
        )
        report.add(
            f"Centralized egress spoke {name} via hub NAT",
            status == "Success" and observed_ip == nat_ip,
            f"exits as {observed_ip or 'n/a'}, NAT EIP is {nat_ip}",
        )
    return online


def check_isolation(ssm, report, out, online):
    """Ping between every ordered pair of spokes: blocked, unless allow_spoke_to_spoke."""
    allowed = out["allow_spoke_to_spoke"]
    if len(online) < 2:
        report.skip("Spoke isolation", "needs at least two online spoke test instances")
        return
    for source, instance_id in online.items():
        for target, spoke in out["spokes"].items():
            target_ip = spoke.get("test_instance_ip")
            if target == source or not target_ip:
                continue
            status, output = run_shell(ssm, instance_id, f"ping -c 3 -W 2 {target_ip}")
            if status == "Success":
                reachable = True
            elif "100% packet loss" in output:
                reachable = False
            else:
                report.add(f"Isolation {source} -> {target}", False, f"inconclusive: {status}")
                continue
            report.add(
                f"Isolation {source} -> {target}",
                reachable == allowed,
                f"ping {'works' if reachable else 'blocked'} (expected {'works' if allowed else 'blocked'})",
            )


def main():
    out = terraform_outputs()
    session = boto3.Session(region_name=out["region"])
    ec2 = session.client("ec2")
    ssm = session.client("ssm")

    report = Report()
    spokes = out["spokes"]
    attachment_ids = [out["hub_attachment_id"]] + [s["attachment_id"] for s in spokes.values()]
    vpc_ids = [out["hub_vpc_id"]] + [s["vpc_id"] for s in spokes.values()]

    check_attachments(ec2, report, attachment_ids)
    check_routes(ec2, report, out)
    check_tgw_segmentation(ec2, report, out)
    check_flow_logs(ec2, report, vpc_ids)
    online = check_egress(ssm, report, out)
    check_isolation(ssm, report, out, online)
    report.print()
    return 1 if report.failed else 0


if __name__ == "__main__":
    sys.exit(main())