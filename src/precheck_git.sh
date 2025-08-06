#!/bin/bash
set -e

# Check for uncommitted changes (staged, unstaged, or untracked)
if [ -n "$(git status --porcelain)" ]; then
  echo "❌ You have uncommitted changes."
  echo "Run: git status to inspect, then commit or stash your changes."
  exit 1
fi

# Fetch latest from origin
git fetch origin master

# Check if local HEAD matches origin/master
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/master)

if [ "$LOCAL" != "$REMOTE" ]; then
  echo "❌ Your branch is not up to date with origin/master."
  echo "Run: git pull --rebase"
  exit 1
fi

echo "✅ Git state is clean and up to date."

