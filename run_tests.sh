#!/bin/bash
# =============================================================================
# Loopa Test Runner Script for AI Agent Integration
# =============================================================================
# This script runs XCUITests and outputs AI-parseable results.
# 
# Usage:
#   ./run_tests.sh              # Run all UI tests
#   ./run_tests.sh --unit       # Run unit tests only
#   ./run_tests.sh --ui         # Run UI tests only
#   ./run_tests.sh --quick      # Quick summary only (no detailed JSON)
#   ./run_tests.sh --test TestName  # Run specific test
# =============================================================================

set -e

# Configuration
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_FILE="$PROJECT_DIR/Loopa.xcodeproj"
RESULT_BUNDLE="$PROJECT_DIR/TestResults.xcresult"
SIMULATOR_NAME="iPhone 16 Pro"
LOG_FILE="$PROJECT_DIR/test_output.log"

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Parse arguments
TEST_TARGET="LoopaUITests"
QUICK_MODE=false
SPECIFIC_TEST=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --unit)
            TEST_TARGET="LoopaTests"
            shift
            ;;
        --ui)
            TEST_TARGET="LoopaUITests"
            shift
            ;;
        --quick)
            QUICK_MODE=true
            shift
            ;;
        --test)
            SPECIFIC_TEST="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Clean previous results
rm -rf "$RESULT_BUNDLE" "$LOG_FILE" 2>/dev/null || true

echo "=========================================="
echo " Loopa Test Runner"
echo "=========================================="
echo "Project: $PROJECT_FILE"
echo "Target: $TEST_TARGET"
echo "Simulator: $SIMULATOR_NAME"
echo ""

# Build the test command
TEST_CMD="xcodebuild test \
    -project \"$PROJECT_FILE\" \
    -scheme Loopa \
    -destination \"platform=iOS Simulator,name=$SIMULATOR_NAME\" \
    -resultBundlePath \"$RESULT_BUNDLE\" \
    -only-testing:$TEST_TARGET"

# Add specific test if provided
if [ -n "$SPECIFIC_TEST" ]; then
    TEST_CMD="$TEST_CMD/$SPECIFIC_TEST"
fi

# Run tests
echo "Running tests..."
echo ""

eval "$TEST_CMD" 2>&1 | tee "$LOG_FILE"
EXIT_CODE=${PIPESTATUS[0]}

echo ""
echo "=========================================="
echo " Test Results"
echo "=========================================="

# Parse and display results
if [ -d "$RESULT_BUNDLE" ]; then
    # Get summary JSON
    SUMMARY=$(xcrun xcresulttool get test-results summary --path "$RESULT_BUNDLE" 2>/dev/null)
    
    # Extract key metrics
    PASSED=$(echo "$SUMMARY" | grep -o '"passedTests" : [0-9]*' | grep -o '[0-9]*')
    FAILED=$(echo "$SUMMARY" | grep -o '"failedTests" : [0-9]*' | grep -o '[0-9]*')
    SKIPPED=$(echo "$SUMMARY" | grep -o '"skippedTests" : [0-9]*' | grep -o '[0-9]*')
    TOTAL=$(echo "$SUMMARY" | grep -o '"totalTestCount" : [0-9]*' | grep -o '[0-9]*')
    
    # Display summary
    echo ""
    if [ "$EXIT_CODE" -eq 0 ]; then
        echo -e "${GREEN}✓ ALL TESTS PASSED${NC}"
    else
        echo -e "${RED}✗ TESTS FAILED${NC}"
    fi
    echo ""
    echo "Summary:"
    echo "  Total:   $TOTAL"
    echo -e "  Passed:  ${GREEN}$PASSED${NC}"
    echo -e "  Failed:  ${RED}$FAILED${NC}"
    echo "  Skipped: $SKIPPED"
    echo ""
    
    # Show failures if any
    if [ "$FAILED" -gt 0 ]; then
        echo -e "${RED}Failed Tests:${NC}"
        echo "$SUMMARY" | grep -A2 '"testName"' | grep -o '"testName" : "[^"]*"' | sed 's/"testName" : "/ - /g' | sed 's/"//g'
        echo ""
        echo "Failure Details:"
        echo "$SUMMARY" | grep -o '"failureText" : "[^"]*"' | sed 's/"failureText" : "/  /g' | sed 's/"//g'
        echo ""
    fi
    
    # Output JSON for AI parsing if not in quick mode
    if [ "$QUICK_MODE" = false ]; then
        echo "=========================================="
        echo " JSON Output (for AI parsing)"
        echo "=========================================="
        echo ""
        echo "--- SUMMARY JSON ---"
        xcrun xcresulttool get test-results summary --path "$RESULT_BUNDLE"
        echo ""
        echo "--- END SUMMARY JSON ---"
    fi
else
    echo -e "${RED}Error: No test results found${NC}"
    echo "Check $LOG_FILE for details"
fi

echo ""
echo "=========================================="
echo " Files"
echo "=========================================="
echo "Result Bundle: $RESULT_BUNDLE"
echo "Log File: $LOG_FILE"
echo ""

# Exit with test exit code
exit $EXIT_CODE


