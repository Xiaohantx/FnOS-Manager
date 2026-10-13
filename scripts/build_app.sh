#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

SDK_PATH="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [ ! -d "$SDK_PATH" ]; then
    SDK_PATH="$(xcrun --show-sdk-path)"
fi

echo "==> Using macOS SDK: $SDK_PATH"

APP_NAME="FnOS Manager"
BUILD_DIR="${PROJECT_DIR}/build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
MACOS_DIR="${APP_BUNDLE}/Contents/MacOS"
RESOURCES_DIR="${APP_BUNDLE}/Contents/Resources"

echo "==> Cleaning old build..."
rm -rf "${BUILD_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

echo "==> Gathering Swift source files..."
SWIFT_FILES=$(find "${PROJECT_DIR}/Sources/fnOSApp" -name "*.swift")

echo "==> Compiling fnOSApp with swiftc..."
swiftc \
    -sdk "${SDK_PATH}" \
    -target arm64-apple-macos14.0 \
    -O \
    -parse-as-library \
    -framework Virtualization \
    -framework SwiftUI \
    -framework AppKit \
    -framework WebKit \
    -framework Network \
    ${SWIFT_FILES} \
    -o "${MACOS_DIR}/fnOSApp"

echo "==> Copying Info.plist and Resources..."
cp "${PROJECT_DIR}/Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"
if [ -f "${PROJECT_DIR}/Resources/AppIcon.icns" ]; then
    cp "${PROJECT_DIR}/Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi
if [ -f "${PROJECT_DIR}/Resources/AppLogo.png" ]; then
    cp "${PROJECT_DIR}/Resources/AppLogo.png" "${RESOURCES_DIR}/AppLogo.png"
fi

echo "==> Signing application with entitlements..."
codesign --force --deep --sign - \
    --entitlements "${PROJECT_DIR}/entitlements.plist" \
    "${APP_BUNDLE}"

echo "==> Build successful: ${APP_BUNDLE}"
echo "==> Verifying signature..."
codesign -dvvv "${APP_BUNDLE}"
