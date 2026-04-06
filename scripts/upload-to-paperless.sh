#!/usr/bin/env bash
# Upload a file to Paperless-ngx via REST API
set -euo pipefail

FILE_PATH="$1"
TITLE="${2:-}"

if [[ ! -f "$FILE_PATH" ]]; then
    echo "ERROR: File not found: $FILE_PATH" >&2
    exit 1
fi

if [[ -z "${PAPERLESS_URL:-}" || -z "${PAPERLESS_TOKEN:-}" ]]; then
    echo "ERROR: PAPERLESS_URL and PAPERLESS_TOKEN must be set" >&2
    exit 1
fi

API_URL="${PAPERLESS_URL}/api/documents/post_document/"

CURL_ARGS=(
    -s -w "\n%{http_code}"
    -X POST
    -H "Authorization: Token ${PAPERLESS_TOKEN}"
    -F "document=@${FILE_PATH}"
)

[[ -n "$TITLE" ]] && CURL_ARGS+=(-F "title=${TITLE}")
[[ -n "${DEFAULT_TAG_IDS:-}" ]] && {
    IFS=',' read -ra TAGS <<< "$DEFAULT_TAG_IDS"
    for tag in "${TAGS[@]}"; do
        CURL_ARGS+=(-F "tags=${tag}")
    done
}
[[ -n "${DEFAULT_CORRESPONDENT_ID:-}" ]] && CURL_ARGS+=(-F "correspondent=${DEFAULT_CORRESPONDENT_ID}")
[[ -n "${DEFAULT_DOC_TYPE_ID:-}" ]] && CURL_ARGS+=(-F "document_type=${DEFAULT_DOC_TYPE_ID}")

RESPONSE=$(curl "${CURL_ARGS[@]}" "$API_URL")
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -n -1)

if [[ "$HTTP_CODE" -ge 200 && "$HTTP_CODE" -lt 300 ]]; then
    TASK_ID=$(echo "$BODY" | jq -r '.task_id // empty' 2>/dev/null || true)
    echo "OK: uploaded $(basename "$FILE_PATH") (task: ${TASK_ID:-unknown})"
    exit 0
else
    echo "ERROR: HTTP ${HTTP_CODE} uploading $(basename "$FILE_PATH")" >&2
    echo "$BODY" >&2
    exit 1
fi
