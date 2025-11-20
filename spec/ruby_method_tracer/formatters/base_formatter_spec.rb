# frozen_string_literal: true

RSpec.describe RubyMethodTracer::Formatters::BaseFormatter do
  let(:formatter) { described_class.new }

  describe "#format_time" do
    context "when time is >= 1 second" do
      it "formats in seconds with 3 decimal places" do
        expect(formatter.format_time(1.0)).to eq("1.0s")
        expect(formatter.format_time(1.234)).to eq("1.234s")
        expect(formatter.format_time(10.5678)).to eq("10.568s")
      end
    end

    context "when time is >= 1 millisecond but < 1 second" do
      it "formats in milliseconds with 1 decimal place" do
        expect(formatter.format_time(0.001)).to eq("1.0ms")
        expect(formatter.format_time(0.0123)).to eq("12.3ms")
        expect(formatter.format_time(0.5)).to eq("500.0ms")
      end
    end

    context "when time is < 1 millisecond" do
      it "formats in microseconds with no decimal places" do
        expect(formatter.format_time(0.0001)).to eq("100µs")
        expect(formatter.format_time(0.000001)).to eq("1µs")
        expect(formatter.format_time(0.0009)).to eq("900µs")
      end
    end
  end

  describe "#colorize" do
    it "applies red color" do
      result = formatter.colorize("error", :red)
      expect(result).to eq("\e[31merror\e[0m")
    end

    it "applies green color" do
      result = formatter.colorize("success", :green)
      expect(result).to eq("\e[32msuccess\e[0m")
    end

    it "applies yellow color" do
      result = formatter.colorize("warning", :yellow)
      expect(result).to eq("\e[33mwarning\e[0m")
    end

    it "applies blue color" do
      result = formatter.colorize("info", :blue)
      expect(result).to eq("\e[34minfo\e[0m")
    end

    it "applies magenta color" do
      result = formatter.colorize("debug", :magenta)
      expect(result).to eq("\e[35mdebug\e[0m")
    end

    it "applies cyan color" do
      result = formatter.colorize("trace", :cyan)
      expect(result).to eq("\e[36mtrace\e[0m")
    end

    it "applies white color" do
      result = formatter.colorize("text", :white)
      expect(result).to eq("\e[37mtext\e[0m")
    end
  end

  describe "#format" do
    it "raises NotImplementedError" do
      expect { formatter.format({}) }.to raise_error(
        NotImplementedError,
        "RubyMethodTracer::Formatters::BaseFormatter must implement #format"
      )
    end
  end
end
