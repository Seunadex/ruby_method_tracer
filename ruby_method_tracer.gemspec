# frozen_string_literal: true

require_relative "lib/ruby_method_tracer/version"

Gem::Specification.new do |spec|
  spec.name = "ruby_method_tracer"
  spec.version = RubyMethodTracer::VERSION
  spec.authors = ["Seun Adekunle"]
  spec.email = ["adekunleseun001@gmail.com"]

  spec.summary = "Lightweight method tracing for Ruby applications"
  spec.description = "A developer-friendly gem for tracing method calls, execution times, with minimal overhead."
  spec.homepage = "https://github.com/Seunadex/ruby_method_tracer"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = "https://github.com/Seunadex/ruby_method_tracer/blob/main/README.md"
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "https://github.com/Seunadex/ruby_method_tracer/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
