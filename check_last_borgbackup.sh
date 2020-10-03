#!/usr/bin/env bash

. /usr/lib/borg-backup-lib.sh


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
            log error "Invalid argument: ${1}"
            exit ${EXIT_ICINGA_UNKNOWN}
            ;;
    esac
    shift 2
done



FILE="/etc/borg-backup-script/${CONFIG}_monitoring"

if [ -f "${FILE}" ]; then
	. ${FILE}
else
	log "ERROR" "No such file: ${FILE}"
	exit ${EXIT_ICINGA_UNKNOWN}
fi

last_backup_monitoring "${REPO}" ${WARN_TIME} ${ERROR_TIME}



