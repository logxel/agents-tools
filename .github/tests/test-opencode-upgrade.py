#!/usr/bin/env python3
"""Exercise project and user addon upgrades in isolated directories."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
INSTALLER = ROOT / '.opencode/install.sh'
OLD_PATH = './.opencode/skills/opencode-v2-workflow'


def run_upgrade(base: Path, user: bool, node_only: bool) -> None:
    target = base / ('config/opencode' if user else 'project/.opencode')
    target.mkdir(parents=True)
    skill = target / 'skills/opencode-v2-workflow'
    skill.mkdir(parents=True)
    (skill / 'opencode-v2-workflow.md').write_text('custom old content')
    (target / 'unrelated.txt').write_text('preserve')
    config = target / 'opencode.jsonc'
    config.write_text('{\n  // keep this comment\n  "default_agent": "custom",\n  "skills": ["other", /* old source */ "' + OLD_PATH + '", "more",],\n  "permissions": []\n}\n')
    second_config = target / 'opencode.json'
    second_config.write_text('{"skills": ["' + OLD_PATH + '", "' + OLD_PATH + '"], "model": "example/model"}\n')
    env = os.environ.copy()
    env['XDG_STATE_HOME'] = str(base / 'state')
    env['XDG_CONFIG_HOME'] = str(base / 'config')
    if node_only:
        bindir = base / 'bin'
        bindir.mkdir()
        for command in ('node', 'dirname', 'mkdir', 'mktemp', 'cp', 'find', 'rm'):
            (bindir / command).symlink_to(shutil.which(command))
        env['PATH'] = str(bindir)
    args = ['--user'] if user else ['--project', str(target.parent)]
    for _ in range(2):
        subprocess.run(['/bin/bash', str(INSTALLER), *args], env=env, check=True, capture_output=True, text=True)
    text = config.read_text()
    assert '// keep this comment' in text and '/* old source */' in text
    assert OLD_PATH not in second_config.read_text()
    assert 'example/model' in second_config.read_text()
    assert OLD_PATH not in text and '"other"' in text and '"more"' in text
    assert '"custom"' in text and (target / 'unrelated.txt').read_text() == 'preserve'
    assert not (skill / 'opencode-v2-workflow.md').exists()
    assert (skill / 'SKILL.md').is_file()
    backups = list((base / 'state/agents-tools/opencode-backups').glob('*/.opencode/skills/opencode-v2-workflow/opencode-v2-workflow.md'))
    assert len(backups) == 1 and backups[0].read_text() == 'custom old content'
    # Confirm the resulting JSONC is still accepted by the same parser.
    subprocess.run(['python3', str(ROOT / '.opencode/merge-config.py'), str(config), str(ROOT / '.opencode/opencode.jsonc'), '0', str(ROOT / '.opencode/mcp/ast-grep.jsonc')], check=True)


with tempfile.TemporaryDirectory() as temporary:
    for user in (False, True):
        for node_only in (False, True):
            base = Path(temporary) / f'{user}-{node_only}'
            run_upgrade(base, user, node_only)
            print(f'upgrade passed: user={user}, node_fallback={node_only}')
