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
      key = :__ruby_method_tracer_in_trace

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

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def build_enhanced_wrapper(aliased, method_name, key, tracer)
      track_hierarchy = tracer.instance_variable_get(:@track_hierarchy)
      # Use method-specific key to prevent only SELF-recursion, not all nested calls
      method_key = :"#{key}_#{method_name}"

      proc do |*args, **kwargs, &block|
        if track_hierarchy
          # Prevent only recursive calls to the SAME method
          return __send__(aliased, *args, **kwargs, &block) if Thread.current[method_key]

          Thread.current[method_key] = true
          full_method_name = "#{tracer.instance_variable_get(:@target_class)}##{method_name}"

          # Start tracking in call tree
          tracer.call_tree.start_call(full_method_name)

          start = tracer.__send__(:monotonic_time)
          begin
            result = __send__(aliased, *args, **kwargs, &block)
            execution_time = tracer.__send__(:monotonic_time) - start

            # Record in both places
            tracer.__send__(:record_call, method_name, execution_time, :success)
            tracer.call_tree.end_call(:success)

            result
          rescue StandardError => e
            execution_time = tracer.__send__(:monotonic_time) - start

            # Record in both places
            tracer.__send__(:record_call, method_name, execution_time, :error, e)
            tracer.call_tree.end_call(:error, e)

            raise
          ensure
            Thread.current[method_key] = false
          end
        else
          tracer.__send__(:wrap_call, method_name, key) do
            __send__(aliased, *args, **kwargs, &block)
          end
        end
      end
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    def default_options
      super.merge(track_hierarchy: true)
    end
  end
end
