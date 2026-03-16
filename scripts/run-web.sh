#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_KEYS_FILE="${SCRIPT_DIR}/env-keys.txt"
GENERATED_ENV_FILE="${ROOT_DIR}/.env.generated.run"
WEB_INDEX_FILE="${ROOT_DIR}/web/index.html"
WEB_INDEX_BACKUP="${ROOT_DIR}/web/index.html.codex.bak"
WEB_MAPS_PLACEHOLDER="YOUR_GOOGLE_MAPS_WEB_API_KEY"
DEVICE="${1:-chrome}"

declare -A ENV_VALUES=()
declare -a ENV_KEYS=()

trim() {
  printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

strip_matching_quotes() {
  local value="$1"
  if [[ "${value}" == \"*\" && "${value}" == *\" ]]; then
    value="${value:1:${#value}-2}"
  elif [[ "${value}" == \'*\' && "${value}" == *\' ]]; then
    value="${value:1:${#value}-2}"
  fi
  printf '%s' "${value}"
}

load_env_keys() {
  while IFS= read -r raw_key || [[ -n "${raw_key}" ]]; do
    local key
    key="$(trim "${raw_key%$'\r'}")"
    if [[ -z "${key}" || "${key}" == \#* ]]; then
      continue
    fi
    ENV_KEYS+=("${key}")
  done < "${ENV_KEYS_FILE}"
}

load_env_file() {
  local file_path="$1"
  [[ -f "${file_path}" ]] || return 0

  while IFS= read -r raw_line || [[ -n "${raw_line}" ]]; do
    local line key value
    line="${raw_line%$'\r'}"
    line="$(trim "${line}")"
    if [[ -z "${line}" || "${line}" == \#* || "${line}" != *=* ]]; then
      continue
    fi

    key="$(trim "${line%%=*}")"
    value="${line#*=}"
    value="$(strip_matching_quotes "${value}")"
    ENV_VALUES["${key}"]="${value}"
  done < "${file_path}"
}

write_generated_env_file() {
  : > "${GENERATED_ENV_FILE}"
  for key in "${ENV_KEYS[@]}"; do
    if [[ -v ENV_VALUES["${key}"] ]]; then
      printf '%s=%s\n' "${key}" "${ENV_VALUES[${key}]}" >> "${GENERATED_ENV_FILE}"
    fi
  done
}

require_non_placeholder() {
  local key="$1"
  local value="${ENV_VALUES[${key}]:-}"
  local placeholder="$2"

  if [[ -z "${value}" || "${value}" == "${placeholder}" ]]; then
    echo "Missing required value for ${key}" >&2
    exit 1
  fi
}

cleanup() {
  rm -f "${GENERATED_ENV_FILE}"
  if [[ -f "${WEB_INDEX_BACKUP}" ]]; then
    mv "${WEB_INDEX_BACKUP}" "${WEB_INDEX_FILE}"
  fi
}

trap cleanup EXIT

load_env_keys
load_env_file "${ROOT_DIR}/.env"

for key in "${ENV_KEYS[@]}"; do
  if [[ -n "${!key-}" ]]; then
    ENV_VALUES["${key}"]="${!key}"
  fi
done

require_non_placeholder "SUPABASE_URL" "https://YOUR_PROJECT.supabase.co"
require_non_placeholder "SUPABASE_ANON_KEY" "YOUR_ANON_KEY"

write_generated_env_file

cp "${WEB_INDEX_FILE}" "${WEB_INDEX_BACKUP}"
WEB_MAPS_KEY="${ENV_VALUES[GOOGLE_MAPS_WEB_API_KEY]:-}"
if [[ "${WEB_MAPS_KEY}" == "${WEB_MAPS_PLACEHOLDER}" ]]; then
  WEB_MAPS_KEY=""
fi
if [[ -z "${WEB_MAPS_KEY}" ]]; then
  echo "Warning: GOOGLE_MAPS_WEB_API_KEY is empty; web map features will stay disabled until it is set." >&2
fi
sed "s|${WEB_MAPS_PLACEHOLDER}|${WEB_MAPS_KEY}|g" "${WEB_INDEX_BACKUP}" > "${WEB_INDEX_FILE}"

cd "${ROOT_DIR}"
flutter run -d "${DEVICE}" --dart-define-from-file="${GENERATED_ENV_FILE}"
