#!/bin/bash
# Export the web build and copy it to the repo root, where Netlify serves it from.
set -e
cd "$(dirname "$0")"
mkdir -p build/web
godot --headless --path . --export-release "Web" build/web/index.html
cp build/web/index.* ..
echo "Web build copied to the repo root."
