---
name: skillfy review
description: Review saved patterns and promote to Skills
allowed-tools: Bash(git:*), Bash(sqlite3:*), Bash(test:*), Bash(mkdir:*), Bash(sed:*), Bash(printf:*), Bash(tr:*), Bash(cut:*), Bash(date:*), Bash(echo:*), Bash(awk:*)
---

# /skillfy review

Review saved patterns and promote them to Skills.

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
SKILL_OUTPUT_PATH="$PROJECT_ROOT/.claude/skills"

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

# SQLite 3.24.0+ required
SQLITE_VERSION=$(sqlite3 --version 2>/dev/null | awk '{print $1}')
MIN_SQLITE_VERSION="3.24.0"
if ! version_ge "$SQLITE_VERSION" "$MIN_SQLITE_VERSION"; then
  echo "Error: SQLite $MIN_SQLITE_VERSION or higher required. Found: ${SQLITE_VERSION:-unknown}"
  exit 1
fi

if [ ! -f "$DB_PATH" ]; then
  echo "Skillfy is not initialized. Run /skillfy init first."
  exit 1
fi

# ============================================================================
# Path Validation
# ============================================================================

# POSIX-compatible path resolution (macOS/Linux)
resolve_path() {
  local p="$1"
  # Try GNU realpath, then Python fallback for macOS compatibility
  realpath -m "$p" 2>/dev/null || python3 -c "import os; print(os.path.abspath('$p'))" 2>/dev/null || echo ""
}

