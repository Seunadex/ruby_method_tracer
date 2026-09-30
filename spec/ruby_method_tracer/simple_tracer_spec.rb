# frozen_string_literal: true

require "spec_helper"
require "stringio"

# Named so the tracer has a real constant to render for class-method traces.
class SingletonTarget
  def self.generate(num) = num * 2
end

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

  # The generated wrapper reads the monotonic clock inline rather than through
  # the tracer, so a deterministic duration has to be stubbed at the source.
  # Other clock ids (the wall-clock timestamp) keep their real values.
  def stub_duration(seconds)
    real = Process.method(:clock_gettime)
    values = [1.0, 1.0 + seconds]
    allow(Process).to receive(:clock_gettime) do |clock_id, *rest|
      clock_id == Process::CLOCK_MONOTONIC ? (values.shift || (1.0 + seconds)) : real.call(clock_id, *rest)
    end
  end

  describe "tracing behavior" do
    it "records successful calls above threshold" do
      tracer = described_class.new(target_class, threshold: 0.0)
      tracer.trace_method(:multiply)

      stub_duration(0.005)

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

      stub_duration(0.002)

      instance.multiply(3)
      results = tracer.fetch_results
      expect(results[:total_calls]).to eq(0)
    end

    it "records errors with status and error object" do
      tracer = described_class.new(target_class, threshold: 0.0)
      tracer.trace_method(:will_fail)

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

      instance.multiply(2)
      results = tracer.fetch_results
      expect(results[:total_calls]).to eq(1)
    end

    it "skips nested tracing within the same thread" do
      tracer = described_class.new(target_class, threshold: 0.0)
      tracer.trace_method(:add)
      tracer.trace_method(:calls_other)

      # Only the outer call should be recorded because the tracer guards with a thread flag
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

      stub_duration(0.005)

      instance.multiply(5)

      log = out.string
      expect(log).to include("TRACE:")
      expect(log).to include("#{target_class}#multiply")
      expect(log).to match(
        /\AI, \[\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+ #\d+\]  INFO -- : TRACE: #{Regexp.escape("#{target_class}#multiply")} \[OK\] took 5\.0ms\n\z/ # rubocop:disable Layout/LineLength
      )
    end
  end

  describe "guarding against double wrapping" do
    it "refuses to wrap a method a second tracer already wrapped" do
      first = described_class.new(target_class, threshold: 0.0)
      second = described_class.new(target_class, threshold: 0.0, logger: Logger.new(StringIO.new))
      first.trace_method(:multiply)

      expect(second.trace_method(:multiply)).to be false
      expect(instance.multiply(2)).to eq(4)
    end

    it "warns when the method is already traced" do
      out = StringIO.new
      described_class.new(target_class, threshold: 0.0).trace_method(:multiply)
      described_class.new(target_class, threshold: 0.0, logger: Logger.new(out)).trace_method(:multiply)

      expect(out.string).to include("already traced")
    end

    it "keeps a method callable after repeated tracing attempts" do
      3.times do
        described_class.new(target_class, threshold: 0.0, logger: Logger.new(StringIO.new)).trace_method(:multiply)
      end

      expect(instance.multiply(3)).to eq(6)
    end
  end

  describe "unknown methods" do
    it "reports false and warns instead of failing silently" do
      out = StringIO.new
      tracer = described_class.new(target_class, threshold: 0.0, logger: Logger.new(out))

      expect(tracer.trace_method(:does_not_exist)).to be false
      expect(out.string).to include("has no method #does_not_exist")
    end
  end

  describe "#untrace_method" do
    it "restores the original implementation and visibility" do
      tracer = described_class.new(target_class, threshold: 0.0)
      tracer.trace_method(:multiply)
      tracer.trace_method(:priv)

      expect(tracer.untrace_method(:multiply)).to be true
      expect(instance.multiply(2)).to eq(4)
      expect(tracer.untrace_all).to eq([:priv])
      expect(target_class.private_method_defined?(:priv)).to be true
    end

    it "stops recording and removes the alias" do
      tracer = described_class.new(target_class, threshold: 0.0)
      tracer.trace_method(:multiply)
      tracer.untrace_method(:multiply)
      instance.multiply(2)

      expect(tracer.fetch_results[:total_calls]).to eq(0)
      expect(target_class.private_method_defined?(:__ruby_method_tracer_original_multiply__)).to be false
    end

    it "returns false for a method it did not trace" do
      expect(described_class.new(target_class).untrace_method(:multiply)).to be false
    end
  end

  describe "alias visibility" do
    it "keeps the saved original out of the public API" do
      described_class.new(target_class, threshold: 0.0).trace_method(:multiply)

      expect(instance.methods.grep(/ruby_method_tracer/)).to be_empty
      expect(target_class.private_method_defined?(:__ruby_method_tracer_original_multiply__)).to be true
    end
  end

  describe "non-local exits" do
    it "records a throw as :incomplete rather than losing the call" do
      klass = Class.new { def jump = throw(:done, 42) }
      tracer = described_class.new(klass, threshold: 0.0)
      tracer.trace_method(:jump)

      expect(catch(:done) { klass.new.jump }).to eq(42)
      expect(tracer.fetch_results[:calls].map { |c| c[:status] }).to eq([:incomplete])
    end
  end

  describe "class methods" do
    it "traces singleton methods and names them as they are called" do
      tracer = described_class.new(SingletonTarget.singleton_class, threshold: 0.0)
      tracer.trace_method(:generate)

      expect(SingletonTarget.generate(3)).to eq(6)
      expect(tracer.fetch_results[:calls].first[:method_name]).to eq("SingletonTarget.generate")
    end
  end

  describe "memory management" do
    it "enforces max_calls limit by removing oldest entries" do
      tracer = described_class.new(target_class, threshold: 0.0, max_calls: 3)
      tracer.trace_method(:multiply)

      5.times { |i| instance.multiply(i) }

      results = tracer.fetch_results
      expect(results[:total_calls]).to eq(3) # Should only keep last 3 calls
      expect(results[:calls].size).to eq(3)
    end

    it "clears all results when clear_results is called" do
      tracer = described_class.new(target_class, threshold: 0.0)
      tracer.trace_method(:multiply)

      stub_duration(0.005)
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
      stub_duration(0.005)

      instance.multiply(5)

      expect(custom_logger).to have_received(:info).with(/TRACE:/)
    end

    it "uses default logger when none provided" do
      out = StringIO.new
      allow(Logger).to(receive(:new).and_wrap_original { |orig, *_args| orig.call(out) })

      tracer = described_class.new(target_class, threshold: 0.0, auto_output: true)
      tracer.trace_method(:multiply)
      allow(tracer).to receive(:colorize) { |text, _color| text }
      stub_duration(0.005)

      instance.multiply(5)

      expect(out.string).to include("TRACE:")
    end
  end
end
