#!/usr/bin/python
"""Audacious DBus bridge. No shell interpolation or changes to audio files."""
import json, os, select, subprocess, sys, time, uuid
from pathlib import Path
from gi.repository import Gio, GLib
from stream_state import StreamConnection
from eq_presets import BUILTINS, matches
from radio_info import display_info
import youtube_audio
connection = StreamConnection()
bus_name = os.environ.get('ADB_DBUS_NAME', 'org.atheme.audacious')
mpris_name = os.environ.get('ADB_MPRIS_NAME', 'org.mpris.MediaPlayer2.audacious')
playlist_catalog = []
bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
prefs_file = Path(os.environ.get('ADB_PREFS', str(Path.home() / '.config/audacious/adb.json')))
try:
    prefs = json.loads(prefs_file.read_text())
except (OSError, ValueError):
    prefs = {'docked': True, 'multiple': False}
error = ''
expanded = False
dialogs = []
youtube_ready = False

def call(method, signature=None, args=()):
    result = bus.call_sync(bus_name, '/org/atheme/audacious',
        'org.atheme.audacious', method,
        GLib.Variant(signature, args) if signature else None,
        None, Gio.DBusCallFlags.NONE, 1500, None)
    values = result.unpack()
    return values[0] if len(values) == 1 else values

def alive():
    return bus.call_sync('org.freedesktop.DBus', '/org/freedesktop/DBus',
        'org.freedesktop.DBus', 'NameHasOwner',
        GLib.Variant('(s)', (bus_name,)), None,
        Gio.DBusCallFlags.NONE, 1000, None).unpack()[0]

def cover_url(filename):
    """Use the playing source's artwork; missing MPRIS or artwork is harmless."""
    if not filename:
        return ''
    try:
        metadata = bus.call_sync(mpris_name, '/org/mpris/MediaPlayer2',
            'org.freedesktop.DBus.Properties', 'Get',
            GLib.Variant('(ss)', ('org.mpris.MediaPlayer2.Player', 'Metadata')),
            None, Gio.DBusCallFlags.NO_AUTO_START, 500, None).unpack()[0]
        if metadata.get('xesam:url') != filename:
            return ''
        url = str(metadata.get('mpris:artUrl', ''))
        return url if url.startswith(('file://', 'http://', 'https://', 'data:image/')) else ''
    except GLib.Error:
        return ''

def save():
    prefs_file.parent.mkdir(parents=True, exist_ok=True)
    temp = prefs_file.with_suffix('.tmp')
    temp.write_text(json.dumps(prefs))
    temp.replace(prefs_file)

