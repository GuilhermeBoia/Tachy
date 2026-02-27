#!/bin/bash
set -euo pipefail

APP_NAME="Tachy"
BUNDLE_NAME="${APP_NAME}.app"
BUILD_DIR=".build/release"
APP_DIR="${BUNDLE_NAME}/Contents"

echo "==> Building ${APP_NAME} (release)..."
swift build -c release

echo "==> Creating .app bundle..."
rm -rf "${BUNDLE_NAME}"
mkdir -p "${APP_DIR}/MacOS"
mkdir -p "${APP_DIR}/Resources"

echo "==> Copying binary..."
cp "${BUILD_DIR}/${APP_NAME}" "${APP_DIR}/MacOS/${APP_NAME}"

echo "==> Copying Info.plist..."
cp "Tachy/Info.plist" "${APP_DIR}/Info.plist"

echo "==> Code signing with entitlements..."
codesign --force --deep --sign - \
    --entitlements "Tachy/Tachy.entitlements" \
    "${BUNDLE_NAME}"

echo ""
echo "==> Build complete: ${BUNDLE_NAME}"
echo "    To run: open ${BUNDLE_NAME}"
echo "    To install: cp -r ${BUNDLE_NAME} /Applications/"
