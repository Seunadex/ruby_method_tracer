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
  # Usage:
  #   tracer = RubyMethodTracer::EnhancedTracer.new(MyClass, threshold: 0.005)
  #   tracer.trace_method(:expensive_call)
  #   tracer.print_tree
  class EnhancedTracer < SimpleTracer
    attr_reader :call_tree

    def initialize(target_class, **options)
      super
      @call_tree = CallTree.new
      @track_hierarchy = @options.fetch(:track_hierarchy, true)
      @formatter = Formatters::TreeFormatter.new
    end

    def trace_method(name)
      method_name = name.to_sym
      visibility = method_visibility(method_name)
      return unless visibility
      return unless mark_wrapped?(method_name)

      aliased = alias_for(method_name)
      @target_class.send(:alias_method, aliased, method_name)

      tracer = self
      key = @tracer_key # unique per tracer instance; prevents cross-tracer interference

      # Build wrapper that tracks hierarchy
      @target_class.define_method(method_name, &build_enhanced_wrapper(aliased, method_name, key, tracer))

      @target_class.send(visibility, method_name)
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

    # Clear both simple tracer results and call tree
    def clear_results
      super
      @call_tree.clear
    end

    private

    def build_enhanced_wrapper(aliased, method_name, key, tracer)
      track_hierarchy = tracer.instance_variable_get(:@track_hierarchy)
      # Use method-specific key to prevent only SELF-recursion, not all nested calls
      method_key = :"#{key}_#{method_name}"

      proc do |*args, **kwargs, &block|
        # Ruby 3+ compatible forwarding helper (avoids passing **{} which caused
        # SystemStackError with Ruby 3.4+ keyword argument forwarding)
        call_aliased = lambda do
          kwargs.empty? ? __send__(aliased, *args, &block) : __send__(aliased, *args, **kwargs, &block)
        end

        if track_hierarchy
          tracer.__send__(:run_with_hierarchy, method_name, method_key, call_aliased)
        else
          tracer.__send__(:wrap_call, method_name, key) { call_aliased.call }
        end
      end
    end

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def run_with_hierarchy(method_name, method_key, call_aliased)
      # Prevent only recursive calls to the SAME method
      return call_aliased.call if Thread.current[method_key]

      Thread.current[method_key] = true
      full_method_name = "#{@target_class}##{method_name}"

      # Start tracking in call tree before entering the timed section
      @call_tree.start_call(full_method_name)

      start = monotonic_time
      call_status = :success
      call_error = nil

      begin
        result = call_aliased.call
        execution_time = monotonic_time - start
        record_call(method_name, execution_time, :success)
        result
      rescue StandardError => e
        call_status = :error
        call_error = e
        execution_time = monotonic_time - start
        record_call(method_name, execution_time, :error, e)
        raise
      ensure
        Thread.current[method_key] = false
        # Always end the call tree entry, even for non-StandardError exceptions,
        # to prevent the per-thread call stack from becoming corrupted.
        @call_tree.end_call(call_status, call_error)
      end
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    def default_options
      super.merge(track_hierarchy: true)
    end
  end
end
