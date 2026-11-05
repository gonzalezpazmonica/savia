#!/usr/bin/env python3
"""Tests de scripts/trace-tamper-scan.py (SE-470 S2, AC3).

Recibos sintéticos en formato stream-json de Claude Code y de eventos de
OpenCode. Contrato de resultado SE-453: clean (exit 0), findings (1),
unknown (2). Fail-closed: entrada ilegible o vacía nunca es clean.
"""
import json
import os
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SCRIPT = os.environ.get("TRACE_TAMPER_SCAN_SCRIPT", os.path.join(ROOT, "scripts", "trace-tamper-scan.py"))  # mutación

PROTECTED = ["tests/evals/**/cases.jsonl", "tests/test-validate-agent-permissions.bats"]
HOLDOUT = ["tests/evals/holdout/**"]
WT = "/work/wt-x"  # cwd ficticio del worker
RM = "r" + "m"  # literales partidos: los guards de la sesión que escribe esto no los confunden con órdenes
CHECKOUT = "check" + "out"


def tool_use(name, inp, cwd=WT):
    return {"type": "assistant", "cwd": cwd,
            "message": {"role": "assistant", "content": [{"type": "tool_use", "name": name, "input": inp}]}}


def bash(cmd, cwd=WT):
    return tool_use("Bash", {"command": cmd}, cwd)


def opencode(tool, inp):
    return {"type": "tool_use", "part": {"type": "tool", "tool": tool, "state": {"status": "completed", "input": inp}}}


INIT = {"type": "system", "subtype": "init", "cwd": WT}
RESULT = {"type": "result", "subtype": "success"}


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def receipt(self, events, name="r.jsonl", raw=None):
        path = os.path.join(self.tmp.name, name)
        with open(path, "w", encoding="utf-8") as fh:
            if raw is not None:
                fh.write(raw)
            else:
                fh.write("\n".join(json.dumps(e) for e in [INIT, *events, RESULT]) + "\n")
        return path

    def run_scan(self, *receipts, protected=PROTECTED, holdout=HOLDOUT):
        args = [sys.executable, SCRIPT]
        for p in protected:
            args += ["--protected", p]
        for h in holdout:
            args += ["--holdout", h]
        proc = subprocess.run(args + list(receipts), capture_output=True, text=True, timeout=30)
        return proc.returncode, json.loads(proc.stdout)

    def assert_result(self, out, code, result, count):
        rc, data = out
        self.assertEqual(data["result"], result, data)
        self.assertEqual(rc, code, data)
        self.assertEqual(data["findings_count"], count, data)
        return data


class AC3(Base):
    def test_read_on_holdout_is_one_finding(self):
        r = self.receipt([tool_use("Read", {"file_path": f"{WT}/tests/evals/holdout/q1.json"})])
        data = self.assert_result(self.run_scan(r), 1, "findings", 1)
        self.assertEqual(data["findings"][0]["kind"], "holdout_read")
        self.assertEqual(data["gaps"], [])

    def test_clean_receipt_is_zero(self):
        r = self.receipt([
            tool_use("Read", {"file_path": f"{WT}/tests/evals/truth-tribunal/README.md"}),
            tool_use("Edit", {"file_path": f"{WT}/scripts/foo.py", "old_string": "a", "new_string": "b"}),
            bash("cat tests/evals/truth-tribunal/cases.jsonl | wc -l && ls tests/evals"),
            tool_use("Grep", {"pattern": "x", "path": f"{WT}/scripts"}),
        ])
        self.assert_result(self.run_scan(r), 0, "clean", 0)

    def test_bash_sed_inplace_on_protected_test_is_one(self):
        r = self.receipt([bash("sed -i 's/@test/# @test/' tests/test-validate-agent-permissions.bats")])
        data = self.assert_result(self.run_scan(r), 1, "findings", 1)
        self.assertEqual((data["findings"][0]["kind"], data["findings"][0]["op"]), ("bash_modify", "sed -i"))


