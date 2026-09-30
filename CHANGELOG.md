## [Unreleased]

## [0.5.0] - 2026-09-30

### Fixed
- Tracing a method that is already traced no longer aliases the wrapper onto itself and raises `SystemStackError`. The duplicate-wrap guard now checks the target class for the alias instead of only consulting the tracer's own bookkeeping, so a second `trace_methods` call, or a second tracer instance, is refused with a warning rather than crashing at call time.
- `CallTree` now honours `:max_calls`, capping both completed calls and retained root trees. Previously only the flat results list was bounded, so an `EnhancedTracer` left enabled grew without limit — every node, parent pointer and `Time` object stayed reachable for the life of the tracer.
- `:threshold` now applies to the call tree as well as the flat list. Calls below the threshold are dropped unless they have children worth reporting, so `print_tree`, the JSON hierarchy and the tree statistics no longer disagree with `fetch_results`.
- `trace_method` warns instead of silently doing nothing when the named method does not exist, and returns `false`. A typo, a rename or a method defined after the `trace_methods` call previously produced empty results with no explanation.
- `RubyMethodTracer.configure` no longer holds a `Mutex` across the caller's block, which made a nested `configure` — reachable through any helper or engine initializer — fail with `ThreadError: deadlock; recursive locking`. The lock provided no real safety, since `configuration` hands out the same mutable object without it.
- Methods that exit via `throw` or a non-`StandardError` exception are now recorded with a new `:incomplete` status instead of vanishing from the results.
- `Exportable#export` no longer raises `NameError` on platforms without the POSIX `O_NOFOLLOW` flag (notably Windows); the flag is applied only where `File::NOFOLLOW` is defined, and the stat-based symlink guard still applies everywhere.
- `Formatters::BaseFormatter#format` now takes `(_data, _options = {})`, matching every subclass. The abstract contract previously described a signature no implementation used.
- Tracing a method whose name is not a plain identifier — a predicate (`ready?`), bang (`save!`), setter (`val=`) or operator (`==`, `[]`, `[]=`, `<=>`, `<<`, `-@`) — now works. The saved original is aliased under a name the parser accepts, since the generated wrapper calls it directly; previously such an alias could misparse silently rather than fail loudly.

### Added
- `CallTree#calls_snapshot`, and an optional `execution_time` argument to `CallTree#end_call` so a caller that already timed the call does not pay for a second clock read.
- `SimpleTracer#untrace_method` and `#untrace_all` restore traced methods to their original implementation and visibility.
- `trace_class_methods` on the mixin traces class (singleton) methods, which the documented API previously could not reach. Traced singleton methods are reported as `Klass.method` rather than `#<Class:Klass>#method`.
- Real RBS signatures for the whole public API, validated in CI and by `rake rbs`. The shipped file was previously the generated template declaring only `VERSION`.
- `RubyMethodTracer::Wrapper`, which generates the traced replacement for a method from the original's `parameters`.
- `RubyMethodTracer::CallTreeStatistics`, extracted from `CallTree`.

### Changed
- **Breaking:** `trace_methods` now returns the `SimpleTracer` it created instead of the array of method names, and memoizes one tracer per class. Results collected through the mixin were previously unreachable unless `auto_output: true` was set.
- Tracing a method preserves its `Method#arity` and `Method#parameters`. The wrapper is generated from the original signature rather than being a generic `proc { |*args, **kwargs, &block| }`, so reflection-driven callers (dependency injection, serializers, argument validators, documentation tooling) still see the real signature. Two limitations remain: a block parameter is always declared, because a method may `yield` without declaring one, and anonymous parameters (`def m(*)`, `def m(...)`) keep their arity but are given generated names.
- The alias holding the original implementation (`__ruby_method_tracer_original_<name>__`) is now private. It previously inherited the original's visibility and appeared in the public API of every instance.
- **Per-call overhead roughly halved for `EnhancedTracer` and cut by about a third for `SimpleTracer`.** Measured on one machine with the same harness for both versions, against an untraced call at ~54ns: `SimpleTracer` 464ns → 354ns below threshold and 836ns → 665ns when recording; `EnhancedTracer` 2144ns → 1081ns below threshold and 2264ns → 1344ns when recording. Three changes account for it:
  - The timing path is now emitted inline in the generated wrapper — the reentrancy guard, both clock reads and the `begin/rescue/ensure` all live in the method itself. It calls the tracer once per invocation instead of threading a block down through `dispatch`, `wrap_call` and `timed`, each of which cost a frame and a `Proc`.
  - `EnhancedTracer` no longer maintains a flat call list alongside the tree. `fetch_results` is derived from the tree instead, so a traced call is recorded once rather than twice — and the two views now agree by construction.
  - Everything knowable at trace time is baked into the wrapper as a literal (the reentrancy key, the method name, the display name) and methods whose parameters all forward unconditionally skip building an argument array, so the common case allocates nothing and does no hash lookups on the call path.
- CI now runs the specs on Ruby 3.0 through 3.4 and head, with RuboCop and RBS validation as a separate job. The matrix previously tested only 3.3.5 even though the gemspec supports `>= 3.0.0` — and two of the last four releases fixed keyword-forwarding breakage that only shows up on specific versions.
- `render(format: :tree)` on a `SimpleTracer` now explains that the format needs a call tree instead of reporting an unknown format.
- The gemspec globs `lib/` and `sig/` instead of deriving its file list from `git ls-files`, and no longer ships development files. The git-based list silently omitted any file that was new and not yet staged — which is how the released 0.3.0 shipped without `EnhancedTracer` and the formatters (fixed in 0.3.1). A `gem-smoke` CI job now builds the gem, installs it and traces through it, so a missing file fails the build instead of a user's install.

## [0.4.0] - 2026-06-09

### Added
- Global configuration via `RubyMethodTracer.configure { |c| ... }`, with `RubyMethodTracer.configuration` and `RubyMethodTracer.reset_configuration!`. Tracers created through the mixin now use these as defaults; explicit per-tracer options still take precedence.
- `Formatters::JsonFormatter` — serializes flat results or a call tree to JSON. Method arguments are never captured; exceptions are reduced to class + message; backtraces are opt-in (`include_backtrace:`) and length-bounded (`backtrace_limit:`). Uses `JSON.generate` only (no `Marshal`/`eval`/`YAML`).
- `Formatters::FlatFormatter` — renders an aggregated text table (method, calls, total, avg, errors) sorted by total time.
- `Exportable` mixin adding `render(format:)` and `export(path, format:)` to both tracers. Supported formats: `:json`, `:flat`, and `:tree` (EnhancedTracer only).

### Security
- File export never invokes a shell and never interpolates the path into a command; it writes via `File.open` with `O_NOFOLLOW`, requires the destination directory to already exist (no recursive mkdir of attacker-influenced paths), and refuses to write through an existing symlink.
- Export format dispatch compares on the string form to avoid interning arbitrary symbols from potentially untrusted input.

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
