# syntax=docker/dockerfile:1
FROM ubuntu:24.04 AS builder

LABEL org.opencontainers.image.title="strongSwan VPN"
LABEL org.opencontainers.image.description="strongSwan IKEv2 VPN server in Docker"
LABEL org.opencontainers.image.source="https://github.com/antonskalkin73/strongswan-docker"

ENV DEBIAN_FRONTEND=noninteractive

# The release tarball is downloaded by the workflow (or before a local build) and
# added to the build context as strongswan.tar.gz.
ARG STRONGSWAN_VERSION
COPY strongswan.tar.gz /tmp/strongswan.tar.gz

# Build strongSwan from the upstream GitHub release tarball.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        pkg-config \
        libgmp-dev \
        libssl-dev \
        bison \
        flex \
        make \
        tar \
        ca-certificates && \
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
    make install

RUN mkdir -p \
        /opt/strongswan-runtime/usr/bin \
        /opt/strongswan-runtime/usr/sbin \
        /opt/strongswan-runtime/usr/lib \
        /opt/strongswan-runtime/usr/libexec \
        /opt/strongswan-runtime/etc \
        /opt/strongswan-runtime/usr/share && \
    cp -a /usr/bin/pki /opt/strongswan-runtime/usr/bin/ && \
    cp -a /usr/sbin/ipsec /opt/strongswan-runtime/usr/sbin/ && \
    cp -a /usr/libexec/ipsec /opt/strongswan-runtime/usr/libexec/ && \
    cp -a /usr/lib/ipsec /opt/strongswan-runtime/usr/lib/ && \
    find /usr/lib \( -name 'libstrongswan.so*' -o -name 'libcharon.so*' \) -exec cp -a {} /opt/strongswan-runtime/usr/lib/ \; && \
    cp -a /etc/strongswan.conf /etc/strongswan.d /opt/strongswan-runtime/etc/ && \
    cp -a /usr/share/strongswan /opt/strongswan-runtime/usr/share/

FROM ubuntu:24.04

LABEL org.opencontainers.image.title="strongSwan VPN"
LABEL org.opencontainers.image.description="strongSwan IKEv2 VPN server in Docker"
LABEL org.opencontainers.image.source="https://github.com/antonskalkin73/strongswan-docker"

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        iptables \
        iproute2 \
        ca-certificates \
        libgmp10 \
        libssl3 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /opt/strongswan-runtime/ /

# Copy the entrypoint script and make it executable.
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Configuration and certificates are supplied at runtime via volume mounts.
# See compose.yaml for mount points.

ENTRYPOINT ["/entrypoint.sh"]
