---
name: auto-calibrate
description: Automatically detect and record error correction patterns when fixing lint, format, type check, build, or test errors. Triggers when Claude fixes recurring issues and suggests skill promotion when patterns repeat 2+ times.
---

# Auto-Calibrate Skill

This skill automatically detects and records error correction patterns without requiring manual `/calibrate` command execution.

## When This Skill Activates

Activate this skill when ALL of the following conditions are met:

1. **Error Detection**: You encountered an error or warning from:
   - Linting tools (ESLint, Prettier, Biome, etc.)
   - Type checking (TypeScript, Flow, etc.)
   - Build processes (Webpack, Vite, esbuild, etc.)
   - Test runners (Jest, Vitest, pytest, etc.)
   - Format checkers

2. **Error Resolution**: You successfully fixed the error

3. **Pattern Recognition**: The fix represents a learnable pattern that could apply to future similar situations

## What NOT to Record

Do NOT record patterns for:
- One-time typos or simple mistakes
- Project-specific configurations that won't recur
- User-requested changes (not error corrections)
- Obvious bugs with no learning value

## Automatic Recording Process

When conditions are met, execute the following steps:

### Step 1: Check Calibrator Initialization and Auto-Detection Setting

```bash
set -euo pipefail

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
DB_PATH="$PROJECT_ROOT/.claude/calibrator/patterns.db"
FLAG_FILE="$PROJECT_ROOT/.claude/calibrator/auto-detect.enabled"

# Check if calibrator is initialized
if [ ! -f "$DB_PATH" ]; then
  echo "⚠️ Calibrator not initialized. Run /calibrate init first to enable auto-learning."
  exit 0
fi

# Check if auto-detection is enabled
if [ ! -f "$FLAG_FILE" ]; then
  # Auto-detection is disabled, skip recording
  exit 0
fi
```

### Step 2: Determine Category

Categorize the error correction:
- `missing`: Something was missing (missing import, missing type, missing config)
- `excess`: Something unnecessary was present (unused variable, redundant code)
- `style`: Different approach preferred (formatting, naming convention)
- `other`: Other type of correction

### Step 3: Extract Pattern Information

Identify and format:
- **SITUATION**: Brief description of when this error occurs (max 500 chars)
  - Example: "When using async/await in TypeScript"
- **EXPECTATION**: What was expected vs what happened (max 1000 chars)
  - Example: "Expected proper error handling with try-catch"
- **INSTRUCTION**: Imperative rule to prevent future occurrences (max 2000 chars)
  - Example: "Always wrap async/await calls in try-catch blocks with typed error handling"

### Step 4: Record to Database

```bash
set -euo pipefail

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
DB_PATH="$PROJECT_ROOT/.claude/calibrator/patterns.db"
THRESHOLD=2

# SQL Injection prevention
escape_sql() {
  printf '%s' "$1" | sed "s/'/''/g"
}

# Variables to be filled by Claude based on the error correction
CATEGORY="{{CATEGORY}}"        # missing|excess|style|other
SITUATION="{{SITUATION}}"      # Brief situation description
EXPECTATION="{{EXPECTATION}}"  # What was expected
INSTRUCTION="{{INSTRUCTION}}"  # Rule to learn

SAFE_CATEGORY=$(escape_sql "$CATEGORY")
SAFE_SITUATION=$(escape_sql "$SITUATION")
SAFE_EXPECTATION=$(escape_sql "$EXPECTATION")
SAFE_INSTRUCTION=$(escape_sql "$INSTRUCTION")

# Record using transaction
sqlite3 "$DB_PATH" <<SQL
BEGIN IMMEDIATE;

INSERT INTO observations (category, situation, expectation)
VALUES ('$SAFE_CATEGORY', '$SAFE_SITUATION', '$SAFE_EXPECTATION');

INSERT INTO patterns (situation, instruction, count)
VALUES ('$SAFE_SITUATION', '$SAFE_INSTRUCTION', 1)
ON CONFLICT(situation, instruction)
DO UPDATE SET count = count + 1, last_seen = CURRENT_TIMESTAMP;

COMMIT;
SQL

# Get current pattern count
COUNT=$(sqlite3 "$DB_PATH" "SELECT count FROM patterns WHERE situation = '$SAFE_SITUATION' AND instruction = '$SAFE_INSTRUCTION';" 2>/dev/null || echo "1")

echo "COUNT=$COUNT"
```

### Step 5: Notify User

After recording, inform the user with a brief message:

```
📝 Auto-recorded pattern: {brief situation summary}
   Category: {category} | Occurrences: {count}
```

If count >= 2, add promotion suggestion:

```
💡 This pattern has occurred {count} times. Consider promoting to a skill with /calibrate review
```

## Output Format

When this skill activates, use this format to notify the user:

```
┌─ 🔄 Auto-Calibrate ──────────────────────────────┐
│ Recorded: "{situation_summary}"                  │
│ Category: {category} | Occurrences: {count}      │
└──────────────────────────────────────────────────┘
```

If count >= 2, add promotion suggestion on a new line:
```
💡 Pattern repeated {count}x → /calibrate review to promote to skill
```

## Important Notes

- Only record genuinely learnable patterns
- Keep descriptions concise but informative
- The instruction should be actionable and specific
- Do not interrupt user workflow - record silently and report briefly
- If DB is not initialized, suggest `/calibrate init` once and continue without blocking
