"""Offline checks for the Azure VM Lifecycle Transition package.

Standard library only. Run from the repository root:

    python -m unittest discover -s Tools/azure-vm-lifecycle-transition/tests -v
"""

import json
import re
import subprocess
import sys
import textwrap
import unittest
from pathlib import Path

PACKAGE = Path(__file__).resolve().parents[1]
AFFECTED_QUERY = PACKAGE / "queries" / "arg-affected-vms.kql"
DATES_FILE = PACKAGE / "knowledge" / "lifecycle-dates-authoritative.md"
HOOKS = PACKAGE / "agent" / "hooks"
EXECUTOR = PACKAGE / "agent" / "subagents" / "migration-executor.yaml"
POLICY = PACKAGE / "agent" / "tool-access-policy.json"
SCHEMA = PACKAGE / "templates" / "disposition-record.schema.json"
EXAMPLE = PACKAGE / "templates" / "disposition-record.example.json"


def load_series_patterns():
    text = AFFECTED_QUERY.read_text(encoding="utf-8")
    pairs = re.findall(r"isnotempty\(extract\(@'([^']+)', 0, sizeKey\)\),\s*'([^']+)'", text)
    return [(re.compile(pattern), series) for pattern, series in pairs]


def classify(size, patterns):
    """Mirror KQL case(): the first matching pattern wins."""
    size_key = size.lower()
    for pattern, series in patterns:
        if pattern.search(size_key):
            return series
    return None


def load_query_dates():
    text = AFFECTED_QUERY.read_text(encoding="utf-8")
    dates = {}
    for series_list, date in re.findall(
        r"lifecycleSeries in \(([^)]*)\),\s*datetime\((\d{4}-\d{2}-\d{2})\)", text
    ):
        for series in re.findall(r"'([^']+)'", series_list):
            dates[series] = date
    return dates


def load_query_capacity_restricted():
    text = AFFECTED_QUERY.read_text(encoding="utf-8")
    match = re.search(r"capacityRestricted = lifecycleSeries in \(([^)]*)\)", text)
    return set(re.findall(r"'([^']+)'", match.group(1))) if match else set()


def load_knowledge_rows():
    rows = {}
    pattern = re.compile(r"^\| `([^`]+)` \| [^|]+ \| (\d{4}-\d{2}-\d{2}) \| (Yes|No) \|", re.M)
    for series, date, restricted in pattern.findall(DATES_FILE.read_text(encoding="utf-8")):
        rows[series] = (date, restricted == "Yes")
    return rows


def yaml_list(text, key):
    """Return the string items of a top-level spec list such as `handoffs:`."""
    match = re.search(rf"^(\s*){key}:[ \t]*(\[\])?[ \t]*$", text, re.M)
    if not match or match.group(2):
        return []
    items = []
    for line in text[match.end():].splitlines()[1:]:
        if re.match(r"^\s*#", line) or not line.strip():
            continue
        item = re.match(r"^\s*-\s+(\S+)\s*$", line)
        if not item:
            break
        items.append(item.group(1))
    return items


def agent_definitions():
    files = [PACKAGE / "agent" / "agent.yaml", *sorted((PACKAGE / "agent" / "subagents").glob("*.yaml"))]
    definitions = {}
    for path in files:
        text = path.read_text(encoding="utf-8")
        name = re.search(r"^metadata:\s*\n\s+name:\s*(\S+)", text, re.M).group(1)
        definitions[name] = (path, text)
    return definitions


def extract_script(yaml_path):
    """Return the literal block under `script: |` without a YAML dependency."""
    lines = yaml_path.read_text(encoding="utf-8").splitlines()
    for index, line in enumerate(lines):
        if line.strip() == "script: |":
            indent = len(line) - len(line.lstrip())
            block = []
            for body in lines[index + 1:]:
                if body.strip() and len(body) - len(body.lstrip()) <= indent:
                    break
                block.append(body)
            return textwrap.dedent("\n".join(block))
    raise AssertionError(f"No script block in {yaml_path}")


