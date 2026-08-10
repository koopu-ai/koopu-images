# syntax=docker/dockerfile:1.7

# The tag is human-auditable and the digest makes the reviewed base immutable.
ARG BASE_IMAGE=timescale/timescaledb:2.29.0-pg18@sha256:aad0e9757cd1498dbc60ce6fc7705f06eb9ab7c0ffe22ad16feda1ced91d71cf

FROM ${BASE_IMAGE} AS vector-builder
USER root
ARG PGVECTOR_VERSION=0.8.5
ARG PGVECTOR_COMMIT=159b79aaad5983fb7459c1e3df2897fbb2d11788
ARG PGVECTOR_SOURCE_SHA256=9a483fad70ae2e0a50b3dccb6c4b4931d9a07375a1d5815e82b57870448a7d52

# Build packages remain in this throw-away stage.
RUN apk add --no-cache --virtual .vector-build-deps \
      build-base=0.5-r3 \
      clang21=21.1.2-r2 \
      llvm21-dev=21.1.2-r1
WORKDIR /tmp/pgvector
RUN wget -O source.tar.gz \
      "https://github.com/pgvector/pgvector/archive/${PGVECTOR_COMMIT}.tar.gz" \
    && printf '%s  %s\n' "${PGVECTOR_SOURCE_SHA256}" source.tar.gz | sha256sum -c - \
    && mkdir source \
    && tar -xzf source.tar.gz --strip-components=1 -C source \
    && make -C source OPTFLAGS="" -j"$(getconf _NPROCESSORS_ONLN)" \
    && make -C source OPTFLAGS="" DESTDIR=/opt/vector-root install \
    && install -D -m 0644 source/LICENSE \
      /opt/vector-root/usr/local/share/licenses/pgvector/LICENSE

FROM ${BASE_IMAGE}
USER root
ARG BASE_IMAGE
ARG PGVECTOR_VERSION
ARG PGVECTOR_COMMIT
ARG PGVECTOR_SOURCE_SHA256
ARG BUILD_REVISION=2

# The base contains pgvector 0.8.1. Remove every old artifact before installing
# the reviewed replacement so obsolete upgrade SQL cannot survive unnoticed.
RUN rm -f \
      /usr/local/lib/postgresql/vector.so \
      /usr/local/lib/postgresql/bitcode/vector.index.bc \
      /usr/local/share/postgresql/extension/vector.control \
      /usr/local/share/postgresql/extension/vector--*.sql \
    && rm -rf /usr/local/lib/postgresql/bitcode/vector
COPY --from=vector-builder /opt/vector-root/usr/local/lib/postgresql/ /usr/local/lib/postgresql/
COPY --from=vector-builder /opt/vector-root/usr/local/share/postgresql/extension/ /usr/local/share/postgresql/extension/
COPY --from=vector-builder /opt/vector-root/usr/local/share/licenses/ /usr/local/share/licenses/

LABEL org.opencontainers.image.source="https://github.com/koopu-ai/koopu-images" \
      org.opencontainers.image.description="Koopu PostgreSQL 18 with TimescaleDB and a CVE-fixed pgvector" \
      com.koopu.postgres.base="${BASE_IMAGE}" \
      com.koopu.postgres.major="18" \
      com.koopu.timescaledb.version="2.29.0" \
      com.koopu.pgvector.version="${PGVECTOR_VERSION}" \
      com.koopu.pgvector.commit="${PGVECTOR_COMMIT}" \
      com.koopu.pgvector.source-sha256="${PGVECTOR_SOURCE_SHA256}" \
      com.koopu.image.build-revision="${BUILD_REVISION}"
