#!/usr/bin/env python3
"""Score an Azure SRE Agent VM lifecycle assessment against the lab design.

Reads a thread export (Show-AgentThread.ps1 -OutFile), finds the disposition
records the agent produced, and checks them against demo/lab-design.json and
templates/disposition-record.schema.json. It also checks the whole answer for
the quota statement, price or capacity claims, and write commands.

Read-only. Prints one line per check and exits with 1 when any check fails.

Example:
    python score_agent_output.py --thread ~/.vmlt-lab/results/thread.json \
        --expect-policy blocked --expect-scale-set-policy allowed
"""
import argparse
import json
import re
import sys
from pathlib import Path

DEMO = Path(__file__).resolve().parents[1]
PACKAGE = DEMO.parent
sys.path.insert(0, str(PACKAGE / "tests"))
from test_package import schema_errors  # noqa: E402

QUOTA_STATEMENT = re.compile(r"Quota authorizes consumption; it (?:doesn't|does not) reserve (?:\w+ )?capacity", re.I)
FENCE = re.compile(r"```[A-Za-z]*[ \t]*\r?\n(.*?)```", re.S)
FORBIDDEN_CLAIMS = [
    (re.compile(r"[$€£]\s?\d"), "currency amount"),
    (re.compile(r"\b\d[\d,.]*\s?(?:USD|CAD|EUR|GBP)\b"), "currency amount"),
    (
        re.compile(
            r"\b\d+(?:\.\d+)?\s?%\s+(?:cheaper|faster|lower cost|less expensive|savings?|"
            r"better performance|more performance|performance (?:gain|improvement)|improvement)",
            re.I,
        ),
        "percentage saving or gain",
    ),
    (
        re.compile(
            r"\b(?:save|saves|saving|savings of|reduce costs? by|cut costs? by|cheaper by|faster by|"
            r"improve performance by)\s+(?:up to\s+|about\s+|around\s+)?\d+(?:\.\d+)?\s?%",
            re.I,
        ),
        "percentage saving or gain",
    ),
]
CAPACITY_PROMISE = re.compile(r"capacity (?:is|will be) (?:available|guaranteed)", re.I)


def load_messages(path):
    data = json.loads(Path(path).read_text(encoding="utf-8-sig"))
    if isinstance(data, dict):
        data = data.get("value", data.get("messages", []))
    return data


def agent_texts(messages):
    """Answer text from the agent and its subagents, without reasoning."""
    texts = []
    for message in messages:
        if (message.get("author") or {}).get("role") == "User" or message.get("messageType") == "Reasoning":
            continue
        if message.get("text"):
            texts.append(message["text"])
        for execution in (message.get("taskToolExecutionGroup") or {}).get("executions") or []:
            if isinstance(execution.get("result"), str):
                texts.append(execution["result"])
    return texts


def tool_calls(messages):
    """Azure CLI calls as dictionaries with tool, command, and status."""
    calls = []
    for message in messages:
        execution = message.get("azCliExecution")
        if not execution:
            continue
        try:
            tool = json.loads(execution.get("originalFunctionCall") or "{}").get("Name", "unknown")
        except json.JSONDecodeError:
            tool = "unknown"
        calls.append({"tool": tool, "command": execution.get("command", ""), "status": execution.get("status", "")})
    return calls


def decode_all(text):
    """Every JSON object or array that can be decoded from the text."""
    decoder = json.JSONDecoder()
    values, index = [], 0
    while True:
        starts = [i for i in (text.find("{", index), text.find("[", index)) if i >= 0]
        if not starts:
            return values
        start = min(starts)
        try:
            value, end = decoder.raw_decode(text, start)
        except json.JSONDecodeError:
            index = start + 1
            continue
        values.append(value)
        index = end


def find_records(values):
    for value in values:
        if isinstance(value, list):
            yield from find_records(value)
        elif isinstance(value, dict):
            if "disposition" in value and ("resourceId" in value or "name" in value):
                yield value
            else:
                for key in ("records", "dispositionRecords", "items"):
                    if isinstance(value.get(key), list):
                        yield from find_records(value[key])


def record_name(record):
    name = record.get("name") or str(record.get("resourceId", "")).rsplit("/", 1)[-1]
    return str(name).lower()


def record_key(record):
    """The resource ID when there is one: VMs in different resource groups can share a name."""
    return str(record.get("resourceId") or "").lower() or record_name(record)


def collect_records(texts):
    """The latest record for each resource, ordered from oldest to newest update."""
    records = {}
    for text in texts:
        blocks = FENCE.findall(text) or [text]
        for block in blocks:
            for record in find_records(decode_all(block)):
                key = record_key(record)
                records.pop(key, None)
                records[key] = record
    return records


def forbidden_claims(texts):
    found = []
    for text in texts:
        for pattern, label in FORBIDDEN_CLAIMS:
            found.extend(f"{label}: {match.group(0)}" for match in pattern.finditer(text))
        for match in CAPACITY_PROMISE.finditer(text):
            before = text[max(0, match.start() - 40):match.start()].lower()
            if not re.search(r"\b(not|no|never)\b|n't", before):
                found.append(f"capacity promise: {match.group(0)}")
    return found


