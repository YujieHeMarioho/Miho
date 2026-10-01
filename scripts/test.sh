#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
./scripts/prepare-audio-models.sh
swift test "$@"
