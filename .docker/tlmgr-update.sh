#!/usr/bin/env bash
set -euo pipefail

# tlmgr-update.sh — Pin tlmgr to a dated TeX Live snapshot
#
# Runs inside the Docker build on a pandoc/latex base image. Points tlmgr
# at a frozen daily snapshot of tlnet (texlive.info/tlnet-archive) so that
# the subsequent `tlmgr install` pulls a fixed package set. This makes the
# image reproducible over time and independent of live CTAN availability —
# every rebuild of the same source resolves the same LaTeX packages.
#
# The snapshot's TeX Live year MUST match the year baked into the base
# image: pandoc/latex ships one specific TL release, and tlmgr refuses a
# repository from a different release. The year guard below fails the
# build early with a clear message rather than letting tlmgr emit a
# cryptic cross-release error. Whenever BASE_IMAGE is bumped, move
# TL_SNAPSHOT to a current date within the new image's TL year (see the
# refresh SOP in docs/maintainers/publishing-docker-image.md).
#
# Run this before `tlmgr install`.
#
# Environment:
#   TL_SNAPSHOT — required; dated snapshot path, e.g. 2026/06/01
#
# Usage: TL_SNAPSHOT=2026/06/01 ./tlmgr-update.sh
#
# Docker usage:
#   ARG TL_SNAPSHOT=2026/06/01
#   COPY .docker/tlmgr-update.sh /tmp/tlmgr-update.sh
#   RUN /tmp/tlmgr-update.sh && rm /tmp/tlmgr-update.sh && \
#       tlmgr install <packages...>

: "${TL_SNAPSHOT:?TL_SNAPSHOT must be set (dated snapshot path, e.g. 2026/06/01)}"

# Validate the shape before deriving anything from it: a malformed value
# (e.g. a bare "2026") could pass the year guard below yet build an invalid
# repository URL, deferring the failure to a cryptic tlmgr error.
if [[ ! "${TL_SNAPSHOT}" =~ ^[0-9]{4}/[0-9]{2}/[0-9]{2}$ ]]; then
  echo "ERROR: TL_SNAPSHOT must be a dated snapshot path YYYY/MM/DD (got: ${TL_SNAPSHOT})" >&2
  exit 1
fi

SNAPSHOT_YEAR=${TL_SNAPSHOT%%/*}
INSTALLED_YEAR=$(tlmgr --version | sed -n 's/.*version \([0-9]\{4\}\).*/\1/p')

if [[ "${SNAPSHOT_YEAR}" != "${INSTALLED_YEAR}" ]]; then
  echo "ERROR: TL_SNAPSHOT year (${SNAPSHOT_YEAR}) does not match the base image's TeX Live year (${INSTALLED_YEAR})" >&2
  echo "       Bump TL_SNAPSHOT to a date within ${INSTALLED_YEAR} — see docs/maintainers/publishing-docker-image.md" >&2
  exit 1
fi

REPOSITORY="https://texlive.info/tlnet-archive/${TL_SNAPSHOT}/tlnet"
echo "Pinning tlmgr to frozen snapshot: ${REPOSITORY}"
tlmgr option repository "${REPOSITORY}"
tlmgr update --self
