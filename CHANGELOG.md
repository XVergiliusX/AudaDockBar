# Changelog

## 1.0.1 — 2026-10-21

- Preserve file lists across Quickshell IPC using an object envelope. A single file previously arrived as a string and was processed character by character, causing each slash to import the filesystem root.
- Reject malformed file lists and directory arguments in file-opening actions; block system directories in the explicit folder picker.
- Keep a private record of the latest file-open request and add isolated playback regression checks.
- Write versioned source archives outside the project folder.

## 1.0.0

First release of AudaDockBar for the Quickshell-based Omarchy shell.

- Music controls, song information and radio metadata in the bar.
- A player popup that stays in place as song titles change.
- Equalizer presets, playlist management, track aliases and entry ordering.
- Previous/next navigation for both streams and files.
- Dock mode, double size and Fast Dock from the native player.
- Optional YouTube audio and manual player startup.
- Portable installation and source packaging with privacy checks.

### Included hotfix

The bar now reconnects automatically when Audacious is already running after a widget or shell reload. If the connection is interrupted, playback controls stay visible while it recovers, without opening the popup or starting Audacious on its own.
