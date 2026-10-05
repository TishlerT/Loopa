#!/bin/bash
# Run selected tests and retain every attempt's evidence. No prior files are removed.
# Deliberately avoid `set -e`: even failed Xcode commands need evidence and a verdict.
set -u
set -o pipefail

usage() {
    cat <<'HELP'
Usage: ./run_tests.sh [options]
  --unit                  Run LoopaTests only
  --ui                    Run LoopaUITests only (default)
  --all                   Run both test targets
  --test Class/testMethod  Select a test within the chosen target
                          With --all, use Target/Class/testMethod
  --destination SPEC      Xcode destination (default: platform=iOS Simulator,name=iPhone 16 Pro)
  --output-dir DIRECTORY  Parent for unique run directories (default: ios/build/test-results)
  --expected-tests COUNT  Require exactly COUNT tests (positive integer)
  --quick                 Omit raw JSON from console; still save and validate it
  -h, --help              Show this help

All selected tests are required: skips and expected failures fail this gate.
Each run saves TestResults.xcresult, xcodebuild.log, summary.json,
xcresulttool.log and verification.json in a new run-* directory.
To inspect a bundle later, pass its printed path explicitly to parse_results.sh.
HELP
}

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }
require_value() {
    [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || die "$1 requires a value"
}

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)" || exit 1
PROJECT_FILE="$PROJECT_DIR/Loopa.xcodeproj"
DESTINATION="platform=iOS Simulator,name=iPhone 16 Pro"
OUTPUT_DIR="$PROJECT_DIR/build/test-results"
TEST_TARGET="LoopaUITests"
SPECIFIC_TEST=""
EXPECTED_TESTS=""
QUICK_MODE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --unit) TEST_TARGET="LoopaTests"; shift ;;
        --ui) TEST_TARGET="LoopaUITests"; shift ;;
        --all) TEST_TARGET="all"; shift ;;
        --quick) QUICK_MODE=true; shift ;;
        --test) require_value "$@"; SPECIFIC_TEST="$2"; shift 2 ;;
        --destination) require_value "$@"; DESTINATION="$2"; shift 2 ;;
        --output-dir) require_value "$@"; OUTPUT_DIR="$2"; shift 2 ;;
        --expected-tests)
            require_value "$@"
            [[ "$2" =~ ^[1-9][0-9]*$ ]] || die "--expected-tests must be a positive integer"
            EXPECTED_TESTS="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) die "Unknown option: $1 (see --help)" ;;
    esac
done

TEST_SELECTORS=()
if [[ "$TEST_TARGET" == "all" ]]; then
    if [[ -n "$SPECIFIC_TEST" ]]; then
        case "$SPECIFIC_TEST" in
            LoopaTests/?*|LoopaUITests/?*) TEST_SELECTORS=("-only-testing:$SPECIFIC_TEST") ;;
            *) die "--all --test requires LoopaTests/ or LoopaUITests/ followed by a test selector" ;;
        esac
    else
        TEST_SELECTORS=("-only-testing:LoopaTests" "-only-testing:LoopaUITests")
    fi
else
    TEST_SELECTORS=("-only-testing:$TEST_TARGET${SPECIFIC_TEST:+/$SPECIFIC_TEST}")
fi

for dependency in xcodebuild xcrun python3; do
    command -v "$dependency" >/dev/null 2>&1 || die "Required command not found: $dependency"
done
mkdir -p "$OUTPUT_DIR" || die "Cannot create output directory: $OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)" || exit 1
# mktemp reserves the directory atomically, including for simultaneous invocations.
RUN_DIR="$(mktemp -d "$OUTPUT_DIR/run-$(date -u +%Y%m%dT%H%M%SZ).XXXXXX")" || die "Cannot reserve run directory"
RESULT_BUNDLE="$RUN_DIR/TestResults.xcresult"
LOG_FILE="$RUN_DIR/xcodebuild.log"
SUMMARY_FILE="$RUN_DIR/summary.json"
PARSER_LOG="$RUN_DIR/xcresulttool.log"
VERIFICATION_FILE="$RUN_DIR/verification.json"
trap 'printf "\nInterrupted; partial artifacts retained at %s\n" "$RUN_DIR" >&2; exit 130' INT
trap 'printf "\nTerminated; partial artifacts retained at %s\n" "$RUN_DIR" >&2; exit 143' TERM

