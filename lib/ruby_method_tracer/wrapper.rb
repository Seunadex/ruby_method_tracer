# frozen_string_literal: true

module RubyMethodTracer
  # Wrapper generates the traced replacement for a method.
  #
  # Two things drive the design:
  #
  # 1. **Signature fidelity.** The replacement is built with `module_eval` from
  #    the original method's `parameters`, not from a generic
  #    `proc { |*args, **kwargs, &block| }`, so `Method#arity` and
  #    `Method#parameters` survive tracing and reflection-driven callers
  #    (dependency injection, serializers, argument validators, documentation
  #    tooling) still see the real signature.
  #
  # 2. **Per-call cost.** The whole timing path is emitted inline: the
  #    reentrancy guard, both clock reads and the `begin/rescue/ensure` live in
  #    the generated method itself. It calls the tracer exactly once per
  #    invocation (twice when tracking hierarchy), instead of threading a block
  #    down through several tracer methods — each of those frames cost a call
  #    plus a `Proc`. Everything knowable at trace time (the reentrancy key, the
  #    method name, the display name) is baked in as a literal so no hash
  #    lookups happen on the call path.
  #
  # Optional positional and optional keyword parameters are declared with
  # OMITTED as their default. Omitted values are dropped before forwarding, so
  # the original method still applies its own defaults — `parameters` does not
  # expose default values, so they cannot be reproduced here.
  #
  # The one signature difference that remains: a block parameter is always
  # declared, even when the original had none, because a method may still
  # `yield`. Block parameters do not affect arity.
  module Wrapper
    # Sentinel marking "this optional argument was not supplied". Referenced by
    # generated code, so it must stay a public constant.
    OMITTED = Object.new

    SENTINEL = "::RubyMethodTracer::Wrapper::OMITTED"
    IDENTIFIER = /\A[a-z_][A-Za-z0-9_]*\z/
    private_constant :SENTINEL, :IDENTIFIER

    # What the generated wrapper should do, beyond forwarding the call.
    #
    # @!attribute key
    #   @return [Symbol] Thread-local key for the reentrancy guard
    # @!attribute close
    #   @return [Symbol] Tracer method called with (name, duration, status, error)
    # @!attribute open
    #   @return [Symbol, nil] Tracer method called before the call, with the display name
    # @!attribute display_name
    #   @return [String, nil] Literal passed to the open hook
    Plan = Struct.new(:key, :close, :open, :display_name, keyword_init: true)

    # Build a signature description for a parameter list.
    #
    # Produces the parameter declaration, the setup that rebuilds the argument
    # list at call time, and the forwarding call itself. Methods whose every
    # parameter forwards unconditionally — no optional positionals, no keywords —
    # skip the argument array entirely and forward straight through, which is
    # the common case.
    class Signature
      # Parameter kind => the builder that emits its declaration and forwarding.
      HANDLERS = {
        req: :required,
        opt: :optional,
        rest: :splat,
        keyreq: :keyword_required,
        key: :keyword_optional,
        keyrest: :keyword_splat,
        nokey: :nokey,
        block: :block_param
      }.freeze
      private_constant :HANDLERS

      def initialize(params)
        @declaration = []
        @positional = []
        @keyword = []
        @direct = []
        @block_name = nil
        @nokey = false
        @dynamic = false
        params.each_with_index { |(kind, name), index| add(kind, name, index) }
        @declaration << "&#{block_name}"
      end

      def declaration
        @declaration.join(", ")
      end

      # Rebuilds the outgoing argument list. Empty for the direct path.
      def setup
        return "" if direct?

        lines = ["__rmt_args__ = []", *@positional]
        lines += ["__rmt_kwargs__ = {}", *@keyword] unless keywordless?
        lines.join("\n  ")
      end

      def forward(aliased)
        return "#{aliased}(#{(@direct + ["&#{block_name}"]).join(", ")})" if direct?

        plain = "#{aliased}(*__rmt_args__, &#{block_name})"
        return plain if keywordless?

        # The empty check keeps `**{}` off the call site, which is what broke
        # keyword forwarding on Ruby 3.4 (see CHANGELOG 0.3.2 and 0.3.3).
        # Parenthesised so the expression stays intact wherever it is spliced in.
        "(__rmt_kwargs__.empty? ? #{plain} : " \
          "#{aliased}(*__rmt_args__, **__rmt_kwargs__, &#{block_name}))"
      end

      private

      # Every parameter forwards unconditionally and no keywords are involved,
      # so the call can be written out literally.
      def direct?
        !@dynamic && @keyword.empty? && !@nokey
      end

      def keywordless?
        @nokey || @keyword.empty?
      end

      def block_name
        @block_name ||= "__rmt_block__"
      end

      def add(kind, name, index)
        handler = HANDLERS[kind]
        send(handler, local_name(name, index)) if handler
      end

      def required(name)
        @declaration << name
        @positional << "__rmt_args__ << #{name}"
        @direct << name
      end

      def optional(name)
        @declaration << "#{name} = #{SENTINEL}"
        @positional << "__rmt_args__ << #{name} unless #{SENTINEL}.equal?(#{name})"
        @dynamic = true
      end

      def splat(name)
        @declaration << "*#{name}"
        @positional << "__rmt_args__.concat(#{name})"
        @direct << "*#{name}"
      end

      def keyword_required(name)
        @declaration << "#{name}:"
        @keyword << "__rmt_kwargs__[:#{name}] = #{name}"
      end

      def keyword_optional(name)
        @declaration << "#{name}: #{SENTINEL}"
        @keyword << "__rmt_kwargs__[:#{name}] = #{name} unless #{SENTINEL}.equal?(#{name})"
      end

      def keyword_splat(name)
        @declaration << "**#{name}"
        @keyword << "__rmt_kwargs__.update(#{name})"
      end

      def nokey(_name)
        @declaration << "**nil"
        @nokey = true
      end

      def block_param(name)
        @block_name = name
      end

      # Anonymous parameters (`def m(*)`) and argument forwarding (`def m(...)`)
      # report names that are unusable or absent; everything else keeps the
      # original name so `parameters` still reports it.
      def local_name(name, index)
        return "__rmt_p#{index}__" if name.nil? || !IDENTIFIER.match?(name.to_s)

        name.to_s
      end
    end

    class << self
      # Define the traced replacement for `method_name` on `target_class`.
      #
      # @param target_class [Module] Class the method lives on
      # @param method_name [Symbol] Method being traced
      # @param aliased [Symbol] Private alias holding the original body
      # @param accessor [Symbol] Private method returning the owning tracer
      # @param plan [Plan] What the wrapper should do around the call
      # @return [Symbol] The defined method name
      def install(target_class, method_name, aliased, accessor, plan)
        signature = Signature.new(target_class.instance_method(aliased).parameters)
        source = source(signature, method_name, aliased, accessor, plan)
        target_class.module_eval(source, __FILE__, __LINE__)
      end

      private

      # rubocop:disable Metrics/MethodLength
      def source(signature, method_name, aliased, accessor, plan)
        forward = signature.forward(aliased)
        <<~RUBY
          def #{method_name}(#{signature.declaration})
            #{signature.setup}
            __rmt_guard__ = (::Thread.current[#{plan.key.inspect}] ||= [false])
            return #{forward} if __rmt_guard__[0]

            __rmt_tracer__ = #{accessor}
            __rmt_guard__[0] = true
            #{open_hook(plan)}
            __rmt_started__ = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
            __rmt_status__ = :incomplete
            __rmt_failure__ = nil
            begin
              __rmt_result__ = #{forward}
              __rmt_status__ = :success
              __rmt_result__
            rescue ::StandardError => __rmt_caught__
              __rmt_status__ = :error
              __rmt_failure__ = __rmt_caught__
              raise
            ensure
              __rmt_tracer__.#{plan.close}(
                #{method_name.inspect},
                ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - __rmt_started__,
                __rmt_status__,
                __rmt_failure__
              )
              __rmt_guard__[0] = false
            end
          end
        RUBY
      end
      # rubocop:enable Metrics/MethodLength

      def open_hook(plan)
        return "" unless plan.open

        "__rmt_tracer__.#{plan.open}(#{plan.display_name.inspect})"
      end
    end
  end
end
