---
name: skillfy reset
description: Reset Skillfy data (dangerous)
arguments:
  - name: mode
    description: "Reset mode: default (data only) or --all (data + skills + DB file)"
    required: false
allowed-tools: Bash(git:*), Bash(sqlite3:*), Bash(test:*), Bash(echo:*), Bash(rm:*), Bash(rmdir:*), Bash(ls:*), Bash(wc:*), Bash(tr:*)
---

# /skillfy reset [--all]

⚠️ Deletes Skillfy data.

## Usage

- `/skillfy reset` - Delete database records only (skills preserved)
- `/skillfy reset --all` - Delete everything: database, skills, and all Skillfy files

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

if ! command -v sqlite3 &> /dev/null; then
  echo "❌ Error: sqlite3 is required but not installed."
  exit 1
fi

if [ ! -f "$DB_PATH" ]; then
  echo "❌ No data to reset."
  exit 1
fi
```

## Flow

### Step 1: Display Current Status
```bash
TOTAL_PATTERNS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM patterns;" 2>/dev/null || echo "0")
```

### Step 2: Determine Reset Mode and Count Skills

Check if `--all` argument was provided and count generated skills:
```bash
SKILL_COUNT=$(ls -1 "$PROJECT_ROOT/.claude/skills/skillfy-"* 2>/dev/null | wc -l | tr -d ' ') || SKILL_COUNT=0

# Count promoted skills (will become orphaned if data is reset without --all)
PROMOTED_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM patterns WHERE promoted = 1;" 2>/dev/null || echo "0")
```

### Step 3: Request Confirmation

**Default mode (data only):**
Display the warning message:
```
⚠️ Skillfy Reset (Data Only)

Database file:
- {DB_PATH}

Data to delete:
- {TOTAL_PATTERNS} patterns

Note: Generated Skills (.claude/skills/) will be preserved.
```

If `PROMOTED_COUNT > 0`, also display an orphan skills warning:
```
⚠️ Orphan Skills Warning

{PROMOTED_COUNT} promoted Skill(s) will become orphaned:
- Skill files in .claude/skills/ will remain but lose their DB connection
- These skills will still work but cannot be managed via /skillfy commands

To completely remove everything including skills, use: /skillfy reset --all
```

Then ask the user for confirmation:
```
⚠️ Are you sure you want to delete all Skillfy data?
This action cannot be undone.

1. Yes, reset data - Delete all observations and patterns permanently
2. Cancel - Keep all data and exit

Confirm (1/2):
```

**--all mode (complete reset):**
Display the warning message:
```
⚠️ Skillfy Complete Reset

This will delete EVERYTHING:
- Database file: {DB_PATH}
- {TOTAL_PATTERNS} patterns
- {SKILL_COUNT} generated skills (.claude/skills/)
- Skillfy directory

⚠️ This action cannot be undone!
```

Then ask the user for confirmation:
```
Are you sure you want to completely remove all Skillfy data and skills?

1. Yes, delete everything - Remove all data, skills, and files
2. Reset data only - Keep skills, delete database records
3. Cancel - Keep everything and exit

Confirm (1/2/3):
```

### Step 4: User Choice Handling

**Default mode:**
- User responds "1" or "yes" → Proceed to Step 5 (data deletion)
- User responds "2" or "cancel" → Print "Reset cancelled." and exit

**--all mode:**
- User responds "1" → Proceed to Step 5 (complete deletion)
- User responds "2" → Proceed to Step 5 (data only deletion)
- User responds "3" or "cancel" → Print "Reset cancelled." and exit

### Step 5: Execute Deletion

**Data only deletion:**
```bash
# Clear data using transaction (safer than rm + recreate)
# Transaction ensures atomicity: on failure, data is preserved via rollback
if ! sqlite3 "$DB_PATH" <<SQL
BEGIN IMMEDIATE;
DELETE FROM patterns;
COMMIT;
SQL
then
  echo "Error: Failed to reset database"
  exit 1
fi
```

**Complete deletion (--all mode, option 1):**
```bash
# Remove all skills
rm -rf "$PROJECT_ROOT/.claude/skills" 2>/dev/null || true

# Remove database file
rm -f "$DB_PATH"

# Remove auto-detect flag (legacy cleanup)
rm -f "$PROJECT_ROOT/.claude/skillfy/auto-detect.enabled"

# Remove skillfy directory
rm -rf "$PROJECT_ROOT/.claude/skillfy" 2>/dev/null || true
```

### Step 6: Completion Message

**Data only:**
```
Skillfy data has been reset

- Patterns: all deleted
- Skills: preserved (.claude/skills/)

Start new records with /skillfy.
```

**Complete reset:**
```
Skillfy completely removed

- Database: deleted
- Patterns: deleted
- Skills: deleted

Run /skillfy-init to start fresh.
```
