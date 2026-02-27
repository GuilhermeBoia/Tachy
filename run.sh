#!/bin/bash
set -euo pipefail

APP_NAME="Tachy"
BUNDLE_NAME="${APP_NAME}.app"
INSTALL_PATH="/Applications/${BUNDLE_NAME}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

echo "==> Building latest app..."
./build.sh

echo "==> Installing to ${INSTALL_PATH}..."
rm -rf "${INSTALL_PATH}"
cp -R "${BUNDLE_NAME}" "${INSTALL_PATH}"

echo "==> Restarting ${APP_NAME}..."
pkill -f "${INSTALL_PATH}/Contents/MacOS/${APP_NAME}" 2>/dev/null || true
sleep 1
open "${INSTALL_PATH}"

echo "==> Running latest installed version."
