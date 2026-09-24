# OpenCode V2 Addon

This directory is the native OpenCode V2 surface for the portable workflow in
this repository. It intentionally uses skills, agents, commands, and an
optional MCP snippet instead of a plugin.

Install the complete bundle with [INSTALL.md](INSTALL.md). The longer
repository rationale and migration notes are in
`docs/opencode-v2-addon.md`.

- `skills/opencode-v2-workflow/` contains the portable planning and verification workflow.
- `agents/` contains the default `orchestrator` and custom read-only
  `reviewer`; V2 built-ins provide `build`, `plan`, `explore`, and `general`.
- `commands/` contains `/work` and `/review` prompt entry points.
- `mcp/` contains an opt-in AST-grep configuration; it is not enabled by
  default.

The root `.opencode/opencode.jsonc` loads the workflow locally. For a machine-
wide install, follow the installation options documented in
`docs/opencode-v2-addon.md`.

## Remote installation

From the project you want to configure:

```bash
curl -fsSL https://raw.githubusercontent.com/logxel/agents-tools/main/.opencode/install-remote.sh | bash -s -- --project "$PWD"
```

Enable the tested AST-grep MCP server explicitly when needed; it asks for
confirmation by default:

```bash
curl -fsSL https://raw.githubusercontent.com/logxel/agents-tools/main/.opencode/install-remote.sh | bash -s -- --project "$PWD" --enable-ast-grep
```

For V1 migration, replace `--install-v2` with `--migrate-v1-to-v2`. Add
`--yes` only for an approved non-interactive run. The installer never
overwrites an existing `.opencode` directory.

Install V2 and enable the addon user-wide instead:

```bash
curl -fsSL https://raw.githubusercontent.com/logxel/agents-tools/main/.opencode/install-remote.sh | bash -s -- --user
```

This preserves existing providers and MCP servers. Keep AST-grep project-scoped
unless its `npx` dependency is intentionally accepted user-wide.

## Optional external MCP servers

OpenCode V2 already includes native web search with Exa and Firecrawl
providers. Configure those through `/connect` or `websearch.provider` instead
of adding duplicate MCP servers. The repository templates keep external MCPs
disabled by default. To opt in immediately, run only the commands you need:

```bash
opencode mcp add context7 --global --url https://mcp.context7.com/mcp
opencode mcp add playwright --global -- npx -y @playwright/mcp@latest --headless
opencode mcp add deepwiki --global --url https://mcp.deepwiki.com/mcp
```

Check the connection state with `opencode mcp list`. Use `/mcps` inside
OpenCode to complete OAuth authentication when requested. Playwright downloads
its browser on first use; use the `--headless` flag for terminals or CI without
a graphical display. These commands are optional and are deliberately not
enabled by the addon installer. DeepWiki provides documentation and Q&A for
public GitHub repositories through its hosted read-only MCP server.

`opencode mcp add` enables a server immediately and has no `--disabled` flag.
To register one without enabling it by default, set its local config entry
after adding it:

```bash
server=playwright
config="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/opencode.json"
tmp="$(mktemp)"
jq --arg server "$server" '.mcp.servers[$server].disabled = true' "$config" > "$tmp" && mv "$tmp" "$config"
```

Replace `playwright` with `context7` or `deepwiki` as needed. Remove the
`disabled` property, or set it to `false`, to enable the server later.
