#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
icon_tool="${ICON_COMPOSER_TOOL:-/Applications/Icon Composer.app/Contents/Executables/ictool}"
if [[ ! -x "$icon_tool" ]]; then
  icon_tool="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"
fi
if [[ ! -x "$icon_tool" ]]; then
  printf 'Install Apple Icon Composer to regenerate icon assets.\n' >&2
  exit 1
fi
compiled="$project_root/.build/icon-compiled"
mkdir -p "$compiled"
"$icon_tool" "$project_root/Assets/AppIcon.icon" --export-image \
  --output-file "$project_root/Assets/Bracket.png" --platform macOS \
  --rendition Default --width 1024 --height 1024 --scale 1
xcrun actool "$project_root/Assets/AppIcon.icon" --compile "$compiled" \
  --output-format human-readable-text --platform macosx \
  --minimum-deployment-target 13.0 --app-icon AppIcon \
  --output-partial-info-plist "$compiled/Info.plist"
cp "$compiled/AppIcon.icns" Assets/Bracket.icns
cp "$compiled/Assets.car" Assets/Assets.car
python3 - <<'PY'
from pathlib import Path
import json
import xml.etree.ElementTree as ET

source = Path('Assets/AppIcon.icon')
document = json.loads((source / 'icon.json').read_text())
def color(value):
    components = value.split(':', 1)[1].split(',')[:3]
    return '#' + ''.join(f'{round(float(component) * 255):02x}' for component in components)

top, bottom = map(color, document['fill']['linear-gradient'])
ET.register_namespace('', 'http://www.w3.org/2000/svg')
shapes = []
for group in document['groups']:
    for layer in group['layers']:
        artwork = ET.parse(source / 'Assets' / layer['image-name']).getroot()
        shapes.extend(ET.tostring(item, encoding='unicode') for item in artwork if item.tag.rsplit('}', 1)[-1] != 'title')

# The web mark is a flat vector counterpart; native icon material remains in .icon.
svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <title>Bracket app icon</title>
  <desc>Soft-cornered white square brackets and three dots on a green gradient. Flat vector counterpart of the native glass layers in Assets/AppIcon.icon.</desc>
  <defs><linearGradient id="green" x1="0" y1="0" x2="0" y2="1"><stop stop-color="{top}"/><stop offset="1" stop-color="{bottom}"/></linearGradient></defs>
  <rect x="80" y="80" width="864" height="864" rx="190" fill="url(#green)"/>
  {''.join(shapes)}
</svg>
'''
Path('Assets/Bracket.svg').write_text(svg)
Path('Assets/Bracket.png.provenance.json').write_text(json.dumps({
    'source': 'Assets/AppIcon.icon',
    'renderer': 'Apple Icon Composer ictool',
    'description': 'Original soft-cornered white square-bracket and three-dot vector layers, rendered with native glass, translucency, and specular lighting over the unchanged green gradient. No generated bitmap artwork.'
}, indent=2) + '\n')
PY
printf 'Created Icon Composer PNG, ICNS, Assets.car, and flat vector reference.\n'
