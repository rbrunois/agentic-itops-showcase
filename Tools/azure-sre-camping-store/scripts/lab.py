#!/usr/bin/env python3
"""Approval-gated Camping Store lab operations; no cloud writes on import."""

import argparse
import base64
import json
import re
import shutil
import subprocess
import sys
import tempfile
import time
import uuid
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
PURPOSE = "azure-sre-camping-store-demo"
READ_TOOLS = {
    "SearchMemory", "RunAzCliReadCommands", "GetAzCliHelp",
    "QueryLogAnalyticsByWorkspaceId", "QueryAppInsightsByResourceId",
    "FetchGithubIssue", "FetchGithubIssues", "FetchGithubIssueComments",
    "FindConnectedGitHubRepo", "GetIaCForGitHub",
    "PlotAreaChartWithCorrelation", "PlotHeatmap", "PlotPieChart", "PlotScatter",
}


def run(*args):
    executable = shutil.which(args[0])
    if not executable:
        raise RuntimeError(f"Required tool not found: {args[0]}")
    return subprocess.run(
        [executable, *args[1:]], cwd=ROOT, check=True,
        text=True, stdout=subprocess.PIPE,
    ).stdout.strip()


def github_target(value):
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_.-]+", value):
        raise argparse.ArgumentTypeError("GitHub target must be an explicit owner/repo")
    return value


def request_json(url, payload=None):
    data = None if payload is None else json.dumps(payload).encode()
    request = Request(url, data=data, headers={"Content-Type": "application/json"})
    with urlopen(request, timeout=30) as response:
        return json.load(response)


def public_app_url(value):
    parsed = urlparse(value)
    if (parsed.scheme != "https" or not parsed.hostname
            or not parsed.hostname.endswith(".azurecontainerapps.io")
            or parsed.username or parsed.password or parsed.port
            or parsed.path not in ("", "/") or parsed.query or parsed.fragment):
        raise RuntimeError("Expected the lab's public Container Apps HTTPS origin")
    return value.rstrip("/")


def agent_payload(path, repo=None):
    import yaml

    spec = yaml.safe_load(path.read_text(encoding="utf-8"))["spec"]
    tools = spec["tools"]
    if not tools or set(tools) - READ_TOOLS:
        raise ValueError(f"{path.name}: tools must be explicitly allowlisted read-only tools")
    instructions = spec["system_prompt"]
    if "GITHUB_REPO_PLACEHOLDER" in instructions and not repo:
        raise ValueError("This agent requires an explicit GitHub target")
    return {
        "name": spec["name"], "type": "ExtendedAgent", "tags": [], "owner": "",
        "properties": {
            "instructions": instructions.replace("GITHUB_REPO_PLACEHOLDER", repo or ""),
            "handoffDescription": spec["handoff_description"],
            "handoffs": [], "tools": tools, "mcpTools": [],
            "allowParallelToolCalls": True, "enableSkills": False,
        },
    }


