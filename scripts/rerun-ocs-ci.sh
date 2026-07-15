#!/bin/bash

# Rerun failed OCS-CI test cases extracted from a pytest log file.
#
# Usage (run from the ocs-upi-kvm/scripts directory):
#
#   export OCS_VERSION=4.15
#   export TIER_TEST=1
#   ./rerun-ocs-ci.sh <path-to-pytest-log-file>
#
# Optional overrides (all have sensible defaults):
#   export FILE_PATH=$WORKSPACE/ocs-upi-kvm/src/ocs-ci   # default
#   export LOG_DIR=$WORKSPACE/rerun-logs                  # default
#   export SUMMARY_FILE=$WORKSPACE/rerun-logs/summary.txt # default
#
# The script will:
#   1. Parse the "short test summary info" section of the provided log file.
#   2. Extract only FAILED lines (ERROR lines are skipped).
#   3. Strip the leading "FAILED " keyword; skip any /ui/ tests.
#   4. Write the cleaned test-case list to ${LOG_DIR}/tier-${TIER_TEST}-rerun.log
#   5. For every extracted test case:
#        a. Check Ceph health (HEALTH_OK required to proceed).
#        b. Run the individual test case via run-ci.
#        c. Capture Pass/Fail/Skip/Error/Deselect status from the log.
#        d. Append a summary line to ${SUMMARY_FILE}.

# ---------------------------------------------------------------------------
# Guard: must be called from ocs-upi-kvm/scripts
# ---------------------------------------------------------------------------
if [ ! -e helper/parameters.sh ]; then
    echo "ERROR: This script must be invoked from the directory ocs-upi-kvm/scripts"
    exit 1
fi

source helper/parameters.sh

# ---------------------------------------------------------------------------
# Required environment variables
# ---------------------------------------------------------------------------
: "${OCS_VERSION:?ERROR: OCS_VERSION is not set (e.g. export OCS_VERSION=4.15)}"
: "${TIER_TEST:?ERROR: TIER_TEST is not set (e.g. export TIER_TEST=1)}"

# ---------------------------------------------------------------------------
# Optional environment variables — all have defaults derived from $WORKSPACE
# ---------------------------------------------------------------------------
FILE_PATH="${FILE_PATH:-$WORKSPACE/ocs-upi-kvm/src/ocs-ci}"
LOG_DIR="${LOG_DIR:-$WORKSPACE/rerun-logs}"
SUMMARY_FILE="${SUMMARY_FILE:-$LOG_DIR/summary.txt}"

# ---------------------------------------------------------------------------
# Input argument: path to the pytest log file
# ---------------------------------------------------------------------------
INPUT_LOG="$1"

if [ -z "$INPUT_LOG" ]; then
    echo "Usage: $0 <path-to-pytest-log-file>"
    echo ""
    echo "Required env vars:  OCS_VERSION, TIER_TEST"
    echo "Optional env vars:"
    echo "  FILE_PATH    (default: \$WORKSPACE/ocs-upi-kvm/src/ocs-ci)"
    echo "  LOG_DIR      (default: \$WORKSPACE/rerun-logs)"
    echo "  SUMMARY_FILE (default: \$LOG_DIR/summary.txt)"
    exit 1
fi

if [ ! -f "$INPUT_LOG" ]; then
    echo "ERROR: Input log file not found: $INPUT_LOG"
    exit 1
fi

# ---------------------------------------------------------------------------
# Derived paths
# ---------------------------------------------------------------------------
OCS_UPI_DIR="$WORKSPACE/ocs-upi-kvm"
BASE_DIR="$WORKSPACE"
OCS_CI_CONF="${OCS_CI_CONF:-$WORKSPACE/ocs-ci-conf.yaml}"
RERUN_LOG_DIR="${LOG_DIR}/rerun-tier${TIER_TEST}"
INPUT_FILE="${LOG_DIR}/tier-${TIER_TEST}-rerun.log"

