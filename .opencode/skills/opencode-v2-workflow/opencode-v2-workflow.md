---
name: opencode-v2-workflow
description: Route medium and high-risk coding work through dated plans, bounded delegation, verification gates, failure triage, and durable evidence on OpenCode V2.
license: MIT
metadata:
  version: "0.1.0"
  source: logxel/agents-tools
---

# OpenCode V2 Workflow

Use this skill for multi-step implementation, migrations, debugging, reviews,
or investigations. Do not add ceremony to a trivial, single-file change.

## Route

1. Classify the request as `TRIVIAL`, `LOW`, `MEDIUM`, or `HIGH` from the
   supplied evidence. Mark architecture, contract, migration, security,
   schema, shared-state, and irreversible changes as risk signals.
2. For `MEDIUM` or `HIGH`, find or create `docs/plans/YYYYMMDD-<slug>.md`.
   Use `YYYYMMDD.md` only when one active task per day is guaranteed.
3. Give each task one owner, explicit acceptance checks, dependencies, and a
   non-overlapping file boundary. Independent tasks may be delegated, but do
   not assume parallel execution unless the runtime reports it.
4. Keep research and review read-only. Send delegates only the objective,
   constraints, relevant evidence, and acceptance criteria; do not dump the
   whole transcript.

Use OpenCode V2 built-ins instead of recreating equivalent agents:

- `build`: native primary implementation and final synthesis when selected;
- `plan`: primary planning without ordinary project edits;
- `explore`: read-only repository discovery;
- `general`: bounded multi-step subagent work.

The custom `orchestrator` is the default primary agent and performs the
primary routing and synthesis in this addon. Use the custom `reviewer` only
for an independent read-only review boundary. Users should not need to switch
agents for ordinary work. The built-in `build` agent remains available as the
native coding fallback, and `plan` remains available for explicit
planning-only sessions. There is no built-in `librarian`: use `explore` for
repository discovery, `websearch`/`webfetch` for web research, and connected
MCP tools for specialized services.

Read [references/handoff-contract.md](references/handoff-contract.md) before a
non-trivial delegation and [references/plan-template.md](references/plan-template.md)
when creating a plan.

## Execute and verify

- Work in dependency order and update the active plan after each meaningful
  step: `status`, `updated`, task checkboxes, evidence, and `Next action`.
- Keep detailed command output in a dated evidence file when it is useful for
  resuming or review.
- Run focused checks for the changed surface, then broader repository checks
  when the change crosses boundaries.
- Classify a failure before retrying: `retryable`, `fixable`, `flaky`,
  `regression`, `blocked`, or `replan-required`. Retry only with new evidence
  and a bounded count.
- Do not report completion until acceptance checks and verification evidence
  are recorded. Read [references/verification-matrix.md](references/verification-matrix.md)
  for the final gate.

After compaction or restart, if an active plan exists, read that plan and its
evidence first, then resume the first unchecked task. A Markdown plan is a
durable convention, not a runtime-enforced state machine.

## Structural search

Use the built-in `glob`, `grep`, and `read` tools for ordinary repository
search. If an `ast-grep` MCP server is connected, use its structural tools for
AST queries and rule testing; otherwise use the `ast-grep` CLI when installed.
Use the opt-in `.opencode/mcp/` configuration only when that capability is
needed. Never run a rewrite without an explicit scope and a reviewable diff.

## Completion report

For planned work, report the plan ID and objective, completed and blocked
tasks, files changed, verification commands and results, residual risk, and
the next action. For unplanned work, report the objective, files changed,
verification results, residual risk, and next action. Promote only stable,
repeated patterns into a new skill; keep task-specific notes in the dated
plan.
