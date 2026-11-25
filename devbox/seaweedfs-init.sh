#!/usr/bin/env bash
# Create the dtool-bucket and allow cross-origin access from the webapp.
# Anonymous read access is granted by the "anonymous" identity in
# devbox/seaweedfs/s3.json.
set -o errexit
set -o pipefail
set -o nounset

ROOT="${DEVBOX_PROJECT_ROOT:?DEVBOX_PROJECT_ROOT not set}"
S3=(aws --endpoint-url http://127.0.0.1:9000 --region us-east-1)

setup_bucket() {
    "${S3[@]}" s3api head-bucket --bucket dtool-bucket 2>/dev/null \
        || "${S3[@]}" s3 mb s3://dtool-bucket \
        || return 1
    "${S3[@]}" s3api put-bucket-cors --bucket dtool-bucket \
        --cors-configuration "file://$ROOT/devbox/seaweedfs/cors.json"
}

# SeaweedFS may report ready before every part (filer, IAM) serves requests,
# e.g. on a clean first start. Retry for up to a minute.
for attempt in $(seq 1 30); do
    if setup_bucket; then
        echo "==> SeaweedFS bucket 'dtool-bucket' ready."
        exit 0
    fi
    echo "    SeaweedFS not ready yet (attempt $attempt), retrying..."
    sleep 2
done
echo "==> Could not set up bucket 'dtool-bucket' on SeaweedFS." >&2
exit 1
