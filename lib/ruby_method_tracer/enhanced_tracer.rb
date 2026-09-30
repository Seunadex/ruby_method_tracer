# frozen_string_literal: true

require_relative "simple_tracer"
require_relative "call_tree"
require_relative "formatters/tree_formatter"

module RubyMethodTracer
  # EnhancedTracer extends SimpleTracer with hierarchical call tracking
  #
  # In addition to the basic tracing functionality, this tracer maintains
  # a call tree that captures parent-child relationships between method calls,
  # enabling visualization of complex call hierarchies.
  #
  # Options:
  # - All options from SimpleTracer
  # - :track_hierarchy (Boolean): Enable call tree tracking; defaults to true
  #
  # The call tree honours the same :threshold and :max_calls limits as the flat
  # results, so leaving a tracer enabled cannot grow the tree without bound.
  #
  # The tree is the only store: `fetch_results` is derived from it rather than
  # maintained alongside it, so a traced call is recorded once, not twice.
  #
  # Usage:
  #   tracer = RubyMethodTracer::EnhancedTracer.new(MyClass, threshold: 0.005)
  #   tracer.trace_method(:expensive_call)
  #   tracer.print_tree
  class EnhancedTracer < SimpleTracer
    attr_reader :call_tree

    def initialize(target_class, **options)
      super
      @call_tree = CallTree.new(threshold: @options[:threshold], max_calls: @options[:max_calls])
      @track_hierarchy = @options.fetch(:track_hierarchy, true)
      @formatter = Formatters::TreeFormatter.new
    end

    # Print the call tree visualization
    #
    # @param options [Hash] Formatting options
    # @option options [Boolean] :show_errors (true) Include error information
    # @option options [Boolean] :colorize (true) Apply colors to output
    def print_tree(options = {})
      puts @formatter.format(@call_tree, options)
    end

    # Get call tree as string without printing
    #
    # @param options [Hash] Formatting options
    # @return [String] Formatted call tree
    def format_tree(options = {})
      @formatter.format(@call_tree, options)
    end

    # Flat results, derived from the call tree.
    #
    # The tree already holds every completed call with its duration, status and
    # error, so keeping a second parallel list would mean recording each call
    # twice. The projection below is what makes the two views agree by
    # construction.
    #
    # @return [Hash] Totals and the flat call list
    def fetch_results
      return super unless @track_hierarchy

      snapshot = @call_tree.calls_snapshot
      {
        total_calls: snapshot.size,
        total_time: snapshot.sum { |call| call[:execution_time] },
        calls: snapshot.map { |call| flat_record(call) }
      }
    end

    # Get enhanced results including both flat list and hierarchy
    #
    # @return [Hash] Results with call tree and statistics
    def fetch_enhanced_results
      {
        flat_calls: fetch_results,
        call_hierarchy: @call_tree.call_hierarchy,
        statistics: @call_tree.statistics
      }
    end

    # Wrapper entry point: open a call-tree entry.
    #
    # Public because the generated wrapper calls it with an explicit receiver,
    # which cannot reach a private method.
    #
    # @param display_name [String] Name as it should appear in reports
    def start_call(display_name)
      @call_tree.start_call(display_name)
    end

    # Wrapper entry point: close the call-tree entry for this invocation.
    #
    # Nothing is stored in the flat list — `fetch_results` derives it from the
    # tree — so a traced call is recorded once. `end_call` returns nil when the
    # call fell below the threshold, which is what gates auto output.
    def record_call(method_name, execution_time, status, error = nil)
      return super unless @track_hierarchy

      call = @call_tree.end_call(status, error, execution_time)
      output_call(flat_record(call)) if call && @options[:auto_output]
    end

    # Clear both simple tracer results and call tree
    def clear_results
      super
      @call_tree.clear
    end

    private

    def flat_record(call)
      {
        method_name: call[:method_name],
        execution_time: call[:execution_time],
        status: call[:status],
        error: call[:error],
        timestamp: call[:timestamp]
      }
    end

    # Per-method reentrancy key so that *different* wrapped methods can nest
    # inside each other; only self-recursion is blocked. Baked into the wrapper
    # as a literal, so no lookup happens on the call path.
    def wrapper_plan(method_name)
      return super unless @track_hierarchy

      Wrapper::Plan.new(
        key: :"#{@tracer_key}_#{method_name}",
        close: :record_call,
        open: :start_call,
        display_name: qualified_name(method_name)
      )
    end

    # Expose the call tree so JSON/flat exports include hierarchy + statistics.
    def report_source
      @call_tree
    end

    def build_formatter(format)
      return Formatters::TreeFormatter.new if format.to_sym == :tree

      super
    end

    def default_options
      super.merge(track_hierarchy: RubyMethodTracer.configuration.track_hierarchy)
    end
  end
end
