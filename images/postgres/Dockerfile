# syntax=docker/dockerfile:1.7

# The tag is human-auditable and the digest makes the reviewed base immutable.
ARG BASE_IMAGE=postgres:18.6-alpine3.23@sha256:697c180dbf244d3ce4a8f4cbc0156cde840af055c1bf8b76aebe422a4822086f
ARG TIMESCALEDB_TOOLS_IMAGE=timescale/timescaledb:2.29.1-pg18@sha256:373eb0fee9c0f8e0b4b0d4e74c7d0dd463dce05de6b49982701c4b540e94cba0

# Preserve the two TimescaleDB operational utilities distributed with the
# previous standard image.  This stage is pinned and only the utilities are
# copied into the final PostgreSQL 18.6 image; no PostgreSQL 18.4 artifact is.
FROM ${TIMESCALEDB_TOOLS_IMAGE} AS timescaledb-tools

FROM ${BASE_IMAGE} AS timescaledb-builder
USER root
ARG TIMESCALEDB_VERSION=2.29.1
ARG TIMESCALEDB_COMMIT=bdc46d313480287d2c21aa50abf405a1493a1769
ARG TIMESCALEDB_SOURCE_SHA256=b0054b6d399268e8abfe4c64db846ec843ae93a1cbba5d5f1811e9198f666212

# Build packages remain in this throw-away stage.  Build TimescaleDB against
# the fixed PostgreSQL 18.6 headers instead of inheriting the unpatched 18.4
# server bundled in the upstream TimescaleDB image.
RUN apk add --no-cache --virtual .timescaledb-build-deps \
      ca-certificates \
      cmake \
      coreutils \
      dpkg \
      dpkg-dev \
      gcc \
      icu-dev \
      libc-dev \
      make \
      openssl \
      openssl-dev \
      tar \
      util-linux-dev
WORKDIR /tmp/timescaledb
RUN wget -O source.tar.gz \
      "https://codeload.github.com/timescale/timescaledb/tar.gz/${TIMESCALEDB_COMMIT}" \
    && printf '%s  %s\n' "${TIMESCALEDB_SOURCE_SHA256}" source.tar.gz | sha256sum -c - \
    && mkdir source \
    && tar -xzf source.tar.gz --strip-components=1 -C source \
    && cmake -S source -B build \
      -DCMAKE_BUILD_TYPE=RelWithDebInfo \
      -DGENERATE_DOWNGRADE_SCRIPT=ON \
      -DPROJECT_INSTALL_METHOD=docker \
      -DREGRESS_CHECKS=OFF \
      -DTAP_CHECKS=OFF \
      -DWARNINGS_AS_ERRORS=OFF \
    && cmake --build build --parallel "$(getconf _NPROCESSORS_ONLN)" \
    && DESTDIR=/opt/timescaledb-root cmake --install build

FROM ${BASE_IMAGE} AS vector-builder
USER root
ARG PGVECTOR_VERSION=0.8.6
ARG PGVECTOR_COMMIT=8ee86c96f0fd72390f890aa8a336fda6d3ab4c6c
ARG PGVECTOR_SOURCE_SHA256=d076a3098010905fd60256649327809651f6288327db6413f0938305f62ea299

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
ARG TIMESCALEDB_TOOLS_IMAGE
ARG TIMESCALEDB_VERSION
ARG TIMESCALEDB_COMMIT
ARG TIMESCALEDB_SOURCE_SHA256
ARG PGVECTOR_VERSION
ARG PGVECTOR_COMMIT
ARG PGVECTOR_SOURCE_SHA256
ARG BUILD_REVISION=4

# Install extensions built against the fixed PostgreSQL base.  Replace every
# pgvector artifact defensively so obsolete upgrade SQL cannot survive a base
# image change unnoticed.
COPY --from=timescaledb-builder /opt/timescaledb-root/usr/local/ /usr/local/
COPY --from=timescaledb-tools /usr/local/bin/timescaledb-parallel-copy /usr/local/bin/timescaledb-parallel-copy
COPY --from=timescaledb-tools /usr/local/bin/timescaledb-tune /usr/local/bin/timescaledb-tune
RUN rm -f \
      /usr/local/lib/postgresql/vector.so \
      /usr/local/lib/postgresql/bitcode/vector.index.bc \
      /usr/local/share/postgresql/extension/vector.control \
      /usr/local/share/postgresql/extension/vector--*.sql \
    && rm -rf /usr/local/lib/postgresql/bitcode/vector \
    && sed -ri "s/[#]*\\s*(shared_preload_libraries)\\s*=\\s*'(.*)'/\\1 = 'timescaledb,\\2'/;s/,'/'/" \
      /usr/local/share/postgresql/postgresql.conf.sample
COPY --from=vector-builder /opt/vector-root/usr/local/lib/postgresql/ /usr/local/lib/postgresql/
COPY --from=vector-builder /opt/vector-root/usr/local/share/postgresql/extension/ /usr/local/share/postgresql/extension/
COPY --from=vector-builder /opt/vector-root/usr/local/share/licenses/ /usr/local/share/licenses/

LABEL org.opencontainers.image.source="https://github.com/koopu-ai/koopu-images" \
      org.opencontainers.image.description="Koopu PostgreSQL 18 with TimescaleDB and a CVE-fixed pgvector" \
      com.koopu.postgres.base="${BASE_IMAGE}" \
      com.koopu.postgres.major="18" \
      com.koopu.postgres.version="18.6" \
      com.koopu.timescaledb.version="${TIMESCALEDB_VERSION}" \
      com.koopu.timescaledb.tools-base="${TIMESCALEDB_TOOLS_IMAGE}" \
      com.koopu.timescaledb.commit="${TIMESCALEDB_COMMIT}" \
      com.koopu.timescaledb.source-sha256="${TIMESCALEDB_SOURCE_SHA256}" \
      com.koopu.pgvector.version="${PGVECTOR_VERSION}" \
      com.koopu.pgvector.commit="${PGVECTOR_COMMIT}" \
      com.koopu.pgvector.source-sha256="${PGVECTOR_SOURCE_SHA256}" \
      com.koopu.image.build-revision="${BUILD_REVISION}"
