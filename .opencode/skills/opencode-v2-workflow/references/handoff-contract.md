# Handoff Contract

Every delegated task should carry only the smallest useful contract:

```yaml
plan_id: <YYYYMMDD-slug>
task_id: T1
objective: Implement the requested V2 change
owner: implementer
constraints:
  - Keep the addon plugin-free
  - Keep changes within the assigned repository scope
relevant_evidence:
  - docs/opencode-v1-to-v2.md
acceptance:
  - Native V2 files are in .opencode/
  - The catalog lists every downloaded file
  - Repository validation passes
```

The delegate returns a compact result:

```yaml
status: completed
changed_files:
  - .opencode/skills/opencode-v2-workflow/opencode-v2-workflow.md
evidence:
  - make skills-validate
risks: []
next_action: Run the OpenCode V2 smoke test on a clean machine
```

For review or research, set `status: read-only` and return findings instead of
editing files. If the objective, scope, or acceptance checks change, stop and
request a replan rather than silently widening the task.
