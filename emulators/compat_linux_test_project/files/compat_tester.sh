#!/bin/sh
#
#	run LTP syscall testes on NetBSD, using Compat Linux
#
#	Usage:
# 	todo
#
# 	Requirements:
# 	- e2fsprogs (for ext* testing)
# 	- module compat_linux enabled

set -e

# Directory from where the script is being called
CALLING_DIR="$(cd "$(dirname "$0")" && pwd)"

# Directory where the script data is stored
DATA_DIR="/usr/pkg/libexec/compat_linux_test_project"

# Directory where the LTP tests will be cloned
LTP_DIR="${DATA_DIR}/ltp"

# Base directory for the syscalls subdirectory inside ltp
SYSCALL_DIR="${LTP_DIR}/testcases/kernel/syscalls"

# Optional: Used to specify one syscalls subdirectory inside SYSCALL_DIR
SYSCALL_NAME=""

# Directory where compiled tests will be placed
BINARIES_DIR="${DATA_DIR}"
export LTPROOT="${BINARIES_DIR}"
export PATH="${PATH}:${BINARIES_DIR}/testcases/bin"

# Directory where logs from tested syscalls are stored
LOGS_DIR="${CALLING_DIR}/syscall_logs"

# Some tests require a block device to be present.
# The way LTP tries to get it does not work on NetBSD, so it is necessary
# to pass through a enviroment variable
BLK_FILE="${DATA_DIR}/test.img"
BLK_VND="vnd0"
BLK_DEV="/dev/${BLK_VND}a"
IS_BLK_MOUNTED=0
export LTP_DEV="${BLK_DEV}"

if ! [ -e "${LOGS_DIR}" ]; then
	mkdir "${LOGS_DIR}"
fi

if ! [ -e "${BLK_FILE}" ]; then
	dd if=/dev/zero of="${DATA_DIR}"/test.img bs=1m count=512
fi

mount_ltp_dev() {

	if ! [ "$(vnconfig -l ${BLK_DEV})" != "${BLK_DEV}: not in use" ]; then
		# Stop early if the vnd target is already in use
		echo "${BLK_DEV} is already in use. Cannot continue" >&2
		echo "Did you stop mid-test?" >&2
		exit 1
	else
		# Mount the vnd if the target is free
		vnconfig "${BLK_VND}" "${BLK_FILE}"
		IS_BLK_MOUNTED=1 # Mark that we mounted
	fi
}

unmount_ltp_dev() {
	# checks if the vnd was mounted by the script
	if [ "${IS_BLK_MOUNTED}" -eq 1 ]; then
		vnconfig -u "${BLK_VND}"
		IS_BLK_MOUNTED=0
	fi
}

is_empty_dir() {
	[ -z "$(ls -A "$1")" ]
}

clean_logs() {
	rm -rf "${LOGS_DIR:?}"/*
}

# Gets the list of tests for a given syscall
get_test_list() {
	syscall_name="$1"

	runtest_file="${BINARIES_DIR}/runtest/syscalls"

	# Globs only the tests that have the syscall_name + number + Space
	# to avoid matching syscalls with similar name (like open & openat)
	list="$(grep -E "^${syscall_name}[0-9_]* " "${runtest_file}")"

	echo "${list}"
}

run_test_for_one_syscall() {
	syscall="$1"

	syscall_name="$(basename "${syscall}")"

	bin_dir="${BINARIES_DIR}/testcases/bin"
	output_file="${LOGS_DIR}/${syscall_name}"

	# Cleans output_file
	echo "" > "${output_file}"

	test_list="$(get_test_list "${syscall_name}")"

	# Iterate through the list of testcases.
	# Parses the informationg provided by runtest/syscalls
	echo "${test_list}" | while read -r test_name test_bin test_args; do

		set -- ${test_args} # word splitting is desired

		{
			echo "==================================================",
			echo "   TEST: ${test_name}",
			echo "==================================================",
			echo "",
		} >> "${output_file}"

		echo "syscall_test: ${test_bin}"

		"${bin_dir}/${test_bin}" "$@" 2>&1 | tee -a "${output_file}" || true

	done
}

run_tests() {

	mount_ltp_dev

	if ! [ -z "${SYSCALL_NAME}" ]; then
		# User specified a syscall to test
		run_test_for_one_syscall "${SYSCALL_NAME}"
	else
		# user did not tell which syscall to test. Test them all
		for syscall in "${SYSCALL_DIR}"/*/; do
			run_test_for_one_syscall "${syscall}"
		done
	fi

	unmount_ltp_dev
}

main() {

	should_clear_logs=1

	while [ "$#" -gt 0 ]; do
		arg="$1"

		if [ "${arg}" = "--clean" ]; then
			should_clear_logs=0
		elif [ "${arg}" = "--syscall" ]; then
			shift #consumes the arg
			SYSCALL_NAME="$1" # uses the next
		else
			echo "Invalid Option: '${arg}'" >&2
			exit 1
		fi
		shift
	done

	if [ "${should_clear_logs}" -eq 0 ]; then
		clean_logs
		return
	fi

	run_tests
}

main "$@"
