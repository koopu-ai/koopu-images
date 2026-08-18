# Koopu Images

Public, reproducible OCI image build definitions maintained by Koopu AI.

This repository contains only image build inputs, verification scripts, and
GitHub Actions workflows. Production Compose files, host inventories,
credentials, and deployment secrets stay in the private operations repository.

## Architecture policy

- `linux/amd64` is the primary production and procurement architecture.
- `linux/arm64` is a required second architecture.
- Each release tag identifies one OCI image index containing both platforms.
- Production deployments must pin the OCI index digest, never a floating tag or
  a platform-specific child manifest digest.

## Images

| Image | Reviewed tag | Contents |
|---|---|---|
| `ghcr.io/koopu-ai/postgres` | `pg18.6-ts2.29.1-pgv0.8.6-b4` | PostgreSQL 18.6, TimescaleDB 2.29.1, pgvector 0.8.6 |
| `ghcr.io/koopu-ai/pgbouncer` | `1.25.2-alpine3.23-b1` | PgBouncer 1.25.2 on Alpine 3.23 |
| `ghcr.io/koopu-ai/minio` | `RELEASE.2025-10-15T17-29-55Z-b1` | MinIO built from the verified upstream source commit |

Release tags are published manually from reviewed `main`. A tag is immutable:
an existing tag can only be attested by supplying its exact registry digest;
the workflow will not overwrite it.

## Pulling on a new server

Packages must be published and made public before anonymous pulls work. Discover
the approved OCI index digest in the private dependency baseline, then pull it
directly:

```bash
docker pull ghcr.io/koopu-ai/postgres@sha256:<approved-oci-index-digest>
docker pull ghcr.io/koopu-ai/pgbouncer@sha256:<approved-oci-index-digest>
docker pull ghcr.io/koopu-ai/minio@sha256:<approved-oci-index-digest>
```

Docker automatically selects the matching `linux/amd64` or `linux/arm64` child
manifest. Tags are useful for human discovery, but are not the production pin.

## Local verification

Each image directory exposes the same interface:

```bash
TARGET_PLATFORM=linux/amd64 images/postgres/build.sh
TARGET_PLATFORM=linux/amd64 images/postgres/health-check.sh \
  koopu/postgres:pg18.6-ts2.29.1-pgv0.8.6-b4
TARGET_PLATFORM=linux/amd64 images/postgres/artifact-fingerprint.sh \
  koopu/postgres:pg18.6-ts2.29.1-pgv0.8.6-b4
```

Use `linux/arm64` after installing QEMU binfmt support, or run the commands on a
native ARM64 host. CI builds every image twice on both required platforms,
executes its smoke test, and compares payload fingerprints.

## Supply-chain controls

- Base images are pinned by human-readable tag and SHA-256 digest.
- Downloaded upstream source archives are pinned by commit/release and SHA-256.
- GitHub Actions are pinned by full commit SHA.
- Publish workflows build one AMD64-first, dual-platform OCI index.
- Published images are pulled back per platform and compared with the reviewed
  local payload fingerprint.
- No production credentials or generated private keys belong in this repository.

## Licensing

The build definitions and original scripts in this repository are licensed
under Apache-2.0. Built images contain upstream software under its own licenses;
in particular, MinIO is distributed under GNU AGPLv3. Consumers are responsible
for complying with the licenses shipped in each image.
