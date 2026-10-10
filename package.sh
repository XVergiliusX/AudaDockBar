#!/usr/bin/bash
set -euo pipefail
source_dir=$(cd -- "$(dirname -- "$0")" && pwd)
python - "$source_dir" <<'PY'
import importlib.util, sys, tarfile
from pathlib import Path
root = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location('adb_release', root / 'tests/check_release.py')
module = importlib.util.module_from_spec(spec)
sys.dont_write_bytecode = True
spec.loader.exec_module(module)
module.check()
# The archive lives outside the source folder; no private installation is read.
target = root.parent / 'AudaDockBar-source.tar.gz'
def clean(info):
    info.uid = info.gid = 0
    info.uname = info.gname = ''
    info.mtime = 0
    return info
with tarfile.open(target, 'w:gz') as archive:
    for name in module.FILES:
        archive.add(root / name, arcname='AudaDockBar/' + name, recursive=False,
                    filter=lambda info: clean(info))
print('Created ' + target.name)
PY
