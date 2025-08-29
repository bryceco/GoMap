#!/usr/bin/env bash
set -euo pipefail

GRACE_SECONDS="${1:-5}"

is_running() {
  pgrep -x "Xcode" >/dev/null 2>&1
}

if ! is_running; then
  echo "Xcode is not running."
  exit 0
fi

echo "Requesting Xcode to quit gracefully..."
osascript -e 'tell application "Xcode" to quit' || true

# Wait a bit for a clean shutdown
for ((i=0; i<GRACE_SECONDS*2; i++)); do
  if ! is_running; then
    echo "Xcode closed gracefully."
    exit 0
  fi
  sleep 0.5
done

# Escalate: TERM, then KILL if needed
if is_running; then
  echo "Sending SIGTERM to Xcode..."
  pkill -TERM -x "Xcode" || true
  sleep 2
fi

if is_running; then
  echo "Forcing SIGKILL to Xcode..."
  pkill -KILL -x "Xcode" || true
  sleep 1
fi

if is_running; then
  echo "Failed to terminate Xcode." >&2
  exit 1
fi

echo "Xcode force-quit."
