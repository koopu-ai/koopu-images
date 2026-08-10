#!/usr/bin/env bash
set -euo pipefail

image="${1:?usage: health-check.sh IMAGE}"
target_platform="${TARGET_PLATFORM:-}"
container="koopu-minio-health-${RANDOM}-$$"
platform_args=()
started=0

case "$target_platform" in
  "") ;;
  linux/amd64|linux/arm64) platform_args=(--platform "$target_platform") ;;
  *) printf 'TARGET_PLATFORM must be linux/amd64 or linux/arm64: %s\n' "$target_platform" >&2; exit 2 ;;
esac

# ShellCheck cannot resolve the indirect invocation through the EXIT trap below.
# shellcheck disable=SC2317
cleanup() {
  local status="$?"
  trap - EXIT
  if [[ "$started" == "1" ]]; then
    [[ "$status" == "0" ]] || docker logs "$container"
    docker rm --force "$container" >/dev/null
  fi
  exit "$status"
}
trap cleanup EXIT

label() { docker image inspect "$image" --format "{{index .Config.Labels \"$1\"}}"; }
release="$(label org.opencontainers.image.version)"
commit="$(label org.opencontainers.image.revision)"
source_sha="$(label com.koopu.minio.source-sha256)"
build_revision="$(label com.koopu.image.build-revision)"
if [[ ! "$release" =~ ^RELEASE\.[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}-[0-9]{2}-[0-9]{2}Z$ ]] \
  || [[ ! "$commit" =~ ^[0-9a-f]{40}$ ]] \
  || [[ ! "$source_sha" =~ ^[0-9a-f]{64}$ ]] \
  || [[ ! "$build_revision" =~ ^[0-9]+$ ]]; then
  printf 'missing or invalid MinIO image labels\n' >&2
  exit 2
fi
expected="koopu/minio:${release}-b${build_revision}"
[[ "$image" == "$expected" ]] || { printf 'non-self-describing image tag: %s\n' "$image" >&2; exit 2; }
version_output="$(docker run "${platform_args[@]}" --rm --entrypoint /usr/bin/minio "$image" --version)"
[[ "$version_output" == *"$release"* && "$version_output" == *"$commit"* ]] \
  || { printf 'unexpected MinIO version output\n' >&2; exit 1; }

docker run "${platform_args[@]}" --detach --name "$container" --network none \
  --env MINIO_ROOT_USER=test_health_admin \
  --env MINIO_ROOT_PASSWORD=test-only-health-password-Aa1 \
  "$image" server /data >/dev/null
started=1
for _ in {1..60}; do
  if docker exec "$container" curl -fsS http://127.0.0.1:9000/minio/health/live >/dev/null; then
    printf 'health_check=pass image=%s release=%s platform=%s\n' \
      "$image" "$release" "${target_platform:-host}"
    exit 0
  fi
  sleep 0.5
done
printf 'MinIO did not become healthy\n' >&2
exit 1
