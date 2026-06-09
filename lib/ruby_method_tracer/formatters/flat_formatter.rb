# frozen_string_literal: true

require_relative "base_formatter"

module RubyMethodTracer
  module Formatters
    # FlatFormatter renders trace data as a flat, aggregated text table:
    # one row per unique method with call count, total time, average time,
    # and error count, sorted by total time descending.
    #
    # Accepts either a CallTree or a flat results hash from
    # `SimpleTracer#fetch_results`.
    class FlatFormatter < BaseFormatter
      HEADERS = %w[Method Calls Total Avg Errors].freeze

      def format(data, options = {})
        opts = default_options.merge(options)
        calls = extract_calls(data)
        return "No method calls recorded.\n" if calls.empty?

        rows = build_rows(calls)
        render(rows, opts)
      end

      private

      def default_options
        { colorize: true }
      end

      def extract_calls(data)
        if data.respond_to?(:call_hierarchy)
          # Read the call tree through its lock-protected accessor, then flatten
          # the hierarchy into a single list of calls.
          data.call_hierarchy.flat_map { |node| flatten_node(node) }
        elsif data.is_a?(Hash)
          data[:calls] || []
        else
          []
        end
      end

      def flatten_node(node)
        [node, *(node[:children] || []).flat_map { |child| flatten_node(child) }]
      end

      def build_rows(calls)
        rows = aggregate(calls).map { |name, agg| build_row(name, agg) }
        rows.sort_by { |row| -row[:total] }
      end

      def build_row(name, agg)
        {
          method: name,
          calls: agg[:count],
          total: agg[:total_time],
          avg: agg[:total_time] / agg[:count],
          errors: agg[:errors]
        }
      end

      def aggregate(calls)
        stats = Hash.new { |h, k| h[k] = { count: 0, total_time: 0.0, errors: 0 } }
        calls.each do |call|
          agg = stats[call[:method_name]]
          agg[:count] += 1
          agg[:total_time] += call[:execution_time].to_f
          agg[:errors] += 1 if call[:status] == :error
        end
        stats
      end

      def render(rows, opts)
        cell_rows = rows.map { |row| cells_for(row) }
        widths = column_widths(cell_rows)
        lines = [align(HEADERS, widths), separator(widths)]
        rows.zip(cell_rows).each { |row, cells| lines << data_line(row, cells, widths, opts) }
        "#{lines.join("\n")}\n"
      end

      # Plain (uncolored) cell strings, used for both width calc and rendering.
      def cells_for(row)
        [row[:method], row[:calls].to_s, format_time(row[:total]), format_time(row[:avg]), row[:errors].to_s]
      end

      def column_widths(cell_rows)
        HEADERS.each_index.map do |i|
          (cell_rows.map { |cells| cells[i].length } + [HEADERS[i].length]).max
        end
      end

      def align(cells, widths)
        cells.each_index.map { |i| pad(cells[i], widths[i], i.zero?) }.join("  ")
      end

      # Justify a plain cell, then wrap it in color so ANSI codes never affect
      # the computed column width.
      def data_line(row, cells, widths, opts)
        cells.each_index.map { |i| color_cell(pad(cells[i], widths[i], i.zero?), i, row, opts) }.join("  ")
      end

      def pad(text, width, left)
        left ? text.ljust(width) : text.rjust(width)
      end

      def color_cell(padded, index, row, opts)
        return padded unless opts[:colorize]
        return colorize(padded, :cyan) if index.zero?
        return colorize(padded, :red) if index == 4 && row[:errors].positive?

        padded
      end

      def separator(widths)
        widths.map { |w| "-" * w }.join("  ")
      end
    end
  end
end
