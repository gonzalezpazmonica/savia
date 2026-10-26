"""Skip a parity test locally when a tool is missing, but fail it where the parity must be proven.

With SAVIA_DUAL_CLI_STRICT=1 (set by CI) a missing `bun` or `jq` is a failure, not a silent skip:
otherwise "same decisions in both cores" would be a claim nobody checks (SE-392 review, PR #1356).
"""
import os
import shutil
import unittest


def needs(*tools):
    missing = [tool for tool in tools if shutil.which(tool) is None]
    if not missing:
        return lambda cls: cls
    reason = f"needs {', '.join(missing)}"
    if os.environ.get("SAVIA_DUAL_CLI_STRICT") != "1":
        return unittest.skip(reason)

    def fail(cls):
        def set_up_class(_cls):
            raise AssertionError(f"SAVIA_DUAL_CLI_STRICT=1 and {reason}: parity cannot be verified")
        cls.setUpClass = classmethod(set_up_class)
        return cls
    return fail
