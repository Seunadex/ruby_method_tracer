# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyMethodTracer::CallTree do
  let(:call_tree) { described_class.new }

  describe "#start_call and #end_call" do
    it "records a simple method call" do
      call_tree.start_call("TestClass#method1")
      call_tree.end_call(:success)

      expect(call_tree.calls.size).to eq(1)
      expect(call_tree.calls.first[:method_name]).to eq("TestClass#method1")
      expect(call_tree.calls.first[:status]).to eq(:success)
    end

    it "tracks call depth correctly" do
      call_tree.start_call("TestClass#level1")
      expect(call_tree.current_depth).to eq(1)

      call_tree.start_call("TestClass#level2")
      expect(call_tree.current_depth).to eq(2)

      call_tree.end_call(:success)
      expect(call_tree.current_depth).to eq(1)

      call_tree.end_call(:success)
      expect(call_tree.current_depth).to eq(0)
    end

    it "records execution time" do
      call_tree.start_call("TestClass#method1")
      sleep(0.01)
      call_tree.end_call(:success)

      expect(call_tree.calls.first[:execution_time]).to be >= 0.01
    end

    it "records errors" do
      error = StandardError.new("test error")
      call_tree.start_call("TestClass#failing_method")
      call_tree.end_call(:error, error)

      call = call_tree.calls.first
      expect(call[:status]).to eq(:error)
      expect(call[:error]).to eq(error)
    end
  end

  describe "#call_hierarchy" do
    it "builds hierarchy for nested calls" do
      call_tree.start_call("Parent#method")
      call_tree.start_call("Child#method")
      call_tree.end_call(:success)
      call_tree.end_call(:success)

      hierarchy = call_tree.call_hierarchy
      expect(hierarchy.size).to eq(1)
      expect(hierarchy[0][:method_name]).to eq("Parent#method")
      expect(hierarchy[0][:children].size).to eq(1)
      expect(hierarchy[0][:children][0][:method_name]).to eq("Child#method")
    end

    it "handles multiple root calls" do
      call_tree.start_call("Root1#method")
      call_tree.end_call(:success)

      call_tree.start_call("Root2#method")
      call_tree.end_call(:success)

      hierarchy = call_tree.call_hierarchy
      expect(hierarchy.size).to eq(2)
      expect(hierarchy[0][:method_name]).to eq("Root1#method")
      expect(hierarchy[1][:method_name]).to eq("Root2#method")
    end

    # rubocop:disable RSpec/ExampleLength
    it "handles multiple children" do
      call_tree.start_call("Parent#method")
      call_tree.start_call("Child1#method")
      call_tree.end_call(:success)
      call_tree.start_call("Child2#method")
      call_tree.end_call(:success)
      call_tree.start_call("Child3#method")
      call_tree.end_call(:success)
      call_tree.end_call(:success)

      hierarchy = call_tree.call_hierarchy
      parent = hierarchy[0]
      expect(parent[:children].size).to eq(3)
      expect(parent[:children].map { |c| c[:method_name] }).to eq([
                                                                    "Child1#method",
                                                                    "Child2#method",
                                                                    "Child3#method"
                                                                  ])
    end
    # rubocop:enable RSpec/ExampleLength

    # rubocop:disable RSpec/ExampleLength
    it "handles deep nesting" do
      call_tree.start_call("Level1#method")
      call_tree.start_call("Level2#method")
      call_tree.start_call("Level3#method")
      call_tree.start_call("Level4#method")
      call_tree.end_call(:success)
      call_tree.end_call(:success)
      call_tree.end_call(:success)
      call_tree.end_call(:success)

      hierarchy = call_tree.call_hierarchy
      level1 = hierarchy[0]
      level2 = level1[:children][0]
      level3 = level2[:children][0]
      level4 = level3[:children][0]

      expect(level1[:depth]).to eq(0)
      expect(level2[:depth]).to eq(1)
      expect(level3[:depth]).to eq(2)
      expect(level4[:depth]).to eq(3)
    end
    # rubocop:enable RSpec/ExampleLength
  end

  describe "#statistics" do
    it "returns default statistics when empty" do
      stats = call_tree.statistics
      expect(stats[:total_calls]).to eq(0)
      expect(stats[:total_time]).to eq(0.0)
      expect(stats[:unique_methods]).to eq(0)
    end

    it "calculates total calls and time" do
      3.times do |i|
        call_tree.start_call("TestClass#method#{i}")
        sleep(0.001)
        call_tree.end_call(:success)
      end

      stats = call_tree.statistics
      expect(stats[:total_calls]).to eq(3)
      expect(stats[:total_time]).to be >= 0.003
      expect(stats[:unique_methods]).to eq(3)
    end

    it "identifies slowest methods" do
      # Fast method
      call_tree.start_call("FastMethod#call")
      sleep(0.001)
      call_tree.end_call(:success)

      # Slow method
      call_tree.start_call("SlowMethod#call")
      sleep(0.01)
      call_tree.end_call(:success)

      stats = call_tree.statistics
      slowest = stats[:slowest_methods]
      expect(slowest.first[:method]).to eq("SlowMethod#call")
    end

    it "identifies most called methods" do
      5.times do
        call_tree.start_call("Frequent#call")
        call_tree.end_call(:success)
      end
      2.times do
        call_tree.start_call("Rare#call")
        call_tree.end_call(:success)
      end

      stats = call_tree.statistics
      most_called = stats[:most_called_methods]
      expect(most_called.first[:method]).to eq("Frequent#call")
      expect(most_called.first[:count]).to eq(5)
    end

    it "calculates max depth" do
      call_tree.start_call("Level1#method")
      call_tree.start_call("Level2#method")
      call_tree.start_call("Level3#method")
      call_tree.end_call(:success)
      call_tree.end_call(:success)
      call_tree.end_call(:success)

      stats = call_tree.statistics
      expect(stats[:max_depth]).to eq(2) # 0-indexed: 0, 1, 2
    end
  end

  describe "#clear" do
    it "clears all recorded calls" do
      call_tree.start_call("TestClass#method")
      call_tree.end_call(:success)

      expect(call_tree.calls).not_to be_empty
      call_tree.clear
      expect(call_tree.calls).to be_empty
      expect(call_tree.empty?).to be true
    end
  end

  describe "thread safety" do
    it "handles concurrent access" do
      threads = 10.times.map do |i|
        Thread.new do
          call_tree.start_call("Thread#{i}#method")
          sleep(0.001)
          call_tree.end_call(:success)
        end
      end

      threads.each(&:join)
      expect(call_tree.calls.size).to eq(10)
    end
  end
end
