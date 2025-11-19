# frozen_string_literal: true

require_relative "ruby_method_tracer/version"
require_relative "ruby_method_tracer/simple_tracer"
require_relative "ruby_method_tracer/call_tree"
require_relative "ruby_method_tracer/enhanced_tracer"
require_relative "ruby_method_tracer/formatters/base_formatter"
require_relative "ruby_method_tracer/formatters/tree_formatter"

# Public: Mixin that adds lightweight method tracing to classes.
#
# When included, this module extends the host class with a class-level
# API (`trace_methods`) that wraps selected instance methods using
# `RubyMethodTracer::SimpleTracer`. Wrapped methods record execution timing and
# errors with minimal overhead, suitable for ad-hoc performance debugging
# in development or selective tracing in production.
#
# Example
#   class Worker
#     include RubyMethodTracer
#     def perform; do_work; end
#   end
#   Worker.trace_methods(:perform, threshold: 0.005, auto_output: true)
#
# See `RubyMethodTracer::SimpleTracer` for available options.
module RubyMethodTracer
  class Error < StandardError; end

  def self.included(base)
    base.extend(ClassMethods)
  end

  # Class-level API mixed into including classes.
  #
  # Provides `trace_methods`, which wraps the specified instance methods on the
  # target class using `RubyMethodTracer::SimpleTracer`. Each wrapped method records
  # execution metrics (duration, status, errors) with minimal intrusion.
  #
  # Usage:
  #   class MyService
  #     include RubyMethodTracer
  #     def call; expensive_work; end
  #   end
  #   MyService.trace_methods(:call, threshold: 0.005, auto_output: true)
  module ClassMethods
    def trace_methods(*method_names, **options)
      tracer = SimpleTracer.new(self, **options)
      method_names.each do |method_name|
        tracer.trace_method(method_name)
      end
    end
  end
end
