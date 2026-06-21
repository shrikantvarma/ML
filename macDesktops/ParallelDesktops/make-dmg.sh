#!/bin/bash
# Builds a Developer-ID-signed, notarized, stapled DMG for download distribution.
# Requires: a "Developer ID Application" certificate + a notarytool credential
# profile (see BUILD.md). An "Apple Development" cert is NOT sufficient.
set -euo pipefail
cd "$(dirname "$0")"

APP="ParallelDesktops.app"
DMG="ParallelDesktops.dmg"
VOL="Parallel Project Desktops"
PROFILE="${NOTARY_PROFILE:-PPDS}"

DEVID="$(security find-identity -v -p codesigning | awk -F\" '/Developer ID Application/{print $2; exit}')"
if [ -z "${DEVID}" ]; then
  echo "ERROR: no 'Developer ID Application' certificate found."
  echo "Create one: Xcode > Settings > Accounts > Manage Certificates > + > Developer ID Application"
  echo "(or https://developer.apple.com/account > Certificates). Then re-run. See BUILD.md."
  exit 1
fi

# Build + bundle as release, signed with Developer ID (make-app.sh auto-picks it).
SIGN_ID="${DEVID}" ./make-app.sh release

# Re-sign with a secure timestamp (required by the notary service).
codesign --force --deep --options runtime --timestamp --sign "${DEVID}" "${APP}"

# Stage a drag-to-install DMG (app + /Applications alias).
STAGE="$(mktemp -d)"
cp -R "${APP}" "${STAGE}/"
ln -s /Applications "${STAGE}/Applications"
rm -f "${DMG}"
hdiutil create -volname "${VOL}" -srcfolder "${STAGE}" -ov -format UDZO "${DMG}"
rm -rf "${STAGE}"

# Notarize the DMG, then staple so Gatekeeper validates it offline.
echo "Submitting to Apple notary service (profile: ${PROFILE})..."
xcrun notarytool submit "${DMG}" --keychain-profile "${PROFILE}" --wait
xcrun stapler staple "${DMG}"
xcrun stapler validate "${DMG}" && echo "Notarized + stapled: $(pwd)/${DMG}"
