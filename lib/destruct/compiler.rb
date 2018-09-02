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

    def compile(pat)
      code = <<~CODE
        proc do
          proc do |x, binding, env|
            #{emit(pat, "x")}
          end
        end
      CODE
      code = beautify_ruby(code)
      puts number_lines(code)
      compiled = eval(code).call
      CompiledPattern.new(pat, compiled)
    end

    def emit(pat, x_expr)
      if pat.is_a?(Var)
      else
        emit_literal(pat, x_expr)
      end
    end

    def emit_literal(pat, x_expr)
      <<~CODE
        if #{x_expr} == #{pat.inspect}
          env ||= ::Destruct::Env.new
        else
          nil
        end
      CODE
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
