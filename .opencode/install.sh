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
an .opencode directory, or merges/upgrades the addon in an existing setup.
Existing project configuration takes precedence and is backed up before merging.
Configuration merging uses Python 3 when available, with Node.js or Bun as fallbacks.
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

if [[ -d "$PROJECT_DIR/.opencode" && "$PROJECT_DIR/.opencode" -ef "$ADDON_DIR" ]]; then
  printf 'OpenCode V2 addon is already installed in %s/.opencode\n' "$PROJECT_DIR"
  exit 0
fi
if command -v python3 >/dev/null 2>&1; then
  CONFIG_MERGE_RUNTIME=python3
elif command -v node >/dev/null 2>&1; then
  CONFIG_MERGE_RUNTIME=node
elif command -v bun >/dev/null 2>&1; then
  CONFIG_MERGE_RUNTIME=bun
else
  printf 'ERROR: Python 3, Node.js, or Bun is required to merge OpenCode configuration\n' >&2
  exit 1
fi

if [[ -L "$PROJECT_DIR/.opencode" ]]; then
  printf 'ERROR: refusing to merge through symlink %s/.opencode\n' "$PROJECT_DIR" >&2
  exit 1
fi
if [[ -e "$PROJECT_DIR/.opencode" && ! -d "$PROJECT_DIR/.opencode" ]]; then
  printf 'ERROR: %s/.opencode exists but is not a directory\n' "$PROJECT_DIR" >&2
  exit 1
fi

if [[ "$ENABLE_AST_GREP" == 1 && "$ASSUME_YES" != 1 ]]; then
  [[ -r /dev/tty || -t 0 ]] || {
    printf 'ERROR: enabling AST-grep non-interactively requires --yes\n' >&2
    exit 1
  }
  printf 'Enable the AST-grep MCP server for this project? [Y/n] '
  read_answer answer
  if [[ -z "$answer" || "$answer" == "y" || "$answer" == "Y" || "$answer" == "yes" ]]; then
    ENABLE_AST_GREP=1
  else
    ENABLE_AST_GREP=0
    printf 'AST-grep remains disabled.\n'
  fi
fi

if [[ ! -e "$PROJECT_DIR/.opencode" ]]; then
  cp -R "$ADDON_DIR" "$PROJECT_DIR/.opencode"
else
  STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
  BACKUP_PARENT="$STATE_HOME/agents-tools/opencode-backups"
  mkdir -p "$BACKUP_PARENT"
  BACKUP_DIR=$(mktemp -d "$BACKUP_PARENT/$(basename "$PROJECT_DIR")-XXXXXXXX")
  cp -a "$PROJECT_DIR/.opencode" "$BACKUP_DIR/.opencode"
  printf 'Backed up existing configuration to %s/.opencode\n' "$BACKUP_DIR"

  while IFS= read -r -d '' source_file; do
    relative_path="${source_file#"$ADDON_DIR"/}"
    [[ "$relative_path" == "opencode.jsonc" ]] && continue

    destination="$PROJECT_DIR/.opencode/$relative_path"
    parent="$PROJECT_DIR/.opencode"
    relative_parent=$(dirname "$relative_path")
    if [[ "$relative_parent" != "." ]]; then
      IFS='/' read -r -a parent_parts <<< "$relative_parent"
      for part in "${parent_parts[@]}"; do
        parent="$parent/$part"
        if [[ -L "$parent" ]]; then
          printf 'ERROR: refusing to follow symlink while merging %s\n' "$parent" >&2
          exit 1
        fi
        if [[ -e "$parent" && ! -d "$parent" ]]; then
          printf 'ERROR: cannot create addon directory over non-directory %s\n' "$parent" >&2
          exit 1
        fi
      done
    fi
    if [[ -L "$destination" ]]; then
      printf 'ERROR: refusing to overwrite symlink %s\n' "$destination" >&2
      exit 1
    fi
    if [[ -e "$destination" && ! -f "$destination" ]]; then
      printf 'ERROR: cannot merge addon file over non-file %s\n' "$destination" >&2
      exit 1
    fi
    mkdir -p "$parent"
    cp -p "$source_file" "$destination"
  done < <(find "$ADDON_DIR" -type f -print0)
fi

CONFIG_PATH="$PROJECT_DIR/.opencode/opencode.jsonc"
if [[ -f "$PROJECT_DIR/.opencode/opencode.json" ]]; then
  CONFIG_PATH="$PROJECT_DIR/.opencode/opencode.json"
fi
if [[ ! -f "$CONFIG_PATH" ]]; then
  cp -p "$ADDON_DIR/opencode.jsonc" "$CONFIG_PATH"
