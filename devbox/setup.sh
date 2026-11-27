#!/usr/bin/env bash
# One-time environment preparation, run from the devbox init_hook.
# Everything here is guarded so repeated shell entries are cheap.
set -o errexit
set -o pipefail
set -o nounset

ROOT="${DEVBOX_PROJECT_ROOT:?DEVBOX_PROJECT_ROOT not set}"

# --------------------------------------------------------------------------
# Runtime data directories (gitignored) replace the docker named volumes.
# --------------------------------------------------------------------------
mkdir -p "$ROOT/.devbox-data/postgres" \
         "$ROOT/.devbox-data/mongo" \
         "$ROOT/.devbox-data/seaweedfs"

# --------------------------------------------------------------------------
# JWT keys (generated at runtime, gitignored)
# --------------------------------------------------------------------------
JWT_DIR="$ROOT/jwt"
mkdir -p "$JWT_DIR"
if [ ! -f "$JWT_DIR/jwt_key" ]; then
    echo "==> Generating JWT RSA key pair..."
    openssl genrsa -out "$JWT_DIR/jwt_key" 2048
    openssl rsa -in "$JWT_DIR/jwt_key" -pubout -out "$JWT_DIR/jwt_key.pub"
    chmod 600 "$JWT_DIR/jwt_key"
    chmod 644 "$JWT_DIR/jwt_key.pub"
fi

# --------------------------------------------------------------------------
# Python virtual environment (replaces the dserver-build-venv container)
# --------------------------------------------------------------------------
# VENV-READY holds the checksum of setup-venv.sh that built the venv, so a
# changed script (new or changed dependencies) updates existing venvs too.
VENV_STAMP="$(shasum "$ROOT/devbox/setup-venv.sh" | cut -d" " -f1)"
if [ ! -f "$ROOT/.venv/VENV-READY" ]; then
    echo "==> Building Python virtual environment (first run, this can take a while)..."
    bash "$ROOT/devbox/setup-venv.sh"
elif [ "$(cat "$ROOT/.venv/VENV-READY")" != "$VENV_STAMP" ]; then
    echo "==> devbox/setup-venv.sh changed, updating the virtual environment..."
    bash "$ROOT/devbox/setup-venv.sh"
fi

# --------------------------------------------------------------------------
# Node dependencies (replaces the webapp image build)
# --------------------------------------------------------------------------
# The webapp uses the built dserver-client-js (dist/), so rebuild when the
# client sources, the dependencies or setup-webapp.sh change; otherwise the
# webapp compiles against an outdated client. The stamp lives in the
# webapp's node_modules, so deleting that directory also forces a rebuild.
WEBAPP_DIR="$ROOT/dserver-webapp/dserver-webapp"
webapp_stamp() {
    cd "$ROOT" && find devbox/setup-webapp.sh dserver-client-js/src \
        dserver-client-js/package.json dserver-client-js/package-lock.json \
        "$WEBAPP_DIR/package.json" "$WEBAPP_DIR/package-lock.json" \
        -type f 2>/dev/null | sort | xargs shasum | shasum | cut -d" " -f1
}
if [ "$(cat "$WEBAPP_DIR/node_modules/.devbox-ready" 2>/dev/null)" != "$(webapp_stamp)" ]; then
    echo "==> Building dserver-client-js and installing Node dependencies (this can take a while)..."
    bash "$ROOT/devbox/setup-webapp.sh"
    # After the setup: npm install may create or update the lock files.
    webapp_stamp > "$WEBAPP_DIR/node_modules/.devbox-ready"
fi
