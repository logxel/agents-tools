#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="install-v2"
PATCH_ADDON=0
ENABLE_AST_GREP=0
INSTALL_CLAUDE=0
TARGET_PROJECT="$PWD"
ASSUME_YES=0
INITIAL_PATH="$PATH"

if [[ -t 1 ]]; then
  GREEN=$'\033[0;32m'
  YELLOW=$'\033[1;33m'
  RED=$'\033[0;31m'
  RESET=$'\033[0m'
else
  GREEN='' YELLOW='' RED='' RESET=''
fi

ok() { printf '%s[ok]%s %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '%s[warn]%s %s\n' "$YELLOW" "$RESET" "$*" >&2; }
die() { printf '%s[error]%s %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }

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
  setup-ai.sh [--install-v2] [--patch-addon] [--enable-ast-grep] [--install-claude] [--project DIR]
  setup-ai.sh --migrate-v1-to-v2 [--yes] [--patch-addon] [--enable-ast-grep] [--install-claude] [--project DIR]

Actions:
  --install-v2          Installs OpenCode V2 only; never replaces V1.
  --migrate-v1-to-v2    Backs up and removes V1, Gem Team, and OMOS; installs V2.
  --patch-addon         Installs this repository's .opencode addon.
  --enable-ast-grep     Explicitly enables AST-grep when installing the addon.
  --install-claude      Installs Claude CLI independently.
  --project DIR         Addon target project (default: cwd).
  --yes                 Confirms migration and installation without prompting.
  -h, --help            Shows this help.

Claude CLI is installed only when explicitly requested.
EOF
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

add_local_paths() {
  export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$HOME/.bun/bin:$PATH"
}

ensure_opencode_path() {
  local original_path="$1"
  local binary_path binary_dir shell_name rc_file marker
  binary_path="$(command -v opencode 2>/dev/null || true)"
  [[ -n "$binary_path" ]] || return 0
  binary_dir="$(dirname "$binary_path")"

  case ":$original_path:" in
    *":$binary_dir:"*) return 0 ;;
  esac

  shell_name="${SHELL:-}"
  shell_name="${shell_name##*/}"
  case "$shell_name" in
    zsh) rc_file="$HOME/.zshrc" ;;
    bash) rc_file="$HOME/.bashrc" ;;
    *)
      warn "OpenCode is installed at $binary_path, but $shell_name may not include its directory in PATH. Add $binary_dir to your shell startup file."
      return 0
      ;;
  esac

  marker="# Added by agents-tools setup-ai.sh"
  if [[ -f "$rc_file" ]] && grep -Fqx "$marker" "$rc_file"; then
    ok "OpenCode PATH is configured in $rc_file. Run 'source $rc_file' or restart your shell."
    return 0
  fi

  if {
    [[ ! -s "$rc_file" ]] || printf '\n'
    printf '%s\n' \
      "$marker" \
      'for path_entry in "$HOME/.local/bin" "$HOME/.opencode/bin" "$HOME/.bun/bin"; do' \
      '  if [[ -d "$path_entry" ]]; then' \
      '    case ":$PATH:" in' \
      '      *":$path_entry:"*) ;;' \
      '      *) PATH="$path_entry:$PATH" ;;' \
      '    esac' \
      '  fi' \
      'done' \
      'export PATH'
  } >> "$rc_file"; then
    ok "Added OpenCode directories to $rc_file. Run 'source $rc_file' or restart your shell."
  else
    warn "Could not update $rc_file. Add $binary_dir to PATH in your shell startup file."
  fi
}

is_v2_version() {
  local version="${1:-}"
  [[ "$version" == opencode\ v2* || "$version" == 2.* ]]
}

current_opencode_version() {
  add_local_paths
  command -v opencode >/dev/null 2>&1 || return 1
  opencode --version 2>/dev/null || true
}

is_v2_installed() {
  is_v2_version "$(current_opencode_version)"
}

preflight() {
  require_command curl
  require_command python3
  add_local_paths
}

