#!/usr/bin/env bash
# scripts/rebase.sh
# Run AFTER merging the PR on GitHub, while still on the feature branch.
# Detects current branch -> switches to main -> pulls -> deletes the merged branch.

set -euo pipefail   # stop immediately on any error

# --- 1. Figure out which branch we're currently on ---
BRANCH=$(git rev-parse --abbrev-ref HEAD)

if [ "$BRANCH" = "main" ]; then
  echo ">> You're already on 'main'. Nothing to clean up."
  echo ">> (Run this while standing on the merged feature branch.)"
  exit 1
fi

echo ">> Current branch is: $BRANCH"
echo ">> This will switch to main, pull latest, and delete '$BRANCH' locally."

# --- 2. Safety pause: confirm (PR must already be merged on GitHub) ---
read -p ">> Proceed? Make sure the PR is already merged on GitHub (y/n) " CONFIRM
if [ "$CONFIRM" != "y" ]; then
  echo ">> Aborted. Nothing changed."
  exit 1
fi

# --- 3. Switch to main and pull the merged changes ---
echo ">> Switching to main and pulling..."
git checkout main
git pull

# --- 4. Delete the old feature branch (SAFE delete — refuses if unmerged) ---
echo ">> Deleting local branch: $BRANCH"
git branch -d "$BRANCH"

echo ""
echo ">> Done. You're on an up-to-date main, and '$BRANCH' is cleaned up."