fi

if [[ "$CONFIG_MERGE_RUNTIME" == "python3" ]]; then
  python3 "$ADDON_DIR/merge-config.py" "$CONFIG_PATH" "$ADDON_DIR/opencode.jsonc" "$ENABLE_AST_GREP" "$ADDON_DIR/mcp/ast-grep.jsonc"
else
"$CONFIG_MERGE_RUNTIME" - "$CONFIG_PATH" "$ADDON_DIR/opencode.jsonc" "$ENABLE_AST_GREP" "$ADDON_DIR/mcp/ast-grep.jsonc" <<'NODE'
const fs = require("fs")

const [configPath, addonConfigPath, enableAstGrep, astGrepPath] = process.argv.slice(-4)

function parseJsonc(text, filePath) {
  let index = 0
  const fail = () => { throw new Error(`${filePath}: invalid JSONC at character ${index}`) }
  const skipTrivia = () => {
    while (index < text.length) {
      if (/\s/.test(text[index])) {
        index += 1
      } else if (text.startsWith("//", index)) {
        index = text.indexOf("\n", index + 2)
        if (index < 0) index = text.length
      } else if (text.startsWith("/*", index)) {
        const end = text.indexOf("*/", index + 2)
        if (end < 0) fail()
        index = end + 2
      } else {
        break
      }
    }
  }
  const parseString = () => {
    const start = index
    index += 1
    while (index < text.length) {
      if (text[index] === "\\") index += 2
      else if (text[index++] === '"') {
        try {
          return { start, end: index, value: JSON.parse(text.slice(start, index)) }
        } catch {
          fail()
        }
      }
    }
    fail()
  }
  const parseValue = () => {
    skipTrivia()
    const start = index
    if (text[index] === "{") {
      index += 1
      const properties = []
      skipTrivia()
      while (text[index] !== "}") {
        if (text[index] !== '"') fail()
        const key = parseString().value
        skipTrivia()
        if (text[index++] !== ":") fail()
        const value = parseValue()
        properties.push({ key, value })
        skipTrivia()
        if (text[index] === ",") {
          index += 1
          skipTrivia()
          if (text[index] === "}") break
        } else if (text[index] !== "}") {
          fail()
        }
      }
      if (text[index++] !== "}") fail()
      return { type: "object", start, end: index, properties }
    }
    if (text[index] === "[") {
      index += 1
      const items = []
      skipTrivia()
      while (text[index] !== "]") {
        items.push(parseValue())
        skipTrivia()
        if (text[index] === ",") {
          index += 1
          skipTrivia()
          if (text[index] === "]") break
        } else if (text[index] !== "]") {
          fail()
        }
      }
      if (text[index++] !== "]") fail()
      return { type: "array", start, end: index, items }
    }
    if (text[index] === '"') {
      const parsed = parseString()
      return { type: "value", start, end: index, value: parsed.value }
    }
    while (index < text.length && !/[\s,\]}]/.test(text[index]) && !text.startsWith("//", index) && !text.startsWith("/*", index)) {
      index += 1
    }
    if (start === index) fail()
    let value
    try {
      value = JSON.parse(text.slice(start, index))
    } catch {
      fail()
    }
    return { type: "value", start, end: index, value }
  }

  const root = parseValue()
  skipTrivia()
  if (index !== text.length) fail()
  return root
}

function toValue(node) {
  if (node.type === "array") return node.items.map(toValue)
  if (node.type === "object") {
    return Object.fromEntries(node.properties.map(({ key, value }) => [key, toValue(value)]))
  }
  return node.value
}

function property(node, key) {
  for (let index = (node.properties?.length ?? 0) - 1; index >= 0; index -= 1) {
    if (node.properties[index].key === key) return node.properties[index]
  }
}

const configText = fs.readFileSync(configPath, "utf8")
const configRoot = parseJsonc(configText, configPath)
const addonRoot = parseJsonc(fs.readFileSync(addonConfigPath, "utf8"), addonConfigPath)
if (configRoot.type !== "object" || addonRoot.type !== "object") {
  throw new Error("OpenCode configuration must be a JSON object")
}
const addon = toValue(addonRoot)
const additions = new Map()
const replacements = []

function addObjectEntries(node, entries) {
  if (!node || node.type !== "object") throw new Error(`${configPath}: expected an object while merging addon`)
  const missing = entries.filter(([key]) => !property(node, key))
  if (missing.length) additions.set(node, [...(additions.get(node) ?? []), ...missing])
}

