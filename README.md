[![Ruby](https://github.com/Seunadex/ruby_method_tracer/actions/workflows/main.yml/badge.svg?branch=main)](https://github.com/Seunadex/ruby_method_tracer/actions/workflows/main.yml)

# RubyMethodTracer

RubyMethodTracer is a lightweight Ruby mixin for targeted method tracing. It wraps instance methods, measures wall-clock runtime, flags errors, and can stream results to your logger without pulling in a full APM agent. Use it to surface slow paths in production or gather quick instrumentation while debugging.

## Highlights
- Wrap only the methods you care about; public, protected, and private methods are supported.
- Records duration, success/error state, and timestamps with thread-safe storage.
- **NEW: Hierarchical call tree visualization** to understand nested method calls and dependencies.
- Configurable threshold to ignore fast calls and optional log streaming via `Logger`.
- Zero dependencies beyond the Ruby standard library, keeping overhead minimal.

## Installation

Add this line to your application's Gemfile:

```ruby
gem "ruby_method_tracer"
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install ruby_method_tracer
```

For local development or experimentation:

```bash
git clone https://github.com/Seunadex/ruby_method_tracer.git
cd ruby_method_tracer
bundle exec rake install
```

## Usage

### Example 1
Include `RubyMethodTracer` in any class whose instance methods you want to observe. Register the target methods with optional settings.

```ruby

class Worker
  include RubyMethodTracer

  def perform(user_id)
    expensive_call(user_id)
  end

  private

  def expensive_call(id)
    # work...
  end
end

Worker.trace_methods(:perform, threshold: 0.005, auto_output: true)

Worker.new.perform(42)
```

With `auto_output: true`, each invocation prints a colorized summary:

```
TRACE: Worker#perform [OK] took 6.3ms
```

To inspect trace results programmatically, manage the tracer yourself:

```ruby
tracer = RubyMethodTracer::SimpleTracer.new(Worker, threshold: 0.002)
tracer.trace_method(:perform)

Worker.new.perform(42)

pp tracer.fetch_results
# => {
#      total_calls: 1,
#      total_time: 0.0063,
#      calls: [
#        { method_name: "Worker#perform", execution_time: 0.0063, status: :success, ... }
#      ]
#    }

# Clear results when needed to free memory
tracer.clear_results
```

### Example 2

```ruby
class OrderProcessor
  include RubyMethodTracer

  def process_order(order)
    # ... perform work ...
  end

  trace_methods :process_order, auto_output: true
end
```

### Example 3: Advanced Configuration

```ruby
# Use a custom logger to write traces to a file
custom_logger = Logger.new('trace.log')
custom_logger.level = Logger::INFO

tracer = RubyMethodTracer::SimpleTracer.new(
  MyService,
  threshold: 0.01,           # Only record calls over 10ms
  auto_output: true,         # Log each call
  max_calls: 500,            # Keep only last 500 calls in memory
  logger: custom_logger      # Use custom logger
)
tracer.trace_method(:expensive_operation)

# Later, clear results to free memory
tracer.clear_results
```

### Example 4: Call Tree Visualization (NEW!)

Visualize hierarchical method call relationships with the `EnhancedTracer`:

```ruby
class OrderProcessor
  def process_order(order)
    validate_order(order)
    charge_payment(order)
    send_confirmation(order)
  end

  def validate_order(order)
    check_inventory(order.items)
  end

  def charge_payment(order)
    # Payment processing...
  end

  def send_confirmation(order)
    # Email sending...
  end

  private

  def check_inventory(items)
    # Inventory check...
  end
end

# Use EnhancedTracer for call tree tracking
tracer = RubyMethodTracer::EnhancedTracer.new(OrderProcessor, threshold: 0.0)
tracer.trace_method(:process_order)
tracer.trace_method(:validate_order)
tracer.trace_method(:charge_payment)
tracer.trace_method(:send_confirmation)
tracer.trace_method(:check_inventory)

processor = OrderProcessor.new
processor.process_order(order)

# Print beautiful call tree visualization
tracer.print_tree
```

This outputs a hierarchical tree showing nested calls:

```
METHOD CALL TREE
============================================================
└── OrderProcessor#process_order (125.3ms)
    ├── OrderProcessor#validate_order (15.2ms)
    │   └── OrderProcessor#check_inventory (12.1ms)
    ├── OrderProcessor#charge_payment (85.4ms)
    └── OrderProcessor#send_confirmation (24.7ms)
============================================================

STATISTICS
------------------------------------------------------------
Total Calls: 5
Total Time: 250.6ms
Unique Methods: 5
Max Depth: 2

Slowest Methods (by average time):
  1. OrderProcessor#process_order - 125.3ms
  2. OrderProcessor#charge_payment - 85.4ms
  3. OrderProcessor#send_confirmation - 24.7ms
  4. OrderProcessor#validate_order - 15.2ms
  5. OrderProcessor#check_inventory - 12.1ms

Most Called Methods:
  1. OrderProcessor#process_order - 1 calls
  2. OrderProcessor#validate_order - 1 calls
  ...
```

**Call Tree Features:**
- Shows parent-child relationships between methods
- Visual tree structure with proper indentation
- Execution times for each method call
- Statistics summary (slowest methods, most called, max depth)
- Error indicators with full error messages
- Color-coded output for better readability


### Options (SimpleTracer)

- `threshold` (Float, default `0.001`): minimum duration (in seconds) to record.
- `auto_output` (Boolean, default `false`): emit a log line using `Logger` for each recorded call.
- `max_calls` (Integer, default `1000`): maximum number of calls to store in memory. When exceeded, the oldest calls are automatically removed to prevent memory leaks.
- `logger` (Logger, default `Logger.new($stdout)`): custom logger instance for output. Useful for directing logs to files or custom log handlers.

### Options (EnhancedTracer)

EnhancedTracer supports all SimpleTracer options plus:

- `track_hierarchy` (Boolean, default `true`): enable call tree tracking. Set to `false` to use EnhancedTracer like SimpleTracer.

### API Methods (EnhancedTracer)

- `print_tree(options = {})` - Print formatted call tree to stdout
  - Options: `colorize: true/false`, `show_errors: true/false`
- `format_tree(options = {})` - Get formatted call tree as string
- `fetch_enhanced_results` - Get hash with `:flat_calls`, `:call_hierarchy`, and `:statistics`
- `clear_results` - Clear both flat results and call tree

## Choosing Between SimpleTracer and EnhancedTracer

**Use SimpleTracer when:**
- You only need flat timing data
- You want minimal overhead
- You're tracing independent methods

**Use EnhancedTracer when:**
- You need to understand call hierarchies
- You want to visualize nested method calls
- You're debugging complex call flows
- You need statistics on method relationships

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then run `rake spec` to execute the test suite. You can also run `bin/console` for an interactive prompt.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version in `lib/ruby_method_tracer/version.rb`, and then run `bundle exec rake release`.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/Seunadex/ruby_method_tracer. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/Seunadex/ruby_method_tracer/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT). See `LICENSE.txt` for details.

## Code of Conduct

Everyone interacting in the RubyMethodTracer project's codebases, issue trackers, chat rooms, and mailing lists is expected to follow the [code of conduct](https://github.com/Seunadex/ruby_method_tracer/blob/main/CODE_OF_CONDUCT.md).
