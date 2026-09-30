# frozen_string_literal: true

require "logger"
require_relative "formatters/base_formatter"
require_relative "exportable"
require_relative "wrapper"

module RubyMethodTracer
  # SimpleTracer wraps instance methods on a target class and records
  # execution metrics for each invocation. It measures wall-clock duration,
  # captures success or error status, stores results in-memory, and can
  # optionally print each trace as it happens.
  #
  # Options:
  # - :threshold (Float): Minimum duration in seconds to record; defaults to 0.001 (1ms).
  # - :auto_output (Boolean): When true, prints each call summary; defaults to false.
  # - :max_calls (Integer): Maximum number of calls to store; defaults to 1000. When exceeded, oldest calls are removed.
  # - :logger (Logger): Custom logger instance; defaults to Logger.new($stdout).
  #
  # Usage:
  #   tracer = RubyMethodTracer::SimpleTracer.new(MyClass, threshold: 0.005)
  #   tracer.trace_method(:expensive_call)
  #   results = tracer.fetch_results
  #
  # To trace class (singleton) methods, pass the singleton class:
  #   RubyMethodTracer::SimpleTracer.new(MyClass.singleton_class)
  # rubocop:disable Metrics/ClassLength
  class SimpleTracer
    include Exportable

    # Method names the parser accepts as a bare identifier in a call.
    PLAIN_IDENTIFIER = /\A[a-z_][A-Za-z0-9_]*\z/
    private_constant :PLAIN_IDENTIFIER

    def initialize(target_class, **options)
      @target_class = target_class
      @options = default_options.merge(options)
      @calls = []
      @lock  = Mutex.new # Mutex to make writes to @calls thread safe.
      @wrapped_methods = {} # method name => visibility it had before wrapping
      @qualified_names = {} # method name => display name, precomputed
      @logger = @options[:logger] || Logger.new($stdout)
      # Unique per instance so separate tracers don't interfere with each other.
      @tracer_key = :"__ruby_method_tracer_in_trace_#{object_id}"
      @accessor = :"__ruby_method_tracer_#{object_id}__"
      @formatter = Formatters::BaseFormatter.new
    end

    # Wrap a method so its calls are recorded.
    #
    # @param name [Symbol, String] Method to trace
    # @return [Boolean] true if the method was wrapped by this call
    def trace_method(name)
      method_name = name.to_sym
      visibility = method_visibility(method_name)
      unless visibility
        warn_missing(method_name)
        return false
      end
      return false if already_traced?(method_name)

      install_wrapper(method_name, visibility)
      @wrapped_methods[method_name] = visibility
      @qualified_names[method_name] = qualified_name(method_name)
      true
    end

    # Restore a traced method to its original implementation and visibility.
    #
    # @param name [Symbol, String] Method to untrace
    # @return [Boolean] true if the method was traced by this tracer
    def untrace_method(name)
      method_name = name.to_sym
      visibility = @wrapped_methods.delete(method_name)
      return false unless visibility

      aliased = alias_for(method_name)
      @target_class.send(:alias_method, method_name, aliased)
      @target_class.send(:remove_method, aliased)
      @target_class.send(visibility, method_name)
      @qualified_names.delete(method_name)
      true
    end

    # Restore every method this tracer wrapped.
    #
    # @return [Array<Symbol>] The methods that were untraced
    def untrace_all
      @wrapped_methods.keys.each_with_object([]) do |method_name, untraced|
        untraced << method_name if untrace_method(method_name)
      end
    end

    # Called by the generated wrapper once per invocation. Kept public because
    # it is the documented way to feed a tracer by hand.
    def record_call(method_name, execution_time, status, error = nil)
      return if execution_time < @options[:threshold]

      call_details = {
        method_name: @qualified_names[method_name] || qualified_name(method_name),
        execution_time: execution_time,
        status: status,
        error: error,
        timestamp: Time.now
      }

      @lock.synchronize do
        @calls << call_details
        # Enforce max_calls limit by removing oldest entries
        @calls.shift if @calls.size > @options[:max_calls]
      end

      output_call(call_details) if @options[:auto_output]
    end

    def fetch_results
      snapshot = nil
      @lock.synchronize { snapshot = @calls.dup } # Copies under lock to prevent races while reading.

      {
        total_calls: snapshot.size,
        total_time: snapshot.sum { |call| call[:execution_time] },
        calls: snapshot
      }
    end

    def clear_results
      @lock.synchronize { @calls.clear }
    end

    private

    # Data passed to formatters by Exportable. Overridden by EnhancedTracer to
    # expose the call tree.
    def report_source
      fetch_results
    end

    def default_options
      config = RubyMethodTracer.configuration
      {
        threshold: config.threshold,
        auto_output: config.auto_output,
        max_calls: config.max_calls,
        logger: config.logger
      }
    end

    def method_visibility(method_name)
      return :private if @target_class.private_method_defined?(method_name)
      return :protected if @target_class.protected_method_defined?(method_name)
      return :public if @target_class.method_defined?(method_name)

      nil
    end

    # Alias the original body aside, define the traced replacement in its
    # place, and put the original visibility back.
    def install_wrapper(method_name, visibility)
      aliased = alias_for(method_name)
      @target_class.send(:alias_method, aliased, method_name)
      # Keep the alias out of the public API: alias_method inherits the
      # original's visibility, which would otherwise expose it on every object.
      @target_class.send(:private, aliased)
      define_accessor
      Wrapper.install(@target_class, method_name, aliased, @accessor, wrapper_plan(method_name))
      @target_class.send(visibility, method_name)
    end

    # What the generated wrapper should do around the call. Overridden by
    # EnhancedTracer to add the call-tree hook.
    def wrapper_plan(_method_name)
      Wrapper::Plan.new(key: @tracer_key, close: :record_call)
    end

    # Generated wrappers are compiled from a string and cannot close over the
    # tracer, so they reach it through this private accessor instead.
    def define_accessor
      return if @accessor_defined

      tracer = self
      @target_class.define_method(@accessor) { tracer }
      @target_class.send(:private, @accessor)
      @accessor_defined = true
    end

    # A method is already traced when this tracer wrapped it, or when the alias
    # is present because some other tracer did. Wrapping twice would alias the
    # existing wrapper onto itself and recurse until the stack runs out.
    def already_traced?(method_name)
      return true if @wrapped_methods.key?(method_name)

      aliased = alias_for(method_name)
      return false unless @target_class.private_method_defined?(aliased) ||
                          @target_class.method_defined?(aliased)

      @logger.warn("RubyMethodTracer: #{@target_class}##{method_name} is already traced; skipping")
      true
    end

    def warn_missing(method_name)
      @logger.warn("RubyMethodTracer: #{@target_class} has no method ##{method_name}; not traced")
    end

    # Singleton classes stringify as "#<Class:Foo>"; render those as "Foo.bar"
    # so traced class methods read the way they are called.
    def qualified_name(method_name)
      return "#{@target_class}##{method_name}" unless @target_class.singleton_class?

      "#{singleton_owner}.#{method_name}"
    end

    # Module#attached_object is Ruby 3.2+; fall back to unwrapping the string
    # form on older versions.
    def singleton_owner
      return @target_class.attached_object if @target_class.respond_to?(:attached_object)

      @target_class.to_s[/\A#<Class:(.+)>\z/, 1] || @target_class.to_s
    end

    # Name under which the original implementation is kept.
    #
    # The generated wrapper calls this alias directly rather than through
    # `__send__`, which is faster but requires a name the parser accepts as an
    # identifier. Predicate (`foo?`), bang (`foo!`), setter (`foo=`) and
    # operator (`==`, `[]`, `<=>`) methods are not, so those are hex-encoded.
    # Deterministic either way, so `untrace_method` reconstructs the same name.
    def alias_for(method_name)
      name = method_name.to_s
      part = PLAIN_IDENTIFIER.match?(name) ? name : "op_#{name.unpack1("H*")}"
      :"__ruby_method_tracer_original_#{part}__"
    end

    # Only used by tracers feeding themselves; the generated wrapper reads the
    # clock inline so the call path carries no extra frames.
    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def output_call(call)
      time_str = colorize(format_time(call[:execution_time]), :yellow)
      status_str = status_label(call[:status])
      method_name = colorize(call[:method_name], :cyan)
      if call[:status] == :error
        @logger.warn(
          "TRACE: #{method_name} #{status_str} took #{time_str} - Error: #{call[:error].class}: #{call[:error].message}"
        )
      else
        @logger.info("TRACE: #{method_name} #{status_str} took #{time_str}")
      end
    end

    def status_label(status)
      case status
      when :error then colorize("[ERROR]", :red)
      when :incomplete then colorize("[INCOMPLETE]", :yellow)
      else colorize("[OK]", :green)
      end
    end

    def format_time(seconds)
      @formatter.format_time(seconds)
    end

    def colorize(text, color)
      @formatter.colorize(text, color)
    end
  end
  # rubocop:enable Metrics/ClassLength
end