# ---------------------------------------------------------------------------
# Ensure output directories exist
# ---------------------------------------------------------------------------
mkdir -p "$LOG_DIR"
mkdir -p "$RERUN_LOG_DIR"

# ---------------------------------------------------------------------------
# Step 1: Extract failed test cases from the provided log file
# ---------------------------------------------------------------------------
echo "======================================================================="
echo "Extracting failed test cases from: $INPUT_LOG"
echo "======================================================================="

if grep -q "short test summary info" "$INPUT_LOG"; then
    # Take only the LAST "short test summary info" block (handles concatenated
    # logs), keep only FAILED lines, drop /ui/ tests, strip the "FAILED "
    # prefix, remove trailing whitespace, and deduplicate.
    awk '/short test summary info/{found=1; block=""} found{block=block $0 "\n"} END{printf "%s", block}' "$INPUT_LOG" \
        | grep "^FAILED " \
        | grep -v "/ui/" \
        | sed 's/^FAILED[[:space:]]*//' \
        | sed 's/[[:space:]]*$//' \
        | sort -u \
        > "$INPUT_FILE"
else
    echo "WARNING: 'short test summary info' section not found in $INPUT_LOG"
    echo "  → Cannot extract test cases. Exiting."
    exit 1
fi

COUNT=$(wc -l < "$INPUT_FILE" | tr -d ' ')
echo "  → $COUNT failed test case(s) written to: $INPUT_FILE"
echo ""

if [ "$COUNT" -eq 0 ]; then
    echo "No failed test cases found (after filtering /ui/ tests). Nothing to rerun."
    exit 0
fi

echo "Test cases to rerun:"
cat "$INPUT_FILE"
echo ""

# ---------------------------------------------------------------------------
# Step 2: Activate the Python virtual environment (required for run-ci)
# ---------------------------------------------------------------------------
if [ ! -f "$WORKSPACE/venv/bin/activate" ]; then
    echo "ERROR: Python venv not found at $WORKSPACE/venv — run setup-ocs-ci.sh first"
    exit 1
fi

source "$WORKSPACE/venv/bin/activate"

export PATH="$WORKSPACE/bin:$PATH"
export KUBECONFIG="$WORKSPACE/auth/kubeconfig"

# ---------------------------------------------------------------------------
# Step 3: Initialise summary file header (only when creating a fresh file)
# ---------------------------------------------------------------------------
if [ ! -f "$SUMMARY_FILE" ]; then
    echo "Test Case | Tier | Status" > "$SUMMARY_FILE"
    echo "--------- | ---- | ------" >> "$SUMMARY_FILE"
fi

# ---------------------------------------------------------------------------
# Step 4: Iterate over extracted test cases and rerun each one
# ---------------------------------------------------------------------------
echo "======================================================================="
echo "Starting rerun of Tier ${TIER_TEST} failed tests"
echo "======================================================================="

pushd "${FILE_PATH}" > /dev/null

