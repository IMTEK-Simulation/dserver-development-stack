#!/usr/bin/env bash
# Fill the running stack with demonstration datasets (with dependencies) in
# s3://dtool-bucket and index them in dserver. See devbox/seed_demo_data.py.
# Usage: devbox run seed-demo-data [-- --force]
set -o errexit
set -o pipefail
set -o nounset

ROOT="${DEVBOX_PROJECT_ROOT:?DEVBOX_PROJECT_ROOT not set}"
cd "$ROOT"

# shellcheck disable=SC1091
source "$ROOT/.venv/bin/activate"

echo "==> Creating demonstration datasets in s3://dtool-bucket..."
python "$ROOT/devbox/seed_demo_data.py" "$@"

echo "==> Indexing s3://dtool-bucket in dserver..."
flask base_uri index s3://dtool-bucket
echo "==> Done. Search for 'demo' in the webapp (http://127.0.0.1:8080)."
