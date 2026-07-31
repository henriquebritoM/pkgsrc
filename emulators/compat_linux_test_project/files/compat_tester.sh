#!/bin/sh
#
#	run LTP syscall testes on NetBSD, using Compat Linux
#
# 	Requirements:
# 	- e2fsprogs (for ext* testing)
# 	- module compat_linux enabled

set -e

# Directory from where the script is being called
CALLING_DIR="$(pwd)"

# Directory where the script data is stored
DATA_DIR="/usr/pkg/libexec/compat_linux_test_project"

# Optional: Used to specify one syscalls subdirectory inside SYSCALL_DIR
SYSCALL_NAME=""

# Optional: A coma separated list of which syscalls to test. Should be parsed
# into individual SYSCALL_NAME
SYSCALLS_LIST=""

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

print_help_message() {
	cat << EOF
NAME
	compat_linux_test_project - package to run LTP tests on NetBSD

SYNOPSIS
	compat_linux_test_project [options]

DESCRIPTION
	compat_linux_test_project is a package to download, build, and run the 
	Linux Test Project (LTP) test suite on NetBSD, intended for testing the
	compat_linux compatibility layer.

	It automates fetching, building, and executing LTP tests, helping
	to identify missing syscalls, behavioral differences, and other
	issues in NetBSD's Linux compatibility subsystem.

	If no --syscall option is passed, the default behavior is to test every
	possible syscall. This uses the LTP runtest/syscalls file to determine what
	to test and in which order. This means that the syscall name cannot be
	correclty determined sometimes, resulting in some not ideal behavior in the
	logs. This also takes some time and is not recommended, except in some
	niche cases.

OPTIONS
	-d, --dir path
		Specify a dir for storing the logs. Note that it will overwrite any
		file with a conflicting name.

	-s, --syscall syscall1,syscall2,...
		A comma separated list of which syscalls to test. 
		The script will search for them using the LTP runtest file, so the name
		may be slightly different from the syscall name. This is unusual,
		though.
		A single syscall can be passed, in this case, no commas should be used.
	
	-h, --help
		Shows this message
EOF
}

mount_ltp_dev() {

	if ! [ -e "${BLK_FILE}" ]; then
		dd if=/dev/zero of="${DATA_DIR}"/test.img bs=1m count=512
	fi

	if [ "$(vnconfig -l ${BLK_VND})" != "${BLK_VND}: not in use" ]; then
		# Stop early if the vnd target is already in use
		echo "${BLK_VND} is already in use. Cannot continue" >&2
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

run_test_for_all_syscalls() {

	runtest_file="${BINARIES_DIR}/runtest/syscalls"

	# Iterate through the list of testcases.
	# Parses the informationg provided by runtest/syscalls
	cat "${runtest_file}" | while read -r test_name test_bin test_args; do

		# skip comments and blank lines
		case "${test_name}" in
			''|'#'*) continue ;;
		esac

		# We cannot know the syscall name directly, this is an approximation
		# using what the runtest file says. 
		# The problem is that LTP is not 100% consistent with it's
		# name convention, this is specially bad when syscalls have variants
		# like clone & clone3 or fstat & fstat_64
		syscall_name="${test_name%%[0-9]*}"

		bin_dir="${BINARIES_DIR}/testcases/bin"
		output_file="${LOGS_DIR}/${syscall_name}"

		# Cleans output_file
		echo "" > "${output_file}"

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

	if [ -z "${SYSCALLS_LIST}" ]; then
		# user did not tell which syscall to test. Test them all
		run_test_for_all_syscalls
	else
		# User specified a syscall to test
		syscall_list_parsed=$(parse_coma_separeted_list "${SYSCALLS_LIST}")
	
		set -- ${syscall_list_parsed} # word splitting is desired

		while [ "$#" -gt 0 ]; do
			SYSCALL_NAME="$1"

			run_test_for_one_syscall "${SYSCALL_NAME}"

			shift
		done
	fi

	unmount_ltp_dev
}

main() {

	should_print_help_message=1

	while [ "$#" -gt 0 ]; do
		arg="$1"

		case "${arg}" in
			-s|--syscall)
				shift # consumes the flag
				SYSCALLS_LIST="$1" # uses the next
				;;
			-d|--output-dir)
				shift # consumes the flag
				CALLING_DIR="$1" # uses the next
				;;
			-h|--help)
				should_print_help_message=0
				;;
			*)
				echo "Invalid Option: '${arg}'" >&2
				exit 1
				;;
		esac
		shift
	done

	if [ "${should_print_help_message}" -eq 0 ]; then
		print_help_message
		return
	fi

	run_tests
}

main "$@"
