#!/usr/bin/env sh

set -e

###############################################################################
# Authenticate with OpenBao
###############################################################################
JWT=$(cat "${TOKEN_PATH:=/var/run/secrets/kubernetes.io/serviceaccount/token}")
export JWT

echo "Using OpenBao auth path: $BAO_AUTH_PATH"
BAO_TOKEN=$(bao write -field=token "auth/$BAO_AUTH_PATH/login" role="${BAO_ROLE}" jwt="${JWT}")
export BAO_TOKEN

###############################################################################
# Create snapshot
###############################################################################
SNAPSHOT_FILE="bao_$(date +%F-%H%M).snapshot"
bao operator raft snapshot save "/bao-snapshots/${SNAPSHOT_FILE}"

###############################################################################
# Build oli profile configuration
# Supported OLI_STORAGE_TYPE values: s3, gcs, azblob
###############################################################################
OLI_PROFILE="${OLI_PROFILE:-bao}"
OLI_CONFIG_DIR="${HOME}/.config/oli"
mkdir -p "${OLI_CONFIG_DIR}"

{
  printf '[profiles.%s]\n' "${OLI_PROFILE}"
  printf 'type = "%s"\n'   "${OLI_STORAGE_TYPE}"
  [ -n "${OLI_ROOT}" ] && printf 'root = "%s"\n' "${OLI_ROOT}"

  case "${OLI_STORAGE_TYPE}" in
    s3)
      printf 'bucket = "%s"\n' "${OLI_BUCKET}"
      printf 'region = "%s"\n' "${OLI_REGION:-us-east-1}"
      [ -n "${OLI_ENDPOINT}"          ] && printf 'endpoint = "%s"\n'          "${OLI_ENDPOINT}"
      [ -n "${AWS_ACCESS_KEY_ID}"     ] && printf 'access_key_id = "%s"\n'     "${AWS_ACCESS_KEY_ID}"
      [ -n "${AWS_SECRET_ACCESS_KEY}" ] && printf 'secret_access_key = "%s"\n' "${AWS_SECRET_ACCESS_KEY}"
      [ -n "${AWS_SESSION_TOKEN}"     ] && printf 'session_token = "%s"\n'     "${AWS_SESSION_TOKEN}"
      ;;
    gcs)
      printf 'bucket = "%s"\n' "${OLI_BUCKET}"
      [ -n "${GOOGLE_APPLICATION_CREDENTIALS}" ] && printf 'credential_path = "%s"\n' "${GOOGLE_APPLICATION_CREDENTIALS}"
      [ -n "${GCS_SERVICE_ACCOUNT_KEY}"        ] && printf 'credential = "%s"\n'      "${GCS_SERVICE_ACCOUNT_KEY}"
      ;;
    azblob)
      printf 'container = "%s"\n' "${OLI_CONTAINER}"
      [ -n "${AZURE_STORAGE_ENDPOINT}"     ] && printf 'endpoint = "%s"\n'     "${AZURE_STORAGE_ENDPOINT}"
      [ -n "${AZURE_STORAGE_ACCOUNT_NAME}" ] && printf 'account_name = "%s"\n' "${AZURE_STORAGE_ACCOUNT_NAME}"
      [ -n "${AZURE_STORAGE_ACCOUNT_KEY}"  ] && printf 'account_key = "%s"\n'  "${AZURE_STORAGE_ACCOUNT_KEY}"
      [ -n "${AZURE_STORAGE_SAS_TOKEN}"    ] && printf 'sas_token = "%s"\n'    "${AZURE_STORAGE_SAS_TOKEN}"
      ;;
    *)
      echo "ERROR: Unsupported OLI_STORAGE_TYPE '${OLI_STORAGE_TYPE}'. Supported values: s3, gcs, azblob" >&2
      exit 1
      ;;
  esac
} > "${OLI_CONFIG_DIR}/config.toml"

###############################################################################
# Upload snapshot to remote storage via oli
###############################################################################
echo "Uploading ${SNAPSHOT_FILE} to ${OLI_PROFILE}:/${SNAPSHOT_FILE} ..."
oli cp "/bao-snapshots/${SNAPSHOT_FILE}" "${OLI_PROFILE}:/${SNAPSHOT_FILE}"
echo "Snapshot uploaded successfully."

# Remove local snapshot files now that they are safely stored remotely
rm -f /bao-snapshots/*.snapshot

###############################################################################
# Remove expired remote snapshots
# Snapshot filenames encode their creation date: bao_YYYY-MM-DD-HHMM.snapshot
###############################################################################
if [ -n "${OLI_EXPIRE_DAYS}" ]; then
  echo "Removing snapshots older than ${OLI_EXPIRE_DAYS} days..."

  NOW_SECS=$(date +%s)
  EXPIRE_THRESHOLD_SECS=$((NOW_SECS - OLI_EXPIRE_DAYS * 86400))

  oli ls "${OLI_PROFILE}:/" | while read -r fileName; do
    # Only process .snapshot files
    case "${fileName}" in *.snapshot) ;; *) continue ;; esac

    # Extract the date from filename: bao_2026-02-26-1430.snapshot -> 2026-02-26
    fileDate=$(printf '%s' "${fileName}" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)
    [ -z "${fileDate}" ] && continue

    fileTs=$(date -d "${fileDate}" +%s 2>/dev/null) || continue

    if [ "${fileTs}" -lt "${EXPIRE_THRESHOLD_SECS}" ]; then
      echo "Removing expired snapshot: ${fileName}"
      oli rm "${OLI_PROFILE}:/${fileName}"
    fi
  done
fi
