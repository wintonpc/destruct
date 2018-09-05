# frozen_string_literal: true

require_relative './types'
require_relative './rbeautify'

class Destruct
  class Compiler
    class << self
      def compile(pat)
        Compiler.new.compile(pat)
      end

      def match(pat, x)
        compile(pat).match(x)
      end
    end

    Frame = Struct.new(:pat, :x, :env, :parent, :type)

    def initialize
      @refs = {}
      @reverse_refs = {}
      @emitted = StringIO.new
      @temp_num = 0
    end

    def compile(pat)
      x = get_temp("x")
      env = get_temp("env")
      match(Frame.new(pat, x, env))
      code = <<~CODE
        lambda do |_code, _refs#{ref_args}|
          lambda do |#{x}, binding, #{env}=true|
            begin
              #{@emitted.string}
      #{env}
            rescue
              ::Destruct::Compiler.show_code(_code, _refs)
              raise
            end
          end
        end
      CODE
      code = beautify_ruby(code)
      Compiler.show_code(code, @refs, fancy: true)
      compiled = eval(code).call(code, @refs, *@refs.values)
      CompiledPattern.new(pat, compiled, code)
    end

    def emit(str)
      @emitted << str
      @emitted << "\n"
    end

    def ref_args
      return "" if @refs.none?
      ", \n#{@refs.map { |k, v| "#{k.to_s.ljust(8)}, # #{v.inspect}" }.join("\n")}\n"
    end

    def match(s)
      match_or_test(s, true)
    end

    def test(s)
      match_or_test(s, false)
    end

    def match_or_test(s, fail_fast)
      if s.pat.is_a?(Obj)
        test_obj(s)
        # return_if_failed not necessary since this is a compound test
      elsif s.pat.is_a?(Or)
        test_or(s)
        return_if_failed(s) if fail_fast
      elsif s.pat.is_a?(Var)
        test_var(s)
        return_if_failed(s) if fail_fast
      elsif s.pat.is_a?(Array)
        test_array(s)
        # return_if_failed not necessary since this is a compound test
      else
        test_literal(s)
        return_if_failed(s) if fail_fast
      end
    end

    def pop(s)
      s.parent
    end

    def return_if_failed(s)
      emit "return nil unless #{s.env}"
    end

    def need_env(s)
      unless created_envs.include?(s.env)
        created_envs << s.env
        emit "#{s.env} = ::Destruct::Env.new"
      end
    end

    def created_envs
      @created_envs ||= []
    end

    def test_array(s)
      s.type = :array
      env_expr = s.env
      emit "#{env_expr} = #{"#{s.x}.size == #{get_ref(s.pat)}.size"} ? #{env_expr} : nil"
      emit "if #{s.env}"
      s.pat.each_with_index do |pi, i|
        match_or_test(Frame.new(pi, "#{s.x}[#{i}]", s.env, s), !in_or(s))
      end
      emit "end"
    end

    def in_or(s)
      !s.nil? && (s.type == :or || in_or(s.parent))
    end

    def test_literal(s)
      s.type = :literal
      emit "#{s.env} = #{"#{s.x} == #{s.pat.inspect}"} ? #{s.env} : nil"
    end

    def test_var(s)
      s.type = :var
      emit "#{s.env} = ::Destruct::Env.bind(#{s.env}, #{get_ref(s.pat)}, #{s.x})"
    end

    def test_obj(s)
      s.type = :obj
      emit "#{s.env} = #{"#{s.x}.is_a?(#{get_ref(s.pat.type)})"} ? #{s.env} : nil"
      if s.pat.fields.any?
        emit "if #{s.env}"
        s.pat.fields.each do |field_name, field_pat|
          match_or_test(Frame.new(field_pat, "#{s.x}.#{field_name}", s.env, s), !in_or(s))
        end
        emit "end"
      end
    end

    def test_or(s)
      s.type = :or
      closers = []
      or_env = get_temp("env")
      emit "#{or_env} = true"
      s.pat.patterns.each_with_index do |alt, i|
        test(Frame.new(alt, s.x, or_env, s))
        if i < s.pat.patterns.size - 1
          emit "unless #{or_env}"
          closers << proc { emit "end" }
          emit "#{or_env} = true"
        end
      end
      closers.each(&:call)
      emit "#{s.env} = ::Destruct::Env.merge!(#{s.env}, #{or_env})"
    end

    def get_ref(pat)
      @reverse_refs.fetch(pat) do
        id = get_temp
        @refs[id] = pat
        @reverse_refs[pat] = id
        id
      end
    end

    def get_temp(prefix="t")
      "_#{prefix}#{@temp_num += 1}"
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
    attr_reader :pat, :code

    def initialize(pat, compiled, code)
      @pat = pat
      @compiled = compiled
      @code = code
    end

    def match(x, binding=nil)
      @compiled.(x, binding)
    end
  end
end
