#!/usr/bin/env bash
# scripts/add.sh
# Usage: ./scripts/add.sh <branch-name> "<commit message>"
# Automates: branch -> stage -> (review pause) -> commit -> push -> open PR.

set -euo pipefail   # stop immediately if any command fails

# --- 1. Check arguments ---
if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <branch-name> \"<commit message>\""
  echo 'Example: ./scripts/add.sh feat/cleaner "Add HTML cleaner"'
  exit 1
fi

BRANCH="$1"
MESSAGE="$2"

# --- 1a. Install any new dependencies (editable install incl. dev extras) ---
#echo ">> Installing/updating dependencies..."
#pip install -e ".[dev]"

# --- 1b. Formatting with ruff ---
echo ">> Formatting with ruff..."
python -m ruff format .

# --- 1c. Lint and format check ---
echo ">> Running ruff lint check..."
python -m ruff check .

# --- 1d. Run tests ---
#echo ">> Running pytest..."
#python -m pytest

# --- 2. Make sure we start from an up-to-date main ---
# echo ">> Switching to main and pulling latest..."
# git checkout main
# git pull

# --- 3. Create and switch to the feature branch ---
echo ">> Creating branch: $BRANCH"
git checkout -b "$BRANCH"

# --- 4. Stage everything, then SHOW what will be committed ---
git add .
echo ""
echo ">> These changes will be committed:"
git status --short
echo ""

# --- 5. Safety pause: confirm before committing ---
read -p ">> Commit and push these changes? (y/n) " CONFIRM
if [ "$CONFIRM" != "y" ]; then
  echo ">> Aborted. Your branch '$BRANCH' exists with changes staged but not committed."
  exit 1
fi

# --- 6. Commit, push, open PR (and capture the PR URL) ---
git commit -m "$MESSAGE"
git push -u origin "$BRANCH"

# gh pr create prints the new PR's URL on success — capture it into a variable.
PR_URL=$(gh pr create --fill)

echo ""
echo ">> Done. Pull request created:"
echo ">> $PR_URL"