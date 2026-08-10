# syntax=docker/dockerfile:1.7

ARG BASE_IMAGE=alpine:3.23@sha256:fd791d74b68913cbb027c6546007b3f0d3bc45125f797758156952bc2d6daf40

FROM ${BASE_IMAGE} AS builder
USER root
ARG PGBOUNCER_VERSION=1.25.2
ARG PGBOUNCER_SOURCE_SHA256=924ad35113fd0a71c8e2dbe85b5d03445532e2b7b37a9f8a48983beea238b332
ARG SOURCE_DATE_EPOCH=1778198400

RUN apk add --no-cache \
      build-base=0.5-r3 \
      pkgconf=2.5.1-r0 \
      libevent-dev=2.1.13-r0 \
      openssl-dev=3.5.7-r0 \
      c-ares-dev=1.34.8-r0
WORKDIR /tmp/pgbouncer
RUN wget -O source.tar.gz \
      "https://www.pgbouncer.org/downloads/files/${PGBOUNCER_VERSION}/pgbouncer-${PGBOUNCER_VERSION}.tar.gz" \
    && printf '%s  %s\n' "${PGBOUNCER_SOURCE_SHA256}" source.tar.gz | sha256sum -c - \
    && mkdir source \
    && tar -xzf source.tar.gz --strip-components=1 -C source
RUN cd source \
    && SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH}" \
       CFLAGS="-O2 -fstack-protector-strong -fPIE" \
       LDFLAGS="-Wl,-z,relro,-z,now -pie" \
       ./configure --prefix=/usr/local --with-cares --disable-debug \
    && make -j"$(getconf _NPROCESSORS_ONLN)" pgbouncer \
    && install -D -m 0755 pgbouncer /opt/pgbouncer-root/usr/local/bin/pgbouncer \
    && install -D -m 0644 COPYRIGHT /opt/pgbouncer-root/usr/local/share/licenses/pgbouncer/COPYRIGHT

FROM ${BASE_IMAGE}
USER root
ARG BASE_IMAGE
ARG PGBOUNCER_VERSION
ARG PGBOUNCER_SOURCE_SHA256
ARG BUILD_REVISION=1

RUN apk add --no-cache \
      ca-certificates=20260611-r0 \
      libevent=2.1.13-r0 \
      c-ares=1.34.8-r0 \
      libssl3=3.5.7-r0 \
      libcrypto3=3.5.7-r0 \
    && addgroup -S -g 6432 pgbouncer \
    && adduser -S -D -H -u 6432 -G pgbouncer -s /sbin/nologin pgbouncer \
    && install -d -m 0750 -o pgbouncer -g pgbouncer /etc/pgbouncer /var/run/pgbouncer
COPY --from=builder /opt/pgbouncer-root/ /

LABEL org.opencontainers.image.source="https://github.com/koopu-ai/koopu-images" \
      org.opencontainers.image.description="Koopu PgBouncer built from the verified upstream release tarball" \
      com.koopu.pgbouncer.base="${BASE_IMAGE}" \
      com.koopu.pgbouncer.version="${PGBOUNCER_VERSION}" \
      com.koopu.pgbouncer.source-sha256="${PGBOUNCER_SOURCE_SHA256}" \
      com.koopu.image.build-revision="${BUILD_REVISION}"

USER 6432:6432
EXPOSE 6432
ENTRYPOINT ["/usr/local/bin/pgbouncer"]
CMD ["/etc/pgbouncer/pgbouncer.ini"]
