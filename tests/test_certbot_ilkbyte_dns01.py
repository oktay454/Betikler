#!/usr/bin/env python3
"""DNS veya API erişimi gerektirmeyen kanca regresyon sınamaları.
Çalıştırma: python3 -m unittest discover -s tests -p 'test_certbot_ilkbyte_dns01.py'
"""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "certbot-ilkbyte-dns01"
MOCK = r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
state = Path(os.environ["TEST_STATE"])
data = json.loads(state.read_text())
args = sys.argv[1:]
name = Path(sys.argv[0]).name
if name == "dig":
	data["dns"].append(args)
	state.write_text(json.dumps(data))
	if "NS" in args:
		print("ns1.example.test.\nns2.example.test.")
	elif os.environ.get("TEST_NO_DNS") != "1":
		print('"unrelated-token"')
		for record in data["records"]:
			if record["Type"] == "TXT":
				print(record["Content"])
	sys.exit(0)
if name == "sleep":
	sys.exit(0)
action = next(a for a in args if a.startswith("https://")).rsplit("/", 1)[1]
data["calls"].append(action)
state.write_text(json.dumps(data))
if os.environ.get("TEST_FAIL") == action:
	print(json.dumps({"status": False, "error": "denied access-test secret-test"}))
	sys.exit(0)
if os.environ.get("TEST_HTTP") == action:
	sys.exit(22)
if os.environ.get("TEST_BAD_JSON") == action:
	print("<html>blocked</html>")
	sys.exit(0)
if os.environ.get("TEST_BAD_RECORDS") == action:
	print(json.dumps({"status": True, "data": {}}))
	sys.exit(0)
params = dict(args[i+1].split("=",1) for i,a in enumerate(args) if a == "--data-urlencode")
if action == "add":
	assert params["record_priority"] == "0"
	assert params["record_content"].startswith('"')
	assert params["record_content"].endswith('"')
	data["records"].append({"Id": max([r["Id"] for r in data["records"]] + [0])+1,
		"Name": params["record_name"], "Type": params["record_type"], "Content": params["record_content"]})
if action == "delete":
	data["records"] = [r for r in data["records"] if str(r["Id"]) != params["record_id"]]
state.write_text(json.dumps(data))
print(json.dumps({"status": True, "data": {"Records": data["records"]}}))
'''


class HookTests(unittest.TestCase):
	def setUp(self):
		self.temp = tempfile.TemporaryDirectory(dir=SCRIPT.parent)
		self.addCleanup(self.temp.cleanup)
		self.root = Path(self.temp.name)
		self.state = self.root / "state.json"
		self.initial = [
			{"Id": 1, "Name": "_acme-challenge", "Type": "TXT", "Content": '"existing-token"'},
			{"Id": 2, "Name": "_acme-challenge", "Type": "CNAME", "Content": "keep.example.test"},
		]
		self.state.write_text(json.dumps({"records": self.initial, "calls": [], "dns": []}))
		for name in ("curl", "dig", "sleep"):
			path = self.root / name
			path.write_text(MOCK)
			path.chmod(0o755)
		config = self.root / "config"
		config.write_text('ACCESS_KEY="access-test"\nSECRET_KEY="secret-test"\nWAIT_ATTEMPTS=2\nWAIT_INTERVAL=1\n')
		self.env = {k: v for k, v in os.environ.items() if not k.startswith(("CERTBOT_", "TEST_"))}
		self.env.update(PATH=f"{self.root}:{os.environ['PATH']}", ENVIRONMENT_FILE=str(config), TEST_STATE=str(self.state))

	def run_hook(self, verb="add", token="token-one", extra=(), **env):
		return subprocess.run(["bash", str(SCRIPT), "-r", verb, *extra],
			env=self.env | {"CERTBOT_DOMAIN": "example.test", "CERTBOT_VALIDATION": token} | env,
			text=True, capture_output=True, timeout=10)

	def data(self):
		return json.loads(self.state.read_text())

	def test_apex_wildcard_and_selective_cleanup(self):
		for token in ("token-one", "token-two"):
			result = self.run_hook(token=token)
			self.assertEqual(result.returncode, 0, result.stderr)
		self.assertEqual(len(self.data()["records"]), 4)
		self.assertNotIn("delete", self.data()["calls"])
		self.assertTrue(any("@ns2.example.test." in call for call in self.data()["dns"]))
		result = self.run_hook("delete")
		self.assertEqual(result.returncode, 0, result.stderr)
		self.assertEqual([r["Content"] for r in self.data()["records"]][-1], '"token-two"')
		self.assertEqual(self.data()["records"][:2], self.initial)
		self.assertEqual(self.run_hook("delete", "token-two").returncode, 0)
		self.assertEqual(self.data()["records"], self.initial)

	def test_duplicate_add_is_idempotent(self):
		self.assertEqual(self.run_hook().returncode, 0)
		self.assertEqual(self.run_hook().returncode, 0)
		self.assertEqual(self.data()["calls"].count("add"), 1)

	def test_show_errors_never_mutate_dns(self):
		for setting in ("TEST_FAIL", "TEST_HTTP", "TEST_BAD_JSON", "TEST_BAD_RECORDS"):
			with self.subTest(setting=setting):
				result = self.run_hook(**{setting: "show"})
				self.assertNotEqual(result.returncode, 0)
				self.assertEqual(self.data()["records"], self.initial)
				self.assertNotIn("add", self.data()["calls"])
				self.assertNotIn("access-test", result.stderr)
				self.assertNotIn("secret-test", result.stderr)

	def test_mutation_failure_is_reported(self):
		for action in ("add", "push"):
			with self.subTest(action=action):
				self.assertNotEqual(self.run_hook(TEST_FAIL=action).returncode, 0)

	def test_delete_failure_is_reported(self):
		result = self.run_hook("delete", "existing-token", TEST_FAIL="delete")
		self.assertNotEqual(result.returncode, 0)
		self.assertEqual(self.data()["records"], self.initial)
		self.assertNotIn("push", self.data()["calls"])

	def test_propagation_timeout_is_reported(self):
		result = self.run_hook(TEST_NO_DNS="1")
		self.assertNotEqual(result.returncode, 0)
		self.assertIn("zaman aşımı", result.stderr)

	def test_delete_requires_token(self):
		result = self.run_hook("delete", "")
		self.assertNotEqual(result.returncode, 0)
		self.assertEqual(self.data()["calls"], [])

	def test_explicit_subdomain_and_uppercase_verb(self):
		result = self.run_hook("ADD", extra=("-d", "example.test", "-s", "api"))
		self.assertEqual(result.returncode, 0, result.stderr)
		self.assertEqual(self.data()["records"][-1]["Name"], "_acme-challenge.api")

	def test_wildcard_prefix(self):
		result = self.run_hook(CERTBOT_DOMAIN="*.example.test")
		self.assertEqual(result.returncode, 0, result.stderr)
		self.assertTrue(any("_acme-challenge.example.test." in call for call in self.data()["dns"]))


if __name__ == "__main__":
	unittest.main()
