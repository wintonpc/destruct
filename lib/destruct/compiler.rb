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
      @temp_num = 0
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

    def test(pat, x_expr, env_expr="env")
      if pat.is_a?(Obj)
        test_obj(pat, x_expr, env_expr)
      elsif pat.is_a?(Or)
        test_or(pat, x_expr, env_expr)
      elsif pat.is_a?(Var)
        test_var(pat, x_expr, env_expr)
      else
        test_literal(pat, x_expr, env_expr)
      end
    end

    def return_if_failed
      emit "return nil unless env"
    end

    def need_env
      unless @created_env
        @created_env = true
        emit "env = ::Destruct::Env.new"
      end
    end

    def match_literal(pat, x_expr)
      test_literal(pat, x_expr)
      return_if_failed
    end

    def test_literal(pat, x_expr, env_expr="env")
      # emit "puts \"\#{#{x_expr}.inspect} == \#{#{pat.inspect.inspect}}\""
      emit "#{env_expr} = #{x_expr} == #{pat.inspect} ? env : nil"
    end

    def match_var(pat, x_expr)
      test_var(pat, x_expr)
      return_if_failed
    end

    def test_var(pat, x_expr, env_expr="env")
      need_env
      # emit "puts \"
      emit "#{env_expr} = env.bind(#{get_ref(pat)}, #{x_expr})"
    end

    def match_obj(pat, x_expr)
      test_obj(pat, x_expr)
      # return_if_failed # thinking this not necessary since this is a compound test and all the primitive tests call it
    end

    def test_obj(pat, x_expr, env_expr="env")
      emit "#{env_expr} = #{x_expr}.is_a?(#{get_ref(pat.type)}) ? env : nil"
      emit "if #{env_expr}"
      pat.fields.each do |key, field_pat|
        match(field_pat, "#{x_expr}[#{get_ref(key)}]")
      end
      emit "end"
    end

    def match_or(pat, x_expr)
      temp_env_expr = get_temp
      emit "#{temp_env_expr} = true"
      pat.patterns.each do |alt|
        test(alt, x_expr, temp_env_expr)
        emit "unless #{temp_env_expr}"
      end
      pat.patterns.each { emit "end" }
      emit "env = ::Destruct::Env.merge!(env, #{temp_env_expr})"
      return_if_failed
    end

    def get_ref(pat)
      @reverse_refs.fetch(pat) do
        id = get_temp
        @refs[id] = pat
        @reverse_refs[pat] = id
        id
      end
    end

    def get_temp
      "_t#{@temp_num += 1}"
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
