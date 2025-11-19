# frozen_string_literal: true

require "set"
require "logger"

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
  class SimpleTracer # rubocop:disable Metrics/ClassLength
    def initialize(target_class, **options)
      @target_class = target_class
      @options = default_options.merge(options)
      @calls = []
      @lock  = Mutex.new # Mutex to make writes to @calls thread safe.
      @wrapped_methods = Set.new
      @logger = @options[:logger] || Logger.new($stdout)
    end

    def trace_method(name)
      method_name = name.to_sym
      visibility = method_visibility(method_name)
      return unless visibility
      return unless mark_wrapped?(method_name)

      aliased = alias_for(method_name)
      @target_class.send(:alias_method, aliased, method_name) # Aliases original implementation to our private name.

      tracer = self
      key = :__ruby_method_tracer_in_trace # local key to avoid recursive tracing.

      # Defines a new method with the original name that delegates to our wrapper.
      @target_class.define_method(method_name, &build_wrapper(aliased, method_name, key, tracer))

      @target_class.send(visibility, method_name) # Restores the original visibility after redefine.
    end

    def record_call(method_name, execution_time, status, error = nil)
      return if execution_time < @options[:threshold]

      call_details = {
        method_name: "#{@target_class}##{method_name}",
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

    def default_options
      {
        threshold: 0.001,
        auto_output: false,
        max_calls: 1000,
        logger: nil
      }
    end

    def method_visibility(method_name)
      return :private if @target_class.private_method_defined?(method_name)
      return :protected if @target_class.protected_method_defined?(method_name)
      return :public if @target_class.method_defined?(method_name)

      nil
    end

    # Marks a method as wrapped to avoid duplicates
    def mark_wrapped?(method_name)
      return false if @wrapped_methods.include?(method_name)

      @wrapped_methods << method_name
      true
    end

    def alias_for(method_name)
      :"__ruby_method_tracer_original_#{method_name}__"
    end

    def build_wrapper(aliased, method_name, key, tracer)
      proc do |*args, **kwargs, &block|                                # Captures args and block exactly like original.
        tracer.__send__(:wrap_call, method_name, key) do               # Delegates to wrapper to handle timing and flag.
          __send__(aliased, *args, **kwargs, &block)                   # Calls the original aliased implementation.
        end
      end
    end

    def wrap_call(method_name, key)
      return yield if Thread.current[key]

      Thread.current[key] = true
      start = monotonic_time
      begin
        result = yield
        record_call(method_name, monotonic_time - start, :success)
        result
      rescue StandardError => e
        record_call(method_name, monotonic_time - start, :error, e)
        raise
      ensure
        Thread.current[key] = false
      end
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def output_call(call)
      time_str = colorize(format_time(call[:execution_time]), :yellow)
      status_str = call[:status] == :error ? colorize("[ERROR]", :red) : colorize("[OK]", :green)
      method_name = colorize(call[:method_name], :cyan)
      if call[:status] == :error
        @logger.warn(
          "TRACE: #{method_name} #{status_str} took #{time_str} - Error: #{call[:error].class}: #{call[:error].message}"
        )
      else
        @logger.info("TRACE: #{method_name} #{status_str} took #{time_str}")
      end
    end

    def format_time(seconds)
      if seconds >= 1.0
        "#{seconds.round(3)}s"
      elsif seconds >= 0.001
        "#{(seconds * 1000).round(1)}ms"
      else
        "#{(seconds * 1_000_000).round(0)}µs"
      end
    end

    def colorize(text, color)
      colors = {
        red: "31",
        green: "32",
        yellow: "33",
        blue: "34",
        magenta: "35",
        cyan: "36",
        white: "37",
        reset: "0"
      }
      "\e[#{colors[color]}m#{text}\e[#{colors[:reset]}m"
    end
  end
end
