-- Calibrator SQLite Schema v1.0

CREATE TABLE IF NOT EXISTS observations (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  timestamp   DATETIME DEFAULT CURRENT_TIMESTAMP,
  category    TEXT NOT NULL,     -- 'missing', 'excess', 'style', 'other'
  situation   TEXT NOT NULL,     -- "모델 생성", "API 엔드포인트 작성"
  expectation TEXT NOT NULL,     -- "timestamp 필드 포함"
  file_path   TEXT,              -- 관련 파일 경로 (선택)
  notes       TEXT               -- 추가 메모 (선택)
);

CREATE TABLE IF NOT EXISTS patterns (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  situation   TEXT UNIQUE NOT NULL,
  instruction TEXT NOT NULL,     -- DO 형태 지시문
  count       INTEGER DEFAULT 1,
  first_seen  DATETIME DEFAULT CURRENT_TIMESTAMP,
  last_seen   DATETIME DEFAULT CURRENT_TIMESTAMP,
  promoted    BOOLEAN DEFAULT FALSE,
  skill_path  TEXT               -- 승격된 Skill 경로
);

CREATE INDEX IF NOT EXISTS idx_observations_situation ON observations(situation);
CREATE INDEX IF NOT EXISTS idx_patterns_count ON patterns(count);
CREATE INDEX IF NOT EXISTS idx_patterns_promoted ON patterns(promoted);
