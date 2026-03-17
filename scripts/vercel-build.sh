#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_KEYS_FILE="${SCRIPT_DIR}/env-keys.txt"
FLUTTER_VERSION_FILE="${SCRIPT_DIR}/flutter-version.txt"
GENERATED_ENV_FILE="${ROOT_DIR}/.env.generated.build"
WEB_INDEX_FILE="${ROOT_DIR}/web/index.html"
WEB_INDEX_BACKUP="${ROOT_DIR}/web/index.html.codex.bak"
WEB_MAPS_PLACEHOLDER="YOUR_GOOGLE_MAPS_WEB_API_KEY"
FLUTTER_BIN=""

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

read_first_non_comment_line() {
  local file_path="$1"
  [[ -f "${file_path}" ]] || return 1

  while IFS= read -r raw_line || [[ -n "${raw_line}" ]]; do
    local line
    line="$(trim "${raw_line%$'\r'}")"
    if [[ -z "${line}" || "${line}" == \#* ]]; then
      continue
    fi
    printf '%s' "${line}"
    return 0
  done < "${file_path}"

  return 1
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

write_build_env_file() {
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

resolve_flutter_version() {
  if [[ -n "${FLUTTER_VERSION:-}" ]]; then
    printf '%s' "${FLUTTER_VERSION}"
    return 0
  fi

  if read_first_non_comment_line "${FLUTTER_VERSION_FILE}" >/dev/null 2>&1; then
    read_first_non_comment_line "${FLUTTER_VERSION_FILE}"
    return 0
  fi

  # Keep a safe fallback in case the version file is missing in CI.
  printf '%s' "3.41.2"
}

ensure_flutter() {
  if command -v flutter >/dev/null 2>&1; then
    FLUTTER_BIN="$(command -v flutter)"
    return 0
  fi

  if [[ "$(uname -s)" != "Linux" ]]; then
    echo "flutter is not on PATH, and automatic Flutter bootstrap is only supported on Linux build environments." >&2
    echo "Install Flutter locally or set FLUTTER_VERSION and run this script on Linux/Vercel." >&2
    exit 1
  fi

  if ! command -v curl >/dev/null 2>&1; then
    echo "curl is required to download Flutter in CI." >&2
    exit 1
  fi

  if ! command -v tar >/dev/null 2>&1; then
    echo "tar is required to extract the Flutter SDK in CI." >&2
    exit 1
  fi

  local flutter_version flutter_cache_root flutter_sdk_dir archive_name download_url temp_dir archive_path
  flutter_version="$(resolve_flutter_version)"
  flutter_cache_root="${XDG_CACHE_HOME:-${HOME:-${ROOT_DIR}}/.cache}/marketflow"
  flutter_sdk_dir="${flutter_cache_root}/flutter-${flutter_version}"

  if [[ -x "${flutter_sdk_dir}/bin/flutter" ]]; then
    FLUTTER_BIN="${flutter_sdk_dir}/bin/flutter"
    return 0
  fi

  archive_name="flutter_linux_${flutter_version}-stable.tar.xz"
  download_url="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/${archive_name}"
  temp_dir="$(mktemp -d)"
  archive_path="${temp_dir}/${archive_name}"

  echo "flutter not found on PATH; downloading Flutter ${flutter_version} for the Vercel build." >&2
  curl -fsSL --retry 3 --retry-delay 2 "${download_url}" -o "${archive_path}"

  mkdir -p "${flutter_cache_root}"
  rm -rf "${flutter_sdk_dir}"
  tar -xf "${archive_path}" -C "${temp_dir}"
  mv "${temp_dir}/flutter" "${flutter_sdk_dir}"
  rm -rf "${temp_dir}"

  FLUTTER_BIN="${flutter_sdk_dir}/bin/flutter"
}

configure_flutter_git_safety() {
  local flutter_sdk_dir

  if [[ -z "${FLUTTER_BIN}" ]]; then
    return 0
  fi

  if ! command -v git >/dev/null 2>&1; then
    return 0
  fi

  flutter_sdk_dir="$(cd "$(dirname "${FLUTTER_BIN}")/.." && pwd)"
  git config --global --add safe.directory "${flutter_sdk_dir}" >/dev/null 2>&1 || true
}

cleanup() {
  rm -f "${GENERATED_ENV_FILE}"
  if [[ -f "${WEB_INDEX_BACKUP}" ]]; then
    mv "${WEB_INDEX_BACKUP}" "${WEB_INDEX_FILE}"
  fi
}

trap cleanup EXIT

if [[ ! -f "${ENV_KEYS_FILE}" ]]; then
  echo "Missing ${ENV_KEYS_FILE}" >&2
  exit 1
fi

load_env_keys
load_env_file "${ROOT_DIR}/.env"

for key in "${ENV_KEYS[@]}"; do
  if [[ -n "${!key-}" ]]; then
    ENV_VALUES["${key}"]="${!key}"
  fi
done

require_non_placeholder "SUPABASE_URL" "https://YOUR_PROJECT.supabase.co"
require_non_placeholder "SUPABASE_ANON_KEY" "YOUR_ANON_KEY"

ensure_flutter
configure_flutter_git_safety

write_build_env_file

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
"${FLUTTER_BIN}" config --enable-web
"${FLUTTER_BIN}" pub get
"${FLUTTER_BIN}" build web --dart-define-from-file="${GENERATED_ENV_FILE}"
