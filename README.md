# AudaDockBar

Version 1.0.0

AudaDockBar brings Audacious into the Omarchy bar, so your music stays within reach as you move between workspaces. See what's playing, pause or skip a track, and click the title when you want the full player.

The expanded player keeps the familiar essentials together: playback controls, progress, volume, cover art, playlists and an equalizer. You can leave it docked, switch back to the normal Audacious window, or use double size for easier reading.

## What it does

- Shows the current song and radio metadata in the bar, with playback controls and elapsed or remaining time.
- Keeps the player popup in place when a longer song title appears.
- Lets you create playlists, rename entries without changing the files, and reorder tracks while music keeps playing.
- Includes equalizer presets and lets you save your own.
- Skips to the next or previous entry for both music files and radio streams.
- Offers optional YouTube audio through yt-dlp and ffmpeg.
- Reconnects to an already running Audacious after the widget or shell reloads.

Audacious starts when you choose to use it. AudaDockBar does not start the player at login.

## Requirements

AudaDockBar was developed with Audacious 4.6, Qt 6 and the Quickshell-based Omarchy shell. Other versions have not been verified.

On Arch, the required packages are `audacious`, `audacious-plugins`, `python-gobject`, `qt6-base`, `gcc`, `pkgconf` and `zenity`. Omarchy provides Quickshell and the shared UI components. Optional YouTube playback also needs `yt-dlp`, a JavaScript runtime supported by yt-dlp, and `ffmpeg`.

The native extension may need rebuilding after incompatible Qt or Audacious updates.

## Installation

From the project directory, run:

```sh
./install.sh
```

The installer copies the plugin and launchers into your user directories, builds the native extension and adds the widget to the bar. Existing bar entries are preserved. Dependencies and keyboard shortcuts are left for you to configure.

If Audacious was already running, restart it once to load the native extension.

For an optional Hyprland Lua shortcut, choose a free key combination:

```lua
o.bind("SUPER + SHIFT + A", "AudaDockBar", os.getenv("HOME") .. "/.local/bin/adb-launch")
```

The launchers are named `adb-launch` and `adb-native`, so they do not conflict with Android's `adb` command. A desktop launcher template is included as `AudaDockBar.desktop`; using it requires `~/.local/bin` in your desktop session's PATH.

## Using the player

Click the song title in the bar to open or close the player. Click the time to switch between elapsed and remaining time. For radio, **Live** means audio is advancing, **reco** means waiting or reconnecting, and **disc** means disconnected.

Click the **Equalizer** heading to turn it on or off. Changing a preset creates a **Custom** curve; use **+** to save it as a new preset. In the playlist, the reorder button switches the entry controls to Up and Down. Renaming an entry only changes its display name, and deleting a playlist leaves your media files intact.

Use **Menu → View → Dock mode** to undock. To dock again, enable **View → Dock mode** in Audacious or run `adb-launch`. The minimize button in Audacious's Winamp main-player window also acts as **Fast Dock**.

## Settings and local data

Settings and custom presets are saved in `~/.config/audacious/adb.json`. Audacious keeps its own playlists and playback settings. The installed runtime lives in `~/.local/share/adb/`, the plugin in `~/.config/omarchy/plugins/adb.audadockbar/`, and backups in `~/.local/state/adb/`.

Personal settings, playlists, credentials and music are not included in the source archive. Your preferences can contain local media paths, so keep that file private. Public YouTube audio does not require an account or browser cookies; its optional helper listens only on localhost, using port 19086 by default.

## Development

```sh
./runtime/build-native-menu.sh
omarchy plugin validate .
dbus-run-session -- /usr/bin/python tests/test_reorder.py
dbus-run-session -- /usr/bin/python tests/test_attach.py
```

The reorder test runs an isolated, muted Audacious instance with temporary audio. It checks playback continuity, entry ordering and rejection of stale requests without touching your normal playlists. The attachment test checks that observing the player does not start it or change its settings.

Internal names use `adb`, and the session-bus service is `org.adb.AudaDockBar`. Test overrides are available through `ADB_DBUS_NAME`, `ADB_MPRIS_NAME`, `ADB_PREFS` and `ADB_YOUTUBE_PORT`.

## Creating a source archive

```sh
python tests/check_release.py
./package.sh
```

The archive includes only the listed source files. Generated libraries, local settings, logs, caches and Git history are excluded. The release check also looks for personal home paths, the current account name and common credential formats. Remove any compiled library from the source directory before packaging.

A distribution license has not been chosen yet.
