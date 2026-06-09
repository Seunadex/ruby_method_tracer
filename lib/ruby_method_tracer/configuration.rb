# frozen_string_literal: true

module RubyMethodTracer
  # Configuration holds global defaults for tracers created through the
  # mixin API. Per-tracer options passed to `trace_methods` or to a tracer's
  # constructor always take precedence over these globals.
  #
  # Configure once during application boot:
  #
  #   RubyMethodTracer.configure do |config|
  #     config.threshold   = 0.005
  #     config.max_calls   = 500
  #     config.auto_output = true
  #   end
  #
  # The object is intended to be set at boot and then read concurrently.
  # Mutating it after threads are tracing is not recommended.
  class Configuration
    # Minimum duration (seconds) a call must take to be recorded.
    attr_accessor :threshold
    # When true, each recorded call is emitted to the logger.
    attr_accessor :auto_output
    # Maximum number of calls retained in memory (sliding window).
    attr_accessor :max_calls
    # Logger instance used for auto output. Nil means each tracer builds its own.
    attr_accessor :logger
    # Whether EnhancedTracer builds a hierarchical call tree.
    attr_accessor :track_hierarchy

    def initialize
      reset!
    end

    # Restore all settings to their built-in defaults.
    def reset!
      @threshold = 0.001
      @auto_output = false
      @max_calls = 1000
      @logger = nil
      @track_hierarchy = true
      self
    end

    # Snapshot of the option keys consumed by the tracers.
    #
    # @return [Hash]
    def to_h
      {
        threshold: @threshold,
        auto_output: @auto_output,
        max_calls: @max_calls,
        logger: @logger,
        track_hierarchy: @track_hierarchy
      }
    end
  end
end
