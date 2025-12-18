---
name: skillfy init
description: Initialize Skillfy. Create database and directory structure.
allowed-tools: Bash(git:*), Bash(mkdir:*), Bash(sqlite3:*), Bash(chmod:*), Bash(test:*), Bash(rm:*), Bash(grep:*), Bash(echo:*), Bash(awk:*), Bash(sort:*), Bash(head:*), Bash(printf:*)
---

# /skillfy init

Initialize the Skillfy system.

## Execution Flow

### Step 0: Dependency Check
```bash
# Bash strict mode for safer script execution
set -euo pipefail
IFS=$'\n\t'

# Ensure UTF-8 locale for proper character handling
export LC_ALL=C.UTF-8 2>/dev/null || export LC_ALL=en_US.UTF-8 2>/dev/null || true

# Get project root (Git root or current directory as fallback)
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

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

# Check required dependencies
if ! command -v sqlite3 &> /dev/null; then
  echo "Error: sqlite3 is required but not installed."
  exit 1
fi

# SQLite 3.24.0+ required for compatibility
SQLITE_VERSION=$(sqlite3 --version 2>/dev/null | awk '{print $1}')
MIN_SQLITE_VERSION="3.24.0"
if ! version_ge "$SQLITE_VERSION" "$MIN_SQLITE_VERSION"; then
  echo "Error: SQLite $MIN_SQLITE_VERSION or higher required. Found: ${SQLITE_VERSION:-unknown}"
  exit 1
fi
```

### Step 1: Check Existing Installation
```bash
# NOTE: Avoid exiting in strict mode when directory does not exist
test -d "$PROJECT_ROOT/.claude/skillfy" || true
```

### Step 2: New Installation - User Confirmation

Ask the user for confirmation with a clear message:

```
Skillfy Initialization

This will create:
- .claude/skillfy/patterns.db (SQLite database for memos)
- .claude/skills/ directory (for promoted skills)

Options:
1. Initialize - Create new Skillfy database
2. Cancel

Which option? (1/2):
```

Wait for user response:
- User responds "1" or "yes" or "init" → Proceed with initialization
- User responds "2" or "cancel" → Exit with message: "Initialization cancelled."

On confirmation, execute Step 2-A, Step 2-B, and Step 2-C in order.

### Step 2-A: Create Directories and Database
```bash
# Create directories (with error handling)
if ! mkdir -p "$PROJECT_ROOT/.claude/skillfy"; then
  echo "Error: Failed to create .claude/skillfy directory"
  exit 1
fi
mkdir -p "$PROJECT_ROOT/.claude/skills"

# Set secure permissions
chmod 700 "$PROJECT_ROOT/.claude/skillfy"           # Owner only: rwx
chmod 700 "$PROJECT_ROOT/.claude/skills"            # Owner only: rwx

# Create DB with inline schema (v1.0)
if ! sqlite3 "$PROJECT_ROOT/.claude/skillfy/patterns.db" <<'SCHEMA_EOF'
-- Skillfy SQLite Schema v1.0

-- Patterns table: User memos for skill promotion
-- No UNIQUE constraint - allows duplicate entries (memo purpose)
CREATE TABLE IF NOT EXISTS patterns (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  situation   TEXT NOT NULL CHECK(length(situation) <= 500),
  expectation TEXT CHECK(length(expectation) <= 1000),
  instruction TEXT NOT NULL CHECK(length(instruction) <= 2000),
  created_at  DATETIME DEFAULT CURRENT_TIMESTAMP,
  promoted    INTEGER NOT NULL DEFAULT 0 CHECK(promoted IN (0, 1)),
  skill_path  TEXT
);

-- Schema version tracking
CREATE TABLE IF NOT EXISTS schema_version (
  version    TEXT PRIMARY KEY,
  applied_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Insert current schema version
INSERT OR IGNORE INTO schema_version (version) VALUES ('1.0');

-- Performance indexes
CREATE INDEX IF NOT EXISTS idx_patterns_promoted ON patterns(promoted);
CREATE INDEX IF NOT EXISTS idx_patterns_created_at ON patterns(created_at DESC);
SCHEMA_EOF
then
  rm -f "$PROJECT_ROOT/.claude/skillfy/patterns.db"
  echo "Error: Failed to create database"
  exit 1
fi

# Set secure permissions on DB file
chmod 600 "$PROJECT_ROOT/.claude/skillfy/patterns.db"     # Owner only: rw
```

### Step 2-B: Update .gitignore (REQUIRED for Git projects)

**IMPORTANT:** This step MUST be executed for Git projects to prevent accidental commits of sensitive data.

```bash
# Update .gitignore (for Git projects)
if [ -d "$PROJECT_ROOT/.git" ]; then
  GITIGNORE_ENTRIES="
# Skillfy runtime data (auto-added by /skillfy init)
.claude/skillfy/
.claude/skillfy/*.db-journal
.claude/skillfy/*.db-wal
.claude/skillfy/*.db-shm"

  if [ -f "$PROJECT_ROOT/.gitignore" ]; then
    # .gitignore exists: append if not already present
    if ! grep -q ".claude/skillfy/" "$PROJECT_ROOT/.gitignore"; then
      echo "$GITIGNORE_ENTRIES" >> "$PROJECT_ROOT/.gitignore"
      echo ".gitignore updated with Skillfy entries"
    else
      echo ".gitignore already contains Skillfy entries"
    fi
  else
    # .gitignore does not exist: create new file
    echo "$GITIGNORE_ENTRIES" > "$PROJECT_ROOT/.gitignore"
    echo ".gitignore file created with Skillfy entries"
  fi
fi
```

### Step 2-C: Verify .gitignore was updated
```bash
# Verify .gitignore contains skillfy entries
if [ -d "$PROJECT_ROOT/.git" ]; then
  if [ -f "$PROJECT_ROOT/.gitignore" ] && grep -q ".claude/skillfy/" "$PROJECT_ROOT/.gitignore"; then
    echo ".gitignore verification passed"
  else
    echo "Warning: .gitignore may not be properly configured"
  fi
fi
```

### Step 3: When Already Exists

If `.claude/skillfy` directory exists (from Step 1), display:

```
Skillfy already exists

Current files:
- .claude/skillfy/patterns.db

Options:
1. Keep existing data - Exit without changes
2. Reinitialize - Delete all data and start fresh

Select option (1/2):
```

Wait for user response:
- User responds "1" or "keep" → Exit with message: "Keeping existing installation."
- User responds "2" or "reinitialize" → Execute cleanup and proceed to Step 2

**Step 3-A: Reinitialize (cleanup)**
```bash
rm -rf "$PROJECT_ROOT/.claude/skillfy"
echo "Existing data removed"
# Then proceed with new installation (Step 2)
```

### Step 4: Completion Message
```
Skillfy initialization complete

- .claude/skillfy/patterns.db created
- .claude/skills/ directory created
- .gitignore updated (if Git project)

You can now record mismatches with /skillfy.
Use /skillfy review to promote saved patterns to skills.
```
