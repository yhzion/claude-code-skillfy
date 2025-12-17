---
name: calibrate reset
description: Reset Calibrator data (dangerous)
---

# /calibrate reset

⚠️ Deletes all Calibrator data.

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
else
  LANG="en"
  DB_PATH=".claude/calibrator/patterns.db"
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
  # i18n key `reset.no_data` message
  exit 1
fi
```

## Flow

### Step 1: Display Current Status (with error handling)
```bash
TOTAL_OBS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM observations;" 2>/dev/null || echo "0")
TOTAL_PATTERNS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM patterns;" 2>/dev/null || echo "0")
```

### Step 2: Request Confirmation
i18n key reference:
- `reset.title` - Title
- `reset.data_to_delete` - Data to delete header
- `reset.observations_count` - Observation count (placeholder: {count})
- `reset.patterns_count` - Pattern count (placeholder: {count})
- `reset.skills_preserved` - Skills preservation notice
- `reset.confirm_prompt` - Confirmation prompt

English example:
```
⚠️ Calibrator Reset

Data to delete:
- {TOTAL_OBS} observations
- {TOTAL_PATTERNS} patterns

Note: Generated Skills (.claude/skills/learned/) will be preserved.

Really reset? Type "reset" to confirm: _
```

### Step 3: User Input Validation
- If "reset" is entered: Proceed with deletion
- Otherwise: Display i18n key `reset.cancelled` message

### Step 4: Execute Data Deletion (with error handling)
```bash
# Delete existing DB
if ! rm "$DB_PATH" 2>/dev/null; then
  echo "❌ Error: Failed to delete database"
  exit 1
fi

# Create new DB (with error handling)
if ! sqlite3 "$DB_PATH" < plugins/calibrator/schemas/schema.sql; then
  echo "❌ Error: Failed to recreate database"
  exit 1
fi
```

### Step 5: Completion Message
i18n key reference:
- `reset.complete_title` - Completion title
- `reset.complete_observations` - Observations deleted
- `reset.complete_patterns` - Patterns deleted
- `reset.complete_skills` - Skills preserved
- `reset.complete_next` - Next steps

English example:
```
✅ Calibrator data has been reset

- Observations: all deleted
- Patterns: all deleted
- Skills: preserved (.claude/skills/learned/)

Start new records with /calibrate.
```
