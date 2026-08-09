#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dockerfile="${root_dir}/Dockerfile"

read_arg() {
  local name="$1"
  awk -F= -v key="ARG ${name}" '$1 == key { print substr($0, index($0, "=") + 1); exit }' "$dockerfile"
}

base_image="$(read_arg BASE_IMAGE)"
default_vector="$(read_arg PGVECTOR_VERSION)"
default_commit="$(read_arg PGVECTOR_COMMIT)"
default_source_sha="$(read_arg PGVECTOR_SOURCE_SHA256)"
default_build="$(read_arg BUILD_REVISION)"

vector_version="${PGVECTOR_VERSION_OVERRIDE:-$default_vector}"
vector_commit="${PGVECTOR_COMMIT_OVERRIDE:-$default_commit}"
vector_source_sha="${PGVECTOR_SOURCE_SHA256_OVERRIDE:-$default_source_sha}"
build_revision="${BUILD_REVISION_OVERRIDE:-$default_build}"
image_tag="${IMAGE_TAG:-koopu/postgres:pg18-ts2.29.0-pgv${vector_version}-b${build_revision}}"
build_mode="${BUILD_MODE:-load}"
target_platforms="${TARGET_PLATFORMS:-${TARGET_PLATFORM:-}}"

if [[ ! "$base_image" =~ ^timescale/timescaledb:[^@]+@sha256:[0-9a-f]{64}$ ]]; then
  printf 'base image must contain both an audited tag and sha256 digest: %s\n' "$base_image" >&2
  exit 2
fi
if [[ ! "$vector_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || [[ ! "$vector_commit" =~ ^[0-9a-f]{40}$ ]] \
  || [[ ! "$vector_source_sha" =~ ^[0-9a-f]{64}$ ]] \
  || [[ ! "$build_revision" =~ ^[0-9]+$ ]]; then
  printf 'invalid version, commit, source digest, or build revision\n' >&2
  exit 2
fi
if [[ "$vector_version" != "$default_vector" && "${ALLOW_UNSAFE_TEST_VERSION:-0}" != "1" ]]; then
  printf 'non-baseline pgvector requires ALLOW_UNSAFE_TEST_VERSION=1 and is for negative tests only\n' >&2
  exit 2
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
  --build-arg "PGVECTOR_VERSION=${vector_version}"
  --build-arg "PGVECTOR_COMMIT=${vector_commit}"
  --build-arg "PGVECTOR_SOURCE_SHA256=${vector_source_sha}"
  --build-arg "BUILD_REVISION=${build_revision}"
  "$root_dir"
)

printf 'base_image=%s\nimage_tag=%s\npgvector=%s\n' "$base_image" "$image_tag" "$vector_version"
"${build[@]}"
if [[ "$build_mode" == "load" ]]; then
  architecture="$(docker image inspect "$image_tag" --format '{{.Architecture}}')"
  if [[ -n "$target_platforms" && "linux/${architecture}" != "$target_platforms" ]]; then
    printf 'loaded architecture differs from requested platform: %s\n' "$architecture" >&2
    exit 1
  fi
  docker image inspect "$image_tag" \
    --format 'image_id={{.Id}} architecture={{.Architecture}} base={{index .Config.Labels "com.koopu.postgres.base"}}'
else
  docker buildx imagetools inspect "$image_tag"
fi
