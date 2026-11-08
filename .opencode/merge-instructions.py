#!/usr/bin/env python3
"""Install or refresh the addon's managed section in global OpenCode AGENTS.md."""

from pathlib import Path
import sys

START = "<!-- agents-tools:dependency-installation:start -->"
END = "<!-- agents-tools:dependency-installation:end -->"


def main() -> None:
    target = Path(sys.argv[1])
    source = Path(sys.argv[2])
    section = f"{START}\n{source.read_text().strip()}\n{END}"
    current = target.read_text() if target.exists() else ""

    if START in current and END in current:
        before, remainder = current.split(START, 1)
        _, after = remainder.split(END, 1)
        current = before.rstrip() + ("\n\n" if before.strip() and after.strip() else "") + after.lstrip()
    elif START in current or END in current:
        raise SystemExit(f"ERROR: incomplete managed section in {target}; restore from backup and retry")

    updated = current.rstrip()
    if updated:
        updated += "\n\n"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(updated + section + "\n")


if __name__ == "__main__":
    main()
