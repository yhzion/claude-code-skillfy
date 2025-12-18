---
name: skillfy
description: Record LLM expectation mismatches. Guide to initialize if not initialized.
allowed-tools: Bash(git:*), Bash(sqlite3:*), Bash(test:*), Bash(sed:*), Bash(printf:*), Bash(echo:*), AskUserQuestion
---

# /skillfy

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
DB_PATH="$PROJECT_ROOT/.claude/skillfy/patterns.db"

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
  echo "Error: sqlite3 is required but not installed."
  exit 1
fi

SQLITE_VERSION=$(sqlite3 --version 2>/dev/null | awk '{print $1}')
MIN_SQLITE_VERSION="3.24.0"
if ! version_ge "$SQLITE_VERSION" "$MIN_SQLITE_VERSION"; then
  echo "Error: SQLite $MIN_SQLITE_VERSION or higher required. Found: ${SQLITE_VERSION:-unknown}"
  exit 1
fi

if [ ! -f "$DB_PATH" ]; then
  echo "Skillfy is not initialized. Run /skillfy-init first."
  exit 1
fi
```

## Recording Flow

### Step 1: Session Context Analysis (Agent Introspection)

**IMPORTANT: This step requires Agent introspection, not programmatic script execution.**

Analyze the current conversation session to identify potential mismatches:

1. **Review recent interactions**:
   - What did the user request?
   - How did Claude respond?
   - What tools were used (especially Bash)?

2. **Identify issues/mismatches**:
   - Bash execution errors (exit code != 0)
   - Lint/type/build/test failures
   - User correction requests ("no", "not that", "try again", etc.)
   - Unexpected results or behaviors

3. **Rank identified issues by probability**:
   - **High**: Clear error messages or explicit user corrections
   - **Medium**: Warnings or implicit dissatisfaction
   - **Low**: Inferred possibilities

4. **Generate dynamic options** based on analysis:
   - Create 1-3 specific situation descriptions (50 chars max each)
   - Order by probability (highest first)
   - Always include "Enter manually" as the last option

### Step 2: Situation Selection (Dynamic)

Use AskUserQuestion to present situation options to the user.

**Option Generation Rules**:
- Minimum 1, maximum 3 specific options based on context analysis
- Each option should be a concrete situation description
- Last option is always "Enter manually"

**If context analysis found issues**, present like:
```
Recording Pattern Mismatch

What situation did this happen in?

1. {Most likely situation from analysis}
2. {Second most likely situation} (if applicable)
3. {Third situation} (if applicable)
4. Enter manually

Select:
```

**If no clear issues found in context**, present:
```
Recording Pattern Mismatch

What situation did this happen in?

1. Enter manually

Describe the situation:
```

**On "Enter manually" selection**, prompt:
```
Describe the situation (max 500 chars):
Example: "When creating a model", "When writing API endpoints"
```

Save user's selection or input as `SITUATION`.

### Step 3: Expectation Selection (Dynamic)

Based on the selected SITUATION, generate expectation options.

**Option Generation Rules**:
- Analyze what typically goes wrong in the selected situation
- Create 1-3 specific expectation descriptions
- Consider the context analysis from Step 1
- Last option is always "Enter manually"

**Present like**:
```
What did you expect?

1. {Most likely expectation based on situation}
2. {Second expectation} (if applicable)
3. {Third expectation} (if applicable)
4. Enter manually

Select:
```

**On "Enter manually" selection**, prompt:
```
Describe what you expected (max 1000 chars):
Example: "Include timestamp field", "Use TypeScript interfaces"
```

Save user's selection or input as `EXPECTATION`.

### Step 4: Instruction Selection (Dynamic)

Based on SITUATION + EXPECTATION, generate instruction options.

**Option Generation Rules**:
- Instructions must be imperative form ("Always...", "Never...", "Include...")
- Create 1-3 specific, actionable instructions
- Last option is always "Enter manually"

**Present like**:
```
What rule should Claude learn? (imperative form)

1. {Most appropriate instruction}
2. {Second instruction} (if applicable)
3. {Third instruction} (if applicable)
4. Enter manually

Select:
```

**On "Enter manually" selection**, prompt:
```
Enter the instruction (imperative form, max 2000 chars):
Example: "Always include timestamp fields", "Never use var in JavaScript"
```

Save user's selection or input as `INSTRUCTION`.

### Step 5: Summary and Final Action Selection

Display summary and ask for final action:

```
Record Summary

Situation: {SITUATION}
Expected: {EXPECTATION}
Instruction: {INSTRUCTION}

What would you like to do?

1. Register as Skill - Create skill file immediately (requires session restart to activate)
2. Save as memo - Store in DB for later review with /skillfy review
3. Cancel - Do nothing

