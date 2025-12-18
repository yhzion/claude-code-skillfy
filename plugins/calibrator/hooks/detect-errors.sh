#!/bin/bash
# PostToolUse Hook: Detect errors from Bash execution and record frequency
# Triggers on Bash tool use with non-zero exit code
#
# ROLE SEPARATION:
# - Hook (this file): Records error occurrences to observations table (frequency tracking)
# - Skill (auto-calibrate.md): Analyzes errors and records learned patterns to patterns table
#
# This hook captures WHAT failed, while the Skill captures HOW to fix it.

set -euo pipefail

# ============================================
# Step 1: Read hook input from stdin
# ============================================
input=$(cat)

# Check if jq is available
if ! command -v jq &> /dev/null; then
  exit 0
fi

# Extract relevant fields from hook input
command=$(echo "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
exit_code=$(echo "$input" | jq -r '.tool_result.exit_code // 0' 2>/dev/null)
stdout=$(echo "$input" | jq -r '.tool_result.stdout // empty' 2>/dev/null)
stderr=$(echo "$input" | jq -r '.tool_result.stderr // empty' 2>/dev/null)

# ============================================
# Step 2: Early exit conditions
# ============================================

# No command to analyze
if [ -z "$command" ]; then
  exit 0
fi

# Successful execution - no errors to detect
if [ "$exit_code" = "0" ] || [ "$exit_code" = "null" ]; then
  exit 0
fi

# ============================================
# Step 3: Check initialization and auto-detect flag
# ============================================

# Check sqlite3 availability
if ! command -v sqlite3 &> /dev/null; then
  exit 0
fi

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
DB_PATH="$PROJECT_ROOT/.claude/calibrator/patterns.db"
FLAG_FILE="$PROJECT_ROOT/.claude/calibrator/auto-detect.enabled"

# Not initialized - skip silently
if [ ! -f "$DB_PATH" ]; then
  exit 0
fi

# Auto-detection disabled - skip silently
if [ ! -f "$FLAG_FILE" ]; then
  exit 0
fi

# ============================================
# Step 4: Classify command type
# ============================================
classify_command() {
  local cmd="$1"

  # Lint/Format
  if echo "$cmd" | grep -qiE '(eslint|prettier|biome|stylelint|pylint|flake8|rubocop|golint|clippy|oxlint)'; then
    echo "lint"
  # Type Check
  elif echo "$cmd" | grep -qiE '(tsc|typescript|mypy|flow|typecheck)'; then
    echo "typecheck"
  # Build
  elif echo "$cmd" | grep -qiE '(build|webpack|vite|esbuild|rollup|turbo|cargo build|go build|make)'; then
    echo "build"
  # Test
  elif echo "$cmd" | grep -qiE '(test|jest|vitest|pytest|mocha|cargo test|go test)'; then
    echo "test"
  # Package
  elif echo "$cmd" | grep -qiE '(npm|yarn|pnpm|pip|cargo|go mod)'; then
    echo "package"
  # Git
  elif echo "$cmd" | grep -qE '^git '; then
    echo "git"
  else
    echo "other"
  fi
}

ERROR_TYPE=$(classify_command "$command")

# ============================================
# Step 5: Extract situation from error (frequency tracking only)
# ============================================
output="$stdout$stderr"

# Extract first meaningful error line as situation
extract_situation() {
  local cmd="$1"
  local out="$2"
  local err_type="$3"

  # Get first error/warning line (max 200 chars)
  local first_error
  first_error=$(echo "$out" | grep -iE '(error|Error|ERROR|warning|Warning|WARN|fail|FAIL)' | head -1 | cut -c1-200)

  if [ -z "$first_error" ]; then
    # Fallback: first non-empty line
    first_error=$(echo "$out" | grep -v '^$' | head -1 | cut -c1-200)
  fi

  # Create situation description
  echo "${err_type}: ${first_error:-Unknown error}" | cut -c1-500
}

SITUATION=$(extract_situation "$command" "$output" "$ERROR_TYPE")

# Skip if we couldn't extract meaningful information
if [ -z "$SITUATION" ]; then
  exit 0
fi

# ============================================
# Step 6: SQL Injection prevention and DB record (observations only)
# ============================================
escape_sql() {
  printf '%s' "$1" | sed "s/'/''/g"
}

# Map ERROR_TYPE to observation category for consistency with calibrate.md
map_category() {
  case "$1" in
    lint)      echo "style" ;;
    typecheck) echo "missing" ;;
    build)     echo "other" ;;
    test)      echo "other" ;;
    package)   echo "missing" ;;
    git)       echo "other" ;;
    *)         echo "other" ;;
  esac
}

CATEGORY=$(map_category "$ERROR_TYPE")
SAFE_CATEGORY=$(escape_sql "$CATEGORY")
SAFE_SITUATION=$(escape_sql "$SITUATION")

# Record to observations table only (frequency tracking)
# NOTE: patterns table is managed by auto-calibrate.md skill which has
# better understanding of the actual fix and can generate meaningful instructions
if ! sqlite3 "$DB_PATH" <<SQL 2>/dev/null
INSERT INTO observations (category, situation, expectation)
VALUES ('$SAFE_CATEGORY', '$SAFE_SITUATION', 'Detected by hook - see auto-calibrate skill for learned pattern');
SQL
then
  # DB error - exit silently
  exit 0
fi

# Hook's job is done - frequency recorded
# Pattern learning and skill promotion are handled by auto-calibrate.md skill
exit 0
