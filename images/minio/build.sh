#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dockerfile="${root_dir}/Dockerfile"

read_arg() {
  local name="$1"
  awk -F= -v key="ARG ${name}" '$1 == key { print substr($0, index($0, "=") + 1); exit }' "$dockerfile"
}

release_tag="$(read_arg MINIO_RELEASE_TAG)"
commit="$(read_arg MINIO_COMMIT)"
default_source_sha="$(read_arg MINIO_SOURCE_SHA256)"
build_revision="$(read_arg BUILD_REVISION)"
source_sha="${MINIO_SOURCE_SHA256_OVERRIDE:-$default_source_sha}"
image_tag="${IMAGE_TAG:-koopu/minio:${release_tag}-b${build_revision}}"
build_mode="${BUILD_MODE:-load}"
target_platforms="${TARGET_PLATFORMS:-${TARGET_PLATFORM:-}}"

if [[ ! "$release_tag" =~ ^RELEASE\.[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}-[0-9]{2}-[0-9]{2}Z$ ]] \
  || [[ ! "$commit" =~ ^[0-9a-f]{40}$ ]] \
  || [[ ! "$source_sha" =~ ^[0-9a-f]{64}$ ]] \
  || [[ ! "$build_revision" =~ ^[0-9]+$ ]]; then
  printf 'invalid MinIO release, commit, source digest, or build revision\n' >&2
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
  --build-arg "MINIO_SOURCE_SHA256=${source_sha}"
  --build-arg "BUILD_REVISION=${build_revision}"
  "$root_dir"
)
printf 'image_tag=%s\nrelease=%s\ncommit=%s\nsource_sha256=%s\n' \
  "$image_tag" "$release_tag" "$commit" "$source_sha"
"${build[@]}"
if [[ "$build_mode" == "load" ]]; then
  architecture="$(docker image inspect "$image_tag" --format '{{.Architecture}}')"
  if [[ -n "$target_platforms" && "linux/${architecture}" != "$target_platforms" ]]; then
    printf 'loaded architecture differs from requested platform: %s\n' "$architecture" >&2
    exit 1
  fi
  docker image inspect "$image_tag" --format 'image_id={{.Id}} architecture={{.Architecture}}'
else
  docker buildx imagetools inspect "$image_tag"
fi
