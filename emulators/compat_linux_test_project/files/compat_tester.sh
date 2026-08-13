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
BINARIES_DIR="${DATA_DIR}/testcases/bin"

RUNTEST_DIR="${DATA_DIR}/runtest"

# Index for helping with grouping testcases for syscall
# LTP uses the file-tree to group them, but we do not have acces to the 
# file-tree here
INDEX_FILE="${DATA_DIR}/syscall-index.txt"

# Directory where logs from tested syscalls are stored
LOGS_DIR="${CALLING_DIR}"
USER_DEFINED_LOGS_DIR=""

# Directory where the baseline logs are stored
# to be compared against
BASELINE_LOGS_DIR=""

# Some tests require a block device to be present.
# The way LTP tries to get it does not work on NetBSD, so it is necessary
# to pass through a enviroment variable
BLK_FILE="${DATA_DIR}/test.img"
BLK_VND="vnd0"
BLK_DEV="/dev/${BLK_VND}a"
IS_BLK_MOUNTED=0

# LTP enviroment variable. 
# used to trim the tests' outputs to a more 'reproducible' style
LTP_REPRODUCIBLE_OUTPUT=0

# Recreation of the command and args used to run te script
_SCRIPT_INVOCATION=""

update_env_vars() {
	export LTPROOT="${DATA_DIR}"
	export PATH="${PATH}:${BINARIES_DIR}"
	export LTP_DEV="${BLK_DEV}"
	export LTP_REPRODUCIBLE_OUTPUT="${LTP_REPRODUCIBLE_OUTPUT}"
}

is_empty_dir() {
	[ -z "$(ls -A "$1")" ]
}

quote_args() {
	out=""
	for a in "$@"; do
		escaped=$(printf '%s' "$a" | sed "s/'/'\\\\''/g")
		out="${out} '${escaped}'"
	done
	printf '%s' "${out# }"
}

# Takes one argument: base_dir_name
# Loops through base_dir_name_1, base_dir_name_2, ..., base_dir_name_x until
# it finds a unused name.
next_unused_dir_name() {
	base_dir_name="$1"

	if [ ! -e "${base_dir_name}" ]; then
		echo "${base_dir_name}"
		return 0
	fi

	i=1

	while [ -e "${base_dir_name}_${i}" ]; do
		i=$((i + 1))
	done

	echo "${base_dir_name}_${i}"
}

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

	All tests belong to Linux Testing Project, this package only ports them to
	make they run on NetBSD. Support the Linux Test Project by checking their
	official website: https://github.com/linux-test-project/ltp

OPTIONS
	-d, --dir path
		Behavior depends on the mode the script is run in:
 
		In test-run mode (default): path is the directory where
		new logs are stored, overwriting any older logs already there.
 
		In comparison mode (-c): path is the directory containing the
		"current" set of logs to compare. Nothing is overwritten in this mode.

	-s, --syscall syscall1,syscall2,...
		A comma separated list of which syscalls to test. 
		The script will search for them using the LTP runtest file, so the name
		may be slightly different from the syscall name. This is unusual,
		though.
		A single syscall can be passed, in this case, no commas should be used.
	
	-r, --reproducible
		Sets the LTP enviroment variable LTP_REPRODUCIBLE_OUTPUT to 1.
		According to LTP documentation, this "suppress printing TINFO and
		TDEBUG messages and discards the actual content of the other messages
		printed by the test (suitable for a reproducible output)."

		This flag should be set if the logs are meant to be compared.
	
	-c, --compare-to[=logs_dir]
		Compares two sets of logs, highlighting their differences. For a
		consistent comparison, both sets os logs must have been gathered
		using the 'reproducible' mode ('-r' flag).

		If no directory is provided through 'logs_dir', the baseline shipped
		with the package for the given NetBSD version is used to compare 
		against. If a directory is passed, it is used instead of the baseline.

		In both cases, the second set of logs to compare against the baseline
		is taken from '-d' flag, if passed, or from the default 'sys_logs'
		otherwise.

		The comparison is done as follows:
		Checks for tests that are new, tests that are no longer present,
		and tests whose result changed. Changed results are further split
		into regressions (e.g. PASS -> FAIL) and fixes (e.g. FAIL -> PASS). 

		Each category is stored in its own subdirectory:
			compared_logs/
			├── fixed/
			├── new/
			├── regressed/
			└── removed/

	--fail-on-regression
		Only meaningful together with -c.
		When this flag is set, the script exits non-zero if any test is found 
		in compared_logs/regressed/, so that automated callers.
		Has no effect without -c.

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

