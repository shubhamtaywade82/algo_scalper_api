#!/usr/bin/env bash
# Starts or stops the paper agent in a detached tmux session, for cron on weekdays.
#   scripts/session.sh start   # no-op if the session already exists
#   scripts/session.sh stop    # SIGTERM (graceful stop), then removes the session
# Attach to the cockpit with: tmux attach -t options-agent
set -euo pipefail

SESSION=options-agent
REPO="$(cd "$(dirname "$0")/.." && pwd)"
# cron's PATH has neither node nor tmux's usual neighbours.
export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"

alert() {
  local url
  url="$(grep -E '^ALERT_WEBHOOK_URL=' "$REPO/.env" 2>/dev/null | cut -d= -f2- || true)"
  [ -n "$url" ] && curl -fsS -m 5 -d "$1" "$url" >/dev/null || true
}

case "${1:-}" in
  start)
    tmux has-session -t "$SESSION" 2>/dev/null && exit 0
    # The trailing shell keeps the pane open after an exit so the last screen can be read on attach.
    tmux new-session -d -s "$SESSION" -c "$REPO" \
      "CONFIG_FILE=config.paper.yml MODE=paper node_modules/.bin/tsx src/index.tsx; code=\$?; \
       [ \$code -ne 0 ] && $REPO/scripts/session.sh crashed \$code; exec bash"
    ;;
  stop)
    tmux has-session -t "$SESSION" 2>/dev/null || exit 0
    pane="$(tmux display -p -t "$SESSION" '#{pane_pid}')"
    pkill -TERM -P "$pane" || true
    for _ in $(seq 60); do pgrep -P "$pane" >/dev/null || break; sleep 1; done
    tmux kill-session -t "$SESSION"
    ;;
  crashed)
    alert "options agent exited with code ${2:-?} at $(TZ=Asia/Kolkata date +%H:%M) IST"
    ;;
  *)
    echo "usage: $0 start|stop" >&2
    exit 2
    ;;
esac
