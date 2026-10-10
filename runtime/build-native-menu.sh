#!/usr/bin/bash
set -euo pipefail
base_dir=$(cd -- "$(dirname -- "$0")" && pwd)
g++ -std=c++17 -O2 -fPIC -shared "$base_dir/native-menu.cpp" -o "$base_dir/native-menu.so.new" $(pkg-config --cflags --libs Qt6Widgets Qt6DBus audacious)

mv -f "$base_dir/native-menu.so.new" "$base_dir/native-menu.so"
