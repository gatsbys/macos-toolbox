#!/bin/zsh
# A hash-only designated requirement loses TCC grants on the next rebuild.
set -euo pipefail
if (( $# != 2 )); then
  print -u2 'Uso: verify-signature.sh /ruta/Toolbox.app bundle.identifier'
  exit 1
fi
toolbox_app="$1"
toolbox_expected_id="$2"
toolbox_actual_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$toolbox_app/Contents/Info.plist")
[[ "$toolbox_actual_id" == "$toolbox_expected_id" ]] || { print -u2 'Bundle ID inesperado.'; exit 1; }
/usr/bin/codesign --verify --deep --strict "$toolbox_app"
toolbox_requirement=$(/usr/bin/codesign -d -r- "$toolbox_app" 2>&1)
if [[ "$toolbox_requirement" == *cdhash* || "$toolbox_requirement" != *'certificate '* ]]; then
  print -u2 'Firma inestable: se necesita un certificado persistente, no firma ad hoc.'
  exit 1
fi
print -r -- "$toolbox_requirement"
