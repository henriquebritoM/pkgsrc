#!/bin/sh
#
#	Run LTP syscall tests on NetBSD, using Compat Linux
#
# 	Requirements:
# 	- e2fsprogs (for ext* testing)
# 	- module compat_linux enabled

set -e

# Directory from where the script is being called
CALLING_DIR="$(pwd)"

# Directory where the script data is stored
DATA_DIR="/usr/pkg/libexec/compat_linux_test_project"

# Optional: Used to specify one syscall subdirectory inside SYSCALL_DIR
SYSCALL_NAME=""

# Optional: A comma-separated list of which syscalls to test. Should be parsed
# into individual SYSCALL_NAME
SYSCALLS_LIST=""

# Directory where compiled tests will be placed
BINARIES_DIR="${DATA_DIR}/testcases/bin"

# Index for helping with grouping testcases for syscall
# LTP uses the file-tree to group them, but we do not have access to the 
# file-tree here
INDEX_FILE="${DATA_DIR}/syscall-index.txt"

# File with both runtest entries for 'syscalls' and 'syscalls-ipc'
# By joining them we can simplify work later, when iterating through them
RUNTEST_JOIN_FILE="${DATA_DIR}/syscalls-runtest"

# Directory where logs from tested syscalls are stored
LOGS_DIR="${CALLING_DIR}/sys_logs"
USER_DEFINED_LOGS_DIR=""

# Directory where the reference logs are stored
# to be compared against
REFERENCE_LOGS_DIR=""
USER_DEFINED_REFERENCE_DIR="${DATA_DIR}/reference_logs/reference"

# Directory where results from comparisons are stored
COMPARE_DIR="${CALLING_DIR}/diff_logs"

# How many lines the log header takes
# They all should have the same size, as they are created in a static style
# This may not be ideal, but there is no need to exchange this method with a 
# runtime check
HEADER_LENGTH=10

# Script returns an error if the comparison found a change marked as 'regressions'
FAIL_ON_REGRESSION=0

# Some tests require a block device to be present.
# The way LTP tries to get it does not work on NetBSD, so it is necessary
# to pass through a enviroment variable
BLK_FILE="${DATA_DIR}/test.img"
BLK_VND="vnd0"
BLK_DEV="/dev/r${BLK_VND}d"

# LTP environment variable. 
# used to trim the tests' outputs to a more 'reproducible' style
LTP_REPRODUCIBLE_OUTPUT=0

# Some tests use the kernel config file to perform checks for some features.
# Here, we use a custom file to tell the tests which features are present.
# Note that the features is this file are not exhaustive, so some tests may ask
# for configuration not currently present in the file.
KCONFIG_PATH="${DATA_DIR}/linux-config"

# Some testcases verify if the operations were finished under
# a timer treshold. The LTP way of detecting if the system is
# a VM does not work os NetBSD.
# With this setting, we tell LTP to not check the tests against
# timers.
LTP_VIRT_OVERRIDE="kvm"

# Recreation of the command and args used to run the script
_SCRIPT_INVOCATION=""