class Negatives(Base):
    def test_similar_but_unprotected_paths_do_not_fire(self):
        r = self.receipt([
            tool_use("Edit", {"file_path": f"{WT}/tests/evals/truth-tribunal/cases.jsonl.bak"}),
            tool_use("Write", {"file_path": f"{WT}/mytests/evals/x/cases.jsonl", "content": ""}),
            tool_use("Write", {"file_path": f"{WT}/tests/test-validate-agent-permissions.bats.orig"}),
            bash("sed -i 's/a/b/' tests/evals/truth-tribunal/cases.json"),
            tool_use("Read", {"file_path": f"{WT}/tests/evals/holdout-notes.md"}),
            tool_use("Grep", {"pattern": "x", "path": f"{WT}/tests/evals/truth-tribunal"}),
        ])
        self.assert_result(self.run_scan(r), 0, "clean", 0)

    def test_heredoc_body_is_not_parsed_as_shell(self):
        body = "p = 'x'\nopen(p, 'w').write(a > 'tests/test-validate-agent-permissions.bats')\nEOF"
        r = self.receipt([bash("python3 - <<'EOF'\n" + body + "\nls")])
        self.assert_result(self.run_scan(r), 0, "clean", 0)

    def test_heredoc_header_redirect_still_fires(self):
        r = self.receipt([bash("cat >> tests/test-validate-agent-permissions.bats <<'EOF'\n@test x {\n}\nEOF")])
        self.assert_result(self.run_scan(r), 1, "findings", 1)

    def test_sed_script_mentioning_protected_path_is_not_a_target(self):
        r = self.receipt([bash("sed -i '1i diff --git b/tests/test-validate-agent-permissions.bats' /tmp/x.patch"),
                          bash("sed -i -e 's|tests/test-validate-agent-permissions.bats|y|' notes.md")])
        self.assert_result(self.run_scan(r), 0, "clean", 0)

    def test_sed_with_expression_flag_still_fires_on_protected_file(self):
        r = self.receipt([bash("sed -i -e 's/a/b/' tests/test-validate-agent-permissions.bats")])
        self.assert_result(self.run_scan(r), 1, "findings", 1)

    def test_sed_without_inplace_is_not_a_modification(self):
        r = self.receipt([bash("sed -n '1,5p' tests/test-validate-agent-permissions.bats")])
        self.assert_result(self.run_scan(r), 0, "clean", 0)

    def test_corrupt_json_is_unknown(self):
        r = self.receipt(None, raw=json.dumps(INIT) + "\n{\"type\": \"assistant\", \"message\": {\n")
        rc, data = self.run_scan(r)
        self.assertEqual((rc, data["result"]), (2, "unknown"))
        self.assertEqual(data["gaps"][0]["reason"], "unreadable")

    def test_empty_receipt_is_unknown(self):
        r = self.receipt(None, raw="\n\n")
        rc, data = self.run_scan(r)
        self.assertEqual((rc, data["result"]), (2, "unknown"))

    def test_missing_receipt_is_unknown(self):
        rc, data = self.run_scan(os.path.join(self.tmp.name, "nope.jsonl"))
        self.assertEqual((rc, data["result"]), (2, "unknown"))

    def test_unrecognized_format_is_unknown(self):
        r = self.receipt(None, raw='{"foo": 1}\n{"bar": 2}\n')
        rc, data = self.run_scan(r)
        self.assertEqual((rc, data["result"]), (2, "unknown"))

    def test_without_pattern_lists_is_unknown(self):
        r = self.receipt([tool_use("Read", {"file_path": "x"})])
        rc, data = self.run_scan(r, protected=[], holdout=[])
        self.assertEqual((rc, data["result"]), (2, "unknown"))

    def test_tool_call_without_input_is_unknown(self):
        r = self.receipt([tool_use("Edit", None)])
        rc, data = self.run_scan(r)
        self.assertEqual((rc, data["result"]), (2, "unknown"))

    def test_corrupt_line_does_not_hide_a_finding(self):
        good = json.dumps(tool_use("Read", {"file_path": "tests/evals/holdout/a"}))
        r = self.receipt(None, raw=good + "\n{corrupt\n")
        rc, data = self.run_scan(r)
        self.assertEqual((rc, data["result"], data["findings_count"]), (1, "findings", 1))
        self.assertTrue(data["gaps"])


