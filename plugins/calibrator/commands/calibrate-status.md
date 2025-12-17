---
name: calibrate status
description: View Calibrator statistics
---

# /calibrate status

View currently recorded patterns and statistics.

## i18n Message Reference

All user-facing messages reference `plugins/calibrator/i18n/messages.json`.
At runtime, reads the `language` field from `.claude/calibrator/config.json` to use appropriate language messages.

```bash
# Bash strict mode for safer script execution
set -euo pipefail
IFS=$'\n\t'

# Config file path
CONFIG_FILE=".claude/calibrator/config.json"

# Config validation and reading with explicit error handling
read_config() {
  if [ ! -f "$CONFIG_FILE" ]; then
    echo "⚠️ Warning: config.json not found. Using defaults." >&2
    return 1
  fi

  # Validate JSON syntax
  if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
    echo "⚠️ Warning: config.json is invalid JSON. Using defaults." >&2
    return 1
  fi

  return 0
}

# Read config with validation
if read_config; then
  LANG=$(jq -r '.language // "en"' "$CONFIG_FILE")
  # Validate language value
  case "$LANG" in
    en|ko|ja|zh) ;;
    *) echo "⚠️ Warning: Invalid language '$LANG'. Using 'en'." >&2; LANG="en" ;;
  esac

  # Read database path
  DB_PATH=$(jq -r '.db_path // ".claude/calibrator/patterns.db"' "$CONFIG_FILE")

  # Read and validate threshold (must be positive integer)
  THRESHOLD=$(jq -r '.threshold // 2' "$CONFIG_FILE")
  if ! [[ "$THRESHOLD" =~ ^[1-9][0-9]*$ ]]; then
    echo "⚠️ Warning: Invalid threshold '$THRESHOLD'. Using '2'." >&2
    THRESHOLD=2
  fi
else
  LANG="en"
  DB_PATH=".claude/calibrator/patterns.db"
  THRESHOLD=2
fi
```

## Pre-execution Check

### Step 0: Dependency and DB Check
```bash
# Check required dependencies
if ! command -v sqlite3 &> /dev/null; then
  echo "❌ Error: sqlite3 is required but not installed."
  exit 1
fi

# Check DB exists
if [ ! -f "$DB_PATH" ]; then
  # i18n key `calibrate.run_init_first` message
  exit 1
fi
```

## Flow

### Step 1: Execute Statistics Queries (with error handling)
```bash
# Query execution function (with error handling)
run_query() {
  result=$(sqlite3 "$DB_PATH" "$1" 2>/dev/null)
  if [ $? -ne 0 ]; then
    echo "0"  # Return default value on error
  else
    echo "${result:-0}"
  fi
}

# Total observation count
TOTAL_OBS=$(run_query "SELECT COUNT(*) FROM observations;")

# Total pattern count
TOTAL_PATTERNS=$(run_query "SELECT COUNT(*) FROM patterns;")

# Count of patterns promoted to Skills
PROMOTED=$(run_query "SELECT COUNT(*) FROM patterns WHERE promoted = TRUE;")

# Count of patterns pending promotion (repeated 2+ times) - uses configurable threshold
PENDING=$(run_query "SELECT COUNT(*) FROM patterns WHERE count >= $THRESHOLD AND promoted = FALSE;")

# Recent 3 observation records
RECENT=$(sqlite3 "$DB_PATH" "SELECT timestamp, category, situation FROM observations ORDER BY timestamp DESC LIMIT 3;" 2>/dev/null)
```

### Step 2: Output Format
i18n key reference:
- `status.title` - Title
- `status.total_observations` - Total observations
- `status.detected_patterns` - Detected patterns
- `status.promoted_skills` - Promoted to Skills
- `status.pending_promotion` - Pending promotion
- `status.recent_records` - Recent records

English example:
```
📊 Calibrator Status

Total observations: {TOTAL_OBS}
Detected patterns: {TOTAL_PATTERNS}
├─ Promoted to Skills: {PROMOTED}
└─ Pending promotion (2+): {PENDING}

Recent records:
- [{timestamp}] {category}: {situation}
- [{timestamp}] {category}: {situation}
- [{timestamp}] {category}: {situation}
```

### Step 3: Pending Promotion Notice
i18n key: `status.promotion_hint`

If PENDING is greater than 0, add:
```
💡 Run /calibrate review to promote pending patterns to Skills.
```

### Step 4: No Data Case
i18n key reference:
- `status.no_data_title` - Title
- `status.no_data_desc` - Description

If TOTAL_OBS is 0 (English example):
```
📊 Calibrator Status

No data recorded yet.
Record your first mismatch with /calibrate.
```
