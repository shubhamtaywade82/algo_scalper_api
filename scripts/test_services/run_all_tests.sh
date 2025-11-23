#!/bin/bash
# Run all service tests with summary report

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../.."

# Timeout for long-running tests (in seconds)
LONG_TEST_TIMEOUT=60

echo "=========================================="
echo "  Running All Service Tests"
echo "=========================================="
echo ""

# Quick tests (fast, no dependencies)
QUICK_TESTS=(
  "test_redis_tick_cache.rb"
  "test_redis_pnl_cache.rb"
  "test_capital_allocator.rb"
  "test_position_index.rb"
  "test_options_services.rb"
  "test_active_cache.rb"
)

# Long-running tests (require services, can timeout)
LONG_RUNNING_TESTS=(
  "test_market_feed_hub.rb"
  "test_signal_scheduler.rb"
  "test_entry_guard.rb"
  "test_exit_engine.rb"
  "test_paper_pnl_refresher.rb"
  "test_pnl_updater_service.rb"
  "test_position_sync_service.rb"
  "test_risk_manager_service.rb"
  "test_orders_services.rb"
  "test_position_heartbeat.rb"
  "test_trading_supervisor.rb"
)

# Integration tests
INTEGRATION_TESTS=(
  "test_integration_flow.rb"
  "test_end_to_end_integration.rb"
)

# Track results
PASSED=0
FAILED=0
WARNINGS=0
TIMED_OUT=0
FAILED_TESTS=()
TIMED_OUT_TESTS=()

# Function to run a test and capture output
run_test() {
  local test_file="$1"
  local timeout_seconds="${2:-0}"  # 0 means no timeout

  if [ "$timeout_seconds" -gt 0 ]; then
    # Run with timeout
    timeout "$timeout_seconds" ruby "$SCRIPT_DIR/$test_file" 2>&1
    local exit_code=$?
    if [ $exit_code -eq 124 ]; then
      return 124  # Timeout
    fi
    return $exit_code
  else
    # Run without timeout
    ruby "$SCRIPT_DIR/$test_file" 2>&1
    return $?
  fi
}

# Function to check test output for errors/warnings
check_test_output() {
  local output="$1"
  local test_name="$2"

  if echo "$output" | grep -q "❌\|Error\|NoMethodError\|undefined method"; then
    return 2  # Failed
  elif echo "$output" | grep -q "⚠️"; then
    return 1  # Warning
  else
    return 0  # Passed
  fi
}

echo "=========================================="
echo "  Phase 1: Quick Tests"
echo "=========================================="
echo ""

for test in "${QUICK_TESTS[@]}"; do
  echo "----------------------------------------"
  echo "Running: $test"
  echo "----------------------------------------"

  output=$(run_test "$test" 0)
  exit_code=$?

  echo "$output"

  if [ $exit_code -eq 0 ]; then
    check_test_output "$output" "$test"
    check_result=$?
    case $check_result in
      0)
        PASSED=$((PASSED + 1))
        echo "✅ $test PASSED"
        ;;
      1)
        WARNINGS=$((WARNINGS + 1))
        echo "⚠️  $test has warnings"
        ;;
      2)
        FAILED=$((FAILED + 1))
        FAILED_TESTS+=("$test")
        echo "❌ $test FAILED"
        ;;
    esac
  else
    FAILED=$((FAILED + 1))
    FAILED_TESTS+=("$test")
    echo "❌ $test FAILED (exit code: $exit_code)"
  fi
  echo ""
done

echo ""
echo "=========================================="
echo "  Phase 2: Long-Running Tests (with ${LONG_TEST_TIMEOUT}s timeout)"
echo "=========================================="
echo ""

