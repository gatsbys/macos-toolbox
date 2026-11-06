#!/bin/zsh
# Integration regression: a changed app version must satisfy the prior DR.
# Builds disposable copies only; never launches apps or changes TCC grants.
set -euo pipefail
cd "${0:A:h:h}"
./Scripts/dev.sh --build-only
toolbox_test_dir=$(mktemp -d "$PWD/work/signing-test.XXXXXX")
trap 'rm -rf "$toolbox_test_dir"' EXIT
toolbox_first="$toolbox_test_dir/first.app"
toolbox_second="$toolbox_test_dir/second.app"
ditto work/DerivedData/Build/Products/Debug/Toolbox.app "$toolbox_first"
cp Toolbox/Info.plist "$toolbox_test_dir/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 999999' "$toolbox_test_dir/Info.plist"
if ! xcodebuild -project Toolbox.xcodeproj -scheme Toolbox -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$toolbox_test_dir/DerivedData" \
  INFOPLIST_FILE="$toolbox_test_dir/Info.plist" \
  CLANG_MODULE_CACHE_PATH="$PWD/work/ModuleCache" \
  OTHER_SWIFT_FLAGS='$(inherited) -disable-sandbox' build > work/test-signing.log 2>&1; then
  tail -n 60 work/test-signing.log
  exit 1
fi
ditto "$toolbox_test_dir/DerivedData/Build/Products/Debug/Toolbox.app" "$toolbox_second"
for toolbox_app in "$toolbox_first" "$toolbox_second"; do
  ./Scripts/verify-signature.sh "$toolbox_app" com.cristian.Toolbox.debug
  codesign -d -r- "$toolbox_app" 2>&1 | sed -n 's/^designated => //p' > "$toolbox_app.req"
  codesign -dvvv "$toolbox_app" 2>&1 | sed -n 's/^CDHash=//p' > "$toolbox_app.hash"
  [[ -s "$toolbox_app.req" && -s "$toolbox_app.hash" ]] || { print -u2 'No se pudo inspeccionar la firma.'; exit 1; }
done
if cmp -s "$toolbox_first.hash" "$toolbox_second.hash"; then
  print -u2 'La prueba necesita dos compilaciones distintas.'
  exit 1
fi
cmp "$toolbox_first.req" "$toolbox_second.req"
codesign --verify --strict -R "$toolbox_first.req" "$toolbox_second"
codesign --verify --strict -R "$toolbox_second.req" "$toolbox_first"
# Ensure the guard catches a reintroduced ad-hoc signature.
codesign --force --sign - "$toolbox_second"
if ./Scripts/verify-signature.sh "$toolbox_second" com.cristian.Toolbox.debug; then
  print -u2 'ERROR: se aceptó una firma ad hoc.'
  exit 1
fi
print 'OK: dos compilaciones diferentes conservan la identidad; firma ad hoc rechazada.'