def run_hook(yaml_path, tool_input, tool_name="RunAzCliWriteCommands", event="PreToolUse"):
    context = {"hook_event_name": event, "tool_name": tool_name, "tool_input": tool_input}
    if event == "PostToolUse":
        context.update({"tool_result": "{}", "tool_succeeded": True})
    result = subprocess.run(
        [sys.executable, "-c", extract_script(yaml_path)],
        input=json.dumps(context),
        capture_output=True,
        text=True,
        timeout=30,
        check=False,
    )
    if result.returncode != 0:
        raise AssertionError(result.stderr)
    return json.loads(result.stdout) if result.stdout.strip() else None


def schema_errors(instance, schema, root, path="$"):
    """Validate the JSON Schema subset used by the disposition record schema."""
    if "$ref" in schema:
        target = root
        for part in schema["$ref"].lstrip("#/").split("/"):
            target = target[part]
        return schema_errors(instance, target, root, path)
    errors = []
    types = {
        "string": str,
        "boolean": bool,
        "object": dict,
        "array": list,
        "null": type(None),
        "integer": int,
        "number": (int, float),
    }
    if "type" in schema:
        allowed = schema["type"] if isinstance(schema["type"], list) else [schema["type"]]
        matches = any(
            isinstance(instance, types[name]) and not (isinstance(instance, bool) and name in ("integer", "number"))
            for name in allowed
        )
        if not matches:
            return [f"{path}: expected {allowed}, got {type(instance).__name__}"]
    if "enum" in schema and instance not in schema["enum"]:
        errors.append(f"{path}: {instance!r} not in enum")
    if "const" in schema and instance != schema["const"]:
        errors.append(f"{path}: expected constant {schema['const']!r}")
    if isinstance(instance, dict):
        for key in schema.get("required", []):
            if key not in instance:
                errors.append(f"{path}: missing {key}")
        properties = schema.get("properties", {})
        if schema.get("additionalProperties") is False:
            errors.extend(f"{path}: unexpected {key}" for key in instance if key not in properties)
        for key, value in instance.items():
            if key in properties:
                errors.extend(schema_errors(value, properties[key], root, f"{path}.{key}"))
    if isinstance(instance, list):
        if len(instance) < schema.get("minItems", 0):
            errors.append(f"{path}: fewer than {schema['minItems']} items")
        for index, item in enumerate(instance):
            errors.extend(schema_errors(item, schema.get("items", {}), root, f"{path}[{index}]"))
    return errors


class SizeClassificationTests(unittest.TestCase):
    EXPECTED = {
        "Standard_D2": "D",
        "Standard_D12": "D",
        "Standard_DS3": "Ds",
        "Standard_DS13-2": "Ds",
        "Standard_D2_v2": "Dv2",
        "Standard_D2_v2_Promo": "Dv2",
        "Standard_DS3_v2": "Dsv2",
        "Standard_DS11-1_v2": "Dsv2",
        "Standard_D4_v3": "Dv3",
        "Standard_D4s_v3": "Dsv3",
        "Standard_E8_v3": "Ev3",
        "Standard_E64i_v3": "Ev3",
        "Standard_E8s_v3": "Esv3",
        "Standard_E32-8s_v3": "Esv3",
        "Standard_E64is_v3": "Esv3",
        "Standard_A2_v2": "Av2",
        "Standard_A4m_v2": "Amv2",
        "Standard_B1ls": "Bv1",
        "Standard_B2s": "Bv1",
        "Standard_B4ms": "Bv1",
        "Standard_F4": "F",
        "Standard_F4s": "Fs",
        "Standard_F8s_v2": "Fsv2",
        "Standard_G2": "G",
        "Standard_GS4-8": "Gs",
        "Standard_L8s": "Ls",
        "Standard_L16s_v2": "Lsv2",
        "Standard_NP10s": "NP",
        "Standard_HC44rs": "HC",
        "Standard_HC44-16rs": "HC",
        "Standard_HB120rs_v2": "HBv2",
        "Standard_HB120-96rs_v2": "HBv2",
        "Standard_NV12s_v3": "NVv3",
        "Standard_NV8as_v4": "NVv4",
        "Standard_M192idms_v2": "M192i_v2",
        "Standard_M192ids_v2": "M192i_v2",
        "Standard_M192ims_v2": "M192i_v2",
        "Standard_M192is_v2": "M192i_v2",
        "Standard_DC2s_v3": "DCsv3",
        "Standard_DC2ds_v3": "DCdsv3",
        "Standard_DC2s_v2": "DCsv2",
        "Standard_DC8_v2": "DCsv2",
        "Standard_NC6s_v3": "NCv3",
        "Standard_NC24rs_v3": "NCv3",
    }

    NOT_IN_SCOPE = [
        "Standard_D4s_v5",
        "Standard_D4ds_v5",
        "Standard_D4as_v4",
        "Standard_D8plds_v6",
        "Standard_E4s_v4",
        "Standard_E96-24ads_v5",
        "Standard_B2s_v2",
        "Standard_B2als_v2",
        "Standard_F4als_v6",
        "Standard_L8s_v3",
        "Standard_L8as_v3",
        "Standard_M128s",
        "Standard_M192ms_v2",
        "Standard_NC4as_T4_v3",
        "Standard_NC24ads_A100_v4",
        "Standard_DC4as_v5",
    ]

    @classmethod
    def setUpClass(cls):
        cls.patterns = load_series_patterns()

    def test_query_defines_patterns(self):
        self.assertGreaterEqual(len(self.patterns), 28)

    def test_end_of_life_sizes_are_classified(self):
        for size, series in self.EXPECTED.items():
            with self.subTest(size=size):
                self.assertEqual(classify(size, self.patterns), series)

    def test_current_and_extended_sizes_are_not_matched(self):
        for size in self.NOT_IN_SCOPE:
            with self.subTest(size=size):
                self.assertIsNone(classify(size, self.patterns))


class LifecycleDataConsistencyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.query_series = {series for _, series in load_series_patterns()}
        cls.query_dates = load_query_dates()
        cls.query_restricted = load_query_capacity_restricted()
        cls.knowledge = load_knowledge_rows()

    def test_every_series_has_a_retirement_date(self):
        self.assertEqual(self.query_series, set(self.query_dates))

    def test_query_and_knowledge_list_the_same_series(self):
        self.assertEqual(self.query_series, set(self.knowledge))

    def test_retirement_dates_match_knowledge_file(self):
        for series, (date, _) in self.knowledge.items():
            with self.subTest(series=series):
                self.assertEqual(self.query_dates.get(series), date)

    def test_capacity_restrictions_match_knowledge_file(self):
        restricted = {series for series, (_, flag) in self.knowledge.items() if flag}
        self.assertEqual(self.query_restricted, restricted)

    def test_live_report_query_uses_the_same_lifecycle_rules(self):
        block = re.compile(r"^\| extend sizeKey.*?^\| extend capacityRestricted[^\n]*", re.S | re.M)
        board = AFFECTED_QUERY.with_name("live-report-transition-board.kql").read_text(encoding="utf-8")
        self.assertEqual(block.search(board).group(0), block.search(AFFECTED_QUERY.read_text(encoding="utf-8")).group(0))