Select (1/2/3):
```

Wait for user response and save as `FINAL_ACTION`.

### Step 6: Input Validation
```bash
# Basic length checks (match DB CHECK constraints)
if [ ${#SITUATION} -eq 0 ] || [ ${#SITUATION} -gt 500 ]; then
  echo "Error: Situation must be 1-500 characters."
  exit 1
fi

if [ ${#EXPECTATION} -gt 1000 ]; then
  echo "Error: Expectation must be 0-1000 characters."
  exit 1
fi

if [ ${#INSTRUCTION} -eq 0 ] || [ ${#INSTRUCTION} -gt 2000 ]; then
  echo "Error: Instruction must be 1-2000 characters."
  exit 1
fi
```

### Step 7: Execute Selected Action

**Option 1: Register as Skill**

```bash
# SQL Injection prevention: escape single quotes
escape_sql() {
  printf '%s' "$1" | sed "s/'/''/g"
}

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
SKILL_OUTPUT_PATH="$PROJECT_ROOT/.claude/skills"
TEMPLATE_PATH="${CLAUDE_PLUGIN_ROOT:-$PROJECT_ROOT/plugins/skillfy}/templates/skill-template.md"

# Generate skill name from situation (kebab-case)
SKILL_NAME=$(printf '%s' "$SITUATION" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | sed 's/[^a-z0-9-]//g')
SKILL_NAME=$(printf '%s' "$SKILL_NAME" | sed 's/-\{2,\}/-/g; s/^-//; s/-$//')
SKILL_NAME=$(printf '%s' "$SKILL_NAME" | cut -c1-50 | sed 's/-$//')
if [ -z "$SKILL_NAME" ]; then
  SKILL_NAME="skill-$(date +%Y%m%d-%H%M%S)"
fi

# Create skill directory
mkdir -p "$SKILL_OUTPUT_PATH"
SKILL_DIR="$SKILL_OUTPUT_PATH/$SKILL_NAME"

# Handle name collision
SUFFIX=0
BASE_NAME="$SKILL_NAME"
while [ -d "$SKILL_DIR" ]; do
  SUFFIX=$((SUFFIX + 1))
  if [ "$SUFFIX" -gt 100 ]; then
    echo "Error: Too many skill name collisions"
    exit 1
  fi
  SKILL_NAME="${BASE_NAME}-${SUFFIX}"
  SKILL_DIR="$SKILL_OUTPUT_PATH/$SKILL_NAME"
done
mkdir "$SKILL_DIR"

# Generate skill file from template
CURRENT_DATE=$(date '+%Y-%m-%d %H:%M:%S')

# Escape for sed replacement
escape_sed() {
  printf '%s' "$1" | sed 's/[&/\]/\\&/g; s/$/\\n/' | tr -d '\n' | sed 's/\\n$//'
}

SAFE_SKILL_NAME=$(escape_sed "$SKILL_NAME")
SAFE_INSTRUCTION=$(escape_sed "$INSTRUCTION")
SAFE_SITUATION=$(escape_sed "$SITUATION")

# Create skill file
cat > "$SKILL_DIR/SKILL.md" << SKILL_EOF
---
name: $SKILL_NAME
description: $INSTRUCTION. Auto-applied in $SITUATION situations.
learned_from: skillfy ($CURRENT_DATE)
---

## Rules

$INSTRUCTION

## Applies to

- $SITUATION

## Examples

### Do

(Add positive examples here)

### Don't

(Add negative examples here)

## Learning History

- Created: $CURRENT_DATE
- Source: Manual recording via /skillfy
SKILL_EOF

# Also save to DB as promoted
SAFE_SITUATION_SQL=$(escape_sql "$SITUATION")
SAFE_EXPECTATION_SQL=$(escape_sql "$EXPECTATION")
SAFE_INSTRUCTION_SQL=$(escape_sql "$INSTRUCTION")
SAFE_SKILL_PATH=$(escape_sql "$SKILL_DIR/SKILL.md")

sqlite3 "$DB_PATH" <<SQL
INSERT INTO patterns (situation, expectation, instruction, promoted, skill_path)
VALUES ('$SAFE_SITUATION_SQL', '$SAFE_EXPECTATION_SQL', '$SAFE_INSTRUCTION_SQL', 1, '$SAFE_SKILL_PATH');
SQL

echo ""
echo "Skill created: $SKILL_DIR/SKILL.md"
echo ""
echo "Restart Claude Code to activate this skill."
```

**Option 2: Save as Memo**

```bash
escape_sql() {
  printf '%s' "$1" | sed "s/'/''/g"
}

SAFE_SITUATION=$(escape_sql "$SITUATION")
SAFE_EXPECTATION=$(escape_sql "$EXPECTATION")
SAFE_INSTRUCTION=$(escape_sql "$INSTRUCTION")

sqlite3 "$DB_PATH" <<SQL
INSERT INTO patterns (situation, expectation, instruction)
VALUES ('$SAFE_SITUATION', '$SAFE_EXPECTATION', '$SAFE_INSTRUCTION');
SQL

if [ $? -ne 0 ]; then
  echo "Error: Failed to save pattern"
  exit 1
fi

echo ""
echo "Pattern saved to database."
echo ""
echo "Use /skillfy review to view saved patterns and promote to skills."
```

**Option 3: Cancel**

```
Cancelled. No changes made.
```
