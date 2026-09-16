#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${TMP_MEDIA_ROOT:-/opt/tmp-media-ai}"
ENV_FILE="${TMP_MEDIA_ENV:-/etc/tmp-media-ai.env}"
[ -f "$ENV_FILE" ] && source "$ENV_FILE"

KEY_HEADER=()
if [ -n "${TMP_MEDIA_API_KEY:-}" ]; then
  KEY_HEADER=(-H "X-API-Key: ${TMP_MEDIA_API_KEY}")
fi

curl -fsS "${KEY_HEADER[@]}" "http://127.0.0.1:${TMP_MEDIA_GATEWAY_PORT:-8200}/api/v1/health" | python3 -m json.tool
