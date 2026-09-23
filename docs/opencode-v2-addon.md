# OpenCode V2 Addon Baseline

The repository now contains a minimal native V2 addon under `.opencode/`. It
keeps the portable `.agents/skills` collection unchanged and adds one
OpenCode-specific workflow surface. Its conventions were informed by public
agent workflow examples, but the implementation is native to OpenCode V2.

## What is included

- `skills/opencode-v2-workflow/`: local dated plans under
  `.opencode/state/plans/`, bounded handoffs, wave ownership,
  failure classification, verification, and evidence.
- `agents/orchestrator.md`: the default primary agent that automatically
  classifies work and chooses dated-plan mode.
- `agents/reviewer.md`: a read-only review role with denied edit, shell, and
  delegation permissions.
- V2 built-ins provide `build`, `plan`, `explore`, and `general`; the addon does
  not duplicate them or invent a separate `librarian` role.
- `commands/work.md` and `commands/review.md`: `/work` and `/review` entry
  points.
- `mcp/ast-grep.jsonc`: opt-in structural-search configuration, not enabled by
  default.

This is deliberately not a V2 plugin. The skill and local dated plan cover the
useful planning and verification behavior without adding runtime hooks,
storage, or a fragile V1 plugin port. Add a plugin only after a concrete gap
requires transforms, events, persistent plugin storage, or a new tool.

## What V2 already provides

V2 already provides the agent runtime, native role prompts, child sessions,
permissions, commands, skills, compaction, and MCP integration. Its built-in
`build`, `plan`, `explore`, and `general` agents are sufficient for ordinary
implementation, planning, research, and delegation. The official [agent
documentation](https://opencode.ai/v2/docs/agents) defines those roles and
their modes.

## Why keep the addon

The addon is optional policy, not missing runtime functionality. Its default
`orchestrator` is the small policy layer that V2 does not provide. It adds the
team conventions that V2 does not enforce automatically: complexity routing,
dated plan identity, bounded handoff fields, evidence retention, failure
classification, acceptance gates, and a reviewer with an explicit read-only
permission boundary. Runtime plans live under `.opencode/state/` and should be
ignored locally rather than committed by default. Native agents can perform
this work; the addon makes the process repeatable and reviewable across
repositories.

Without those conventions, use native V2 directly. With them, the default
orchestrator keeps the same primary session and decides when to create a plan;
you do not need to switch to the `plan` agent for ordinary work.

## Use locally

When this repository is the active project, OpenCode reads
`.opencode/opencode.jsonc` and loads the workflow skill. The standard commands
are:

```text
/work migrate the authentication boundary
/review the current changes for regressions and missing evidence
```

Install the V2 client first. The official installer is:

```bash
curl -fsSL https://opencode.ai/v2/install | bash
opencode --version
```

The output must identify the V2 client. Do not use the existing V1 binary with
this V2-native configuration.

For another project, install the complete addon with the repository script:

```bash
git clone https://github.com/logxel/agents-tools ~/.config/opencode/addons/agents-tools
bash ~/.config/opencode/addons/agents-tools/.opencode/install.sh \
  --project /path/to/your/project
```

Then start V2 from the target project:

```bash
cd /path/to/your/project
opencode
```

The project install includes the skill, default `orchestrator`, read-only
`reviewer`, commands, permissions, and catalog. It refuses to overwrite an
existing `.opencode` directory; merge the files manually when the project
already has OpenCode configuration.

For a global installation, copy or symlink the addon’s `agents`, `commands`,
and `skills` into `~/.config/opencode/{agents,commands,skills}` and merge
`"default_agent": "orchestrator"` plus the addon’s skill permission into the
existing global `opencode.jsonc`. Do not replace an existing global config.

OpenCode V2 also supports an HTTP skill catalog. After this repository version
is published, the catalog can be referenced directly:

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "skills": [
    "https://raw.githubusercontent.com/logxel/agents-tools/main/.opencode/skills/"
  ]
}
```

The catalog is `.opencode/skills/index.json`; its version must change whenever
the downloaded skill files change. The HTTP catalog distributes only the
workflow skill. It does not distribute the custom agents, commands, default
agent, permissions, or MCP snippet, so use the project installer for the full
addon.

## Optional AST-grep

Do not enable AST-grep for every machine. Use the CLI for occasional searches:

```bash
npm install --save-dev @ast-grep/cli
ast-grep run --pattern 'oldApi($$$ARGS)' --lang ts src/
```

For repeated model-visible structural searches, merge
`.opencode/mcp/ast-grep.jsonc` into the active V2 config. It is a fragment, so
it deliberately has no `$schema`; the active V2 config owns schema validation.
The server is disabled until explicitly enabled. For a new project, enable it
directly during installation:

```bash
bash .opencode/install.sh --project /path/to/project --enable-ast-grep
```

The installer configures a pinned `ast-grep` CLI through `npx`. Smoke-test one
search and one rule test before permitting rewrites.

The addon also includes `.opencode/mcp/web-research.jsonc` with disabled
templates for Context7 and Playwright. OpenCode V2 already provides native
`websearch` providers for Exa and Firecrawl; configure those with `/connect` or
`websearch.provider` instead of duplicating them as MCP servers. Keep API keys
and headers outside repository configuration.

## Validation baseline

Before replacing the old harnesses, validate the following on a clean V2
machine:

1. `opencode` exposes built-in `build`, `plan`, `explore`, and `general`, plus
   custom `orchestrator`, `reviewer`, `work`, `review`, and
   `opencode-v2-workflow`.
2. `/work` creates or resumes a dated plan and records evidence.
3. `/review` cannot edit, shell, or delegate.
4. The catalog loads every file listed in `index.json`.
5. AST-grep remains absent unless its config is intentionally merged.
6. Repository checks pass: `make skills-validate`, `make opencode-validate`,
   audit verification, and `git diff --check`.

The implementation is intentionally convention-based where Markdown cannot
enforce behavior. V2 permissions and CI remain the enforcement boundary.

## References

- [OpenCode V2 skills](https://opencode.ai/v2/docs/skills)
- [OpenCode V2 agents](https://opencode.ai/v2/docs/agents)
- [OpenCode V2 commands](https://opencode.ai/v2/docs/commands)
- [OpenCode V2 plugins](https://opencode.ai/v2/docs/plugins)
- [OpenCode V2 MCP servers](https://opencode.ai/v2/docs/mcp-servers)
- [Gem Team](https://github.com/mubaidr/gem-team) and
  [OmO](https://github.com/code-yeongyu/oh-my-openagent) are inspiration only;
  neither project is installed or required.