update_env_vars() {
	export LTPROOT="${DATA_DIR}"
	export PATH="${PATH}:${BINARIES_DIR}"
	export LTP_DEV="${BLK_DEV}"
	export LTP_REPRODUCIBLE_OUTPUT="${LTP_REPRODUCIBLE_OUTPUT}"
	export KCONFIG_PATH="${KCONFIG_PATH}"
	export LTP_VIRT_OVERRIDE="${LTP_VIRT_OVERRIDE}"
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
	compat_linux_test_project is a package to download, build, and run
	the Linux Test Project (LTP) test suite on NetBSD, intended for
	testing	the compat_linux compatibility layer.

	It automates fetching, building, and executing LTP tests, helping
	to identify missing syscalls, behavioral differences, and other
	issues in NetBSD's Linux compatibility subsystem.

	If no --syscall option is passed, the default behavior is to test
	every possible syscall. This uses the LTP runtest/syscalls file to
	determine what to test and in which order. This means that the syscall
	name cannot be correctly-determined sometimes, resulting in suboptimal
	output in the logs. This also takes some time and is not
	recommended, except in some niche cases.

	All tests belong to Linux Testing Project, this package only ports
	them to	make them run on NetBSD. Support the Linux Test Project by
	checking their official website:
		https://github.com/linux-test-project/ltp

OPTIONS
	-d, --dir path
		Behavior depends on the mode the script is run in:
 
		In test-run mode (default): path is the directory where
		new logs are stored, overwriting any older logs already there.
 
		In comparison mode (-c): path is the directory containing the
		"current" set of logs to compare. Nothing is overwritten in
		this mode.

	-s, --syscall syscall1[,syscall2,...]
		A comma-separated list of which syscalls to test. 
		The script will search for them using the LTP runtest file,
		so the name may be slightly different from the syscall name
		(though this is unusual).
	
	-r, --reproducible
		Sets the LTP enviroment variable LTP_REPRODUCIBLE_OUTPUT to 1.
		According to LTP documentation, this "suppress printing TINFO
		and TDEBUG messages and discards the actual content of the
		other messages printed by the test (suitable for a
		reproducible output)."

		This flag should be set if the logs are meant to be compared.
	
	-c, --compare-to[=logs_dir]
		Compares two sets of logs, highlighting their differences. For
		a consistent comparison, both sets of logs must have been
		created using the 'reproducible' mode ('-r' flag).

		If no directory is provided through 'logs_dir', the reference
		shipped	with the package is used to compare against. If a
		directory is passed, it is used	instead of the reference.

		In both cases, the second set of logs to compare against the
		reference is taken from '-d' flag, if passed, or from the
		default 'sys_logs' otherwise.

		If '-s' is also passed, the comparison is restricted to the
		syscalls listed there.

		The comparison is done as follows:
		Checks for tests that are new, tests that are no longer
		present, and tests whose result changed. Changed results are
		further split into regressions (e.g. PASS -> FAIL), fixes
		(e.g. FAIL -> PASS) and	other changes (e.g. shift in skipped
		or warnings). 

		Each category is stored in its own subdirectory, mirroring the
		syscall/testcase layout of the compared logs:
			compared_logs/
			|-- changed/
			|-- fixed/
			|-- new/
			|-- regressed/
			|-- removed/
			    |-- syscall_a/
			        |- testcase01.log

		The comparison assumes the testcases output follows the 
		standard and new LTP strucuture. This is not true for every
		testcase, in this case, the comparison has undefined 
		behaviour.

	--fail-on-regression
		Only meaningful together with -c.
		When this flag is set, the script exits with a non-zero status
		if any test is found in compared_logs/regressed/. This is
		intended for use by automated testing.
		Has no effect without -c.

	-h, --help
		Shows this message
EOF
}

mount_ltp_dev() {

	if [ "$(vnconfig -l ${BLK_VND})" != "${BLK_VND}: not in use" ]; then
		# Stop early if the vnd target is already in use
		echo "${BLK_VND} is already in use. Cannot continue" >&2
		echo "Did you stop mid-test?" >&2
		exit 1
	else
		# Mount the vnd if the target is free
		vnconfig "${BLK_VND}" "${BLK_FILE}"
	fi
}

unmount_ltp_dev() {
	# checks if the vnd was mounted by the script
	vnconfig -u "${BLK_VND}"
}

