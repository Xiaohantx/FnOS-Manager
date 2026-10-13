#!/bin/bash
set -e

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-1.0.0}"
APP_NAME="FnOS Manager"
BUILD_DIR="${PROJECT_ROOT}/build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
DMG_STAGING="${BUILD_DIR}/dmg_staging"
DMG_FILENAME="FnOS-Manager-${VERSION}-arm64.dmg"
DMG_PATH="${BUILD_DIR}/${DMG_FILENAME}"

echo "==> Step 1: Building ${APP_NAME}.app (v${VERSION})..."
"${PROJECT_ROOT}/scripts/build_app.sh"

echo "==> Step 2: Preparing DMG staging directory..."
rm -rf "${DMG_STAGING}" "${DMG_PATH}"
mkdir -p "${DMG_STAGING}"

cp -R "${APP_BUNDLE}" "${DMG_STAGING}/${APP_NAME}.app"
ln -s /Applications "${DMG_STAGING}/Applications"

if [ -f "${PROJECT_ROOT}/Resources/AppIcon.icns" ]; then
    cp "${PROJECT_ROOT}/Resources/AppIcon.icns" "${DMG_STAGING}/.VolumeIcon.icns"
    if command -v SetFile >/dev/null 2>&1; then
        SetFile -c icnC "${DMG_STAGING}/.VolumeIcon.icns" || true
        SetFile -a C "${DMG_STAGING}" || true
    fi
fi

echo "==> Step 3: Creating compressed DMG installer..."
hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${DMG_STAGING}" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "${DMG_PATH}"

rm -rf "${DMG_STAGING}"

echo "==> DMG packaged successfully:"
ls -lh "${DMG_PATH}"
shasum -a 256 "${DMG_PATH}"
