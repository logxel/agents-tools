# Install the OpenCode V2 Addon

## 1. Install OpenCode V2

```bash
curl -fsSL https://opencode.ai/v2/install | bash
opencode --version
```

Confirm that the version is V2. Do not run this addon with an OpenCode V1
binary; the configuration uses native V2 fields.

## 2. Install into a project

Clone this repository and run the bundled installer:

```bash
git clone https://github.com/logxel/agents-tools ~/.config/opencode/addons/agents-tools
bash ~/.config/opencode/addons/agents-tools/.opencode/install.sh \
  --project /path/to/your/project
cd /path/to/your/project
opencode
```

The installer copies the complete `.opencode` directory, including the
default `orchestrator`, read-only `reviewer`, workflow skill, commands,
permissions, and optional MCP configuration. It refuses to overwrite an
existing `.opencode` directory.

## 3. Use it

The default `orchestrator` decides whether work needs a dated plan. You can
also invoke the commands directly:

```text
/work migrate the authentication boundary
/review the current changes for regressions and missing evidence
```

For a project that already has `.opencode`, merge the addon files manually.
The repository-level guide is [`docs/opencode-v2-addon.md`](../docs/opencode-v2-addon.md).

To enable the optional AST-grep MCP server during installation, pass
`--enable-ast-grep` to `.opencode/install.sh`. The default installation keeps
it disabled.

## Migration and setup helper

OpenCode V1 migration, clean V2 installation, Claude CLI opt-in installation,
and addon patching are documented in
[`docs/opencode-v1-to-v2.md`](../docs/opencode-v1-to-v2.md). Keep those
commands centralized there so this file remains focused on installing the
addon itself.
