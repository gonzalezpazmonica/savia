"""Isolated hook-engine tests; fixtures never install hooks or use the network."""
import json
from pathlib import Path
import sys
import unittest

CORE = Path(__file__).resolve().parents[2] / "scripts/dual-cli"
sys.path.insert(0, str(CORE))

from hooks import HookEngine


class HookEngineTests(unittest.TestCase):
    def test_regex_and_glob_matchers_run_only_for_matching_tool(self):
        calls = []

        def prompt_transport(handler, payload, timeout):
            calls.append((handler, json.loads(payload), timeout))
            return {"ok": True}

        engine = HookEngine(prompt_transport=prompt_transport)
        payload = {"tool_name": "Bash", "tool_input": {"command": "git commit -m test"}}
        rules = [
            {"matcher": "Read", "hooks": [{"type": "prompt", "prompt": "skip"}]},
            {"matcher": ".*", "hooks": [{"type": "prompt", "prompt": "regex"}]},
            {"matcher": "Bash(git commit*)", "hooks": [{"type": "prompt", "prompt": "glob"}]},
        ]

        result = engine.evaluate("PreToolUse", payload, rules)

        self.assertEqual(result["action"], "allow")
        self.assertEqual([call[0]["prompt"] for call in calls], ["regex", "glob"])
        self.assertEqual(calls[0][1], payload)


if __name__ == "__main__":
    unittest.main()