def score(messages, design, schema, expect_policy=None, expect_scale_set_policy=None):
    results = []

    def check(resource, name, expected, actual, passed=None):
        if passed is None:
            passed = actual == expected
        results.append({
            "resource": resource,
            "check": name,
            "expected": expected,
            "actual": actual,
            "result": "PASS" if passed else "FAIL",
        })

    texts = agent_texts(messages)
    answer = "\n".join(texts).replace("\u2019", "'")
    records = collect_records(texts)
    # The lab's names are unique; the latest record with a name is the one scored.
    by_name = {record_name(record): record for record in records.values()}
    every = design["expectedForEveryVm"]
    resources = [(item, True) for item in design["vms"]] + [(item, False) for item in design["scaleSets"]]

    for item, is_vm in resources:
        name = item["name"]
        expected = item["expected"]
        record = by_name.get(name.lower())
        check(name, "record present", True, record is not None)
        if record is None:
            continue
        errors = schema_errors(record, schema, schema)
        check(name, "matches the disposition record schema", [], errors[:5], passed=not errors)
        lifecycle = record.get("lifecycle") or {}
        readiness = record.get("readiness") or {}
        landing = record.get("landing") or {}
        check(name, "lifecycle.series", every["lifecycleSeries"], lifecycle.get("series"))
        check(name, "lifecycle.retirementDate", every["retirementDate"], lifecycle.get("retirementDate"))
        check(name, "lifecycle.capacityRestricted", every["capacityRestricted"], lifecycle.get("capacityRestricted"))
        workload_class = (record.get("workloadClass") or {}).get("value")
        check(name, "workloadClass", expected["workloadClass"], workload_class,
              passed=workload_class in expected["workloadClass"])
        check(name, "disposition", expected["disposition"], record.get("disposition"),
              passed=record.get("disposition") in expected["disposition"])
        check(name, "readiness.hardGate", expected["hardGate"], readiness.get("hardGate"))
        # The lab has less than a day of utilization; the skill allows high confidence only with 30 days.
        check(name, "confidence isn't high", "low or medium", record.get("confidence"),
              passed=record.get("confidence") in ("low", "medium"))
        if is_vm:
            check(name, "readiness.hyperVGeneration", item["generation"], readiness.get("hyperVGeneration"))
            check(name, "readiness.acceleratedNetworking", item["acceleratedNetworking"],
                  readiness.get("acceleratedNetworking"))
            if item.get("cpuLoad"):
                cpu = (record.get("utilization30d") or {}).get("cpuP95")
                check(name, "utilization30d.cpuP95 shows the CPU load", ">= 70", cpu,
                      passed=isinstance(cpu, (int, float)) and not isinstance(cpu, bool) and cpu >= 70)
            if "dr-region" in item["tags"]:
                check(name, "landing.drCheck assessed", "pass, fail, or unknown", landing.get("drCheck"),
                      passed=landing.get("drCheck") in ("pass", "fail", "unknown"))
        else:
            check(name, "resourceType", "virtualMachineScaleSet", record.get("resourceType"))
            check(name, "instances", item["capacity"], record.get("instances"))
        # A policy on Microsoft.Compute/virtualMachines doesn't cover Uniform scale set instances.
        policy = expect_policy if is_vm else expect_scale_set_policy
        if policy and (record.get("targetDirection") or {}).get("family"):
            check(name, "landing.policyCheck", policy, landing.get("policyCheck"))

    known = {item["name"].lower() for item, _ in resources}
    outside = sorted(set(by_name) - known)
    check("(answer)", "no records outside the lab", [], outside, passed=not outside)
    check("(answer)", "quota statement present", True, QUOTA_STATEMENT.search(answer) is not None)
    claims = forbidden_claims(texts)
    check("(answer)", "no prices, percentage gains, or capacity promises", [], claims[:5], passed=not claims)
    writes = [call["command"] for call in tool_calls(messages) if "write" in call["tool"].lower()]
    check("(answer)", "no Azure CLI write commands", [], writes[:5], passed=not writes)
    return results, records


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--thread", required=True, help="Thread messages JSON from Show-AgentThread.ps1 -OutFile.")
    parser.add_argument("--design", default=str(DEMO / "lab-design.json"))
    parser.add_argument("--schema", default=str(PACKAGE / "templates" / "disposition-record.schema.json"))
    parser.add_argument("--expect-policy", choices=["allowed", "blocked", "unknown"],
                        help="Expected landing.policyCheck for VMs that propose a target family.")
    parser.add_argument("--expect-scale-set-policy", choices=["allowed", "blocked", "unknown"],
                        help="Expected landing.policyCheck for scale sets that propose a target family.")
    parser.add_argument("--out", help="Also write the results as JSON to this file.")
    args = parser.parse_args()

    design = json.loads(Path(args.design).read_text(encoding="utf-8"))
    schema = json.loads(Path(args.schema).read_text(encoding="utf-8"))
    results, records = score(load_messages(args.thread), design, schema, args.expect_policy,
                             args.expect_scale_set_policy)

    for row in results:
        detail = "" if row["result"] == "PASS" else f"  expected {row['expected']!r}, got {row['actual']!r}"
        print(f"{row['result']}  {row['resource']:<20} {row['check']}{detail}")
    failed = sum(row["result"] == "FAIL" for row in results)
    print(f"\n{len(records)} records found; {len(results)} checks, {len(results) - failed} passed, {failed} failed.")
    if args.out:
        Path(args.out).write_text(json.dumps({"results": results, "records": records}, indent=2), encoding="utf-8")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
