# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

require "rubocop/rake_task"

RuboCop::RakeTask.new

# Deliberately not a bundle dependency: rbs requires Ruby >= 3.1, and this gem
# supports >= 3.0, so adding it to the Gemfile breaks `bundle install` on 3.0.
# Install it yourself (`gem install rbs`) to run this; CI validates it strictly.
desc "Type-check the shipped RBS signatures (requires: gem install rbs)"
task :rbs do
  sh "rbs -r logger -I sig validate"
rescue Errno::ENOENT
  abort "rbs not found. Install it with: gem install rbs"
end

task default: %i[spec rubocop]