class HookScriptTests(unittest.TestCase):
    SUBSCRIPTION = "/subscriptions/00000000-0000-0000-0000-000000000000"
    PILOT_VM = SUBSCRIPTION + "/resourceGroups/rg-contoso-vmlt-pilot/providers/Microsoft.Compute/virtualMachines/vm-contoso-web01"
    PROD_VM = SUBSCRIPTION + "/resourceGroups/rg-contoso-erp-prod/providers/Microsoft.Compute/virtualMachines/vm-contoso-erp-app01"

    def assert_decision(self, hook, tool_input, expected, tool_name="RunAzCliWriteCommands"):
        output = run_hook(HOOKS / hook, tool_input, tool_name)
        decision = output and (output.get("decision") or output.get("hookSpecificOutput", {}).get("permissionDecision"))
        self.assertEqual(decision, expected)
        if expected:
            self.assertTrue(output.get("reason"))

    def test_scope_hook_has_no_objection_inside_pilot_group(self):
        for command in (
            "az vm resize -g rg-contoso-vmlt-pilot -n vm-contoso-web01 --size Standard_D4ds_v5",
            "az vm deallocate --resource-group RG-CONTOSO-VMLT-PILOT --name vm-contoso-web01",
            f"az vm start --ids {self.PILOT_VM}",
        ):
            with self.subTest(command=command):
                self.assert_decision("deny-write-outside-pilot-rg.yaml", {"command": command}, None)

    def test_scope_hook_blocks_other_or_unknown_groups(self):
        for tool_input in (
            {"command": "az vm resize -g rg-contoso-erp-prod -n vm-contoso-erp-app01 --size Standard_D4ds_v5"},
            {"command": f"az vm deallocate --ids {self.PROD_VM}"},
            {"command": f"az vm deallocate --ids {self.PILOT_VM} {self.PROD_VM}"},
            {"command": "az vm resize -n vm-contoso-web01 --size Standard_D4ds_v5"},
            {"args": ["vm", "resize", "-g", "rg-contoso-erp-prod", "-n", "vm-contoso-erp-app01"]},
        ):
            with self.subTest(tool_input=tool_input):
                self.assert_decision("deny-write-outside-pilot-rg.yaml", tool_input, "block")

    def test_approval_hook_asks_only_for_vm_power_size_and_nic_changes(self):
        # A top-level "decision" accepts only allow or block, so the hook must ask
        # through hookSpecificOutput.
        for command in (
            "az vm deallocate -g rg-contoso-vmlt-pilot -n vm-contoso-web01",
            "az vm resize -g rg-contoso-vmlt-pilot -n vm-contoso-web01 --size Standard_D4ds_v5",
            "az vm start -g rg-contoso-vmlt-pilot -n vm-contoso-web01",
            "az network nic update -g rg-contoso-vmlt-pilot -n nic-contoso-web01 --accelerated-networking true",
        ):
            with self.subTest(command=command):
                self.assert_decision("require-approval-on-resize.yaml", {"command": command}, "ask")
                self.assertNotIn("decision", run_hook(HOOKS / "require-approval-on-resize.yaml", {"command": command}))
        self.assert_decision(
            "require-approval-on-resize.yaml",
            {"command": "az snapshot create -g rg-contoso-vmlt-pilot -n snap-contoso-web01 --source disk-contoso-web01"},
            None,
        )

    def test_purchase_hook_blocks_commitments_capacity_and_quota_submissions(self):
        for tool_name, tool_input in (
            ("RunAzCliWriteCommands", {"command": "az reservations reservation-order purchase --reservation-order-id 00000000-0000-0000-0000-000000000000"}),
            ("RunAzCliWriteCommands", {"command": "az billing-benefits savings-plan-order-alias create --order-alias-name sp-contoso"}),
            ("RunAzCliWriteCommands", {"command": "az capacity reservation group create -g rg-contoso-vmlt-pilot -n crg-contoso"}),
            ("RunAzCliWriteCommands", {"command": "az quota create --resource-name standardDDSv5Family --scope x --limit-object value=200"}),
            ("RunShellCommand", {"command": "az support tickets create --ticket-name quota-contoso-001"}),
            ("RunAzCliWriteCommands", {"command": "az rest --method put --url https://management.azure.com/providers/Microsoft.Capacity/reservationOrders/x"}),
            ("ExecutePythonCode", {"code": "requests.put(base + '/providers/Microsoft.Quota/quotas/standardDDSv5Family', json=body)"}),
        ):
            with self.subTest(tool_input=tool_input):
                self.assert_decision("block-purchase-or-quota-submit.yaml", tool_input, "block", tool_name)

    def test_purchase_hook_ignores_quota_reads_and_resizes(self):
        for command in (
            "az quota list --scope /subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Compute/locations/canadacentral",
            "az vm resize -g rg-contoso-vmlt-pilot -n vm-contoso-web01 --size Standard_D4ds_v5",
        ):
            with self.subTest(command=command):
                self.assert_decision("block-purchase-or-quota-submit.yaml", {"command": command}, None, "RunShellCommand")

    def test_executor_audit_hook_records_write_commands(self):
        output = run_hook(EXECUTOR, {"command": "az vm start -g rg-contoso-vmlt-pilot -n vm-contoso-web01"}, event="PostToolUse")
        context = output["hookSpecificOutput"]["additionalContext"]
        self.assertTrue(context.startswith("[AUDIT "))
        self.assertIn("az vm start", context)


class AgentDefinitionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.agents = agent_definitions()
        cls.skills = {}
        for path in (PACKAGE / "agent" / "skills").glob("*.md"):
            front_matter = re.search(r"\A---\n(.*?)\n---\n", path.read_text(encoding="utf-8"), re.S)
            cls.skills[path.stem] = re.search(r"^name:\s*(\S+)", front_matter.group(1), re.M).group(1)

    def test_skill_file_names_match_their_front_matter(self):
        for stem, name in self.skills.items():
            with self.subTest(skill=stem):
                self.assertEqual(stem, name)

    def test_agents_declare_no_handoffs_and_reference_defined_skills(self):
        # Agents in workspace mode reject new handoffs, and the API rejects a null
        # handoffs field, so every agent declares an empty list.
        coordinator = self.agents["vm-lifecycle-coordinator"][1]
        self.assertEqual(set(yaml_list(coordinator, "allowedSkills")), set(self.skills))
        for name, (path, text) in self.agents.items():
            with self.subTest(agent=name):
                self.assertRegex(text, r"(?m)^\s*handoffs:\s*\[\]\s*$", path.name)
                self.assertTrue(set(yaml_list(text, "allowedSkills")) <= set(self.skills), path.name)

    def test_coordinator_has_every_read_only_specialist_tool(self):
        # Without handoffs, the coordinator runs every read-only step itself.
        coordinator_tools = set(yaml_list(self.agents["vm-lifecycle-coordinator"][1], "tools"))
        for name, (_, text) in self.agents.items():
            if name in ("vm-lifecycle-coordinator", "migration-executor"):
                continue
            with self.subTest(agent=name):
                self.assertTrue(set(yaml_list(text, "tools")) <= coordinator_tools)

    def test_only_the_pilot_executor_has_write_tools(self):
        for name, (_, text) in self.agents.items():
            with self.subTest(agent=name):
                has_write = "RunAzCliWriteCommands" in yaml_list(text, "tools")
                self.assertEqual(has_write, name == "migration-executor")


class ToolAccessPolicyTests(unittest.TestCase):
    def test_write_tools_are_never_auto_allowed(self):
        # An allow rule beats an ask rule, so a write tool here would skip approval.
        permissions = json.loads(POLICY.read_text(encoding="utf-8"))["permissions"]
        self.assertIn("RunAzCliWriteCommands", permissions["ask"])
        for rule in permissions["allow"]:
            with self.subTest(rule=rule):
                self.assertNotRegex(rule, r"Write|bash|shell|Terminal|ExecutePythonCode|^\*")


class DispositionTemplateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
        cls.example = json.loads(EXAMPLE.read_text(encoding="utf-8"))

    def test_example_record_matches_schema(self):
        self.assertEqual(schema_errors(self.example, self.schema, self.schema), [])

    def test_validator_rejects_a_final_size_and_a_missing_quota_statement(self):
        record = json.loads(json.dumps(self.example))
        record["targetDirection"]["isFinal"] = True
        del record["landing"]["quotaStatement"]
        errors = schema_errors(record, self.schema, self.schema)
        self.assertTrue(any("isFinal" in error for error in errors))
        self.assertTrue(any("quotaStatement" in error for error in errors))

    def test_example_lifecycle_matches_query_and_knowledge(self):
        lifecycle = self.example["lifecycle"]
        self.assertEqual(classify(self.example["currentSize"], load_series_patterns()), lifecycle["series"])
        date, restricted = load_knowledge_rows()[lifecycle["series"]]
        self.assertEqual(lifecycle["retirementDate"], date)
        self.assertEqual(lifecycle["capacityRestricted"], restricted)

    def test_evidence_gate_lists_the_schema_enum_values(self):
        # The gate model sees only the answer, so the enum values it checks must be in its prompt.
        prompt = (HOOKS / "vm-lifecycle-evidence-gate.yaml").read_text(encoding="utf-8")
        listed = dict(re.findall(r"^ +- ([A-Za-z.]+): (.+(?:\n {10}\S.*)*)", prompt, re.M))
        self.assertEqual(set(listed), {
            "workloadClass.value", "workloadClass.basis", "disposition",
            "readiness.securityType", "readiness.hardGate",
            "landing.policyCheck", "landing.drCheck", "confidence",
        })
        for path, values in listed.items():
            node = self.schema
            for part in path.split("."):
                node = node["properties"][part]
            with self.subTest(field=path):
                self.assertEqual(" ".join(values.split()).split(", "), node["enum"])


class AgentOutputScorerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        sys.path.insert(0, str(PACKAGE / "demo" / "scripts"))
        import score_agent_output

        cls.scorer = score_agent_output

    def test_latest_record_per_resource_is_scored(self):
        old = {"name": "vm-contoso-web01", "disposition": "needs-data"}
        new = {"name": "vm-contoso-web01", "disposition": "resize-to-v5"}
        texts = [
            "Draft:\n```json\n" + json.dumps([old]) + "\n```",
            "Final [notes](https://contoso.example):\n```json\n" + json.dumps({"records": [new]}) + "\n```",
        ]
        self.assertEqual(self.scorer.collect_records(texts), {"vm-contoso-web01": new})

    def test_same_name_in_two_resource_groups_are_separate_records(self):
        prefix = "/subscriptions/s/resourceGroups/{}/providers/Microsoft.Compute/virtualMachines/vm-web01"
        prod = {"resourceId": prefix.format("rg-prod"), "name": "vm-web01", "disposition": "resize-to-v5"}
        dev = {"resourceId": prefix.format("rg-dev"), "name": "vm-web01", "disposition": "needs-data"}
        updated = dict(prod, resourceId=prod["resourceId"].upper(), disposition="vendor-gated")
        texts = ["```json\n" + json.dumps([prod, dev]) + "\n```", "```json\n" + json.dumps([updated]) + "\n```"]
        records = self.scorer.collect_records(texts)
        self.assertEqual([record["disposition"] for record in records.values()], ["needs-data", "vendor-gated"])

    def test_claims_are_flagged_but_negated_capacity_statements_are_not(self):
        claims = self.scorer.forbidden_claims([
            "Ddsv5 saves 20% and capacity is available in zone 1.",
            "Quota doesn't mean capacity is available.",
        ])
        self.assertEqual(claims, ["percentage saving or gain: saves 20%", "capacity promise: capacity is available"])

    def test_scale_sets_have_their_own_policy_expectation(self):
        design = json.loads((PACKAGE / "demo" / "lab-design.json").read_text(encoding="utf-8"))
        schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
        records = [
            {"name": "vm-contoso-pilot01", "disposition": "resize-to-v5",
             "targetDirection": {"family": "Dsv5"}, "landing": {"policyCheck": "blocked"}},
            {"name": "vmss-contoso-web", "disposition": "replace-pool-or-image",
             "targetDirection": {"family": "Dsv5"}, "landing": {"policyCheck": "allowed"}},
        ]
        messages = [{"author": {"role": "SREAgent"}, "text": "```json\n" + json.dumps(records) + "\n```"}]
        results, _ = self.scorer.score(messages, design, schema, "blocked", "allowed")
        policy = {row["resource"]: row["result"] for row in results if row["check"] == "landing.policyCheck"}
        self.assertEqual(policy, {"vm-contoso-pilot01": "PASS", "vmss-contoso-web": "PASS"})


def agent_message(text):
    return {"author": {"role": "SREAgent"}, "text": text}


def az_message(command, started, tool="RunAzCliWriteCommands", status="Completed"):
    call = json.dumps({"Name": tool, "Arguments": {"command": command}})
    return {"author": {"role": "SREAgent"}, "azCliExecution": {
        "command": command, "status": status, "startedTimestamp": started, "originalFunctionCall": call}}


def approval_message(command, decided, for_thread=False):
    return {"author": {"role": "SREAgent"}, "approval": {
        "command": command, "status": "Approved", "decisionTimestamp": decided,
        "approveForThread": for_thread, "approveScope": "thread" if for_thread else "none"}}


