# syntax=docker/dockerfile:1
FROM ubuntu:24.04

LABEL org.opencontainers.image.title="strongSwan VPN"
LABEL org.opencontainers.image.description="strongSwan IKEv2 VPN server in Docker"
LABEL org.opencontainers.image.source="https://github.com/antonskalkin73/strongswan-docker"

ENV DEBIAN_FRONTEND=noninteractive

# The release tarball is downloaded by the workflow (or before a local build) and
# added to the build context as strongswan.tar.gz.
ARG STRONGSWAN_VERSION
COPY strongswan.tar.gz /tmp/strongswan.tar.gz

RUN apt-get update && \
    build_deps="build-essential pkg-config libgmp-dev libssl-dev bison flex make" && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        iptables \
        iproute2 \
        tar \
        ${build_deps} && \
    tar -xzf /tmp/strongswan.tar.gz -C /tmp && \
    test -d /tmp/strongswan-${STRONGSWAN_VERSION} && \
    cd /tmp/strongswan-${STRONGSWAN_VERSION} && \
    ./configure \
        --prefix=/usr \
        --sysconfdir=/etc \
        --enable-openssl \
        --enable-pki \
        --enable-eap-identity \
        --enable-eap-mschapv2 \
        --enable-stroke \
        --enable-starter && \
    make -j"$(nproc)" && \
    make install && \
    cd / && \
    rm -rf /tmp/strongswan* && \
    apt-get purge -y --auto-remove ${build_deps} && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Copy the entrypoint script and make it executable.
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Configuration and certificates are supplied at runtime via volume mounts.
# See compose.yaml for mount points.

ENTRYPOINT ["/entrypoint.sh"]
