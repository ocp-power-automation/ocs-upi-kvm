#!/bin/bash

set -euo pipefail

#########################################################
# SCRIPT METADATA
#########################################################
readonly SCRIPT_VERSION="2.0"
readonly SCRIPT_NAME="$(basename "$0")"

#########################################################
# CONFIGURATION
#########################################################

# Timeouts and delays
readonly CEPH_HEALTH_WAIT=120
readonly COMMAND_TIMEOUT=3600

# Paths - use $WORKSPACE instead of hardcoded paths
readonly VENV_PATH="${VENV_PATH:-$WORKSPACE/venv}"
readonly OCS_CI_PATH="${OCS_CI_PATH:-$WORKSPACE/ocs-upi-kvm/src/ocs-ci}"
readonly CLUSTER_PATH="${CLUSTER_PATH:-$WORKSPACE}"
readonly OCS_CI_CONF="${OCS_CI_CONF:-$WORKSPACE/ocs-ci-conf.yaml}"

#########################################################
# VARIABLES
#########################################################
source helper/parameters.sh
export OCS_VERSION="${OCS_VERSION}"

# Can be overridden while running
# Example: TEST_MARKER=tier4b RUN_MODE=object ./test.sh
TEST_MARKER="${TEST_MARKER:-tier2}"
RUN_MODE="${RUN_MODE:-non-object}"
PARALLEL_JOBS="${PARALLEL_JOBS:-1}"
DRY_RUN="${DRY_RUN:-false}"

readonly BASE_DIR="$(pwd)"
readonly LOG_BASE_DIR="${BASE_DIR}/${TEST_MARKER}_${RUN_MODE}_test_results"
readonly SUMMARY_FILE="${BASE_DIR}/${TEST_MARKER}_${RUN_MODE}_test_summary.log"
readonly REPORT_FILE="${BASE_DIR}/${TEST_MARKER}_${RUN_MODE}_final_test_report.txt"

#########################################################
# UTILITY FUNCTIONS
#########################################################

log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
}

log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
}

log_warn() {
    echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
}

show_usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS]

OCS-CI Automated Test Execution Script v${SCRIPT_VERSION}

OPTIONS:
    -h, --help              Show this help message
    -m, --marker MARKER     Test marker (default: tier2)
    -r, --run-mode MODE     Run mode: object|non-object|all (default: non-object)
    -p, --parallel JOBS     Number of parallel jobs (default: 1)
    -d, --dry-run           Show what would be executed without running
    -v, --version           Show script version

ENVIRONMENT VARIABLES:
    TEST_MARKER             Override test marker
    RUN_MODE                Override run mode
    PARALLEL_JOBS           Override parallel jobs
    DRY_RUN                 Enable dry-run mode (true/false)
    VENV_PATH               Path to virtual environment
    OCS_CI_PATH             Path to ocs-ci directory
    CLUSTER_PATH            Path to cluster configuration
    OCS_CI_CONF             Path to ocs-ci configuration file

EXAMPLES:
    # Run tier2 tests in non-object mode
    $SCRIPT_NAME

    # Run tier4b tests in object mode
    $SCRIPT_NAME -m tier4b -r object

    # Run all tests (non-object phase first, then object phase)
    $SCRIPT_NAME -r all

    # Dry run to see what would be executed
    $SCRIPT_NAME -d

    # Run with 4 parallel jobs
    $SCRIPT_NAME -p 4

EOF
    exit 0
}

check_dependencies() {
    local missing_deps=()

    for cmd in oc python3 find grep sed awk; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing required commands: ${missing_deps[*]}"
        exit 1
    fi

    if [[ ! -d "$VENV_PATH" ]]; then
        log_error "Virtual environment not found at: $VENV_PATH"
        exit 1
    fi

    if [[ ! -d "$OCS_CI_PATH" ]]; then
        log_error "OCS-CI directory not found at: $OCS_CI_PATH"
        exit 1
    fi

    if [[ ! -f "$OCS_CI_CONF" ]]; then
        log_error "OCS-CI configuration not found at: $OCS_CI_CONF"
        exit 1
    fi
}

