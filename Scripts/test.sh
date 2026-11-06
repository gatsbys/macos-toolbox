#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/work/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/work/ModuleCache"
swift test --scratch-path work/swift-build --cache-path work/swift-cache \
  --disable-sandbox -Xswiftc -disable-sandbox
