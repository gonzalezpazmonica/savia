"""Synthetic probes must not grant operational authority or write profiles."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

CORE = Path(__file__).resolve().parents[2] / 'scripts/dual-cli'


class DoctorIntegrityTests(unittest.TestCase):
    def invoke(self, *args):
        return subprocess.run([sys.executable, str(CORE / 'codex_profile.py'), *args],
            env=dict(os.environ, SAVIA_CODEX_TEST_MODE='1'), capture_output=True, text=True, timeout=10)

    def test_synthetic_probe_never_verifies_l2(self):
        result = self.invoke('probe', '--sandbox-probe', '/bin/true', '--enforcement-probe', '/bin/true')
        evidence = json.loads(result.stdout)
        self.assertFalse(evidence['passed'])
        self.assertIsNone(evidence['max_verified_risk'])
        self.assertEqual(evidence['evidence_type'], 'SYNTHETIC')

    def test_synthetic_configuration_cannot_write_profile(self):
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder) / 'profile.toml'
            result = self.invoke('configure', '--target', str(target), '--sandbox-probe', '/bin/true',
                                 '--enforcement-probe', '/bin/true')
            self.assertEqual(result.returncode, 2)
            self.assertFalse(target.exists())

    def test_synthetic_evidence_is_retained_only_as_nonoperational(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / 'evidence.json'
            result = self.invoke('evidence', '--output', str(output), '--sandbox-probe', '/bin/true',
                                 '--enforcement-probe', '/bin/true')
            self.assertEqual(result.returncode, 2)
            evidence = json.loads(output.read_text())
            self.assertFalse(evidence['passed'])
            self.assertEqual(evidence['evidence_type'], 'SYNTHETIC')
