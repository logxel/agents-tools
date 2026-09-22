# OpenCode V1 to V2 Migration

Status: validated against the OpenCode V2 documentation on 2026-09-21.

This guide separates migrations that are mostly mechanical from migrations
that require a code port. OpenCode V2 intentionally keeps most file-based
project definitions compatible, but it does not make a V1 plugin or V1 server
client a V2 implementation.

## Executive summary

| Area | V2 status | Action |
| --- | --- | --- |
| `AGENTS.md` | Supported | Keep it; V2 discovers `AGENTS.md` rather than using a `CLAUDE.md` fallback. |
| Skills | Compatible | Keep the complete skill directory. `.agents/skills` is a supported compatibility source; `.opencode/skills` is the preferred V2 project path. |
| Agents | Compatible with a native shape available | Move new agents to `.opencode/agents/<name>.md`; normalize frontmatter when practical. |
| Commands | Compatible with a native shape available | Prefer `.opencode/commands`; rename `subtask` to `subagent` in native V2 definitions. |
| Configuration | Normalized in memory | Convert legacy fields incrementally; keep a V1 backup while testing. |
| Plugins | Breaking change | Port the implementation to `Plugin.define({ id, setup })` or the V2 effect API. Renaming `plugin` to `plugins` is not enough. |
| Server API and clients | Breaking change | Port V1 integrations to `@opencode/client` and the V2 API contract. |
| TUI settings | Migrated to a global client file | V2 uses `~/.config/opencode/cli.json`; the first client startup migrates supported global `tui.json(c)` settings. |

## Safe migration sequence

### 1. Inventory and preserve the V1 setup

Before changing files, record:

```text
opencode.json, opencode.jsonc
.opencode/
AGENTS.md and any CLAUDE.md fallback files
configured plugins and their package versions
integrations using the V1 server API
global ~/.config/opencode files
```

Keep a copy of the original configuration. V1 and V2 use overlapping paths,
so a V1 process must not read a file after it has been converted to a native
V2-only shape.

### 2. Start V2 before rewriting everything

The supported migration order is to start V2 with the existing configuration,
verify models, credentials, agents, permissions, and MCP servers, then port
plugins and API clients. Native V2 normalization can be done afterward.

