# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Multi-language support (i18n) for all user-facing messages
  - English (default), Korean, Japanese, Chinese
  - Language selection during `/calibrate init`
  - Language preference stored in `config.json`
  - Option to change language for existing installations

## [0.1.0] - 2025-12-17

### Added

- Initial release of Claude Code Calibrator plugin
- `/calibrate init` command - Initialize SQLite database and directory structure
- `/calibrate` command - Record expectation mismatches with category selection (누락/과잉/스타일/기타)
- `/calibrate review` command - Review patterns and promote to Skills (2+ occurrences threshold)
- `/calibrate status` command - View statistics and recent observations
- `/calibrate reset` command - Reset all observation data (preserves generated Skills)
- SQLite-based pattern storage (`patterns.db`)
- Automatic pattern detection for repeated mismatches
- Skill template for generated learning files

[Unreleased]: https://github.com/yhzion/claude-code-calibrator/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/yhzion/claude-code-calibrator/releases/tag/v0.1.0
