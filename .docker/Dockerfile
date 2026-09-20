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

# --- yq ---
# Throwaway stage — only the yq binary reaches the final image.
FROM mikefarah/yq:4.53.6@sha256:cfc4eee658595834ef304eadb0c3ea721f3b7cb6404ad8b7cb909cc5b5145b23 AS yq

# --- assembled TeX Live base (builder) ---
# pandoc/minimal ships no TeX Live, so we install our own: install-tl fetches
# scheme-infraonly from the pinned snapshot, then tlmgr adds the
# general pandoc/XeLaTeX package closure our PDFs need. This stage is a BUILDER —
# nothing it installs is carried into the runtime image: the final stage COPYs
# the finished /opt/texlive tree into a fresh pandoc/minimal instead. Docker
# layers are additive, so a build tool installed here could not be reclaimed by
# purging downstream — the COPY-into-clean-stage drops it.
#
# base-fonts installs first: the closure below pulls its packages in as
# dependencies whether or not they are named, and tlmgr adds nothing to a
# package already present.
#
# It holds only format-agnostic, non-Keystone packages; Keystone's own packages
# layer on in the keystone-tex stage. That seam keeps the base separable — an
# external pandoc-latex image could take its place. The fonts and keystone-tex
# stages derive FROM it, inheriting the TeX Live install and its pinned tlmgr
# repository.
FROM ${BASE_IMAGE} AS base
ARG TL_SNAPSHOT
COPY .docker/keystone.aptconf /etc/apt/apt.conf
# Not removed with install-tl below: the fonts and keystone-tex stages build
# FROM here and install from this tree.
COPY .docker/packages /tmp/packages
RUN /tmp/packages/apt-install.sh \
      --from-file /tmp/packages/apt/bootstrap.build.packages \
      --from-file /tmp/packages/apt/fonts.runtime.packages
ENV PATH="/opt/texlive/texdir/bin/default:${PATH}"
COPY .docker/install-texlive.sh /tmp/install-texlive.sh
COPY .docker/texlive-pubkey.asc /tmp/texlive-pubkey.asc
RUN /tmp/install-texlive.sh && rm /tmp/install-texlive.sh /tmp/texlive-pubkey.asc && \
    /tmp/packages/tlmgr-install.sh --with-doc \
      --from-file /tmp/packages/tlmgr/base-fonts.packages && \
    /tmp/packages/tlmgr-install.sh \
      --from-file /tmp/packages/tlmgr/base.packages \
      --from-file /tmp/packages/tlmgr/babel.packages \
      --from-file /tmp/packages/tlmgr/hyphen.packages && \
    fmtutil-sys --all && \
    chmod -R o+w /opt/texlive/texdir/texmf-var

# --- font extractor (throwaway stage) ---
# Installs the font packages from the pinned snapshot, then stages the files the
# registry references (via extract-fonts.sh + list-builtin-fonts.lua) and each
# family's license beside them, refusing a license the registry names and the
# copy list never staged. Only that staged tree reaches the final image:
# Docker layers are additive, so the packages and their docs could not be
# reclaimed downstream, and discarding this stage is what drops them.
#
FROM base AS fonts
RUN /tmp/packages/tlmgr-install.sh --with-doc \
      --from-file /tmp/packages/tlmgr/fonts.packages
# The extractor reads the file list from the registry, so it needs the filters
# tree (font-registry.lua + loader + its ks_require deps). pandoc lua is the
# convenient standard-Lua interpreter already in the base image.
COPY .pandoc/filters /tmp/filters
COPY .docker/fonts /tmp/fonts
RUN /tmp/fonts/extract-fonts.sh pandoc lua /tmp/filters/lib/list-builtin-fonts.lua && \
    /tmp/fonts/extract-font-licenses.sh /tmp/fonts/licenses.copy.txt \
      pandoc lua /tmp/filters/lib/list-builtin-font-licenses.lua

