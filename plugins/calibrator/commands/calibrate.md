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
# Stable JSON parsing using jq
LANG=$(jq -r '.language // "en"' .claude/calibrator/config.json 2>/dev/null)
LANG=${LANG:-en}  # Default: English
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
   # Read database path from config
   DB_PATH=$(jq -r '.db_path // ".claude/calibrator/patterns.db"' .claude/calibrator/config.json 2>/dev/null)
   DB_PATH=${DB_PATH:-.claude/calibrator/patterns.db}

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

1. Record to observations table:
   ```bash
   sqlite3 "$DB_PATH" "INSERT INTO observations (category, situation, expectation) VALUES ('$SAFE_CATEGORY', '$SAFE_SITUATION', '$SAFE_EXPECTATION');"
   ```

2. Update patterns table using UPSERT (atomic operation to prevent race conditions):
   ```bash
   # Use INSERT ... ON CONFLICT for atomic upsert operation
   sqlite3 "$DB_PATH" "INSERT INTO patterns (situation, instruction, count)
     VALUES ('$SAFE_SITUATION', '$SAFE_INSTRUCTION', 1)
     ON CONFLICT(situation)
     DO UPDATE SET count = count + 1, last_seen = CURRENT_TIMESTAMP;"
   ```

   Instruction generation rules:
   - Convert expectation to imperative form
   - Example: "include timestamp field" → "Always include timestamp field"

3. Get current pattern count:
   ```bash
   COUNT=$(sqlite3 "$DB_PATH" "SELECT count FROM patterns WHERE situation = '$SAFE_SITUATION';")
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
