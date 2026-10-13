#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [ ! -d "${PROJECT_DIR}/build/FnOS Manager.app" ]; then
    echo "==> App bundle not found. Building now..."
    "${SCRIPT_DIR}/build_app.sh"
fi

echo "==> Launching FnOS Manager.app..."
open "${PROJECT_DIR}/build/FnOS Manager.app"