def ensure():
    global youtube_ready
    if prefs.get('youtubeEnabled') and not youtube_ready:
        youtube_audio.ensure_server()
        youtube_ready = True
    if not alive():
        subprocess.Popen([str(Path.home() / '.local/bin/adb-native')], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(30):
            if alive(): break
            time.sleep(.1)
    if prefs.get('docked', True): call('ShowMainWin', '(b)', (False,))

def media_target(value):
    global youtube_ready
    target = str(value).strip()
    source = youtube_audio.youtube_url(target)
    if source:
        youtube_audio.ensure_server()
        youtube_ready = True
        prefs['youtubeEnabled'] = True
        save()
        return youtube_audio.stream_url(source)
    return target

def refresh_playlists():
    global playlist_catalog
    original = call('GetActivePlaylist')
    catalog = []
    try:
        for index in range(call('NumberOfPlaylists')):
            call('SetActivePlaylist', '(i)', (index,))
            catalog.append({'index': index, 'name': call('GetActivePlaylistName')})
    finally:
        call('SetActivePlaylist', '(i)', (original,))
    playlist_catalog = catalog

def presets():
    return BUILTINS + prefs.get('eqPresets', [])

def mark_custom():
    if prefs.get('eqSelected') != 'custom':
        prefs['eqSelected'] = 'custom'; save()

def action(msg):
    global expanded
    name, value = msg.get('action'), msg.get('value')
    if name == 'expanded': expanded = bool(value); return
    if name == 'rename-entry':
        uri, label = str(value['uri']), str(value['label']).strip()
        labels = prefs.setdefault('labels', {})
        if label: labels[uri] = label
        else: labels.pop(uri, None)
        save(); return
    if name == 'remaining': prefs['remaining'] = bool(value); save(); return
    if name == 'double-size': prefs['doubleSize'] = bool(value); save(); return
    if name == 'dock':
        prefs['docked'] = bool(value); save(); ensure()
        call('ShowMainWin', '(b)', (not value,))
        return
    if name == 'start': ensure(); return
    if name == 'launch-files':
        ensure()
        urls = [media_target(item) if '://' in item else Path(item).resolve().as_uri() for item in value]
        if urls: call('OpenList', '(as)', (urls,))
        return
    if name in ('openfiles', 'openfolder'):
        ensure()
        args = ['/usr/bin/zenity', '--file-selection', '--title=' + ('Open Files — Audacious' if name == 'openfiles' else 'Open Folder — Audacious')]
        if name == 'openfolder': args.append('--directory')
        else: args += ['--multiple', '--separator=\x1f']
        # Collect dialog output outside the polling loop: cancellation changes nothing.
        dialogs.append(subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True))
        return
    if name == 'library':
        ensure()
        call('PluginEnable', '(sb)', ('search-tool-qt', True))
        prefs['docked'] = False; save()
        call('ShowMainWin', '(b)', (True,))
        return
    if name == 'quit':
        if alive(): call('Quit')
        return
    ensure()
    if name == 'preset':
        preset = next((p for p in presets() if p['id'] == value), None)
        if preset is None: raise ValueError('This preset no longer exists.')
        call('SetEq', '(dad)', (float(preset['preamp']), [float(v) for v in preset['bands']]))
        call('EqualizerActivate', '(b)', (True,))
        prefs['eqSelected'] = preset['id']; save(); return
    if name == 'save-preset':
        title = str(value).strip()
        if not title: raise ValueError('Please enter a preset name.')
        if any(p['name'].casefold() == title.casefold() for p in presets()):
            raise ValueError('A preset with this name already exists.')
        preamp, bands = call('GetEq')
        preset = {'id':'user:'+uuid.uuid4().hex, 'name':title, 'preamp':preamp, 'bands':bands, 'user':True}
        prefs.setdefault('eqPresets', []).append(preset)
        prefs['eqSelected'] = preset['id']; save(); return
    if name == 'delete-preset':
        own = prefs.get('eqPresets', [])
        if not any(p['id'] == value for p in own): raise ValueError('Only custom presets can be deleted.')
        prefs['eqPresets'] = [p for p in own if p['id'] != value]
        if prefs.get('eqSelected') == value: prefs['eqSelected'] = 'custom'
        save(); return
    if name == 'list-playlists': refresh_playlists(); return
    if name == 'rename-list':
        index, expected = int(value['index']), str(value['name'])
        title = str(value['title']).strip()
        if not title: raise ValueError('Please enter a playlist name.')
        original = call('GetActivePlaylist')
        if not 0 <= index < call('NumberOfPlaylists'):
            refresh_playlists()
            raise ValueError('This playlist no longer exists.')
        try:
            call('SetActivePlaylist', '(i)', (index,))
            if call('GetActivePlaylistName') != expected:
                raise ValueError('The playlists have changed. Please select one again.')
            call('SetActivePlaylistName', '(s)', (title,))
        finally:
            call('SetActivePlaylist', '(i)', (original,))
            refresh_playlists()
        return
    if name == 'create-list':
        title = str(value).strip()
        if not title: raise ValueError('Please enter a playlist name.')
        call('NewPlaylist')
        call('SetActivePlaylist', '(i)', (call('NumberOfPlaylists') - 1,))
        call('SetActivePlaylistName', '(s)', (title,))
        refresh_playlists(); return
    if name == 'delete-list':
        index, expected = int(value['index']), str(value['name'])
        original = call('GetActivePlaylist')
        if not 0 <= index < call('NumberOfPlaylists'): raise ValueError('This playlist no longer exists.')
        call('SetActivePlaylist', '(i)', (index,))
        if call('GetActivePlaylistName') != expected:
            call('SetActivePlaylist', '(i)', (original,))
            refresh_playlists()
            raise ValueError('The playlists have changed. Please select one again.')
        call('DeleteActivePlaylist')
        count = call('NumberOfPlaylists')
        if count:
            selected = original - 1 if index < original else original
            call('SetActivePlaylist', '(i)', (min(selected, count - 1),))
        refresh_playlists(); return
    if name == 'move-entry':
        bus.call_sync('org.adb.AudaDockBar', '/org/adb/AudaDockBar',
            'org.adb.AudaDockBar', 'MoveEntry',
            GLib.Variant('(s)', (json.dumps(value),)), None,
            Gio.DBusCallFlags.NO_AUTO_START, 1500, None)
        return
    if name in ('next', 'prev'):
        length = call('Length')
        if length == 0: return
        position = call('Position')
        if position >= length:
            target = 0 if name == 'next' else length - 1
        else:
            target = (position + (1 if name == 'next' else -1)) % length
        # Explicitly select AND play the next list entry. Changing the displayed
        # playlist position alone can leave the previous stream playing.
        call('Jump', '(u)', (target,))
        call('Play')
        return
    simple = {'play':'PlayPause', 'stop':'Stop',
        'repeat':'ToggleRepeat', 'shuffle':'ToggleShuffle', 'settings':'ShowPrefsBox',
        'files':'ShowFilebrowser', 'clear':'Clear', 'new':'NewPlaylist',
        'playonly':'Play', 'pause':'Pause', 'prevalbum':'ReverseAlbum', 'nextalbum':'AdvanceAlbum',
        'advance':'ToggleAutoAdvance', 'stopafter':'ToggleStopAfter', 'record':'Record',
        'about':'ShowAboutBox', 'jumpdialog':'ShowJtfBox'}
    if name in simple:
        call(simple[name], '(b)' if name in ('settings','files','about','jumpdialog') else None,
             (True,) if name in ('settings','files','about','jumpdialog') else ())
    elif name == 'volumeup':
        v = min(100, call('Volume')[0] + 5); call('SetVolume', '(ii)', (v, v))
    elif name == 'volumedown':
        v = max(0, call('Volume')[0] - 5); call('SetVolume', '(ii)', (v, v))
    elif name == 'openurl':
        target = media_target(value)
        if target: call('OpenList', '(as)', ([target],))
    elif name == 'volume': call('SetVolume', '(ii)', (int(value), int(value)))
    elif name == 'seek': call('Seek', '(u)', (max(0, int(value)),))
    elif name == 'eq': call('EqualizerActivate', '(b)', (bool(value),))
    elif name == 'preamp':
        call('SetEqPreamp', '(d)', (float(value),)); mark_custom()
    elif name == 'band':
        call('SetEqBand', '(id)', (int(msg['band']), float(value))); mark_custom()
    elif name == 'flat':
        call('SetEq', '(dad)', (0.0, [0.0]*10)); prefs['eqSelected'] = 'builtin:neutral'; save()
    elif name == 'add':
        target = media_target(value)
        if target and ':' not in target:
            target = Path(target).expanduser().resolve().as_uri()
        if target: call('AddUrl', '(s)', (target,))
    elif name == 'jump': call('Jump', '(u)', (int(value),)); call('Play')
    elif name == 'delete': call('Delete', '(u)', (int(value),))
    elif name == 'playlist':
        call('SetActivePlaylist', '(i)', (int(value),)); refresh_playlists()

