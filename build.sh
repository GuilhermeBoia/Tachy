#!/bin/bash
set -euo pipefail

APP_NAME="Tachy"
BUNDLE_NAME="${APP_NAME}.app"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRATCH_DIR="${SCRIPT_DIR}/.build"
MODULE_CACHE_DIR="${SCRATCH_DIR}/module-cache"
BUILD_DIR="${SCRATCH_DIR}/release"
APP_DIR="${BUNDLE_NAME}/Contents"

cd "${SCRIPT_DIR}"

echo "==> Preparing Swift cache..."
# Path moves can invalidate cached PCH/module artifacts. Remove only module cache dirs.
rm -rf \
    "${MODULE_CACHE_DIR}" \
    "${SCRATCH_DIR}/release/ModuleCache" \
    "${SCRATCH_DIR}/arm64-apple-macosx/release/ModuleCache" \
    "${SCRATCH_DIR}/arm64-apple-macosx/debug/ModuleCache"
mkdir -p "${MODULE_CACHE_DIR}"

echo "==> Building ${APP_NAME} (release)..."
swift build -c release \
    --scratch-path "${SCRATCH_DIR}" \
    -Xswiftc -module-cache-path \
    -Xswiftc "${MODULE_CACHE_DIR}"

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
