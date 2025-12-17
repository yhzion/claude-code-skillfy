---
name: calibrate init
description: Initialize Calibrator. Create database and config files.
---

# /calibrate init

Initialize the Calibrator system.

## i18n Message Reference

All user-facing messages reference `plugins/calibrator/i18n/messages.json`.
Language setting is stored in the `language` field of `.claude/calibrator/config.json`.

Supported languages:
- `en` - English (default)
- `ko` - Korean (한국어)
- `ja` - Japanese (日本語)
- `zh` - Chinese (中文)

## Execution Flow

### Step 0: Dependency Check
```bash
# Bash strict mode for safer script execution
set -euo pipefail
IFS=$'\n\t'

# Check required dependencies
check_dependency() {
  if ! command -v "$1" &> /dev/null; then
    echo "❌ Error: $1 is required but not installed."
    exit 1
  fi
}

check_dependency sqlite3
check_dependency jq

# Config schema validation function
validate_config() {
  local config_file="$1"

  # Check if config file exists and is valid JSON
  if [ ! -f "$config_file" ]; then
    return 1
  fi

  # Validate required fields exist and have correct types
  if ! jq -e '.language and .threshold and .skill_output_path and .db_path' "$config_file" >/dev/null 2>&1; then
    echo "⚠️ Warning: config.json is missing required fields. Will use defaults."
    return 1
  fi

  # Validate language is one of supported values
  local lang=$(jq -r '.language' "$config_file" 2>/dev/null)
  case "$lang" in
    en|ko|ja|zh) ;;
    *)
      echo "⚠️ Warning: Invalid language '$lang' in config. Using 'en'."
      return 1
      ;;
  esac

  # Validate threshold is a positive integer
  local threshold=$(jq -r '.threshold' "$config_file" 2>/dev/null)
  if ! [[ "$threshold" =~ ^[1-9][0-9]*$ ]]; then
    echo "⚠️ Warning: Invalid threshold '$threshold' in config. Using '2'."
    return 1
  fi

  return 0
}
```

### Step 1: Check Existing Installation
```bash
test -d .claude/calibrator
```

### Step 2-A: New Installation - Language Selection
```
🌐 Select Language

Choose your preferred language for Calibrator:

1. English (default)
2. Korean (한국어)
3. Japanese (日本語)
4. Chinese (中文)

[1-4]: _
```

Language mapping (with input validation):
```bash
# Input validation and mapping
validate_language() {
  case "$1" in
    1|"") echo "en" ;;
    2)    echo "ko" ;;
    3)    echo "ja" ;;
    4)    echo "zh" ;;
    *)    echo "" ;;  # Invalid input
  esac
}

LANG_CODE=$(validate_language "$USER_INPUT")
if [ -z "$LANG_CODE" ]; then
  echo "❌ Invalid selection. Please enter 1-4."
  # Return to selection screen
fi
```

### Step 2-B: New Installation - Confirmation
Display messages in the selected language. (English example below)
```
⚙️ Calibrator Initialization

Files to create:
- .claude/calibrator/patterns.db
- .claude/calibrator/config.json

[Confirm] [Cancel]
```

On confirmation:
```bash
# Create directories (with error handling)
if ! mkdir -p .claude/calibrator; then
  echo "❌ Error: Failed to create .claude/calibrator directory"
  exit 1
fi
mkdir -p .claude/skills/learned

# Set secure permissions
chmod 700 .claude/calibrator        # Owner only: rwx
chmod 700 .claude/skills/learned    # Owner only: rwx

# Create DB from schema.sql (with error handling and cleanup on failure)
if ! sqlite3 .claude/calibrator/patterns.db < plugins/calibrator/schemas/schema.sql; then
  rm -f .claude/calibrator/patterns.db
  echo "❌ Error: Failed to create database"
  exit 1
fi

# Set secure permissions on DB file
chmod 600 .claude/calibrator/patterns.db  # Owner only: rw

# Create config.json (safe JSON generation using jq)
# Includes db_path for configurable database location
jq -n \
  --arg version "1.0.0" \
  --arg language "$LANG_CODE" \
  --argjson threshold 2 \
  --arg skill_output_path ".claude/skills/learned" \
  --arg db_path ".claude/calibrator/patterns.db" \
  '{version: $version, language: $language, threshold: $threshold, skill_output_path: $skill_output_path, db_path: $db_path}' \
  > .claude/calibrator/config.json

if [ $? -ne 0 ]; then
  rm -f .claude/calibrator/patterns.db
  echo "❌ Error: Failed to create config.json"
  exit 1
fi

# Set secure permissions on config file
chmod 600 .claude/calibrator/config.json  # Owner only: rw

# Update .gitignore (for Git projects)
if [ -d .git ]; then
  GITIGNORE_ENTRIES="
# Calibrator runtime data (auto-added by /calibrate init)
.claude/calibrator/
.claude/skills/learned/
*.db-journal
*.db-wal
*.db-shm"

  if [ -f .gitignore ]; then
    # Check if calibrator entries already exist
    if ! grep -q ".claude/calibrator/" .gitignore; then
      echo "$GITIGNORE_ENTRIES" >> .gitignore
      echo "📝 Calibrator entries added to .gitignore"
    fi
  else
    # Create .gitignore file
    echo "$GITIGNORE_ENTRIES" > .gitignore
    echo "📝 .gitignore file created"
  fi
fi
```

### Step 2-C: When Already Exists
```bash
# Check current language setting (stable JSON parsing using jq)
CURRENT_LANG=$(jq -r '.language // "en"' .claude/calibrator/config.json)
```

Display messages in the selected language. (English example below)
```
⚠️ Calibrator already exists

Current records: {observations} observations, {patterns} patterns
Current language: {CURRENT_LANG}

[Keep] [Change Language] [Reinitialize (delete data)]
```

- Keep selected: Exit
- Change Language selected: Go to language selection screen → Only update language field in config.json
- Reinitialize selected:
```bash
rm -rf .claude/calibrator
# Proceed with new installation (starting from language selection)
```

### Step 3: Completion Message
Display completion message in the selected language.

i18n key reference: `init.complete_title`, `init.complete_db_created`, `init.complete_config_created`, `init.complete_skills_created`, `init.complete_gitignore`, `init.complete_next`

English example:
```
✅ Calibrator initialization complete

- .claude/calibrator/patterns.db created
- .claude/calibrator/config.json created
- .claude/skills/learned/ directory created
- .gitignore updated (if Git project)

You can now record mismatches with /calibrate.
```

Korean example:
```
✅ Calibrator 초기화 완료

- .claude/calibrator/patterns.db 생성됨
- .claude/calibrator/config.json 생성됨
- .claude/skills/learned/ 디렉토리 생성됨
- .gitignore 업데이트됨 (Git 프로젝트인 경우)

이제 /calibrate로 불일치를 기록할 수 있어요.
```
