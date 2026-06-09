# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
bundle exec rspec          # Run all tests (also generates coverage report in coverage/)
bundle exec rubocop        # Lint
bundle exec rake           # Run both spec and rubocop (default task)

# Run a single spec file
bundle exec rspec spec/ruby_method_tracer/simple_tracer_spec.rb

# Run a specific example by description
bundle exec rspec spec/ruby_method_tracer/simple_tracer_spec.rb -e "records call details"

# Install gem locally for manual testing
bundle exec rake install

# Release: bump version in lib/ruby_method_tracer/version.rb, then:
bundle exec rake release
```

## Commit conventions

- Do NOT add a `Co-authored-by:` trailer (or any "Generated with"/agent attribution) to commit messages.

## Architecture

The gem provides two ways to trace methods:

1. **Mixin API** — `include RubyMethodTracer` in a class, then call `trace_methods(:method_name, **opts)` at the class level. This creates a `SimpleTracer` internally and is the simplest entry point.

2. **Direct tracer API** — instantiate `SimpleTracer` or `EnhancedTracer` directly for programmatic access to results.

### Tracing mechanism (SimpleTracer)

`SimpleTracer#trace_method` wraps a method by:
1. Detecting visibility (public/protected/private) via `method_defined?` etc.
2. Aliasing the original to `__ruby_method_tracer_original_<name>__`
3. Redefining the method with a proc that times the call and delegates to the alias
4. Restoring the original visibility

The wrapper uses `Thread.current[:__ruby_method_tracer_in_trace]` as a reentrancy flag to avoid recursive double-recording. Kwargs are forwarded conditionally (`kwargs.empty?` check) to stay compatible with Ruby 3.x.

Results are stored in `@calls` (an Array) guarded by a `Mutex`. The `max_calls` option enforces a sliding window by `shift`-ing the oldest entry.

### EnhancedTracer

Inherits from `SimpleTracer` and adds call-tree tracking via `CallTree`. It overrides `trace_method` to use a per-method reentrancy key (`__ruby_method_tracer_in_trace_<method_name>`) so that *different* wrapped methods can nest inside each other (unlike `SimpleTracer` which blocks all nesting).

### CallTree

Stack-based hierarchy tracker. `start_call` pushes a record (with a `parent` pointer and `children` array) onto `@call_stack`; `end_call` pops it, fills timing/status, and appends to the flat `@calls` list. Root-level calls (depth 0) are also collected in `@root_calls` for tree rendering.

### Formatters

`Formatters::BaseFormatter` — abstract base providing `format_time` and `colorize` (ANSI).

`Formatters::TreeFormatter < BaseFormatter` — renders a `CallTree` as an ASCII tree with `└──`/`├──` connectors, then appends a statistics block (slowest methods, most-called methods).
