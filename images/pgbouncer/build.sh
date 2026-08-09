#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dockerfile="${root_dir}/Dockerfile"

read_arg() {
  local name="$1"
  awk -F= -v key="ARG ${name}" '$1 == key { print substr($0, index($0, "=") + 1); exit }' "$dockerfile"
}

base_image="$(read_arg BASE_IMAGE)"
default_version="$(read_arg PGBOUNCER_VERSION)"
default_source_sha="$(read_arg PGBOUNCER_SOURCE_SHA256)"
default_build="$(read_arg BUILD_REVISION)"

version="${PGBOUNCER_VERSION_OVERRIDE:-$default_version}"
source_sha="${PGBOUNCER_SOURCE_SHA256_OVERRIDE:-$default_source_sha}"
build_revision="${BUILD_REVISION_OVERRIDE:-$default_build}"
image_tag="${IMAGE_TAG:-koopu/pgbouncer:${version}-alpine3.23-b${build_revision}}"
build_mode="${BUILD_MODE:-load}"
target_platforms="${TARGET_PLATFORMS:-${TARGET_PLATFORM:-}}"

if [[ ! "$base_image" =~ ^alpine:[^@]+@sha256:[0-9a-f]{64}$ ]]; then
  printf 'base image must contain an audited tag and sha256 digest: %s\n' "$base_image" >&2
  exit 2
fi
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || [[ ! "$source_sha" =~ ^[0-9a-f]{64}$ ]] \
  || [[ ! "$build_revision" =~ ^[0-9]+$ ]]; then
  printf 'invalid PgBouncer version, source digest, or build revision\n' >&2
  exit 2
fi
if [[ "$version" != "$default_version" ]]; then
  printf 'PgBouncer version must match the reviewed baseline: %s\n' "$default_version" >&2
  exit 2
fi
if [[ "$source_sha" != "$default_source_sha" ]]; then
  if [[ "${ALLOW_INVALID_SOURCE_TEST:-0}" != "1" || ! "$source_sha" =~ ^0{64}$ ]]; then
    printf 'only the all-zero CI source-digest negative control may override the baseline\n' >&2
    exit 2
  fi
fi

case "$build_mode" in
  load)
    if [[ -n "$target_platforms" && ! "$target_platforms" =~ ^linux/(amd64|arm64)$ ]]; then
      printf 'load mode requires one approved platform: %s\n' "$target_platforms" >&2
      exit 2
    fi
    output=(--load)
    ;;
  push)
    if [[ "$target_platforms" != "linux/amd64,linux/arm64" ]]; then
      printf 'push mode requires linux/amd64,linux/arm64 in primary-first order\n' >&2
      exit 2
    fi
    output=(--push)
    ;;
  *)
    printf 'BUILD_MODE must be load or push: %s\n' "$build_mode" >&2
    exit 2
    ;;
esac

build=(docker buildx build "${output[@]}" --pull --file "$dockerfile" --tag "$image_tag")
[[ -z "${BUILDER_NAME:-}" ]] || build+=(--builder "$BUILDER_NAME")
[[ "${NO_CACHE:-0}" != "1" ]] || build+=(--no-cache)
[[ -z "$target_platforms" ]] || build+=(--platform "$target_platforms")
build+=(
  --build-arg "PGBOUNCER_VERSION=${version}"
  --build-arg "PGBOUNCER_SOURCE_SHA256=${source_sha}"
  --build-arg "BUILD_REVISION=${build_revision}"
  "$root_dir"
)

printf 'base_image=%s\nimage_tag=%s\npgbouncer=%s\nsource_sha256=%s\n' \
  "$base_image" "$image_tag" "$version" "$source_sha"
"${build[@]}"
if [[ "$build_mode" == "load" ]]; then
  architecture="$(docker image inspect "$image_tag" --format '{{.Architecture}}')"
  if [[ -n "$target_platforms" && "linux/${architecture}" != "$target_platforms" ]]; then
    printf 'loaded architecture differs from requested platform: %s\n' "$architecture" >&2
    exit 1
  fi
  docker image inspect "$image_tag" \
    --format 'image_id={{.Id}} architecture={{.Architecture}} user={{.Config.User}} base={{index .Config.Labels "com.koopu.pgbouncer.base"}}'
else
  docker buildx imagetools inspect "$image_tag"
fi
