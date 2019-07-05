#!/bin/bash

EXIT_OK=0
EXIT_ERROR=1
EXIT_TRUE=0
EXIT_FALSE=1

LOCK_DIR="/var/borg/lock_dir"

format_date() {
	date "+%Y-%m-%d %H:%M:%S"
}


create_lock_file_from_repo() {
	local repo=${1}

	echo ${repo//\//.}
}

acquire_lock() {
	local repo=${1}


	if ! break_lock  "${repo}"; then
		log INFO "Cannot acquire lock for: ${repo} Repo is already locked."
		return ${EXIT_ERROR}
	fi

	log DEBUG "Acquiring lock for ${repo}"
	touch "${LOCK_DIR}/$(create_lock_file_from_repo "${repo}")"

	return ${EXIT_OK}
}

release_lock() {
	local repo=${1}

	if ! check_for_lock "${repo}"; then
		log ERROR "Cannot release lock for: ${repo} Repo is not locked"
		return ${EXIT_ERROR}
	fi

	log DEBUG "Release lock for: ${repo}"

	cmd rm -f "${LOCK_DIR}/$(create_lock_file_from_repo "${repo}")"
}

check_for_lock() {
	local repo=${1}

	if [ -f "${LOCK_DIR}/$(create_lock_file_from_repo "${repo}")" ]; then
		return ${EXIT_TRUE}
	fi

	return ${EXIT_FALSE}
}

break_lock() {
	local repo=${1}

	local lock_file="${LOCK_DIR}/$(create_lock_file_from_repo "${repo}")"

	if [ -f "${lock_file}" ]; then
		# Check if the lock exist more then 12h
		local lock_file_date=$(cmd stat -c %Y "${lock_file}")
		local now_date=$(get_timestamp_from_date "$(format_date)")

		local diff_date=$(( ${now_date} - ${lock_file_date} ))

		if [ ${diff_date} -lt 43200 ]; then
			log DEBUG "The lock was created before $(format_time_from_timestamp ${diff_date}) "
			return ${EXIT_FALSE}
		else
			log ERROR "The lock was created before $(format_time_from_timestamp ${diff_date}), BREAKING LOCK"
			release_lock "${repo}"
			return ${EXIT_TRUE}
		fi
	fi

	return ${EXIT_TRUE}
}

log() {
	local type=${1}
	shift

	local message="$@"

	local date="$(format_date)"

	echo "${date} [${type}] ${message}" >> "/var/log/borg-$(date "+%Y-%m-%d")"

	if [[ ${type} != "DEBUG" ]]; then
		>&2 echo "${date} [${type}] ${message}"
	fi
}


log_backup() {
	local type=${1}
	local repo=${2}
	shift 2

	local message="$@"

	log "${type}" "[${repo}] ${message}"
}

cmd() {
	log DEBUG "Executing command: $@"

	"$@"
}

create_backup_computer() {
	local repo="${1}"
	local passwd="${2}"
	local compression="${3}"
	local exclude="${4}"
	local time_between="${5}"

	shift 5
	local paths="$@"

	create_backup "${repo}" "${passwd}" "${compression}" "--exclude-from ${exclude}" "${time_between}" "$@"
}

create_backup_server() {
	local repo="${1}"
	local passwd="${2}"
	local compression="${3}"

	shift 3
	local paths="$@"

	create_backup "${repo}" "${passwd}" "${compression}" "" "" "$@"
}

create_backup() {
	local repo="${1}"
	local passwd="${2}"
	local compression="${3}"
	local cmd_args="${4}"
	local time_between="${5}"

	shift 5
	local paths="$@"

	export BORG_PASSPHRASE="${passwd}"

	if ! [[ ${time_between} = "" ]]; then
		log DEBUG "Checking if we need to create a backup"
		if last_backup "${repo}" "${passwd}" ${time_between}; then
			return ${EXIT_OK}
		fi
	fi

	# Now we go to change the repo and therefore we need to lock it
	while ! acquire_lock "${repo}"; do
		sleep 300
	done

	tag="$(format_date)"

	local path
	for path in ${paths}; do
		if [ -d "${path}" ]; then
			echo "${tag}" > "${path}/check-borg-backup"
		fi
	done


	log DEBUG "Additional cmd args: ${cmd_args}"
	if ! cmd /usr/bin/borg create ${cmd_args} --verbose --stats -C "${compression}"  "${repo}::${tag}" ${paths}; then
		log_backup "ERROR" "${repo}" "Could not create backup"
		release_lock "${repo}"
		return ${EXIT_ERROR}
	else
		log_backup "INFO" "${repo}" "Successfully created backup"
		release_lock "${repo}"
		return ${EXIT_OK}
	fi
}


list_backups() {
	local repo="${1}"
	local passwd="${2}"


	export BORG_PASSPHRASE="${passwd}"

	while ! acquire_lock "${repo}"; do
		sleep 300
	done

	if ! cmd /usr/bin/borg list "${repo}"; then
		log_backup ERROR "${repo}" "Could not list archives"
		release_lock "${repo}"
		return ${EXIT_ERROR}
	else
		release_lock "${repo}"
		return ${EXIT_OK}
	fi
}

get_timestamp_from_date() {
	local date="${1}"

	date -d "${date}" +%s
}

format_time_from_timestamp() {
	local timestamp=${1}
	local rest
	local string
	local unit_value

	rest=${timestamp}

	local units="d h m s"

	for unit in ${units}; do
		case ${unit} in
			"d")
				unit_value=$(( ${rest} / 86400 ))
				rest=$(( ${rest} % 86400 ))
				string="${string} ${unit_value}${unit}"
			;;
			"h")
				unit_value=$(( ${rest} / 3600 ))
				rest=$(( ${rest} % 3600 ))
				string="${string} ${unit_value}${unit}"
			;;
			"m")
				unit_value=$(( ${rest} / 60 ))
				rest=$(( ${rest} % 60 ))
				string="${string} ${unit_value}${unit}"
			;;
			"s")
				string="${string} ${rest}${unit}"
			;;


		esac
	done

	echo "${string}"
}