validate_run_mode() {
    case "$RUN_MODE" in
        object|non-object|all)
            return 0
            ;;
        *)
            log_error "Invalid RUN_MODE: $RUN_MODE"
            log_error "Allowed values: object | non-object | all"
            exit 1
            ;;
    esac
}

cleanup_on_exit() {
    local exit_code=$?
    # Exit code 5 means no tests were collected -- not a script failure
    if [[ $exit_code -ne 0 && $exit_code -ne 5 ]]; then
        log_warn "Script interrupted with exit code: $exit_code"
        log_info "Partial results may be available in: $LOG_BASE_DIR"
    fi
}

#########################################################
# ENVIRONMENT SETUP
#########################################################

setup_environment() {
    log_info "Setting up environment..."

    # shellcheck disable=SC1091
    source "$VENV_PATH/bin/activate" || {
        log_error "Failed to activate virtual environment"
        exit 1
    }

    cd "$OCS_CI_PATH" || {
        log_error "Unable to change directory to $OCS_CI_PATH"
        exit 1
    }

    mkdir -p "$LOG_BASE_DIR"
    > "$SUMMARY_FILE"
    > "$REPORT_FILE"

    log_info "Environment setup complete"
}

#########################################################
# CEPH HEALTH CHECK
#########################################################

get_tool_pod() {
    local pod_name
    pod_name=$(oc get pods -n openshift-storage 2>/dev/null \
        | awk '/rook-ceph-tools/ && $3 == "Running" {print $1; exit}')

    echo "$pod_name"
}

ceph_health_check() {
    log_info "Checking Ceph health..."

    local tools_pod
    tools_pod=$(get_tool_pod)

    if [[ -z "$tools_pod" ]]; then
        log_warn "rook-ceph-tools pod not found or not running"
        return 1
    fi

    local health
    health=$(oc -n openshift-storage rsh "$tools_pod" ceph health 2>/dev/null | tr -d '[:space:]')

    if [[ "$health" == "HEALTH_OK" ]]; then
        log_info "Ceph Health: HEALTH_OK"
        return 0
    else
        log_warn "Ceph Health: $health"
        log_info "Archiving crash reports..."
        oc -n openshift-storage rsh "$tools_pod" ceph crash archive-all >/dev/null 2>&1 || true
        log_info "Waiting ${CEPH_HEALTH_WAIT}s for cluster to stabilize..."
        sleep "$CEPH_HEALTH_WAIT"
        return 1
    fi
}

#########################################################
# DIRECTORIES TO SEARCH
#########################################################

readonly TEST_DIRS=(
    tests/functional/data_replication_separation
    tests/functional/external_mode
    tests/functional/monitoring
    tests/functional/object
    tests/functional/pod_and_daemons
    tests/functional/pv
    tests/functional/tlsprofile
    tests/functional/upgrade
    tests/functional/z_cluster
    tests/functional/deployment
    tests/functional/lvmo
    tests/functional/odf-cli
    tests/functional/storageclass
    tests/functional/workloads
)

#########################################################
# DISCOVER TEST FILES
#########################################################

# Collect test files for a given phase: "object" or "non-object".
# Prints one file path per line to stdout (safe for mapfile; no logging here).
_collect_phase_files() {
    local phase="$1"

    for dir in "${TEST_DIRS[@]}"; do
        if [[ ! -d "$dir" ]]; then
            continue
        fi

        case "$phase" in
            object)
                [[ "$dir" != */object ]] && continue
                ;;
            non-object)
                [[ "$dir" == */object ]] && continue
                ;;
        esac

        find "$dir" -type f -name "test*.py" | sort
    done
}

# Prints discovered test file paths to stdout, one per line.
# All log_info calls go to stderr so mapfile captures only file paths.
discover_test_files() {
    log_info "Discovering test files (mode: $RUN_MODE)..."

    case "$RUN_MODE" in
        object)
            _collect_phase_files object
            ;;
        non-object)
            _collect_phase_files non-object
            ;;
        all)
            # non-object files first, then object files
            local non_obj_count obj_count
            non_obj_count=$(_collect_phase_files non-object | wc -l)
            obj_count=$(_collect_phase_files object | wc -l)
            log_info "Discovered ${non_obj_count} non-object file(s) and ${obj_count} object file(s)"
            _collect_phase_files non-object
            _collect_phase_files object
            ;;
    esac
}

