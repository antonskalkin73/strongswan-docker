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
        iptables \
        iproute2 \
        ca-certificates && \
    tar -xzf /tmp/strongswan.tar.gz -C /tmp && \
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

COPY --from=builder /usr/sbin/ipsec /usr/sbin/ipsec
COPY --from=builder /usr/bin/pki /usr/bin/pki
COPY --from=builder /usr/sbin/swanctl /usr/sbin/swanctl
COPY --from=builder /usr/libexec/ipsec /usr/libexec/ipsec
COPY --from=builder /usr/lib/ipsec /usr/lib/ipsec
COPY --from=builder /usr/lib/libstrongswan.so* /usr/lib/
COPY --from=builder /usr/lib/libcharon.so* /usr/lib/
COPY --from=builder /etc/strongswan.conf /etc/strongswan.conf
COPY --from=builder /etc/strongswan.d /etc/strongswan.d
COPY --from=builder /usr/share/strongswan /usr/share/strongswan

# Copy the entrypoint script and make it executable.
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Configuration and certificates are supplied at runtime via volume mounts.
# See compose.yaml for mount points.

ENTRYPOINT ["/entrypoint.sh"]
