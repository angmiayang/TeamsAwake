#!/bin/bash
# One-time setup: create a local code-signing identity so macOS stops
# revoking TeamsAwake's Accessibility permission on every rebuild.
#
# Why this is needed:
#   An ad-hoc signature has no certificate, so macOS keys the Accessibility
#   grant to the exact binary hash. Re-signing changes that hash and orphans
#   the grant. With a real certificate the app's designated requirement becomes
#   certificate-based, and the grant survives every future rebuild.
#
# This is a self-signed certificate, trusted only on this Mac, only for code
# signing. It is not an Apple Developer certificate and cannot notarize or
# distribute anything. It is worthless to anyone else.
#
# Run:  ./scripts/setup-signing.sh
# You will be asked for your login password once, by sudo, for the trust step.

set -euo pipefail

NAME="TeamsAwake Local Signing"
DIR="$HOME/Library/Application Support/TeamsAwake/signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

echo "==> 1/5  checking for an existing identity"
if security find-identity -v -p codesigning | grep -q "$NAME"; then
  echo "    '$NAME' already exists and is valid. Nothing to do."
  security find-identity -v -p codesigning | grep "$NAME"
  exit 0
fi

echo "==> 2/5  generating key and certificate in $DIR"
mkdir -p "$DIR"
chmod 700 "$DIR"
cd "$DIR"

cat > req.cnf <<'CNF'
[req]
distinguished_name = dn
x509_extensions    = v3
prompt             = no
[dn]
CN = TeamsAwake Local Signing
[v3]
basicConstraints     = critical,CA:false
keyUsage             = critical,digitalSignature
extendedKeyUsage     = critical,codeSigning
subjectKeyIdentifier = hash
CNF

openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout key.pem -out cert.pem -config req.cnf
chmod 600 key.pem

# Legacy PBE algorithms, because /usr/bin/security cannot read modern
# AES-encrypted PKCS#12 bundles.
openssl pkcs12 -export -inkey key.pem -in cert.pem -out id.p12 \
  -passout pass:teamsawake -name "$NAME" \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1
chmod 600 id.p12

echo "==> 3/5  importing into the login keychain"
# -T /usr/bin/codesign + -A pre-authorise codesign so it never prompts later.
security import id.p12 -k "$KEYCHAIN" -P teamsawake -T /usr/bin/codesign -A

echo "==> 4/5  marking it trusted for code signing (sudo will ask for your password)"
echo "    Trust is limited to code signing (-p codeSign). It does not affect"
echo "    web browsing, TLS, or anything else."
sudo security add-trusted-cert -d -r trustRoot -p codeSign \
  -k /Library/Keychains/System.keychain cert.pem

echo "==> 5/5  verifying"
if security find-identity -v -p codesigning | grep -q "$NAME"; then
  echo
  echo "SUCCESS — codesign can now use this identity:"
  security find-identity -v -p codesigning | grep "$NAME"
  echo
  echo "SHA-1 fingerprint:"
  openssl x509 -in cert.pem -noout -fingerprint -sha1 | sed 's/.*=//'
  echo

  # The private key now lives in the keychain, so these plaintext copies are
  # redundant. They matter because anyone able to read this key could sign a
  # binary matching TeamsAwake's designated requirement and thereby inherit
  # its Accessibility grant, which is full synthetic keyboard and mouse
  # control, with no fresh permission prompt. Keep the key in one place only.
  rm -f key.pem id.p12
  echo "Removed the on-disk private key copies (key.pem, id.p12)."
  echo "The key now exists only in your login keychain. cert.pem is public and"
  echo "is kept so you can identify the certificate later."
  echo
  echo "Next: rebuild and install with"
  echo "  ./install.sh"
  echo "You will grant Accessibility access ONE final time. After that,"
  echo "rebuilds keep the grant."
else
  echo
  echo "FAILED — the identity is present but not valid for code signing."
  echo "Check the trust setting in Keychain Access:"
  echo "  open -a 'Keychain Access'  ->  System  ->  '$NAME'"
  echo "Set 'Code Signing' to 'Always Trust'."
  exit 1
fi
