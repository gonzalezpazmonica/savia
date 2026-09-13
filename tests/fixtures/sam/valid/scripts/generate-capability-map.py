#!/usr/bin/env python3
import sys

if sys.argv[1:] == ["--check"]:
    print("SCM: FRESH (1 resources)")
    raise SystemExit(0)
raise SystemExit(2)
