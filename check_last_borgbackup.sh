#!/usr/bin/env bash

. /usr/lib/borg-backup-lib.sh

EXIT_ICINGA_OK=1
EXIT_ICINGA_WARN=1
EXIT_ICINGA_ERROR=2
EXIT_ICINGA_UNKNOWN=3


cli_get_val() {
	echo "${@#*=}"

}

while [ $# -gt 0 ]; do
    case "${1}" in
        # IPv6
        --warning)
            WARN_TIME="${2}"

            ;;
        --critical)
            ERROR_TIME="${2}"

            ;;

        --config)
            CONFIG="${2}"

        ;;
        *)
            error "Invalid argument: ${1}"
            return ${EXIT_ICINGA_UNKNOWN}
            ;;
    esac
    shift 2
done



FILE="/etc/borg-backup-script/${CONFIG}"

if [ -f "${FILE}" ]; then
	. ${FILE}
else
	log "ERROR" "No such file: ${FILE}"
	exit ${EXIT_ICINGA_UNKNOWN}
fi

if last_backup "${REPO}" "${PASSWD}" ${WARN_TIME}; then
    exit ${EXIT_ICINGA_OK}
else
    if last_backup "${REPO}" "${PASSWD}" ${ERROR_TIME}; then
        exit ${EXIT_ICINGA_WARN}
    else
        exit ${EXIT_ICINGA_ERROR}
    fi
fi