backup_v1_state() {
  local backup_root="${XDG_STATE_HOME:-$HOME/.local/state}/agents-tools/opencode-v1-to-v2/$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$backup_root"

  local path
  for path in \
    "${XDG_CONFIG_HOME:-$HOME/.config}/opencode/opencode.json" \
    "${XDG_CONFIG_HOME:-$HOME/.config}/opencode/opencode.jsonc" \
    "${XDG_CONFIG_HOME:-$HOME/.config}/opencode/tui.json" \
    "${XDG_CONFIG_HOME:-$HOME/.config}/opencode/tui.jsonc" \
    "$PWD/opencode.json" "$PWD/opencode.jsonc" \
    "$PWD/.opencode/opencode.json" "$PWD/.opencode/opencode.jsonc" \
    "$PWD/apm.yml" "$PWD/apm.lock.yaml"; do
    if [[ -f "$path" ]]; then
      mkdir -p "$backup_root/$(dirname "${path#${HOME}/}")"
      cp -p "$path" "$backup_root/${path#${HOME}/}"
    fi
  done

  ok "Backup created at $backup_root"
}

uninstall_legacy_gem_team() {
  if command -v apm >/dev/null 2>&1; then
    apm uninstall mubaidr/gem-team >/dev/null 2>&1 || true
  fi

  local path
  for path in \
    "$PWD/.agents/agents" "$PWD/.opencode/agents" "$HOME/.config/opencode/agents" \
    "$HOME/.config/opencode"; do
    [[ -d "$path" ]] || continue
    find "$path" -maxdepth 1 -type f -name 'gem-*.md' -delete
  done

  rm -rf "$PWD/apm_modules/mubaidr/gem-team"
  ok "Removed Gem Team artifacts, if present"
}

uninstall_legacy_omos() {
  local config_path
  while IFS= read -r config_path; do
    [[ -n "$config_path" ]] || continue
    CONFIG_PATH="$config_path" python3 - <<'PY'
import json
import os
import shutil
import tempfile
from pathlib import Path

path = Path(os.environ["CONFIG_PATH"])
try:
    text = path.read_text()
    clean = "\n".join(line for line in text.splitlines() if not line.lstrip().startswith("//"))
    config = json.loads(clean)
except (OSError, json.JSONDecodeError):
    raise SystemExit(0)

def is_omos(value):
    if isinstance(value, str):
        return "oh-my-opencode-slim" in value
    if isinstance(value, list):
        return any(is_omos(item) for item in value)
    if isinstance(value, dict):
        return any(is_omos(item) for item in value.values())
    return False

changed = False
for key in ("plugin", "plugins"):
    plugins = config.get(key)
    if not isinstance(plugins, list):
        continue
    filtered = [item for item in plugins if not is_omos(item)]
    if filtered != plugins:
        changed = True
        if filtered:
            config[key] = filtered
        else:
            config.pop(key, None)

agents = config.get("agent")
if isinstance(agents, dict):
    for name in ("explore", "general"):
        value = agents.get(name)
        if isinstance(value, dict) and value.get("disable") is True:
            agents.pop(name, None)
            changed = True
    if not agents:
        config.pop("agent", None)

if not changed:
    raise SystemExit(0)

backup = path.with_name(path.name + ".bak")
shutil.copy2(path, backup)
with tempfile.NamedTemporaryFile("w", dir=path.parent, delete=False) as handle:
    json.dump(config, handle, indent=2)
    handle.write("\n")
    temporary = Path(handle.name)
os.replace(temporary, path)
print(f"OMOS removido de {path}")
PY
  done < <(
    printf '%s\n' \
      "${XDG_CONFIG_HOME:-$HOME/.config}/opencode/opencode.json" \
      "${XDG_CONFIG_HOME:-$HOME/.config}/opencode/opencode.jsonc" \
      "${XDG_CONFIG_HOME:-$HOME/.config}/opencode/tui.json" \
      "${XDG_CONFIG_HOME:-$HOME/.config}/opencode/tui.jsonc" \
      "$PWD/opencode.json" "$PWD/opencode.jsonc" \
      "$PWD/.opencode/opencode.json" "$PWD/.opencode/opencode.jsonc" \
      "$HOME/.config/opencode/oh-my-opencode.json" \
      "$HOME/.config/opencode/oh-my-opencode.jsonc"
  )

  rm -rf "$HOME/.config/opencode/oh-my-opencode" "$HOME/.config/opencode/oh-my-opencode-slim"
  ok "Removed OMOS from configuration, if present"
}

uninstall_v1_opencode() {
  add_local_paths
  local binary=""
  binary="$(command -v opencode 2>/dev/null || true)"

  if [[ -z "$binary" ]]; then
    ok "OpenCode V1 installation not found"
  elif is_v2_installed; then
    ok "OpenCode V2 is already installed; leaving it in place"
  else
    local resolved="$(readlink -f "$binary" 2>/dev/null || printf '%s' "$binary")"
    if [[ "$resolved" == *"/.bun/install/global"* ]] && command -v bun >/dev/null 2>&1; then
      bun remove --global opencode-ai || true
    elif [[ "$resolved" == *"/node_modules/opencode-ai"* ]] && command -v npm >/dev/null 2>&1; then
      npm uninstall --global opencode-ai || true
    fi
    rm -f "$HOME/.opencode/bin/opencode"
    hash -r 2>/dev/null || true
    if command -v opencode >/dev/null 2>&1 && ! is_v2_installed; then
      die "Could not remove OpenCode V1: $(current_opencode_version)"
    fi
    ok "Removed OpenCode V1"
  fi
}

install_v2() {
  add_local_paths
  if is_v2_installed; then
    ok "OpenCode V2 is already installed: $(current_opencode_version)"
    ensure_opencode_path "$INITIAL_PATH"
    return
  fi

  if command -v opencode >/dev/null 2>&1; then
    die "Detected $(current_opencode_version). Use --migrate-v1-to-v2 to replace V1."
  fi

  ok "Installing OpenCode V2 with the official installer"
  CI=true curl -fsSL https://opencode.ai/v2/install | bash
  add_local_paths
  is_v2_installed || die "Installation finished, but OpenCode V2 was not detected"
  ok "Installed OpenCode V2: $(current_opencode_version)"
  ensure_opencode_path "$INITIAL_PATH"
}

confirm_install() {
  [[ "$ASSUME_YES" == 1 ]] && return
  [[ -r /dev/tty || -t 0 ]] || die "Non-interactive installation requires --yes"
  printf 'OpenCode V2 will be installed with the official installer. Continue? [Y/n] '
  read_answer answer
  [[ -z "$answer" || "$answer" == "y" || "$answer" == "Y" || "$answer" == "yes" ]] || die "Installation cancelled"
}

install_claude() {
  if command -v claude >/dev/null 2>&1; then
    ok "Claude CLI is already installed ($(claude --version 2>&1))"
    return 0
  fi

  echo ""
  echo "  -- Installing Claude CLI --"
  if curl -fsSL https://claude.ai/install.sh | bash; then
    add_local_paths
    if command -v claude >/dev/null 2>&1; then
      ok "Installed Claude CLI ($(claude --version 2>&1))"
    else
      die "Claude CLI was installed but not found in PATH. Restart your shell or add ~/.local/bin to PATH."
    fi
  else
    die "Claude CLI installation failed. Try manually: curl -fsSL https://claude.ai/install.sh | bash"
  fi
}

patch_addon() {
  local project="$(cd "$TARGET_PROJECT" && pwd)"
  if [[ "$project" == "$ROOT_DIR" ]]; then
    make -C "$ROOT_DIR" opencode-validate
    ok "The addon is already in this repository"
    return
  fi

  if [[ "$ENABLE_AST_GREP" == 1 ]]; then
    "$ROOT_DIR/.opencode/install.sh" --project "$project" --enable-ast-grep
  else
    "$ROOT_DIR/.opencode/install.sh" --project "$project"
  fi
  ok "OpenCode V2 addon installed in $project/.opencode"
}

confirm_migration() {
  [[ "$ASSUME_YES" == 1 ]] && return
  [[ -r /dev/tty || -t 0 ]] || die "Non-interactive migration requires --yes"
  printf 'V1, Gem Team, and OMOS will be removed after creating a backup. Continue? [Y/n] '
  read_answer answer
  [[ -z "$answer" || "$answer" == "y" || "$answer" == "Y" || "$answer" == "yes" ]] || die "Migration cancelled"
}

migrate() {
  preflight
  confirm_migration
  backup_v1_state
  uninstall_legacy_gem_team
  uninstall_legacy_omos
  uninstall_v1_opencode
  install_v2
  if [[ "$PATCH_ADDON" == 1 ]]; then
    patch_addon
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-v2|--opencode)
      MODE="install-v2"
      ;;
    --migrate-v1-to-v2)
      MODE="migrate"
      ;;
    --patch-addon)
      PATCH_ADDON=1
      ;;
    --enable-ast-grep)
      ENABLE_AST_GREP=1
      PATCH_ADDON=1
      ;;
    --install-claude|--claude)
      INSTALL_CLAUDE=1
      ;;
    --project)
      [[ $# -ge 2 ]] || die "--project requires a directory"
      TARGET_PROJECT="$2"
      shift
      ;;
    --yes)
      ASSUME_YES=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1 (use --help)"
      ;;
  esac
  shift
done

case "$MODE" in
  migrate)
    migrate
    if [[ "$INSTALL_CLAUDE" == 1 ]]; then
      install_claude
    fi
    ;;
  install-v2)
    preflight
    is_v2_installed || confirm_install
    install_v2
    if [[ "$PATCH_ADDON" == 1 ]]; then
      patch_addon
    fi
    if [[ "$INSTALL_CLAUDE" == 1 ]]; then
      install_claude
    fi
    ;;
esac
