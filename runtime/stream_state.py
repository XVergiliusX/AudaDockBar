"""Derive stream readiness from the playback engine, without extra network probes."""
import time

class StreamConnection:
    def __init__(self, stall_seconds=3.0):
        self.stall_seconds = stall_seconds
        self.key = None
        self.position = None
        self.progress_at = None

    def update(self, key, status, position, audio_ready, now=None):
        now = time.monotonic() if now is None else now
        if key != self.key or (self.position is not None and position < self.position):
            self.position = None
            self.progress_at = None
        self.key = key
        if key is None:
            self.position = None
            self.progress_at = None
            return None
        if status == 'stopped':
            self.progress_at = None
            result = 'disc'
        elif status == 'paused':
            self.progress_at = None
            result = 'Pause'
        else:
            if audio_ready and self.position is not None and position > self.position + 50:
                self.progress_at = now
            flowing = audio_ready and self.progress_at is not None and now - self.progress_at <= self.stall_seconds
            result = 'Live' if flowing else 'reco'
        self.position = position
        return result
