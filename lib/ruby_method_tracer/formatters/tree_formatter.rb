# frozen_string_literal: true

require_relative "base_formatter"

module RubyMethodTracer
  module Formatters
    # TreeFormatter generates hierarchical tree visualizations of method calls
    class TreeFormatter < BaseFormatter
      # Format call tree into hierarchical string representation
      #
      # @param call_tree [CallTree] The call tree to format
      # @param options [Hash] Formatting options
      # @option options [Boolean] :show_errors (true) Include error information
      # @option options [Boolean] :colorize (true) Apply colors to output
      # @return [String] Formatted tree visualization
      # rubocop:disable Metrics/AbcSize
      def format(call_tree, options = {})
        opts = default_options.merge(options)
        root_calls = call_tree.call_hierarchy

        return "No method calls recorded.\n" if root_calls.empty?

        output = []
        output << header
        output << separator

        root_calls.each_with_index do |call, index|
          is_last_root = index == root_calls.size - 1
          output << format_call_node(call, "", is_last_root, opts)
          output << "" unless is_last_root # Blank line between root calls
        end

        output << separator
        output << format_statistics(call_tree.statistics, opts)

        output.join("\n")
      end
      # rubocop:enable Metrics/AbcSize

      private

      def default_options
        {
          show_errors: true,
          colorize: true
        }
      end

      def header
        "METHOD CALL TREE"
      end

      def separator
        "=" * 60
      end

      # Recursively format a call node and its children
      #
      # @param call [Hash] Call record
      # @param prefix [String] Current line prefix for indentation
      # @param is_last [Boolean] Whether this is the last sibling
      # @param opts [Hash] Formatting options
      # @return [String] Formatted call tree section
      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
      def format_call_node(call, prefix, is_last, opts)
        lines = []

        # Format the current call
        lines << format_call_line(call, prefix, is_last, opts)

        # Format error details if present
        if call[:status] == :error && call[:error] && opts[:show_errors]
          error_prefix = prefix + (is_last ? "    " : "│   ")
          lines << format_error_line(call[:error], error_prefix, opts)
        end

        # Format children
        unless call[:children].empty?
          child_prefix = prefix + (is_last ? "    " : "│   ")
          call[:children].each_with_index do |child, index|
            is_last_child = index == call[:children].size - 1
            lines << format_call_node(child, child_prefix, is_last_child, opts)
          end
        end

        lines.join("\n")
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity

      # Format a single call line
      #
      # @param call [Hash] Call record
      # @param prefix [String] Current line prefix
      # @param is_last [Boolean] Whether this is the last sibling
      # @param opts [Hash] Formatting options
      # @return [String] Formatted call line
      def format_call_line(call, prefix, is_last, opts)
        connector = is_last ? "└── " : "├── "
        tree_part = prefix + connector

        method_name = call[:method_name]
        time_str = format_time(call[:execution_time])
        status_indicator = call[:status] == :error ? " [ERROR]" : ""

        if opts[:colorize]
          method_name = colorize(method_name, :cyan)
          time_str = colorize("(#{time_str})", :yellow)
          status_indicator = colorize(status_indicator, :red) unless status_indicator.empty?
        else
          time_str = "(#{time_str})"
        end

        "#{tree_part}#{method_name} #{time_str}#{status_indicator}"
      end

      # Format error information
      #
      # @param error [Exception] The error object
      # @param prefix [String] Current line prefix
      # @param opts [Hash] Formatting options
      # @return [String] Formatted error line
      def format_error_line(error, prefix, opts)
        error_msg = "└─ Error: #{error.class}: #{error.message}"
        error_msg = colorize(error_msg, :red) if opts[:colorize]
        "#{prefix}#{error_msg}"
      end

      # Format statistics summary
      #
      # @param stats [Hash] Statistics hash from CallTree
      # @param opts [Hash] Formatting options
      # @return [String] Formatted statistics
      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      def format_statistics(stats, _opts)
        lines = []
        lines << "\nSTATISTICS"
        lines << ("-" * 60)

        lines << "Total Calls: #{stats[:total_calls]}"
        lines << "Total Time: #{format_time(stats[:total_time])}"
        lines << "Unique Methods: #{stats[:unique_methods]}"
        lines << "Max Depth: #{stats[:max_depth]}"

        unless stats[:slowest_methods].empty?
          lines << "\nSlowest Methods (by average time):"
          stats[:slowest_methods].take(5).each_with_index do |method, index|
            time_str = format_time(method[:avg_time])
            lines << "  #{index + 1}. #{method[:method]} - #{time_str}"
          end
        end

        unless stats[:most_called_methods].empty?
          lines << "\nMost Called Methods:"
          stats[:most_called_methods].take(5).each_with_index do |method, index|
            lines << "  #{index + 1}. #{method[:method]} - #{method[:count]} calls"
          end
        end

        lines.join("\n")
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
    end
  end
end
