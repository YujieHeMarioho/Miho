#!/bin/bash
# Select a full Xcode for XCTest, without changing global xcode-select settings.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

# Fail before downloading dependencies when tests cannot load XCTest.
require_xctest() {
    local developer
    developer="${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null || true)}"
    if [[ ! -d "$developer/Platforms/MacOSX.platform/Developer/Library/Frameworks/XCTest.framework" ]]; then
        printf 'Tests require full Xcode with XCTest. Install Xcode or set DEVELOPER_DIR to Xcode.app/Contents/Developer.\n' >&2
        return 1
    fi
}
