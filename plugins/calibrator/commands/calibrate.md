---
name: calibrate
description: Record LLM expectation mismatches. Guide to initialize if not initialized.
---

# /calibrate

Record patterns when Claude generates something different from expectations.

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
else
  LANG="en"
fi
```

## Pre-execution Check

### Step 0: Dependency Check
```bash
# Check required dependencies
if ! command -v sqlite3 &> /dev/null; then
  echo "❌ Error: sqlite3 is required but not installed."
  exit 1
fi
```

1. Check if `.claude/calibrator/patterns.db` exists:
   ```bash
   # Read database path from config (uses read_config from above)
   if read_config; then
     DB_PATH=$(jq -r '.db_path // ".claude/calibrator/patterns.db"' "$CONFIG_FILE")
   else
     DB_PATH=".claude/calibrator/patterns.db"
   fi

   test -f "$DB_PATH"
   ```

2. If file doesn't exist:
   - i18n key: `calibrate.not_initialized` - Ask user if they want to initialize
   - Y selected: Run `/calibrate init` then continue
   - n selected: i18n key: `calibrate.run_init_first` message then exit

## Recording Flow

### Step 1: Category Selection
i18n key reference:
- `calibrate.category_prompt` - Question
- `calibrate.category_missing` - Option 1
- `calibrate.category_excess` - Option 2
- `calibrate.category_style` - Option 3
- `calibrate.category_other` - Option 4

English example:
```
What kind of mismatch just happened?

1. Something was missing
2. There was something unnecessary
3. I wanted a different approach
4. Let me explain
```

Category mapping:
- 1 → `missing`
- 2 → `excess`
- 3 → `style`
- 4 → `other`

### Step 2: Situation and Expectation Input
i18n key reference:
- `calibrate.situation_prompt` - Question
- `calibrate.situation_example` - Example
- `calibrate.situation_label` - Situation label
- `calibrate.expectation_label` - Expectation label

English example:
```
In what situation, and what did you expect?
Example: "When creating a model, include timestamp field"

Situation: [user input]
Expected: [user input]
```

### Step 3: Database Recording

**Input Escaping** (SQL Injection Prevention):
```bash
# Single quote escaping: ' → ''
SAFE_CATEGORY=$(printf '%s' "$CATEGORY" | sed "s/'/''/g")
SAFE_SITUATION=$(printf '%s' "$SITUATION" | sed "s/'/''/g")
SAFE_EXPECTATION=$(printf '%s' "$EXPECTATION" | sed "s/'/''/g")
SAFE_INSTRUCTION=$(printf '%s' "$INSTRUCTION" | sed "s/'/''/g")
```

1. Record to both tables using transaction (prevents race conditions):
   ```bash
   # Use BEGIN IMMEDIATE for write lock, ensuring atomic operation
   sqlite3 "$DB_PATH" <<SQL
   BEGIN IMMEDIATE;

   -- Record observation
   INSERT INTO observations (category, situation, expectation)
   VALUES ('$SAFE_CATEGORY', '$SAFE_SITUATION', '$SAFE_EXPECTATION');

   -- Upsert pattern (composite unique: situation + instruction)
   INSERT INTO patterns (situation, instruction, count)
   VALUES ('$SAFE_SITUATION', '$SAFE_INSTRUCTION', 1)
   ON CONFLICT(situation, instruction)
   DO UPDATE SET count = count + 1, last_seen = CURRENT_TIMESTAMP;

   COMMIT;
   SQL

   if [ $? -ne 0 ]; then
     echo "❌ Error: Failed to record pattern"
     exit 1
   fi
   ```

   Instruction generation rules:
   - Convert expectation to imperative form
   - Example: "include timestamp field" → "Always include timestamp field"

2. Get current pattern count:
   ```bash
   COUNT=$(sqlite3 "$DB_PATH" "SELECT count FROM patterns WHERE situation = '$SAFE_SITUATION' AND instruction = '$SAFE_INSTRUCTION';")
   ```

### Step 4: Output Result
i18n key reference:
- `calibrate.record_complete` - Completion title
- `calibrate.situation_label` - Situation label
- `calibrate.expectation_label` - Expectation label
- `calibrate.pattern_count` - Pattern accumulation count (placeholder: {count})
- `calibrate.promotion_hint` - Promotion hint

English example:
```
✅ Record complete

Situation: {situation}
Expected: {expectation}

Same pattern accumulated {count} times
```

If count is 2 or more, add:
```
💡 You can promote this to a Skill with /calibrate review.
```
