# Context Map — Profile × Command

> **Principle**: Load only needed profile fragments. Less is more.

| Group | Commands | Load | Skip |
|-------|----------|------|------|
| Sprint Daily | sprint-status, sprint-plan, sprint-review, sprint-retro, velocity-trend, sprint-forecast, sprint-autoplan, risk-predict, my-sprint, nl-query, async-standup, ceremony-health | identity, workflow, projects, tone | tools, preferences |
| Reporting | report-hours, report-capacity, report-executive, kpi-dashboard, kpi-dora, dx-dashboard, ceo-report, ceo-alerts, portfolio-overview, incident-postmortem, value-stream-map, stakeholder-report, portfolio-deps, org-metrics, meeting-summarize, capacity-forecast, okr-define, okr-track, okr-align, strategy-map, sprint-release-notes | identity, preferences, projects, tone | workflow, tools |
| PBI & Backlog | pbi-decompose, pbi-decompose-batch, pbi-assign, pbi-plan-sprint, epic-plan, feature-impact, backlog-patterns, pbi-jtbd, pbi-prd, backlog-capture | identity, workflow, projects, tools | preferences, tone |
| Backlog Mgmt | backlog-groom, backlog-prioritize, outcome-track, stakeholder-align, retro-patterns, retro-actions | identity, workflow, projects | tools, preferences, tone |
| Spec & SDD | spec-generate, spec-design, spec-explore, spec-implement, spec-review, spec-verify, spec-status, agent-run, agent-cost, agent-efficiency, agent-trace, agent-notes-archive, my-focus | identity, workflow, projects | tools, preferences, tone |
| Quality & PRs | pr-pending, pr-review, perf-audit, perf-fix, perf-report, qa-dashboard, qa-regression-plan, qa-bug-triage, testplan-generate, testplan-results, testplan-status, my-learning, release-readiness | identity, workflow, tools | projects, preferences, tone |
| Accessibility | a11y-audit, a11y-fix, a11y-report, a11y-monitor | identity, preferences, projects | workflow, tools, tone |
| Infra & Pipelines | pipeline-create, pipeline-run, pipeline-status, pipeline-logs, pipeline-artifacts, devops-validate, mcp-server, webhook-config, integration-status, company-setup, company-edit, company-show, company-vertical, diagram-config | identity, tools, projects | workflow, preferences, tone |
| Governance | compliance-scan, compliance-fix, compliance-report, security-review, security-audit, governance-policy, governance-audit, governance-report, governance-certify, ai-safety-config, ai-confidence, ai-boundary, ai-incident, ai-audit-log, ai-model-card, ai-risk-assessment | identity, projects, preferences | workflow, tools, tone |
| Memory & Context | memory-sync, memory-save, memory-search, memory-context, context-load, session-save, context-optimize, context-age, context-benchmark, context-budget, context-compress, context-defer, context-profile, hub-audit, cross-project-search, memory-compress, memory-importance, memory-graph, memory-prune | identity, projects, preferences | workflow, tools, tone |
| Messaging | notify-slack, notify-whatsapp, notify-nctalk, slack-search, whatsapp-search, nctalk-search, inbox-check, inbox-start | identity, preferences, tone | workflow, tools, projects |
| Company Savia | company-repo, savia-send, savia-inbox, savia-reply, savia-announce, savia-directory, savia-broadcast | identity, preferences, tone | workflow, tools, projects |
| Connectors | confluence-publish, gdrive-upload, jira-sync, jira-connect, github-projects, linear-sync, notion-sync, wiki-sync, wiki-publish, platform-migrate, figma-extract | identity, preferences, projects | workflow, tools, tone |
| Diagrams | diagram-generate, diagram-import, diagram-status | identity, projects, preferences | workflow, tools, tone |
| Architecture & Tech | arch-detect, arch-suggest, arch-compare, arch-fitness, arch-recommend, tech-radar, arch-health, debt-track, debt-analyze, debt-prioritize, debt-budget, code-patterns, dependencies-audit, dependency-map, legacy-assess, sbom-generate | identity, projects, preferences | workflow, tools, tone |
| Daily Health | daily-routine, health-dashboard, flow-metrics, flow-protect, deep-work, prevention-metrics, burnout-radar, workload-balance, sustainable-pace, team-sentiment | identity, workflow, projects, tone | tools, preferences |
| Team & Skills | team-workload, board-flow, team-onboarding, team-evaluate, team-skills-matrix | identity, projects, tone | workflow, tools, preferences |
| Project Mgmt | project-assign, project-audit, project-kickoff, project-release-plan, project-roadmap, adoption-assess, adoption-plan, adoption-sandbox, adoption-track | identity, projects | workflow, tools, preferences, tone |
| Repos & Git | repos-branches, repos-list, repos-pr-create, repos-pr-list, repos-pr-review, repos-search, github-activity, github-issues | identity, tools, projects | workflow, preferences, tone |
| Observability | obs-connect, obs-query, obs-dashboard, obs-status, trace-search, trace-analyze, error-investigate, incident-correlate, sentry-bugs, sentry-health | identity, projects, tools | workflow, preferences, tone |
| Audit & Compliance | audit-trail, audit-export, audit-search, audit-alert, credential-scan, security-alerts, dependencies-audit | identity, projects | workflow, tools, preferences, tone |
| Multi-Tenant | tenant-create, tenant-share | identity, projects | workflow, tools, preferences, tone |
| Verticals | vertical-education, vertical-finance, vertical-healthcare, vertical-legal, vertical-propose | identity, projects, preferences | workflow, tools, tone |
| Banking | banking-detect, banking-bian, banking-eda-validate, banking-data-governance, banking-mlops-audit | identity, projects, preferences, tools | workflow, tone |
| Savia Flow | flow-setup, flow-board, flow-intake, flow-metrics, flow-spec | identity, workflow, projects, tools | preferences, tone |
| E2E Test Harness | docker/savia-test (harness.sh, 6 scenarios, mock+live, CI workflow) | identity, projects | workflow, tools, preferences, tone |
| Knowledge Priming | knowledge-priming.md, role-evolution-ai.md, multimodal-agents.md | identity, projects, preferences | workflow, tools, tone |
| Playbooks | playbook-create, playbook-evolve, playbook-library, playbook-reflect | identity, workflow, projects | tools, preferences, tone |
| Caching | cache-analytics, cache-invalidate, cache-strategy, cache-warm | identity, projects | workflow, tools, preferences, tone |
| DX Metrics | dx-core4, dx-recommendations, dx-survey | identity, projects, preferences | workflow, tools, tone |
| ADR & Decisions | adr-create, risk-log | identity, projects | workflow, tools, preferences, tone |
| Community | contribute, feedback, review-community | identity, preferences | workflow, tools, projects, tone |
| Utilities | help, backup, update, changelog-update, emergency-mode, emergency-plan, validate-filesize, validate-schema, team-privacy-notice, evaluate-repo, review-cache-clear, review-cache-stats, meeting-agenda, worktree-setup | identity | workflow, tools, projects, preferences, tone |
| Profile | profile-edit, profile-setup, profile-show, profile-switch | identity | workflow, tools, projects, preferences, tone |

---

## Agent Rule (role: "Agent")

- **Always load**: identity.md
- **Load if needed**: preferences.md (output_format: yaml/json)
- **Load if project scope**: projects.md
- **Never load**: tone.md, workflow.md, tools.md

Output: Structured YAML/JSON, no narrative, no emojis, no greetings.

---

## Default Rule

If command not listed: load **identity.md** only. When in doubt: **less is more**.