printf 'Loopa Test Runner\nProject: %s\nTarget: %s\nDestination: %s\n' "$PROJECT_FILE" "$TEST_TARGET" "$DESTINATION"
printf 'Result Bundle: %s\nLog File: %s\nSummary JSON: %s\nVerification JSON: %s\n\n' \
    "$RESULT_BUNDLE" "$LOG_FILE" "$SUMMARY_FILE" "$VERIFICATION_FILE"

# An array keeps paths, destination strings and test names literal, with no eval.
TEST_CMD=(xcodebuild test -project "$PROJECT_FILE" -scheme Loopa
    -destination "$DESTINATION" -resultBundlePath "$RESULT_BUNDLE" "${TEST_SELECTORS[@]}")
"${TEST_CMD[@]}" 2>&1 | tee "$LOG_FILE"
PIPELINE_STATUS=("${PIPESTATUS[@]}")
BUILD_EXIT=${PIPELINE_STATUS[0]}
LOG_EXIT=${PIPELINE_STATUS[1]}

SUMMARY_EXIT=1
if [[ -d "$RESULT_BUNDLE" ]]; then
    xcrun xcresulttool get test-results summary --path "$RESULT_BUNDLE" >"$SUMMARY_FILE" 2>"$PARSER_LOG"
    SUMMARY_EXIT=$?
else
    printf 'No result bundle produced: %s\n' "$RESULT_BUNDLE" >"$PARSER_LOG"
fi

# Parse top-level counters and separately validate per-device/configuration outcomes.
# Keep the raw tool output even when it is malformed or the tool exits nonzero.
python3 - "$SUMMARY_FILE" "$VERIFICATION_FILE" "$BUILD_EXIT" "$LOG_EXIT" "$SUMMARY_EXIT" "$EXPECTED_TESTS" <<'PY'
import json
from pathlib import Path
import sys

summary_path, verification_path, build_status, log_status, summary_status, expected = sys.argv[1:]
errors = []
counts = {}
receipt = {
    "passed": False,
    "xcodebuildExitCode": int(build_status),
    "logExitCode": int(log_status),
    "summaryExitCode": int(summary_status),
    "expectedTestCount": int(expected) if expected else None,
    "counts": counts,
    "errors": errors,
}
for label, status in (("xcodebuild", build_status), ("log capture", log_status), ("xcresult summary", summary_status)):
    if int(status) != 0:
        errors.append(f"{label} command exited {status}")

def unique_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result

def reject_constant(token):
    raise ValueError(f"invalid JSON numeric constant: {token}")

