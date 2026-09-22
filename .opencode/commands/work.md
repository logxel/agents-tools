---
description: Run bounded planning, implementation, and verification for a work request
agent: orchestrator
---

Load `opencode-v2-workflow`. Use the built-in `plan` agent only when the user
explicitly requests a planning-only session. Otherwise, use the built-in
`explore` agent for read-only repository discovery, the `websearch`/`webfetch`
tools for web research, and the built-in `general` agent for bounded delegated
work when appropriate. Handle this request:

$ARGUMENTS
