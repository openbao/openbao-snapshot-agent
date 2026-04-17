#!/usr/bin/env sh

set -e

# Authenticate with OpenBao
JWT=$(cat "${TOKEN_PATH:=/var/run/secrets/kubernetes.io/serviceaccount/token}")
export JWT

echo "Using OpenBao auth path: $BAO_AUTH_PATH"
BAO_TOKEN=$(bao write -field=token  "auth/$BAO_AUTH_PATH/login" role="${BAO_ROLE}" jwt="${JWT}")
export BAO_TOKEN

if [ "${BAO_SECRET_PATH}" ]; then
    echo "Fetching S3 credentials from OpenBao: ${BAO_SECRET_PATH}"
    AWS_ACCESS_KEY_ID=$(bao kv get -field AWS_ACCESS_KEY_ID "${BAO_SECRET_PATH}")
    export AWS_ACCESS_KEY_ID

    AWS_SECRET_ACCESS_KEY=$(bao kv get -field AWS_SECRET_ACCESS_KEY "${BAO_SECRET_PATH}")
    export AWS_SECRET_ACCESS_KEY
fi

# Create snapshot
bao operator raft snapshot save /bao-snapshots/bao_"$(date +%F-%H%M)".snapshot

# Upload to S3
s3cmd put /bao-snapshots/* "${S3_URI}" --host="${S3_HOST}" --host-bucket="${S3_BUCKET}" ${S3CMD_EXTRA_FLAG:+$S3CMD_EXTRA_FLAG}

# Remove expired snapshots
if [ "${S3_EXPIRE_DAYS}" ]; then
    s3cmd ls "${S3_URI}" --host="${S3_HOST}" --host-bucket="${S3_BUCKET}" ${S3CMD_EXTRA_FLAG:+$S3CMD_EXTRA_FLAG} | while read -r line; do
        createDate=$(echo "$line" | awk '{print $1" "$2}')
        createDate=$(date -d"$createDate" +%s)
        olderThan=$(date --date @$(($(date +%s) - 86400*S3_EXPIRE_DAYS)) +%s)
        if [ "$createDate" -lt "$olderThan" ]; then
            fileName=$(echo "$line" | awk '{print $4}')
            if [ "$fileName" != "" ]; then
                s3cmd del "$fileName" --host="${S3_HOST}" --host-bucket="${S3_BUCKET}" ${S3CMD_EXTRA_FLAG:+$S3CMD_EXTRA_FLAG}
            fi
        fi
    done;
fi
