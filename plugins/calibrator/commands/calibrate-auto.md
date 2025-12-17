---
name: calibrate auto
description: Toggle auto pattern detection on/off
allowed-tools: Bash(git:*), Bash(test:*), Bash(touch:*), Bash(rm:*), Bash(echo:*), Bash(chmod:*)
---

# /calibrate auto [on|off]

Toggle automatic pattern detection.

## Usage

```
/calibrate auto on   - Enable auto pattern detection (default)
/calibrate auto off  - Disable auto pattern detection
/calibrate auto      - Show current status
```

## Execution Flow

### Step 0: Setup and Check Initialization
```bash
set -euo pipefail

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
FLAG_FILE="$PROJECT_ROOT/.claude/calibrator/auto-detect.enabled"
DB_PATH="$PROJECT_ROOT/.claude/calibrator/patterns.db"

if [ ! -f "$DB_PATH" ]; then
  echo "❌ Calibrator is not initialized. Run /calibrate init first."
  exit 1
fi
```

### Step 1: Parse Argument

The command argument should be one of:
- `on` - Enable auto-detection
- `off` - Disable auto-detection
- (empty) - Show current status

### Step 2-A: Enable Auto-Detection (when argument is "on")
```bash
touch "$FLAG_FILE"
chmod 600 "$FLAG_FILE"
echo "✅ Auto pattern detection enabled"
echo ""
echo "Patterns will be automatically recorded when fixing:"
echo "  - Lint errors (ESLint, Prettier, etc.)"
echo "  - Type errors (TypeScript, Flow, etc.)"
echo "  - Build errors (Webpack, Vite, etc.)"
echo "  - Test failures (Jest, Vitest, etc.)"
```

### Step 2-B: Disable Auto-Detection (when argument is "off")
```bash
rm -f "$FLAG_FILE"
echo "✅ Auto pattern detection disabled"
echo ""
echo "Use /calibrate to manually record patterns."
```

### Step 2-C: Show Status (when no argument)
```bash
if [ -f "$FLAG_FILE" ]; then
  echo "📊 Auto pattern detection: enabled"
  echo ""
  echo "To disable: /calibrate auto off"
else
  echo "📊 Auto pattern detection: disabled"
  echo ""
  echo "To enable: /calibrate auto on"
fi
```
