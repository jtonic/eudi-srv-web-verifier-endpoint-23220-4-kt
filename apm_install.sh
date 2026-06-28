#!/usr/bin/env bash
set -euo pipefail

PROFILES_DIR="$(dirname "$0")/companion/apm/profiles"
ARG1="${1:-}"

if [[ "${ARG1}" == "--profiles" ]]; then
  find "${PROFILES_DIR}" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort
  exit 0
fi

PROFILE="${ARG1:-empty}"
PROFILE_DIR="${PROFILES_DIR}/${PROFILE}"

if [[ ! -d "${PROFILE_DIR}" ]]; then
  echo "Profile '${PROFILE}' not found in ${PROFILES_DIR}" >&2
  exit 1
fi

if [[ ! -f "${PROFILE_DIR}/apm.yml" ]]; then
  echo "apm.yml not found in ${PROFILE_DIR}" >&2
  exit 1
fi

cp "${PROFILE_DIR}/apm.yml" ./apm.yml

apm install
apm prune

cp ./apm.lock.yaml "${PROFILE_DIR}/apm_lock.yaml"
rm ./apm.yml