def snapshot():
    state = dict(prefs, running=alive(), error=error)
    if not state['running']: return state
    pos, length = call('Position'), call('Length')
    filename = call('SongFilename', '(u)', (pos,)) if pos < length else ''
    youtube_source = youtube_audio.original_url(filename)
    youtube_info = youtube_audio.status(filename) if youtube_source else {}
    track_title = call('SongTuple', '(us)', (pos, 'title')) if pos < length else ''
    artist = call('SongTuple', '(us)', (pos, 'artist')) if pos < length else ''
    # SongLength is seconds; Time and Seek use milliseconds.
    duration = max(0, call('SongLength', '(u)', (pos,))) * 1000 if pos < length else 0
    is_stream = filename.startswith(('http://','https://','icy://','mms://'))
    status, play_time = call('Status'), call('Time')
    rate, frequency, channels = call('GetInfo') if is_stream else (0, 0, 0)
    stream_state = connection.update((filename, pos) if is_stream else None,
        status, play_time, frequency > 0 and channels > 0)
    formatted_title = call('SongTitle', '(u)', (pos,)) if pos < length else ''
    label = prefs.get('labels', {}).get(filename, '')
    display_title = display_info(track_title, artist, formatted_title, label, is_stream, stream_state == 'Live')
    if youtube_source:
        display_title = label or youtube_info.get('title') or track_title or 'YouTube audio'
        if youtube_info.get('loading'):
            stream_state = 'reco'
        state['error'] = error or youtube_info.get('error', '')
    state.update(displayTitle=display_title, filename=filename, trackTitle=track_title or '', artist=artist or '',
        stream=is_stream, streamState=stream_state, live=stream_state == 'Live',
        status=status, title=formatted_title,
        position=pos, length=length, time=play_time,
        duration=duration,
        volume=call('Volume')[0], repeat=call('Repeat'), shuffle=call('Shuffle'))
    if expanded:
        state['artUrl'] = cover_url(filename) or youtube_info.get('artUrl', '')
        if not playlist_catalog or len(playlist_catalog) != call('NumberOfPlaylists'): refresh_playlists()
        labels = prefs.get('labels', {})
        entries = []
        for index in range(length):
            uri = call('SongFilename', '(u)', (index,))
            title = call('SongTitle', '(u)', (index,))
            if youtube_audio.original_url(uri):
                title = youtube_audio.status(uri).get('title') or title or 'YouTube audio'
            entries.append({'uri': uri, 'original': title, 'label': labels.get(uri, title)})
        preamp, bands = call('GetEq')
        selected_id = prefs.get('eqSelected', 'builtin:neutral')
        selected = next((p for p in presets() if p['id'] == selected_id), None)
        if selected_id != 'custom' and (selected is None or not matches(selected, preamp, bands)):
            mark_custom(); selected = None; selected_id = 'custom'
        state.update(eqPresets=presets(), eqPresetId=selected_id,
            eqPresetName=selected['name'] if selected else 'Custom', eqCustom=selected is None, preamp=preamp, bands=bands,
            eq=call('ConfigGet','(ss)',('','equalizer_active')) == 'TRUE',
            playlistName=call('GetActivePlaylistName'), playlistIndex=call('GetActivePlaylist'),
            playlistCount=call('NumberOfPlaylists'), advance=call('AutoAdvance'),
            stopafter=call('StopAfter'), recording=call('Recording'),
            songs=[entry['label'] for entry in entries], songEntries=entries, playlists=playlist_catalog)
    return state

