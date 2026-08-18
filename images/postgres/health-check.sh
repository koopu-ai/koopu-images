#!/usr/bin/env bash
set -euo pipefail

image="${1:?usage: health-check.sh IMAGE}"
target_platform="${TARGET_PLATFORM:-}"
container="koopu-postgres-health-${RANDOM}-$$"
platform_args=()
export POSTGRES_PASSWORD
POSTGRES_PASSWORD="$(openssl rand -hex 24)"
started=0

case "$target_platform" in
  "") ;;
  linux/amd64|linux/arm64) platform_args=(--platform "$target_platform") ;;
  *) printf 'TARGET_PLATFORM must be linux/amd64 or linux/arm64: %s\n' "$target_platform" >&2; exit 2 ;;
esac

cleanup() {
  local status="$?"
  if [[ "$started" == "1" ]]; then
    if [[ "$status" != "0" ]]; then
      docker logs "$container"
    fi
    docker rm --force "$container"
  fi
  return "$status"
}
trap cleanup EXIT

label() {
  docker image inspect "$image" --format "{{index .Config.Labels \"$1\"}}"
}

pg_major="$(label com.koopu.postgres.major)"
pg_version="$(label com.koopu.postgres.version)"
ts_version="$(label com.koopu.timescaledb.version)"
vector_version="$(label com.koopu.pgvector.version)"
build_revision="$(label com.koopu.image.build-revision)"
base_image="$(label com.koopu.postgres.base)"
timescaledb_tools_image="$(label com.koopu.timescaledb.tools-base)"

for value in "$pg_major" "$pg_version" "$ts_version" "$vector_version" "$build_revision"; do
  if [[ ! "$value" =~ ^[0-9]+([.][0-9]+){0,2}$ ]]; then
    printf 'missing or invalid image version label: %s\n' "$value" >&2
    exit 2
  fi
done
expected_tag="koopu/postgres:pg${pg_version}-ts${ts_version}-pgv${vector_version}-b${build_revision}"
if [[ "$image" != "$expected_tag" ]]; then
  printf 'image tag is not self-describing: expected %s, got %s\n' "$expected_tag" "$image" >&2
  exit 2
fi
if [[ ! "$base_image" =~ @sha256:[0-9a-f]{64}$ ]]; then
  printf 'base image label is not digest-pinned: %s\n' "$base_image" >&2
  exit 2
fi
if [[ ! "$timescaledb_tools_image" =~ ^timescale/timescaledb:[^@]+@sha256:[0-9a-f]{64}$ ]]; then
  printf 'TimescaleDB tools image label is not digest-pinned: %s\n' "$timescaledb_tools_image" >&2
  exit 2
fi

docker run "${platform_args[@]}" --detach --name "$container" \
  --network none \
  --env POSTGRES_PASSWORD \
  "$image" \
  -c shared_preload_libraries=timescaledb,pg_stat_statements
started=1

ready=0
for _ in {1..60}; do
  if docker exec "$container" grep -q -x postgres /proc/1/comm \
    && docker exec "$container" pg_isready --quiet --username postgres --dbname postgres; then
    ready=1
    break
  fi
  sleep 1
done
if [[ "$ready" != "1" ]]; then
  printf 'final PID 1 postgres did not become ready within 60 seconds\n' >&2
  exit 1
fi
docker exec "$container" grep -x postgres /proc/1/comm
docker exec "$container" pg_isready --username postgres --dbname postgres
docker exec "$container" timescaledb-tune --version
docker exec "$container" timescaledb-parallel-copy --version

docker exec --interactive "$container" psql \
  --no-psqlrc \
  --username postgres \
  --dbname postgres \
  --set ON_ERROR_STOP=on \
  --set expected_pg_major="$pg_major" \
  --set expected_pg_version="$pg_version" \
  --set expected_ts="$ts_version" \
  --set expected_vector="$vector_version" <<'SQL'
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS timescaledb;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

SELECT 1 / (split_part(current_setting('server_version'), '.', 1) = :'expected_pg_major')::int
  AS require_expected_postgres_major;
SELECT 1 / (current_setting('server_version') = :'expected_pg_version')::int
  AS require_expected_postgres_version;
SELECT 1 / (extversion = :'expected_vector')::int AS require_expected_vector
  FROM pg_extension WHERE extname = 'vector';
SELECT 1 / (string_to_array(extversion, '.')::int[] >= ARRAY[0,8,2])::int
  AS require_vector_at_or_above_cve_floor
  FROM pg_extension WHERE extname = 'vector';
SELECT 1 / (extversion = :'expected_ts')::int AS require_expected_timescaledb
  FROM pg_extension WHERE extname = 'timescaledb';
SELECT 1 / (count(*) = 0)::int AS require_forbidden_extensions_absent
  FROM pg_available_extensions
  WHERE name IN ('postgis', 'ai', 'vectorscale', 'pgmq', 'pg_cron');

SELECT 1 AS pg_stat_statements_queryable FROM pg_stat_statements LIMIT 1;
SELECT current_setting('server_version') AS server_version,
       (SELECT extversion FROM pg_extension WHERE extname='timescaledb') AS timescaledb,
       (SELECT extversion FROM pg_extension WHERE extname='vector') AS vector,
       current_setting('shared_preload_libraries') AS shared_preload_libraries;
SQL

printf 'health_check=pass image=%s platform=%s\n' "$image" "${target_platform:-host}"
