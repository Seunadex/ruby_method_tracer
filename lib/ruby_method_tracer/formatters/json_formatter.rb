# frozen_string_literal: true

require "json"
require "time"
require_relative "base_formatter"

module RubyMethodTracer
  module Formatters
    # JsonFormatter serializes trace data to JSON.
    #
    # Security/privacy notes:
    # - Serialization uses `JSON.generate` only; no `Marshal`/`eval`/`YAML` is
    #   involved, so the output cannot be used as a deserialization gadget.
    # - Method arguments are never captured or emitted, avoiding accidental
    #   leakage of secrets passed as parameters.
    # - Exceptions are reduced to their class name and message. Backtraces are
    #   opt-in (`include_backtrace: true`) and truncated to `backtrace_limit`
    #   lines to avoid leaking large amounts of internal path information.
    #
    # Accepts either a CallTree (serializes hierarchy + statistics) or a flat
    # results hash as produced by `SimpleTracer#fetch_results`.
    class JsonFormatter < BaseFormatter
      def format(data, options = {})
        opts = default_options.merge(options)
        payload = build_payload(data, opts)
        opts[:pretty] ? JSON.pretty_generate(payload) : JSON.generate(payload)
      end

      private

      def default_options
        {
          pretty: false,
          include_backtrace: false,
          backtrace_limit: 10
        }
      end

      def build_payload(data, opts)
        if data.respond_to?(:call_hierarchy) && data.respond_to?(:statistics)
          {
            generated_at: Time.now.utc.iso8601,
            call_hierarchy: data.call_hierarchy.map { |node| serialize_node(node, opts) },
            statistics: serialize_statistics(data.statistics)
          }
        else
          serialize_flat(data, opts)
        end
      end

      def serialize_flat(results, opts)
        results = {} unless results.is_a?(Hash)
        calls = results[:calls] || []
        {
          generated_at: Time.now.utc.iso8601,
          total_calls: results[:total_calls] || calls.size,
          total_time: results[:total_time] || 0.0,
          calls: calls.map { |call| serialize_call(call, opts) }
        }
      end

      def serialize_call(call, opts)
        {
          method_name: call[:method_name],
          execution_time: call[:execution_time],
          status: call[:status],
          error: serialize_error(call[:error], opts),
          timestamp: iso8601(call[:timestamp])
        }
      end

      def serialize_node(node, opts)
        {
          method_name: node[:method_name],
          execution_time: node[:execution_time],
          status: node[:status],
          depth: node[:depth],
          error: serialize_error(node[:error], opts),
          timestamp: iso8601(node[:timestamp]),
          children: (node[:children] || []).map { |child| serialize_node(child, opts) }
        }
      end

      def serialize_statistics(stats)
        stats
      end

      # Reduce an exception to a safe, bounded representation.
      def serialize_error(error, opts)
        return nil unless error

        result = { class: error.class.name, message: error.message.to_s }
        if opts[:include_backtrace] && error.backtrace
          limit = opts[:backtrace_limit].to_i
          result[:backtrace] = limit.positive? ? error.backtrace.first(limit) : []
        end
        result
      end

      def iso8601(time)
        time.respond_to?(:iso8601) ? time.iso8601(6) : time
      end
    end
  end
end