for test in "${LONG_RUNNING_TESTS[@]}"; do
  echo "----------------------------------------"
  echo "Running: $test (timeout: ${LONG_TEST_TIMEOUT}s)"
  echo "----------------------------------------"

  output=$(run_test "$test" "$LONG_TEST_TIMEOUT" 2>&1)
  exit_code=$?

  echo "$output"

  if [ $exit_code -eq 124 ]; then
    TIMED_OUT=$((TIMED_OUT + 1))
    TIMED_OUT_TESTS+=("$test")
    echo "⏱️  $test TIMED OUT (exceeded ${LONG_TEST_TIMEOUT}s)"
  elif [ $exit_code -eq 0 ]; then
    check_test_output "$output" "$test"
    check_result=$?
    case $check_result in
      0)
        PASSED=$((PASSED + 1))
        echo "✅ $test PASSED"
        ;;
      1)
        WARNINGS=$((WARNINGS + 1))
        echo "⚠️  $test has warnings"
        ;;
      2)
        FAILED=$((FAILED + 1))
        FAILED_TESTS+=("$test")
        echo "❌ $test FAILED"
        ;;
    esac
  else
    FAILED=$((FAILED + 1))
    FAILED_TESTS+=("$test")
    echo "❌ $test FAILED (exit code: $exit_code)"
  fi
  echo ""
done

echo ""
echo "=========================================="
echo "  Phase 3: Integration Tests"
echo "=========================================="
echo ""

for test in "${INTEGRATION_TESTS[@]}"; do
  echo "----------------------------------------"
  echo "Running: $test (timeout: ${LONG_TEST_TIMEOUT}s)"
  echo "----------------------------------------"

  output=$(run_test "$test" "$LONG_TEST_TIMEOUT" 2>&1)
  exit_code=$?

  echo "$output"

  if [ $exit_code -eq 124 ]; then
    TIMED_OUT=$((TIMED_OUT + 1))
    TIMED_OUT_TESTS+=("$test")
    echo "⏱️  $test TIMED OUT (exceeded ${LONG_TEST_TIMEOUT}s)"
  elif [ $exit_code -eq 0 ]; then
    check_test_output "$output" "$test"
    check_result=$?
    case $check_result in
      0)
        PASSED=$((PASSED + 1))
        echo "✅ $test PASSED"
        ;;
      1)
        WARNINGS=$((WARNINGS + 1))
        echo "⚠️  $test has warnings"
        ;;
      2)
        FAILED=$((FAILED + 1))
        FAILED_TESTS+=("$test")
        echo "❌ $test FAILED"
        ;;
    esac
  else
    FAILED=$((FAILED + 1))
    FAILED_TESTS+=("$test")
    echo "❌ $test FAILED (exit code: $exit_code)"
  fi
  echo ""
done

echo ""
echo "=========================================="
echo "  Test Summary"
echo "=========================================="
echo "✅ Passed: $PASSED"
echo "⚠️  Warnings: $WARNINGS"
echo "⏱️  Timed Out: $TIMED_OUT"
echo "❌ Failed: $FAILED"
echo ""

if [ $FAILED -gt 0 ]; then
  echo "Failed tests:"
  for test in "${FAILED_TESTS[@]}"; do
    echo "  ❌ $test"
  done
  echo ""
fi

if [ $TIMED_OUT -gt 0 ]; then
  echo "Timed out tests:"
  for test in "${TIMED_OUT_TESTS[@]}"; do
    echo "  ⏱️  $test (exceeded ${LONG_TEST_TIMEOUT}s)"
  done
  echo ""
  echo "Note: Timed out tests may need more time or services may not be running."
  echo "      Run individually with longer timeout: timeout 120 ruby scripts/test_services/$test"
  echo ""
fi

if [ $FAILED -gt 0 ] || [ $TIMED_OUT -gt 0 ]; then
  echo "Run individual tests for details:"
  for test in "${FAILED_TESTS[@]}"; do
    echo "  ruby scripts/test_services/$test"
  done
  for test in "${TIMED_OUT_TESTS[@]}"; do
    echo "  timeout 120 ruby scripts/test_services/$test"
  done
  echo ""
fi

echo "Generate detailed summary:"
echo "  ruby scripts/test_services/test_summary.rb"
echo ""

# Exit with error if any tests failed (timeouts are warnings, not failures)
if [ $FAILED -gt 0 ]; then
  exit 1
fi

exit 0

