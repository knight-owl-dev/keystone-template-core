# Pinned by digest; the tag is documentation (Docker resolves by digest).
# Re-resolve on a bump:
#   docker buildx imagetools inspect pandoc/minimal:<tag> --format '{{.Manifest.Digest}}'
#
# We unfold from pandoc/minimal (pandoc binary + runtime libs, multi-arch, no
# TeX Live) and assemble our own TeX Live in the `base` stage below, rather than
# inheriting pandoc/latex's superset (scheme-basic + all-packages-pandoc-might-
# use + an unused 80MB pandoc-crossref). This ships only the package closure our
# PDFs need and lets us own the TeX Live year directly.
ARG BASE_IMAGE=pandoc/minimal:3.10.0.0-ubuntu@sha256:c179ef899a4030ad8e1e424d76812364ae79fcad826f822931c7891718b120e2

# TL_SNAPSHOT pins TeX Live to a frozen daily tlnet snapshot
# (texlive.info/tlnet-archive) so install-tl and every `tlmgr install` resolve a
# fixed package set — reproducible builds, no dependency on live CTAN. We
# install FROM this snapshot, so the installed TeX Live year is the snapshot's
# by construction. Advance it periodically to pick up upstream fixes.
ARG TL_SNAPSHOT=2026/08/12

# ATTRIBUTION: every component this image redistributes under its own license
# MUST have a matching entry in NOTICE.md — proper attribution, and a
# self-check that we ship nothing whose license we have not reviewed. Each stage
# below names its additions and the NOTICE section they belong in; confirm a
# TeX Live package's license with `tlmgr info <pkg>` (the cat-license field).

# --- yq download (runs in parallel with the main build) ---
FROM alpine:3.24@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b AS yq
# Throwaway stage — only the yq binary reaches the final image.
# Attribute yq in NOTICE.md under "Primary Tools".
ARG YQ_VERSION=v4.53.3
# Per-arch release-asset sha256, pinned with YQ_VERSION (bump together); not
# fetched at build — a same-release fetch verifies nothing. On a bump, read the
# new hashes from the release's checksums file (the SHA-256 column, ordered per
# checksums_hashes_order): github.com/mikefarah/yq/releases/download/<ver>/checksums
ARG YQ_CHECKSUM_AMD64=fa52a4e758c63d38299163fbdd1edfb4c4963247918bf9c1c5d31d84789eded4
ARG YQ_CHECKSUM_ARM64=578648e463a11c1b6db6010cbf41eafed6bee79466fcffa1bb446672cf7945ea
# busybox wget (no curl); sha256sum -c gates the download against the pinned hash.
RUN arch="$(apk --print-arch)" && \
    case "${arch}" in \
      x86_64)  yq_arch="amd64"; yq_sha="${YQ_CHECKSUM_AMD64}" ;; \
      aarch64) yq_arch="arm64"; yq_sha="${YQ_CHECKSUM_ARM64}" ;; \
      *)       echo "ERROR: unsupported architecture: ${arch}" >&2; exit 1 ;; \
    esac && \
    wget -qO /usr/local/bin/yq \
      "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${yq_arch}" && \
    echo "${yq_sha}  /usr/local/bin/yq" > /tmp/yq.sha256 && \
    sha256sum -c /tmp/yq.sha256 && \
    chmod +x /usr/local/bin/yq

