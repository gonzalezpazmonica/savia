import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
RECEIPT = ROOT / "docs/evidence/SE-396-a01c-operational-receipts.json"


class A01cOperationalReceiptTests(unittest.TestCase):
    def test_two_adapters_cover_the_complete_scenario(self):
        evidence = json.loads(RECEIPT.read_text(encoding="utf-8"))
        receipts = {item["adapter_id"]: item for item in evidence["receipts"]}

        self.assertEqual({"codex", "opencode"}, set(receipts))
        for receipt in receipts.values():
            for stage in ("start", "stream", "cancel", "persistent_resume"):
                self.assertEqual("VERIFIED", receipt[stage])
            self.assertFalse(receipt["unsafe_approval_flags"])

    def test_receipt_is_metadata_only(self):
        evidence = json.loads(RECEIPT.read_text(encoding="utf-8"))
        self.assertFalse(evidence["content_persisted"])
        self.assertFalse(evidence["native_session_ids_persisted"])

        forbidden = {"prompt", "response", "session_id", "thread_id", "credential", "api_key"}

        def keys(value):
            if isinstance(value, dict):
                for key, nested in value.items():
                    yield key
                    yield from keys(nested)
            elif isinstance(value, list):
                for nested in value:
                    yield from keys(nested)

        self.assertTrue(forbidden.isdisjoint(keys(evidence)))


if __name__ == "__main__":
    unittest.main()
