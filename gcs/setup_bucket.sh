#!/usr/bin/env bash
set -euo pipefail

BUCKET="gs://robot-tutor.firebasestorage.app"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR="${SCRIPT_DIR}/.tmp_keep"

echo "Using existing bucket: ${BUCKET}"
echo "Skipping bucket creation."

mkdir -p "${TMP_DIR}"

OBJECTS=(
  "raw-uploads/.keep"
  "processed/.keep"
  "module-media/math/.keep"
  "module-media/english/.keep"
  "module-media/science/.keep"
  "module-media/custom/.keep"
  "icons/.keep"
)

for object_path in "${OBJECTS[@]}"; do
  local_path="${TMP_DIR}/${object_path}"
  mkdir -p "$(dirname "${local_path}")"
  : > "${local_path}"
  gcloud storage cp "${local_path}" "${BUCKET}/${object_path}" >/dev/null
  echo "Ensured ${BUCKET}/${object_path}"
done

cat > "${SCRIPT_DIR}/cors.json" <<'JSON'
[
  {
    "origin": ["*"],
    "method": ["GET"],
    "maxAgeSeconds": 3600
  }
]
JSON

echo "Applying CORS config from ${SCRIPT_DIR}/cors.json..."
gcloud storage buckets update "${BUCKET}" --cors-file="${SCRIPT_DIR}/cors.json"

rm -rf "${TMP_DIR}"
echo "Done."
