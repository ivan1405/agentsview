import json
import os
from pathlib import Path
import shutil
import subprocess
import unittest


@unittest.skipUnless(shutil.which("docker"), "Docker Compose is required")
class ComposeDesktopTest(unittest.TestCase):
    def config(self, desktop):
        environment = dict(os.environ)
        environment.update({
            "AGENTSVIEW_IMAGE": "example.invalid/agentsview:test",
            "AGENTSVIEW_AUTH_TOKEN": "example-token",
            "AGENTSVIEW_WEB_CONFIG_TOML": '[pg]\nurl = "${PG_PASSWORD}"\n',
            "AGENTSVIEW_COLLECTOR_CONFIG_TOML": '[pg]\nurl = "${PG_PASSWORD}"\n',
            "PG_PASSWORD": "example-password",
            "POSTGRES_USER": "example",
            "POSTGRES_DB": "example",
            "AWS_REGION": "us-east-1",
            "AWS_ACCESS_KEY_ID": "example-key",
            "AWS_SECRET_ACCESS_KEY": "example-secret",
            "COLLECTOR_INTERVAL": "5s",
        })
        command = ["docker", "compose", "--env-file", os.devnull, "-f", "compose.yaml"]
        if desktop:
            command += ["-f", "compose.desktop.yaml"]
        result = subprocess.run(
            command + ["config", "--format", "json"],
            cwd=Path(__file__).resolve().parent,
            env=environment,
            check=True,
            capture_output=True,
            text=True,
        )
        return json.loads(result.stdout)["services"]

    def test_linux_retains_host_networking(self):
        services = self.config(desktop=False)
        self.assertNotIn("net", services)
        for service in services.values():
            self.assertEqual(service["network_mode"], "host")
            self.assertFalse(service.get("ports"))

    def test_desktop_shares_namespace_and_publishes_only_loopback_web(self):
        services = self.config(desktop=True)
        for name in ("postgres", "web", "collector"):
            self.assertEqual(services[name]["network_mode"], "service:net")
            self.assertFalse(services[name].get("ports"))
        ports = services["net"]["ports"]
        self.assertEqual(len(ports), 1)
        self.assertEqual(ports[0]["host_ip"], "127.0.0.1")
        self.assertEqual(ports[0]["published"], "8080")
        self.assertEqual(ports[0]["target"], 8080)
        self.assertEqual(services["web"]["environment"]["AGENTSVIEW_HOST"], "0.0.0.0")
        self.assertEqual(services["web"]["environment"]["AGENTSVIEW_REQUIRE_AUTH"], "true")
        self.assertEqual(services["collector"]["environment"]["AGENTSVIEW_HOST"], "127.0.0.1")
        self.assertEqual(services["collector"]["environment"]["AWS_S3_ENDPOINT"], "https://127.0.0.1:9297")


if __name__ == "__main__":
    unittest.main()
