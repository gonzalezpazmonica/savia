---
version_bump: patch
section: Fixed
---

### Fixed

- Los hooks PostToolUse agent-trace-log y bash-output-compress leen la entrada JSON por stdin (hook_read_posttool); antes leían variables TOOL_* que ningún runtime define y no hacían nada.

