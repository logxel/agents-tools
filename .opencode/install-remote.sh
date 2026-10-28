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
INSTALL_ARGS=(--user)
[[ "$ENABLE_AST_GREP" == 1 ]] && INSTALL_ARGS+=(--enable-ast-grep)
bash "$TEMP_DIR/.opencode/install.sh" "${INSTALL_ARGS[@]}"
