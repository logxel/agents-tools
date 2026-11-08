#!/usr/bin/env node
"""Install or refresh the addon's managed section in global OpenCode AGENTS.md."""

const fs = require("fs")
const path = require("path")

const [target, source] = process.argv.slice(2)
const start = "<!-- agents-tools:dependency-installation:start -->"
const end = "<!-- agents-tools:dependency-installation:end -->"
const section = `${start}\n${fs.readFileSync(source, "utf8").trim()}\n${end}`
let current = fs.existsSync(target) ? fs.readFileSync(target, "utf8") : ""

if (current.includes(start) && current.includes(end)) {
  const before = current.slice(0, current.indexOf(start))
  const after = current.slice(current.indexOf(end) + end.length)
  current = `${before.trimEnd()}${before.trim() && after.trim() ? "\n\n" : ""}${after.trimStart()}`
} else if (current.includes(start) || current.includes(end)) {
  throw new Error(`Incomplete managed section in ${target}; restore from backup and retry`)
}

current = `${current.trimEnd()}${current.trim() ? "\n\n" : ""}${section}\n`
fs.mkdirSync(path.dirname(target), { recursive: true })
fs.writeFileSync(target, current)
