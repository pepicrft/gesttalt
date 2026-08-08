if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
  SCRIPT_PATH="${BASH_SOURCE[0]}"
elif [[ -n "${ZSH_VERSION:-}" ]]; then
  SCRIPT_PATH="${(%):-%x}"
else
  SCRIPT_PATH="${0}"
fi

SCRIPT_DIR="$(cd "$(dirname "${SCRIPT_PATH}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ROOT_INSTANCE_FILE="${PROJECT_ROOT}/.gesttalt-dev-instance"

resolve_git_path() {
  local target_name="$1"
  local fallback_path="$2"
  local git_path=""

  if command -v git >/dev/null 2>&1 &&
    git -C "${PROJECT_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git_path="$({
      git -C "${PROJECT_ROOT}" rev-parse --path-format=absolute --git-path "${target_name}" 2>/dev/null ||
        git -C "${PROJECT_ROOT}" rev-parse --git-path "${target_name}" 2>/dev/null ||
        true
    })"

    if [[ -n "${git_path}" && "${git_path}" != /* ]]; then
      git_path="${PROJECT_ROOT}/${git_path#./}"
    fi
  fi

  if [[ -n "${git_path}" ]]; then
    printf '%s' "${git_path}"
  else
    printf '%s' "${fallback_path}"
  fi
}

INSTANCE_FILE="$(resolve_git_path "gesttalt-dev-instance" "${ROOT_INSTANCE_FILE}")"

validate_suffix() {
  local suffix="$1"

  [[ "${suffix}" =~ ^[0-9]+$ ]] || return 1
  ((suffix >= 1 && suffix <= 999))
}

persist_suffix() {
  local suffix="$1"
  local target="$2"

  mkdir -p "$(dirname "${target}")" 2>/dev/null || return 1
  printf '%s' "${suffix}" | tee "${target}" >/dev/null 2>&1
}

collect_used_suffixes() {
  local common_dir="" file

  if command -v git >/dev/null 2>&1 &&
    git -C "${PROJECT_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    common_dir="$(
      git -C "${PROJECT_ROOT}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null ||
        true
    )"
  fi

  [[ -n "${common_dir}" && -d "${common_dir}" ]] || return 0

  for file in "${common_dir}/gesttalt-dev-instance" "${common_dir}"/worktrees/*/gesttalt-dev-instance; do
    [[ -s "${file}" ]] || continue
    [[ "${file}" -ef "${INSTANCE_FILE}" ]] 2>/dev/null && continue
    tr -d '[:space:]' < "${file}"
    printf '\n'
  done
}

generate_suffix() {
  local used
  used="$(collect_used_suffixes | tr '\n' ' ')"

  awk -v used="${used}" -v seed="$$" '
    BEGIN {
      srand(seed)
      n = split(used, list, " ")
      for (i = 1; i <= n; i++) taken[list[i]] = 1
      for (attempt = 0; attempt < 100000; attempt++) {
        candidate = int(100 + rand() * 900)
        if (!(candidate in taken)) { print candidate; exit 0 }
      }
      exit 1
    }
  '
}

ensure_suffix() {
  local suffix=""

  if [[ -s "${INSTANCE_FILE}" ]]; then
    suffix="$(tr -d '[:space:]' < "${INSTANCE_FILE}")"
  elif [[ -n "${GESTTALT_DEV_INSTANCE:-}" ]] &&
    { [[ "${GESTTALT_DEV_INSTANCE_ROOT:-}" == "${PROJECT_ROOT}" ]] ||
      [[ -z "${GESTTALT_DEV_INSTANCE_ROOT:-}" ]]; }; then
    suffix="${GESTTALT_DEV_INSTANCE}"
  elif [[ -s "${ROOT_INSTANCE_FILE}" ]]; then
    suffix="$(tr -d '[:space:]' < "${ROOT_INSTANCE_FILE}")"
  else
    suffix="$(generate_suffix)"
  fi

  validate_suffix "${suffix}" || {
    echo "Invalid Gesttalt development instance suffix '${suffix}'. Expected an integer between 1 and 999." >&2
    return 1
  }

  if ! persist_suffix "${suffix}" "${INSTANCE_FILE}"; then
    if [[ "${INSTANCE_FILE}" != "${ROOT_INSTANCE_FILE}" ]] &&
      persist_suffix "${suffix}" "${ROOT_INSTANCE_FILE}"; then
      INSTANCE_FILE="${ROOT_INSTANCE_FILE}"
    else
      echo "Failed to persist Gesttalt development instance suffix '${suffix}'." >&2
      return 1
    fi
  fi

  printf '%s' "${suffix}"
}

suffix="$(ensure_suffix)"
test_partition="${MIX_TEST_PARTITION:-}"
project_basename="$(basename "${PROJECT_ROOT}")"
project_hostname="$(
  printf '%s' "${project_basename}" |
    tr '[:upper:]' '[:lower:]' |
    sed 's/[^a-z0-9-]/-/g; s/^-*//; s/-*$//'
)"

export GESTTALT_DEV_INSTANCE="${suffix}"
export GESTTALT_DEV_INSTANCE_ROOT="${PROJECT_ROOT}"
export GESTTALT_PORT="$((4000 + suffix))"
export GESTTALT_HOSTNAME="${project_hostname}.localhost"
export GESTTALT_PLATFORM_HOST="${GESTTALT_HOSTNAME}"
export GESTTALT_URL="http://${GESTTALT_HOSTNAME}:${GESTTALT_PORT}"
export GESTTALT_DEMO_URL="http://demo.${GESTTALT_HOSTNAME}:${GESTTALT_PORT}"
export GESTTALT_DATABASE_NAME="gesttalt_dev_${suffix}"
export GESTTALT_THEME_PORT="$((5000 + suffix))"
export GESTTALT_TEST_PORT="$((6000 + suffix))"
export GESTTALT_TEST_DATABASE_NAME="gesttalt_test${test_partition}_${suffix}"
