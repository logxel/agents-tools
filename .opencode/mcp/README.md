# Optional MCP Tools

The baseline does not require an MCP server. OpenCode V2 already provides the
workflow surface through skills, agents, commands, permissions, and local
files. Add a server only when the repository has a repeated need that a CLI or
script cannot cover transparently.

The AST-grep example in `ast-grep.jsonc` is an opt-in fragment, marked
disabled, and intentionally has no `$schema` because it is not a complete
OpenCode config. Merge its `mcp.servers` object into the active
`opencode.jsonc`, or run `.opencode/install.sh --project DIR
--enable-ast-grep` for a new project. The installer enables the server and
configures `npx` to provide the pinned `ast-grep` CLI. Verify with:

```bash
opencode mcp list
```

Pin the server source for team use and smoke-test search and rule testing
before allowing rewrites. Do not put credentials in this file.

## Optional web and browser MCPs

`web-research.jsonc` contains disabled templates for three complementary
servers:

- `context7`: current library and API documentation.
- `playwright`: browser interaction and end-to-end inspection; requires Node.js.
- `deepwiki`: documentation and Q&A for public GitHub repositories.

Merge the desired entries into the active `mcp.servers` object, remove their
`"disabled": true` field, and authenticate when prompted. Never commit API
keys or headers. OpenCode V2 already provides native `websearch` providers for
Exa and Firecrawl, so do not add duplicate MCP servers for those services.
Playwright runs locally through `npx`.
