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
    end

    def compile(pat)
      matching_code = emit(pat, "x")
      code = <<~CODE
        lambda do #{ref_args}
          lambda do |x, binding, env|
            #{matching_code}
      #{need_env}
          env
          end
        end
      CODE
      code = beautify_ruby(code)
      show_code(code)
      compiled = eval(code).call(*@refs.values)
      CompiledPattern.new(pat, compiled)
    end

    def need_env
      if @emitted_env
        ""
      else
        @emitted_env = true
        "env ||= ::Destruct::Env.new"
      end
    end

    def ref_args
      return "" if @refs.none?
      "|\n#{@refs.map { |k, v| "#{k.to_s.ljust(8)}, # #{v.inspect}" }.join("\n")}\n|"
    end

    def emit(pat, x_expr, dont_return=false)
      if pat.is_a?(Obj)
        emit_obj(pat, x_expr, dont_return)
      elsif pat.is_a?(Or)
        emit_or(pat, x_expr, dont_return)
      elsif pat.is_a?(Var)
        emit_var(pat, x_expr, dont_return)
      else
        emit_literal(pat, x_expr, dont_return)
      end
    end

    def emit_literal(pat, x_expr, dont_return)
      <<~CODE
        puts "\#{#{x_expr}.inspect} == \#{#{pat.inspect.inspect}}"
        result = #{x_expr} == #{pat.inspect} 
        #{dont_return ? "" : "return nil unless result"}
      CODE
    end

    def emit_var(pat, x_expr, dont_return)
      <<~CODE
#{need_env}
        result = env.bind(#{get_ref(pat)}, #{x_expr})
        #{dont_return ? "" : "return nil unless result"}
      CODE
    end

    def emit_obj(pat, x_expr, dont_return)
      s = StringIO.new
      s << <<~CODE
        puts "\#{#{x_expr}.inspect}.is_a?(#{get_ref(pat.type)})"
        result = #{x_expr}.is_a?(#{get_ref(pat.type)})
        #{dont_return ? "" : "return nil unless result"}
      CODE
      pat.fields.each do |k, v|
        s << emit(v, "#{x_expr}[#{get_ref(k)}]")
      end
      s.string
    end

    def emit_or(pat, x_expr, dont_return)
      pat.patterns.map do |p|
        "if (#{emit(pat, x_expr)})"
      end
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

    def match(x, binding=nil, env=nil)
      @compiled.(x, binding, env)
    end
  end
end
