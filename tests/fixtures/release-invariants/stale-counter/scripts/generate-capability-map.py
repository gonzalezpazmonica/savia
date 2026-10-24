#!/usr/bin/env python3
import os
os.makedirs(".scm", exist_ok=True)
open(".scm/INDEX.scm","w").write("# Savia Capability Map — INDEX\n> hash: ab12cd34ef56 | resources: 1\n> 1 commands\n[quality] a — t — script:scripts/a.sh\n")
