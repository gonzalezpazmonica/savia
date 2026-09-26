---
name: hook-profile
description: View or change the active SAVIA_HOOK_PROFILE (minimal/standard/strict/ci)
argument-hint: "[get|set <profile>|list]"
allowed-tools: [Bash, Read]
model_tier: fast
context_cost: low
tier: core
---

# /hook-profile

Manage the active Savia hook profile. Hook profiles control which of the 22+ hooks run during your session, letting you reduce friction in CI/CD environments or increase scrutiny before critical deployments.

## Usage

```
/hook-profile             # show active profile
/hook-profile get         # same as above
/hook-profile list        # list all profiles with descriptions
/hook-profile set minimal # switch to minimal (security-only)
/hook-profile set standard # switch to standard (default)
/hook-profile set strict  # switch to strict (extra scrutiny)
/hook-profile set ci      # switch to CI mode (non-interactive)
```

## Execution

Run the command:

```bash
bash scripts/hook-profile.sh $ARGUMENTS
```

If no arguments, run:

```bash
bash scripts/hook-profile.sh list
```

## Profiles at a glance

| Profile | Gates active | Best for |
|---------|-------------|----------|
| `minimal` | Security only | Demos, onboarding, hook debugging |
| `standard` | Security + quality | Daily work (default) |
| `strict` | All hooks | Pre-release, critical code |
| `ci` | Standard (non-interactive) | CI/CD pipelines |

## Note

The profile persists to `~/.savia/hook-profile`. To override for one command only, use the env var: `SAVIA_HOOK_PROFILE=ci bash scripts/pr-plan.sh`
