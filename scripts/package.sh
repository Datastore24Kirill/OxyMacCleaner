#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="dist/OxyMac Cleaner.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/OxyMacCleaner" "$APP/Contents/MacOS/OxyMacCleaner"
cp docs/branding/oxymac-cleaner-neon-v1.png "$APP/Contents/Resources/BrandIcon.png"
cp LICENSE "$APP/Contents/Resources/LICENSE.txt"
python3 - <<'PY'
import plistlib
from pathlib import Path
info={'CFBundleName':'OxyMac Cleaner','CFBundleDisplayName':'OxyMac Cleaner','CFBundleIdentifier':'com.oxyfire.OxyMacCleaner','CFBundleVersion':'29','CFBundleShortVersionString':'0.2.0','CFBundleExecutable':'OxyMacCleaner','CFBundlePackageType':'APPL','LSMinimumSystemVersion':'14.0','NSHighResolutionCapable':True,'CFBundleIconFile':'AppIcon','CFBundleIconName':'AppIcon','NSHumanReadableCopyright':'Copyright © 2026 Oxyfire. MIT License.'}
Path('dist/OxyMac Cleaner.app/Contents/Info.plist').write_bytes(plistlib.dumps(info))
PY
swift scripts/icon.swift
iconutil -c icns dist/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
# Icon Composer assets prevent the legacy icon treatment on macOS 26+.
xcrun actool Resources/AppIcon.icon --compile "$APP/Contents/Resources" --platform macosx --minimum-deployment-target 14.0 --app-icon AppIcon --output-partial-info-plist dist/icon-info.plist
# Production builds must reuse the same Developer ID identity. Do not weaken
# designated requirements to identifier-only rules to bypass macOS privacy checks.
if [[ -n "${OXYMAC_SIGNING_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$OXYMAC_SIGNING_IDENTITY" "$APP"
else
  codesign --force --sign - "$APP"
fi
codesign --verify --deep --strict "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" dist/OxyMacCleaner-0.2.0-macOS-arm64.zip
(cd dist && shasum -a 256 OxyMacCleaner-0.2.0-macOS-arm64.zip > SHA256SUMS.txt)
