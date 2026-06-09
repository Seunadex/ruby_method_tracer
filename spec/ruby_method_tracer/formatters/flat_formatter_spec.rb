# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyMethodTracer::Formatters::FlatFormatter do
  let(:formatter) { described_class.new }

  let(:results) do
    {
      calls: [
        { method_name: "Foo#slow", execution_time: 0.100, status: :success },
        { method_name: "Foo#slow", execution_time: 0.200, status: :success },
        { method_name: "Foo#fast", execution_time: 0.001, status: :error }
      ]
    }
  end

  describe "#format" do
    it "returns a message when there are no calls" do
      expect(formatter.format({ calls: [] })).to eq("No method calls recorded.\n")
    end

    it "renders a header row" do
      output = formatter.format(results, colorize: false)
      expect(output).to include("Method")
      expect(output).to include("Calls")
      expect(output).to include("Errors")
    end

    it "aggregates calls per method and sorts by total time descending" do
      output = formatter.format(results, colorize: false)
      lines = output.lines
      expect(lines[2]).to include("Foo#slow") # slow has the highest total time
      expect(lines[3]).to include("Foo#fast")
    end

    it "counts errors per method" do
      output = formatter.format(results, colorize: false)
      fast_line = output.lines.find { |l| l.include?("Foo#fast") }
      expect(fast_line).to match(/\b1\b/)
    end

    it "omits ANSI codes when colorize is disabled" do
      expect(formatter.format(results, colorize: false)).not_to include("\e[")
    end

    it "applies color by default" do
      expect(formatter.format(results)).to include("\e[36m")
    end

    it "accepts a CallTree as input" do
      tree = RubyMethodTracer::CallTree.new
      tree.start_call("Foo#bar")
      tree.end_call(:success)
      expect(formatter.format(tree, colorize: false)).to include("Foo#bar")
    end

    it "treats unrecognized input as no calls" do
      expect(formatter.format(nil)).to eq("No method calls recorded.\n")
    end
  end
end
