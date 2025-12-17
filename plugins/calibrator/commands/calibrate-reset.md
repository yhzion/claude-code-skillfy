---
name: calibrate reset
description: Calibrator 데이터 초기화 (위험)
---

# /calibrate reset

⚠️ 모든 Calibrator 데이터를 삭제합니다.

## i18n 메시지 참조

모든 사용자 대면 메시지는 `plugins/calibrator/i18n/messages.json`을 참조합니다.
실행 시 `.claude/calibrator/config.json`의 `language` 필드를 읽어 해당 언어 메시지를 사용합니다.

```bash
# jq 사용으로 안정적인 JSON 파싱
LANG=$(jq -r '.language // "en"' .claude/calibrator/config.json 2>/dev/null)
LANG=${LANG:-en}  # 기본값: 영어
```

## 실행 전 확인

### Step 0: 의존성 및 DB 확인
```bash
# 필수 의존성 체크
if ! command -v sqlite3 &> /dev/null; then
  echo "❌ Error: sqlite3 is required but not installed."
  exit 1
fi

# DB 존재 확인
if [ ! -f .claude/calibrator/patterns.db ]; then
  # i18n 키 `reset.no_data` 안내
  exit 1
fi
```

## 플로우

### Step 1: 현재 상태 표시 (에러 핸들링 포함)
```bash
DB_PATH=".claude/calibrator/patterns.db"

TOTAL_OBS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM observations;" 2>/dev/null || echo "0")
TOTAL_PATTERNS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM patterns;" 2>/dev/null || echo "0")
```

### Step 2: 확인 요청
i18n 키 참조:
- `reset.title` - 타이틀
- `reset.data_to_delete` - 삭제될 데이터 헤더
- `reset.observations_count` - 관찰 기록 수 (placeholder: {count})
- `reset.patterns_count` - 패턴 수 (placeholder: {count})
- `reset.skills_preserved` - Skills 유지 안내
- `reset.confirm_prompt` - 확인 프롬프트

영어 예시:
```
⚠️ Calibrator Reset

Data to delete:
- {TOTAL_OBS} observations
- {TOTAL_PATTERNS} patterns

Note: Generated Skills (.claude/skills/learned/) will be preserved.

Really reset? Type "reset" to confirm: _
```

### Step 3: 사용자 입력 검증
- "reset" 입력 시: 삭제 진행
- 그 외: i18n 키 `reset.cancelled` 안내

### Step 4: 데이터 삭제 실행 (에러 핸들링 포함)
```bash
DB_PATH=".claude/calibrator/patterns.db"

# 기존 DB 삭제
if ! rm "$DB_PATH" 2>/dev/null; then
  echo "❌ Error: Failed to delete database"
  exit 1
fi

# 새 DB 생성 (에러 핸들링)
if ! sqlite3 "$DB_PATH" < plugins/calibrator/schemas/schema.sql; then
  echo "❌ Error: Failed to recreate database"
  exit 1
fi
```

### Step 5: 완료 메시지
i18n 키 참조:
- `reset.complete_title` - 완료 타이틀
- `reset.complete_observations` - 관찰 기록 삭제됨
- `reset.complete_patterns` - 패턴 삭제됨
- `reset.complete_skills` - Skills 유지됨
- `reset.complete_next` - 다음 안내

영어 예시:
```
✅ Calibrator data has been reset

- Observations: all deleted
- Patterns: all deleted
- Skills: preserved (.claude/skills/learned/)

Start new records with /calibrate.
```
