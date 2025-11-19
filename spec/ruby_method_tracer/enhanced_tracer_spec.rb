# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyMethodTracer::EnhancedTracer do
  let(:target_class) do
    Class.new do
      def parent_method
        child_method
      end

      def child_method
        grandchild_method
      end

      def grandchild_method
        sleep(0.001)
        "result"
      end

      def sibling1
        sleep(0.001)
        "sibling1"
      end

      def sibling2
        sleep(0.001)
        "sibling2"
      end

      def parent_with_siblings
        sibling1
        sibling2
      end

      def failing_method
        raise StandardError, "test error"
      end

      def error_handler
        failing_method
      rescue StandardError
        "handled"
      end
    end
  end

  let(:tracer) { described_class.new(target_class, threshold: 0.0) }
  let(:instance) { target_class.new }

  describe "call tree tracking" do
    it "tracks nested method calls" do
      tracer.trace_method(:parent_method)
      tracer.trace_method(:child_method)
      tracer.trace_method(:grandchild_method)

      instance.parent_method

      hierarchy = tracer.call_tree.call_hierarchy
      expect(hierarchy.size).to eq(1)

      parent = hierarchy[0]
      expect(parent[:method_name]).to include("parent_method")
      expect(parent[:children].size).to eq(1)

      child = parent[:children][0]
      expect(child[:method_name]).to include("child_method")
      expect(child[:children].size).to eq(1)

      grandchild = child[:children][0]
      expect(grandchild[:method_name]).to include("grandchild_method")
    end

    it "tracks multiple children" do
      tracer.trace_method(:parent_with_siblings)
      tracer.trace_method(:sibling1)
      tracer.trace_method(:sibling2)

      instance.parent_with_siblings

      hierarchy = tracer.call_tree.call_hierarchy
      parent = hierarchy[0]

      expect(parent[:children].size).to eq(2)
      expect(parent[:children][0][:method_name]).to include("sibling1")
      expect(parent[:children][1][:method_name]).to include("sibling2")
    end

    it "records execution times in hierarchy" do
      tracer.trace_method(:parent_method)
      tracer.trace_method(:child_method)
      tracer.trace_method(:grandchild_method)

      instance.parent_method

      hierarchy = tracer.call_tree.call_hierarchy
      parent = hierarchy[0]

      expect(parent[:execution_time]).to be > 0
      expect(parent[:children][0][:execution_time]).to be > 0
    end

    it "records errors in call tree" do
      tracer.trace_method(:error_handler)
      tracer.trace_method(:failing_method)

      result = instance.error_handler
      expect(result).to eq("handled")

      hierarchy = tracer.call_tree.call_hierarchy
      parent = hierarchy[0]
      child = parent[:children][0]

      expect(child[:status]).to eq(:error)
      expect(child[:error]).to be_a(StandardError)
    end
  end

  describe "#print_tree" do
    it "outputs formatted call tree" do
      tracer.trace_method(:parent_method)
      tracer.trace_method(:child_method)
      tracer.trace_method(:grandchild_method)

      instance.parent_method

      output = capture_stdout { tracer.print_tree(colorize: false) }

      expect(output).to include("METHOD CALL TREE")
      expect(output).to include("parent_method")
      expect(output).to include("child_method")
      expect(output).to include("grandchild_method")
      expect(output).to include("└──")
    end
  end

  describe "#format_tree" do
    it "returns formatted string without printing" do
      tracer.trace_method(:parent_method)
      tracer.trace_method(:child_method)

      instance.parent_method

      result = tracer.format_tree(colorize: false)

      expect(result).to be_a(String)
      expect(result).to include("parent_method")
      expect(result).to include("child_method")
    end
  end

  describe "#fetch_enhanced_results" do
    it "returns both flat and hierarchical results" do
      tracer.trace_method(:parent_method)
      tracer.trace_method(:child_method)

      instance.parent_method

      results = tracer.fetch_enhanced_results

      expect(results).to have_key(:flat_calls)
      expect(results).to have_key(:call_hierarchy)
      expect(results).to have_key(:statistics)

      expect(results[:flat_calls][:total_calls]).to eq(2)
      expect(results[:call_hierarchy].size).to eq(1)
      expect(results[:statistics][:total_calls]).to eq(2)
    end
  end

  describe "#clear_results" do
    it "clears both simple tracer and call tree" do
      tracer.trace_method(:parent_method)
      instance.parent_method

      expect(tracer.fetch_results[:total_calls]).to be > 0
      expect(tracer.call_tree.calls).not_to be_empty

      tracer.clear_results

      expect(tracer.fetch_results[:total_calls]).to eq(0)
      expect(tracer.call_tree.calls).to be_empty
    end
  end

  describe "backward compatibility with SimpleTracer" do
    it "supports all SimpleTracer features" do
      tracer.trace_method(:grandchild_method)

      instance.grandchild_method

      results = tracer.fetch_results
      expect(results[:total_calls]).to eq(1)
      expect(results[:calls].first[:status]).to eq(:success)
    end
  end

  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end
end