# --- assembled TeX Live base (builder) ---
# pandoc/minimal ships no TeX Live, so we install our own: install-tl fetches
# scheme-infraonly from the pinned snapshot, then `tlmgr install` adds the
# general pandoc/XeLaTeX package closure our PDFs need. This stage is a BUILDER —
# it carries the build-only toolchain (perl for tlmgr, gnupg/wget for install-tl,
# xzdec) which never reaches the runtime image: the final stage COPYs the
# finished /opt/texlive tree into a fresh pandoc/minimal that has only runtime
# libs. Docker layers are additive, so a build tool installed here could not be
# reclaimed by purging downstream — the COPY-into-clean-stage is what drops it.
#
# It holds only format-agnostic, non-Keystone packages; Keystone's own packages
# layer on in the keystone-tex stage. That seam keeps the base separable — an
# external pandoc-latex image could take its place. The fonts and keystone-tex
# stages derive FROM it, inheriting the TeX Live install and its pinned tlmgr
# repository.
#
# Attribute TeX Live in NOTICE.md under "TeX Live Packages" (alphabetical).
FROM ${BASE_IMAGE} AS base
ARG TL_SNAPSHOT
# Build-only toolchain (perl/gnupg/wget/xzdec) plus the font libraries fmtutil
# needs; none carry into the runtime image (see the final stage's own apt).
RUN apt-get -q --no-allow-insecure-repositories update && \
    DEBIAN_FRONTEND=noninteractive apt-get install --assume-yes --no-install-recommends \
      fontconfig=\* \
      gnupg=\* \
      gzip=\* \
      libfontconfig1=\* \
      libfreetype6=\* \
      perl=\* \
      tar=\* \
      wget=\* \
      xzdec=\* && \
    rm -rf /var/lib/apt/lists/*
ENV PATH="/opt/texlive/texdir/bin/default:${PATH}"
# The babel-*/hyphen-* set below is exact parity with what pandoc/latex
# bundled — the languages an author can select via `lang:` today. Listed
# explicitly (not via collection-lang*, which drag in hundreds of MB of docs
# and fonts). Non-Latin scripts (CJK, Arabic, Indic) are out of scope here;
# they would ship as a separate engine variant with the fonts they need.
#
# `ec` has no direct consumer here: it carries ectt1000.tfm, which soul.sty
# loads at package load. Pandoc pulls soul in for `.mark`/`.underline` under
# XeLaTeX, and with no mf in the image there is no mktextfm fallback.
COPY .docker/install-texlive.sh /tmp/install-texlive.sh
COPY .docker/texlive-pubkey.asc /tmp/texlive-pubkey.asc
RUN /tmp/install-texlive.sh && rm /tmp/install-texlive.sh /tmp/texlive-pubkey.asc && \
    tlmgr install \
      amsfonts \
      amsmath \
      babel \
      babel-basque \
      babel-czech \
      babel-danish \
      babel-dutch \
      babel-english \
      babel-finnish \
      babel-french \
      babel-german \
      babel-hungarian \
      babel-italian \
      babel-norsk \
      babel-polish \
      babel-portuges \
      babel-spanish \
      babel-swedish \
      bidi \
      bookmark \
      booktabs \
      caption \
      ec \
      fancyvrb \
      float \
      fontspec \
      footnotehyper \
      framed \
      geometry \
      graphics \
      hyperref \
      hyphen-basque \
      hyphen-czech \
      hyphen-danish \
      hyphen-dutch \
      hyphen-english \
      hyphen-finnish \
      hyphen-french \
      hyphen-german \
      hyphen-hungarian \
      hyphen-italian \
      hyphen-norwegian \
      hyphen-polish \
      hyphen-portuguese \
      hyphen-spanish \
      hyphen-swedish \
      iftex \
      latex \
      lm \
      lm-math \
      microtype \
      multirow \
      parskip \
      setspace \
      soul \
      tools \
      ulem \
      unicode-math \
      upquote \
      xcolor \
      xetex \
      xurl && \
    fmtutil-sys --all && \
    chmod -R o+w /opt/texlive/texdir/texmf-var

# --- font extractor (throwaway stage) ---
# Installs the font packages from the pinned snapshot, then stages only the
# files the registry references (via extract-fonts.sh + list-builtin-fonts.lua).
# Only that staged tree reaches the final image; the full packages' pdfLaTeX
# dead weight (.pfb/.tfm/.vf/.fd and unused weights) is discarded with this
# stage. Reclaiming those bytes needs a separate stage — Docker layers are
# additive, so purging them in the final stage would free nothing.
#
# Attribute these in NOTICE.md under "Fonts" — still redistributed, now as the
# extracted files:
#   dejavu        — DejaVu font families (TTF)
#   ebgaramond    — EB Garamond font family
#   fourier       — Fourier ornaments OTF (fleurons, manicules, pilcrows)
#   imfellenglish — IM Fell English fonts; ships FeFlow1/2 floral ornament OTFs
#   libertine     — Linux Libertine / Biolinum font families
#   noto          — Noto Sans Mono (TTF); modern, broad-coverage code face
#   sourcecodepro — Adobe Source Code Pro OTF; modern code face
#   tex-gyre      — TeX Gyre font families
# lm and lm-math also ship (extracted below): the base stage installs them for
# the default and math fonts, so this stage inherits their files — no re-install.
FROM base AS fonts
RUN tlmgr install \
      dejavu \
      ebgaramond \
      fourier \
      imfellenglish \
      libertine \
      noto \
      sourcecodepro \
      tex-gyre
