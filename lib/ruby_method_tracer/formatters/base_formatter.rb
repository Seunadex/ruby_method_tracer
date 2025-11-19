# frozen_string_literal: true

module RubyMethodTracer
  module Formatters
    # Base class for formatting trace output
    class BaseFormatter
      # Format timing value into human-readable string
      #
      # @param seconds [Float] Time in seconds
      # @return [String] Formatted time string
      def format_time(seconds)
        if seconds >= 1.0
          "#{seconds.round(3)}s"
        elsif seconds >= 0.001
          "#{(seconds * 1000).round(1)}ms"
        else
          "#{(seconds * 1_000_000).round(0)}µs"
        end
      end

      # Apply color to text using ANSI escape codes
      #
      # @param text [String] Text to colorize
      # @param color [Symbol] Color name
      # @return [String] Colorized text
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

      # Abstract method to be implemented by subclasses
      #
      # @param _data [Object] Data to format
      # @raise [NotImplementedError] Must be implemented by subclass
      def format(_data)
        raise NotImplementedError, "#{self.class} must implement #format"
      end
    end
  end
end
