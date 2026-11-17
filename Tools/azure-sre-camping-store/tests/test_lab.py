import argparse
import io
import importlib.util
import subprocess
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("lab", ROOT / "scripts" / "lab.py")
lab = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(lab)


class OperatorTests(unittest.TestCase):
    def test_external_or_non_https_fault_targets_are_rejected(self):
        for value in ("http://app.azurecontainerapps.io", "https://production.example",
                      "https://app.azurecontainerapps.io.evil.example",
                      "https://app.azurecontainerapps.io/other"):
            with self.subTest(value=value), self.assertRaises(RuntimeError):
                lab.public_app_url(value)

    def test_failed_image_build_stops_before_deployment(self):
        instance = object.__new__(lab.Lab)
        instance.group = "rg-contoso"
        instance.values = {"AZURE_CONTAINER_REGISTRY_NAME": "contosodemo"}
        failure = subprocess.CalledProcessError(1, ["az", "acr", "build"])
        with patch.object(instance, "az", side_effect=["contosodemo.azurecr.io", failure]) as az, \
                patch("sys.stdout", new_callable=io.StringIO):
            with self.assertRaises(subprocess.CalledProcessError):
                instance.deploy_app()
        self.assertEqual(2, az.call_count)
        self.assertIn(instance.group, az.call_args.args)
        self.assertNotIn("containerapp", az.call_args.args)

    def test_all_write_commands_require_approval_before_any_cli_call(self):
        for command in ("deploy-app", "configure-agent", "inject-memory", "recover", "create-sample-issues"):
            argv = [command]
            if command == "create-sample-issues":
                argv.extend(["--github-repo", "contoso/demo"])
            with self.subTest(command=command), patch.object(lab, "run") as run, \
                    patch("sys.stderr", new_callable=io.StringIO):
                with self.assertRaises(SystemExit) as result:
                    lab.main(argv)
                self.assertEqual(2, result.exception.code)
                run.assert_not_called()

    def test_load_is_bounded_before_cli_calls(self):
        for count in ("0", "121", "-1"):
            with self.subTest(count=count), patch.object(lab, "run") as run, \
                    patch("sys.stderr", new_callable=io.StringIO):
                with self.assertRaises(SystemExit):
                    lab.main(["inject-memory", "--approve", "--requests", count])
                run.assert_not_called()

    def test_github_target_is_explicit_and_not_a_url_or_option(self):
        for target in ("", "user", "https://github.com/contoso/demo", "--repo", "a/b/c"):
            with self.assertRaises(argparse.ArgumentTypeError):
                lab.github_target(target)
        self.assertEqual("contoso/showcase", lab.github_target("contoso/showcase"))

    def test_environment_subscription_and_resource_group_are_guarded(self):
        subscription = "00000000-0000-0000-0000-000000000000"
        with patch.object(lab, "run", side_effect=[
            subscription, "rg-contoso-camping", "different-subscription",
        ]) as run:
            with self.assertRaisesRegex(RuntimeError, "subscription differs"):
                lab.Lab()
            self.assertEqual(3, run.call_count)
            self.assertEqual(("azd", "env", "get-value", "AZURE_SUBSCRIPTION_ID"), run.call_args_list[0].args)
        with patch.object(lab, "run", side_effect=[
            subscription, "rg-contoso-camping", subscription, "production",
        ]):
            with self.assertRaisesRegex(RuntimeError, "not tagged"):
                lab.Lab()

    def test_every_agent_has_only_read_tools_and_no_implicit_github_target(self):
        for path in (ROOT / "sre-config" / "agents").glob("*.yaml"):
            payload = lab.agent_payload(path, "contoso/showcase")
            self.assertFalse(set(payload["properties"]["tools"]) - lab.READ_TOOLS)
            self.assertEqual([], payload["properties"]["mcpTools"])
            self.assertNotIn("GITHUB_REPO_PLACEHOLDER", payload["properties"]["instructions"])
        with self.assertRaisesRegex(ValueError, "explicit GitHub target"):
            lab.agent_payload(ROOT / "sre-config" / "agents" / "code-analyzer.yaml")

    def test_recover_disables_fault_and_verifies_checkout(self):
        instance = object.__new__(lab.Lab)
        with patch.object(instance, "update_api") as update, \
                patch.object(instance, "api_origin", return_value="https://api.example"), \
                patch.object(lab, "request_json", side_effect=[{"version": "v1"}, {}, {"id": 1}]) as http:
            instance.recover()
            update.assert_called_once_with("Camping__AnalyticsEntryMegabytes=0", "API_VERSION=v1")
            self.assertEqual("https://api.example/api/orders", http.call_args.args[0])

    def test_no_success_when_recovery_health_is_wrong(self):
        instance = object.__new__(lab.Lab)
        with patch.object(instance, "update_api"), \
                patch.object(instance, "api_origin", return_value="https://api.example"), \
                patch.object(lab, "request_json", return_value={"version": "v2"}):
            with self.assertRaisesRegex(RuntimeError, "health check failed"):
                instance.recover()

    def test_endpoint_mismatch_prevents_sre_data_calls(self):
        instance = object.__new__(lab.Lab)
        instance.subscription = "00000000-0000-0000-0000-000000000000"
        instance.group = "rg-contoso"
        instance.values = {"SRE_AGENT_NAME": "contoso", "SRE_AGENT_ENDPOINT": "https://wrong.example"}
        with patch.object(instance, "az", return_value="https://actual.example"), \
                patch.object(instance, "data") as data:
            with self.assertRaisesRegex(RuntimeError, "does not match"):
                instance.configure_agent()
            data.assert_not_called()

    def test_configuration_verification_fails_closed(self):
        instance = object.__new__(lab.Lab)
        instance.subscription = "00000000-0000-0000-0000-000000000000"
        instance.group = "rg-contoso"
        instance.values = {"SRE_AGENT_NAME": "contoso", "SRE_AGENT_ENDPOINT": "https://actual.example"}
        with patch.object(instance, "az", return_value="https://actual.example"), \
                patch.object(instance, "data", return_value={}):
            with self.assertRaisesRegex(RuntimeError, "verification failed"):
                instance.configure_agent()

    def test_onboarding_core_and_explicit_github_have_no_automatic_writes(self):
        for repo, count in ((None, 1), ("contoso/showcase", 3)):
            instance = object.__new__(lab.Lab)
            instance.subscription = "00000000-0000-0000-0000-000000000000"
            instance.group = "rg-contoso"
            instance.values = {"SRE_AGENT_NAME": "contoso", "SRE_AGENT_ENDPOINT": "https://actual.example"}
            writes = []

            def data(method, path, body=None):
                if method == "GET" and path.endswith("/github/domains"):
                    return {"values": [{"name": "github_com"}]}
                self.assertEqual("PUT", method)
                writes.append((path, body))
                return body

            with self.subTest(repo=repo), \
                    patch.object(instance, "az", return_value="https://actual.example"), \
                    patch.object(instance, "data", side_effect=data), \
                    patch("sys.stdout", new_callable=io.StringIO):
                instance.configure_agent(repo)
            agents = [body for path, body in writes if "/agents/" in path]
            knowledge = [body for path, body in writes if "/connectors/" in path]
            self.assertEqual(count, len(agents))
            self.assertEqual(4, len(knowledge))
            self.assertFalse(any("scheduledtasks" in path or "incidentFilters" in path for path, _ in writes))

    def test_fault_load_sends_only_requested_count_to_resolved_lab(self):
        instance = object.__new__(lab.Lab)
        with patch.object(instance, "update_api") as update, \
                patch.object(instance, "api_origin", return_value="https://api.example"), \
                patch.object(lab, "time") as clock, \
                patch.object(lab, "request_json", side_effect=[{"version": "v1"}, {}, {}, {}]) as http, \
                patch("sys.stdout", new_callable=io.StringIO):
            instance.inject_memory(3)
            update.assert_called_once_with("Camping__AnalyticsEntryMegabytes=10")
            self.assertEqual(4, http.call_count)
            self.assertEqual(3, clock.sleep.call_count)
            self.assertTrue(all(call.args[0] == "https://api.example/api/cart/demo-user/items"
                                for call in http.call_args_list[1:]))


if __name__ == "__main__":
    unittest.main()
