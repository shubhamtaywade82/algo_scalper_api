#!/bin/bash
# Wrapper script to run parameter optimization with proper environment variables
# Usage: ./scripts/run_optimization.sh [INDEX] [DAYS] [INTERVAL]

set -e

INDEX="${1:-NIFTY}"
DAYS="${2:-30}"
INTERVAL="${3:-1}"

echo "Running optimization for $INDEX (Days: $DAYS, Interval: ${INTERVAL}min)"
echo "Environment: SCRIPT_MODE=1 DISABLE_TRADING_SERVICES=1 BACKTEST_MODE=1"
echo ""

SCRIPT_MODE=1 \
DISABLE_TRADING_SERVICES=1 \
BACKTEST_MODE=1 \
rails runner scripts/optimize_indicator_parameters.rb "$INDEX" "$DAYS" "$INTERVAL"

