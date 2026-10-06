#!/bin/bash
# Source this helper; publish a download only after SHA-256 verification.
download_verified() {
    local url="$1" expected="$2" destination="$3" temporary actual
    temporary=$(mktemp "${destination}.download.XXXXXX") || return 1
    if ! curl --fail --location --retry 2 --connect-timeout 20 --max-time 600 --output "$temporary" "$url"; then
        printf 'Download failed: %s\n' "$url" >&2
        rm -f "$temporary"
        return 1
    fi
    actual=$(shasum -a 256 "$temporary" | cut -d' ' -f1)
    if [[ "$actual" != "$expected" ]]; then
        printf 'SHA-256 mismatch for %s: expected %s, got %s\n' "$destination" "$expected" "$actual" >&2
        rm -f "$temporary"
        return 1
    fi
    mv "$temporary" "$destination"
}
