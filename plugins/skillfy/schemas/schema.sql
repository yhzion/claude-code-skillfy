-- Skillfy SQLite Schema v1.0
-- Requires SQLite 3.24.0+ for compatibility

-- Patterns table: User memos for skill promotion
-- No UNIQUE constraint - allows duplicate entries (memo purpose)
CREATE TABLE IF NOT EXISTS patterns (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  situation   TEXT NOT NULL CHECK(length(situation) <= 500),
  expectation TEXT CHECK(length(expectation) <= 1000),
  instruction TEXT NOT NULL CHECK(length(instruction) <= 2000),
  created_at  DATETIME DEFAULT CURRENT_TIMESTAMP,
  promoted    INTEGER NOT NULL DEFAULT 0 CHECK(promoted IN (0, 1)),
  skill_path  TEXT
);

-- Schema version tracking
CREATE TABLE IF NOT EXISTS schema_version (
  version    TEXT PRIMARY KEY,
  applied_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Insert current schema version
INSERT OR IGNORE INTO schema_version (version) VALUES ('1.0');

-- Performance indexes
CREATE INDEX IF NOT EXISTS idx_patterns_promoted ON patterns(promoted);
CREATE INDEX IF NOT EXISTS idx_patterns_created_at ON patterns(created_at DESC);
