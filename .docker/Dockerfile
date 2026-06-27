ARG BASE_IMAGE=pandoc/latex:3.9.0.2-ubuntu

# TL_SNAPSHOT pins TeX Live to a frozen daily tlnet snapshot
# (texlive.info/tlnet-archive) so `tlmgr install` resolves a fixed package
# set — reproducible builds, no dependency on live CTAN. Its year MUST match
# the TL release baked into BASE_IMAGE (the build fails loudly otherwise), so
# these two pins move together: bumping BASE_IMAGE is the moment to advance
# TL_SNAPSHOT to a current date within the new image's TL year. Refresh SOP:
# docs/maintainers/publishing-docker-image.md.
ARG TL_SNAPSHOT=2026/06/16

# --- yq download (runs in parallel with the main build) ---
FROM alpine:3.24 AS yq
# Throwaway stage — only the yq binary reaches the final image.
# yq is redistributed in the final image, so its license must stay
# attributed in src/shared/NOTICE.md (Primary Tools). See the ATTRIBUTION
# note in the main image stage below.
# hadolint ignore=DL3018
RUN apk add --no-cache curl
ARG YQ_VERSION=v4.53.3
RUN arch="$(apk --print-arch)" && \
    case "${arch}" in \
      x86_64)  yq_arch="amd64" ;; \
      aarch64) yq_arch="arm64" ;; \
      *)       echo "ERROR: unsupported architecture: ${arch}" >&2; exit 1 ;; \
    esac && \
    curl -fsSL -o /usr/local/bin/yq \
      "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${yq_arch}" && \
    chmod +x /usr/local/bin/yq

# --- main image ---
FROM ${BASE_IMAGE}

# ATTRIBUTION (license compliance): every component added to this image
# that ships under its own license MUST get a matching entry in
# src/shared/NOTICE.md — under "TeX Live Packages" for the packages below
# (or "Fonts" for font packages), and "Primary Tools" for standalone
# binaries like yq. This is both proper attribution and a self-check that
# we redistribute nothing whose license we have not reviewed. Confirm a
# package's license with `tlmgr info <pkg>` (the cat-license field).
#
# TeX Live packages (alphabetical):
#   draftwatermark — watermark overlay for draft documents
#   ebgaramond   — EB Garamond font family
#   endnotes     — \endnote / \theendnotes for collected endnotes (note placement)
#   fourier      — Fourier ornaments OTF (fleurons, manicules, pilcrows)
#   fvextra      — fancyvrb extensions for code listings
#   hyperxmp     — embeds keywords/metadata into PDF Info dict and XMP stream
#   imfellenglish — IM Fell English fonts; ships FeFlow1/2 floral ornament OTFs
#   koma-script  — KOMA-Script document classes (scrbook, scrartcl, scrreprt)
#                  plus scrlayer-scrpage.sty for fancyhdr-free page layout
#   lettrine     — drop caps (\lettrine command)
#   libertine    — Linux Libertine / Biolinum font families
#   lineno       — line numbering (used by pandoc)
#   pdfcol       — tcolorbox skins dependency (color stacks)
#   ragged2e     — hyphenation-preserving ragged-right (\RaggedRight, \justifying)
#   tcolorbox    — colored boxes for callout/aside blocks
#   tex-gyre     — TeX Gyre font families
#   tikzfill     — tcolorbox skins dependency (fill patterns)
# Re-declared here because ARGs do not cross FROM (see top-of-file pin).
ARG TL_SNAPSHOT
COPY .docker/tlmgr-update.sh /tmp/tlmgr-update.sh
RUN /tmp/tlmgr-update.sh && rm /tmp/tlmgr-update.sh && \
    tlmgr install \
      draftwatermark \
      ebgaramond \
      endnotes \
      fourier \
      fvextra \
      hyperxmp \
      imfellenglish \
      koma-script \
      lettrine \
      libertine \
      lineno \
      pdfcol \
      ragged2e \
      tcolorbox \
      tex-gyre \
      tikzfill

COPY --from=yq /usr/local/bin/yq /usr/local/bin/yq

RUN useradd --no-log-init --create-home --shell /usr/sbin/nologin publisher

WORKDIR /keystone

COPY .licenses/ /usr/share/doc/keystone/
COPY .pandoc/ .pandoc/
RUN chmod +x .pandoc/publish.sh .pandoc/import.sh .pandoc/export-sample.sh && \
    chown -R publisher:publisher /keystone

# --- OCI metadata (last to avoid busting layer cache on version bumps) ---
ARG BASE_IMAGE
ARG KEYSTONE_VERSION=local
LABEL maintainer="Knight Owl <support@knight-owl.dev>"
LABEL org.opencontainers.image.licenses="GPL-2.0-or-later"
LABEL org.opencontainers.image.authors="Knight Owl LLC"
LABEL org.opencontainers.image.source="https://github.com/knight-owl-dev/keystone"
LABEL org.opencontainers.image.base.name="${BASE_IMAGE}"
LABEL org.opencontainers.image.version="${KEYSTONE_VERSION}"
LABEL org.opencontainers.image.description="Keystone publishing image based on pandoc/latex"
# --- end OCI metadata ---

USER publisher

ENTRYPOINT ["/bin/bash"]
