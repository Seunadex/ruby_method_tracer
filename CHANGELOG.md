## [Unreleased]

## [0.2.0] - 2025-11-19

### Added
- Memory management with `max_calls` option (default: 1000) to prevent unbounded memory growth
- `clear_results` public method to manually free stored trace data
- Configurable logger via `logger` option for custom log destinations and formatting
- Comprehensive test coverage for memory management and logger configuration

### Fixed
- Removed unnecessary `logger` gem dependency (now uses Ruby standard library)
- Fixed gemspec URL casing inconsistencies for GitHub links

### Changed
- Default behavior now automatically limits stored calls to 1000 entries (oldest removed when exceeded)
- Documentation updated with new configuration options and advanced usage examples

## [0.1.1] - 2025-09-16

- Bug fixes and improvements

## [0.1.0] - 2025-09-03

- Initial release