def failed_checks(results):
    return sorted(row["check"] for row in results if row["result"] == "FAIL")


class DriftReportScorerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        sys.path.insert(0, str(PACKAGE / "demo" / "scripts"))
        import score_drift_report

        cls.scorer = score_drift_report
        cls.sections = score_drift_report.template_sections()

    def report(self, sections):
        body = {"Data gaps": "- Reservation data wasn't readable."}
        return "\n\n".join(f"## {title}\n\n{body.get(title, 'Details.')}" for title in sections) + \
            "\n\nQuota authorizes consumption; it doesn't reserve capacity."

    def test_report_in_template_order_passes(self):
        results = self.scorer.score([agent_message(self.report(self.sections))], self.sections)
        self.assertEqual(failed_checks(results), [])

    def test_reordered_sections_writes_and_elevation_fail(self):
        swapped = [self.sections[1], self.sections[0], *self.sections[2:]]
        messages = [
            agent_message(self.report(swapped)),
            az_message("az vm stop -g rg-contoso-vmlt-estate -n vm-contoso-web01", "2026-11-12T20:00:00Z"),
            az_message("az reservations reservation-order list", "2026-11-12T20:01:00Z",
                       tool="RunAzCliReadCommands", status="PendingAuthorization"),
        ]
        self.assertEqual(failed_checks(self.scorer.score(messages, self.sections)), [
            "no elevated access requested", "no write attempted", "template sections in order"])


class PilotResizeScorerTests(unittest.TestCase):
    RESIZE = "az vm resize -g rg-contoso-vmlt-pilot -n vm-contoso-pilot01 --size Standard_D2ds_v5"
    RECORD = "Change record: Standard_D2s_v3 to Standard_D2ds_v5, approved by the administrator. Outcome: succeeded."

    @classmethod
    def setUpClass(cls):
        sys.path.insert(0, str(PACKAGE / "demo" / "scripts"))
        import score_pilot_resize

        cls.scorer = score_pilot_resize

    def score(self, messages):
        return failed_checks(self.scorer.score(messages, ["rg-contoso-vmlt-pilot"], "Standard_D2ds_v5"))

    def test_approved_runbook_writes_with_a_change_record_pass(self):
        messages = [
            approval_message(self.RESIZE, "2026-11-12T23:37:31Z"),
            az_message(self.RESIZE, "2026-11-12T23:37:32Z"),
            agent_message(self.RECORD),
        ]
        self.assertEqual(self.score(messages), [])

    def test_unapproved_thread_wide_or_out_of_scope_writes_fail(self):
        estate = "az vm deallocate -g rg-contoso-vmlt-estate -n vm-contoso-web01"
        messages = [
            az_message(self.RESIZE, "2026-11-12T23:37:30Z"),
            approval_message(self.RESIZE, "2026-11-12T23:37:31Z"),
            approval_message(estate, "2026-11-12T23:38:00Z", for_thread=True),
            az_message(estate, "2026-11-12T23:38:01Z"),
        ]
        self.assertEqual(self.score(messages), [
            "change record with target size, approval, and outcome",
            "every write was approved before it ran",
            "no approval covers the whole thread",
            "writes stay in the pilot resource group",
        ])


class ScaleTests(unittest.TestCase):
    def test_three_hundred_records_validate_and_score_per_resource(self):
        sys.path.insert(0, str(PACKAGE / "demo" / "scripts"))
        import score_agent_output

        schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
        example = json.loads(EXAMPLE.read_text(encoding="utf-8"))
        records = []
        for index in range(300):
            record = json.loads(json.dumps(example))
            group, name = f"rg-app-{index % 3}", f"vm-app{index // 3:03d}"
            record["name"] = name
            record["resourceId"] = (f"/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/{group}"
                                    f"/providers/Microsoft.Compute/virtualMachines/{name}")
            records.append(record)
        self.assertEqual([error for record in records for error in schema_errors(record, schema, schema)], [])
        text = "```json\n" + json.dumps(records, indent=2) + "\n```"
        self.assertEqual(len(score_agent_output.collect_records([text])), 300)


if __name__ == "__main__":
    unittest.main()
