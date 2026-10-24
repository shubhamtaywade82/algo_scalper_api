#!/bin/bash
# Simple wrapper script for WebSocket connection test
# Usage: ./scripts/test_ws.sh [instruments] [segment] [wait_seconds]

set -e

INSTRUMENTS="${1:-}"
SEGMENT="${2:-IDX_I}"
WAIT="${3:-15}"

echo "Testing WebSocket connection..."
echo "Instruments: ${INSTRUMENTS:-'from config'}"
echo "Segment: $SEGMENT"
echo "Wait time: ${WAIT}s"
echo ""

if [ -n "$INSTRUMENTS" ]; then
  bundle exec rails runner "load 'lib/tasks/ws_connection_test.rb'; WsConnectionTest.run(instruments: '$INSTRUMENTS', segment: '$SEGMENT', wait_seconds: $WAIT)"
else
  bundle exec rails runner "load 'lib/tasks/ws_connection_test.rb'; WsConnectionTest.run(segment: '$SEGMENT', wait_seconds: $WAIT)"
fi

