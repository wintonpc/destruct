# frozen_string_literal: true

require_relative './types'
require_relative './rbeautify'

class Destruct
  class Compiler
    class << self
      def compile(pat)
        Compiler.new.compile(pat)
      end
    end

    def initialize
      @refs = {}
    end

    def compile(pat)
      matching_code = emit(pat, "x")
      code = <<~CODE
        lambda do |#{@refs.keys.join(", ")}|
          lambda do |x, binding, env|
            #{matching_code}
            env ||= ::Destruct::Env.new
          end
        end
      CODE
      code = beautify_ruby(code)
      puts number_lines(code)
      compiled = eval(code).call(*@refs.values)
      CompiledPattern.new(pat, compiled)
    end

    def emit(pat, x_expr)
      if pat.is_a?(Var)
        emit_var(pat, x_expr)
      else
        emit_literal(pat, x_expr)
      end
    end

    def emit_literal(pat, x_expr)
      <<~CODE
        return nil unless #{x_expr} == #{pat.inspect}
      CODE
    end

    def emit_var(pat, x_expr)
      <<~CODE
        env ||= ::Destruct::Env.new
        return nil unless env.bind(#{get_ref(pat)}, #{x_expr})
      CODE
    end

    def get_ref(pat)
      id = "_ref#{@refs.size}"
      @refs[id] = pat
      id
    end

    def beautify_ruby(code)
      RBeautify.beautify_string(code.split("\n").reject { |line| line.strip == '' }).first
    end

    def number_lines(code)
      code.split("\n").each_with_index.map do |line, n|
        "#{(n + 1).to_s.rjust(3)} #{line}"
      end
    end
  end

  class CompiledPattern
    attr_reader :pat

    def initialize(pat, compiled)
      @pat = pat
      @compiled = compiled
    end

    def match(x, binding=nil, env=nil)
      @compiled.(x, binding, env)
    end
  end
end
