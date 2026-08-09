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
    /usr/local/bin/pgbouncer --version
    sha256sum /usr/local/bin/pgbouncer
    cat /usr/local/share/licenses/pgbouncer/COPYRIGHT
  } | sha256sum
'
