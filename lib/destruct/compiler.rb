# frozen_string_literal: true

require "pp"
require_relative './types'
require_relative './rbeautify'

module Enumerable
  def rest
    result = []
    while true
      result << self.next
    end
  rescue StopIteration
    result
  end

  def new_from_here
    orig = self
    WrappedEnumerator.new(orig) do |y|
      while true
        y << orig.next
      end
    end
  end
end

class WrappedEnumerator < Enumerator
  def initialize(inner, &block)
    super(&block)
    @inner = inner
  end

  def new_from_here
    orig = @inner
    WrappedEnumerator.new(orig) do |y|
      while true
        y << orig.next
      end
    end
  end
end

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
      @vars = []
    end

    def compile(pat)
      x = get_temp("x")
      env = get_temp("env")
      match(Frame.new(pat, x, env))
      match_code = @emitted.string

      env_class_code = ""
      if @vars.any?
        env_class_code = <<~ENV
          _env_class = ::Destruct::Env.new_class(#{@vars.map(&:name).map(&:inspect).join(", ")})
          _make_env = lambda { _env_class.new }
        ENV
      end

      code = <<~CODE
        lambda do |_code, _refs#{ref_args}|
          #{env_class_code}
          lambda do |#{x}, binding, #{env}=true|
            begin
              #{match_code}
      #{env}
            rescue
              ::Destruct::Compiler.show_code(_code, _refs)
              raise
            end
          end
        end
      CODE
      code = beautify_ruby(code)
      Compiler.show_code(code, @refs, fancy: true, include_vm: false)
      compiled = eval(code).call(code, @refs, *@refs.values)
      CompiledPattern.new(pat, compiled, code)
    end

    def emit(str)
      @emitted_line_count ||= 0
      @emitted_line_count += 1
      @emitted << str
      @emitted << "\n"
    end

    def emitted_line_count
      @emitted_line_count ||= 0
    end

    def ref_args
      return "" if @refs.none?
      ", \n#{@refs.map { |k, v| "#{k.to_s.ljust(8)}, # #{v.inspect}" }.join("\n")}\n"
    end

    def match(s)
      if s.pat.is_a?(Obj)
        match_obj(s)
      elsif s.pat.is_a?(Or)
        match_or(s)
      elsif s.pat.is_a?(Var)
        saw_var(s.pat)
        match_var(s)
      elsif s.pat.is_a?(Array)
        match_array(s)
      else
        match_literal(s)
      end
    end

    def saw_var(var)
      @vars << var unless @vars.any? { |v| v.name == var.name }
    end

    def match_array(s)
      s.type = :array
      splat_count = s.pat.count { |p| p.is_a?(Splat) }
      if splat_count > 1
        raise "An array pattern cannot have more than one splat: #{s.pat}"
      end
      splat_index = s.pat.find_index { |p| p.is_a?(Splat) }
      is_closed = !splat_index || splat_index != s.pat.size - 1
      pre_splat_range = 0...(splat_index || s.pat.size)
      saw_var(s.pat[splat_index]) if splat_index

      s.x = localize(nil, s.x)
      emit "if #{s.x}.is_a?(Array)"

      cond = splat_index ? "#{s.x}.size >= #{s.pat.size - 1}" : "#{s.x}.size == #{s.pat.size}"
      test(s, cond) do

        pre_splat_range.each do |i|
          item_pat = s.pat[i]
          x = localize(item_pat, "#{s.x}[#{i}]")
          match(Frame.new(item_pat, x, s.env, s))
        end

        if splat_index
          splat_range = get_temp("splat_range")
          post_splat_width = s.pat.size - splat_index - 1
          emit "#{splat_range} = #{splat_index}...(#{s.x}.size#{post_splat_width > 0 ? "- #{post_splat_width}" : ""})"
          bind(s, s.pat[splat_index], "#{s.x}[#{splat_range}]")

          post_splat_pat_range = ((splat_index + 1)...s.pat.size)
          post_splat_pat_range.each do |i|
            item_pat = s.pat[i]
            x = localize(item_pat, "#{s.x}[-#{s.pat.size - i}]")
            match(Frame.new(item_pat, x, s.env, s))
          end
        end
      end

      emit "elsif #{s.x}.is_a?(Enumerable)"

      en = get_temp("en")
      done = get_temp("done")
      stopped = get_temp("stopped")
      emit "#{en} = #{s.x}.each"
      emit "#{done} = false"
      emit "begin"

      s.pat[0...(splat_index || s.pat.size)].each do |item_pat|
        x = localize(item_pat, "#{en}.next")
        match(Frame.new(item_pat, x, s.env, s))
      end

      if splat_index
        splat = get_temp("splat")
        emit "#{splat} = []"
        if is_closed
          splat_len = get_temp("splat_len")
          emit "#{splat_len} = #{s.x}.size - #{s.pat.size - 1}"
          emit "#{splat_len}.times do "
          emit "#{splat} << #{en}.next"
          emit "end"
          bind(s, s.pat[splat_index], splat)

          s.pat[(splat_index+1)...(s.pat.size)].each do |item_pat|
            x = localize(item_pat, "#{en}.next")
            match(Frame.new(item_pat, x, s.env, s))
          end
        else
          bind(s, s.pat[splat_index], "#{en}.new_from_here")
        end
      end

      emit "#{done} = true"
      emit "#{en}.next" if is_closed
      emit "rescue StopIteration"
      emit "#{stopped} = true"
      test(s, done)
      emit "end"
      test(s, stopped) if is_closed

      emit "else"
      test(s, "nil")
      emit "end"
    end

    def in_or(s)
      !s.nil? && (s.type == :or || in_or(s.parent))
    end

    def match_literal(s)
      s.type = :literal
      test(s, "#{s.x} == #{s.pat.inspect}")
    end

    def test(s, cond)
      # emit "puts \"line #{emitted_line_count + 8}: \#{#{cond.inspect}}\""
      # emit "puts \"test: \#{#{cond.inspect}}\""
      if in_or(s)
        update = "#{s.env} = (#{cond}) ? #{s.env} : nil if #{s.env}"
        if block_given?
          emit "if (#{update})"
          yield
          emit "end"
        else
          emit update
        end
      else
        emit "#{cond} or return nil"
        yield if block_given?
      end
    end

    def match_var(s)
      s.type = :var
      bind(s, s.pat, s.x)
    end

    def bind(s, var, val, val_could_be_unbound=false)
      current_val = get_temp("current_val")
      proposed_val = get_temp("proposed_val")
      require_outer_check = in_or(s) || val_could_be_unbound
      emit <<~CODE
        # bind #{var.name}
      #{proposed_val} = #{val}
        #{require_outer_check ? "if #{s.env} #{val_could_be_unbound ? "&& #{proposed_val} != :__unbound__" : ""}" : ""} 
      #{s.env} = _make_env.() if #{s.env} == true
          #{current_val} = #{s.env}.#{var.name}
          if #{current_val} == :__unbound__
            #{s.env}.#{var.name} = #{proposed_val}
          elsif #{current_val} != #{proposed_val}
      #{s.env} = nil
          end
        #{require_outer_check ? "end" : ""}
      CODE
      test(s, "#{s.env}")
    end

    def match_obj(s)
      s.type = :obj
      test(s, "#{s.x}.is_a?(#{get_ref(s.pat.type)})") do
        s.pat.fields.each do |field_name, field_pat|
          x = localize(field_pat, "#{s.x}.#{field_name}", field_name)
          match(Frame.new(field_pat, x, s.env, s))
        end
      end
    end

    def multi?(pat)
      pat.is_a?(Or) ||
          (pat.is_a?(Array) && pat.size > 1) ||
          pat.is_a?(Obj) && pat.fields.any?
    end

    def match_or(s)
      s.type = :or
      closers = []
      or_env = get_temp("env")
      emit "#{or_env} = true"
      s.pat.patterns.each_with_index do |alt, i|
        match(Frame.new(alt, s.x, or_env, s))
        if i < s.pat.patterns.size - 1
          emit "unless #{or_env}"
          closers << proc { emit "end" }
          emit "#{or_env} = true"
        end
      end
      closers.each(&:call)
      # emit "#{s.env} = ::Destruct::Env.merge!(#{s.env}, #{or_env})"
      merge(s, or_env)
      emit "#{s.env} or return nil" if !in_or(s.parent)
    end

    def merge(s, other_env)
      emit <<~CODE
        if #{s.env}.nil? || #{other_env}.nil?
          #{s.env} = nil
        elsif #{s.env} == true
          #{s.env} = #{other_env}
        elsif #{other_env} != true
      CODE
      @vars.each do |var|
        bind(s, var, "#{other_env}.#{var.name}", true)
      end
      emit "end"
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

    def self.show_code(code, refs, fancy: true, include_vm: false)
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
      if include_vm
        pp RubyVM::InstructionSequence.compile(code).to_a
      end
    end

    def self.number_lines(code)
      code.split("\n").each_with_index.map do |line, n|
        "#{(n + 1).to_s.rjust(3)} #{line}"
      end
    end

    private

    def localize(pat, x, prefix="t")
      if (pat.nil? && x =~ /\.\[\]/) || multi?(pat)
        t = get_temp(prefix)
        emit "#{t} = #{x}"
        x = t
      end
      x
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
