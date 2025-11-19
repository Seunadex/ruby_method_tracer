# frozen_string_literal: true

module RubyMethodTracer
  # CallTree manages the hierarchical structure of method calls,
  # tracking parent-child relationships and call depths.
  #
  # It uses a stack-based approach to manage nested calls and builds
  # a tree structure showing the complete call hierarchy.
  class CallTree
    attr_reader :calls, :root_calls

    def initialize
      @calls = []           # All recorded calls (flat list)
      @call_stack = []      # Current execution stack
      @root_calls = []      # Top-level calls (depth 0)
      @lock = Mutex.new     # Thread safety
    end

    # Start tracking a method call
    #
    # @param method_name [String] The name of the method being called
    # @return [Hash] The call record that was pushed to the stack
    def start_call(method_name) # rubocop:disable Metrics/MethodLength
      @lock.synchronize do
        call_record = {
          method_name: method_name,
          start_time: monotonic_time,
          depth: @call_stack.size,
          parent: @call_stack.last,
          children: [],
          status: nil,
          error: nil,
          execution_time: nil,
          timestamp: Time.now
        }

        # Add as child to parent if we're nested
        @call_stack.last[:children] << call_record if @call_stack.any?

        # Track root-level calls
        @root_calls << call_record if @call_stack.empty?

        @call_stack.push(call_record)
        call_record
      end
    end

    # End tracking a method call
    #
    # @param status [Symbol] :success or :error
    # @param error [Exception, nil] The exception if status is :error
    # @return [Hash, nil] The completed call record
    def end_call(status = :success, error = nil)
      @lock.synchronize do
        return nil if @call_stack.empty?

        call_record = @call_stack.pop
        call_record[:status] = status
        call_record[:error] = error
        call_record[:execution_time] = monotonic_time - call_record[:start_time]

        @calls << call_record
        call_record
      end
    end

    # Get the current call depth
    #
    # @return [Integer] The current nesting level
    def current_depth
      @lock.synchronize { @call_stack.size }
    end

    # Get call hierarchy as nested structure
    #
    # @return [Array<Hash>] Root calls with nested children
    def call_hierarchy
      @lock.synchronize { @root_calls.dup }
    end

    # Calculate statistics from recorded calls
    #
    # @return [Hash] Statistics including total calls, time, slowest methods, etc.
    def statistics
      @lock.synchronize do
        return default_statistics if @calls.empty?

        method_stats = calculate_method_stats

        {
          total_calls: @calls.size,
          total_time: @calls.sum { |c| c[:execution_time] },
          unique_methods: method_stats.size,
          slowest_methods: slowest_methods(method_stats),
          most_called_methods: most_called_methods(method_stats),
          average_time_per_method: average_times(method_stats),
          max_depth: @calls.map { |c| c[:depth] }.max || 0
        }
      end
    end

    # Clear all recorded calls and reset state
    def clear
      @lock.synchronize do
        @calls.clear
        @call_stack.clear
        @root_calls.clear
      end
    end

    # Check if call stack is empty (no active calls)
    #
    # @return [Boolean]
    def empty?
      @lock.synchronize { @call_stack.empty? }
    end

    private

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def default_statistics
      {
        total_calls: 0,
        total_time: 0.0,
        unique_methods: 0,
        slowest_methods: [],
        most_called_methods: [],
        average_time_per_method: {},
        max_depth: 0
      }
    end

    def calculate_method_stats
      method_stats = Hash.new { |h, k| h[k] = { calls: 0, total_time: 0.0, times: [] } }

      @calls.each do |call|
        stats = method_stats[call[:method_name]]
        stats[:calls] += 1
        stats[:total_time] += call[:execution_time]
        stats[:times] << call[:execution_time]
      end

      method_stats
    end

    def slowest_methods(method_stats)
      method_stats
        .map { |name, stats| { method: name, avg_time: stats[:total_time] / stats[:calls] } }
        .sort_by { |m| -m[:avg_time] }
        .take(10)
    end

    def most_called_methods(method_stats)
      method_stats
        .map { |name, stats| { method: name, count: stats[:calls] } }
        .sort_by { |m| -m[:count] }
        .take(10)
    end

    def average_times(method_stats)
      method_stats.transform_values { |stats| stats[:total_time] / stats[:calls] }
    end
  end
end
