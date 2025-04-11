FROM pandoc/latex:latest-ubuntu

ARG DEBIAN_FRONTEND=noninteractive
# Install required LaTeX packages and tools
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        texlive-latex-extra \
        dos2unix && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Update tlmgr itself before using it
RUN tlmgr update --self
# Install the Libertine font via TeX Live's tlmgr (this adds the font files to the active TeX distribution)
RUN tlmgr install libertine
# Optional: Verify the font is available
RUN kpsewhich libertine.sty || (echo "❌ libertine.sty not found" && exit 1)

# Set working directory inside container
WORKDIR /keystone

# Copy low-churn core files first for better caching
COPY ./.pandoc/ ./.pandoc/
# Normalize and make publish.sh executable
RUN dos2unix ./.pandoc/publish.sh && chmod +x ./.pandoc/publish.sh

# Copy high-churn content files (more likely to change) in the order from less likely to more likely
COPY ./publish.txt ./publish.txt
COPY ./assets/ ./assets/
COPY ./appendix/ ./appendix/
COPY ./chapters/ ./chapters/

# Normalize markdown/txt files only
RUN find ./chapters ./appendix ./assets -type f \( -name "*.md" -o -name "*.txt" \) -exec dos2unix {} +

# Default shell
ENTRYPOINT ["/bin/bash"]