clean_logs() {
	rm -rf "${LOGS_DIR:?}"/*
}

create_logs_dir() {
	if [ ! -z "${USER_DEFINED_LOGS_DIR}" ]; then
		LOGS_DIR="${USER_DEFINED_LOGS_DIR}"

	else
		base_logs_dir="$(next_unused_dir_name  "sys_logs")"

		LOGS_DIR="${CALLING_DIR}/${base_logs_dir}"
	fi

	mkdir -p "${LOGS_DIR}"
}

create_compare_dir() {

	if [ -e "${COMPARE_DIR}" ]; then
		diff_name="$(next_unused_dir_name  "diff_logs")"
		COMPARE_DIR="${CALLING_DIR}/${diff_name}"
	fi

	mkdir -p "${COMPARE_DIR}"
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

	output_file="${syscall_dir}/${test_name}.log"

	# Prints the header for the logs
	# Clears the file if it was present
	log_header "${sys_filter}" > "${output_file}"

	set -- ${test_args} # word splitting is desired

	echo "syscall_test: ${test_bin}"

	"${bin_dir}/${test_bin}" "$@" 2>&1 | tee -a "${output_file}" || true
}

check_for_testcase_issue() {
	syscall_name="$1"

	# The user decided to run this syscall, do not block
	if [ "${syscall_name}" = "${SYSCALL_NAME}" ]; then
		return 0
	fi

	case "${syscall_name}" in
		# causes kernel panic
		rt_sigqueueinfo)
			return 1
			;;
		# causes kernel panic
		copy_file_range)
			return 1
			;;
		# Does not finish
		sigprocmask)
			return 1
			;;
		# Does not finish
		sigrelse)
			return 1
			;;
		*)
			return 0
			;;
	esac
}

# Runs all testcases for a given syscall, if one provided as argument.
# Otherwise, goes through all syscalls and testcases listed in the index
run_testcases() {
	syscall="$1"
	sys_filter="$(basename "${syscall}")" # name of the syscall passed

	bin_dir="${BINARIES_DIR}"
	runtest_syscalls_file="${RUNTEST_JOIN_FILE}"

	cat "${INDEX_FILE}" | while read -r syscall_name testcases; do

		# skipps the lines that do not match sys_filter, unless it is empty
		if [ -n "${sys_filter}" ] && [ "${syscall_name}" != "${sys_filter}" ]; then
			continue
		fi

		# skipps tests that are known to cause issues
		if ! check_for_testcase_issue "${syscall_name}"; then
			continue
		fi

		syscall_dir="${LOGS_DIR}/${syscall_name}"
		# Clears previous logs, if any
		if [ -e "${syscall_dir:?}" ]; then
			rm "${syscall_dir:?}/*"
		else 
			mkdir -p "${syscall_dir}"
		fi

		for testcase in ${testcases}; do

			runtest_line="$(grep "^${testcase}[[:space:]]" "${runtest_syscalls_file}")"

			set -- ${runtest_line} # word-splitting is desired

			test_name="$1"
			test_bin="$2"
			shift 2
			
			run_testcase "${test_name}" "${test_bin}" "$*"
		done
	done
}

run_tests() {

	mount_ltp_dev
	
	if [ -z "${SYSCALLS_LIST}" ]; then
		# user did not specify which syscall to test. Test them all
		run_testcases 
	else
		# User specified syscalls to test
		# Go through each one and test their testcases
		syscall_list_parsed=$(echo "${SYSCALLS_LIST}" | sed "s/,/ /g")
	
		set -- ${syscall_list_parsed} # word-splitting is desired

		while [ "$#" -gt 0 ]; do
			SYSCALL_NAME="$1"

			run_testcases "${SYSCALL_NAME}"

			shift
		done
	fi

	unmount_ltp_dev
}

# Get the 'header' inside dir/*/*.log (does not check if it is, in fact, a log
# header)
get_representative_log() {
	dir="$1"
	find "${dir}" -mindepth 2 -maxdepth 2 -type f -name '*.log' | head -n 1
}

# Creates the header for the comparison
# This header is made up of both headers from the reference and current sets of
# logs, warnings, whether both headers have some key different values and a
# brief summary of the results.
compare_create_header() {
	reference_logs_dir="$1"
	current_logs_dir="$2"

	reference_sample="$(get_representative_log "${reference_logs_dir}")"
	current_sample="$(get_representative_log "${current_logs_dir}")"

	if [ -z "${current_sample}" ] || [ -z "${reference_sample}" ]; then
		printf "Cannot build comparison summary: no log files found in one of the sets\n" >&2
		exit 1
	fi

	current_header="$(head -n "${HEADER_LENGTH}" "${current_sample}")"
	reference_header="$(head -n "${HEADER_LENGTH}" "${reference_sample}")"

	{
		printf '==================================================\n'
		printf '   COMPARISON SUMMARY\n'
		printf '==================================================\n\n'

		printf 'reference set: %s \n' "${reference_logs_dir}"
		printf '%s\n\n' "${reference_header}"

		printf 'current set: %s \n' "${current_logs_dir}"
		printf '%s\n\n' "${current_header}"
	} > "${COMPARE_DIR}/summary.log"

	# Checks for some fields that *may* be relevant (or even invalidate) some
	# tests comparisons. Outputs a warning for them.
	for field in netbsd_version arch ltp_version reproducible; do

		reference_val="$(printf '%s\n' "${reference_header}" | sed -n "s/^${field}: //p")"
		current_val="$(printf '%s\n' "${current_header}" | sed -n "s/^${field}: //p")"

		if [ "${reference_val}" != "${current_val}" ]; then
			printf 'WARNING: %s differs (reference: "%s", current: "%s")\n' \
				"${field}" "${reference_val}" "${current_val}" >> "${COMPARE_DIR}/summary.log"
		fi
	done
}

# Counts how many cases were found for each comparison category
compare_append_counts() {
	{
		printf '\n'
		printf '==================================================\n'
		printf '   RESULTS\n'
		printf '==================================================\n'
		printf '\n'

		for category in regressed fixed changed new removed; do
			count="$(find "${COMPARE_DIR}/${category}" -type f -name '*.log' 2>/dev/null | wc -l)"
			printf '%-10s %s\n' "${category}:" "${count}"
		done
	} >> "${COMPARE_DIR}/summary.log"
}

# Extracts the values of the results and returns them in a single line
compare_extract_summary() {
	file="$1"
	awk '
		/^passed[[:space:]]/   { passed = $2 }
		/^failed[[:space:]]/   { failed = $2 }
		/^broken[[:space:]]/   { broken = $2 }
		/^skipped[[:space:]]/  { skipped = $2 }
		/^warnings[[:space:]]/ { warnings = $2 }
		END { print passed, failed, broken, skipped, warnings }
	' "${file}"
}


compare_testcase() {
	reference_file="$1"
	current_file="$2"
	syscall_name="$3"
	testcase_name="$4"

	# This testcase is not present in the reference logs, so it is 'new'
	if [ ! -e "${reference_file}" ]; then
		mkdir -p "${COMPARE_DIR}/new/${syscall_name}"

		printf 'testcase: %s\n' "${testcase_name}" \
			> "${COMPARE_DIR}/new/${syscall_name}/${testcase_name}.log"
		return
	fi

	# This testcase is not present in the current logs, so it was 'removed'
	if [ ! -e "${current_file}" ]; then
		mkdir -p "${COMPARE_DIR}/removed/${syscall_name}"

		printf 'testcase: %s\n' "${testcase_name}" \
			> "${COMPARE_DIR}/removed/${syscall_name}/${testcase_name}.log"
		return
	fi

	r_summary="$(compare_extract_summary "${reference_file}")"
	c_summary="$(compare_extract_summary "${current_file}")"

	# Nothing to when both testcases have the same output
	[ "${r_summary}" = "${c_summary}" ] && return

	# By 'bad', we mean the sum of the 'failed' + 'broken' fields
	r_bad="$(printf '%s' "${r_summary}" | awk '{print $2+$3}')"
	c_bad="$(printf '%s' "${c_summary}" | awk '{print $2+$3}')"

	if [ "${c_bad}" -gt "${r_bad}" ]; then
		category="regressed"
	elif [ "${c_bad}" -lt "${r_bad}" ]; then
		category="fixed"
	else
		# A testcase is marked as 'changed' when there is a difference in its
		# 'skipped' or/and 'warnings' ltp fields
		# We may want to look closer to why this happened
		category="changed"
	fi

	mkdir -p "${COMPARE_DIR}/${category}/${syscall_name}"

	{
		printf 'testcase: %s\n' "${testcase_name}"
		printf '  reference (passed failed broken skipped warnings): %s\n' "${r_summary}"
		printf '  current   (passed failed broken skipped warnings): %s\n' "${c_summary}"
	} > "${COMPARE_DIR}/${category}/${syscall_name}/${testcase_name}.log"
}
	
compare_tests() {
	current_logs_dir=""
	reference_logs_dir=""

	# Use default, unless user passed another dir as argument
	if [ ! -z "${USER_DEFINED_LOGS_DIR}" ]; then
		current_logs_dir="${USER_DEFINED_LOGS_DIR}"
	else 
		current_logs_dir="${LOGS_DIR}"
	fi

	# Use default, unless user passed another dir as argument
	if [ ! -z "${USER_DEFINED_REFERENCE_DIR}" ]; then
		reference_logs_dir="${USER_DEFINED_REFERENCE_DIR}"
	else 
		reference_logs_dir=${REFERENCE_LOGS_DIR}
	fi

	# Cannot compare if one directory does not exist
	if [ ! -e "${current_logs_dir}" ]; then
		printf "Nothing to be compared, \'%s\' not found\n" "${current_logs_dir}" >&2
		exit 1
	elif [ ! -e "${reference_logs_dir}" ]; then
		printf "Nothing to be compared, \'%s\' not found\n" "${reference_logs_dir}" >&2
		exit 1
	fi

	create_compare_dir 
	compare_create_header "${reference_logs_dir}" "${current_logs_dir}"

	# Allow the user to pass which syscall should be compared
	if [ -n "${SYSCALLS_LIST}" ]; then
		all_syscalls="$(echo "${SYSCALLS_LIST}" | tr ',' '\n' | sort -u)"
	else
		all_syscalls="$( (ls "${reference_logs_dir}"; ls "${current_logs_dir}") | sort -u)"
	fi

	for syscall in ${all_syscalls}; do

		r_dir="${reference_logs_dir}/${syscall}"
		c_dir="${current_logs_dir}/${syscall}"

		# redirect the error logs to /dev/null. With this, the user won't see
		# anything if a syscall dir is empty. (In case of a new/remove syscall
		# between the reference and the current logs)
		all_testcases="$(\
            (ls "${r_dir}" 2>/dev/null || true; ls "${c_dir}" 2>/dev/null || true) \
            | sort -u)"

		for tc_file in ${all_testcases}; do
			testcase="${tc_file%.log}"

			compare_testcase "${r_dir}/${tc_file}" "${c_dir}/${tc_file}" \
				"${syscall}" "${testcase}"
		done

	done

	compare_append_counts
	cat "${COMPARE_DIR}/summary.log"
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
				USER_DEFINED_LOGS_DIR="${CALLING_DIR}/$1" # uses the next
				;;
			-h|--help)
				should_print_help_message=0
				;;
			-r|--reproducible)
				LTP_REPRODUCIBLE_OUTPUT=1
				;;
			--compare-to=*)
				USER_DEFINED_REFERENCE_DIR="${CALLING_DIR}/${arg#--compare-to=}"
				compare_mode=0
				;;
			-c=*)
				USER_DEFINED_REFERENCE_DIR="${CALLING_DIR}/${arg#-c=}"
				compare_mode=0
				;;
			-c|--compare-to)
				compare_mode=0
				;;
			--fail-on-regression)
				FAIL_ON_REGRESSION=1
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

	if [ "${compare_mode}" -eq 0 ] && [ "${FAIL_ON_REGRESSION}" -eq 1 ]; then
		regressions="$(find "${COMPARE_DIR}/regressed" -type f -name '*.log' 2>/dev/null | wc -l)"
		if [ "${regressions}" -gt 0 ]; then
			exit 1
		fi
	fi

	if [ "${compare_mode}" -eq 1 ] && [ "${FAIL_ON_REGRESSION}" -eq 1 ]; then
		echo "Flag 'FAIL_ON_REGRESSION' is being used outside comparison mode. \
			This flag has no effect outside comparison mode"
	fi
}

main "$@"
