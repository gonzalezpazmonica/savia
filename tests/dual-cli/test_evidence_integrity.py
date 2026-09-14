"""Negative controls for certification, value objects and durable receipts."""
import copy
from pathlib import Path
import tempfile
import unittest
from test_harness_contracts import CONTEXT, RESULT
from contracts import capability_observation, execution_context, execution_result
from protocol import ProtocolError
from autonomy import AutonomyPolicy, write_receipt


class ValueObjectTests(unittest.TestCase):
    def test_container_enum_values_raise_protocol_error(self):
        for bad in ([], {}, True, 1, None):
            for field in ('inference_mode', 'authority_ceiling'):
                with self.subTest(field=field, bad=bad), self.assertRaises(ProtocolError):
                    execution_context(dict(CONTEXT, **{field: bad}))
            with self.assertRaises(ProtocolError):
                execution_result(dict(RESULT, state=bad))

    def test_usage_extensions_are_not_token_counters(self):
        value = dict(RESULT, usage={'input_tokens': 1, 'output_tokens': 2,
                                  'extensions': {'fixture:cache_hits': 3}})
        self.assertEqual(execution_result(value), value)

    def test_timestamp_requires_rfc3339_utc(self):
        for stamp in ('2026-09-07T01:00:00+01:00', '2026-09-07 00:00:00Z',
                      '20260907T000000Z', 123):
            with self.subTest(stamp=stamp), self.assertRaises(ProtocolError):
                capability_observation(dict(capability_id='edit', status='verified',
                    mechanism='native', observed_at=stamp, environment_hash='env',
                    subject_version='1', evidence_ref='evidence'))


class ReceiptIntegrityTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.path = Path(self.folder.name) / 'receipt.json'
        self.decision = AutonomyPolicy([], []).decide('edit')

    def write(self, **changes):
        args = dict(frontend='fixture-cli', request_id='request', event_id='event',
                    decision_id='decision', execution=copy.deepcopy(RESULT), context=CONTEXT)
        args.update(changes)
        return write_receipt(self.path, self.decision, 'scope', 'p', ['edit'], **args)

    def test_mismatch_is_rejected_before_file_creation(self):
        with self.assertRaises(ProtocolError):
            self.write(execution=dict(RESULT, request_id='other'))
        self.assertFalse(self.path.exists())

    def test_same_receipt_is_idempotent_but_changed_content_is_rejected(self):
        first = self.write()
        content = self.path.read_bytes()
        self.assertEqual(self.write(), first)
        with self.assertRaises(ProtocolError):
            self.write(execution=dict(RESULT, state='failed'))
        self.assertEqual(self.path.read_bytes(), content)

    def test_symlink_target_is_never_followed(self):
        other = Path(self.folder.name) / 'other.json'
        other.write_text('operator data')
        self.path.symlink_to(other)
        with self.assertRaises(ProtocolError):
            self.write()
        self.assertEqual(other.read_text(), 'operator data')

    def test_missing_effective_context_does_not_fabricate_identity(self):
        with self.assertRaises(ProtocolError):
            self.write(context=None)
        self.assertFalse(self.path.exists())

    def test_policy_permission_is_not_execution_pass(self):
        value = write_receipt(self.path, self.decision, 'scope', 'p', ['edit'])
        self.assertEqual(value['result'], 'PROCEED')


if __name__ == '__main__':
    unittest.main()
