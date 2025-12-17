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
LANG=$(cat .claude/calibrator/config.json 2>/dev/null | grep '"language"' | sed 's/.*: *"\([^"]*\)".*/\1/')
LANG=${LANG:-en}  # 기본값: 영어
```

## 실행 전 확인
- `.claude/calibrator/patterns.db` 존재 확인
- 없으면 i18n 키 `reset.no_data` 안내

## 플로우

### Step 1: 현재 상태 표시
```bash
TOTAL_OBS=$(sqlite3 .claude/calibrator/patterns.db "SELECT COUNT(*) FROM observations;")
TOTAL_PATTERNS=$(sqlite3 .claude/calibrator/patterns.db "SELECT COUNT(*) FROM patterns;")
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

### Step 4: 데이터 삭제 실행
```bash
# 기존 DB 삭제
rm .claude/calibrator/patterns.db

# 새 DB 생성 (스키마 적용)
sqlite3 .claude/calibrator/patterns.db << 'EOF'
CREATE TABLE IF NOT EXISTS observations (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  timestamp   DATETIME DEFAULT CURRENT_TIMESTAMP,
  category    TEXT NOT NULL,
  situation   TEXT NOT NULL,
  expectation TEXT NOT NULL,
  file_path   TEXT,
  notes       TEXT
);

CREATE TABLE IF NOT EXISTS patterns (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  situation   TEXT UNIQUE NOT NULL,
  instruction TEXT NOT NULL,
  count       INTEGER DEFAULT 1,
  first_seen  DATETIME DEFAULT CURRENT_TIMESTAMP,
  last_seen   DATETIME DEFAULT CURRENT_TIMESTAMP,
  promoted    BOOLEAN DEFAULT FALSE,
  skill_path  TEXT
);

CREATE INDEX IF NOT EXISTS idx_observations_situation ON observations(situation);
CREATE INDEX IF NOT EXISTS idx_patterns_count ON patterns(count);
CREATE INDEX IF NOT EXISTS idx_patterns_promoted ON patterns(promoted);
EOF
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