#########################################################
# HEADER / PHASE BANNER
#########################################################

# Write a phase separator banner into the summary file
write_phase_banner() {
    local phase="$1"
    {
        echo
        echo "========================================================="
        echo "  PHASE: $(echo "$phase" | tr '[:lower:]' '[:upper:]') TESTS"
        echo "========================================================="
        echo
    } >> "$SUMMARY_FILE"
}

write_header() {
    {
        echo "========================================================="
        echo "OCS-CI Automated Execution Summary"
        echo "========================================================="
        echo "Script Version : $SCRIPT_VERSION"
        echo "Started        : $(date)"
        echo "OCS Version    : $OCS_VERSION"
        echo "Marker         : $TEST_MARKER"
        echo "Run Mode       : $RUN_MODE"
        echo "Parallel Jobs  : $PARALLEL_JOBS"
        echo "Dry Run        : $DRY_RUN"
        echo "========================================================="
        echo
    } >> "$SUMMARY_FILE"
}

#########################################################
# EXECUTE SINGLE TEST
#########################################################

execute_test() {
    local test_file="$1"
    local test_dir test_name safe_dir current_log_dir log_file xml_file

    test_dir=$(dirname "$test_file")
    test_name=$(basename "$test_file" .py)
    safe_dir=$(echo "$test_dir" | tr '/' '_')
    current_log_dir="${LOG_BASE_DIR}/${safe_dir}/${test_name}"

    mkdir -p "$current_log_dir"

    log_file="${current_log_dir}/run.log"
    xml_file="${current_log_dir}/results.xml"

    log_info "Running: $test_file"
    log_info "Log Dir: $current_log_dir"

    {
        echo
        echo "FILE: $test_file"
    } >> "$SUMMARY_FILE"

    # Ceph health check before test
    ceph_health_check || log_warn "Ceph health check failed, continuing anyway"

    local start_time end_time duration rc
    start_time=$(date +%s)

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would execute: run-ci for $test_file"
        rc=0
        duration=0
    else
        # Execute test with timeout.
        # Use || true so set -e does not abort the script on non-zero exit codes.
        timeout "$COMMAND_TIMEOUT" run-ci \
            --ocs-version "$OCS_VERSION" \
            --ocsci-conf conf/ocsci/production_powervs_upi.yaml \
            --ocsci-conf conf/ocsci/lso_enable_rotational_disks.yaml \
            --ocsci-conf "$OCS_CI_CONF" \
            --cluster-name ocstest \
            --cluster-path "$CLUSTER_PATH" \
            "$test_file" \
            -m "$TEST_MARKER" \
            -vv \
            -rA \
            --junitxml="$xml_file" \
            2>&1 | tee "$log_file" || true

        rc=${PIPESTATUS[0]}

        end_time=$(date +%s)
        duration=$((end_time - start_time))
    fi

    # Exit code meanings (pytest / run-ci):
    #   0 = all tests passed
    #   1 = some tests failed
    #   2 = interrupted
    #   3 = internal error
    #   4 = command-line usage error
    #   5 = no tests collected (marker matched nothing) -- treat as skip
    if [[ "$rc" -eq 5 ]]; then
        log_warn "No tests collected in $test_file (marker: $TEST_MARKER) -- skipping"
    fi

    log_info "Exit Code: $rc"
    log_info "Duration: ${duration}s"

    {
        echo
        echo "EXIT CODE: $rc"
        echo "DURATION: ${duration}s"
        echo
        echo "TEST CASE RESULTS:"
    } >> "$SUMMARY_FILE"

    # Parse test results (rc=5 → record as NO-TESTS-COLLECTED, not an error)
    if [[ "$rc" -eq 5 ]]; then
        echo "SKIP  [NO-TESTS-COLLECTED] $test_file" >> "$SUMMARY_FILE"
    else
        parse_test_results "$xml_file" "$log_file"
    fi

    # File summary
    local summary
    if [[ "$DRY_RUN" != "true" ]]; then
        if [[ "$rc" -eq 5 ]]; then
            summary="no tests ran (no tests collected for marker: $TEST_MARKER)"
        else
            summary=$(grep -E "passed|failed|error|errors|skipped|deselected" "$log_file" 2>/dev/null | tail -1 || true)
        fi
    else
        summary="[DRY-RUN] No execution performed"
    fi

    {
        echo
        if [[ -n "$summary" ]]; then
            echo "SUMMARY: $summary"
        else
            echo "SUMMARY: No pytest summary found."
        fi
        echo "--------------------------------------------------------"
    } >> "$SUMMARY_FILE"
}

