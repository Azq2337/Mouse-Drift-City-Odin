#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
odin build src/main -out:build/mouse-drift-city

ROOT_DIR="$(pwd)"
cat > build/mouse-drift-city.desktop <<EOF
[Desktop Entry]
Type=Application
Name=Mouse Drift City
Exec="${ROOT_DIR}/build/mouse-drift-city"
Terminal=false
Categories=Game;
EOF
chmod +x build/mouse-drift-city.desktop
