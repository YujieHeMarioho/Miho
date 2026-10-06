#!/bin/bash
# Read-only environment check: no downloads, builds or system configuration changes.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
failed=0
check() {
    if "$@"; then printf 'OK: %s\n' "$*"; else printf 'Missing: %s\n' "$*" >&2; failed=1; fi
}
check test "$(uname -s)" = Darwin
check test "$(uname -m)" = arm64
check command -v swift
check command -v codesign
check command -v iconutil
if [[ "${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null || true)}" == */CommandLineTools ]]; then
    printf 'XCTest requires full Xcode. Install Xcode or set DEVELOPER_DIR to its Contents/Developer.\n' >&2
    failed=1
fi
for file in Vendor/models/hop128.onnx Vendor/onnxruntime/lib/libonnxruntime.1.26.0.dylib Vendor/onnxruntime/include/onnxruntime_cxx_api.h Resources/Models/beatnet.onnx; do
    check test -s "$file"
done
printf 'Doctor checks file presence only; build/runtime verify model integrity.\n'
exit "$failed"