last_backup() {
	local repo="${1}"
	local passwd="${2}"
	local time=${3}
	shift 2

	local tmp
	local tag
	local line
	local backup

	local tag_date
	local now_date
	local diff_date

	local tmp_backup_list=$(mktemp)


	export BORG_PASSPHRASE="${passwd}"

	shopt -s extglob

	if [[ ${time} = "" ]]; then
		log ERROR "Get no time value which should be between the backups"
		return ${EXIT_ERROR}
	fi

	while ! acquire_lock "${repo}"; do
		sleep 300
	done

	cmd /usr/bin/borg list ${repo} > "${tmp_backup_list}"

	release_lock "${repo}"

	while read backup; do
		line="${backup}"
	done < ${tmp_backup_list}

	rm -f  "${tmp_backup_list}"



	# get tag
	tmp=${line}
	log_backup "DEBUG" "${repo}"  "Last backup line is:'${tmp}'"

	tmp=${tmp%\[*\]}
	tmp=${tmp%+([[:space:]])}
	tmp=${tmp%%???, ????-??-?? ??:??:??}
	tmp=${tmp%%+([[:space:]])}


	tag=${tmp}

	log_backup "INFO" "${repo}"  "Last backup tag is:'${tag}'"

	tag_date=$(get_timestamp_from_date "${tag}")
	now_date=$(get_timestamp_from_date "$(format_date)")

	diff_date=$(( ${now_date} - ${tag_date}))

	if [ ${diff_date} -lt ${time} ]; then
		log INFO "The last backup was before $(format_time_from_timestamp ${diff_date})"
		return ${EXIT_OK}
	else
		log ERROR "The last backup was before $(format_time_from_timestamp ${diff_date})"
		return ${EXIT_ERROR}
	fi

}

prune_backup() {
	local repo="${1}"
	local passwd="${2}"

	local BORG_PASSPHRASE="${passwd}"

	/usr/bin/borg prune -v "${repo}" --keep-daily=7 --keep-weekly=4 --keep-monthly=6
}

md5sum_get_sum() {
	local file=${1}

	if [ -f "${file}" ]; then
		local tmp="$(md5sum "${file}")"
		echo "${tmp:0:32}"
	fi
}

check_repo() {
	local repo="${1}"
	local passwd="${2}"
	shift 2
	local paths="$@"

	local tag

	local tmp_backup_list=$(mktemp)

	export BORG_PASSPHRASE="${passwd}"

	shopt -s extglob

	# Load the fuse module

	while ! acquire_lock "${repo}"; do
		sleep 300
	done

	# cmd crashes here because  the redirect
	cmd /usr/bin/borg list "${repo}" > "${tmp_backup_list}"

	release_lock "${repo}"

	while read backup; do
		# get tag
		tmp=${backup%%???, ????-??-?? ??:??:??}
		tag=${tmp%%+([[:space:]])}

		check_backup "${repo}" "${passwd}" "${tag}" ${paths}
	done < ${tmp_backup_list}

}

check_backup() {
	local repo="${1}"
	local passwd="${2}"
	local tag="${3}"
	shift 3
	local paths="$@"

	local tmp_dir=$(mktemp -d /var/tmp/XXXXXXXXXXXXXXXXXXX)
	local tmp_file=$(mktemp /var/tmp/XXXXXXXXXXXXXXXXXXX)
	local return_value=${EXIT_OK}
	local path

	# Export the password in this shell
	export BORG_PASSPHRASE="${passwd}"

	# Load the fuse module
	cmd modprobe fuse

	while ! acquire_lock "${repo}"; do
		sleep 300
	done

	log_backup "INFO" "${repo}"  "Check backup '${tag}'"

	echo "${tag}" > "${tmp_file}"

	# mount backup
	cmd /usr/bin/borg mount "${repo}::${tag}" "${tmp_dir}"


	for path in ${paths}; do
		if [ -d "${tmp_dir}${path}" ]; then
			if ! [[ "$(md5sum_get_sum "${tmp_dir}${path}/check-borg-backup")" == "$(md5sum_get_sum "${tmp_file}")" ]]; then

				return_value=${EXIT_ERROR}
			fi
		fi
	done


	if [[ ${return_value} == ${EXIT_ERROR} ]]; then
		log_backup ERROR "${repo}"  "Backup '${tag}' is corrupted"
	else
		log_backup DEBUG "${repo}" "Backup '${tag}' is ok"
	fi

	# Cleanup

	cmd umount "${tmp_dir}"
	rm -d ${tmp_dir}
	rm ${tmp_file}

	release_lock "${repo}"

	return ${return_value}

}
