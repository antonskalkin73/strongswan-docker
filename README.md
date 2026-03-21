# strongswan-docker

[English](README.md) | [Русский](README.ru.md)

A production-ready Docker image for running a **strongSwan IKEv2 VPN server**,
published to GitHub Container Registry (GHCR) and deployed on a Linux VPS with
Docker Compose v2.

---

## Table of contents

1. [Project purpose](#1-project-purpose)
2. [Architecture overview](#2-architecture-overview)
3. [Security model](#3-security-model)
4. [Repository structure](#4-repository-structure)
5. [Local build](#5-local-build)
6. [GHCR publishing](#6-ghcr-publishing)
7. [VPS deployment](#7-vps-deployment)
8. [Updating the container](#8-updating-the-container)
9. [Files: examples vs. secrets](#9-files-examples-vs-secrets)
10. [Troubleshooting](#10-troubleshooting)

---

## 1. Project purpose

This project packages [strongSwan](https://www.strongswan.org/) – a widely used
open-source IPsec/IKEv2 VPN implementation – into a minimal Ubuntu-based Docker
image.  
The image is **generic and secret-free**; all runtime configuration, certificates
and credentials are mounted from the host at container start time.

Typical use-case: roadwarrior IKEv2 VPN on a cheap Linux VPS, giving remote
clients encrypted access to the internet or a private subnet.

---

## 2. Architecture overview

```
GitHub repo (source + CI)
        │
        │  push / tag
        ▼
GitHub Actions workflow
        │
        │  docker build + push
        ▼
GHCR  ghcr.io/antonskalkin73/strongswan-docker:latest
        │
        │  docker compose pull
        ▼
VPS (Ubuntu + Docker Engine)
  ┌─────────────────────────────────┐
  │  strongSwan container           │
  │  network_mode: host             │
  │                                 │
  │  /etc/ipsec.conf       ◄── ro mount from ./config/
  │  /etc/strongswan.conf  ◄── ro mount from ./config/
  │  /etc/ipsec.secrets    ◄── ro mount from ./config/
  │  /etc/ipsec.d/         ◄── ro mount from ./certs/
  └─────────────────────────────────┘
```

The container uses **host networking** so strongSwan has direct access to the
physical NIC and UDP ports 500/4500 without any port-mapping complexity.

---

## 3. Security model

| Concern | Approach |
|---|---|
| Secrets in the image | None. Certs and PSKs are mounted at runtime. |
| Secrets in the repository | `.gitignore` excludes `.env`, `config/ipsec.secrets`, and everything under `certs/` (except `.gitkeep`). |
| Least-privilege mounts | All config and cert volumes are mounted **read-only** (`:ro`). |
| Kernel capabilities | Only `NET_ADMIN` and `SYS_MODULE` are added. |
| Image base | Ubuntu 24.04 LTS – regularly patched upstream. |
| CI token | GHCR login uses the auto-generated `GITHUB_TOKEN`; no personal tokens stored. |

> **Rule of thumb:** if a file contains a password, private key, or PSK, it must
> never be committed. Use the `*.example` files as templates only.

---

## 4. Repository structure

```
strongswan-docker/
├── .github/
│   └── workflows/
│       └── docker-publish.yml   # CI: build & push to GHCR
├── config/
│   ├── ipsec.conf               # IKEv2 roadwarrior example (safe to commit)
│   ├── strongswan.conf          # Charon daemon config (safe to commit)
│   └── ipsec.secrets.example   # Placeholder only – copy and fill in on VPS
├── certs/
│   └── .gitkeep                 # Keeps the directory in git; real certs go here
├── Dockerfile
├── entrypoint.sh
├── compose.yaml
├── .env.example                 # Copy to .env on VPS and fill in
├── .gitignore
├── README.md
└── README.ru.md                 # Russian translation of this guide
```

---

## 5. Local build

```bash
# Clone the repository
git clone https://github.com/antonskalkin73/strongswan-docker.git
cd strongswan-docker

# Download the latest upstream strongSwan release into the build context
STRONGSWAN_VERSION="$(
  basename "$(
    curl -fsSLI -o /dev/null -w '%{url_effective}' \
      https://github.com/strongswan/strongswan/releases/latest
  )"
)"
curl -fsSL -o strongswan.tar.gz \
  "https://github.com/strongswan/strongswan/releases/download/${STRONGSWAN_VERSION}/strongswan-${STRONGSWAN_VERSION}.tar.gz"

# Build the image locally from the upstream release tarball
docker build --build-arg STRONGSWAN_VERSION="$STRONGSWAN_VERSION" -t strongswan-local .

# Inspect the image
docker image inspect strongswan-local

# Optional cleanup of the downloaded source archive
rm -f strongswan.tar.gz
```

To test locally you still need the runtime config files (see
[VPS deployment](#7-vps-deployment)).

---

## 6. GHCR publishing

Images are published automatically by the GitHub Actions workflow
(`.github/workflows/docker-publish.yml`):

| Event | Image tag |
|---|---|
| Push to `main` | `latest`, `<strongswan-version>` |
| Push of tag `v1.2.3` | `1.2.3`, `1.2`, `latest`, `<strongswan-version>` |
| Pull request | Build only, no push |

Additionally, every published image gets a tag matching the installed
strongSwan version inside the container, for example `6.0.4`.

The workflow downloads the latest upstream release tarball directly from
<https://github.com/strongswan/strongswan/releases/> before building the image.

The workflow uses `secrets.GITHUB_TOKEN` – no additional secrets or PATs are
required.  
To enable the package, visit:  
**GitHub → your profile → Packages → strongswan-docker → Package settings →
Change visibility** (set to Public or leave Private as needed).

If the package visibility is set to **Public**, you can pull the image without
logging in:

```bash
docker pull ghcr.io/antonskalkin73/strongswan-docker:latest
```

---

## 7. VPS deployment

### 7.1 Prerequisites

- Ubuntu 22.04 / 24.04 VPS with a public IP
- Docker Engine installed: <https://docs.docker.com/engine/install/ubuntu/>
- Docker Compose v2 plugin: included with Docker Engine ≥ 20.10 (`docker compose`)

### 7.2 Create the runtime directory layout

```bash
git clone https://github.com/antonskalkin73/strongswan-docker.git
cd strongswan-docker

# Copy example files and fill them in
cp .env.example .env
nano .env                              # set VPN_FQDN

cp config/ipsec.secrets.example config/ipsec.secrets
nano config/ipsec.secrets             # set real credentials
chmod 600 config/ipsec.secrets        # restrict permissions

# Edit config files as needed
nano config/ipsec.conf
nano config/strongswan.conf
```

### 7.3 Generate and place certificates

strongSwan's `pki` tool can generate a self-signed CA and a server certificate.
The certs must be placed in the `certs/` subdirectories that strongSwan expects:

```bash
mkdir -p certs/cacerts certs/certs certs/private

# 1. Generate CA private key and self-signed certificate
docker run --rm -v "$(pwd)/certs:/out" \
  ghcr.io/antonskalkin73/strongswan-docker:latest \
  sh -c '
    ipsec pki --gen --type rsa --size 4096 --outform pem > /out/private/ca-key.pem
    ipsec pki --self --ca --lifetime 3650 \
      --in /out/private/ca-key.pem --type rsa \
      --dn "CN=VPN CA" --outform pem > /out/cacerts/ca-cert.pem
  '

# 2. Generate server private key and certificate signed by the CA.
#    Set FQDN to the value you placed in .env (VPN_FQDN=...).
FQDN=vpn.example.com   # <-- change this to your actual FQDN

docker run --rm -v "$(pwd)/certs:/out" \
  -e FQDN="$FQDN" \
  ghcr.io/antonskalkin73/strongswan-docker:latest \
  sh -c '
    ipsec pki --gen --type rsa --size 4096 --outform pem > /out/private/server-key.pem
    ipsec pki --pub --in /out/private/server-key.pem --type rsa |
      ipsec pki --issue --lifetime 1825 \
        --cacert /out/cacerts/ca-cert.pem \
        --cakey  /out/private/ca-key.pem \
        --dn "CN=$FQDN" --san "$FQDN" \
        --flag serverAuth --flag ikeIntermediate \
        --outform pem > /out/certs/server-cert.pem
  '

chmod 600 certs/private/ca-key.pem certs/private/server-key.pem
```

> The `certs/` directory is excluded from git by `.gitignore`.  
> **Back up `certs/private/` securely – losing the CA key means re-issuing all
> client certificates.**

### 7.4 Start the container

```bash
docker compose pull
docker compose up -d
docker compose logs -f
```

---

## 8. Updating the container

When a new image is published to GHCR:

```bash
docker compose pull
docker compose up -d
```

This performs a zero-downtime rolling replacement of the container.

---

## 9. Files: examples vs. secrets

| File | Status | Notes |
|---|---|---|
| `config/ipsec.conf` | ✅ Safe to commit | Example config, no secrets |
| `config/strongswan.conf` | ✅ Safe to commit | Daemon config, no secrets |
| `config/ipsec.secrets.example` | ✅ Safe to commit | Placeholder values only |
| `.env.example` | ✅ Safe to commit | Placeholder values only |
| `config/ipsec.secrets` | 🔴 **Never commit** | Contains real passwords |
| `.env` | 🔴 **Never commit** | May contain sensitive values |
| `certs/*` (except `.gitkeep`) | 🔴 **Never commit** | Private keys and certificates |

---

## 10. Troubleshooting

### View container logs

```bash
docker compose logs -f
# or
docker logs -f $(docker compose ps -q strongswan)
```

### Check strongSwan status inside the container

```bash
docker compose exec strongswan ipsec statusall
```

### Common issues

| Symptom | Likely cause | Fix |
|---|---|---|
| Container exits immediately | Missing config or secrets mount | Check that all files listed in `compose.yaml` exist on the host |
| `permission denied` on secrets | Wrong file permissions | `chmod 600 config/ipsec.secrets` |
| Clients can't connect | Firewall blocking UDP 500/4500 | Open ports in your VPS firewall / security group |
| Certificate mismatch | `VPN_FQDN` doesn't match cert CN/SAN | Regenerate the server cert with the correct FQDN |
| IP forwarding not enabled | Kernel sysctl not applied | Verify `sysctl net.ipv4.ip_forward` returns `1` inside the container |

### Check kernel IP forwarding

```bash
docker compose exec strongswan sysctl net.ipv4.ip_forward
```

### Inspect loaded IPsec policies

```bash
docker compose exec strongswan ip xfrm policy
```
