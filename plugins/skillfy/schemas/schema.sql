-- Skillfy SQLite Schema v2.0
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
  skill_path  TEXT,
  notes       TEXT
);

-- Schema version tracking
CREATE TABLE IF NOT EXISTS schema_version (
  version    TEXT PRIMARY KEY,
  applied_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Insert current schema version
INSERT OR IGNORE INTO schema_version (version) VALUES ('2.0');

-- Performance indexes
CREATE INDEX IF NOT EXISTS idx_patterns_promoted ON patterns(promoted);
CREATE INDEX IF NOT EXISTS idx_patterns_created_at ON patterns(created_at DESC);

-- ============================================================================
-- Migration Instructions (v1.1 → v2.0)
-- ============================================================================
-- For existing installations with schema v1.x, run the following migration:
--
-- Step 1: Create new patterns table
--   CREATE TABLE IF NOT EXISTS patterns_v2 (
--     id          INTEGER PRIMARY KEY AUTOINCREMENT,
--     situation   TEXT NOT NULL CHECK(length(situation) <= 500),
--     expectation TEXT CHECK(length(expectation) <= 1000),
--     instruction TEXT NOT NULL CHECK(length(instruction) <= 2000),
--     created_at  DATETIME DEFAULT CURRENT_TIMESTAMP,
--     promoted    INTEGER NOT NULL DEFAULT 0 CHECK(promoted IN (0, 1)),
--     skill_path  TEXT,
--     notes       TEXT
--   );
--
-- Step 2: Migrate existing data
--   INSERT INTO patterns_v2 (situation, instruction, created_at, promoted, skill_path)
--   SELECT situation, instruction, first_seen, promoted, skill_path
--   FROM patterns;
--
-- Step 3: Replace tables
--   DROP TABLE patterns;
--   ALTER TABLE patterns_v2 RENAME TO patterns;
--
-- Step 4: Drop observations table (no longer used)
--   DROP TABLE IF EXISTS observations;
--
-- Step 5: Recreate indexes
--   CREATE INDEX IF NOT EXISTS idx_patterns_promoted ON patterns(promoted);
--   CREATE INDEX IF NOT EXISTS idx_patterns_created_at ON patterns(created_at DESC);
--
-- Step 6: Update schema version
--   INSERT OR REPLACE INTO schema_version (version) VALUES ('2.0');
--
-- Changes in v2.0:
-- - Removed: observations table (auto-detection removed)
-- - Removed: count, last_seen, dismissed columns (threshold concept removed)
-- - Removed: UNIQUE(situation, instruction) constraint (duplicates allowed)
-- - Added: expectation column (store expected behavior)
-- - Added: notes column (additional memo)
-- - Renamed: first_seen → created_at
