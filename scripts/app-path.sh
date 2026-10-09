#!/bin/bash
# Resolve relative outputs against the repository before any build work starts.
resolve_app_path() {
    local candidate="${MIHO_APP_PATH:-$PWD/dist/Miho.app}"
    case "$candidate" in
        *.app) ;;
        *) printf 'MIHO_APP_PATH must end in .app: %s\n' "$candidate" >&2; return 1 ;;
    esac
    [[ "$candidate" == /* ]] || candidate="$PWD/$candidate"
    printf '%s\n' "$candidate"
}
