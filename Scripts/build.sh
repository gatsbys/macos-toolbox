#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
./Scripts/setup-signing.sh
mkdir -p work outputs
if ! xcodebuild -project Toolbox.xcodeproj -scheme Toolbox -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath work/DerivedData \
  CLANG_MODULE_CACHE_PATH="$PWD/work/ModuleCache" \
  OTHER_SWIFT_FLAGS='$(inherited) -disable-sandbox' build > work/build-release.log 2>&1; then
  tail -n 60 work/build-release.log
  exit 1
fi
./Scripts/verify-signature.sh work/DerivedData/Build/Products/Release/Toolbox.app com.cristian.Toolbox
toolbox_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Toolbox/Info.plist)
toolbox_destination="outputs/Toolbox-$toolbox_version"
mkdir -p "$toolbox_destination"
ditto work/DerivedData/Build/Products/Release/Toolbox.app "$toolbox_destination/Toolbox.app"
codesign --verify --deep --strict "$toolbox_destination/Toolbox.app"
ditto -c -k --sequesterRsrc --keepParent "$toolbox_destination/Toolbox.app" "outputs/Toolbox-$toolbox_version-macOS.zip"
cp "outputs/Toolbox-$toolbox_version-macOS.zip" outputs/Toolbox-macOS.zip
print "Aplicación: $toolbox_destination/Toolbox.app"
print "ZIP: outputs/Toolbox-$toolbox_version-macOS.zip"
print 'Para arrancar en local: ./Scripts/dev.sh (ruta e identidad de desarrollo estables).'
