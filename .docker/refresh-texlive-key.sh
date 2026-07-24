#!/usr/bin/env bash
set -euo pipefail

# refresh-texlive-key.sh — Re-vendor the TeX Live signing key
#
# The image build verifies the install-tl bootstrapper against the vendored copy
# of TUG's public key (texlive-pubkey.asc, next to this script). TUG renews the
# signing subkey periodically; once a newer TL_SNAPSHOT's installer is signed by
# a subkey the vendored copy lacks, `install-texlive.sh`'s `gpg --verify` fails
# during the image build. This script re-fetches the key by its stable primary
# fingerprint and re-exports it, so the vendored copy carries the current subkeys
# again.
#
# The primary fingerprint is the trust anchor: `--recv-keys` accepts only the
# key whose material matches it, so the keyserver cannot substitute a different
# key. The refresh runs in a throwaway keyring, never touching the user's, and
# writes texlive-pubkey.asc beside itself.
#
# Requires gpg and network access. Run it, then commit the updated key:
#   make refresh-texlive-key   (or: ./.docker/refresh-texlive-key.sh)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# TUG "TeX Live Distribution <tex-live@tug.org>" primary key.
FINGERPRINT="C78B82D8C79512F79CC0D7C80D5E5D9106BAB6BC"
KEYSERVER="keyserver.ubuntu.com"
KEY_FILE="${SCRIPT_DIR}/texlive-pubkey.asc"

command -v gpg > /dev/null 2>&1 || {
  echo "ERROR: gpg is required but not found" >&2
  exit 2
}

# Isolated keyring so the refresh never touches the user's gpg home.
GNUPGHOME="$(mktemp -d)"
export GNUPGHOME
trap 'rm -rf "${GNUPGHOME}"' EXIT

echo "Fetching ${FINGERPRINT} from ${KEYSERVER} ..." >&2
gpg --keyserver "${KEYSERVER}" --recv-keys "0x${FINGERPRINT}" || {
  echo "ERROR: could not fetch the key (keyserver unreachable?)" >&2
  exit 2
}

# --recv-keys only imports the matching fingerprint; confirm it landed before
# overwriting the vendored copy.
gpg --list-keys "0x${FINGERPRINT}" > /dev/null 2>&1 || {
  echo "ERROR: keyserver did not return the pinned key ${FINGERPRINT}" >&2
  exit 2
}

gpg --export --armor --export-options export-minimal "0x${FINGERPRINT}" > "${KEY_FILE}"
echo "Wrote ${KEY_FILE}" >&2

# Print the key so the maintainer can note the new subkey expiry for the runbook.
gpg --show-keys --with-fingerprint "${KEY_FILE}"
