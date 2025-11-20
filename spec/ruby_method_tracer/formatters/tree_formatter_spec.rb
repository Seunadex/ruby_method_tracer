# frozen_string_literal: true

RSpec.describe RubyMethodTracer::Formatters::TreeFormatter do
  let(:formatter) { described_class.new }
  let(:call_tree) { RubyMethodTracer::CallTree.new }

  describe "#format" do
    context "when call tree is empty" do
      it "returns a message indicating no calls recorded" do
        result = formatter.format(call_tree)
        expect(result).to eq("No method calls recorded.\n")
      end
    end

    context "when call tree has a single method call" do
      before do
        call_tree.start_call("TestClass#method1")
        sleep(0.001)
        call_tree.end_call(:success)
      end

      it "formats the call tree with header and statistics" do
        result = formatter.format(call_tree)
        expect(result).to include("METHOD CALL TREE")
        expect(result).to include("TestClass#method1")
        expect(result).to include("STATISTICS")
        expect(result).to include("Total Calls: 1")
      end

      it "includes colorized output by default" do
        result = formatter.format(call_tree)
        expect(result).to include("\e[36m") # cyan color
        expect(result).to include("\e[33m") # yellow color
      end

      it "can disable colorization" do
        result = formatter.format(call_tree, colorize: false)
        expect(result).not_to include("\e[")
      end
    end

    context "when call tree has nested calls" do
      before do
        call_tree.start_call("TestClass#parent")
        call_tree.start_call("TestClass#child1")
        sleep(0.001)
        call_tree.end_call(:success)
        call_tree.start_call("TestClass#child2")
        sleep(0.001)
        call_tree.end_call(:success)
        call_tree.end_call(:success)
      end

      it "shows hierarchical structure with tree connectors" do
        result = formatter.format(call_tree)
        expect(result).to include("└──") # tree connector
        expect(result).to include("TestClass#parent")
        expect(result).to include("TestClass#child1")
        expect(result).to include("TestClass#child2")
      end

      it "includes depth in statistics" do
        result = formatter.format(call_tree)
        expect(result).to include("Max Depth: 1")
      end
    end

    context "when call tree has multiple root calls" do
      before do
        call_tree.start_call("TestClass#method1")
        sleep(0.001)
        call_tree.end_call(:success)

        call_tree.start_call("TestClass#method2")
        sleep(0.001)
        call_tree.end_call(:success)
      end

      it "formats multiple root calls with proper connectors" do
        result = formatter.format(call_tree)
        expect(result).to include("TestClass#method1")
        expect(result).to include("TestClass#method2")
        # First root uses ├──, last root uses └──
        expect(result).to include("├──")
        expect(result).to include("└──")
      end
    end

    context "when call tree has errors" do
      let(:test_error) { StandardError.new("Test error message") }

      before do
        call_tree.start_call("TestClass#failing_method")
        sleep(0.001)
        call_tree.end_call(:error, test_error)
      end

      it "shows error indicator" do
        result = formatter.format(call_tree)
        expect(result).to include("[ERROR]")
      end

      it "includes error details by default" do
        result = formatter.format(call_tree, show_errors: true)
        expect(result).to include("Error: StandardError: Test error message")
      end

      it "can hide error details" do
        result = formatter.format(call_tree, show_errors: false)
        expect(result).not_to include("Error: StandardError")
      end

      it "colorizes error messages when colorize is enabled" do
        result = formatter.format(call_tree, colorize: true)
        expect(result).to include("\e[31m") # red color for errors
      end

      it "does not colorize error messages when colorize is disabled" do
        result = formatter.format(call_tree, colorize: false)
        expect(result).to include("[ERROR]")
        expect(result).not_to include("\e[31m")
      end
    end

    context "when call tree has deep nesting with errors" do
      let(:test_error) { RuntimeError.new("Deep error") }

      before do
        call_tree.start_call("TestClass#level1")
        call_tree.start_call("TestClass#level2")
        call_tree.start_call("TestClass#level3")
        sleep(0.001)
        call_tree.end_call(:error, test_error)
        call_tree.end_call(:success)
        call_tree.end_call(:success)
      end

      it "shows nested structure with error at the deepest level" do
        result = formatter.format(call_tree)
        expect(result).to include("TestClass#level1")
        expect(result).to include("TestClass#level2")
        expect(result).to include("TestClass#level3")
        expect(result).to include("[ERROR]")
        expect(result).to include("Error: RuntimeError: Deep error")
      end

      it "shows correct indentation for nested calls" do
        result = formatter.format(call_tree)
        # Check for proper nesting structure with multiple levels
        expect(result).to include("└──") # tree connector
        expect(result).to include("TestClass#level1")
        expect(result).to include("TestClass#level2")
        expect(result).to include("TestClass#level3")
      end
    end

    context "when formatting statistics" do
      before do
        # Create multiple calls to same method
        3.times do
          call_tree.start_call("TestClass#repeated_method")
          sleep(0.001)
          call_tree.end_call(:success)
        end

        # Create a slower method
        call_tree.start_call("TestClass#slow_method")
        sleep(0.005)
        call_tree.end_call(:success)
      end

      it "shows slowest methods" do
        result = formatter.format(call_tree)
        expect(result).to include("Slowest Methods (by average time):")
        expect(result).to include("TestClass#slow_method")
      end

      it "shows most called methods" do
        result = formatter.format(call_tree)
        expect(result).to include("Most Called Methods:")
        expect(result).to include("TestClass#repeated_method - 3 calls")
      end

      it "shows total calls and time" do
        result = formatter.format(call_tree)
        expect(result).to include("Total Calls: 4")
        expect(result).to include("Total Time:")
        expect(result).to include("Unique Methods: 2")
      end
    end

    context "when there are no children" do
      before do
        call_tree.start_call("TestClass#no_children")
        sleep(0.001)
        call_tree.end_call(:success)
      end

      it "formats correctly without children" do
        result = formatter.format(call_tree)
        expect(result).to include("TestClass#no_children")
        expect(result).not_to include("├──") # no child connectors
      end
    end

    context "when status indicator is empty" do
      before do
        call_tree.start_call("TestClass#success")
        sleep(0.001)
        call_tree.end_call(:success)
      end

      it "does not show error indicator for successful calls" do
        result = formatter.format(call_tree, colorize: true)
        expect(result).not_to include("[ERROR]")
      end
    end
  end
end
