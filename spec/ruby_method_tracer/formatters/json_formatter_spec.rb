# frozen_string_literal: true

require "spec_helper"
require "json"

RSpec.describe RubyMethodTracer::Formatters::JsonFormatter do
  let(:formatter) { described_class.new }

  describe "#format with a flat results hash" do
    let(:results) do
      {
        total_calls: 1,
        total_time: 0.005,
        calls: [
          {
            method_name: "Foo#bar",
            execution_time: 0.005,
            status: :success,
            error: nil,
            timestamp: Time.utc(2026, 1, 2, 3, 4, 5)
          }
        ]
      }
    end

    it "produces valid JSON that round-trips" do
      parsed = JSON.parse(formatter.format(results))
      expect(parsed["total_calls"]).to eq(1)
      expect(parsed["calls"].first["method_name"]).to eq("Foo#bar")
      expect(parsed["calls"].first["status"]).to eq("success")
    end

    it "serializes timestamps as ISO8601" do
      parsed = JSON.parse(formatter.format(results))
      expect(parsed["calls"].first["timestamp"]).to start_with("2026-01-02T03:04:05")
    end

    it "supports pretty output" do
      expect(formatter.format(results, pretty: true)).to include("\n")
    end
  end

  describe "error serialization" do
    let(:error) do
      RuntimeError.new("boom").tap { |e| e.set_backtrace(%w[a.rb:1 b.rb:2 c.rb:3]) }
    end
    let(:results) do
      {
        calls: [{ method_name: "Foo#x", execution_time: 0.1, status: :error, error: error, timestamp: Time.now }]
      }
    end

    it "reduces exceptions to class and message and omits backtrace by default" do
      parsed = JSON.parse(formatter.format(results))
      err = parsed["calls"].first["error"]
      expect(err["class"]).to eq("RuntimeError")
      expect(err["message"]).to eq("boom")
      expect(err).not_to have_key("backtrace")
    end

    it "includes a bounded backtrace when explicitly requested" do
      parsed = JSON.parse(formatter.format(results, include_backtrace: true, backtrace_limit: 2))
      expect(parsed["calls"].first["error"]["backtrace"]).to eq(%w[a.rb:1 b.rb:2])
    end

    it "emits an empty backtrace when the limit is not positive" do
      parsed = JSON.parse(formatter.format(results, include_backtrace: true, backtrace_limit: 0))
      expect(parsed["calls"].first["error"]["backtrace"]).to eq([])
    end
  end

  describe "defensive input handling" do
    it "treats non-hash input as empty results" do
      parsed = JSON.parse(formatter.format(nil))
      expect(parsed["total_calls"]).to eq(0)
      expect(parsed["calls"]).to eq([])
    end

    it "passes through a non-time timestamp unchanged" do
      results = { calls: [{ method_name: "Foo#x", execution_time: 0.1, status: :success, timestamp: "n/a" }] }
      parsed = JSON.parse(formatter.format(results))
      expect(parsed["calls"].first["timestamp"]).to eq("n/a")
    end
  end

  describe "#format with a CallTree" do
    let(:call_tree) { RubyMethodTracer::CallTree.new }

    before do
      call_tree.start_call("Foo#parent")
      call_tree.start_call("Foo#child")
      call_tree.end_call(:success)
      call_tree.end_call(:success)
    end

    it "serializes the hierarchy and statistics" do
      parsed = JSON.parse(formatter.format(call_tree))
      expect(parsed["call_hierarchy"].size).to eq(1)
      expect(parsed["call_hierarchy"].first["children"].first["method_name"]).to eq("Foo#child")
      expect(parsed["statistics"]["total_calls"]).to eq(2)
    end
  end
end
