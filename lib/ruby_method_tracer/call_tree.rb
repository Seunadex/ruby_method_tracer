# frozen_string_literal: true

module RubyMethodTracer
  # CallTree manages the hierarchical structure of method calls,
  # tracking parent-child relationships and call depths.
  #
  # It uses a per-thread stack to manage nested calls and builds
  # a tree structure showing the complete call hierarchy.
  #
  # Note: @calls and @root_calls are shared across threads and protected
  # by a Mutex. The call stack is stored in thread-local storage so that
  # concurrent callers each maintain their own independent call depth.
  class CallTree
    attr_reader :calls, :root_calls

    def initialize
      @calls = []           # All recorded calls (flat list, shared)
      @root_calls = []      # Top-level calls (depth 0, shared)
      @lock = Mutex.new     # Protects @calls and @root_calls
      @thread_key = :"__ruby_method_tracer_call_stack_#{object_id}" # per-instance thread-local key
    end

    # Start tracking a method call
    #
    # @param method_name [String] The name of the method being called
    # @return [Hash] The call record that was pushed to the stack
    def start_call(method_name)
      stack = thread_call_stack

      call_record = {
        method_name: method_name,
        start_time: monotonic_time,
        depth: stack.size,
        children: [],
        status: nil,
        error: nil,
        execution_time: nil,
        timestamp: Time.now
      }

      # Add as child to parent if we're nested
      stack.last[:children] << call_record if stack.any?

      # Track root-level calls (lock required since @root_calls is shared)
      @lock.synchronize { @root_calls << call_record } if stack.empty?

      stack.push(call_record)
      call_record
    end

    # End tracking a method call
    #
    # @param status [Symbol] :success or :error
    # @param error [Exception, nil] The exception if status is :error
    # @return [Hash, nil] The completed call record
    def end_call(status = :success, error = nil)
      stack = thread_call_stack
      return nil if stack.empty?

      call_record = stack.pop
      call_record[:status] = status
      call_record[:error] = error
      call_record[:execution_time] = monotonic_time - call_record[:start_time]

      @lock.synchronize { @calls << call_record }
      call_record
    end

    # Get the current call depth for the calling thread
    #
    # @return [Integer] The current nesting level
    def current_depth
      thread_call_stack.size
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
    #
    # Note: only the current thread's call stack is cleared; other threads
    # that are mid-trace retain their stacks.
    def clear
      @lock.synchronize do
        @calls.clear
        @root_calls.clear
      end
      thread_call_stack.clear
    end

    # Check if the current thread has no active calls
    #
    # @return [Boolean]
    def empty?
      thread_call_stack.empty?
    end

    private

    # Returns the call stack for the current thread, creating it if needed.
    # Using a per-instance key prevents interference between multiple CallTree
    # instances running in the same thread.
    def thread_call_stack
      Thread.current[@thread_key] ||= []
    end

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