def validate_configurations(summary):
    if "devicesAndConfigurations" not in summary:
        return
    configurations = summary["devicesAndConfigurations"]
    if not isinstance(configurations, list) or not configurations:
        raise ValueError("devicesAndConfigurations must be a nonempty array")
    per_configuration_passes = []
    for index, configuration in enumerate(configurations):
        label = f"devicesAndConfigurations[{index}]"
        if not isinstance(configuration, dict):
            raise ValueError(f"{label} must be an object")
        for key in ("passedTests", "failedTests", "skippedTests", "expectedFailures"):
            value = configuration.get(key)
            if type(value) is not int or value < 0:
                raise ValueError(f"{label}.{key} must be a nonnegative integer")
            if key != "passedTests" and value:
                errors.append(f"{label}.{key} is nonzero")
        per_configuration_passes.append(configuration["passedTests"])
        if "totalTestCount" in configuration:
            total = configuration["totalTestCount"]
            if type(total) is not int or total < 0:
                raise ValueError(f"{label}.totalTestCount must be a nonnegative integer")
            if total != sum(configuration[key] for key in ("passedTests", "failedTests", "skippedTests", "expectedFailures")):
                errors.append(f"{label} counters do not add up to totalTestCount")
        # Outcome fields apply to the configuration record, not arbitrary metadata
        # such as device details, testPlanConfiguration or statistics dictionaries.
        if "result" in configuration and configuration["result"] != "Passed":
            errors.append(f"{label}.result is not 'Passed'")
        if "testFailures" in configuration:
            failures = configuration["testFailures"]
            if not isinstance(failures, list) or failures:
                errors.append(f"{label}.testFailures must be an empty array")
    # Configurations may cover overlapping sets of tests. Do not add their
    # counters to the summary or require every configuration to run every test.
    # These bounds also require exact agreement for a single configuration.
    if not max(per_configuration_passes) <= counts["passedTests"] <= sum(per_configuration_passes):
        errors.append("configuration passedTests counts contradict summary passedTests")

try:
    with open(summary_path) as stream:
        summary = json.load(stream, object_pairs_hook=unique_keys, parse_constant=reject_constant)
    if not isinstance(summary, dict):
        raise ValueError("summary must be a JSON object")
    for key in ("totalTestCount", "passedTests", "failedTests", "skippedTests", "expectedFailures"):
        value = summary.get(key)
        if type(value) is not int or value < 0:
            raise ValueError(f"{key} must be a nonnegative integer")
        counts[key] = value
    if summary.get("result") != "Passed":
        errors.append(f"summary result is {summary.get('result')!r}, not 'Passed'")
    failures = summary.get("testFailures")
    if not isinstance(failures, list):
        errors.append("testFailures must be an array")
    elif failures:
        errors.append("summary contains test failure records")
    if counts["totalTestCount"] == 0:
        errors.append("no tests ran")
    if counts["failedTests"]:
        errors.append("tests failed")
    if counts["skippedTests"]:
        errors.append("required tests were skipped")
    if counts["expectedFailures"]:
        errors.append("expected failures do not satisfy this gate")
    if counts["totalTestCount"] != sum(counts[key] for key in ("passedTests", "failedTests", "skippedTests", "expectedFailures")):
        errors.append("test counts do not add up to totalTestCount")
    if expected and counts["totalTestCount"] != int(expected):
        errors.append(f"expected {expected} tests, found {counts['totalTestCount']}")
    validate_configurations(summary)
except (OSError, ValueError) as error:
    errors.append(f"cannot validate summary: {error}")

receipt["passed"] = not errors
Path(verification_path).write_text(json.dumps(receipt, indent=2) + "\n")
if errors:
    print("\nTEST VERIFICATION FAILED")
    for error in errors:
        print(f"  - {error}")
else:
    print(f"\nALL TESTS PASSED ({counts['totalTestCount']} tests; no skips or expected failures)")
if counts:
    print("Counts: " + json.dumps(counts, sort_keys=True))
sys.exit(1 if errors else 0)
PY
VERIFY_EXIT=$?

if [[ "$QUICK_MODE" == false && -f "$SUMMARY_FILE" ]]; then
    printf '\n--- SUMMARY JSON ---\n'
    cat "$SUMMARY_FILE"
    printf '\n--- END SUMMARY JSON ---\n'
fi
if [[ "$SUMMARY_EXIT" -ne 0 ]]; then
    cat "$PARSER_LOG" >&2
fi
printf '\nArtifacts retained: %s\n' "$RUN_DIR"

# Preserve Xcode's failure code while rejecting false success from missing/bad evidence.
[[ "$BUILD_EXIT" -eq 0 ]] || exit "$BUILD_EXIT"
[[ "$LOG_EXIT" -eq 0 && "$SUMMARY_EXIT" -eq 0 && "$VERIFY_EXIT" -eq 0 ]] || exit 1
exit 0
