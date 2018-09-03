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
      @reverse_refs = {}
      @emitted = StringIO.new
    end

    def compile(pat)
      match(pat, "x")
      code = <<~CODE
        lambda do #{ref_args}
          lambda do |x, binding, env=true|
            #{@emitted.string}
            env
          end
        end
      CODE
      code = beautify_ruby(code)
      show_code(code)
      compiled = eval(code).call(*@refs.values)
      CompiledPattern.new(pat, compiled)
    end

    def emit(str)
      @emitted << str
      @emitted << "\n"
    end

    def ref_args
      return "" if @refs.none?
      "|\n#{@refs.map { |k, v| "#{k.to_s.ljust(8)}, # #{v.inspect}" }.join("\n")}\n|"
    end

    def match(pat, x_expr)
      if pat.is_a?(Obj)
        match_obj(pat, x_expr)
      elsif pat.is_a?(Or)
        match_or(pat, x_expr)
      elsif pat.is_a?(Var)
        match_var(pat, x_expr)
      else
        match_literal(pat, x_expr)
      end
    end

    def match_literal(pat, x_expr)
      test_literal(pat, x_expr)
      return_if_failed
    end

    def return_if_failed
      emit "return nil unless env"
    end

    def test_literal(pat, x_expr, env_expr="env")
      emit "puts \"\#{#{x_expr}.inspect} == \#{#{pat.inspect.inspect}}\""
      emit "#{env_expr} = #{x_expr} == #{pat.inspect} ? env : nil"
    end

    def match_var(pat, x_expr)
      <<~CODE
#{need_env}
        result = env.bind(#{get_ref(pat)}, #{x_expr})
        #{dont_return ? "" : "return nil unless result"}
      CODE
    end

    def match_obj(pat, x_expr, dont_return)
      s = StringIO.new
      s << <<~CODE
        puts "\#{#{x_expr}.inspect}.is_a?(#{get_ref(pat.type)})"
        result = #{x_expr}.is_a?(#{get_ref(pat.type)})
        #{dont_return ? "" : "return nil unless result"}
      CODE
      pat.fields.each do |k, v|
        s << match(v, "#{x_expr}[#{get_ref(k)}]")
      end
      s.string
    end

    def match_or(pat, x_expr, dont_return)
      clauses = pat.patterns.map do |p|
        "if (#{match(p, x_expr, true)})"
      end.join("\nels")
      clauses + "\nelse\nreturn nil\nend"
    end

    def get_ref(pat)
      @reverse_refs.fetch(pat) do
        id = "_ref#{@refs.size}"
        @refs[id] = pat
        @reverse_refs[pat] = id
        id
      end
    end

    def beautify_ruby(code)
      RBeautify.beautify_string(code.split("\n").reject { |line| line.strip == '' }).first
    end

    def number_lines(code)
      code.split("\n").each_with_index.map do |line, n|
        "#{(n + 1).to_s.rjust(3)} #{line}"
      end
    end

    private

    def show_code(code)
      lines = number_lines(code)
                  .reject { |line| line =~ /^\s*\d+\s*puts/ }
                  .map do |line|
        if line !~ /, #/
          @refs.each do |k, v|
            line = line.gsub(/#{k}(?!\d+)/, v.inspect)
          end
        end
        line
      end
      puts lines
    end
  end

  class CompiledPattern
    attr_reader :pat

    def initialize(pat, compiled)
      @pat = pat
      @compiled = compiled
    end

    def match(x, binding=nil)
      @compiled.(x, binding)
    end
  end
end