#########################################################
# PARSE TEST RESULTS
#########################################################

parse_test_results() {
    local xml_file="$1"
    local log_file="$2"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "SKIP  [DRY-RUN] Test execution skipped" >> "$SUMMARY_FILE"
        return
    fi

    if [[ -f "$xml_file" ]]; then
        # Parse XML results using Python
        # Output format: tests.functional.module.ClassName::test_method
        python3 - "$xml_file" >> "$SUMMARY_FILE" <<'EOF'
import sys
import xml.etree.ElementTree as ET

xml_file = sys.argv[1]

def to_dot_format(classname, name):
    """
    Convert pytest classname + name to slash-path format expected by run-ci.

    pytest XML stores classname as a fully dot-separated string:
      classname = "tests.functional.object.mcg.test_write_to_bucket.TestBucketIO"
      name      = "test_mcg_data_deduplication[AWS-OC-1]"

    We want:
      tests/functional/object/mcg/test_write_to_bucket.py::TestBucketIO::test_mcg_data_deduplication[AWS-OC-1]
    """
    parts = classname.replace("\\", ".").replace("/", ".").split(".")

    # The last part starting with an uppercase letter is the class name.
    # Everything before it is the module path (dots -> slashes).
    if len(parts) >= 2 and parts[-1][:1].isupper():
        class_name = parts[-1]
        module_path = "/".join(parts[:-1]) + ".py"
        return f"{module_path}::{class_name}::{name}"
    else:
        # No class suffix — the whole classname is the module path
        module_path = "/".join(parts) + ".py"
        return f"{module_path}::{name}"

try:
    tree = ET.parse(xml_file)
    root = tree.getroot()

    for tc in root.iter("testcase"):
        classname = tc.attrib.get("classname", "")
        name = tc.attrib.get("name", "")
        testcase = to_dot_format(classname, name)

        if tc.find("failure") is not None:
            print(f"FAIL  {testcase}")
        elif tc.find("error") is not None:
            print(f"ERROR {testcase}")
        elif tc.find("skipped") is not None:
            print(f"SKIP  {testcase}")
        else:
            print(f"PASS  {testcase}")

except Exception as ex:
    print(f"XML_PARSE_ERROR {ex}", file=sys.stderr)
EOF
    elif [[ -f "$log_file" ]]; then
        # Fallback: parse pytest terminal output and convert path::Class::method
        # to dot-separated format: module.Class::method
        _convert_log_line() {
            # e.g. "PASSED tests/functional/object/mcg/test_write_to_bucket.py::TestBucketIO::test_foo"
            # ->   "PASS  tests.functional.object.mcg.test_write_to_bucket.TestBucketIO::test_foo"
            sed -E 's|([^ ]+/)(([^/:]+)\.py)::([^:]+)::|'$'\1''\3.\4::|g' \
            | sed 's|/|.|g'
        }
        grep '^PASSED '  "$log_file" 2>/dev/null \
            | sed 's/^PASSED /PASS  /' | _convert_log_line >> "$SUMMARY_FILE" || true
        grep '^FAILED '  "$log_file" 2>/dev/null \
            | sed 's/^FAILED /FAIL  /' | _convert_log_line >> "$SUMMARY_FILE" || true
        grep '^ERROR '   "$log_file" 2>/dev/null \
            | _convert_log_line >> "$SUMMARY_FILE" || true
        grep '^SKIPPED ' "$log_file" 2>/dev/null \
            | sed 's/^SKIPPED /SKIP  /' | _convert_log_line >> "$SUMMARY_FILE" || true
    fi
}

#########################################################
# COLLECT FINAL COUNTS
#########################################################

