#!/usr/bin/env bash
# Build the Python virtual environment with all dserver packages in editable
# mode. Mirrors compose/dserver/scripts/make-venv.sh but installs into a
# project-local .venv instead of the /venv docker volume.
set -o errexit
set -o pipefail
set -o nounset

ROOT="${DEVBOX_PROJECT_ROOT:?DEVBOX_PROJECT_ROOT not set}"
VENV="$ROOT/.venv"

echo "==> Creating Python virtual environment..."
python -m venv "$VENV"
# shellcheck disable=SC1091
source "$VENV/bin/activate"

echo "==> Upgrading pip..."
# Pin setuptools < 81: dtool-cli (and other dtool packages) still import the
# legacy pkg_resources module, which setuptools removed in v81.
pip install --upgrade pip wheel "setuptools<81"

echo "==> Installing the dtool command line tools (from PyPI)..."
# The CLI plugins individually instead of the 'dtool' meta-package: that pins
# exact, older versions (e.g. dtoolcore==3.18.3, dtool-cli==0.7.1, which
# fails on Python >= 3.12 without pkg_resources) and would replace the
# editable dtoolcore below. Installed first, so the editable submodules win.
pip uninstall --yes dtool 2>/dev/null || true  # meta-package in older venvs
pip install "dtool-cli>=0.7.2" dtool-create dtool-info dtool-symlink \
    dtool-http dtool-config dtool-overlay dtool-annotation dtool-tag

echo "==> Installing dtoolcore..."
pip install -e "$ROOT/dtoolcore"

echo "==> Installing dtool-s3..."
pip install -e "$ROOT/dtool-s3"

echo "==> Installing dtool-dserver (dserver:// storage broker, dtool dserver login)..."
pip install -e "$ROOT/dtool-dserver"

echo "==> Installing dservercore..."
pip install -e "$ROOT/dservercore"

echo "==> Installing dserver-search-plugin-mongo..."
pip install -e "$ROOT/dserver-search-plugin-mongo"

echo "==> Installing dserver-retrieve-plugin-mongo..."
pip install -e "$ROOT/dserver-retrieve-plugin-mongo"

echo "==> Installing dserver-dependency-graph-plugin..."
pip install -e "$ROOT/dserver-dependency-graph-plugin"

echo "==> Installing dserver-signed-url-plugin..."
pip install -e "$ROOT/dserver-signed-url-plugin"

echo "==> Installing dserver-token-generator-plugin-oauth2..."
pip install -e "$ROOT/dserver-token-generator-plugin-oauth2"

echo "==> Installing additional dependencies..."
# psycopg 3: SQLAlchemy >= 2.1 uses it for postgresql:// URLs by default.
pip install gunicorn "psycopg[binary]" PyJWT requests authlib httpx python-dotenv flask-cors

echo "==> Checking the virtual environment..."
# Fail here, not later as a dserver restart loop: import what the services
# need and load the database driver of SQLALCHEMY_DATABASE_URI (no
# connection is made).
python - <<'PYEOF'
import os

import sqlalchemy

import dservercore  # noqa: F401
import dtool_dserver  # noqa: F401
import dtool_s3  # noqa: F401
import dtoolcore

# dtoolcore must be the editable submodule, not a release pulled in as a
# dependency.
root = os.environ["DEVBOX_PROJECT_ROOT"]
assert dtoolcore.__file__.startswith(os.path.join(root, "dtoolcore")), \
    f"dtoolcore is not the submodule: {dtoolcore.__file__}"

sqlalchemy.create_engine(os.environ["SQLALCHEMY_DATABASE_URI"])
print("    OK")
PYEOF

echo "==> Virtual environment setup complete!"
# Record which version of this script built the venv; devbox/setup.sh
# re-runs it when the script changes (e.g. new or changed dependencies).
shasum "$ROOT/devbox/setup-venv.sh" | cut -d" " -f1 > "$VENV/VENV-READY"
