#!/usr/bin/python
"""Check the explicit release allowlist; never include installation state."""
import getpass
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FILES = [
    '.gitignore', 'README.md', 'CHANGELOG.md', 'manifest.json', 'Dock.qml', 'AudaDockBar.desktop',
    'install.sh', 'package.sh', 'bin/adb-launch', 'bin/adb-native',
    'runtime/bridge.py', 'runtime/youtube_audio.py', 'runtime/stream_state.py',
    'runtime/eq_presets.py', 'runtime/radio_info.py', 'runtime/native-menu.cpp',
    'runtime/build-native-menu.sh', 'tests/test_reorder.py', 'tests/test_attach.py', 'tests/test_file_open.py', 'tests/check_release.py',
]

def check():
    problems = []
    manifest = json.loads((ROOT / 'manifest.json').read_text())
    public_author = manifest.get('author', '').strip()
    if not public_author or public_author.casefold() in ('adb', 'audadockbar'):
        problems.append('Set the plugin author to the repository owner, not the project abbreviation.')
    actual = {str(p.relative_to(ROOT)) for p in ROOT.rglob('*') if (p.is_file() or p.is_symlink()) and '.git' not in p.relative_to(ROOT).parts}
    for name in sorted(actual - set(FILES)):
        problems.append('Unexpected release file: ' + name)
    patterns = [
        re.compile(r'/' + r'home/[^/\s\"\']+'),
        re.compile(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
        re.compile(r'gh[pousr]_[A-Za-z0-9]{20,}'),
        re.compile(r'github_pat_[A-Za-z0-9_]{20,}'),
        re.compile(r'AKIA[0-9A-Z]{16}'),
    ]
    account = getpass.getuser()
    account_pattern = None
    if len(account) >= 3 and account.lower() not in ('adb', 'root', 'runner'):
        account_pattern = re.compile(re.escape(account), re.IGNORECASE)
    for name in FILES:
        path = ROOT / name
        if not path.is_file() or path.is_symlink():
            problems.append('Missing file or symlink: ' + name)
            continue
        data = path.read_bytes()
        if b'\0' in data:
            problems.append('Unexpected binary: ' + name)
            continue
        text = data.decode('utf-8')
        # A public GitHub handle may legitimately contain the local account name.
        private_text = text.replace(public_author, '') if public_author else text
        if any(pattern.search(text) for pattern in patterns) or (account_pattern and account_pattern.search(private_text)):
            problems.append('Private identifier/path or credential pattern: ' + name)
    if problems:
        raise SystemExit('\n'.join(problems))
    print('PASS: source allowlist and privacy checks (' + str(len(FILES)) + ' files)')

if __name__ == '__main__':
    check()
