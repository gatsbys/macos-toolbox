#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
if (( $# > 1 )) || { (( $# == 1 )) && [[ "$1" != '--build-only' ]]; }; then
  print -u2 'Uso: ./Scripts/dev.sh [--build-only]'
  exit 1
fi
./Scripts/setup-signing.sh
mkdir -p work
if ! xcodebuild -project Toolbox.xcodeproj -scheme Toolbox -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath work/DerivedData \
  CLANG_MODULE_CACHE_PATH="$PWD/work/ModuleCache" \
  OTHER_SWIFT_FLAGS='$(inherited) -disable-sandbox' build > work/build-debug.log 2>&1; then
  tail -n 60 work/build-debug.log
  exit 1
fi
toolbox_built_app="$PWD/work/DerivedData/Build/Products/Debug/Toolbox.app"
./Scripts/verify-signature.sh "$toolbox_built_app" com.cristian.Toolbox.debug
if [[ "${1:-}" == '--build-only' ]]; then
  print "Compilación verificada: $toolbox_built_app"
  exit 0
fi
# Install only after a successful build; stop existing Toolbox processes before
# replacing executable pages or starting a second mouse/clipboard monitor.
xcrun swift -module-cache-path "$PWD/work/ModuleCache" Scripts/install-dev.swift "$toolbox_built_app"
/usr/bin/open "$HOME/Applications/Toolbox Dev.app"
print "Desarrollo: $HOME/Applications/Toolbox Dev.app"
