#!/usr/bin/env python3
"""Verify plan preparation against real Git worktrees and ignore rules."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / '.opencode/skills/opencode-v2-workflow/scripts/prepare-plan.sh'
PLAN_ID = '20261028-sample-task'


def git(cwd: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(['git', *args], cwd=cwd, check=True, capture_output=True, text=True)


def prepare(cwd: Path, plan_id: str = PLAN_ID) -> subprocess.CompletedProcess:
    return subprocess.run(['bash', str(SCRIPT), plan_id], cwd=cwd, capture_output=True, text=True)


with tempfile.TemporaryDirectory() as temporary:
    base = Path(temporary)
    repo = base / 'repo'
    repo.mkdir()
    git(repo, 'init', '-q')
    nested = repo / 'nested/deep'
    nested.mkdir(parents=True)
    result = prepare(nested)
    expected = repo / '.opencode/state/plans' / (PLAN_ID + '.md')
    assert result.returncode == 0 and result.stdout.strip() == str(expected), result.stderr
    git(repo, 'check-ignore', '-q', '--', str(expected))
    exclude = Path(git(repo, 'rev-parse', '--git-path', 'info/exclude').stdout.strip())
    exclude = repo / exclude
    first = exclude.read_text()
    assert prepare(nested).returncode == 0 and exclude.read_text() == first
    assert not (repo / '.gitignore').exists()
    assert prepare(repo, '../bad').returncode != 0

    conflict = base / 'conflict'
    conflict.mkdir()
    git(conflict, 'init', '-q')
    (conflict / '.gitignore').write_text('!.opencode/\n!.opencode/state/\n!.opencode/state/plans/\n!.opencode/state/plans/*.md\n')
    assert prepare(conflict).returncode != 0
    assert not (conflict / '.opencode/state/plans').exists()

    tracked = base / 'tracked'
    tracked.mkdir()
    git(tracked, 'init', '-q')
    file = tracked / '.opencode/state/existing.md'
    file.parent.mkdir(parents=True)
    file.write_text('tracked')
    git(tracked, 'add', str(file))
    assert prepare(tracked).returncode != 0
    assert not (tracked / '.opencode/state/plans').exists()

    non_git = base / 'non-git'
    non_git.mkdir()
    assert prepare(non_git).returncode != 0
    assert not (non_git / '.opencode').exists()
print('Plan preparation checks passed')
