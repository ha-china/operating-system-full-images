# HAOS Full Image Builder
# Container with all required tools for building pre-loaded HAOS images

FROM debian:trixie-slim

# Install base packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    coreutils \
    curl \
    e2fsprogs \
    fdisk \
    gdisk \
    gnupg \
    jq \
    make \
    openssl \
    p7zip-full \
    pigz \
    procps \
    qemu-utils \
    rsync \
    skopeo \
    util-linux \
    xz-utils \
    zerofree \
    zip \
    && rm -rf /var/lib/apt/lists/*

# Install Docker from official repository
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian trixie stable" > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends docker-ce docker-ce-cli containerd.io \
    && rm -rf /var/lib/apt/lists/*

# Create work directories
RUN mkdir -p /work /input /output /cache

# Copy scripts
COPY scripts/ /opt/haos-builder/scripts/
COPY build.mk /opt/haos-builder/Makefile

# Make scripts executable
RUN chmod +x /opt/haos-builder/scripts/*.sh

WORKDIR /opt/haos-builder

ENTRYPOINT ["/opt/haos-builder/scripts/entry.sh"]
CMD ["help"]
