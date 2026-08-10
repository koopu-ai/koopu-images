# syntax=docker/dockerfile:1.7

ARG BUILD_IMAGE=golang:1.24.8-alpine3.22@sha256:3d78beb141d98f42337f1252ecf2a5f20374109929a4c3f6817f9e4179cc0ae5
ARG RUNTIME_IMAGE=minio/minio:RELEASE.2025-09-07T16-13-09Z@sha256:14cea493d9a34af32f524e538b8346cf79f3321eff8e708c1e2960462bd8936e
ARG MINIO_COMMIT=9e49d5e7a648f00e26f2246f4dc28e6b07f8c84a
ARG MINIO_SOURCE_SHA256=45521908307306e925c98d629e1c17d78c8b72b6ee242b1bfb1409f7d8ee5841
ARG MINIO_RELEASE_TIME=2025-10-15T17:29:55Z
ARG MINIO_RELEASE_TAG=RELEASE.2025-10-15T17-29-55Z
ARG BUILD_REVISION=1

FROM ${BUILD_IMAGE} AS builder
ARG MINIO_COMMIT
ARG MINIO_SOURCE_SHA256
ARG MINIO_RELEASE_TIME
ARG MINIO_RELEASE_TAG
ARG TARGETOS
ARG TARGETARCH

WORKDIR /src
RUN wget -O source.tar.gz "https://github.com/minio/minio/archive/${MINIO_COMMIT}.tar.gz" \
    && printf '%s  %s\n' "${MINIO_SOURCE_SHA256}" source.tar.gz | sha256sum -c - \
    && mkdir source \
    && tar -xzf source.tar.gz --strip-components=1 -C source
WORKDIR /src/source
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    SHORT_COMMIT="$(printf '%.12s' "${MINIO_COMMIT}")" \
    && LDFLAGS="-s -w \
      -X github.com/minio/minio/cmd.Version=${MINIO_RELEASE_TIME} \
      -X github.com/minio/minio/cmd.CopyrightYear=2025 \
      -X github.com/minio/minio/cmd.ReleaseTag=${MINIO_RELEASE_TAG} \
      -X github.com/minio/minio/cmd.CommitID=${MINIO_COMMIT} \
      -X github.com/minio/minio/cmd.ShortCommitID=${SHORT_COMMIT} \
      -X github.com/minio/minio/cmd.GOPATH=/go \
      -X github.com/minio/minio/cmd.GOROOT=/usr/local/go" \
    && CGO_ENABLED=0 GOOS="${TARGETOS}" GOARCH="${TARGETARCH}" \
       go build -tags kqueue -trimpath --ldflags "${LDFLAGS}" -o /out/minio . \
    && install -D -m 0644 LICENSE /out/licenses/minio/LICENSE

FROM ${RUNTIME_IMAGE}
ARG BUILD_IMAGE
ARG RUNTIME_IMAGE
ARG MINIO_COMMIT
ARG MINIO_SOURCE_SHA256
ARG MINIO_RELEASE_TAG
ARG BUILD_REVISION
USER root
COPY --from=builder --chmod=0755 /out/minio /usr/bin/minio
COPY --from=builder /out/licenses/minio/LICENSE /usr/share/licenses/minio/LICENSE
LABEL org.opencontainers.image.source="https://github.com/koopu-ai/koopu-images" \
      org.opencontainers.image.licenses="AGPL-3.0-only" \
      org.opencontainers.image.version="${MINIO_RELEASE_TAG}" \
      org.opencontainers.image.revision="${MINIO_COMMIT}" \
      com.koopu.minio.build-image="${BUILD_IMAGE}" \
      com.koopu.minio.runtime-image="${RUNTIME_IMAGE}" \
      com.koopu.minio.source-sha256="${MINIO_SOURCE_SHA256}" \
      com.koopu.image.build-revision="${BUILD_REVISION}"