clean_logs() {
	rm -rf "${LOGS_DIR:?}"/*
}

create_logs_dir() {
	if [ ! -z "${USER_DEFINED_LOGS_DIR}" ]; then
		LOGS_DIR="${USER_DEFINED_LOGS_DIR}"

	else
		base_logs_dir="sys_logs"
		base_logs_dir="$(next_unused_dir_name  ${base_logs_dir})"

		LOGS_DIR="${LOGS_DIR}/${base_logs_dir}"
	fi

	if ! [ -e "${LOGS_DIR}" ]; then
		mkdir "${LOGS_DIR}"
	fi
}

# Header stores some useful data about the enviroment in which the tests
# ran. It can be useful to track down issues:
#
# ---- compat_linux_test_project log header ----
# date: Fri, 14 Aug 2026 00:09:27 +0000
# netbsd_version: 11.0_RC5
# netbsd_build: NetBSD 11.0_RC5 (GENERIC) #0: Tue Jun 16 15:48:07 UTC
# 2026  mkrepro@mkrepro.NetBSD.org:/usr/src/sys/arch/amd64/compile/GENERIC
# arch: amd64
# ltp_version: 20260529
# script_invocation: "/usr/pkg/bin/compat_linux_test_project '-r' '-s' 'readv,writev'"
# syscall_tested: readv
# reproducible: 1
# --------------------------------------------------
log_header() {
	sys_filter="$1"

	curr_date="$(date -uR)"
	kernel_version="$(uname -r)"
	kernel_build="$(uname -v)"
	arch="$(uname -m)"
	ltp_version="$(cat ${DATA_DIR}/ltp-version.txt)" 

	cat << EOF
	
---- compat_linux_test_project log header ----
date: ${curr_date}
netbsd_version: ${kernel_version}
netbsd_build: ${kernel_build}
arch: ${arch}
ltp_version: ${ltp_version}
script_invocation: "${_SCRIPT_INVOCATION}"
syscall_tested: ${sys_filter}
reproducible: ${LTP_REPRODUCIBLE_OUTPUT}
--------------------------------------------------

EOF
}

# Runs a given testcase and outputs their result into the output file
run_testcase() {
	test_name="$1"
	test_bin="$2"
	test_args="$3"
	output_file="$4"

	set -- ${test_args} # word splitting is desired

	{
		echo "=================================================="
		echo "   TEST: ${test_name}"
		echo "=================================================="
		echo ""
	} >> "${output_file}"

	echo "syscall_test: ${test_bin}"

	"${bin_dir}/${test_bin}" "$@" 2>&1 | tee -a "${output_file}" || true
}

# Runs all testcases for a given syscall, if one provided as argument,
# otherwise, goes through all syscalls and testcases listed in the index
run_testcases() {
	syscall="$1"
	sys_filter="$(basename "${syscall}")" # name of the syscall passed

	bin_dir="${BINARIES_DIR}"
	output_file="${LOGS_DIR}/${sys_filter}.txt"
	runtest_syscalls_file="${RUNTEST_DIR}/syscalls"

	cat "${INDEX_FILE}" | while read -r read_syscall_name testcases; do

		# skipps the lines that do not match sys_filter, unless it is empty
		if [ -n "${sys_filter}" ] && [ "${read_syscall_name}" != "${sys_filter}" ]; then
			continue
		fi

		# Prints the header for the logs
		# Clears the file if it was present
		log_header "${sys_filter}" > "${output_file}"

		for testcase in ${testcases}; do

			runtest_line="$(grep "^${testcase}[[:space:]]" "${runtest_syscalls_file}")"

			set -- ${runtest_line} # word splitting is desired

			test_name="$1"
			test_bin="$2"
			shift 2
			
			run_testcase "${test_name}" "${test_bin}" "$*" "${output_file}"
		done
	done
}

run_tests() {

	mount_ltp_dev
	
	if [ -z "${SYSCALLS_LIST}" ]; then
		# user did not tell which syscall to test. Test them all
		run_testcases 
	else
		# User specified n syscalls to test
		# Go through each one and test theit testcases
		syscall_list_parsed=$(echo "${SYSCALLS_LIST}" | sed "s/,/ /g")
	
		set -- ${syscall_list_parsed} # word splitting is desired

		while [ "$#" -gt 0 ]; do
			SYSCALL_NAME="$1"

			run_testcases "${SYSCALL_NAME}"

			shift
		done
	fi

	unmount_ltp_dev
}

compare_tests() {
	echo "option not implemented yet"
	return 0
}

main() {
	_SCRIPT_INVOCATION="$0 $(quote_args "$@")"

	should_print_help_message=1
	compare_mode=1

	while [ "$#" -gt 0 ]; do
		arg="$1"

		case "${arg}" in
			-s|--syscall)
				shift # consumes the flag
				SYSCALLS_LIST="$1" # uses the next
				;;
			-d|--output-dir)
				shift # consumes the flag
				USER_DEFINED_LOGS_DIR="$1" # uses the next
				;;
			-h|--help)
				should_print_help_message=0
				;;
			-r|--reproducible)
				LTP_REPRODUCIBLE_OUTPUT=1
				;;
			--compare-to=*)
				BASELINE_LOGS_DIR="${arg#--compare-to=}"
				compare_mode=0
				;;
			-c=*)
				BASELINE_LOGS_DIR="${arg#c=}"
				compare_mode=0
				;;
			-c|--compare-to)
				compare_mode=0
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

	update_env_vars

	create_logs_dir 

	if [ "${compare_mode}" -eq 0 ]; then
		compare_tests
	else 
		run_tests
	fi
}

main "$@"
