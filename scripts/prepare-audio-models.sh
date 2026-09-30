#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Exact upstream release graph, never a moving branch or an unverified model.
model_sha=77164d6a581fafb2a31f53fd8ffde44c07cf618472952a4cdba14e68dda3b8b9
sdk_sha=7a1280bbb1701ea514f71828765237e7896e0f2e1cd332f1f70dbd5c3e33aca3
[[ "$(uname -m)" == arm64 ]] || { printf 'Current audio runtime requires Apple Silicon.\n' >&2; exit 1; }
mkdir -p Vendor/models Vendor/onnxruntime dist
if [[ ! -f Vendor/models/hop128.onnx ]] || [[ "$(shasum -a 256 Vendor/models/hop128.onnx | cut -d' ' -f1)" != "$model_sha" ]]; then
    curl --fail --location --retry 2 --output Vendor/models/hop128.onnx.download 'https://media.githubusercontent.com/media/sweetspotsoundsystem/stemgen-rt/61df8f4aa1555ef110308d01ea92b54ace770979/model/model.onnx'
    [[ "$(shasum -a 256 Vendor/models/hop128.onnx.download | cut -d' ' -f1)" == "$model_sha" ]]
    mv Vendor/models/hop128.onnx.download Vendor/models/hop128.onnx
fi
if [[ ! -f Vendor/onnxruntime/lib/libonnxruntime.1.26.0.dylib || ! -f Vendor/onnxruntime/include/onnxruntime_cxx_api.h || ! -f Vendor/onnxruntime/ThirdPartyNotices.txt ]]; then
    [[ "$(uname -m)" == arm64 ]] || { printf 'Current audio runtime requires Apple Silicon.\n' >&2; exit 1; }
    curl --fail --location --retry 2 --output dist/onnxruntime-sdk.tgz 'https://github.com/microsoft/onnxruntime/releases/download/v1.26.0/onnxruntime-osx-arm64-1.26.0.tgz'
    [[ "$(shasum -a 256 dist/onnxruntime-sdk.tgz | cut -d' ' -f1)" == "$sdk_sha" ]]
    tar -xzf dist/onnxruntime-sdk.tgz -C Vendor/onnxruntime --strip-components=2
fi
printf 'Local audio model and native runtime ready.\n'
