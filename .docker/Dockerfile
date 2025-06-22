FROM pandoc/latex:3.6.4-ubuntu

ARG DEBIAN_FRONTEND=noninteractive

# Install the Libertine font via TeX Live's tlmgr (this adds the font files to the active TeX distribution)
RUN tlmgr update --self && \
    tlmgr install libertine

WORKDIR /keystone

COPY .pandoc/ .pandoc/
RUN chmod +x .pandoc/publish.sh .pandoc/import.sh

ENTRYPOINT ["/bin/bash"]
