#!/bin/bash
# Bundles index.html + js/*.js into one self-contained file: dist/arbor-simulator.html
set -e
cd "$(dirname "$0")"
mkdir -p dist
python3 - <<'PY'
import re
html=open('index.html').read()
def inline(m):
    src=m.group(1)
    return '<script>\n'+open(src).read()+'\n</script>'
out=re.sub(r'<script src="([^"]+)"></script>',inline,html)
open('dist/arbor-simulator.html','w').write(out)
PY
echo "built dist/arbor-simulator.html"