# The extractor reads the file list from the registry, so it needs the filters
# tree (font-registry.lua + loader + its ks_require deps). pandoc lua is the
# convenient standard-Lua interpreter already in the base image.
COPY .pandoc/filters /tmp/filters
COPY .docker/extract-fonts.sh /tmp/extract-fonts.sh
RUN /tmp/extract-fonts.sh pandoc lua /tmp/filters/lib/list-builtin-fonts.lua

# --- Keystone TeX Live layer (builder) ---
# Keystone's own packages atop the general `base`. Still a builder: the final
# runtime stage COPYs this stage's finished /opt/texlive tree.
FROM base AS keystone-tex

# Attribute these in NOTICE.md under "TeX Live Packages" (alphabetical):
#   draftwatermark — watermark overlay for draft documents
#   endnotes     — \endnote / \theendnotes for collected endnotes (note placement)
#   fancyhdr     — page-layout package (page-layout-fancyhdr.tex)
#   fvextra      — fancyvrb extensions for code listings
#   hyperxmp     — embeds keywords/metadata into PDF Info dict and XMP stream
#   koma-script  — KOMA-Script document classes (scrbook, scrartcl, scrreprt)
#                  plus scrlayer-scrpage.sty for fancyhdr-free page layout
#   lettrine     — drop caps (\lettrine command)
#   lineno       — line numbering (used by pandoc)
#   pdfcol       — tcolorbox skins dependency (color stacks)
#   psnfss       — provides pifont.sty for Dingbat symbols (base-packages.tex)
#   ragged2e     — hyphenation-preserving ragged-right (\RaggedRight, \justifying)
#   tcolorbox    — colored boxes for callout/aside blocks
#   tikzfill     — tcolorbox skins dependency (fill patterns)
RUN tlmgr install \
      draftwatermark \
      endnotes \
      fancyhdr \
      fvextra \
      hyperxmp \
      koma-script \
      lettrine \
      lineno \
      pdfcol \
      psnfss \
      ragged2e \
      tcolorbox \
      tikzfill
# Drop build-time cruft the XeLaTeX runtime never reads (package docs and .dtx
# sources), then refresh the file database so the copied tree's ls-R matches.
# Reclaimed for real: the final stage COPYs this tree AFTER the removal.
RUN rm -rf /opt/texlive/texdir/texmf-dist/doc \
           /opt/texlive/texdir/texmf-dist/source \
           /opt/texlive/texdir/tlpkg/backups && \
    mktexlsr

# --- runtime image ---
# A fresh pandoc/minimal carrying ONLY runtime libraries. The assembled TeX Live
# tree and the slim fonts arrive by COPY, so the build toolchain (perl, gnupg,
# wget, xzdec) stays behind in the builder stages and never ships.
# librsvg2-bin keeps SVG→PDF (pandoc shells out to rsvg-convert); fontconfig /
# libfreetype are XeLaTeX's font runtime.
FROM ${BASE_IMAGE}
RUN apt-get -q --no-allow-insecure-repositories update && \
    DEBIAN_FRONTEND=noninteractive apt-get install --assume-yes --no-install-recommends \
      fontconfig=\* \
      libfontconfig1=\* \
      libfreetype6=\* \
      librsvg2-bin=\* && \
    rm -rf /var/lib/apt/lists/*
ENV PATH="/opt/texlive/texdir/bin/default:${PATH}"

# The assembled TeX Live tree (general base + Keystone packages), build tools
# left behind. Binaries, formats, and ls-R travel with it under /opt/texlive.
COPY --from=keystone-tex /opt/texlive /opt/texlive

COPY --from=yq /usr/local/bin/yq /usr/local/bin/yq

# Only the registry-referenced font files, staged slim by the `fonts` stage.
# The registry resolves every built-in font by explicit Path= under this root
# (font-registry.lua FONTS_ROOT), so orphaned files here — no tlmgr database
# entry — resolve fine for XeLaTeX (fontspec) and EPUB (--epub-embed-font).
COPY --from=fonts /staging/ /opt/keystone/fonts/

# IDs are pinned: the UID stamps ownership on bind-mounted build output, and an
# implicitly assigned next-free UID shifts when the base image gains an account.
RUN groupadd --gid 1001 publisher && \
    useradd --no-log-init --create-home --shell /usr/sbin/nologin \
      --uid 1001 --gid 1001 publisher

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
LABEL org.opencontainers.image.description="Keystone publishing image based on pandoc/minimal"
# --- end OCI metadata ---

# publisher
USER 1001:1001

ENTRYPOINT ["/bin/bash"]