collect_final_counts() {
    # Use awk for efficient single-pass counting
    awk '
        /^PASS /  { passed++ }
        /^FAIL /  { failed++ }
        /^ERROR / { errors++ }
        /^SKIP /  { skipped++ }
        END {
            print passed+0, failed+0, errors+0, skipped+0
        }
    ' "$SUMMARY_FILE"
}

#########################################################
# FINAL REPORT
#########################################################

generate_final_report() {
    local total_files="$1"
    local passed_count failed_count error_count skipped_count total_tests

    read -r passed_count failed_count error_count skipped_count < <(collect_final_counts)
    total_tests=$((passed_count + failed_count + error_count + skipped_count))

    {
        echo
        echo "============================================================"
        echo "                OCS-CI TEST EXECUTION REPORT"
        echo "============================================================"
        echo
        echo "Script Version   : $SCRIPT_VERSION"
        echo "Execution Date   : $(date)"
        echo "OCS Version      : $OCS_VERSION"
        echo "Marker           : $TEST_MARKER"
        echo "Run Mode         : $RUN_MODE"
        echo "Parallel Jobs    : $PARALLEL_JOBS"
        echo "Dry Run          : $DRY_RUN"
        echo
        echo "Total Test Files : $total_files"
        echo "Total Test Cases : $total_tests"
        echo "Passed           : $passed_count"
        echo "Failed           : $failed_count"
        echo "Errors           : $error_count"
        echo "Skipped          : $skipped_count"
        echo
        echo "============================================================"
        echo "FAILED TEST CASES ($failed_count)"
        echo "============================================================"

        grep "^FAIL " "$SUMMARY_FILE" 2>/dev/null | sed 's/^FAIL  //' || echo "None"

        echo
        echo "============================================================"
        echo "ERROR TEST CASES ($error_count)"
        echo "============================================================"

        grep "^ERROR " "$SUMMARY_FILE" 2>/dev/null | sed 's/^ERROR //' || echo "None"

        echo
        echo "============================================================"
        echo "SKIPPED TEST CASES ($skipped_count)"
        echo "============================================================"

        grep "^SKIP " "$SUMMARY_FILE" 2>/dev/null | sed 's/^SKIP  //' || echo "None"

        echo
        echo "============================================================"
        echo "PASSED TEST CASES ($passed_count)"
        echo "============================================================"

        grep "^PASS " "$SUMMARY_FILE" 2>/dev/null | sed 's/^PASS  //' || echo "None"

        echo
        echo "============================================================"
        echo "FAILED + ERROR RERUN LIST"
        echo "============================================================"

        grep -E "^(FAIL|ERROR) " "$SUMMARY_FILE" 2>/dev/null \
            | sed 's/^FAIL  //' \
            | sed 's/^ERROR //' || echo "None"

        echo
        echo "============================================================"
        echo "REPORT FILES"
        echo "============================================================"
        echo "Summary Report : $SUMMARY_FILE"
        echo "Final Report   : $REPORT_FILE"
        echo "Log Directory  : $LOG_BASE_DIR"

        echo
        echo "Completed : $(date)"
        echo "============================================================"

    } | tee "$REPORT_FILE"
}

