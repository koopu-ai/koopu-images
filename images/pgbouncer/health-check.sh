#!/usr/bin/env bash
set -euo pipefail

image="${1:?usage: health-check.sh IMAGE}"
target_platform="${TARGET_PLATFORM:-}"
container="koopu-pgbouncer-health-${RANDOM}-$$"
platform_args=()
scratch="$(mktemp -d)"
started=0

case "$target_platform" in
  "") ;;
  linux/amd64|linux/arm64) platform_args=(--platform "$target_platform") ;;
  *) printf 'TARGET_PLATFORM must be linux/amd64 or linux/arm64: %s\n' "$target_platform" >&2; exit 2 ;;
esac

cleanup() {
  local status="$?"
  trap - EXIT
  if [[ "$started" == "1" ]]; then
    if [[ "$status" != "0" ]]; then
      docker logs "$container"
    fi
    docker rm --force "$container" >/dev/null
  fi
  rm -rf "$scratch"
  exit "$status"
}
trap cleanup EXIT

label() {
  docker image inspect "$image" --format "{{index .Config.Labels \"$1\"}}"
}

version="$(label com.koopu.pgbouncer.version)"
build_revision="$(label com.koopu.image.build-revision)"
base_image="$(label com.koopu.pgbouncer.base)"
source_sha="$(label com.koopu.pgbouncer.source-sha256)"
runtime_user="$(docker image inspect "$image" --format '{{.Config.User}}')"

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || [[ ! "$build_revision" =~ ^[0-9]+$ ]] \
  || [[ ! "$source_sha" =~ ^[0-9a-f]{64}$ ]]; then
  printf 'missing or invalid PgBouncer image labels\n' >&2
  exit 2
fi
expected_tag="koopu/pgbouncer:${version}-alpine3.23-b${build_revision}"
if [[ "$image" != "$expected_tag" ]]; then
  printf 'image tag is not self-describing: expected %s, got %s\n' "$expected_tag" "$image" >&2
  exit 2
fi
if [[ ! "$base_image" =~ ^alpine:3[.]23@sha256:[0-9a-f]{64}$ ]]; then
  printf 'base image label is not the digest-pinned Alpine 3.23 baseline: %s\n' "$base_image" >&2
  exit 2
fi
if [[ "$runtime_user" != "6432:6432" ]]; then
  printf 'runtime user must be fixed non-root 6432:6432, got %s\n' "$runtime_user" >&2
  exit 2
fi

version_output="$(docker run "${platform_args[@]}" --rm --entrypoint /usr/local/bin/pgbouncer "$image" --version)"
if [[ "$version_output" != *"PgBouncer ${version}"* ]]; then
  printf 'unexpected version output: %s\n' "$version_output" >&2
  exit 1
fi
docker run "${platform_args[@]}" --rm --entrypoint sh "$image" -c '
  test "$(id -u)" = 6432
  test "$(id -g)" = 6432
  ! command -v cc
  ! ldd /usr/local/bin/pgbouncer | grep "not found"
'

cat > "$scratch/pgbouncer.ini" <<'EOF'
[databases]
health = host=127.0.0.1 port=6543 dbname=health

[pgbouncer]
listen_addr = 127.0.0.1
listen_port = 6432
unix_socket_dir = /tmp
pidfile = /tmp/pgbouncer.pid
auth_type = scram-sha-256
auth_file = /etc/pgbouncer/userlist.txt
pool_mode = transaction
max_client_conn = 10000
default_pool_size = 10
reserve_pool_size = 2
max_prepared_statements = 0
EOF
: > "$scratch/userlist.txt"
config_directory_mode=0755
if [[ "${ALLOW_UNREADABLE_CONFIG_TEST:-0}" == "1" ]]; then
  config_directory_mode=0700
fi
chmod "$config_directory_mode" "$scratch"
chmod 0644 "$scratch/pgbouncer.ini" "$scratch/userlist.txt"

container_id="$(docker run "${platform_args[@]}" --detach --name "$container" \
  --network none \
  --read-only \
  --tmpfs /tmp:rw,nosuid,nodev,noexec,size=16m \
  --volume "$scratch:/etc/pgbouncer:ro" \
  "$image")"
if [[ ! "$container_id" =~ ^[0-9a-f]{64}$ ]]; then
  printf 'docker did not return a full container ID: %s\n' "$container_id" >&2
  exit 1
fi
started=1
for _ in {1..10}; do
  if [[ "$(docker inspect "$container" --format '{{.State.Running}}')" != "true" ]]; then
    printf 'PgBouncer exited during configuration smoke test\n' >&2
    exit 1
  fi
  sleep 0.2
done
docker exec "$container" sh -c 'test "$(id -u)" = 6432 && kill -0 1'

printf 'health_check=pass image=%s version=%s uid=6432 platform=%s\n' \
  "$image" "$version" "${target_platform:-host}"
