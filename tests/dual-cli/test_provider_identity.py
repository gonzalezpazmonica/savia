import os
from pathlib import Path
import subprocess
import unittest

ROOT=Path(__file__).resolve().parents[2]
SCRIPT=ROOT / "scripts/model-capability-resolver.sh"

class ProviderIdentityTests(unittest.TestCase):
    def resolve(self, model):
        output=subprocess.check_output([str(SCRIPT),"--model",model], text=True, env={**os.environ, "SAVIA_MODEL":""})
        return dict(line.removeprefix("export ").split("=",1) for line in output.splitlines())

    def test_provider_qualified_identity_is_not_collapsed(self):
        values=self.resolve("deepseek/deepseek-v4-pro")
        self.assertEqual(values["SAVIA_MODEL_PROVIDER"], "deepseek")
        self.assertEqual(values["SAVIA_MODEL_ID"], "deepseek-v4-pro")
        self.assertEqual(values["SAVIA_DETECTED_MODEL"], "deepseek/deepseek-v4-pro")
        self.assertTrue(values["SAVIA_MODEL_METADATA_SOURCE"].endswith("config/model-capabilities.yaml"))
        self.assertNotEqual(values["SAVIA_MODEL_METADATA_REVISION"], "unknown")

    def test_unknown_model_has_no_invented_context_budget(self):
        values=self.resolve("other/deepseek-v4-pro")
        self.assertEqual(values["SAVIA_MODEL_METADATA_STATUS"], "unknown")
        self.assertEqual(values["SAVIA_CONTEXT_WINDOW"], "0")

    def test_known_model_with_unregistered_provider_is_not_verified(self):
        values=self.resolve("fixture-unregistered/deepseek-v4-pro")
        self.assertEqual(values["SAVIA_MODEL_METADATA_STATUS"], "unknown")
        self.assertEqual(values["SAVIA_CONTEXT_WINDOW"], "0")

if __name__ == "__main__": unittest.main()
