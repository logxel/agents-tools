#!/usr/bin/env bash
# Prepare the project-local plan directory and print the absolute plan path.
set -euo pipefail

if [[ $# != 1 || ! "$1" =~ ^[0-9]{8}-[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
  printf 'Usage: bash prepare-plan.sh YYYYMMDD-slug\n' >&2
  exit 2
fi

root=$(git rev-parse --show-toplevel) || {
  printf 'ERROR: plans require a Git worktree; do not create a plan in another location.\n' >&2
  exit 1
}
cd "$root"
plan=".opencode/state/plans/$1.md"
if [[ -n "$(git ls-files -- .opencode/state)" ]]; then
  printf 'ERROR: .opencode/state contains tracked files; resolve this before creating runtime plans.\n' >&2
  exit 1
fi
if ! git check-ignore -q --no-index -- "$plan"; then
  exclude=$(git rev-parse --git-path info/exclude)
  mkdir -p "$(dirname "$exclude")"
  printf '\n/.opencode/state/\n' >> "$exclude"
fi
if ! git check-ignore -q --no-index -- "$plan"; then
  printf 'ERROR: %s is not ignored; check higher-priority ignore rules.\n' "$plan" >&2
  exit 1
fi
mkdir -p .opencode/state/plans
printf '%s/%s\n' "$root" "$plan"
