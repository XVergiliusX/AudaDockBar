"""Run under dbus-run-session: file opening must never become a folder scan."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import wave

sys.dont_write_bytecode = True
project = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='adb-file-open-') as temp:
    root = Path(temp)
    os.environ.update(XDG_CONFIG_HOME=str(root / 'config'),
                      ADB_PREFS=str(root / 'prefs.json'),
                      ADB_OPEN_LOG=str(root / 'last-open.json'),
                      QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='')
    (root / 'prefs.json').write_text('{"docked":false,"youtubeEnabled":false}')
    first = root / 'Lecture with spaces # 100%.wav'
    second = root / 'Second lecture.wav'
    for path in (first, second):
        with wave.open(str(path), 'wb') as audio:
            audio.setparams((1, 2, 22050, 0, 'NONE', 'not compressed'))
            audio.writeframes(b'\0\0' * 22050 * 5)
    sys.path.insert(0, str(project / 'runtime'))
    ns = {}
    source = (project / 'runtime/bridge.py').read_text().split("buffer = b''")[0]
    exec(compile(source, 'bridge.py', 'exec'), ns)
    assert not ns['alive'](), 'Use an isolated dbus-run-session'
    with tempfile.TemporaryDirectory(prefix='.adb-music-test-', dir=Path.home()) as folder:
        directory = Path(folder)
        assert ns['file_targets']([folder], allow_folders=True) == [directory.as_uri()]
        link = directory / 'system-link'
        link.symlink_to('/var/cache', target_is_directory=True)
        try:
            ns['file_targets']([str(link)], allow_folders=True)
        except ValueError:
            pass
        else:
            raise AssertionError('System-directory symlink accepted')
    print('PASS: music folders remain supported; symlinks cannot bypass the system-folder check')
    player = subprocess.Popen(['/usr/bin/audacious', '--headless'],
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(60):
            if ns['alive']():
                break
            time.sleep(.05)
        call = ns['call']
        call('SetVolume', '(ii)', (0, 0))
        def wait_for(uris):
            for _ in range(100):
                actual = [call('SongFilename', '(u)', (i,)) for i in range(call('Length'))]
                if actual == uris and call('Status') == 'playing' and call('Time') > 100:
                    return
                time.sleep(.03)
            raise AssertionError((actual, uris, call('Status')))
        ns['action']({'action': 'launch-files', 'value': [first.as_uri()]})
        wait_for([first.as_uri()])
        print('PASS: one file with spaces and URI escapes plays as exactly one entry')
        for values, folders in [(first.as_uri(), False), (['/'], False),
                                (['/'], True), (['/var/cache'], True),
                                ([first.as_uri(), '/usr'], False),
                                ([first.as_uri(), {}], False)]:
            original_ensure = ns['ensure']
            def unexpected_dispatch(*args, **kwargs):
                raise AssertionError('Unsafe request reached Audacious: ' + repr(values))
            ns['ensure'] = ns['call'] = unexpected_dispatch
            try:
                try:
                    ns['open_targets'](values, allow_folders=folders)
                except (ValueError, OSError):
                    pass
                else:
                    raise AssertionError('Unsafe request accepted: ' + repr(values))
            finally:
                ns['ensure'], ns['call'] = original_ensure, call
            assert call('Length') == 1
            assert call('SongFilename', '(u)', (0,)) == first.as_uri()
        print('PASS: scalar strings and system folders leave the playlist untouched')
        ns['action']({'action': 'launch-files', 'value': [str(first), second.as_uri()]})
        wait_for([first.as_uri(), second.as_uri()])
        print('PASS: multiple selected files retain their names and order')
        if len(sys.argv) > 1:
            fixture = root / Path(sys.argv[1]).name
            shutil.copyfile(sys.argv[1], fixture)
            call('OpenList', '(as)', ([fixture.as_uri()],))
            wait_for([fixture.as_uri()])
            ns['action']({'action': 'launch-files', 'value': [fixture.as_uri()]})
            wait_for([fixture.as_uri()])
            print('PASS: supplied audio plays through both native and dock file opening')
        record = json.loads((root / 'last-open.json').read_text())
        assert record['status'] == 'opened'
        assert (root / 'last-open.json').stat().st_mode & 0o777 == 0o600
        print('PASS: last request is recorded with private permissions')
    finally:
        if player.poll() is None:
            try:
                ns['call']('Quit')
                player.wait(timeout=5)
            except Exception:
                player.terminate()
                player.wait(timeout=5)