class Lab:
    def __init__(self):
        self.values = {}
        self.subscription = self.value("AZURE_SUBSCRIPTION_ID")
        self.group = self.value("AZURE_RESOURCE_GROUP")
        actual = run("az", "account", "show", "--query", "id", "-o", "tsv")
        if actual.lower() != self.subscription.lower():
            raise RuntimeError("Azure CLI subscription differs from the selected azd environment")
        tag = self.az("group", "show", "-n", self.group, "--query", "tags.purpose", "-o", "tsv")
        if tag != PURPOSE:
            raise RuntimeError("Refusing to operate: resource group is not tagged as this demo")

    def value(self, name):
        if name not in self.values:
            self.values[name] = run("azd", "env", "get-value", name)
        value = self.values.get(name)
        if not isinstance(value, str) or not value.strip():
            raise RuntimeError(f"Missing azd environment value: {name}")
        return value.strip()

    def az(self, *args):
        return run("az", *args, "--subscription", self.subscription)

    def api_origin(self):
        # Resolve the current resource rather than trusting a user-supplied URL.
        fqdn = self.az(
            "containerapp", "show", "-g", self.group, "-n", self.value("CONTAINER_APP_NAME"),
            "--query", "properties.configuration.ingress.fqdn", "-o", "tsv",
        )
        return public_app_url(f"https://{fqdn}")

    def update_api(self, *settings):
        self.az(
            "containerapp", "update", "-g", self.group, "-n", self.value("CONTAINER_APP_NAME"),
            "--set-env-vars", *settings, "-o", "none",
        )

    def deploy_app(self):
        registry = self.value("AZURE_CONTAINER_REGISTRY_NAME")
        server = self.az(
            "acr", "show", "-n", registry, "-g", self.group,
            "--query", "loginServer", "-o", "tsv",
        )
        tag = uuid.uuid4().hex[:12]
        for component, folder in (("api", "api"), ("frontend", "frontend")):
            print(f"Building {component}:{tag} using billable ACR Tasks...", flush=True)
            self.az(
                "acr", "build", "--registry", registry, "--resource-group", self.group,
                "--image", f"camping-{component}:{tag}",
                "--file", str(ROOT / "src" / folder / "Dockerfile"),
                str(ROOT / "src" / folder), "--no-logs", "-o", "none",
            )
        self.az(
            "containerapp", "update", "-g", self.group, "-n", self.value("CONTAINER_APP_NAME"),
            "--image", f"{server}/camping-api:{tag}",
            "--set-env-vars", "API_VERSION=v1", "Camping__AnalyticsEntryMegabytes=0",
            "-o", "none",
        )
        origin = self.api_origin()
        self.az(
            "containerapp", "update", "-g", self.group, "-n", self.value("FRONTEND_APP_NAME"),
            "--image", f"{server}/camping-frontend:{tag}",
            "--set-env-vars", f"REACT_APP_API_BASE_URL={origin}/api", "-o", "none",
        )
        frontend = self.az(
            "containerapp", "show", "-g", self.group, "-n", self.value("FRONTEND_APP_NAME"),
            "--query", "properties.configuration.ingress.fqdn", "-o", "tsv",
        )
        self.update_api(f"AllowedOrigins__0={public_app_url('https://' + frontend)}")
        health = request_json(f"{origin}/health")
        if health.get("version") != "v1" or not request_json(f"{origin}/api/products"):
            raise RuntimeError("Deployment completed but API verification failed")
        print(f"API verified: {origin}\nFrontend: https://{frontend}\nImage tag: {tag}")

    def data(self, method, path, body=None):
        endpoint = self.value("SRE_AGENT_ENDPOINT").rstrip("/")
        args = [
            "rest", "--method", method, "--resource", "https://azuresre.dev",
            "--url", endpoint + path,
        ]
        if body is None:
            return json.loads(self.az(*args, "-o", "json"))
        with tempfile.TemporaryDirectory(prefix="camping-agent-") as directory:
            payload = Path(directory) / "body.json"
            payload.write_text(json.dumps(body), encoding="utf-8")
            self.az(*args, "--headers", "Content-Type=application/json",
                    "--body", "@" + str(payload), "-o", "none")
        return self.data("GET", path)

    def configure_agent(self, repo=None):
        # Do not send an Azure token to an arbitrary endpoint from local state.
        resource_id = (
            f"/subscriptions/{self.subscription}/resourceGroups/{self.group}"
            f"/providers/Microsoft.App/agents/{self.value('SRE_AGENT_NAME')}"
        )
        endpoint = self.az(
            "resource", "show", "--ids", resource_id, "--api-version", "2025-05-01-preview",
            "--query", "properties.agentEndpoint", "-o", "tsv",
        )
        if endpoint.rstrip("/") != self.value("SRE_AGENT_ENDPOINT").rstrip("/"):
            raise RuntimeError("SRE endpoint does not match the deployed lab agent")
        if urlparse(endpoint).scheme != "https":
            raise RuntimeError("SRE endpoint must use HTTPS")

        # Validate all local payloads before writing any configuration.
        paths = [ROOT / "sre-config" / "agents" / "incident-handler-core.yaml"]
        if repo:
            paths.extend(ROOT / "sre-config" / "agents" / name
                         for name in ("code-analyzer.yaml", "issue-triager.yaml"))
        agents = [agent_payload(path, repo) for path in paths]
        if repo:
            if not self.data("GET", "/api/v2/github/domains").get("values"):
                raise RuntimeError("Connect GitHub in the SRE portal first, then rerun")
            name = repo.split("/")[1]
            body = {
                "name": name, "type": "CodeRepo",
                "properties": {"url": f"https://github.com/{repo}", "type": "GitHub",
                               "description": "Camping Store showcase source / demo issue target"},
            }
            saved = self.data("PUT", f"/api/v2/repos/{name}", body)
            if saved.get("properties", {}).get("url", "").rstrip("/") != f"https://github.com/{repo}":
                raise RuntimeError("Connected repository verification failed")

        for path in sorted((ROOT / "knowledge-base").glob("*.md")):
            name = path.name.replace(".", "-")
            body = {
                "name": name, "type": "KnowledgeItem", "tags": [],
                "properties": {
                    "dataConnectorType": "KnowledgeFile", "dataSource": name,
                    "extendedProperties": {
                        "displayName": path.name, "fileName": path.name,
                        "fileContent": base64.b64encode(path.read_bytes()).decode("ascii"),
                        "contentType": "text/markdown",
                    },
                },
            }
            saved = self.data("PUT", f"/api/v2/extendedAgent/connectors/{name}", body)
            if saved.get("properties", {}).get("dataConnectorType") != "KnowledgeFile":
                raise RuntimeError(f"Knowledge connector verification failed: {name}")
        for body in agents:
            name = body["name"]
            saved = self.data("PUT", f"/api/v2/extendedAgent/agents/{name}", body)
            props = saved.get("properties", {})
            if set(props.get("tools", [])) != set(body["properties"]["tools"]) or props.get("mcpTools"):
                raise RuntimeError(f"Read-only tool verification failed: {name}")
        print("Knowledge uploaded and read-only custom agents verified.")
        print("No response plan, scheduled task, sample issue, or GitHub write was created.")
        print("Verify knowledge indexing in the SRE portal before starting investigation.")

    def inject_memory(self, count):
        origin = self.api_origin()
        if request_json(f"{origin}/health").get("version") != "v1":
            raise RuntimeError("Expected a healthy v1 API before injecting a memory fault")
        self.update_api("Camping__AnalyticsEntryMegabytes=10")
        successes = failures = 0
        try:
            for _ in range(count):
                try:
                    request_json(f"{origin}/api/cart/demo-user/items", {"productId": 1, "quantity": 1})
                    successes += 1
                except (HTTPError, URLError, TimeoutError) as error:
                    failures += 1
                    print(f"Load request failed: {error}", file=sys.stderr)
                time.sleep(0.5)
        finally:
            print("Fault setting remains enabled until you explicitly run recover --approve.")
        print(f"Load finished: {successes} successful requests, {failures} failures.")
        print("Inspect memory, restarts, and logs; OOM/5xx/alerts are not guaranteed.")

    def recover(self):
        self.update_api("Camping__AnalyticsEntryMegabytes=0", "API_VERSION=v1")
        origin = self.api_origin()
        if request_json(f"{origin}/health").get("version") != "v1":
            raise RuntimeError("Recovery health check failed")
        request_json(f"{origin}/api/cart/recovery-check/items", {"productId": 1, "quantity": 1})
        order = request_json(f"{origin}/api/orders", {
            "userId": "recovery-check", "shippingAddress": "1 Contoso Trail", "paymentMethod": "card",
        })
        if not order.get("id"):
            raise RuntimeError("Recovery checkout verification failed")
        print("v1 health, cart add, and synthetic checkout verified.")
        print("Now verify memory/restarts stabilize and the Azure Monitor alert clears.")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("status", "deploy-app", "configure-agent", "inject-memory", "recover", "create-sample-issues"):
        command = commands.add_parser(name)
        if name != "status":
            command.add_argument("--approve", action="store_true", help="Approve this command's documented writes")
        if name in ("configure-agent", "create-sample-issues"):
            command.add_argument("--github-repo", type=github_target, required=name == "create-sample-issues")
        if name == "inject-memory":
            command.add_argument("--requests", type=int, default=120, choices=range(1, 121), metavar="1..120")
    args = parser.parse_args(argv)
    if args.command != "status" and not args.approve:
        parser.error("No changes made. Read README.md and pass --approve for this operation.")
    if args.command == "create-sample-issues":
        for title, body in (
            ("[Customer Issue] Cart becomes slow", "Synthetic Contoso report: repeated cart adds become slow. Please investigate memory."),
            ("[Customer Issue] Checkout reports payment error", "Synthetic Contoso report: checkout shows PAYMENT_ERROR after a deployment."),
            ("[Customer Issue] Product comparison", "Synthetic Contoso request: compare tent capacity before purchase."),
        ):
            print(run("gh", "issue", "create", "--repo", args.github_repo, "--title", title, "--body", body))
        return
    lab = Lab()
    if args.command == "status":
        print(json.dumps({
            "resourceGroup": lab.group, "api": lab.api_origin(),
            "agent": lab.value("SRE_AGENT_NAME"),
        }, indent=2))
    elif args.command == "configure-agent":
        lab.configure_agent(args.github_repo)
    elif args.command == "inject-memory":
        lab.inject_memory(args.requests)
    elif args.command == "deploy-app":
        lab.deploy_app()
    elif args.command == "recover":
        lab.recover()


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, ValueError, subprocess.CalledProcessError, HTTPError, URLError, TimeoutError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(1)
