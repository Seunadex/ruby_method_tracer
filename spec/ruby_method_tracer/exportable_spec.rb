# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "json"

RSpec.describe RubyMethodTracer::Exportable do
  let(:target_class) do
    Class.new do
      def work
        :done
      end
    end
  end

  def traced_simple
    tracer = RubyMethodTracer::SimpleTracer.new(target_class, threshold: 0.0)
    tracer.trace_method(:work)
    target_class.new.work
    tracer
  end

  describe "#render" do
    it "renders JSON by default" do
      parsed = JSON.parse(traced_simple.render)
      expect(parsed["total_calls"]).to eq(1)
    end

    it "renders a flat table" do
      expect(traced_simple.render(format: :flat, colorize: false)).to include("Method")
    end

    it "raises on an unknown format" do
      expect { traced_simple.render(format: :bogus) }.to raise_error(ArgumentError, /unknown export format/)
    end

    it "supports :tree for EnhancedTracer" do
      tracer = RubyMethodTracer::EnhancedTracer.new(target_class, threshold: 0.0)
      tracer.trace_method(:work)
      target_class.new.work
      expect(tracer.render(format: :tree, colorize: false)).to include("METHOD CALL TREE")
    end
  end

  describe "#export" do
    it "writes rendered content to disk and returns the path" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "trace.json")
        returned = traced_simple.export(path, format: :json)
        expect(returned).to eq(File.expand_path(path))
        expect(JSON.parse(File.read(path))["total_calls"]).to eq(1)
      end
    end

    it "rejects a blank path" do
      expect { traced_simple.export("  ") }.to raise_error(ArgumentError, /path must be provided/)
    end

    it "rejects a non-existent target directory" do
      expect { traced_simple.export("/no/such/dir/trace.json") }
        .to raise_error(ArgumentError, /directory does not exist/)
    end

    it "refuses to write through an existing symlink" do
      Dir.mktmpdir do |dir|
        real = File.join(dir, "real.json")
        link = File.join(dir, "link.json")
        File.write(real, "{}")
        File.symlink(real, link)
        expect { traced_simple.export(link) }.to raise_error(ArgumentError, /symlink/)
      end
    end
  end
end
