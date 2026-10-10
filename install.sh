#!/usr/bin/bash
set -euo pipefail
source_dir=$(cd -- "$(dirname -- "$0")" && pwd)
for dependency in omarchy omarchy-shell audacious python g++ pkg-config; do
  command -v "$dependency" >/dev/null || { printf 'Missing dependency: %s\n' "$dependency" >&2; exit 1; }
done
/usr/bin/python -c 'from gi.repository import Gio, GLib'
pkg-config --exists Qt6Widgets Qt6DBus audacious
omarchy plugin validate "$source_dir"
backup_dir="$HOME/.local/state/adb/install-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$backup_dir" "$HOME/.local/share/adb" "$HOME/.local/bin" "$HOME/.config/omarchy/plugins/adb.audadockbar"
if [[ -f "$HOME/.config/omarchy/shell.json" ]]; then
  cp -- "$HOME/.config/omarchy/shell.json" "$backup_dir/shell.json"
fi
for file in bridge.py youtube_audio.py stream_state.py eq_presets.py radio_info.py native-menu.cpp build-native-menu.sh; do
  destination="$HOME/.local/share/adb/$file"
  if [[ -f "$destination" ]]; then cp -- "$destination" "$backup_dir/$file"; fi
  if [[ "$source_dir/runtime/$file" != "$destination" ]]; then cp -- "$source_dir/runtime/$file" "$destination"; fi
done
bash "$HOME/.local/share/adb/build-native-menu.sh"
for file in adb-launch adb-native; do
  destination="$HOME/.local/bin/$file"
  if [[ -f "$destination" ]]; then cp -- "$destination" "$backup_dir/$file"; fi
  install -m 755 -- "$source_dir/bin/$file" "$destination"
done
for file in Dock.qml manifest.json; do
  destination="$HOME/.config/omarchy/plugins/adb.audadockbar/$file"
  if [[ -f "$destination" && "$source_dir/$file" != "$destination" ]]; then cp -- "$destination" "$backup_dir/$file"; fi
  if [[ "$source_dir/$file" != "$destination" ]]; then cp -- "$source_dir/$file" "$destination"; fi
done
omarchy-shell shell rescanPlugins >/dev/null
for attempt in {1..40}; do
  if omarchy plugin list --json | /usr/bin/python -c 'import json,sys; sys.exit(not any(p["id"]=="adb.audadockbar" for p in json.load(sys.stdin)))'; then break; fi
  sleep 0.05
done
omarchy plugin enable adb.audadockbar
printf 'AudaDockBar installed. Restart an already running Audacious instance to load the native extension.\n'
