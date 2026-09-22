#!/usr/bin/env bash

set -euo pipefail

REPOSITORY_URL="https://github.com/logxel/agents-tools/archive/refs/heads/main.tar.gz"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

MODE="project"
PROJECT_DIR="$PWD"
MIGRATE=0
ENABLE_AST_GREP=0
ASSUME_YES=0

read_answer() {
  if [[ -r /dev/tty ]]; then
    IFS= read -r "$1" < /dev/tty
  else
    IFS= read -r "$1"
  fi
}

usage() {
  cat <<'EOF'
Usage:
  install-remote.sh [--project DIR] [--enable-ast-grep] [--yes]
  install-remote.sh --user [--enable-ast-grep] [--yes]
  install-remote.sh --migrate-v1-to-v2 [--project DIR] [--enable-ast-grep] [--yes]
  install-remote.sh --user --migrate-v1-to-v2 [--enable-ast-grep] [--yes]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      [[ $# -ge 2 ]] || { usage >&2; exit 1; }
      PROJECT_DIR="$2"
      shift
      ;;
    --user)
      MODE="user"
      ;;
    --migrate-v1-to-v2)
      MIGRATE=1
      ;;
    --enable-ast-grep)
      ENABLE_AST_GREP=1
      ;;
    --yes)
      ASSUME_YES=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
  shift
done

curl -fsSL "$REPOSITORY_URL" | tar -xz -C "$TEMP_DIR" --strip-components=1

SETUP_ARGS=(--install-v2)
[[ "$MIGRATE" == 1 ]] && SETUP_ARGS=(--migrate-v1-to-v2)
[[ "$ASSUME_YES" == 1 ]] && SETUP_ARGS+=(--yes)

if [[ "$MODE" == "project" ]]; then
  SETUP_ARGS+=(--patch-addon --project "$PROJECT_DIR")
  [[ "$ENABLE_AST_GREP" == 1 ]] && SETUP_ARGS+=(--enable-ast-grep)
  bash "$TEMP_DIR/setup-ai.sh" "${SETUP_ARGS[@]}"
  exit 0
fi

bash "$TEMP_DIR/setup-ai.sh" "${SETUP_ARGS[@]}"
GLOBAL_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
mkdir -p "$GLOBAL_DIR/agents" "$GLOBAL_DIR/commands" "$GLOBAL_DIR/skills"
cp -R "$TEMP_DIR/.opencode/agents/." "$GLOBAL_DIR/agents/"
cp -R "$TEMP_DIR/.opencode/commands/." "$GLOBAL_DIR/commands/"
cp -R "$TEMP_DIR/.opencode/skills/." "$GLOBAL_DIR/skills/"

CONFIG_PATH="$GLOBAL_DIR/opencode.json"
if [[ ! -f "$CONFIG_PATH" && -f "$GLOBAL_DIR/opencode.jsonc" ]]; then
  CONFIG_PATH="$GLOBAL_DIR/opencode.jsonc"
fi
CONFIG_PATH="$CONFIG_PATH" node - <<'NODE'
const fs = require("fs")
const path = process.env.CONFIG_PATH
const config = fs.existsSync(path) ? JSON.parse(fs.readFileSync(path, "utf8")) : {}
config.default_agent = "orchestrator"
config.permissions = [
  ...(config.permissions || []).filter(
    (item) => !(item.action === "skill" && item.resource === "opencode-v2-workflow"),
  ),
  { action: "skill", resource: "opencode-v2-workflow", effect: "allow" },
]
fs.writeFileSync(path, `${JSON.stringify(config, null, 2)}\n`)
NODE

if [[ "$ENABLE_AST_GREP" == 1 ]]; then
  if [[ "$ASSUME_YES" != 1 ]]; then
    [[ -r /dev/tty || -t 0 ]] || { printf 'ERROR: enabling AST-grep non-interactively requires --yes\n' >&2; exit 1; }
    printf 'Enable the AST-grep MCP server user-wide? [Y/n] '
    read_answer answer
    [[ -z "$answer" || "$answer" == "y" || "$answer" == "Y" || "$answer" == "yes" ]] || exit 0
  fi
  CONFIG_PATH="$CONFIG_PATH" FRAGMENT_PATH="$TEMP_DIR/.opencode/mcp/ast-grep.jsonc" node - <<'NODE'
const fs = require("fs")
const configPath = process.env.CONFIG_PATH
const fragment = JSON.parse(fs.readFileSync(process.env.FRAGMENT_PATH, "utf8"))
const config = JSON.parse(fs.readFileSync(configPath, "utf8"))
fragment.mcp.servers["ast-grep"].disabled = false
config.mcp = { ...(config.mcp || {}), ...fragment.mcp }
fs.writeFileSync(configPath, `${JSON.stringify(config, null, 2)}\n`)
NODE
fi

printf 'Installed OpenCode V2 addon user-wide in %s\n' "$GLOBAL_DIR"
