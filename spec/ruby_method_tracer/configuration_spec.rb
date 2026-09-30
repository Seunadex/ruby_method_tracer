# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyMethodTracer::Configuration do
  let(:target_class) do
    Class.new do
      def work
        :done
      end
    end
  end

  describe "defaults" do
    it "provides built-in defaults" do
      config = described_class.new
      expect(config.threshold).to eq(0.001)
      expect(config.auto_output).to be(false)
      expect(config.max_calls).to eq(1000)
      expect(config.logger).to be_nil
      expect(config.track_hierarchy).to be(true)
    end
  end

  describe "#to_h" do
    it "returns the option keys consumed by tracers" do
      config = described_class.new
      expect(config.to_h.keys).to contain_exactly(
        :threshold, :auto_output, :max_calls, :logger, :track_hierarchy
      )
    end
  end

  describe "#reset!" do
    it "restores defaults after mutation" do
      config = described_class.new
      config.threshold = 5.0
      config.reset!
      expect(config.threshold).to eq(0.001)
    end
  end

  describe "RubyMethodTracer.configure" do
    it "yields the global configuration" do
      RubyMethodTracer.configure do |config|
        config.threshold = 0.25
        config.max_calls = 42
      end

      expect(RubyMethodTracer.configuration.threshold).to eq(0.25)
      expect(RubyMethodTracer.configuration.max_calls).to eq(42)
    end

    it "is used as defaults by newly created tracers" do
      RubyMethodTracer.configure { |c| c.threshold = 9.99 }

      tracer = RubyMethodTracer::SimpleTracer.new(target_class)
      tracer.trace_method(:work)
      target_class.new.work

      # threshold is huge, so nothing is recorded
      expect(tracer.fetch_results[:total_calls]).to eq(0)
    end

    it "lets per-tracer options override globals" do
      RubyMethodTracer.configure { |c| c.threshold = 9.99 }

      tracer = RubyMethodTracer::SimpleTracer.new(target_class, threshold: 0.0)
      tracer.trace_method(:work)
      target_class.new.work

      expect(tracer.fetch_results[:total_calls]).to eq(1)
    end

    it "does not deadlock when called from inside another configure block" do
      expect do
        RubyMethodTracer.configure do |outer|
          outer.threshold = 0.1
          RubyMethodTracer.configure { |inner| inner.max_calls = 7 }
        end
      end.not_to raise_error

      expect(RubyMethodTracer.configuration.max_calls).to eq(7)
    end

    it "can be reset back to defaults" do
      RubyMethodTracer.configure { |c| c.threshold = 9.99 }
      RubyMethodTracer.reset_configuration!
      expect(RubyMethodTracer.configuration.threshold).to eq(0.001)
    end
  end
end
