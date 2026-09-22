#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ADDON_DIR="$ROOT_DIR/.opencode"

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

[[ -d "$ADDON_DIR" ]] || fail "Missing addon directory: .opencode"
[[ -x "$ADDON_DIR/install.sh" ]] || fail "Installer is not executable"

node - "$ROOT_DIR" <<'NODE'
const fs = require("fs")
const path = require("path")

const root = process.argv[2]
const addon = path.join(root, ".opencode")
const readJson = (relativePath) => {
  const filePath = path.join(root, relativePath)
  try {
    return JSON.parse(fs.readFileSync(filePath, "utf8"))
  } catch (error) {
    throw new Error(`${relativePath}: invalid JSON/JSONC: ${error.message}`)
  }
}

readJson(".opencode/opencode.jsonc")
readJson(".opencode/mcp/ast-grep.jsonc")
readJson(".opencode/mcp/web-research.jsonc")
const catalog = readJson(".opencode/skills/index.json")
if (!Array.isArray(catalog.skills)) throw new Error("catalog skills must be an array")

const frontmatter = (filePath) => {
  const text = fs.readFileSync(filePath, "utf8")
  if (!text.startsWith("---\n")) throw new Error(`${filePath}: missing frontmatter`)
  const end = text.indexOf("\n---\n", 4)
  if (end < 0) throw new Error(`${filePath}: unterminated frontmatter`)
  const header = text.slice(4, end).split(/\r?\n/)
  const fields = new Map(header.map((line) => {
    const separator = line.indexOf(":")
    return separator < 0 ? [line, ""] : [line.slice(0, separator), line.slice(separator + 1).trim()]
  }))
  if (!fields.get("name") || !fields.get("description")) {
    throw new Error(`${filePath}: name and description are required`)
  }
  return fields
}

for (const entry of catalog.skills) {
  if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(entry.name)) {
    throw new Error(`invalid catalog skill name: ${entry.name}`)
  }
  if (!String(entry.version)) throw new Error(`${entry.name}: missing catalog version`)
  if (!Array.isArray(entry.files) || !entry.files.includes(`${entry.name}.md`)) {
    throw new Error(`${entry.name}: catalog must include its named Markdown entry`)
  }
  const skillRoot = path.join(addon, "skills", entry.name)
  for (const relativePath of entry.files) {
    if (!relativePath || path.isAbsolute(relativePath) || relativePath.split("/").includes("..")) {
      throw new Error(`${entry.name}: unsafe catalog path ${relativePath}`)
    }
    const filePath = path.join(skillRoot, relativePath)
    if (!fs.statSync(filePath).isFile()) throw new Error(`${entry.name}: missing ${relativePath}`)
  }
  const entryFile = path.join(skillRoot, `${entry.name}.md`)
  const fields = frontmatter(entryFile)
  if (fields.get("name") !== entry.name) {
    throw new Error(`${entry.name}: frontmatter name does not match catalog ID`)
  }
  console.log(`catalog: ${entry.name} (${entry.files.length} files)`)
}

for (const directory of ["agents", "commands"]) {
  const directoryPath = path.join(addon, directory)
  for (const file of fs.readdirSync(directoryPath).filter((name) => name.endsWith(".md"))) {
    frontmatter(path.join(directoryPath, file))
    console.log(`${directory}: ${file}`)
  }
}

console.log("OpenCode V2 addon validation completed successfully")
NODE
