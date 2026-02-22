ARG BASE_IMAGE=pandoc/latex:3.9.0-ubuntu
FROM ${BASE_IMAGE}

ARG BASE_IMAGE
ARG KEYSTONE_VERSION=local

LABEL maintainer="Knight Owl <support@knight-owl.dev>"
LABEL org.opencontainers.image.licenses="GPL-2.0-or-later"
LABEL org.opencontainers.image.authors="Knight Owl LLC"
LABEL org.opencontainers.image.source="https://github.com/knight-owl-dev/keystone"
LABEL org.opencontainers.image.base.name="${BASE_IMAGE}"
LABEL org.opencontainers.image.version="${KEYSTONE_VERSION}"
LABEL org.opencontainers.image.description="Keystone publishing image based on pandoc/latex"

ARG DEBIAN_FRONTEND=noninteractive

# Install fonts via TeX Live's tlmgr
RUN tlmgr update --self && \
    tlmgr install \
      libertine \
      tex-gyre \
      ebgaramond

RUN useradd --no-log-init --create-home --shell /usr/sbin/nologin publisher

WORKDIR /keystone

COPY .licenses/ /usr/share/doc/keystone/
COPY .pandoc/ .pandoc/
RUN chmod +x .pandoc/publish.sh .pandoc/import.sh .pandoc/export-sample.sh && \
    chown -R publisher:publisher /keystone

USER publisher

ENTRYPOINT ["/bin/bash"]
