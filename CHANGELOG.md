# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- **BREAKING**: Renamed from "Calibrator" to "Skillfy"
  - Plugin name: `calibrator` → `skillfy`
  - Commands: `/calibrate` → `/skillfy`
  - Data folder: `.claude/calibrator/` → `.claude/skillfy/`
  - Marketplace ID: `yhzion-claude-code-calibrator` → `yhzion-skillfy`
- Simplified workflow: record → save/promote → apply
- `.gitignore` entries now use `.claude/skillfy/`

### Removed

- Auto-detection feature (manual recording only)
- `/calibrate auto` command
- `/calibrate status` command - Use `/skillfy help` instead
- `/calibrate refactor` command - Edit skill files directly
- `/calibrate delete` command - Delete skill directories directly
- Locale/i18n support (English-only for now)
- `config.json`/`jq` dependency
- Hook-based error detection

## [0.1.0] - 2024-12-17

### Added

- Initial release of Claude Code Calibrator plugin
- `/calibrate init` command - Initialize SQLite database and directory structure
- `/calibrate` command - Record expectation mismatches with category selection
- `/calibrate review` command - Review patterns and promote to Skills
- `/calibrate status` command - View statistics and recent observations
- `/calibrate reset` command - Reset all observation data (preserves generated Skills)
- SQLite-based pattern storage (`patterns.db`)
- Automatic pattern detection for repeated mismatches
- Skill template for generated learning files

[Unreleased]: https://github.com/yhzion/claude-code-skillfy/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/yhzion/claude-code-skillfy/releases/tag/v0.1.0
