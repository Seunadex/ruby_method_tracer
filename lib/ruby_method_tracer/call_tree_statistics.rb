# frozen_string_literal: true

module RubyMethodTracer
  # CallTreeStatistics summarises a list of completed call records.
  #
  # It is a pure function of the records handed to it — the caller is
  # responsible for reading them under whatever lock protects them.
  class CallTreeStatistics
    TOP_N = 10

    EMPTY = {
      total_calls: 0,
      total_time: 0.0,
      unique_methods: 0,
      slowest_methods: [],
      most_called_methods: [],
      average_time_per_method: {},
      max_depth: 0
    }.freeze

    def initialize(calls)
      @calls = calls
    end

    # @return [Hash] Totals, the slowest and most-called methods, and max depth
    def to_h
      return EMPTY.dup if @calls.empty?

      stats = per_method

      {
        total_calls: @calls.size,
        total_time: @calls.sum { |call| call[:execution_time] },
        unique_methods: stats.size,
        slowest_methods: slowest(stats),
        most_called_methods: most_called(stats),
        average_time_per_method: averages(stats),
        max_depth: max_depth
      }
    end

    private

    def per_method
      blank = Hash.new { |hash, key| hash[key] = { calls: 0, total_time: 0.0 } }
      @calls.each_with_object(blank) do |call, stats|
        entry = stats[call[:method_name]]
        entry[:calls] += 1
        entry[:total_time] += call[:execution_time]
      end
    end

    def slowest(stats)
      stats
        .map { |name, entry| { method: name, avg_time: entry[:total_time] / entry[:calls] } }
        .sort_by { |method| -method[:avg_time] }
        .take(TOP_N)
    end

    def most_called(stats)
      stats
        .map { |name, entry| { method: name, count: entry[:calls] } }
        .sort_by { |method| -method[:count] }
        .take(TOP_N)
    end

    def averages(stats)
      stats.transform_values { |entry| entry[:total_time] / entry[:calls] }
    end

    def max_depth
      @calls.map { |call| call[:depth] }.max || 0
    end
  end
end
