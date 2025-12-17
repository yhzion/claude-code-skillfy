---
name: calibrate
description: Record LLM expectation mismatches. Guide to initialize if not initialized.
allowed-tools: Bash(git:*), Bash(sqlite3:*), Bash(test:*), Bash(sed:*), Bash(printf:*), Bash(echo:*)
---

# /calibrate

Record patterns when Claude generates something different from expectations.

## Notes

This command is English-only (no locale/i18n).

## Pre-execution Setup

### Step 0: Dependency and DB Check
```bash
set -euo pipefail
IFS=$'\n\t'

# Ensure UTF-8 locale for proper character handling
export LC_ALL=C.UTF-8 2>/dev/null || export LC_ALL=en_US.UTF-8 2>/dev/null || true

# Get project root (Git root or current directory as fallback)
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
DB_PATH="$PROJECT_ROOT/.claude/calibrator/patterns.db"
THRESHOLD=2

# POSIX-compatible version comparison (returns 0 if $1 >= $2)
version_ge() {
  printf '%s\n%s' "$2" "$1" | awk -F. '
    NR==1 { split($0,a,"."); next }
    NR==2 { split($0,b,".")
      for(i=1; i<=3; i++) {
        if((b[i]+0) > (a[i]+0)) exit 0
        if((b[i]+0) < (a[i]+0)) exit 1
      }
      exit 0
    }'
}

if ! command -v sqlite3 &> /dev/null; then
  echo "❌ Error: sqlite3 is required but not installed."
  exit 1
fi

# SQLite 3.24.0+ required for UPSERT support
SQLITE_VERSION=$(sqlite3 --version 2>/dev/null | awk '{print $1}')
MIN_SQLITE_VERSION="3.24.0"
if ! version_ge "$SQLITE_VERSION" "$MIN_SQLITE_VERSION"; then
  echo "❌ Error: SQLite $MIN_SQLITE_VERSION or higher required. Found: ${SQLITE_VERSION:-unknown}"
  exit 1
fi

if [ ! -f "$DB_PATH" ]; then
  echo "❌ Calibrator is not initialized. Run /calibrate init first."
  exit 1
fi
```

## Recording Flow

### Step 2: Category Selection

Use the `AskUserQuestion` tool to ask the user to select a category:

```
header: "Category"
question: "What kind of mismatch just happened?"
options:
  - label: "Something was missing"
    description: "Expected output was not included"
  - label: "Something unnecessary"
    description: "Output included unwanted content"
  - label: "Different approach"
    description: "Wanted a different style or method"
  - label: "Other"
    description: "Let me explain in detail"
```

Category mapping:
- "Something was missing" → `CATEGORY="missing"`
- "Something unnecessary" → `CATEGORY="excess"`
- "Different approach" → `CATEGORY="style"`
- "Other" → `CATEGORY="other"`

### Step 3: Situation and Expectation Input

Use the `AskUserQuestion` tool to collect input (3 separate questions):

**Question 1:**
```
header: "Situation"
question: "In what situation did this happen? (e.g., 'When creating a model')"
options:
  - label: "Let me describe"
    description: "I'll type the situation"
```
→ User provides text input via "Other" option → Save as `SITUATION`

**Question 2:**
```
header: "Expected"
question: "What did you expect? (e.g., 'Include timestamp field')"
options:
  - label: "Let me describe"
    description: "I'll type what I expected"
```
→ User provides text input via "Other" option → Save as `EXPECTATION`

**Question 3:**
```
header: "Instruction"
question: "What rule should Claude learn? (imperative form, e.g., 'Always include timestamp fields')"
options:
  - label: "Let me describe"
    description: "I'll type the instruction"
```
→ User provides text input via "Other" option → Save as `INSTRUCTION`

### Step 4: Input Validation
```bash
# Validate category defensively
case "$CATEGORY" in
  missing|excess|style|other) ;;
  *) echo "❌ Error: Invalid category '$CATEGORY'"; exit 1 ;;
esac

# Basic length checks (match DB CHECK constraints)
if [ ${#SITUATION} -eq 0 ] || [ ${#SITUATION} -gt 500 ]; then
  echo "❌ Error: Situation must be 1-500 characters."
  exit 1
fi

if [ ${#EXPECTATION} -eq 0 ] || [ ${#EXPECTATION} -gt 1000 ]; then
  echo "❌ Error: Expected must be 1-1000 characters."
  exit 1
fi

if [ ${#INSTRUCTION} -eq 0 ] || [ ${#INSTRUCTION} -gt 2000 ]; then
  echo "❌ Error: Instruction must be 1-2000 characters."
  exit 1
fi
```

### Step 5: Database Recording

**Input Escaping** (SQL Injection Prevention):
```bash
# SQL Injection prevention: escape single quotes
escape_sql() {
  printf '%s' "$1" | sed "s/'/''/g"
}

SAFE_CATEGORY=$(escape_sql "$CATEGORY")
SAFE_SITUATION=$(escape_sql "$SITUATION")
SAFE_EXPECTATION=$(escape_sql "$EXPECTATION")
SAFE_INSTRUCTION=$(escape_sql "$INSTRUCTION")
```

Record to both tables using transaction (prevents race conditions):
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

Get current pattern count:
```bash
COUNT=$(sqlite3 "$DB_PATH" "SELECT count FROM patterns WHERE situation = '$SAFE_SITUATION' AND instruction = '$SAFE_INSTRUCTION';" 2>/dev/null || echo "1")
```

### Step 6: Output Result
English example:
```
✅ Record complete

Situation: {situation}
Expected: {expectation}
Instruction: {instruction}

Same pattern accumulated {count} times
```

If count is >= 2, add:
```
💡 You can promote this to a Skill with /calibrate review.
```
