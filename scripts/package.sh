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
info={'CFBundleName':'OxyMac Cleaner','CFBundleDisplayName':'OxyMac Cleaner','CFBundleIdentifier':'com.oxyfire.OxyMacCleaner','CFBundleVersion':'2','CFBundleShortVersionString':'0.1.1','CFBundleExecutable':'OxyMacCleaner','CFBundlePackageType':'APPL','LSMinimumSystemVersion':'14.0','NSHighResolutionCapable':True,'CFBundleIconFile':'AppIcon','NSHumanReadableCopyright':'Copyright © 2026 Oxyfire. MIT License.'}
Path('dist/OxyMac Cleaner.app/Contents/Info.plist').write_bytes(plistlib.dumps(info))
PY
swift scripts/icon.swift
iconutil -c icns dist/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" dist/OxyMacCleaner-0.1.1-macOS-arm64.zip
(cd dist && shasum -a 256 OxyMacCleaner-0.1.1-macOS-arm64.zip > SHA256SUMS.txt)
