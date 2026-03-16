#!/usr/bin/env bash

#version=1.0.0

set -u
set -o pipefail

###############################################################################
# STATIC CONFIG
###############################################################################

SCRIPT_NAME="veeam-pre-freeze-mariadb"
TIMESTAMP="$(date '+%Y-%m-%d_%H-%M-%S')"
CONFIG_FILE="/opt/veeam-hooks/config/veeam-mariadb-backup.conf"

DOCKER_BIN="/usr/bin/docker"
MARIADB_DUMP_BIN="/usr/bin/mariadb-dump"
MYSQLDUMP_BIN="/usr/bin/mysqldump"
GZIP_BIN="/usr/bin/gzip"
GZIP_TEST_BIN="/usr/bin/gzip"
GREP_BIN="/usr/bin/grep"
ZGREP_BIN="/usr/bin/zgrep"
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

check_binary() {
    local bin_path="$1"
    [[ -x "${bin_path}" ]] || fail "Required binary not found or not executable: ${bin_path}"
}

load_config() {
    [[ -f "${CONFIG_FILE}" ]] || fail "Config file not found: ${CONFIG_FILE}"

    # shellcheck disable=SC1090
    source "${CONFIG_FILE}"

    [[ -n "${DB_CONTAINER_NAME:-}" ]] || fail "DB_CONTAINER_NAME is not set"
    [[ -n "${DB_NAME:-}" ]] || fail "DB_NAME is not set"
    [[ -n "${DB_USER:-}" ]] || fail "DB_USER is not set"
    [[ -n "${DB_PASSWORD_FILE:-}" ]] || fail "DB_PASSWORD_FILE is not set"
    [[ -n "${BACKUP_DIR:-}" ]] || fail "BACKUP_DIR is not set"
    [[ -n "${STATE_DIR:-}" ]] || fail "STATE_DIR is not set"
    [[ -n "${RETENTION_DAYS:-}" ]] || fail "RETENTION_DAYS is not set"
    [[ -n "${COMPRESS_DUMP:-}" ]] || fail "COMPRESS_DUMP is not set"

    [[ -f "${DB_PASSWORD_FILE}" ]] || fail "Password file not found: ${DB_PASSWORD_FILE}"

    DB_PASSWORD="$(< "${DB_PASSWORD_FILE}")"
    [[ -n "${DB_PASSWORD}" ]] || fail "Password file is empty: ${DB_PASSWORD_FILE}"

    LOCK_FILE="${STATE_DIR}/backup_in_progress.lock"
    FREEZE_STATE_FILE="${STATE_DIR}/fs_frozen.state"
    DUMP_BASENAME="mariadb_dump_${TIMESTAMP}.sql"
    DUMP_FILE="${BACKUP_DIR}/${DUMP_BASENAME}"
    COMPRESSED_DUMP_FILE="${DUMP_FILE}.gz"
    LATEST_DUMP_LINK="${STATE_DIR}/latest_mariadb_dump"

    mkdir -p "${STATE_DIR}" "${BACKUP_DIR}"
}

detect_dump_command() {
    if "${DOCKER_BIN}" exec "${DB_CONTAINER_NAME}" test -x "${MARIADB_DUMP_BIN}"; then
        echo "${MARIADB_DUMP_BIN}"
        return 0
    fi

    if "${DOCKER_BIN}" exec "${DB_CONTAINER_NAME}" test -x "${MYSQLDUMP_BIN}"; then
        echo "${MYSQLDUMP_BIN}"
        return 0
    fi

    return 1
}

validate_dump_file() {
    local file_path="$1"
    local search_bin=""

    [[ -f "${file_path}" ]] || fail "Dump file does not exist: ${file_path}"
    [[ -s "${file_path}" ]] || fail "Dump file is empty: ${file_path}"

    if [[ "${file_path}" == *.gz ]]; then
        search_bin="${ZGREP_BIN}"
	log "Your dump is compressed (.gz) as configured in ${CONFIG_FILE}"
    else
        search_bin="${GREP_BIN}"
	log "Your dump is NOT compressed. Consider compressing for less disk usage. Configure in ${CONFIG_FILE}"
    fi

    if ! "${search_bin}" -qE '^CREATE DATABASE|^USE `|^CREATE TABLE|^INSERT INTO `|^DROP TABLE IF EXISTS' "${file_path}"; then
        fail "Dump validation failed. No expected SQL markers found in ${file_path}"
    fi

    if ! "${search_bin}" -q "CREATE DATABASE.*\`${DB_NAME}\`" "${file_path}" && \
       ! "${search_bin}" -q "USE \`${DB_NAME}\`;" "${file_path}"; then
        fail "Dump validation failed. Database name ${DB_NAME} not found in ${file_path}"
    fi

    log "Dump validation succeeded for ${file_path}"
}

