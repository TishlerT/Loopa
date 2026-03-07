#!/bin/bash
# =============================================================================
# Loopa Test Results Parser for AI Agent Consumption
# =============================================================================
# Parses xcresult bundle and outputs clean JSON for AI analysis.
# 
# Usage:
#   ./parse_results.sh              # Parse default TestResults.xcresult
#   ./parse_results.sh path.xcresult  # Parse specific xcresult bundle
#   ./parse_results.sh --summary    # Summary only
#   ./parse_results.sh --tests      # Full test list
#   ./parse_results.sh --failures   # Failures only
# =============================================================================

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_RESULT_BUNDLE="$PROJECT_DIR/TestResults.xcresult"

# Determine result bundle path and mode
RESULT_BUNDLE="$DEFAULT_RESULT_BUNDLE"
MODE="summary"

# Parse arguments
for arg in "$@"; do
    case "$arg" in
        --summary|--tests|--failures)
            MODE="${arg#--}"
            ;;
        *)
            if [ -d "$arg" ]; then
                RESULT_BUNDLE="$arg"
            fi
            ;;
    esac
done

# Check if result bundle exists
if [ ! -d "$RESULT_BUNDLE" ]; then
    echo '{"error": "No test results found. Run ./run_tests.sh first."}'
    exit 1
fi

# Parse based on mode
case "$MODE" in
    summary)
        # Get summary - best for quick AI parsing
        xcrun xcresulttool get test-results summary --path "$RESULT_BUNDLE" 2>/dev/null
        ;;
    tests)
        # Get full test list with pass/fail status
        xcrun xcresulttool get test-results tests --path "$RESULT_BUNDLE" 2>/dev/null
        ;;
    failures)
        # Extract just failures for focused debugging
        SUMMARY=$(xcrun xcresulttool get test-results summary --path "$RESULT_BUNDLE" 2>/dev/null)
        echo "$SUMMARY" | python3 -c "
import sys, json
data = json.load(sys.stdin)
failures = data.get('testFailures', [])
output = {
    'totalTests': data.get('totalTestCount', 0),
    'passed': data.get('passedTests', 0),
    'failed': data.get('failedTests', 0),
    'failures': [
        {
            'test': f.get('testName', ''),
            'error': f.get('failureText', ''),
            'target': f.get('targetName', '')
        }
        for f in failures
    ]
}
print(json.dumps(output, indent=2))
" 2>/dev/null || echo "$SUMMARY"
        ;;
    *)
        echo '{"error": "Invalid mode: '"$MODE"'"}'
        exit 1
        ;;
esac

