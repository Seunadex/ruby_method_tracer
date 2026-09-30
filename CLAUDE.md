# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
bundle exec rspec          # Run all tests (also generates coverage report in coverage/)
bundle exec rubocop        # Lint
bundle exec rake rbs       # Validate the shipped RBS signatures
bundle exec rake           # Run spec, rubocop and rbs (default task)

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
1. Detecting visibility (public/protected/private) via `method_defined?` etc. An unknown method warns and returns `false`.
2. Refusing to wrap if the alias already exists on the target class — wrapping twice would alias the wrapper onto itself and recurse until the stack runs out.
3. Aliasing the original to `__ruby_method_tracer_original_<name>__` and making that alias **private**
4. Defining a private accessor on the target class that returns the tracer (generated wrappers are compiled from a string and cannot close over it)
5. Generating the replacement method via `Wrapper.install`
6. Restoring the original visibility

`untrace_method` reverses steps 3, 5 and 6; `untrace_all` does it for everything the tracer wrapped.

Results are stored in `@calls` (an Array) guarded by a `Mutex`. The `max_calls` option enforces a sliding window by `shift`-ing the oldest entry.

`trace_method` precomputes the display name into `@qualified_names` so `record_call` does no string work on the call path. Singleton classes are rendered as `Klass.method` rather than `#<Class:Klass>#method`.

### Wrapper (codegen)

`Wrapper` builds the replacement method with `module_eval`. Two goals drive it.

**Signature fidelity.** The declaration is derived from the original's `parameters`, not a generic `proc { |*args, **kwargs, &block| }`, so `Method#arity` and `Method#parameters` survive tracing. `Wrapper::Signature` turns a parameter list into the declaration, the setup that rebuilds `__rmt_args__`/`__rmt_kwargs__`, and the forwarding call. Optional positional and keyword parameters default to `Wrapper::OMITTED`; omitted values are dropped before forwarding so the **original** applies its own defaults (which `parameters` does not expose). Kwargs are forwarded conditionally (`__rmt_kwargs__.empty?`) to keep `**{}` off the call site, which is what broke keyword forwarding on Ruby 3.4.

Two deliberate infidelities: a block parameter is always declared (a method may `yield` without one; block params do not affect arity), and anonymous parameters (`def m(*)`, `def m(...)`) get generated names.

**Per-call cost.** The whole timing path is emitted inline — reentrancy guard, both clock reads, `begin/rescue/ensure` — so the wrapper calls the tracer once per invocation (twice when tracking hierarchy) instead of threading a block through several tracer frames. `Wrapper::Plan` carries what varies: the reentrancy key, the close hook, and optionally an open hook plus the display name. Everything knowable at trace time is a literal in the generated source, so no hash lookups happen on the call path.

The reentrancy guard is a one-element array fetched from thread-local storage once, then mutated in place — cheaper than three `Thread.current[]` operations.

Methods whose parameters all forward unconditionally (no optional positionals, no keywords) take a direct path with no argument array and no splat. That is the common case.

The generated wrapper calls the saved alias **directly**, not via `__send__`, which is faster but needs a name the parser accepts as an identifier — hence the hex encoding in `alias_for` for predicate, bang, setter and operator methods.

### EnhancedTracer

Inherits from `SimpleTracer` and adds call-tree tracking via `CallTree`. It overrides `wrapper_plan` (not `trace_method` or the timing) to add the `start_call` open hook and a per-method reentrancy key, so that *different* wrapped methods can nest inside each other while self-recursion is still blocked.

`start_call` and `record_call` are public because the generated wrapper calls them with an explicit receiver. `record_call` closes the tree entry and does **not** store anything in the flat list: `fetch_results` is derived from the tree via `flat_record`, so a call is recorded once instead of twice and the two views cannot disagree. When `track_hierarchy` is false both fall through to `super`.

### CallTree

Stack-based hierarchy tracker. `start_call` pushes a record (with a `children` array) onto the current thread's `@call_stack`; `end_call` pops it and fills in timing/status. `end_call` accepts an `execution_time` so a caller that already timed the call (the generated wrapper always has) avoids a second clock read; standalone callers omit it and it is measured from the record's `start_time`.

The status starts at `:incomplete` in the generated wrapper and is only upgraded on a normal return or a rescued `StandardError`, so a `throw` or a non-`StandardError` exception is recorded rather than lost.

Retention is bounded on both ends. A completed call is dropped if it is below `:threshold` **and** has no children (dropping a parent would orphan the descendants it recorded); otherwise it is appended to the flat `@calls` list, and root-level calls are also appended to `@root_calls`. Both lists are capped at `:max_calls` — capping `@root_calls` is what actually lets old subtrees be collected.

Roots are collected on completion rather than at `start_call`, so an in-flight call is never visible to `call_hierarchy`.

`CallTreeStatistics` computes the summary as a pure function of a snapshot of the calls.

### Formatters

`Formatters::BaseFormatter` — abstract base providing `format_time` and `colorize` (ANSI).

`Formatters::TreeFormatter < BaseFormatter` — renders a `CallTree` as an ASCII tree with `└──`/`├──` connectors, then appends a statistics block (slowest methods, most-called methods).
