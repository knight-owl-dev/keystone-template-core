#!/usr/bin/env bash
set -euo pipefail

# install-texlive.sh — Install a minimal TeX Live from a pinned snapshot
#
# Runs inside the Docker `base` stage on a pandoc/minimal image (which ships
# pandoc + its runtime libs but NO TeX Live). It fetches the install-tl
# bootstrapper from a frozen daily tlnet snapshot (texlive.info/tlnet-archive)
# and installs `scheme-infraonly` — tlmgr and the bare infrastructure, no LaTeX
# packages yet. The caller then installs exactly the package closure our PDFs
# need, so the image carries our set rather than pandoc/latex's superset.
#
# Pinning install-tl AND its repository to the same snapshot makes the whole
# TeX Live layer reproducible and independent of live CTAN — the same source
# rebuilds resolve the same packages, and the repository pin persists so every
# later `tlmgr install` (this stage and the stages built FROM it) resolves the
# same set. Installing FROM the snapshot also means we own the TeX Live year
# directly — there is no base-image year to reconcile against.
#
# Run this before tlmgr-install.sh installs the package list.
#
# The install-tl bootstrapper is verified against the vendored TUG public key
# (KEY_FILE) rather than a keyserver fetch, so the trust anchor is pinned in the
# repo and the build needs no keyserver at build time. Refresh the key after an
# upstream rotation with `make refresh-texlive-key` (refresh-texlive-key.sh).
#
# That verified bootstrapper also carries the keyring that verifies what comes
# after it; tlmgr-install.sh asserts the result.
#
# Environment:
#   TL_SNAPSHOT — required; dated snapshot path, e.g. 2026/06/16
#   KEY_FILE    — vendored TeX Live signing key (default /tmp/texlive-pubkey.asc)
#
# Usage: TL_SNAPSHOT=2026/06/16 ./install-texlive.sh

: "${TL_SNAPSHOT:?TL_SNAPSHOT must be set (dated snapshot path, e.g. 2026/06/16)}"

if [[ ! "${TL_SNAPSHOT}" =~ ^[0-9]{4}/[0-9]{2}/[0-9]{2}$ ]]; then
  echo "ERROR: TL_SNAPSHOT must be a dated snapshot path YYYY/MM/DD (got: ${TL_SNAPSHOT})" >&2
  exit 1
fi

KEY_FILE="${KEY_FILE:-/tmp/texlive-pubkey.asc}"
if [[ ! -f "${KEY_FILE}" ]]; then
  echo "ERROR: TeX Live signing key not found: ${KEY_FILE}" >&2
  exit 1
fi

INSTALLER_URL="https://texlive.info/tlnet-archive/${TL_SNAPSHOT}/tlnet"

# Per-arch precompiled-binary selector, matched by install-tl against the
# snapshot's binary sets (e.g. x86_64-linux, aarch64-linux). Assigned in two
# steps so each command substitution is a sole right-hand side — set -e then
# catches a failing uname (a concatenated "$(a)-$(b)" would mask it).
machine="$(uname -m)"
kernel="$(uname -s | tr '[:upper:]' '[:lower:]')"
TEXLIVE_ARCH="${machine}-${kernel}"

# scheme-infraonly: tlmgr + infrastructure only. Doc/src files off and no
# format pre-build here — the engines (and their formats) arrive with the
# package install that follows. For what each key and path below means, see the
# PROFILES section of https://tug.org/texlive/doc/install-tl.html
cat > /tmp/texlive.profile << PROFILE
selected_scheme scheme-infraonly
TEXDIR         /opt/texlive/texdir
TEXMFLOCAL     /opt/texlive/texmf-local
TEXMFSYSVAR    /opt/texlive/texdir/texmf-var
TEXMFSYSCONFIG /opt/texlive/texdir/texmf-config
TEXMFVAR       ~/.texlive/texmf-var
TEXMFCONFIG    ~/.texlive/texmf-config
TEXMFHOME      ~/texmf
binary_${TEXLIVE_ARCH} 1
instopt_adjustpath 0
instopt_adjustrepo 0
instopt_letter 0
instopt_portable 0
tlpdbopt_autobackup 0
tlpdbopt_create_formats 0
tlpdbopt_install_docfiles 0
tlpdbopt_install_srcfiles 0
tlpdbopt_sys_bin /usr/local/bin
tlpdbopt_sys_info /usr/local/share/info
tlpdbopt_sys_man /usr/local/share/man
PROFILE

cd /tmp

# Fetch the bootstrapper and its checksum + signature from the snapshot.
wget -4 --no-verbose \
  "${INSTALLER_URL}/install-tl-unx.tar.gz" \
  "${INSTALLER_URL}/install-tl-unx.tar.gz.sha512" \
  "${INSTALLER_URL}/install-tl-unx.tar.gz.sha512.asc"

# Verify the checksum file's signature with gpgv against a keyring of just the
# vendored TUG key: a good signature means it came from that pinned key, with no
# web-of-trust model (and so no misleading "not certified" warning). If the key
# rotated upstream the vendored copy can't verify a newer installer; fail with the
# fix in the message rather than ship it unverified.
gpg --dearmor < "${KEY_FILE}" > /tmp/tl-keyring.gpg
if ! gpgv --keyring /tmp/tl-keyring.gpg \
  install-tl-unx.tar.gz.sha512.asc install-tl-unx.tar.gz.sha512; then
  echo "ERROR: install-tl signature did not verify against the vendored TeX Live key" >&2
  echo "  The upstream key may have rotated —" >&2
  echo "  refresh it with 'make refresh-texlive-key', then rebuild" >&2
  exit 1
fi
# Echo the key so its subkey expiry lands in every build log — a passive,
# always-current refresh reminder, with no date to keep in sync in the docs.
gpg --show-keys "${KEY_FILE}"
sha512sum -c install-tl-unx.tar.gz.sha512

mkdir -p ./install-tl
tar --strip-components 1 -zxf install-tl-unx.tar.gz -C ./install-tl

# install-tl lays binaries under bin/<arch>; point a stable `default` at it so
# the image's PATH (set in the Dockerfile) needs no arch knowledge. The target
# does not exist until install-tl runs — a dangling symlink now, resolved after.
mkdir -p /opt/texlive/texdir/bin
ln -sf "/opt/texlive/texdir/bin/${TEXLIVE_ARCH}" /opt/texlive/texdir/bin/default

./install-tl/install-tl \
  -repository "${INSTALLER_URL}" \
  --profile=/tmp/texlive.profile

# Pin the snapshot as tlmgr's repository — the sole setter of it (the profile's
# instopt_adjustrepo is 0, so install-tl does not touch it). Every later `tlmgr
# install` (this stage and the keystone-tex and fonts stages built FROM it) then
# resolves against the same frozen set — reproducible, never live CTAN.
tlmgr option repository "${INSTALLER_URL}"

rm -rf ./install-tl \
  install-tl-unx.tar.gz \
  install-tl-unx.tar.gz.sha512 \
  install-tl-unx.tar.gz.sha512.asc \
  /tmp/tl-keyring.gpg \
  /tmp/texlive.profile
