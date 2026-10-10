"""Run under dbus-run-session: observing an absent player must not launch it."""
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from gi.repository import Gio, GLib

sys.dont_write_bytecode = True
root = Path(__file__).resolve().parents[1]
private = Path(tempfile.mkdtemp(prefix='adb-observer-test-'))
prefs = private / 'prefs.json'
prefs.write_text(json.dumps({'docked': False, 'youtubeEnabled': True}))
original = prefs.read_bytes()
bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
def player_present():
    return bus.call_sync('org.freedesktop.DBus', '/org/freedesktop/DBus',
        'org.freedesktop.DBus', 'NameHasOwner',
        GLib.Variant('(s)', ('org.atheme.audacious',)), None,
        Gio.DBusCallFlags.NO_AUTO_START, 1000, None).unpack()[0]
assert not player_present(), 'Use an isolated dbus-run-session'
env = dict(os.environ, ADB_PREFS=str(prefs), PYTHONDONTWRITEBYTECODE='1')
process = subprocess.Popen(['/usr/bin/python', str(root / 'runtime/bridge.py')],
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
try:
    process.wait(timeout=5)
    state = json.loads(process.stdout.readline())
    assert process.returncode == 0, process.stderr.read()
    assert state['running'] is False and state['docked'] is False
    assert not player_present()
    assert prefs.read_bytes() == original
    print('PASS: observer exits without launching Audacious or changing dock preferences')
finally:
    if process.poll() is None:
        process.terminate()
        process.wait(timeout=5)
