# frozen_string_literal: true

require_relative "call_tree_statistics"

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
  #
  # Retention is bounded on both ends: calls faster than :threshold are
  # dropped unless they have children worth keeping, and :max_calls caps how
  # many completed calls and root trees are retained.
  class CallTree
    attr_reader :calls, :root_calls

    DEFAULT_MAX_CALLS = 1000

    # @param threshold [Float] Minimum duration in seconds for a leaf call to be kept
    # @param max_calls [Integer] Maximum completed calls and root trees to retain
    def initialize(threshold: 0.0, max_calls: DEFAULT_MAX_CALLS)
      @threshold = threshold
      @max_calls = max_calls
      @calls = []           # All recorded calls (flat list, shared)
      @root_calls = []      # Completed top-level calls (depth 0, shared)
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

      # Root calls are collected on completion rather than here, so an
      # in-flight call is never visible to readers of the hierarchy.
      stack.push(call_record)
      call_record
    end

    # End tracking a method call
    #
    # @param status [Symbol] :success, :error or :incomplete
    # @param error [Exception, nil] The exception if status is :error
    # @param execution_time [Float, nil] Duration in seconds. Callers that
    #   already timed the call pass it in, which saves a clock read here; when
    #   omitted it is measured from the record's start time.
    # @return [Hash, nil] The completed call record, or nil if it was dropped
    def end_call(status = :success, error = nil, execution_time = nil)
      stack = thread_call_stack
      return nil if stack.empty?

      call_record = stack.pop
      call_record[:status] = status
      call_record[:error] = error
      call_record[:execution_time] = execution_time || (monotonic_time - call_record[:start_time])

      return discard(call_record, stack.last) if discardable?(call_record)

      retain(call_record)
    end

    # Get the current call depth for the calling thread
    #
    # @return [Integer] The current nesting level
    def current_depth
      thread_call_stack.size
    end

    # Snapshot of every retained call, flat.
    #
    # @return [Array<Hash>] Completed call records, oldest first
    def calls_snapshot
      @lock.synchronize { @calls.dup }
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
      CallTreeStatistics.new(calls_snapshot).to_h
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

    # A call is dropped only when it is too fast to be interesting and has no
    # children — dropping a parent would orphan the descendants it recorded.
    def discardable?(call_record)
      call_record[:execution_time] < @threshold && call_record[:children].empty?
    end

    # The record is always the last child appended by this thread's stack, so
    # detaching it is a pop rather than a scan.
    def discard(call_record, parent)
      parent[:children].pop if parent && parent[:children].last.equal?(call_record)
      nil
    end

    def retain(call_record)
      @lock.synchronize do
        @calls << call_record
        @calls.shift while @calls.size > @max_calls
        next unless call_record[:depth].zero?

        # Dropping the oldest root releases its whole subtree; without this the
        # flat cap above could not actually free anything.
        @root_calls << call_record
        @root_calls.shift while @root_calls.size > @max_calls
      end
      call_record
    end

    # Returns the call stack for the current thread, creating it if needed.
    # Using a per-instance key prevents interference between multiple CallTree
    # instances running in the same thread.
    def thread_call_stack
      Thread.current[@thread_key] ||= []
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
