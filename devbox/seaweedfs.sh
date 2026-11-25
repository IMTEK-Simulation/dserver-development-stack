#!/usr/bin/env bash
# SeaweedFS S3-compatible object storage service.
#
# Identities (admin/secret12, anonymous read) are defined in
# devbox/seaweedfs/s3.json. `-master.electionTimeout` only matters to a
# multi-master cluster; the single master here still waits it out on every
# start, so the default 10s just delays the S3 gateway behind it. The volume
# server moves from its default port 8080, which is the webapp's.
set -o errexit
set -o pipefail
set -o nounset

ROOT="${DEVBOX_PROJECT_ROOT:?DEVBOX_PROJECT_ROOT not set}"
DATA="$ROOT/.devbox-data/seaweedfs"
mkdir -p "$DATA"

# After a restart, the previous instance may still be shutting down: wait
# until its ports (master, volume, filer, S3) are free, or fail clearly.
port_in_use() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }
for port in 9333 8090 8888 9000; do
    for _ in $(seq 1 30); do
        port_in_use "$port" || continue 2
        sleep 1
    done
    echo "==> Port $port is still in use; is another SeaweedFS running?" >&2
    exit 1
done

exec weed server \
    -ip=127.0.0.1 \
    -dir="$DATA" \
    -volume.port=8090 \
    -filer \
    -s3 -s3.port=9000 \
    -s3.config="$ROOT/devbox/seaweedfs/s3.json" \
    -master.electionTimeout=1s
