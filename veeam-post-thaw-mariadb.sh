#!/usr/bin/env bash

#version=1.0.0

set -u
set -o pipefail

###############################################################################
# STATIC CONFIG
###############################################################################

SCRIPT_NAME="veeam-post-thaw-mariadb"
CONFIG_FILE="/opt/veeam-hooks/config/veeam-mariadb-backup.conf"
FSFREEZE_BIN="/sbin/fsfreeze"

###############################################################################
# LOGGING
###############################################################################

log() {
    local msg="$*"
    printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${SCRIPT_NAME}" "${msg}"
    logger -t "${SCRIPT_NAME}" "${msg}"
}

fail() {
    local msg="$*"
    printf '%s [%s] ERROR: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${SCRIPT_NAME}" "${msg}"
    logger -p user.err -t "${SCRIPT_NAME}" "ERROR: ${msg}"
    exit 1
}

###############################################################################
# HELPERS
###############################################################################

load_config() {
    [[ -f "${CONFIG_FILE}" ]] || fail "Config file not found: ${CONFIG_FILE}"

    # shellcheck disable=SC1090
    source "${CONFIG_FILE}"

    [[ -n "${STATE_DIR:-}" ]] || fail "STATE_DIR is not set"

    LOCK_FILE="${STATE_DIR}/backup_in_progress.lock"
    FREEZE_STATE_FILE="${STATE_DIR}/fs_frozen.state"

    mkdir -p "${STATE_DIR}"
}

###############################################################################
# START
###############################################################################

load_config

log "===== POST-THAW SCRIPT START ====="

if [[ -f "${FREEZE_STATE_FILE}" ]]; then
    FREEZE_MOUNT="$(cat "${FREEZE_STATE_FILE}")"

    if [[ -n "${FREEZE_MOUNT}" ]]; then
        [[ -x "${FSFREEZE_BIN}" ]] || fail "fsfreeze binary not found: ${FSFREEZE_BIN}"
        log "Unfreezing filesystem mount: ${FREEZE_MOUNT}"
        "${FSFREEZE_BIN}" --unfreeze "${FREEZE_MOUNT}" || fail "Failed to unfreeze mount ${FREEZE_MOUNT}"
        rm -f "${FREEZE_STATE_FILE}"
        log "Filesystem unfrozen successfully: ${FREEZE_MOUNT}"
    else
        log "Freeze state file exists but mount value is empty. Removing state file."
        rm -f "${FREEZE_STATE_FILE}"
    fi
else
    log "No freeze state file found. Nothing to unfreeze."
fi

if [[ -f "${LOCK_FILE}" ]]; then
    rm -f "${LOCK_FILE}"
    log "Removed stale lock file: ${LOCK_FILE}"
fi

log "Post-thaw completed successfully."
log "===== POST-THAW SCRIPT END ====="

exit 0
