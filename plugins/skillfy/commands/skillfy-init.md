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

# Create DB with inline schema (v2.0)
if ! sqlite3 "$PROJECT_ROOT/.claude/skillfy/patterns.db" <<'SCHEMA_EOF'
-- Skillfy SQLite Schema v2.0

-- Patterns table: User memos for skill promotion
-- No UNIQUE constraint - allows duplicate entries (memo purpose)
CREATE TABLE IF NOT EXISTS patterns (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  situation   TEXT NOT NULL CHECK(length(situation) <= 500),
  expectation TEXT CHECK(length(expectation) <= 1000),
  instruction TEXT NOT NULL CHECK(length(instruction) <= 2000),
  created_at  DATETIME DEFAULT CURRENT_TIMESTAMP,
  promoted    INTEGER NOT NULL DEFAULT 0 CHECK(promoted IN (0, 1)),
  skill_path  TEXT,
  notes       TEXT
);

-- Schema version tracking
CREATE TABLE IF NOT EXISTS schema_version (
  version    TEXT PRIMARY KEY,
  applied_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Insert current schema version
INSERT OR IGNORE INTO schema_version (version) VALUES ('2.0');

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

If `.claude/skillfy` directory exists (from Step 1):

**Step 3-A: Check Schema Version**
```bash
DB_PATH="$PROJECT_ROOT/.claude/skillfy/patterns.db"
CURRENT_VERSION=""
NEEDS_MIGRATION="no"

if [ -f "$DB_PATH" ]; then
  # Get current schema version
  CURRENT_VERSION=$(sqlite3 "$DB_PATH" "SELECT version FROM schema_version ORDER BY applied_at DESC LIMIT 1;" 2>/dev/null || echo "")

  # If no version found, assume 1.0 (pre-versioning)
  if [ -z "$CURRENT_VERSION" ]; then
    CURRENT_VERSION="1.0"
  fi

  # Check if migration is needed (target: 2.0)
  case "$CURRENT_VERSION" in
    2.0) NEEDS_MIGRATION="no" ;;
    *) NEEDS_MIGRATION="yes" ;;
  esac
fi
```

**Step 3-B: Display Options Based on Migration Status**

If `NEEDS_MIGRATION="yes"`, display:
```
Skillfy already exists (schema v{CURRENT_VERSION})

A database upgrade is available (v{CURRENT_VERSION} -> v2.0).

Changes in v2.0:
- Simplified schema (memo-focused)
- Removed auto-detection features
- Removed count/threshold system

Options:
1. Upgrade database - Migrate to v2.0 (preserves pattern data)
2. Keep as-is - Exit without changes (some features may not work)
3. Reinitialize - Delete all data and start fresh with v2.0

Select option (1/2/3):
```

Wait for user response:
- User responds "1" or "upgrade" → Execute migration (Step 3-C)
- User responds "2" or "keep" → Exit with message: "Keeping existing installation. Note: Some features may not work with older schema."
- User responds "3" or "reinitialize" → Execute cleanup and proceed to Step 2

If `NEEDS_MIGRATION="no"` (already at v2.0), display:
```
Skillfy already exists (schema v2.0 - up to date)

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

**Step 3-C: Execute Migration (v1.x -> v2.0)**
```bash
echo "Migrating database schema to v2.0..."

# Create new patterns table with v2.0 schema
sqlite3 "$DB_PATH" <<'MIGRATION_EOF'
-- Create new patterns table
CREATE TABLE IF NOT EXISTS patterns_v2 (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  situation   TEXT NOT NULL CHECK(length(situation) <= 500),
  expectation TEXT CHECK(length(expectation) <= 1000),
  instruction TEXT NOT NULL CHECK(length(instruction) <= 2000),
  created_at  DATETIME DEFAULT CURRENT_TIMESTAMP,
  promoted    INTEGER NOT NULL DEFAULT 0 CHECK(promoted IN (0, 1)),
  skill_path  TEXT,
  notes       TEXT
);

-- Migrate existing data (only situation, instruction, promoted, skill_path)
INSERT INTO patterns_v2 (situation, instruction, created_at, promoted, skill_path)
SELECT situation, instruction, first_seen, promoted, skill_path
FROM patterns WHERE 1=1;

-- Drop old tables
DROP TABLE IF EXISTS patterns;
DROP TABLE IF EXISTS observations;

-- Rename new table
ALTER TABLE patterns_v2 RENAME TO patterns;

-- Drop old indexes (they reference dropped columns)
DROP INDEX IF EXISTS idx_observations_situation;
DROP INDEX IF EXISTS idx_observations_timestamp;
DROP INDEX IF EXISTS idx_patterns_count;
DROP INDEX IF EXISTS idx_patterns_dismissed;
DROP INDEX IF EXISTS idx_patterns_situation_instruction;
DROP INDEX IF EXISTS idx_patterns_review;

-- Create new indexes
CREATE INDEX IF NOT EXISTS idx_patterns_promoted ON patterns(promoted);
CREATE INDEX IF NOT EXISTS idx_patterns_created_at ON patterns(created_at DESC);

-- Update schema version
INSERT OR REPLACE INTO schema_version (version) VALUES ('2.0');
MIGRATION_EOF

if [ $? -ne 0 ]; then
  echo "Error: Migration failed"
  exit 1
fi

# Remove auto-detect flag file (no longer used)
rm -f "$PROJECT_ROOT/.claude/skillfy/auto-detect.enabled"

echo "Database migrated to schema v2.0"
```

After successful migration, display completion message and exit.

**Step 3-D: Reinitialize (cleanup)**
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
