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

  # Globbed rather than derived from `git ls-files`.
  #
  # The git-based list silently omits any file that is new and not yet staged,
  # which shipped a broken gem once already (see CHANGELOG 0.3.1 — the released
  # 0.3.0 was missing EnhancedTracer and the formatters). Globbing cannot leave
  # out a file that exists on disk, and the `gem-smoke` CI job builds the gem
  # and requires it so a missing file fails the build rather than a user's
  # install.
  spec.files = Dir[
    "lib/**/*.rb",
    "sig/**/*.rbs"
  ] + %w[
    CHANGELOG.md
    CODE_OF_CONDUCT.md
    LICENSE.txt
    README.md
  ].select { |path| File.file?(File.join(__dir__, path)) }

  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
