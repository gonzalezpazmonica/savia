"""Tests del skill python-backed de ejemplo (template)."""

import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from example_skill import run


def test_run_contract():
    assert "OK" in run("a", 3)