while IFS= read -r TEST_CASE || [ -n "$TEST_CASE" ]; do

    # Skip blank lines
    [ -z "$TEST_CASE" ] && continue

    # Validate test-case name length (guard against partial/garbled lines)
    LOG_FILE_NAME=$(awk -F '::' '{print $NF}' <<<"$TEST_CASE" | tr -d '[:space:]')
    SIZE=${#LOG_FILE_NAME}
    if [[ $SIZE -le 5 ]]; then
        echo "Skipping invalid test case (name too short): $TEST_CASE"
        continue
    fi

    echo "-----------------------------------------------------------------------"
    echo "Next test: $TEST_CASE"

    # -------------------------------------------------------------------
    # Ceph health check — retry for up to 10 minutes before aborting
    # -------------------------------------------------------------------
    CEPH_HEALTH_TIMEOUT=600   # 10 minutes in seconds
    CEPH_HEALTH_INTERVAL=30   # poll every 30 seconds
    CEPH_HEALTH_ELAPSED=0
    CEPH_HEALTH=""

    while true; do
        CEPH_HEALTH=$(oc -n openshift-storage exec deploy/rook-ceph-tools -- ceph health 2>/dev/null || true)
        echo "  Ceph health: $CEPH_HEALTH"

        if [ "$CEPH_HEALTH" = "HEALTH_OK" ]; then
            break
        fi

        if [ "$CEPH_HEALTH_ELAPSED" -ge "$CEPH_HEALTH_TIMEOUT" ]; then
            echo "ERROR: Ceph cluster is not HEALTH_OK after ${CEPH_HEALTH_TIMEOUT}s — aborting rerun."
            echo "  Failed at: $TEST_CASE"
            deactivate
            popd > /dev/null
            exit 1
        fi

        echo "  Ceph not healthy yet — retrying in ${CEPH_HEALTH_INTERVAL}s (elapsed: ${CEPH_HEALTH_ELAPSED}s / ${CEPH_HEALTH_TIMEOUT}s)"
        sleep "$CEPH_HEALTH_INTERVAL"
        CEPH_HEALTH_ELAPSED=$(( CEPH_HEALTH_ELAPSED + CEPH_HEALTH_INTERVAL ))
    done

    # -------------------------------------------------------------------
    # Execute the test case
    # -------------------------------------------------------------------
    CURRENT_LOG="${RERUN_LOG_DIR}/${LOG_FILE_NAME}.log"
    echo "  Running test, logging to: $CURRENT_LOG"

    nohup run-ci \
        -m "tier${TIER_TEST}" \
        --ocs-version "$OCS_VERSION" \
        --ocsci-conf "${OCS_UPI_DIR}/src/ocs-ci/conf/ocsci/production_powervs_upi.yaml" \
        --ocsci-conf "${OCS_UPI_DIR}/src/ocs-ci/conf/ocsci/lso_enable_rotational_disks.yaml" \
        --ocsci-conf "${OCS_CI_CONF}" \
        --cluster-name "ocstest" \
        --cluster-path "${BASE_DIR}/" \
        --collect-logs \
        "$TEST_CASE" \
        | tee "${CURRENT_LOG}" 2>&1

    # Capture exit code of run-ci (first command in the pipeline)
    EXIT_CODE=${PIPESTATUS[0]}

    # -------------------------------------------------------------------
    # Determine status from pytest summary line in the log
    # -------------------------------------------------------------------
    if grep -qE "={2,}.*[0-9]+ error.*={2,}" "$CURRENT_LOG"; then
        STATUS="Error"
    elif grep -qE "={2,}.*[0-9]+ failed.*={2,}" "$CURRENT_LOG"; then
        STATUS="Fail"
    elif grep -qE "={2,}.*[0-9]+ skipped.*={2,}" "$CURRENT_LOG"; then
        STATUS="Skipped"
    elif grep -qE "={2,}.*[0-9]+ deselected.*={2,}" "$CURRENT_LOG"; then
        STATUS="Deselect"
    elif [ "$EXIT_CODE" -eq 0 ]; then
        STATUS="Pass"
    else
        STATUS="Fail"
    fi

    echo "  Result: $STATUS (exit code: $EXIT_CODE)"
    echo "$TEST_CASE | Tier $TIER_TEST | $STATUS" >> "$SUMMARY_FILE"

    echo "Sleeping 10 seconds before next test execution..."
    sleep 10

done < <(cat < "$INPUT_FILE")

popd > /dev/null
deactivate

# ---------------------------------------------------------------------------
# Step 5: Print final summary
# ---------------------------------------------------------------------------
echo ""
echo "======================================================================="
echo "Rerun Summary"
echo "======================================================================="
cat "$SUMMARY_FILE"
echo ""
echo "Full summary written to : $SUMMARY_FILE"
echo "Individual test logs in : $RERUN_LOG_DIR/"
