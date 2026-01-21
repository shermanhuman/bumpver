# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog:
https://keepachangelog.com/en/1.0.0/

This project adheres to Semantic Versioning:
https://semver.org/spec/v2.0.0.html

## [1.0.0] - 2026-01-19

### Added

- `mix bumpver` interactive semantic version bumping (with non-interactive flags)
- `mix bumpver.check` guard that ensures `mix.exs` version changed since a git revision
- `mix bumpver.check --auto-bump` opt-in auto-bumping (interactive by default; supports `--yes` and `--bump …`)
- `mix bumpver.git.install` / `mix bumpver.git.uninstall` optional git hook helpers
- Supports both `version: "x.y.z"` and `@version "x.y.z"` patterns in `mix.exs`

[1.0.0]: https://github.com/shermanhuman/bumpver/releases/tag/v1.0.0
[Unreleased]: https://github.com/shermanhuman/bumpver/compare/v1.0.0...HEAD
