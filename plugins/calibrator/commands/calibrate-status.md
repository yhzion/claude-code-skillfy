---
name: calibrate status
description: Calibrator 통계 조회
---

# /calibrate status

현재 기록된 패턴과 통계를 확인합니다.

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
  # i18n 키 `calibrate.run_init_first` 안내
  exit 1
fi
```

## 플로우

### Step 1: 통계 쿼리 실행 (에러 핸들링 포함)
```bash
DB_PATH=".claude/calibrator/patterns.db"

# 쿼리 실행 함수 (에러 핸들링)
run_query() {
  result=$(sqlite3 "$DB_PATH" "$1" 2>/dev/null)
  if [ $? -ne 0 ]; then
    echo "0"  # 에러 시 기본값 반환
  else
    echo "${result:-0}"
  fi
}

# 총 관찰 기록 수
TOTAL_OBS=$(run_query "SELECT COUNT(*) FROM observations;")

# 총 패턴 수
TOTAL_PATTERNS=$(run_query "SELECT COUNT(*) FROM patterns;")

# Skill로 승격된 패턴 수
PROMOTED=$(run_query "SELECT COUNT(*) FROM patterns WHERE promoted = TRUE;")

# 승격 대기중인 패턴 수 (2회 이상 반복)
PENDING=$(run_query "SELECT COUNT(*) FROM patterns WHERE count >= 2 AND promoted = FALSE;")

# 최근 3개 관찰 기록
RECENT=$(sqlite3 "$DB_PATH" "SELECT timestamp, category, situation FROM observations ORDER BY timestamp DESC LIMIT 3;" 2>/dev/null)
```

### Step 2: 출력 형식
i18n 키 참조:
- `status.title` - 타이틀
- `status.total_observations` - 총 관찰 기록
- `status.detected_patterns` - 감지된 패턴
- `status.promoted_skills` - Skill 승격됨
- `status.pending_promotion` - 승격 대기중
- `status.recent_records` - 최근 기록

영어 예시:
```
📊 Calibrator Status

Total observations: {TOTAL_OBS}
Detected patterns: {TOTAL_PATTERNS}
├─ Promoted to Skills: {PROMOTED}
└─ Pending promotion (2+): {PENDING}

Recent records:
- [{timestamp}] {category}: {situation}
- [{timestamp}] {category}: {situation}
- [{timestamp}] {category}: {situation}
```

### Step 3: 승격 대기 안내
i18n 키: `status.promotion_hint`

PENDING이 0보다 크면 추가:
```
💡 Run /calibrate review to promote pending patterns to Skills.
```

### Step 4: 데이터 없음 시
i18n 키 참조:
- `status.no_data_title` - 타이틀
- `status.no_data_desc` - 설명

TOTAL_OBS가 0이면 (영어 예시):
```
📊 Calibrator Status

No data recorded yet.
Record your first mismatch with /calibrate.
```
