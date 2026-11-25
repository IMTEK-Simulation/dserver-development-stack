#!/usr/bin/env bash
# Run the Vue.js webapp development server with hot reload.
# VUE_APP_* configuration comes from the environment (see devbox.json).
set -o errexit
set -o pipefail
set -o nounset

ROOT="${DEVBOX_PROJECT_ROOT:?DEVBOX_PROJECT_ROOT not set}"
cd "$ROOT/dtool-lookup-webapp/dtool-lookup-webapp"

# The dev server silently moves to the next free port if 8080 is taken, where
# the readiness probe and the OAuth2 redirects would not find it: fail
# instead.
if (exec 3<>/dev/tcp/127.0.0.1/8080) 2>/dev/null; then
    echo "==> Port 8080 is already in use; stop the other process first." >&2
    exit 1
fi

exec npm run serve -- --host 127.0.0.1 --port 8080
