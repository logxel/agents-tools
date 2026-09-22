#!/usr/bin/env bash

set -euo pipefail

ADDON_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR=""
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
  .opencode/install.sh --project <directory> [--enable-ast-grep] [--yes]

Installs the complete native addon into a project that does not already have
an .opencode directory. The script refuses to overwrite an existing V2 setup.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      [[ $# -ge 2 ]] || { usage >&2; exit 1; }
      PROJECT_DIR="$2"
      shift
      ;;
    --enable-ast-grep)
      ENABLE_AST_GREP=1
      ;;
    --yes)
      ASSUME_YES=1
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
  shift
done

[[ -n "$PROJECT_DIR" ]] || { usage >&2; exit 1; }

PROJECT_DIR=$(cd "$PROJECT_DIR" 2>/dev/null && pwd) || {
  printf 'ERROR: project directory does not exist: %s\n' "$PROJECT_DIR" >&2
  exit 1
}

[[ ! -e "$PROJECT_DIR/.opencode" ]] || {
  printf 'ERROR: refusing to overwrite existing %s/.opencode\n' "$PROJECT_DIR" >&2
  exit 1
}

cp -R "$ADDON_DIR" "$PROJECT_DIR/.opencode"
if [[ "$ENABLE_AST_GREP" == 1 ]]; then
  if [[ "$ASSUME_YES" != 1 ]]; then
    [[ -r /dev/tty || -t 0 ]] || {
      printf 'ERROR: enabling AST-grep non-interactively requires --yes\n' >&2
      exit 1
    }
    printf 'Enable the AST-grep MCP server for this project? [Y/n] '
    read_answer answer
    [[ -z "$answer" || "$answer" == "y" || "$answer" == "Y" || "$answer" == "yes" ]] || {
      printf 'AST-grep remains disabled.\n'
      exit 0
    }
  fi
  node - "$PROJECT_DIR/.opencode/opencode.jsonc" "$PROJECT_DIR/.opencode/mcp/ast-grep.jsonc" <<'NODE'
const fs = require("fs")
const [configPath, fragmentPath] = process.argv.slice(2)
const config = JSON.parse(fs.readFileSync(configPath, "utf8"))
const fragment = JSON.parse(fs.readFileSync(fragmentPath, "utf8"))
fragment.mcp.servers["ast-grep"].disabled = false
config.mcp = fragment.mcp
fs.writeFileSync(configPath, `${JSON.stringify(config, null, 2)}\n`)
NODE
  printf 'Enabled AST-grep in %s/.opencode/opencode.jsonc\n' "$PROJECT_DIR"
fi
printf 'Installed OpenCode V2 addon in %s/.opencode\n' "$PROJECT_DIR"
