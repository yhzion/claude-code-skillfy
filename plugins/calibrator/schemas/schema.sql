-- Calibrator SQLite Schema v1.0

CREATE TABLE IF NOT EXISTS observations (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  timestamp   DATETIME DEFAULT CURRENT_TIMESTAMP,
  category    TEXT NOT NULL,     -- 'missing', 'excess', 'style', 'other'
  situation   TEXT NOT NULL,     -- e.g., "Model creation", "API endpoint"
  expectation TEXT NOT NULL,     -- e.g., "include timestamp field"
  file_path   TEXT,              -- Related file path (optional)
  notes       TEXT               -- Additional notes (optional)
);

CREATE TABLE IF NOT EXISTS patterns (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  situation   TEXT UNIQUE NOT NULL,  -- UNIQUE constraint enables UPSERT
  instruction TEXT NOT NULL,     -- Imperative form instruction
  count       INTEGER DEFAULT 1,
  first_seen  DATETIME DEFAULT CURRENT_TIMESTAMP,
  last_seen   DATETIME DEFAULT CURRENT_TIMESTAMP,
  promoted    BOOLEAN DEFAULT FALSE,
  skill_path  TEXT               -- Path to promoted Skill
);

-- Performance indexes
CREATE INDEX IF NOT EXISTS idx_observations_situation ON observations(situation);
CREATE INDEX IF NOT EXISTS idx_patterns_count ON patterns(count);
CREATE INDEX IF NOT EXISTS idx_patterns_promoted ON patterns(promoted);
