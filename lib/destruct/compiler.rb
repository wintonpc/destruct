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
        lambda do |_code, _refs, #{ref_args}|
          lambda do |x, binding, env=true|
            begin
              #{@emitted.string}
              env
            rescue
              ::Destruct::Compiler.show_code(_code, _refs)
              raise
            end
          end
        end
      CODE
      code = beautify_ruby(code)
      # show_code(code, fancy: false)
      compiled = eval(code).call(code, @refs, *@refs.values)
      CompiledPattern.new(pat, compiled)
    end

    def emit(str)
      @emitted << str
      @emitted << "\n"
    end

    def ref_args
      return "" if @refs.none?
      "\n#{@refs.map { |k, v| "#{k.to_s.ljust(8)}, # #{v.inspect}" }.join("\n")}\n"
    end

    def match(pat, x_expr)
      if pat.is_a?(Obj)
        match_obj(pat, x_expr)
      elsif pat.is_a?(Or)
        match_or(pat, x_expr)
      elsif pat.is_a?(Var)
        match_var(pat, x_expr)
      elsif pat.is_a?(Array)
        match_array(pat, x_expr)
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
      elsif pat.is_a?(Array)
        test_array(pat, x_expr, env_expr)
      else
        test_literal(pat, x_expr, env_expr)
      end
    end

    def return_if_failed
      emit "return nil unless env"
    end

    def need_env(env_expr="env")
      unless @created_env
        @created_env = true
        emit "#{env_expr} = ::Destruct::Env.new"
      end
    end

    def match_array(pat, x_expr)
      test_array(pat, x_expr) # no need to return_if_failed because it's compound
    end

    def test_array(pat, x_expr, env_expr="env")
      assign_env(env_expr, "#{x_expr}.size == #{get_ref(pat)}.size")
      emit "if #{env_expr}"
      pat.each_with_index do |pi, i|
        if env_expr == "env"
          # not in an Or, so fail fast
          match(pi, "#{x_expr}[#{i}]")
        else
          # in an Or, so only test
          test(pi, "#{x_expr}[#{i}]", env_expr)
        end
      end
      emit "end"
    end

    def match_literal(pat, x_expr)
      test_literal(pat, x_expr)
      return_if_failed
    end

    def test_literal(pat, x_expr, env_expr="env")
      # emit "puts \"\#{#{x_expr}.inspect} == \#{#{pat.inspect.inspect}}\""
      assign_env(env_expr, "#{x_expr} == #{pat.inspect}")
    end

    def assign_env(env_expr, cond)
      if env_expr == "env"
        emit "#{env_expr} = #{cond} ? env : nil"
      else
        emit "#{env_expr} = #{cond}"
      end
    end

    def match_var(pat, x_expr)
      test_var(pat, x_expr)
      return_if_failed
    end

    def test_var(pat, x_expr, env_expr="env")
      need_env(env_expr)
      # emit "puts \"
      emit "#{env_expr} = #{env_expr}.bind(#{get_ref(pat)}, #{x_expr})"
    end

    def match_obj(pat, x_expr)
      test_obj(pat, x_expr)
      # return_if_failed # thinking this not necessary since this is a compound test and all the primitive tests call it
    end

    def test_obj(pat, x_expr, env_expr="env")
      assign_env(env_expr, "#{x_expr}.is_a?(#{get_ref(pat.type)})")
      emit "if #{env_expr}"
      pat.fields.each do |field_name, field_pat|
        if env_expr == "env"
          # not in an Or, so fail fast
          match(field_pat, "#{x_expr}.#{field_name}")
        else
          # in an Or, so only test
          test(field_pat, "#{x_expr}.#{field_name}", env_expr)
        end
      end
      emit "end"
    end

    def match_or(pat, x_expr)
      test_or(pat, x_expr)
      return_if_failed
    end

    def test_or(pat, x_expr, env_expr="env")
      temp_env_expr = get_temp
      emit "#{temp_env_expr} = nil"
      num_nestings = pat.patterns.size - 1
      pat.patterns.each_with_index do |alt, i|
        test(alt, x_expr, temp_env_expr)
        emit "unless #{temp_env_expr}" if i < num_nestings
      end
      num_nestings.times { emit "end" }
      emit "#{env_expr} = ::Destruct::Env.merge!(#{env_expr}, #{temp_env_expr})"
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

    def self.show_code(code, refs, fancy: true)
      lines = number_lines(code)
      if fancy
        lines = lines
                    .reject { |line| line =~ /^\s*\d+\s*puts/ }
                    .map do |line|
          if line !~ /, #|_code|_refs/
            refs.each do |k, v|
              line = line.gsub(/#{k}(?!\d+)/, v.inspect)
            end
          end
          line
        end
      end
      puts lines
    end

    def self.number_lines(code)
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

    def match(x, binding=nil)
      @compiled.(x, binding)
    end
  end
end
