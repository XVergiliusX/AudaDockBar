# AudaDockBar

Version 1.0.0 — first public release.

A compact Audacious player for the Omarchy bar. Internal names use `adb`; the plugin ID is `adb.audadockbar`.

## Features

- Click the track title to open or collapse the player.
- Playback controls, elapsed/remaining time, volume, artwork and stream metadata.
- A fixed popup anchor that follows the bar position without moving when the title changes.
- Equalizer with built-in and custom presets; disabled controls are dimmed.
- Playlist creation, renaming, track aliases and entry ordering.
- Previous/Next select the neighboring file or stream in displayed list order.
- View-menu dock mode, double size and native-player Fast Dock.
- Optional on-demand YouTube audio via yt-dlp and ffmpeg.
- No player or bridge autostart at login; opening the player starts the bridge.

## Requirements

Developed with Audacious 4.6, Qt 6 and the Quickshell-based Omarchy shell. Other versions need verification. The native extension uses Audacious's public libaudcore playlist API and Qt event filters.

Arch packages: `audacious`, `audacious-plugins`, `python-gobject`, `qt6-base`, `gcc`, `pkgconf`, `zenity`. The Omarchy shell supplies Quickshell and the shared QML UI components. Optional YouTube support needs `yt-dlp`, its supported JavaScript runtime, and `ffmpeg`.

The extension must be rebuilt after incompatible Qt/Audacious updates.

## Install

From the project directory, run:

```sh
./install.sh
```

The installer copies the runtime and launchers into the current user's directories, builds the native extension, validates the manifest, and enables the bar widget. It preserves other bar entries and does not install packages or change keyboard shortcuts. Restart Audacious if it was already running to load the native extension.

For an optional Hyprland Lua shortcut, use your own preferred free key:

```lua
o.bind("SUPER + SHIFT + A", "AudaDockBar", os.getenv("HOME") .. "/.local/bin/adb-launch")
```

The launchers are `adb-launch` and `adb-native`, leaving the Android `adb` command available. A desktop launcher template is in `AudaDockBar.desktop`; add `~/.local/bin` to the desktop session's PATH before using it.

## Local data

The source repository contains no playlists, aliases, listening history, account credentials, cookies or music files. Runtime data stays outside the source directory:

- Settings and custom EQ presets: `~/.config/audacious/adb.json`.
- Audacious manages its own playlists and playback configuration.
- Runtime: `~/.local/share/adb/`.
- Plugin: `~/.config/omarchy/plugins/adb.audadockbar/`.
- Backups: `~/.local/state/adb/`.

A normal installed preferences file may contain local media URIs. Do not publish that file. No account or browser cookies are required for public YouTube audio. The optional helper binds only to loopback; its default port is 19086.

## Controls

The main panel has a one-line title, playback controls with time on the same row, progress, volume, artwork, then menus. The time in the bar is an unhighlighted clickable label that switches elapsed/remaining time. Radio playback shows Live only while audio advances; reco means reconnecting/waiting, disc means disconnected, and Pause means paused.

Click the Equalizer heading to enable/disable it. Presets use a floating selector; manual changes become Custom, and + saves the curve. Click the playlist heading's reorder control to replace rename/delete actions with Up/Down. Moving an entry preserves current playback, queue and selection. Track aliases do not modify files or tags. Deleting a playlist does not delete its media.

Menu → View → Dock mode undocks. Native Audacious → View → Dock mode or `adb-launch` docks again. The native Winamp main-player minimize button becomes Fast Dock. Auxiliary dialogs retain their normal behavior.

## Development and verification

```sh
./runtime/build-native-menu.sh
omarchy plugin validate .
dbus-run-session -- /usr/bin/python tests/test_reorder.py
python tests/check_release.py
```

The reorder test uses an isolated, muted Audacious instance and temporary generated audio. It tests both directions, playback continuity, stream URI ordering and stale/out-of-range rejection. It does not use the normal session's playlists.

The release check permits only the source-file allowlist, rejects symlinks, caches and binaries, and checks for the current account name, literal home paths and common private-key/token formats. This is a focused packaging check, not a general security audit.

The internal session-bus service is `org.adb.AudaDockBar`; optional test overrides are `ADB_DBUS_NAME`, `ADB_MPRIS_NAME`, `ADB_PREFS` and `ADB_YOUTUBE_PORT`.

## Publishing

Publish only this project directory after running the release check. A clean source archive can be created with `./package.sh`; it is built from an explicit file allowlist. Generated libraries, local state, screenshots, logs, caches, editor backups and Git history are excluded. Review the archive before uploading. No remote repository is configured by these scripts.

A distribution license has not been specified yet.