# --- Keystone TeX Live layer (builder) ---
# Keystone's own packages atop the general `base`. Still a builder: the final
# runtime stage COPYs this stage's finished /opt/texlive tree.
FROM base AS keystone-tex
RUN /tmp/packages/tlmgr-install.sh --from-file /tmp/packages/tlmgr/keystone-tex.packages
# Drop build-time cruft the XeLaTeX runtime never reads (package docs and .dtx
# sources), then refresh the file database so the copied tree's ls-R matches.
# Reclaimed for real: the final stage COPYs this tree AFTER the removal.
RUN rm -rf /opt/texlive/texdir/texmf-dist/doc \
           /opt/texlive/texdir/texmf-dist/source \
           /opt/texlive/texdir/tlpkg/backups && \
    mktexlsr

# --- runtime image ---
# A fresh pandoc/minimal, so nothing the builder stages installed is carried in.
# The assembled TeX Live tree and the slim fonts arrive by COPY; the apt layer
# below is the only one this image installs for itself.
FROM ${BASE_IMAGE}
COPY .docker/keystone.aptconf /etc/apt/apt.conf
COPY .docker/packages /tmp/packages
RUN /tmp/packages/apt-install.sh \
      --from-file /tmp/packages/apt/fonts.runtime.packages \
      --from-file /tmp/packages/apt/engine.runtime.packages && \
    rm -rf /tmp/packages
# The rm leaves the running container with no build input in its filesystem.
# Layers being additive, it reclaims nothing — the base stage above says why.
ENV PATH="/opt/texlive/texdir/bin/default:${PATH}"

# The assembled TeX Live tree (general base + Keystone packages), build tools
# left behind. Binaries, formats, and ls-R travel with it under /opt/texlive.
COPY --from=keystone-tex /opt/texlive /opt/texlive

COPY --from=yq /usr/bin/yq /usr/local/bin/yq

# The registry-referenced font files and their licenses, staged slim by the
# `fonts` stage. Nothing here has a tlmgr database entry and nothing needs one:
# font-registry.lua resolves each built-in font by explicit path under this root
# (its FONTS_ROOT).
COPY --from=fonts /staging/ /opt/keystone/fonts/

# IDs are pinned: the UID stamps ownership on bind-mounted build output, and an
# implicitly assigned next-free UID shifts when the base image gains an account.
RUN groupadd --gid 1001 publisher && \
    useradd --no-log-init --create-home --shell /usr/sbin/nologin \
      --uid 1001 --gid 1001 publisher

WORKDIR /keystone

# .hooks/ is where a hook leaves its socket, and the engine only reads it.
# Docker seeds an empty volume from the mountpoint of whichever container
# mounts it first, so the directory ships in the image for its mode: a volume
# Docker had to create itself arrives root-owned, and a hook running as any
# other user could not bind there. A hook image does the same for its side,
# since either may be first. Sticky and world-writable for the reason /tmp is:
# any hook may add its own socket, none may remove another's.
#
# .hooks-cache/ is where the engine remembers what a hook answered. It ships
# here for its mode under the same seeding rule, world-writable because compose
# runs the engine as the invoking user and the image cannot know that UID. Not
# sticky: only the engine's own service mounts this one, so there is no second
# writer whose files need protecting.

# The image mirrors a template's layout: NOTICE.md links into .licenses/, so the
# same relative path has to resolve here and in a project's tree.
COPY .licenses/ /usr/share/doc/keystone/.licenses/
COPY NOTICE.md /usr/share/doc/keystone/
COPY .pandoc/ .pandoc/
RUN chmod +x .pandoc/publish.sh .pandoc/import.sh .pandoc/export-sample.sh && \
    chown -R publisher:publisher /keystone && \
    mkdir -p .hooks && chmod 1777 .hooks && \
    mkdir -p .hooks-cache && chmod 0777 .hooks-cache

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

# Engine version, readable at runtime — the OCI label above carries the same
# value but labels are invisible from inside the container. `local` on an
# unversioned build.
ENV KEYSTONE_VERSION=${KEYSTONE_VERSION}

# publisher
USER 1001:1001

ENTRYPOINT ["/bin/bash"]
