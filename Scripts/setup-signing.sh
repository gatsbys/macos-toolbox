#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
toolbox_config="Config/LocalSigning.xcconfig"
# Preserve the selected signer across builds, even when other identities exist.
if (( $# == 0 )) && [[ -f "$toolbox_config" ]]; then
  print 'Firma local ya configurada. Se conserva la identidad existente.'
  exit 0
fi
toolbox_identities=$(/usr/bin/security find-identity -v -p codesigning)
if (( $# != 1 )) || [[ ! "$1" =~ '^[A-Fa-f0-9]{40}$' ]]; then
  print -u2 'Uso: ./Scripts/setup-signing.sh HUELLA_SHA1_DEL_CERTIFICADO'
  print -u2 -r -- "$toolbox_identities"
  exit 1
fi
toolbox_identity="${1:u}"
if ! print -r -- "$toolbox_identities" | /usr/bin/grep -Eq "[[:space:]]${toolbox_identity}[[:space:]]"; then
  print -u2 'La identidad elegida no está disponible para firmar en este llavero.'
  exit 1
fi
mkdir -p Config
{
  print '// Local to this Mac. Certificate/private key remain in Keychain.'
  print "CODE_SIGN_IDENTITY = $toolbox_identity"
} > "$toolbox_config"
print 'Identidad guardada en Config/LocalSigning.xcconfig para Debug y Release.'