cleanup_on_error() {
    log "Cleanup after error started."

    if [[ -f "${FREEZE_STATE_FILE:-}" ]] && [[ -n "${FREEZE_MOUNT:-}" ]]; then
        log "Attempting emergency unfreeze for mount ${FREEZE_MOUNT}."
        "${FSFREEZE_BIN}" --unfreeze "${FREEZE_MOUNT}" >/dev/null 2>&1 || true
        rm -f "${FREEZE_STATE_FILE}"
    fi

    rm -f "${LOCK_FILE:-}"

    # remove partial dump files if they exist
    rm -f "${DUMP_FILE:-}" "${COMPRESSED_DUMP_FILE:-}"

    log "Cleanup after error finished."
}

trap cleanup_on_error EXIT

###############################################################################
# START
###############################################################################

load_config

log "===== PRE-FREEZE SCRIPT START ====="

check_binary "${DOCKER_BIN}"
check_binary "${GZIP_BIN}"
check_binary "${GZIP_TEST_BIN}"
check_binary "${GREP_BIN}"
check_binary "${ZGREP_BIN}"

if [[ -n "${FREEZE_MOUNT}" ]]; then
    check_binary "${FSFREEZE_BIN}"
fi

if [[ -f "${LOCK_FILE}" ]]; then
    fail "Lock file exists: ${LOCK_FILE}. Previous run may still be active."
fi

touch "${LOCK_FILE}"
log "Created lock file: ${LOCK_FILE}"

"${DOCKER_BIN}" inspect "${DB_CONTAINER_NAME}" >/dev/null 2>&1 || fail "Docker container not found: ${DB_CONTAINER_NAME}"

DUMP_CMD="$(detect_dump_command)" || fail "Neither mariadb-dump nor mysqldump found in container ${DB_CONTAINER_NAME}."
log "Using dump command inside container: ${DUMP_CMD}"

log "Creating MariaDB dump from container '${DB_CONTAINER_NAME}', database '${DB_NAME}'."

if [[ "${COMPRESS_DUMP}" == "yes" ]]; then
    "${DOCKER_BIN}" exec \
        -e MYSQL_PWD="${DB_PASSWORD}" \
        "${DB_CONTAINER_NAME}" \
        "${DUMP_CMD}" \
        --user="${DB_USER}" \
        --databases "${DB_NAME}" \
        --single-transaction \
        --quick \
        --routines \
        --events \
        --triggers \
        --add-drop-table \
        --add-drop-database \
        --default-character-set=utf8mb4 \
        | "${GZIP_BIN}" -c > "${COMPRESSED_DUMP_FILE}" || fail "MariaDB dump with compression failed."

    "${GZIP_TEST_BIN}" -t "${COMPRESSED_DUMP_FILE}" || fail "gzip integrity test failed for ${COMPRESSED_DUMP_FILE}"
    validate_dump_file "${COMPRESSED_DUMP_FILE}"

    ln -sfn "${COMPRESSED_DUMP_FILE}" "${LATEST_DUMP_LINK}" || fail "Failed to update latest dump symlink."
    log "Updated latest dump symlink: ${LATEST_DUMP_LINK} -> ${COMPRESSED_DUMP_FILE}"
else
    "${DOCKER_BIN}" exec \
        -e MYSQL_PWD="${DB_PASSWORD}" \
        "${DB_CONTAINER_NAME}" \
        "${DUMP_CMD}" \
        --user="${DB_USER}" \
        --databases "${DB_NAME}" \
        --single-transaction \
        --quick \
        --routines \
        --events \
        --triggers \
        --add-drop-table \
        --add-drop-database \
        --default-character-set=utf8mb4 \
        > "${DUMP_FILE}" || fail "MariaDB dump failed."

    validate_dump_file "${DUMP_FILE}"

    ln -sfn "${DUMP_FILE}" "${LATEST_DUMP_LINK}" || fail "Failed to update latest dump symlink."
    log "Updated latest dump symlink: ${LATEST_DUMP_LINK} -> ${DUMP_FILE}"
fi

log "Running sync."
sync

if [[ -n "${FREEZE_MOUNT}" ]]; then
    log "Freezing filesystem mount: ${FREEZE_MOUNT}"
    "${FSFREEZE_BIN}" --freeze "${FREEZE_MOUNT}" || fail "fsfreeze failed for mount ${FREEZE_MOUNT}"
    echo "${FREEZE_MOUNT}" > "${FREEZE_STATE_FILE}" || fail "Failed to write freeze state file."
    log "Filesystem frozen successfully: ${FREEZE_MOUNT}"
else
    log "Filesystem freeze disabled."
fi

if [[ "${RETENTION_DAYS}" != "0" ]]; then
    log "Applying retention: deleting dumps older than ${RETENTION_DAYS} days."
    find "${BACKUP_DIR}" -maxdepth 1 -type f \( -name '*.sql' -o -name '*.sql.gz' \) -mtime +"${RETENTION_DAYS}" -print -delete || true
fi

rm -f "${LOCK_FILE}"
trap - EXIT

log "Pre-freeze completed successfully."
log "===== PRE-FREEZE SCRIPT END ====="

exit 0
