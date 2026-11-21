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
/hook-profile set minimal # validate and show how to export minimal (security-only)
/hook-profile set strict  # same for strict (extra scrutiny)
/hook-profile set ci      # same for CI mode (non-interactive)
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

`set` writes nothing: the profile is read only from the `SAVIA_HOOK_PROFILE` environment variable, and `~/.savia/hook-profile` is ignored (a file an agent could write would let it lower the guards). Export the variable yourself, or for one command only: `SAVIA_HOOK_PROFILE=ci bash scripts/pr-plan.sh`