#########################################################
# MAIN EXECUTION
#########################################################

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_usage
                ;;
            -m|--marker)
                TEST_MARKER="$2"
                shift 2
                ;;
            -r|--run-mode)
                RUN_MODE="$2"
                shift 2
                ;;
            -p|--parallel)
                PARALLEL_JOBS="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN="true"
                shift
                ;;
            -v|--version)
                echo "$SCRIPT_NAME version $SCRIPT_VERSION"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                ;;
        esac
    done

    # Setup cleanup trap
    trap cleanup_on_exit EXIT INT TERM

    # Validate configuration
    validate_run_mode
    check_dependencies

    # Setup environment
    setup_environment

    # Write header
    write_header

    # Discover test files -- one path per line, safe for spaces
    local test_files=()
    mapfile -t test_files < <(discover_test_files)
    local total_files=${#test_files[@]}

    log_info "========================================"
    log_info "Execution Configuration"
    log_info "========================================"
    log_info "Marker      : $TEST_MARKER"
    log_info "Run Mode    : $RUN_MODE"
    log_info "Directories : ${#TEST_DIRS[@]}"
    log_info "Test Files  : $total_files"
    log_info "Parallel    : $PARALLEL_JOBS"
    log_info "Dry Run     : $DRY_RUN"
    log_info "========================================"

    if [[ "$total_files" -eq 0 ]]; then
        log_error "No test files found."
        exit 1
    fi

    # Execute tests
    log_info "Starting test execution..."

    if [[ "$RUN_MODE" == "all" ]]; then
        # Two-phase execution: non-object first, then object
        local non_obj_files=() obj_files=()
        mapfile -t non_obj_files < <(_collect_phase_files non-object)
        mapfile -t obj_files     < <(_collect_phase_files object)

        log_info "========================================"
        log_info "Phase 1: Non-Object Tests (${#non_obj_files[@]} file(s))"
        log_info "========================================"
        write_phase_banner "non-object"

        if [[ "$PARALLEL_JOBS" -gt 1 ]]; then
            printf '%s\n' "${non_obj_files[@]}" | xargs -P "$PARALLEL_JOBS" -I {} bash -c \
                "$(declare -f execute_test parse_test_results ceph_health_check get_tool_pod log_info log_warn log_error); execute_test '{}'"
        else
            for test_file in "${non_obj_files[@]}"; do
                execute_test "$test_file"
            done
        fi

        log_info "========================================"
        log_info "Phase 1 complete. Checking Ceph health before Phase 2..."
        log_info "========================================"
        ceph_health_check || log_warn "Ceph health check failed between phases, continuing anyway"

        log_info "========================================"
        log_info "Phase 2: Object Tests (${#obj_files[@]} file(s))"
        log_info "========================================"
        write_phase_banner "object"

        if [[ "$PARALLEL_JOBS" -gt 1 ]]; then
            printf '%s\n' "${obj_files[@]}" | xargs -P "$PARALLEL_JOBS" -I {} bash -c \
                "$(declare -f execute_test parse_test_results ceph_health_check get_tool_pod log_info log_warn log_error); execute_test '{}'"
        else
            for test_file in "${obj_files[@]}"; do
                execute_test "$test_file"
            done
        fi

    elif [[ "$PARALLEL_JOBS" -gt 1 ]]; then
        log_info "Running tests in parallel (jobs: $PARALLEL_JOBS)"
        printf '%s\n' "${test_files[@]}" | xargs -P "$PARALLEL_JOBS" -I {} bash -c \
            "$(declare -f execute_test parse_test_results ceph_health_check get_tool_pod log_info log_warn log_error); execute_test '{}'"
    else
        for test_file in "${test_files[@]}"; do
            execute_test "$test_file"
        done
    fi

    # Generate final report
    generate_final_report "$total_files"

    # Console summary
    local passed_count failed_count error_count skipped_count total_tests
    read -r passed_count failed_count error_count skipped_count < <(collect_final_counts)
    total_tests=$((passed_count + failed_count + error_count + skipped_count))

    log_info "=================================================="
    log_info "Execution Completed Successfully"
    log_info "=================================================="
    log_info "Run Mode       : $RUN_MODE"
    log_info "Marker         : $TEST_MARKER"
    log_info "Total Files    : $total_files"
    log_info "Total Tests    : $total_tests"
    log_info "Passed         : $passed_count"
    log_info "Failed         : $failed_count"
    log_info "Errors         : $error_count"
    log_info "Skipped        : $skipped_count"

    if [[ "$RUN_MODE" == "all" ]]; then
        local non_obj_files=() obj_files=()
        mapfile -t non_obj_files < <(_collect_phase_files non-object)
        mapfile -t obj_files     < <(_collect_phase_files object)
        log_info "--------------------------------------------------"
        log_info "Phase 1 (non-object) files : ${#non_obj_files[@]}"
        log_info "Phase 2 (object) files     : ${#obj_files[@]}"
    fi

    log_info ""
    log_info "Summary : $SUMMARY_FILE"
    log_info "Report  : $REPORT_FILE"
    log_info "Logs    : $LOG_BASE_DIR"
    log_info "=================================================="
}

# Run main function
main "$@"



