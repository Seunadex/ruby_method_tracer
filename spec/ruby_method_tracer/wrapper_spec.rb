# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe RubyMethodTracer::Wrapper do
  let(:silent_logger) { Logger.new(StringIO.new) }

  # Trace `name` on `klass` and hand back the signature before and after, with
  # block parameters stripped: the wrapper always declares one (a method may
  # still `yield`) and block params do not affect arity.
  def signature_change(klass, name)
    before = klass.instance_method(name)
    original = [before.arity, before.parameters.reject { |param| param.first == :block }]
    RubyMethodTracer::SimpleTracer.new(klass, threshold: 0.0, logger: silent_logger).trace_method(name)
    after = klass.instance_method(name)
    [original, [after.arity, after.parameters.reject { |param| param.first == :block }]]
  end

  describe "signature preservation" do
    {
      "no parameters" => -> { Class.new { def m; end } },
      "required" => -> { Class.new { def m(a) = a } },
      "optional" => -> { Class.new { def m(a, b = :d) = [a, b] } },
      "rest" => -> { Class.new { def m(*a) = a } },
      "required after rest" => -> { Class.new { def m(*a, z) = [a, z] } },
      "required keyword" => -> { Class.new { def m(k:) = k } },
      "optional keyword" => -> { Class.new { def m(k: :d) = k } },
      "keyword rest" => -> { Class.new { def m(**o) = o } },
      "no keywords" => -> { Class.new { def m(a, **nil) = a } },
      "block" => -> { Class.new { def m(&b) = b&.call } },
      "every form at once" => lambda {
        Class.new { def m(a, b = :d, *r, z, k1:, k2: :d2, **o, &bl) = [a, b, r, z, k1, k2, o, bl] }
      }
    }.each do |label, build|
      it "keeps arity and parameters for a method with #{label}" do
        original, wrapped = signature_change(build.call, :m)
        expect(wrapped).to eq(original)
      end
    end

    it "keeps the signature of operator methods" do
      original, wrapped = signature_change(Class.new { def ==(other) = equal?(other) }, :==)
      expect(wrapped).to eq(original)
    end

    it "keeps arity for anonymous parameters, naming them so they can be forwarded" do
      klass = Class.new { def m(*) = :anon }
      original, wrapped = signature_change(klass, :m)
      expect(wrapped.first).to eq(original.first)
      expect(wrapped.last.map(&:first)).to eq([:rest])
    end
  end

  describe "call semantics" do
    it "lets the original apply its own positional default" do
      klass = Class.new { def m(a, b = :dflt) = [a, b] }
      signature_change(klass, :m)
      expect([klass.new.m(1), klass.new.m(1, 2)]).to eq([[1, :dflt], [1, 2]])
    end

    it "lets the original apply its own keyword default" do
      klass = Class.new { def m(k: :dflt) = k }
      signature_change(klass, :m)
      expect([klass.new.m, klass.new.m(k: 9)]).to eq([:dflt, 9])
    end

    it "forwards a block to a method that yields without declaring one" do
      klass = Class.new { def m = yield }
      signature_change(klass, :m)
      expect(klass.new.m { :yielded }).to be(:yielded)
    end

    it "forwards arguments that arrive through ..." do
      klass = Class.new do
        def inner(a, k: 1) = [a, k]
        def m(...) = inner(...)
      end
      signature_change(klass, :m)
      expect(klass.new.m(1, k: 5)).to eq([1, 5])
    end

    it "places required arguments that follow a rest parameter correctly" do
      klass = Class.new { def m(*a, z) = [a, z] }
      signature_change(klass, :m)
      expect(klass.new.m(1, 2, 3)).to eq([[1, 2], 3])
    end

    it "still raises ArgumentError from the call site" do
      klass = Class.new { def m(a) = a }
      signature_change(klass, :m)
      expect { klass.new.m }.to raise_error(ArgumentError, /given 0, expected 1/)
    end
  end

  # The generated wrapper calls the saved original as a bare identifier, which
  # the parser only accepts for plain names. These shapes are the ones where an
  # unsanitised alias would misparse rather than fail loudly, so each case
  # asserts behaviour, not just the signature.
  describe "method names that are not plain identifiers" do
    {
      "predicate" => [-> { Class.new { def ready?(num) = num > 1 } }, :ready?, ->(obj) { obj.ready?(2) }, true],
      "bang" => [-> { Class.new { def save!(num) = "saved #{num}" } }, :save!, ->(obj) { obj.save!(1) }, "saved 1"],
      "setter" => [lambda {
        Class.new do
          def val=(value)
            @val = value * 2
          end

          attr_reader :val
        end
      }, :val=, lambda { |obj|
        obj.val = 5
        obj.val
      }, 10],
      "equality" => [-> { Class.new { def ==(other) = other == 42 } }, :==, ->(obj) { obj == 42 }, true],
      "index" => [-> { Class.new { def [](idx) = idx * 3 } }, :[], ->(obj) { obj[4] }, 12],
      "index assignment" => [lambda {
        Class.new do
          def []=(key, value)
            @pair = [key, value]
          end

          attr_reader :pair
        end
      }, :[]=, lambda { |obj|
        obj[1] = 2
        obj.pair
      }, [1, 2]],
      "spaceship" => [-> { Class.new { def <=>(_other) = 0 } }, :<=>, ->(obj) { obj <=> 1 }, 0],
      "append" => [-> { Class.new { def <<(num) = "got #{num}" } }, :<<, ->(obj) { obj << 9 }, "got 9"],
      "unary minus" => [-> { Class.new { def -@ = :negated } }, :-@, :-@.to_proc, :negated]
    }.each do |label, (build, name, invoke, expected)|
      it "traces a #{label} method without changing what it returns" do
        klass = build.call
        tracer = RubyMethodTracer::SimpleTracer.new(klass, threshold: 0.0, logger: silent_logger)
        tracer.trace_method(name)

        expect(invoke.call(klass.new)).to eq(expected)
        expect(tracer.fetch_results[:total_calls]).to be >= 1
      end
    end

    it "untraces an operator method back to the original" do
      klass = Class.new { def [](idx) = idx * 3 }
      tracer = RubyMethodTracer::SimpleTracer.new(klass, threshold: 0.0, logger: silent_logger)
      tracer.trace_method(:[])

      expect(tracer.untrace_method(:[])).to be true
      expect(klass.new[4]).to eq(12)
      expect(klass.new.methods.grep(/ruby_method_tracer/)).to be_empty
    end
  end

  # Driven through Signature directly with the parameter lists each Ruby
  # reports, so the behaviour is covered on every version rather than only on
  # the one running the suite.
  describe RubyMethodTracer::Wrapper::Signature do
    it "declares a keyword rest for the shape Ruby 3.0 reports for ..." do
      legacy = described_class.new([[:rest, :*], [:block, :&]], repair_forwarding: true)
      modern = described_class.new([[:rest, :*], [:keyrest, :**], [:block, :&]])

      expect(legacy.declaration).to eq(modern.declaration)
      expect(legacy.declaration).to include("**")
    end

    it "leaves a genuine rest-and-block signature alone" do
      signature = described_class.new([[:rest, :args], [:block, :blk]], repair_forwarding: true)

      expect(signature.declaration).to eq("*args, &blk")
    end

    it "does not add keywords to an anonymous rest parameter" do
      signature = described_class.new([[:rest, :*]], repair_forwarding: true)

      expect(signature.declaration).not_to include("**")
    end

    it "does not add keywords on Rubies that describe ... completely" do
      signature = described_class.new([[:rest, :*], [:block, :&]], repair_forwarding: false)

      expect(signature.declaration).not_to include("**")
    end
  end
end
