"""CodeQL #54/#55 (py/insecure-temporary-file) in zeroclaw/savia-voice/tts.py.

tempfile.mktemp() returns a free name in the shared temp dir without creating
it; edge-tts/ffmpeg then write to that path, so a planted file or symlink wins
the race. The fallback now writes inside a private mkdtemp() directory.
"""
import importlib.util
import os
import stat
import sys
import types
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
TTS_PATH = ROOT / "zeroclaw" / "savia-voice" / "tts.py"


def _load_tts():
    # numpy/sounddevice are runtime deps of the voice daemon, not of CI.
    stubs = {"numpy": types.ModuleType("numpy"),
             "sounddevice": types.ModuleType("sounddevice")}
    with patch.dict(sys.modules, stubs):
        spec = importlib.util.spec_from_file_location("savia_tts_under_test", TTS_PATH)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
    return module


tts = _load_tts()


class EdgeTempfileTests(unittest.TestCase):
    def _run_synth(self, returncode):
        seen = []

        def fake_run(cmd, **_kwargs):
            out = cmd[cmd.index("--write-media") + 1]
            parent = Path(out).parent
            seen.append((out, stat.S_IMODE(parent.stat().st_mode), parent))
            return types.SimpleNamespace(returncode=returncode)

        synth = object.__new__(tts.TTSSynthesizer)
        synth.lead_in = 0
        with patch.object(tts.tempfile, "mktemp",
                          side_effect=AssertionError("mktemp is racy")), \
                patch.object(tts.subprocess, "run", side_effect=fake_run):
            result = synth._synth_edge("hola")
        return result, seen

    def test_media_is_written_inside_a_private_directory(self):
        result, seen = self._run_synth(returncode=1)
        self.assertIsNone(result)
        out, mode, parent = seen[0]
        self.assertEqual(mode, 0o700)
        self.assertNotEqual(parent, Path(tts.tempfile.gettempdir()))

    def test_private_directory_is_removed_afterwards(self):
        _result, seen = self._run_synth(returncode=1)
        self.assertFalse(os.path.exists(seen[0][2]))


if __name__ == "__main__":
    unittest.main()
