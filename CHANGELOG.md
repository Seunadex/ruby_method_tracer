## [Unreleased]

## [0.3.3] - 2026-06-08

### Changed
- `CallTree` now stores its call stack in per-thread storage (keyed per instance) instead of a single shared `@call_stack`, so concurrent callers each track their own nesting depth. `@calls` and `@root_calls` remain shared and `Mutex`-guarded.
- `SimpleTracer` and `EnhancedTracer` now use a per-instance reentrancy key (`__ruby_method_tracer_in_trace_<object_id>`) so separate tracer instances no longer interfere with each other's re-entry guards.
- `EnhancedTracer` hierarchy tracking extracted into a dedicated `run_with_hierarchy` method; the call-tree entry is now always closed in an `ensure` block (even for non-`StandardError` exceptions) to prevent the per-thread call stack from becoming corrupted.
- `SimpleTracer` now delegates `format_time` and `colorize` to a `Formatters::BaseFormatter` instance instead of duplicating the formatting logic inline.

### Fixed
- Keyword-argument forwarding in `EnhancedTracer`'s wrapper now avoids passing `**{}`, preventing `SystemStackError` on Ruby 3.4+ (mirrors the `SimpleTracer` fix from 0.3.2).

## [0.3.2] - 2025-11-22

### Fixed
- Fixed `SystemStackError: stack level too deep` with Ruby 3.4+ by improving keyword argument forwarding in method wrapper

## [0.3.1] - 2025-11-22

### Fixed
- Fixed file permissions for `call_tree.rb`, `enhanced_tracer.rb`, and formatter files to be world-readable
- Gem now correctly includes all files when installed (previously missing EnhancedTracer and formatters)

### Added
- Code coverage reporting with SimpleCov (99% line coverage, 84% branch coverage)
- Codecov integration for CI/CD coverage tracking
- Comprehensive test suite for BaseFormatter and TreeFormatter (18 new tests)
- Coverage badge in README

## [0.3.0] - 2025-11-19

### Added
- **NEW: Hierarchical Call Tree Visualization** - `EnhancedTracer` class for tracking nested method calls
- `CallTree` class for managing call hierarchy with parent-child relationships
- `TreeFormatter` for beautiful tree visualization with proper indentation and tree characters
- Statistics calculation: slowest methods, most called methods, max call depth
- `print_tree()` method for outputting formatted call trees
- `format_tree()` method for programmatic access to tree visualization
- `fetch_enhanced_results()` for combined flat and hierarchical data
- Thread-safe call stack management
- Error tracking in call tree with full error messages
- Color-coded tree output for better readability
- 24 new comprehensive tests covering call tree functionality

### Changed
- Main module now auto-loads `EnhancedTracer` and formatting classes
- README updated with call tree examples and usage guide
- Documentation expanded with decision guide for choosing between SimpleTracer and EnhancedTracer

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
