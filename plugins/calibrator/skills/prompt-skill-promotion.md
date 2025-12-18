---
name: prompt-skill-promotion
description: When a repeated error pattern reaches CALIBRATOR_THRESHOLD+ occurrences (default 2), prompt the user to promote it to a skill. Activates after auto-calibrate skill records a pattern that reaches the threshold.
---

# Skill Promotion Prompt

This skill activates when a pattern recorded by the `auto-calibrate` skill reaches the promotion threshold (count >= CALIBRATOR_THRESHOLD, default 2) and hasn't been promoted or dismissed yet.

## Activation Condition

Activate this skill when the auto-calibrate skill outputs a promotion suggestion:
```
💡 Pattern repeated {count}x → /calibrate review to promote to skill
```

Or when you detect that a newly recorded pattern has count >= CALIBRATOR_THRESHOLD by checking the database.

## Workflow

### Step 1: Parse the promotion context

Extract the following from the marker:
- `pattern_id`: Database ID of the pattern
- `count`: Number of occurrences
- `situation`: Error description
- `instruction`: Suggested fix instruction

### Step 2: Ask the user

Present the following question to the user using AskUserQuestion tool:

**Question format:**
```
This error pattern has occurred {count} times. Would you like to promote it to a Skill?

**Pattern**: {situation}
**Suggested Rule**: {instruction}

Promoting to a Skill means Claude will learn to handle this pattern automatically in the future.
```

**Options:**
1. `Yes` - Promote to Skill (requires restart)
2. `No` - Don't promote (won't ask again for this pattern)

### Step 3: Handle user response

#### If user selects "Yes":

1. Create the skill file using template:
```bash
set -euo pipefail

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
DB_PATH="$PROJECT_ROOT/.claude/calibrator/patterns.db"
SKILLS_DIR="$PROJECT_ROOT/.claude/skills"
# Use CLAUDE_PLUGIN_ROOT if available (plugin installation), fallback to PROJECT_ROOT
TEMPLATE_PATH="${CLAUDE_PLUGIN_ROOT:-$PROJECT_ROOT/plugins/calibrator}/templates/skill-template.md"

# Ensure skills directory exists
mkdir -p "$SKILLS_DIR"

# Generate kebab-case skill name from situation (consistent with calibrate-review.md)
SITUATION="{{SITUATION}}"
SKILL_NAME=$(printf '%s' "$SITUATION" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | sed 's/[^a-z0-9-]//g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//' | head -c 50)

# Handle empty or invalid skill name
if [ -z "$SKILL_NAME" ]; then
  SKILL_NAME="calibrator-pattern-{{PATTERN_ID}}"
fi

SKILL_DIR="$SKILLS_DIR/$SKILL_NAME"

# Handle name collision by adding suffix
SUFFIX=0
ORIGINAL_SKILL_DIR="$SKILL_DIR"
while [ -d "$SKILL_DIR" ]; do
  SKILL_DIR="${ORIGINAL_SKILL_DIR}-${SUFFIX}"
  SUFFIX=$((SUFFIX + 1))
  if [ "$SUFFIX" -gt 100 ]; then
    echo "❌ Error: Too many skill name collisions"
    exit 1
  fi
done

# Create directory (collision already handled above)
mkdir -p "$SKILL_DIR"

# Get pattern details from database for template
ROW=$(sqlite3 -separator $'\t' "$DB_PATH" \
  "SELECT first_seen, last_seen FROM patterns WHERE id = {{PATTERN_ID}};" \
  2>/dev/null) || ROW=""

if [ -z "$ROW" ]; then
  rmdir "$SKILL_DIR" 2>/dev/null
  echo "❌ Error: Pattern not found (id={{PATTERN_ID}})"
  exit 1
fi

IFS=$'\t' read -r FIRST_SEEN LAST_SEEN <<<"$ROW"

# Escape variables for sed substitution
escape_sed() {
  printf '%s' "$1" | awk '
    BEGIN { ORS="" }
    {
      gsub(/\\/, "\\\\")
      gsub(/&/, "\\\\&")
      gsub(/\|/, "\\|")
      if (NR > 1) printf "\\n"
      print
    }
  '
}

SAFE_SKILL_NAME=$(escape_sed "$SKILL_NAME")
SAFE_INSTRUCTION=$(escape_sed "{{INSTRUCTION}}")
SAFE_SITUATION=$(escape_sed "{{SITUATION}}")

# Verify template file exists
if [ ! -f "$TEMPLATE_PATH" ]; then
  rmdir "$SKILL_DIR" 2>/dev/null
  echo "❌ Error: Template file not found at $TEMPLATE_PATH"
  exit 1
fi

# Generate Skill using template file (consistent with calibrate-review.md)
if ! sed -e "s|{{SKILL_NAME}}|$SAFE_SKILL_NAME|g" \
    -e "s|{{INSTRUCTION}}|$SAFE_INSTRUCTION|g" \
    -e "s|{{SITUATION}}|$SAFE_SITUATION|g" \
    -e "s|{{COUNT}}|{{COUNT}}|g" \
    -e "s|{{FIRST_SEEN}}|$FIRST_SEEN|g" \
    -e "s|{{LAST_SEEN}}|$LAST_SEEN|g" \
    "$TEMPLATE_PATH" > "$SKILL_DIR/SKILL.md"; then
  rm -rf "$SKILL_DIR"
  echo "❌ Error: Failed to generate skill file"
  exit 1
fi

# SQL Injection prevention: escape single quotes
escape_sql() {
  printf '%s' "$1" | sed "s/'/''/g"
}
SAFE_SKILL_PATH=$(escape_sql "$SKILL_DIR")

# Update database
sqlite3 "$DB_PATH" "UPDATE patterns SET promoted = 1, skill_path = '$SAFE_SKILL_PATH' WHERE id = {{PATTERN_ID}};"

echo "SKILL_CREATED: $SKILL_DIR/SKILL.md"
```

2. Display success message:
```
Skill created successfully: {skill_path}

To apply this skill, please restart Claude Code.
The skill will then be automatically loaded and applied to similar patterns.
```

#### If user selects "No":

1. Update the database to mark as dismissed:
```bash
set -euo pipefail

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
DB_PATH="$PROJECT_ROOT/.claude/calibrator/patterns.db"

sqlite3 "$DB_PATH" "UPDATE patterns SET dismissed = 1 WHERE id = {{PATTERN_ID}};"

echo "PATTERN_DISMISSED"
```

2. Display confirmation message:
```
Pattern dismissed. You won't be asked about this pattern again.

You can manually promote dismissed patterns later using:
/calibrate review --dismissed
```

## Important Notes

- Replace `{{PATTERN_ID}}`, `{{SITUATION}}`, `{{INSTRUCTION}}`, and `{{COUNT}}` with actual values from the promotion context
- The skill is created in a directory structure: `.claude/skills/{kebab-case-situation}/SKILL.md`
  - Example: `.claude/skills/typecheck-missing-type/SKILL.md`
- This naming is consistent with `/calibrate review` command's skill creation
- After creating a skill, the user must restart Claude Code for it to take effect
- Dismissed patterns can still be manually promoted via `/calibrate review --dismissed`
- Uses the same skill-template.md as other commands for consistent formatting
