---
name: calibrate init
description: Calibrator 초기화. DB 및 설정 파일 생성.
---

# /calibrate init

Calibrator를 초기화합니다.

## i18n 메시지 참조

모든 사용자 대면 메시지는 `plugins/calibrator/i18n/messages.json`을 참조합니다.
언어 설정은 `.claude/calibrator/config.json`의 `language` 필드에 저장됩니다.

지원 언어:
- `en` - English (default)
- `ko` - Korean (한국어)
- `ja` - Japanese (日本語)
- `zh` - Chinese (中文)

## 실행 플로우

### Step 0: 의존성 확인
```bash
# 필수 의존성 체크
check_dependency() {
  if ! command -v "$1" &> /dev/null; then
    echo "❌ Error: $1 is required but not installed."
    exit 1
  fi
}

check_dependency sqlite3
check_dependency jq
```

### Step 1: 기존 설치 확인
```bash
test -d .claude/calibrator
```

### Step 2-A: 신규 설치 - 언어 선택
```
🌐 Select Language

Choose your preferred language for Calibrator:

1. English (default)
2. Korean (한국어)
3. Japanese (日本語)
4. Chinese (中文)

[1-4]: _
```

언어 매핑 (입력값 검증 포함):
```bash
# 입력값 검증 및 매핑
validate_language() {
  case "$1" in
    1|"") echo "en" ;;
    2)    echo "ko" ;;
    3)    echo "ja" ;;
    4)    echo "zh" ;;
    *)    echo "" ;;  # 잘못된 입력
  esac
}

LANG_CODE=$(validate_language "$USER_INPUT")
if [ -z "$LANG_CODE" ]; then
  echo "❌ Invalid selection. Please enter 1-4."
  # 다시 선택 화면으로
fi
```

### Step 2-B: 신규 설치 - 확인
선택된 언어로 메시지를 표시합니다. (아래는 영어 예시)
```
⚙️ Calibrator Initialization

Files to create:
- .claude/calibrator/patterns.db
- .claude/calibrator/config.json

[Confirm] [Cancel]
```

확인 시:
```bash
# 디렉토리 생성 (에러 핸들링)
if ! mkdir -p .claude/calibrator; then
  echo "❌ Error: Failed to create .claude/calibrator directory"
  exit 1
fi
mkdir -p .claude/skills/learned

# schema.sql 파일로 DB 생성 (에러 핸들링)
if ! sqlite3 .claude/calibrator/patterns.db < plugins/calibrator/schemas/schema.sql; then
  echo "❌ Error: Failed to create database"
  exit 1
fi

# config.json 생성 (jq 사용으로 안전한 JSON 생성)
jq -n \
  --arg version "1.0.0" \
  --arg language "$LANG_CODE" \
  --argjson threshold 2 \
  --arg skill_output_path ".claude/skills/learned" \
  '{version: $version, language: $language, threshold: $threshold, skill_output_path: $skill_output_path}' \
  > .claude/calibrator/config.json

if [ $? -ne 0 ]; then
  echo "❌ Error: Failed to create config.json"
  exit 1
fi

# .gitignore 업데이트 (Git 프로젝트인 경우)
if [ -d .git ]; then
  GITIGNORE_ENTRIES="
# Calibrator runtime data (auto-added by /calibrate init)
.claude/calibrator/
.claude/skills/learned/
*.db-journal
*.db-wal
*.db-shm"

  if [ -f .gitignore ]; then
    # 이미 calibrator 항목이 있는지 확인
    if ! grep -q ".claude/calibrator/" .gitignore; then
      echo "$GITIGNORE_ENTRIES" >> .gitignore
      echo "📝 .gitignore에 Calibrator 제외 항목 추가됨"
    fi
  else
    # .gitignore 파일 생성
    echo "$GITIGNORE_ENTRIES" > .gitignore
    echo "📝 .gitignore 파일 생성됨"
  fi
fi
```

### Step 2-C: 이미 존재할 때
```bash
# 현재 설정된 언어 확인 (jq 사용으로 안정적인 JSON 파싱)
CURRENT_LANG=$(jq -r '.language // "en"' .claude/calibrator/config.json)
```

선택된 언어로 메시지를 표시합니다. (아래는 영어 예시)
```
⚠️ Calibrator already exists

Current records: {observations} observations, {patterns} patterns
Current language: {CURRENT_LANG}

[Keep] [Change Language] [Reinitialize (delete data)]
```

- 유지 선택 시: 종료
- 언어 변경 선택 시: 언어 선택 화면으로 이동 → config.json의 language 필드만 업데이트
- 초기화 선택 시:
```bash
rm -rf .claude/calibrator
# 이후 신규 설치 진행 (언어 선택부터)
```

### Step 3: 완료 메시지
선택된 언어로 완료 메시지를 표시합니다.

i18n 키 참조: `init.complete_title`, `init.complete_db_created`, `init.complete_config_created`, `init.complete_skills_created`, `init.complete_gitignore`, `init.complete_next`

영어 예시:
```
✅ Calibrator initialization complete

- .claude/calibrator/patterns.db created
- .claude/calibrator/config.json created
- .claude/skills/learned/ directory created
- .gitignore updated (if Git project)

You can now record mismatches with /calibrate.
```

한국어 예시:
```
✅ Calibrator 초기화 완료

- .claude/calibrator/patterns.db 생성됨
- .claude/calibrator/config.json 생성됨
- .claude/skills/learned/ 디렉토리 생성됨
- .gitignore 업데이트됨 (Git 프로젝트인 경우)

이제 /calibrate로 불일치를 기록할 수 있어요.
```
