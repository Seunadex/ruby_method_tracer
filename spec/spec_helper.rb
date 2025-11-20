# frozen_string_literal: true

require "simplecov"

SimpleCov.start do
  add_filter "/spec/"
  add_filter "/vendor/"
  enable_coverage :branch
  minimum_coverage line: 95, branch: 80

  if ENV["CI"]
    require "simplecov_json_formatter"
    formatter SimpleCov::Formatter::JSONFormatter
  end
end

require "ruby_method_tracer"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
