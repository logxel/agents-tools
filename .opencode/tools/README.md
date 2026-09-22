# Tools Policy

No custom runtime tool is part of the baseline. Use built-in search and shell
for ordinary work, the AST-grep CLI for occasional structural queries, and the
optional MCP server only for repeated model-visible structural analysis.

If a future tool performs edits, keep the implementation reviewed, require an
explicit mutation flag, and cover it with a smoke test before enabling it.
