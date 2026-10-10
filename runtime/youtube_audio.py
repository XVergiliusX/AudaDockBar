#!/usr/bin/python
"""Local, on-demand YouTube audio transport for Audacious. No media is saved."""
import base64
import json
import os
import shutil
import socket
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse
from urllib.request import urlopen

PORT = int(os.environ.get('ADB_YOUTUBE_PORT', '19086'))
BASE = f'http://127.0.0.1:{PORT}'

def youtube_url(value):
    """Normalize supported video/live links; do not treat channels as playlists."""
    parsed = urlparse(value.strip())
    host = (parsed.hostname or '').lower()
    if parsed.scheme not in ('http', 'https') or parsed.username or parsed.password:
        return ''
    if host == 'youtu.be':
        video = parsed.path.strip('/').split('/')[0]
    elif host in ('youtube.com', 'www.youtube.com', 'm.youtube.com', 'music.youtube.com'):
        if parsed.path == '/watch':
            video = parse_qs(parsed.query).get('v', [''])[0]
        elif parsed.path.startswith(('/live/', '/shorts/', '/embed/')):
            video = parsed.path.split('/')[2]
        elif parsed.path.endswith('/live') and parsed.path.startswith(('/@', '/channel/', '/c/')):
            return 'https://www.youtube.com' + parsed.path
        else:
            raise ValueError('Use a YouTube video or channel live link.')
    else:
        return ''
    if len(video) != 11 or any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-' for c in video):
        raise ValueError('Invalid YouTube video link.')
    return 'https://www.youtube.com/watch?v=' + video

def key_for(url):
    return base64.urlsafe_b64encode(url.encode()).decode().rstrip('=')

def stream_url(url):
    return BASE + '/youtube/' + key_for(url) + '.mp3'

def original_url(uri):
    if not uri.startswith(BASE + '/youtube/') or not uri.endswith('.mp3'):
        return ''
    key = uri[len(BASE + '/youtube/'):-4]
    try:
        url = base64.urlsafe_b64decode(key + '=' * (-len(key) % 4)).decode()
        return youtube_url(url)
    except (ValueError, UnicodeError):
        return ''

def status(uri):
    source = original_url(uri)
    if not source:
        return {}
    try:
        with urlopen(BASE + '/status/' + key_for(source), timeout=.3) as response:
            return json.load(response)
    except (OSError, ValueError):
        return {}

def ensure_server():
    """Keep streaming independent of dock UI reloads, but never start at login."""
    try:
        with urlopen(BASE + '/health', timeout=.3) as response:
            if response.read() == b'audacious-youtube-audio':
                return
    except OSError:
        pass
    if not shutil.which('yt-dlp') or not shutil.which('ffmpeg'):
        raise ValueError('YouTube audio requires yt-dlp and ffmpeg.')
    subprocess.Popen([sys.executable, str(Path(__file__).resolve()), '--serve'],
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True)
    for _ in range(20):
        try:
            with urlopen(BASE + '/health', timeout=.2) as response:
                if response.read() == b'audacious-youtube-audio':
                    return
        except OSError:
            time.sleep(.05)
    raise ValueError('Could not start the local YouTube audio service.')

class AudioServer(ThreadingHTTPServer):
    daemon_threads = True
    def __init__(self, address):
        super().__init__(address, AudioHandler)
        self.lock = threading.RLock()
        self.sources = {}
        self.processes = set()
        self.stopping = False

    def resolve(self, source):
        # One metadata request per source, including concurrent Audacious probes.
        with self.lock:
            entry = self.sources.setdefault(source, {'lock': threading.Lock(), 'public': {}})
        with entry['lock']:
            if entry.get('expires', 0) > time.monotonic():
                return entry['info']
            entry['public'] = {'title': entry['public'].get('title', 'YouTube'), 'loading': True}
            try:
                result = subprocess.run(['yt-dlp', '--ignore-config', '--no-playlist',
                    '--skip-download', '--no-warnings', '--socket-timeout', '15', '--retries', '1',
                    '-f', 'bestaudio/best', '--dump-single-json', '--', source],
                    capture_output=True, text=True, timeout=90)
                if result.returncode:
                    message = result.stderr.strip().split('\n')[-1]
                    raise ValueError(message.removeprefix('ERROR: ') or 'Could not resolve YouTube audio.')
                info = json.loads(result.stdout)
                if not info.get('url'):
                    raise ValueError('YouTube returned no playable audio source.')
                entry['info'] = info
                entry['expires'] = time.monotonic() + 900
                entry['public'] = {'title': info.get('title') or 'YouTube',
                    'artUrl': info.get('thumbnail') or '', 'live': bool(info.get('is_live')),
                    'loading': False, 'error': ''}
                return info
            except (OSError, ValueError, subprocess.TimeoutExpired) as exc:
                entry['public'] = {'title': 'YouTube', 'loading': False, 'error': str(exc)}
                raise ValueError(str(exc)) from exc

    def playback_error(self, source):
        with self.lock:
            entry = self.sources.get(source)
            if entry:
                entry['expires'] = 0
                entry['public'] = dict(entry['public'], error='YouTube audio disconnected. Press Play to reconnect.')

