#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="install-v2"
PATCH_ADDON=0
ENABLE_AST_GREP=0
INSTALL_CLAUDE=0
TARGET_PROJECT="$PWD"
ASSUME_YES=0

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
Uso:
  setup-ai.sh [--install-v2] [--patch-addon] [--enable-ast-grep] [--install-claude] [--project DIR]
  setup-ai.sh --migrate-v1-to-v2 [--yes] [--patch-addon] [--enable-ast-grep] [--install-claude] [--project DIR]

Acciones:
  --install-v2          Instala OpenCode V2 solamente; nunca reemplaza V1.
  --migrate-v1-to-v2    Respalda y elimina V1, Gem Team y OMOS; instala V2.
  --patch-addon         Instala el addon .opencode de este repositorio.
  --enable-ast-grep     Activa AST-grep al instalar el addon.
  --install-claude      Instala Claude CLI de forma independiente.
  --project DIR         Proyecto destino del addon (por defecto: cwd).
  --yes                 Confirma migracion, instalaciones y AST-grep sin preguntar.
  -h, --help            Muestra esta ayuda.

Claude CLI solo se instala cuando se solicita explicitamente.
EOF
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Falta el comando requerido: $1"
}

add_local_paths() {
  export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$HOME/.bun/bin:$PATH"
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

  ok "Respaldo creado en $backup_root"
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
  ok "Artefactos de Gem Team eliminados (si existian)"
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
  ok "OMOS eliminado de la configuracion (si estaba presente)"
}

uninstall_v1_opencode() {
  add_local_paths
  local binary=""
  binary="$(command -v opencode 2>/dev/null || true)"

  if [[ -z "$binary" ]]; then
    ok "No se encontro OpenCode V1 instalado"
  elif is_v2_installed; then
    ok "OpenCode V2 ya estaba instalado; no se elimina"
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
      die "No se pudo eliminar OpenCode V1: $(current_opencode_version)"
    fi
    ok "OpenCode V1 eliminado"
  fi
}

install_v2() {
  add_local_paths
  if is_v2_installed; then
    ok "OpenCode V2 ya instalado: $(current_opencode_version)"
    return
  fi

  if command -v opencode >/dev/null 2>&1; then
    die "Se detecto $(current_opencode_version). Usa --migrate-v1-to-v2 para reemplazar V1."
  fi

  ok "Instalando OpenCode V2 desde el instalador oficial"
  CI=true curl -fsSL https://opencode.ai/v2/install | bash
  add_local_paths
  is_v2_installed || die "La instalacion termino, pero no se detecto OpenCode V2"
  ok "OpenCode V2 instalado: $(current_opencode_version)"
}

confirm_install() {
  [[ "$ASSUME_YES" == 1 ]] && return
  [[ -r /dev/tty || -t 0 ]] || die "La instalacion no interactiva requiere --yes"
  printf 'Se instalara OpenCode V2 desde el instalador oficial. Continuar? [Y/n] '
  read_answer answer
  [[ -z "$answer" || "$answer" == "y" || "$answer" == "Y" || "$answer" == "yes" ]] || die "Instalacion cancelada"
}

install_claude() {
  if command -v claude >/dev/null 2>&1; then
    ok "Claude CLI ya instalado ($(claude --version 2>&1))"
    return 0
  fi

  echo ""
  echo "  -- Instalando Claude CLI --"
  if curl -fsSL https://claude.ai/install.sh | bash; then
    add_local_paths
    if command -v claude >/dev/null 2>&1; then
      ok "Claude CLI instalado ($(claude --version 2>&1))"
    else
      die "Claude CLI instalado pero no encontrado en PATH. Prueba reiniciar tu shell o agregar ~/.local/bin a PATH."
    fi
  else
    die "Error al instalar Claude CLI. Intenta manualmente: curl -fsSL https://claude.ai/install.sh | bash"
  fi
}

patch_addon() {
  local project="$(cd "$TARGET_PROJECT" && pwd)"
  if [[ "$project" == "$ROOT_DIR" ]]; then
    make -C "$ROOT_DIR" opencode-validate
    ok "El addon ya esta en este repositorio"
    return
  fi

  if [[ -e "$project/.opencode" ]]; then
    die "El proyecto ya tiene .opencode; no se sobrescribe. Fusiona los archivos desde $ROOT_DIR/.opencode"
  fi

  if [[ "$ENABLE_AST_GREP" == 1 ]]; then
    if [[ "$ASSUME_YES" == 1 ]]; then
      "$ROOT_DIR/.opencode/install.sh" --project "$project" --enable-ast-grep --yes
    else
      "$ROOT_DIR/.opencode/install.sh" --project "$project" --enable-ast-grep
    fi
  else
    "$ROOT_DIR/.opencode/install.sh" --project "$project"
  fi
  ok "Addon V2 instalado en $project/.opencode"
}

confirm_migration() {
  [[ "$ASSUME_YES" == 1 ]] && return
  [[ -r /dev/tty || -t 0 ]] || die "La migracion no interactiva requiere --yes"
  printf 'Se eliminara V1, Gem Team y OMOS despues de crear un respaldo. Continuar? [Y/n] '
  read_answer answer
  [[ -z "$answer" || "$answer" == "y" || "$answer" == "Y" || "$answer" == "yes" ]] || die "Migracion cancelada"
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
      [[ $# -ge 2 ]] || die "--project requiere un directorio"
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
      die "Argumento desconocido: $1 (usa --help)"
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