function addArrayItems(node, values) {
  if (!node || node.type !== "array") throw new Error(`${configPath}: expected an array while merging addon`)
  const existing = toValue(node)
  const missing = values.filter((value) => !existing.some((item) => JSON.stringify(item) === JSON.stringify(value)))
  if (missing.length) additions.set(node, [...(additions.get(node) ?? []), ...missing])
}

const schema = property(configRoot, "$schema")
if (!schema) addObjectEntries(configRoot, [["$schema", addon.$schema]])
if (!property(configRoot, "default_agent")) {
  addObjectEntries(configRoot, [["default_agent", addon.default_agent]])
}

const agentsProperty = property(configRoot, "agents")
if (!agentsProperty) {
  addObjectEntries(configRoot, [["agents", addon.agents]])
} else {
  if (agentsProperty.value.type !== "object") {
    throw new Error(`${configPath}: agents must be an object to merge the addon`)
  }
  addObjectEntries(agentsProperty.value, Object.entries(addon.agents ?? {}))
}

for (const field of ["skills", "permissions"]) {
  const fieldProperty = property(configRoot, field)
  if (!fieldProperty) {
    addObjectEntries(configRoot, [[field, addon[field] ?? []]])
    continue
  }
  const node = fieldProperty.value
  if (node.type !== "array") {
    throw new Error(`${configPath}: ${field} must be an array to merge the addon`)
  }
  const existing = toValue(node)
  const missing = (addon[field] ?? []).filter((value) => {
    if (field !== "permissions") {
      return !existing.some((item) => JSON.stringify(item) === JSON.stringify(value))
    }
    return !existing.some((item) =>
      item?.action === value.action && item?.resource === value.resource,
    )
  })
  addArrayItems(node, missing)
}

if (enableAstGrep === "1") {
  const fragment = toValue(parseJsonc(fs.readFileSync(astGrepPath, "utf8"), astGrepPath))
  const mcpProperty = property(configRoot, "mcp")
  if (!mcpProperty) {
    addObjectEntries(configRoot, [[
      "mcp",
      { servers: { "ast-grep": { ...fragment.mcp.servers["ast-grep"], disabled: false } } },
    ]])
  } else {
    const mcp = mcpProperty.value
    if (mcp.type !== "object") throw new Error(`${configPath}: mcp must be an object to enable AST-grep`)
    const serversProperty = property(mcp, "servers")
    if (!serversProperty) {
      addObjectEntries(mcp, [["servers", {
        "ast-grep": { ...fragment.mcp.servers["ast-grep"], disabled: false },
      }]])
    } else {
      const servers = serversProperty.value
      if (servers.type !== "object") {
        throw new Error(`${configPath}: mcp.servers must be an object to enable AST-grep`)
      }
      const astProperty = property(servers, "ast-grep")
      if (!astProperty) {
        addObjectEntries(servers, [["ast-grep", { ...fragment.mcp.servers["ast-grep"], disabled: false }]])
      } else {
        const astServer = astProperty.value
        if (astServer.type !== "object") {
          throw new Error(`${configPath}: mcp.servers.ast-grep must be an object`)
        }
        const disabledProperty = property(astServer, "disabled")
        if (!disabledProperty) addObjectEntries(astServer, [["disabled", false]])
        else if (toValue(disabledProperty.value) !== false) {
          replacements.push({ start: disabledProperty.value.start, end: disabledProperty.value.end, text: "false" })
        }
      }
    }
  }
}

const edits = [...replacements]
for (const [node, entries] of additions) {
  const isObject = node.type === "object"
  const children = isObject ? node.properties.map((entry) => entry.value) : node.items
  const lastChild = children[children.length - 1]
  const position = lastChild ? lastChild.end : node.start + 1
  const values = isObject
    ? entries.map(([key, value]) => `${JSON.stringify(key)}: ${JSON.stringify(value)}`)
    : entries.map((value) => JSON.stringify(value))
  edits.push({
    start: position,
    end: position,
    text: `${lastChild ? ", " : ""}${values.join(", ")}`,
  })
}

let mergedText = configText
for (const edit of edits.sort((left, right) => right.start - left.start)) {
  mergedText = `${mergedText.slice(0, edit.start)}${edit.text}${mergedText.slice(edit.end)}`
}
parseJsonc(mergedText, configPath)
if (mergedText !== configText) fs.writeFileSync(configPath, mergedText)
NODE
fi

if [[ "$ENABLE_AST_GREP" == 1 ]]; then
  printf 'Enabled AST-grep in %s\n' "$CONFIG_PATH"
fi
printf 'OpenCode V2 addon installed or updated in %s/.opencode\n' "$PROJECT_DIR"