# Path traversal protection: validate that a path is under allowed directory
validate_skill_path() {
  local path="$1"
  local resolved_path resolved_base

  # Resolve to absolute path and check it's under SKILL_OUTPUT_PATH
  resolved_path=$(resolve_path "$path")
  resolved_base=$(resolve_path "$SKILL_OUTPUT_PATH")

  if [ -z "$resolved_path" ] || [ -z "$resolved_base" ]; then
    return 1
  fi

  # Check path starts with base directory
  case "$resolved_path" in
    "$resolved_base"/*) return 0 ;;
    *) return 1 ;;
  esac
}
```

## Flow

### Step 1: Query Unpromoted Patterns
```bash
# Query all unpromoted patterns
# Columns: id, situation, instruction, expectation, created_at
CANDIDATES=$(sqlite3 -separator $'\t' "$DB_PATH" \
  "SELECT id, situation, instruction, expectation, created_at FROM patterns WHERE promoted = 0 ORDER BY created_at DESC LIMIT 50;" \
  2>/dev/null) || CANDIDATES=""
```

### Step 2-A: No Candidates
```
No saved patterns found.

Use /skillfy to record patterns first.
```

### Step 2-B: Candidates Found

Display the candidates list with selection options:
```
Saved Patterns (not yet promoted)

[id=12] When creating models -> Always include timestamp fields (2024-12-18)
[id=15] When writing API endpoints -> Always include error handling (2024-12-17)

Enter pattern id(s) to promote (comma-separated for multiple, or 'skip' to cancel):
Example: 12 or 12,15
```

Note: The list should be dynamically generated from the CANDIDATES query result.

Wait for user response:
- User responds with id(s) (e.g., "12" or "12,15") → Parse and process each PATTERN_ID
- User responds "skip" or "cancel" → Exit with message: "No patterns promoted."

### Step 3: Load Pattern Details
For each selected `PATTERN_ID`:
```bash
# Validate id defensively
if ! [[ "$PATTERN_ID" =~ ^[0-9]+$ ]]; then
  echo "Error: Invalid pattern id '$PATTERN_ID'"
  exit 1
fi

ROW=$(sqlite3 -separator $'\t' "$DB_PATH" \
  "SELECT situation, instruction, expectation, created_at FROM patterns WHERE id = $PATTERN_ID AND promoted = 0;" \
  2>/dev/null) || ROW=""

if [ -z "$ROW" ]; then
  echo "Error: Pattern not found or already promoted (id=$PATTERN_ID)"
  exit 1
fi

IFS=$'\t' read -r SITUATION INSTRUCTION EXPECTATION CREATED_AT <<<"$ROW"
```

### Step 4: Skill Preview and Confirmation

Display the skill preview:
```
Skill Preview: {situation}

---
name: {kebab-case situation}
description: {instruction}. Auto-applied in {situation} situations.
learned_from: skillfy ({created_at})
---

## Rules

{instruction}

## Applies to

- {situation}

## Learning History

This Skill was created from a saved pattern.
- Created: {created_at}
- Source: /skillfy memo
```

Then ask the user for confirmation:

```
What would you like to do with this skill?

1. Save skill (Recommended) - Create the skill file and activate it
2. Edit first - Modify the instruction before saving
3. Skip - Don't create this skill

Select action (1/2/3):
```

Wait for user response:
- User responds "1" or "save" → Proceed to Step 5
- User responds "2" or "edit" → Ask "Enter the modified instruction:" and wait for response, then proceed to Step 5
- User responds "3" or "skip" → Skip this pattern and continue to next (if any)

### Step 5: Skill Creation
On save selection:
```bash
# Generate Skill name (kebab-case) - Path Traversal prevention
SKILL_NAME=$(printf '%s' "$SITUATION" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | sed 's/[^a-z0-9-]//g')
# Collapse multiple consecutive hyphens and remove leading/trailing hyphens
SKILL_NAME=$(printf '%s' "$SKILL_NAME" | sed 's/-\{2,\}/-/g; s/^-//; s/-$//')
SKILL_NAME=$(printf '%s' "$SKILL_NAME" | cut -c1-50)
# Remove any trailing hyphen that might result from truncation
SKILL_NAME=$(printf '%s' "$SKILL_NAME" | sed 's/-$//')
if [ -z "$SKILL_NAME" ]; then
  SKILL_NAME="skill-$(date +%Y%m%d-%H%M%S)"
fi

# Handle skill name collisions atomically using mkdir
mkdir -p "$SKILL_OUTPUT_PATH"

MAX_SKILL_NAME_ATTEMPTS="${SKILLFY_MAX_NAME_ATTEMPTS:-100}"

BASE_SKILL_NAME="$SKILL_NAME"
SUFFIX=0
SKILL_DIR=""

while [ $SUFFIX -le $MAX_SKILL_NAME_ATTEMPTS ]; do
  if [ $SUFFIX -eq 0 ]; then
    CURRENT_NAME="$BASE_SKILL_NAME"
  else
    CURRENT_NAME="${BASE_SKILL_NAME}-${SUFFIX}"
  fi

  # Validate path before creation
  CURRENT_PATH="$SKILL_OUTPUT_PATH/$CURRENT_NAME"
  if ! validate_skill_path "$CURRENT_PATH"; then
    echo "Error: Invalid skill path detected (potential path traversal)"
    exit 1
  fi

  # mkdir (without -p) fails if directory exists - atomic check+create
  if mkdir "$CURRENT_PATH" 2>/dev/null; then
    SKILL_NAME="$CURRENT_NAME"
    SKILL_DIR="$CURRENT_PATH"
    break
  fi
  SUFFIX=$((SUFFIX + 1))
done

if [ -z "$SKILL_DIR" ]; then
  echo "Error: Failed to generate unique skill name after $MAX_SKILL_NAME_ATTEMPTS attempts"
  exit 1
fi

# Create skill file
CURRENT_DATE=$(date '+%Y-%m-%d %H:%M:%S')

cat > "$SKILL_DIR/SKILL.md" << SKILL_EOF
---
name: $SKILL_NAME
description: $INSTRUCTION. Auto-applied in $SITUATION situations.
learned_from: skillfy ($CREATED_AT)
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

- Original created: $CREATED_AT
- Promoted to skill: $CURRENT_DATE
- Source: /skillfy review
SKILL_EOF

# SQL Injection prevention: escape single quotes
escape_sql() {
  printf '%s' "$1" | sed "s/'/''/g"
}
SAFE_SKILL_PATH=$(escape_sql "$SKILL_DIR/SKILL.md")

# Update database
if ! sqlite3 "$DB_PATH" "UPDATE patterns SET promoted = 1, skill_path = '$SAFE_SKILL_PATH' WHERE id = $PATTERN_ID;"; then
  echo "Warning: Skill file created but database update failed"
  echo "Skill path: $SKILL_DIR/SKILL.md"
fi

printf '\nSkill created: %s/SKILL.md\n\nRestart Claude Code to activate this skill.\n' "$SKILL_DIR"
```

## Reference: Skill Name Conversion Rules

- Space → hyphen
- Uppercase → lowercase
- Remove special characters
- Example: "Model creation" → "model-creation"
- Example: "API endpoint" → "api-endpoint"