Use the [official V2 installation and migration documentation](https://opencode.ai/v2/docs/migrate-v1)
for the version-specific installer. Do not assume that a successful binary
upgrade means that third-party plugins are loaded.

### 3. Normalize file-based definitions

#### Agents

Preferred location:

```text
.opencode/agents/<name>.md
```

For native V2 definitions:

- Keep the Markdown body as the system instruction.
- Rename JSON `prompt` to `system`.
- Rename `disable` to `disabled`.
- Rename `permission` to `permissions`.
- Combine `model` and `variant` as `provider/model#variant`.
- Put `temperature`, `top_p`, and provider-specific request settings under
  `request.body`.
- Use `mode: primary`, `mode: subagent`, or `mode: all` deliberately.

V2 can translate supported legacy agent frontmatter, so these edits are a
normalization step rather than a prerequisite for every agent.

#### Commands

Preferred location:

```text
.opencode/commands/<name>.md
```

Keep the command body and its `description` and `agent` fields. Rename
`subtask` to `subagent` when adopting the native V2 field. Combine a separate
`model` and `variant` into the V2 `model` form.

#### Skills

Preferred V2 project location:

```text
.opencode/skills/<skill-id>/SKILL.md
```

The portable compatibility location used by this repository is:

```text
.agents/skills/<skill-id>/SKILL.md
```

OpenCode V2 searches project `.agents/skills` and global `~/.agents/skills`.
Move the whole directory, including `rules/`, `references/`, `scripts/`, and
templates; moving only `SKILL.md` silently breaks relative resources. Keep the
directory ID stable and use a lowercase kebab-case ID that matches the
frontmatter `name` for cross-harness portability.

If both `.agents/skills` and `.opencode/skills` define the same ID, the later
V2 source wins. Use duplicate IDs only when an intentional project override is
required.

#### Instructions

Keep `AGENTS.md` in place. If a V1 workflow depended on a `CLAUDE.md` fallback,
move the applicable instructions into `AGENTS.md`; V2 currently discovers
`AGENTS.md` as its instruction file.

### 4. Port plugins, do not just rename them

V1 configuration:

```jsonc
{
  "plugin": [
    "opencode-example-plugin",
    ["./plugin/local.ts", { "enabled": true }]
  ]
}
```

V2 configuration:

```jsonc
{
  "plugins": [
    "opencode-example-plugin",
    {
      "package": "./plugin/local.ts",
      "options": { "enabled": true }
    }
  ]
}
```

A V2 plugin uses a default export with a stable ID and a `setup(ctx)` or
`effect(ctx)` entrypoint:

```ts
import { Plugin } from "@opencode/plugin"

export default Plugin.define({
  id: "example",
  async setup(ctx) {
    await ctx.storage.set("loaded", true)
    await ctx.tool.hook("execute.before", (event) => {
      // Register V2 hooks through the V2 context.
    })
  },
})
```

Port each hook, tool, transform, event subscription, cleanup function, and
state store separately. V2 groups these capabilities under domains such as
`ctx.tool`, `ctx.session`, `ctx.event`, and `ctx.storage`; there is no promise
that every experimental V1 hook has a one-to-one replacement.

For a temporary support window, one package can expose separate V1 `server()`
and V2 `setup()` implementations. Sharing an export does not translate V1
hooks automatically; test both loaders.

### 5. Port API clients and client settings

V2 has a revised server API and client package. Integrations that call the V1
server API need to move to `@opencode/client` and the released V2 endpoint and
request shapes.

V2 terminal client settings are global in `~/.config/opencode/cli.json`.
Project-local client settings are not migrated into that file. Verify the
resulting client behavior explicitly after the first V2 startup.

## V2 capabilities to use directly

| Capability | What it enables | Replacement design implication |
| --- | --- | --- |
| Primary and subagent modes | A main agent can launch fresh foreground or background child sessions. | Put stable role prompts in V2 agent files and permit only the delegation targets each parent needs. |
| Ordered permissions | `allow`, `ask`, and `deny` can target tools, skills, subagents, paths, web access, and MCP tools. | Treat permissions as the security boundary; do not rely on prompt instructions for safety. |
| On-demand skills | The model sees skill metadata and loads the full body only when selected. | Keep skills focused, progressive, and explicit about which supporting files to read. |
| Skill source precedence | Built-ins, `.agents/skills`, config directories, `.opencode/skills`, and explicit catalogs can coexist. | Use `.agents/skills` for portable repository knowledge and `.opencode/skills` only for intentional V2 overrides. |
| Native model variants | Agents and commands can select `provider/model#variant`; providers can define settings and variants. | Route expensive planning/review to a stronger model and bounded implementation work to a cheaper one. |
| Event, tool, session, storage, and transform plugin domains | V2 plugins can implement runtime behavior beyond Markdown instructions. | Keep runtime automation in a small V2 plugin; do not force it into a skill. |
| Checkpoint-based compaction | V2 compaction keeps a configured token budget around checkpoints. | Store durable task state in files or plugin storage instead of assuming the full transcript survives. |
| CLI API and ACP | V2 exposes server operations and an Agent Client Protocol entrypoint. | Rebuild editor or automation integrations against V2 contracts rather than wrapping V1 endpoints. |

See the [V2 agents](https://opencode.ai/v2/docs/agents),
[V2 skills](https://opencode.ai/v2/docs/skills),
[V2 permissions](https://opencode.ai/v2/docs/permissions),
[V2 plugin](https://opencode.ai/v2/docs/build/plugins), and
[V2 compaction](https://opencode.ai/v2/docs/compaction) references for the
current details.

## Validation checklist

This repository provides an ordered migration helper:

```bash
bash setup-ai.sh --migrate-v1-to-v2
```

It backs up configuration, removes legacy Gem Team and OMOS artifacts before
removing detected OpenCode V1 installations, then installs and verifies
OpenCode V2. It does not install Gem Team, OMOS, APM, or Bun. Claude CLI is
preserved and can be installed independently with `--install-claude`.
Use `--yes` only for an approved non-interactive run. A clean V2 install uses:

```bash
bash setup-ai.sh --install-v2
```

The optional `--patch-addon --project DIR` installs this repository's native
`.opencode` bundle only when the target does not already have `.opencode`;
existing project configuration is never overwritten. Add
`--enable-ast-grep` to enable the tested AST-grep MCP server in that new
project; it remains disabled by default.

Run this checklist against a clean project and each supported model/provider:

- `opencode` starts with the preserved configuration and reports the expected
  V2 version.
- The active model list contains the expected providers and variants.
- The default primary agent is visible and can launch only its permitted
  subagents.
- Each skill appears by its path-derived ID and loads its supporting files.
- A read-only reviewer cannot edit or run shell commands.
- Every migrated command expands its arguments and delegates to the intended
  agent.
- Each plugin appears in the active plugin list, exercises every hook/tool,
  and releases its resources on reload.
- API integrations use V2 client methods and pass a real request/response
  smoke test.
- Compaction preserves the task state needed to continue the workflow.
- V1 is tested separately until the support window ends; do not assume a V2
  config conversion remains valid in V1.

## Sources

- [OpenCode V2 migration guide](https://opencode.ai/v2/docs/migrate-v1)
- [OpenCode V2 plugin migration](https://opencode.ai/v2/docs/build/plugins/migrate-v1)
- [OpenCode V2 configuration](https://opencode.ai/v2/docs/config)
- [OpenCode V2 API reference](https://opencode.ai/v2/docs/api)
