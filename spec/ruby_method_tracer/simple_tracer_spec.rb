# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyMethodTracer::SimpleTracer do
  let(:target_class) do
    Class.new do
      def multiply(arg)
        arg * 2
      end

      protected

      def add(arg)
        arg + 1
      end

      private

      def priv
        :secret
      end

      public

      def calls_other
        add(1)
      end

      def will_fail
        raise "boom"
      end
    end
  end

  def instance
    target_class.new
  end

  describe "tracing behavior" do
    it "records successful calls above threshold" do
      tracer = described_class.new(target_class, threshold: 0.0)
      tracer.trace_method(:multiply)

      allow(tracer).to receive(:monotonic_time).and_return(1.0, 1.005)

      expect(instance.multiply(3)).to eq(6)

      results = tracer.fetch_results
      expect(results[:total_calls]).to eq(1)
      expect(results[:total_time]).to be_within(1e-6).of(0.005)

      call = results[:calls].first
      expect(call[:method_name]).to eq("#{target_class}#multiply")
      expect(call[:status]).to eq(:success)
      expect(call[:error]).to be_nil
      expect(call[:timestamp]).to be_a(Time)
    end

    it "does not record calls below threshold" do
      tracer = described_class.new(target_class, threshold: 0.010)
      tracer.trace_method(:multiply)

      allow(tracer).to receive(:monotonic_time).and_return(1.0, 1.002)

      instance.multiply(3)
      results = tracer.fetch_results
      expect(results[:total_calls]).to eq(0)
    end

    it "records errors with status and error object" do
      tracer = described_class.new(target_class, threshold: 0.0)
      tracer.trace_method(:will_fail)

      allow(tracer).to receive(:monotonic_time).and_return(1.0, 1.001)

      expect { instance.__send__(:will_fail) }.to raise_error(RuntimeError, "boom")

      results = tracer.fetch_results
      expect(results[:total_calls]).to eq(1)
      call = results[:calls].first
      expect(call[:status]).to eq(:error)
      expect(call[:error]).to be_a(RuntimeError)
      expect(call[:error].message).to eq("boom")
    end

    it "restores original visibility after wrapping" do
      tracer = described_class.new(target_class, threshold: 0.0)
      tracer.trace_method(:multiply)
      tracer.trace_method(:add)
      tracer.trace_method(:priv)

      expect(target_class.method_defined?(:multiply)).to be true
      expect(target_class.protected_method_defined?(:add)).to be true
      expect(target_class.private_method_defined?(:priv)).to be true
    end

    it "does not double-wrap the same method" do
      tracer = described_class.new(target_class, threshold: 0.0)
      tracer.trace_method(:multiply)
      tracer.trace_method(:multiply) # no-op on second call

      allow(tracer).to receive(:monotonic_time).and_return(1.0, 1.003)

      instance.multiply(2)
      results = tracer.fetch_results
      expect(results[:total_calls]).to eq(1)
    end

    it "skips nested tracing within the same thread" do
      tracer = described_class.new(target_class, threshold: 0.0)
      tracer.trace_method(:add)
      tracer.trace_method(:calls_other)

      # Only the outer call should be recorded because the tracer guards with a thread flag
      allow(tracer).to receive(:monotonic_time).and_return(1.0, 1.004)

      expect(instance.calls_other).to eq(2)
      names = tracer.fetch_results[:calls].map { |c| c[:method_name] }
      expect(names).to contain_exactly("#{target_class}#calls_other")
    end

    it "prints output when auto_output is true" do
      out = StringIO.new
      allow(Logger).to(receive(:new).and_wrap_original { |orig, *_args| orig.call(out) })

      tracer = described_class.new(target_class, threshold: 0.0, auto_output: true)
      tracer.trace_method(:multiply)
      allow(tracer).to receive(:colorize) { |text, _color| text }

      allow(tracer).to receive(:monotonic_time).and_return(1.0, 1.005)

      instance.multiply(5)

      log = out.string
      expect(log).to include("TRACE:")
      expect(log).to include("#{target_class}#multiply")
      expect(log).to match(
        /\AI, \[\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+ #\d+\]  INFO -- : TRACE: #{Regexp.escape("#{target_class}#multiply")} \[OK\] took 5\.0ms\n\z/ # rubocop:disable Layout/LineLength
      )
    end
  end

  describe "memory management" do
    it "enforces max_calls limit by removing oldest entries" do
      tracer = described_class.new(target_class, threshold: 0.0, max_calls: 3)
      tracer.trace_method(:multiply)

      # Simulate 5 calls
      5.times do |i|
        allow(tracer).to receive(:monotonic_time).and_return(i.to_f, i.to_f + 0.001)
        instance.multiply(i)
      end

      results = tracer.fetch_results
      expect(results[:total_calls]).to eq(3) # Should only keep last 3 calls
      expect(results[:calls].size).to eq(3)
    end

    it "clears all results when clear_results is called" do
      tracer = described_class.new(target_class, threshold: 0.0)
      tracer.trace_method(:multiply)

      allow(tracer).to receive(:monotonic_time).and_return(1.0, 1.005)
      instance.multiply(3)

      expect(tracer.fetch_results[:total_calls]).to eq(1)

      tracer.clear_results

      expect(tracer.fetch_results[:total_calls]).to eq(0)
      expect(tracer.fetch_results[:calls]).to be_empty
    end
  end

  describe "logger configuration" do
    it "uses custom logger when provided" do
      custom_logger = Logger.new(StringIO.new)
      allow(custom_logger).to receive(:info)
      tracer = described_class.new(target_class, threshold: 0.0, auto_output: true, logger: custom_logger)
      tracer.trace_method(:multiply)

      allow(tracer).to receive(:colorize) { |text, _color| text }
      allow(tracer).to receive(:monotonic_time).and_return(1.0, 1.005)

      instance.multiply(5)

      expect(custom_logger).to have_received(:info).with(/TRACE:/)
    end

    it "uses default logger when none provided" do
      out = StringIO.new
      allow(Logger).to(receive(:new).and_wrap_original { |orig, *_args| orig.call(out) })

      tracer = described_class.new(target_class, threshold: 0.0, auto_output: true)
      tracer.trace_method(:multiply)
      allow(tracer).to receive(:colorize) { |text, _color| text }
      allow(tracer).to receive(:monotonic_time).and_return(1.0, 1.005)

      instance.multiply(5)

      expect(out.string).to include("TRACE:")
    end
  end
end
