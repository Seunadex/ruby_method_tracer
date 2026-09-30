# frozen_string_literal: true

class MixinTarget
  include RubyMethodTracer

  def work(num)
    num * 2
  end

  def other
    :other
  end

  def self.build
    :built
  end
end

class TestClass
  include RubyMethodTracer

  def greet(name)
    "Hello, #{name}!"
  end

  def fail_method
    raise "Intentional failure"
  end
end

RSpec.describe RubyMethodTracer do
  it "has a version number" do
    expect(RubyMethodTracer::VERSION).not_to be_nil
  end

  it "traces a simple block and outputs JSON" do
    TestClass.trace_methods(:greet, :fail_method, threshold: 0.0, auto_output: true)

    instance = TestClass.new
    expect(instance.greet("World")).to eq("Hello, World!")

    expect { instance.fail_method }.to raise_error(RuntimeError, "Intentional failure")
  end

  describe ".trace_methods" do
    it "returns the tracer so results can be read back" do
      tracer = MixinTarget.trace_methods(:work, threshold: 0.0)

      expect(MixinTarget.new.work(2)).to eq(4)
      expect(tracer).to be_a(RubyMethodTracer::SimpleTracer)
      expect(tracer.fetch_results[:total_calls]).to eq(1)
    end

    it "reuses one tracer per class instead of wrapping twice" do
      first = MixinTarget.trace_methods(:work, threshold: 0.0)
      second = MixinTarget.trace_methods(:other)

      expect(second).to be(first)
      expect(MixinTarget.new.work(2)).to eq(4)
    end
  end

  describe ".trace_class_methods" do
    it "traces singleton methods through the mixin" do
      tracer = MixinTarget.trace_class_methods(:build, threshold: 0.0)

      expect(MixinTarget.build).to be(:built)
      expect(tracer.fetch_results[:calls].first[:method_name]).to eq("MixinTarget.build")
    end
  end
end
