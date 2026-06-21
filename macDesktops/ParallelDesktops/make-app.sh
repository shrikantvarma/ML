#!/bin/bash
# Wraps the SwiftPM executable into a real .app bundle so MenuBarExtra registers
# its status item (an unbundled binary does not reliably show a menu-bar icon).
# Dev convenience until the Xcode/signing migration (plan KTD-1/KTD-7).
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-debug}"
APP="ParallelDesktops.app"
BIN_NAME="ParallelDesktops"

echo "Building (${CONFIG})..."
swift build -c "${CONFIG}"
BIN_PATH="$(swift build -c "${CONFIG}" --show-bin-path)/${BIN_NAME}"

echo "Assembling ${APP}..."
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS"
cp "${BIN_PATH}" "${APP}/Contents/MacOS/${BIN_NAME}"

cat > "${APP}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>               <string>Parallel Project Desktops</string>
    <key>CFBundleDisplayName</key>        <string>Parallel Project Desktops</string>
    <key>CFBundleExecutable</key>         <string>ParallelDesktops</string>
    <key>CFBundleIdentifier</key>         <string>com.shrikant.parallel-project-desktops</string>
    <key>CFBundlePackageType</key>        <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>0.1.0</string>
    <key>CFBundleVersion</key>            <string>1</string>
    <key>LSUIElement</key>                <true/>
    <key>LSMinimumSystemVersion</key>     <string>14.0</string>
</dict>
</plist>
PLIST

# Pick the best available signing identity:
#   Developer ID Application (distributable, notarizable)  >  Apple Development
#   (stable local identity, fixes Accessibility re-grant churn)  >  ad-hoc.
# Override with SIGN_ID="..." if needed.
if [ -z "${SIGN_ID:-}" ]; then
  SIGN_ID="$(security find-identity -v -p codesigning | awk -F\" '/Developer ID Application/{print $2; exit}')"
  [ -z "${SIGN_ID}" ] && SIGN_ID="$(security find-identity -v -p codesigning | awk -F\" '/Apple Development/{print $2; exit}')"
fi

if [ -n "${SIGN_ID}" ]; then
  echo "Signing with: ${SIGN_ID}"
  # --options runtime (hardened runtime) so the same build is notarization-ready;
  # SkyLight is Apple-signed, so dlopen passes library validation.
  codesign --force --deep --options runtime --sign "${SIGN_ID}" "${APP}"
else
  echo "No signing identity found - falling back to ad-hoc (grant resets each rebuild)."
  codesign --force --deep --sign - "${APP}" || true
fi

echo "Done: $(pwd)/${APP}"
