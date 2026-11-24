#!/usr/bin/env bash
# Register a user in dserver with access to s3://dtool-bucket, e.g. your
# ORCID iD after logging in to the webapp with ORCID (the OAuth2 plugin does
# not create users itself).
# Usage: devbox run add-user <username> [--no-admin]
set -o errexit
set -o pipefail
set -o nounset

ROOT="${DEVBOX_PROJECT_ROOT:?DEVBOX_PROJECT_ROOT not set}"
cd "$ROOT"

if [ $# -lt 1 ]; then
    echo "Usage: devbox run add-user <username, e.g. ORCID iD> [--no-admin]" >&2
    exit 1
fi
USERNAME="$1"
ADMIN="--is_admin"
if [ "${2:-}" = "--no-admin" ]; then
    ADMIN=""
fi

# shellcheck disable=SC1091
source "$ROOT/.venv/bin/activate"

echo "==> Registering user '$USERNAME'..."
# shellcheck disable=SC2086
flask user add $ADMIN "$USERNAME" || echo "    User may already exist"
flask user search_permission "$USERNAME" s3://dtool-bucket
flask user register_permission "$USERNAME" s3://dtool-bucket
echo "==> '$USERNAME' may search and register datasets in s3://dtool-bucket."