class AudioHandler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.0'
    def log_message(self, *args):
        pass

    def reply(self, code, body, content_type='application/json'):
        self.send_response(code)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        if self.command != 'HEAD':
            self.wfile.write(body)

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        if self.path == '/health':
            self.reply(200, b'audacious-youtube-audio', 'text/plain')
            return
        if self.path.startswith('/status/'):
            key = self.path[len('/status/'):]
            source = original_url(BASE + '/youtube/' + key + '.mp3')
            with self.server.lock:
                public = dict(self.server.sources.get(source, {}).get('public', {}))
            self.reply(200, json.dumps(public).encode())
            return
        source = original_url(BASE + self.path)
        if not source:
            self.reply(404, b'{}')
            return
        if self.command == 'HEAD':
            self.reply(200, b'', 'audio/mpeg')
            return
        process = None
        try:
            info = self.server.resolve(source)
            headers = ''.join(f'{k}: {v}\r\n' for k, v in info.get('http_headers', {}).items()
                if '\n' not in str(k) + str(v) and '\r' not in str(k) + str(v))
            args = ['ffmpeg', '-hide_banner', '-loglevel', 'error', '-nostdin', '-re',
                '-rw_timeout', '15000000', '-reconnect', '1', '-reconnect_streamed', '1',
                '-reconnect_delay_max', '5']
            if headers:
                args += ['-headers', headers]
            args += ['-i', info['url'], '-map', '0:a:0', '-vn', '-sn', '-dn',
                '-c:a', 'libmp3lame', '-b:a', '192k', '-metadata', 'title=' + info.get('title', 'YouTube'),
                '-metadata', 'artist=' + info.get('uploader', 'YouTube'),
                '-f', 'mp3', '-write_xing', '0', '-flush_packets', '1', 'pipe:1']
            with self.server.lock:
                if self.server.stopping:
                    return
                process = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
                self.server.processes.add(process)
            self.send_response(200)
            self.send_header('Content-Type', 'audio/mpeg')
            self.send_header('Cache-Control', 'no-store')
            self.end_headers()
            while chunk := process.stdout.read(4096):
                self.wfile.write(chunk)
                self.wfile.flush()
            if process.wait() != 0:
                self.server.playback_error(source)
        except ValueError as exc:
            self.reply(502, json.dumps({'error': str(exc)}).encode())
        except (OSError, socket.timeout):
            pass
        finally:
            if process is not None:
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        process.kill(); process.wait()
                process.stdout.close()
                with self.server.lock:
                    self.server.processes.discard(process)

def serve():
    try:
        server = AudioServer(('127.0.0.1', PORT))
    except OSError:
        return  # Another bridge may have started it concurrently.
    threading.Thread(target=server.serve_forever, daemon=True).start()
    from gi.repository import Gio, GLib
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    seen_player = False
    deadline = time.monotonic() + 30
    try:
        while True:
            alive = bus.call_sync('org.freedesktop.DBus', '/org/freedesktop/DBus',
                'org.freedesktop.DBus', 'NameHasOwner',
                GLib.Variant('(s)', ('org.atheme.audacious',)), None,
                Gio.DBusCallFlags.NONE, 1000, None).unpack()[0]
            seen_player |= alive
            if not alive and (seen_player or time.monotonic() > deadline):
                break
            time.sleep(2)
    finally:
        with server.lock:
            server.stopping = True
            for process in server.processes:
                if process.poll() is None:
                    process.terminate()
        server.shutdown(); server.server_close()

if __name__ == '__main__' and sys.argv[1:] == ['--serve']:
    serve()
