# frozen_string_literal: true

module RubyMethodTracer
  # Exportable provides render/export helpers shared by the tracers.
  #
  # Host classes must implement a private `#report_source` returning the data
  # handed to formatters (a results hash or a CallTree).
  #
  # Security notes:
  # - `export` never invokes a shell and never interpolates the path into a
  #   command; it writes via `File.open` with `O_NOFOLLOW`.
  # - The destination directory must already exist (no recursive mkdir of
  #   attacker-influenced paths) and the tracer refuses to write through an
  #   existing symlink, guarding against symlink-redirection.
  #
  # Concurrency: `render`/`export` read the tracer's in-memory buffers and are
  # intended to be called when tracing is quiescent (e.g. after the traced work
  # has finished). The flat results path is snapshotted under a lock; the call
  # tree is read via its locked hierarchy/statistics accessors.
  module Exportable
    # Render the current results to a string.
    #
    # @param format [Symbol] :json, :flat (and :tree for EnhancedTracer)
    # @return [String]
    def render(format: :json, **opts)
      build_formatter(format).format(report_source, opts)
    end

    # Render results and write them to a file.
    #
    # @param path [String] Destination file path
    # @param format [Symbol] :json, :flat (and :tree for EnhancedTracer)
    # @return [String] The absolute path written
    def export(path, format: :json, **opts)
      write_export(path, render(format: format, **opts))
    end

    private

    # Compare on the string form so an unknown format never interns an
    # arbitrary symbol (avoids unbounded symbol-table growth if a caller
    # forwards untrusted input as the format).
    def build_formatter(format)
      case format.to_s
      when "json" then Formatters::JsonFormatter.new
      when "flat" then Formatters::FlatFormatter.new
      when "tree" then raise ArgumentError, "the :tree format needs a call tree; use EnhancedTracer"
      else raise ArgumentError, "unknown export format: #{format.inspect}"
      end
    end

    def write_export(path, content)
      safe_path = validate_export_path(path)
      # O_NOFOLLOW makes the open fail if the final component is a symlink,
      # closing the check-then-write race left by the stat-based guard below.
      # It is a POSIX open(2) flag and is absent on some platforms (Windows);
      # there the stat-based guard alone applies.
      flags = File::WRONLY | File::CREAT | File::TRUNC
      flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
      File.open(safe_path, flags) { |file| file.write(content) }
      safe_path
    rescue Errno::ELOOP
      raise ArgumentError, "refusing to write through symlink: #{path}"
    end

    def validate_export_path(path)
      raise ArgumentError, "export path must be provided" if path.nil? || path.to_s.strip.empty?

      expanded = File.expand_path(path.to_s)
      dir = File.dirname(expanded)
      raise ArgumentError, "export directory does not exist: #{dir}" unless File.directory?(dir)
      raise ArgumentError, "refusing to overwrite symlink: #{expanded}" if File.symlink?(expanded)

      expanded
    end
  end
end