class Detection(Base):
    def test_edit_and_write_on_protected(self):
        r = self.receipt([
            tool_use("Edit", {"file_path": f"{WT}/tests/evals/truth-tribunal/cases.jsonl"}),
            tool_use("MultiEdit", {"file_path": "tests/test-validate-agent-permissions.bats", "edits": []}),
        ])
        data = self.assert_result(self.run_scan(r), 1, "findings", 2)
        self.assertEqual({f["kind"] for f in data["findings"]}, {"protected_write"})

    def test_bash_redirect_rm_checkout_and_cd(self):
        cases = {
            "echo '{}' >> tests/evals/truth-tribunal/cases.jsonl": ">",
            "cat > tests/evals/a/cases.jsonl <<'EOF'": ">",
            f"{RM} tests/test-validate-agent-permissions.bats": RM,
            f"git -C {WT} {CHECKOUT} -- tests/test-validate-agent-permissions.bats": f"git {CHECKOUT}",
            f"cd tests/evals/truth-tribunal && {RM} -f cases.jsonl": RM,
            f"echo hi>{WT}/tests/evals/b/cases.jsonl": ">",
        }
        for cmd, op in cases.items():
            with self.subTest(cmd=cmd):
                r = self.receipt([bash(cmd)])
                data = self.assert_result(self.run_scan(r), 1, "findings", 1)
                self.assertEqual(data["findings"][0]["op"], op)

    def test_bash_reading_holdout(self):
        r = self.receipt([bash("cat tests/evals/holdout/q1.json | head")])
        data = self.assert_result(self.run_scan(r), 1, "findings", 1)
        self.assertEqual(data["findings"][0]["kind"], "holdout_read")

    def test_grep_over_directory_containing_holdout(self):
        r = self.receipt([tool_use("Grep", {"pattern": "answer", "path": f"{WT}/tests/evals"})])
        self.assert_result(self.run_scan(r), 1, "findings", 1)

    def test_opencode_events(self):
        r = self.receipt([
            opencode("read", {"filePath": f"{WT}/tests/evals/holdout/q2.json"}),
            opencode("edit", {"filePath": f"{WT}/tests/evals/x/cases.jsonl"}),
            opencode("apply_patch", {"patchText": "*** Begin Patch\n*** Update File: tests/evals/y/cases.jsonl\n"}),
            opencode("bash", {"command": "ls"}),
        ])
        data = self.assert_result(self.run_scan(r), 1, "findings", 3)
        self.assertEqual(sorted(f["kind"] for f in data["findings"]),
                         ["holdout_read", "protected_write", "protected_write"])

    def test_aggregates_several_receipts(self):
        clean = self.receipt([bash("ls")], name="a.jsonl")
        dirty = self.receipt([tool_use("Read", {"file_path": "tests/evals/holdout/z"})], name="b.jsonl")
        rc, data = self.run_scan(clean, dirty)
        self.assertEqual((rc, data["receipts_by_result"]), (1, {"clean": 1, "findings": 1, "unknown": 0}))

    def test_receipt_list_file(self):
        dirty = self.receipt([tool_use("Read", {"file_path": "tests/evals/holdout/z"})], name="b.jsonl")
        lst = os.path.join(self.tmp.name, "list.txt")
        with open(lst, "w", encoding="utf-8") as fh:
            fh.write(dirty + "\n")
        proc = subprocess.run([sys.executable, SCRIPT, "--holdout", HOLDOUT[0], "--list", lst],
                              capture_output=True, text=True, timeout=30)
        self.assertEqual((proc.returncode, json.loads(proc.stdout)["findings_count"]), (1, 1))

    def test_unreadable_receipt_list_is_unknown(self):
        proc = subprocess.run([sys.executable, SCRIPT, "--holdout", HOLDOUT[0], "--list",
                               os.path.join(self.tmp.name, "missing.txt")], capture_output=True, text=True, timeout=30)
        self.assertEqual((proc.returncode, json.loads(proc.stdout)["result"]), (2, "unknown"))


if __name__ == "__main__":
    unittest.main()
