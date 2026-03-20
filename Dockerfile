# syntax=docker/dockerfile:1
FROM ubuntu:24.04

LABEL org.opencontainers.image.title="strongSwan VPN"
LABEL org.opencontainers.image.description="strongSwan IKEv2 VPN server in Docker"
LABEL org.opencontainers.image.source="https://github.com/antonskalkin73/strongswan-docker"

ENV DEBIAN_FRONTEND=noninteractive

# Install strongSwan and required runtime packages; clean up apt cache to keep the image small.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        strongswan \
        strongswan-pki \
        libstrongswan-extra-plugins \
        libstrongswan-standard-plugins \
        iptables \
        iproute2 \
        ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Copy the entrypoint script and make it executable.
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Configuration and certificates are supplied at runtime via volume mounts.
# See compose.yaml for mount points.

ENTRYPOINT ["/entrypoint.sh"]
