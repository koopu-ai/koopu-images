#!/usr/bin/env bash
set -euo pipefail

image="${1:?usage: artifact-fingerprint.sh IMAGE}"
target_platform="${TARGET_PLATFORM:-}"
platform_args=()
case "$target_platform" in
  "") ;;
  linux/amd64|linux/arm64) platform_args=(--platform "$target_platform") ;;
  *) printf 'TARGET_PLATFORM must be linux/amd64 or linux/arm64: %s\n' "$target_platform" >&2; exit 2 ;;
esac

docker run "${platform_args[@]}" --rm --entrypoint sh "$image" -c '
  {
    /usr/bin/minio --version
    sha256sum /usr/bin/minio
    sha256sum /usr/share/licenses/minio/LICENSE
  } | sha256sum
'