last_snapshot = None
buffer = b''
while True:
    ready, _, _ = select.select([sys.stdin], [], [], 1)
    if ready:
        chunk = os.read(sys.stdin.fileno(), 65536)
        if not chunk: break
        buffer += chunk
        while b'\n' in buffer:
            line, buffer = buffer.split(b'\n', 1)
            try:
                action(json.loads(line)); error = ''
            except Exception as exc:
                error = str(exc).split('\n')[0]
    try:
        for dialog in dialogs[:]:
            if dialog.poll() is not None:
                output = dialog.communicate()[0].rstrip('\n')
                dialogs.remove(dialog)
                if dialog.returncode == 0 and output:
                    ensure()
                    urls = [Path(path).resolve().as_uri() for path in output.split('\x1f')]
                    call('OpenList', '(as)', (urls,))
                    error = ''
                elif dialog.returncode not in (0, 1):
                    error = 'Could not open the file dialog.'
        state = snapshot()
        last_snapshot = state
        print(json.dumps(state), flush=True)
        if not state['running']: break
    except Exception as exc:
        still_running = alive()
        print(json.dumps(dict(last_snapshot or prefs, running=still_running, error=str(exc).split('\n')[0])), flush=True)
        if not still_running: break

for dialog in dialogs:
    if dialog.poll() is None: dialog.terminate()
