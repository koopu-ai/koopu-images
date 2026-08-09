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
    postgres --version
    awk "/default_version/ {print FILENAME \":\" \$0}" \
      /usr/local/share/postgresql/extension/vector.control \
      /usr/local/share/postgresql/extension/timescaledb.control
    sha256sum /usr/local/share/licenses/pgvector/LICENSE
    find /usr/local/lib/postgresql /usr/local/share/postgresql/extension \
      -type f \( -name "vector*" -o -path "*/bitcode/vector/*" \) \
      -exec sha256sum {} \;
  } | LC_ALL=C sort | sha256sum
'
