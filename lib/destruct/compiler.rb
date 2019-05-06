# frozen_string_literal: true

require "pp"
require_relative './types'
require_relative './rbeautify'
require_relative './code_gen'
require_relative './rule_set'
require "set"
require "stringio"

RubyVM::InstructionSequence.load_from_binary(File.read("boot1")).eval

module Backport
  refine Object do
    def then
      yield(self)
    end
  end
end

class Destruct
  class Compiler
    include CodeGen
    using Backport

    class << self
      def compile(pat)
        if pat.is_a?(CompiledPattern)
          pat
        else
          compiled_patterns.fetch(pat) do # TODO: consider caching by object_id
            compiled_patterns[pat] = begin
              cp = Compiler.new.compile(pat)
              on_compile_handlers.each { |h| h.(pat) }
              cp
            end
          end
        end
      end

      def compiled_patterns
        Thread.current[:__destruct_compiled_patterns__] ||= {}
      end

      def match(pat, x)
        compile(pat).match(x)
      end

      def on_compile(&block)
        on_compile_handlers << block
      end

      private def on_compile_handlers
        @on_compile_handlers ||= []
      end
    end

    Frame = Struct.new(:pat, :x, :env, :parent)

    MakeEnv = make_singleton("#<MakeEnv>")

    Form = Struct.new(:type, :children)
    class Form
      def initialize(type, *children)
        self.type = type
        self.children = children
      end

      def to_s
        if type == :ident
          "❲#{children.first}❳"
        else
          "(#{type} #{children.map { |c| c.is_a?(Form) ? c.to_s : c.inspect }.join(" ")})"
        end
      end
    end

    def self.pretty_sexp(x)
      require 'open3'
      Open3.popen3("scheme -q") do |i, o, e, t|
        i.write "(pretty-print '#{to_sexp(x)})"
        i.close
        return o.read
      end
    end

    def self.to_sexp(x)
      destruct(x) do
        if match { form(:ident, name) }
          name.to_s
        elsif match { form(:lambda, args, body) }
          "(lambda (#{args.map { |a| to_sexp(a) }.join(" ")}) #{to_sexp(body)})"
        elsif match { form(:let, var, val, body) }
          "(let ([#{to_sexp(var)} #{to_sexp(val)}]) #{to_sexp(body)})"
        elsif match { form(type, ~children) }
          "(#{type} #{children.map { |c| to_sexp(c) }.join(" ")})"
        elsif x.is_a?(Array)
          "#(#{x.map { |c| to_sexp(c) }.join(" ")})"
        elsif x.is_a?(Symbol)
          "'#{x}"
        elsif x == MakeEnv
          "(make-env)"
        else
          x.inspect
        end
      end
    end

    class CompilerPatternRules
      include Boot1::Destruct::RuleSet

      def initialize
        meta_rule_set Boot1::Destruct::RuleSets::AstToPattern
        add_rule(-> { form(type, *children) }) do |type:, children:|
          Boot1::Destruct::Obj.new(Form, type: type, children: children)
        end
        add_rule_set(Boot1::Destruct::RuleSets::StandardPattern)
      end

      def validate(x)
        Boot1::Destruct::RuleSets::PatternValidator.validate(x)
      end
    end

    def ident(prefix = "t")
      Form.new(:ident, get_temp(prefix).to_sym)
    end

    def initialize
      @known_real_envs ||= Set.new
    end

    def compile(pat)
      @var_counts = var_counts(pat)
      @var_names = @var_counts.keys
      if @var_names.any?
        get_ref(Destruct::Env.new_class(*@var_names).method(:new), "_make_env")
      end

      x = ident("x")
      binding = ident("binding")
      emit_lambda(ident_name(x), ident_name(binding)) do
        show_code_on_error do
          c = _apply(matcher(pat), x, true, binding).tap(&print_pass("initial"))
          c = normalize(c).tap(&print_pass("normalize"))
          c = inline(c).tap(&print_pass("inline"))
          c = fixed_point(c) do |c|
            c = remove_redundant_tests(c).then(&method(:inline)).tap(&print_pass("remove_redundant_tests"))
            fold_bool(c).tap(&print_pass("fold_bool"))
          end
          if Destruct.optimize
            # c = squash_begins(c).tap(&print_pass("squash_begins"))
            # c = remove_redundant_tests(c).tap(&print_pass("remove_redundant_tests"))
            # c = inline_stuff(c).tap(&print_pass("inline_stuff"))
            # c = squash_begins(c).tap(&print_pass("squash_begins"))
          end
          # c = normalize(c).tap(&print_pass("normalize"))
          c = emit3(c)
          emit c
        end
      end
      g = generate("Matcher for: #{pat.inspect.gsub(/\s+/, " ")}")
      CompiledPattern.new(pat, g, @var_names)
    end

    def fixed_point(x)
      last_x = Object.new
      while x != last_x
        last_x = x
        x = yield(x)
      end
      x
    end

    def print_pass(name)
      proc { |c| puts "#{name}:\n#{Compiler.pretty_sexp(c)}\n" if Destruct.print_passes }
    end

    def map_form(x)
      if x.is_a?(Form)
        recurse = proc do |method_name, &map_child|
          block = map_child || method(method_name)
          Form.new(x.type, *x.children.map(&block))
        end
        yield recurse
      else
        x
      end
    end

    def ident_name(ident)
      ident.children[0]
    end

    def normalize(x)
      map_form(x) do |recurse|
        destruct(x) do
          if match { form(:apply, form(:lambda, params, body), ~args) }
            params.size == args.size or raise "mismatched params/args: #{params} #{args}"
            if params.none?
              normalize(body)
            else
              var, *vars = params
              val, *vals = args
              _let(var, val, normalize(_apply(_lambda(vars, body), *vals)))
            end
          elsif match { form(:if, cond, cons, alt) }
            tval = ident?(cond) ? cond : ident
            _let(tval, normalize(cond),
                 _if(tval, normalize(cons), normalize(alt)))
          else
            recurse.call(:normalize)
          end
        end
      end
    end

    def inline(x)
      map_form(x) do |recurse|
        destruct(x) do
          if match { form(:let, var, val, body) } && inlineable?(var, val, body)
            inline(inline_ident(var, val, body))
          else
            recurse.call(:inline)
          end
        end
      end
    end

    def inlineable?(var, val, body)
      literal_val?(val) ||
          ident?(val) ||
          (ident_count(var, body) <= 1 && (can_be_condition?(val) || !appears_in_if_condition(var, body)))
    end

    def can_be_condition?(x)
      !x.is_a?(Form) || (%i[and or ident equal? not_equal? not array_get is_type get_field].include?(x.type) && x.children.all? { |c| can_be_condition?(c) })
    end

    def ident_count(var, x)
      if x == var
        1
      elsif x.is_a?(Form)
        x.children.map { |c| ident_count(var, c) }.reduce(:+)
      else
        0
      end
    end

    def appears_in_if_condition(var, x)
      destruct(x) do
        if match { form(:if, !var, _, _) }
          true
        elsif match { form(:if, _, cons, alt) }
          appears_in_if_condition(var, cons) || appears_in_if_condition(var, alt)
        elsif x.is_a?(Form)
          x.children.any? { |c| appears_in_if_condition(var, c) }
        else
          false
        end
      end
    end

    def inline_ident(var, val, x)
      map_form(x) do |recurse|
        x == var ? val : recurse.call { |c| inline_ident(var, val, c) }
      end
    end

    def lambda?(x)
      x.is_a?(Form) && x.type == :lambda
    end

    def ident?(x)
      x.is_a?(Form) && x.type == :ident
    end

    def fold_bool(x)
      map_form(x) do |recurse|
        destruct(x) do
          if match { form(:equal?, lhs, rhs) }
            lhs == rhs ? true : x
          elsif match { form(:not, true) }
            false
          elsif match { form(:not, false) }
            true
          elsif match { form(:not, form(:not, exp)) }
            fold_bool(exp)
          elsif match { form(:not, form(:equal?, lhs, rhs)) }
            fold_bool(_not_equal?(lhs, rhs))
          elsif match { form(:not, form(:not_equal?, lhs, rhs)) }
            fold_bool(_equal?(lhs, rhs))
          else
            recurse.call(:fold_bool)
          end
        end
      end
    end

    # remove redundant tests
    def remove_redundant_tests(x)
      map_form(x) do |recurse|
        destruct(x) do
          if match { form(:if, cond, true, false | nil) }
            remove_redundant_tests(cond)
          elsif match { form(:if, cond, false | nil, true) }
            remove_redundant_tests(_not(cond))
          elsif match { form(:if, true, cons, _) }
            remove_redundant_tests(cons)
          elsif match { form(:if, false, _, alt) }
            remove_redundant_tests(alt)
          elsif match { form(:and) }
            true
          elsif match { form(:and, v) }
            remove_redundant_tests(v)
          elsif match { form(:and, ~children) } && children.any? { |c| c == true }
            remove_redundant_tests(_and(*children.reject { |c| c == true }))
          else
            recurse.call(:remove_redundant_tests)
          end
        end
      end
    end

    # inline stuff
    def inline_stuff(x)
      counts = Hash.new { |h, k| h[k] = 0 }
      map = {}
      count_refs!(x, counts, map)
      map.delete_if { |k, _| counts[k] > 1 }
      inline(x, map)
    end

    # def inline(x, map)
    #   map_form(x) do |recurse|
    #     destruct(x) do
    #       if match { form(:set!, lhs, _) } && map.keys.include?(lhs)
    #         _noop
    #       elsif match { form(:ident, _) }
    #         map.fetch(x, x)
    #       else
    #         recurse.call { |c| inline(c, map) }
    #       end
    #     end
    #   end
    # end

    # def count_refs!(x, counts, map)
    #   map_form(x) do |recurse|
    #     destruct(x) do
    #       if match { form(:set!, lhs, rhs) }
    #         map[lhs] = rhs
    #         count_refs!(rhs, counts, map)
    #       elsif match { form(:ident, _) }
    #         counts[x] += 1
    #       else
    #         recurse.call { |c| count_refs!(c, counts, map) }
    #       end
    #     end
    #   end
    #   nil
    # end

    def squash_begins(x)
      map_form(x) do |recurse|
        if x.type == :begin
          squashed_children =
              x.children
                  .map { |c| squash_begins(c) }
                  .reject { |c| c.is_a?(Form) && c.type == :begin && c.children.none? }
          if squashed_children.size == 1
            squashed_children.first
          else
            _begin(*squashed_children)
          end
        else
          recurse.call { |c| squash_begins(c) }
        end
      end
    end

    def literal_val?(x)
      [TrueClass, FalseClass, NilClass, Numeric, String, Symbol, Module].any? { |c| x.is_a?(c) }
    end

    def literal_pattern
      @literal_pattern ||= any(true, false, nil, is_a(Numeric), is_a(String), is_a(Symbol))
    end

    def any(*pats)
      Boot1::Destruct::Or.new(*pats)
    end

    def is_a(klass)
      Boot1::Destruct::Obj.new(klass)
    end

    def denest_let(x)
      map_form(x) do |recurse|
        destruct(x) do
          if match { form(:let, var, val, body) }
            t = ident
            _begin(_set!(t, val),
                   _let(var, t, body))
          else
            recurse.call(:let_to_set)
          end
        end
      end
    end

    def continue_with(x, &k)

    end

    def _set!(var, val)
      Form.new(:set!, var, val)
    end

    def emit3(x)
      destruct(x) do
        case
        when match { form(:let, var, val, body) }
          if contains_forms?(%i(if let begin), val)
            "#{eref(var)} = begin\n#{emit3(val)}\nend\n#{emit3(body)}"
          else
            "#{eref(var)} = #{emit3(val)}\n#{emit3(body)}"
          end
        when match { form(:if, cond, cons, alt) }
          ["if #{emit3(cond)}",
           emit3(cons),
           "else",
           emit3(alt),
           "end"].join("\n")
        when match { form(:equal?, lhs, rhs) }
          "#{emit3(lhs)} == #{emit3(rhs)}"
        when match { form(:not_equal?, lhs, rhs) }
          "#{emit3(lhs)} != #{emit3(rhs)}"
        when match { form(:ident, _) }
          eref(x).to_s
        when match { form(:begin, ~children) }
          children.map { |x| emit3(x) }.join
        when match { form(:and, ~children) }
          children.map { |c| maybe_parenthesize(c) }.join(" && ")
        when match { form(:or, ~children) }
          children.map { |c| maybe_parenthesize(c) }.join(" || ")
        when match { form(:not, x) }
          "!(#{maybe_parenthesize(x.children.first)})"
        when match { form(:set_field, recv, meth, val) }
          "#{emit3(recv)}.#{meth} = #{emit3(val)}\n"
        when match { form(:get_field, recv, meth) }
          "#{emit3(recv)}.#{meth}"
        when match { form(:array_get, arr, index) }
          "#{emit3(arr)}[#{emit3(index)}]"
        when match { form(:is_type, recv, klass) }
          "#{emit3(recv)}.is_a?(#{emit3(klass)})"
        when match { Form[] }
          raise "emit3: unexpected: #{x}"
        when match(MakeEnv)
          "_make_env.()"
        else
          eref(x)
        end
      end
    end

    def contains_forms?(fs, x)
      x.is_a?(Form) && (fs.include?(x.type) || x.children.any? { |c| contains_forms?(fs, c) })
    end

    def maybe_parenthesize(x)
      if x.is_a?(Form) && %i(and or).include?(x.type)
        "(#{emit3(x)})"
      else
        emit3(x)
      end
    end

    def multival(ss)
      if ss.size == 1
        ss.first
      else
        "(#{ss.join("; ")})"
      end
    end

    def eref(x)
      if ident?(x)
        ident_name(x)
      elsif literal_val?(x)
        x.inspect
      else
        if Destruct.debug_compile
          raise "eref: unexpected: #{x.class} : #{x}"
        else
          get_ref(x)
        end
      end
    end

    def self.destruct_instance
      Thread.current[:__compiler_destruct_instance__] ||= Boot1::Destruct.new(CompilerPatternRules)
    end

    def self.destruct(value, &block)
      destruct_instance.destruct(value, &block)
    end

    def destruct(value, &block)
      Compiler.destruct(value, &block)
    end

    def matcher(pat)
      destruct(pat) do
        if pat.is_a?(Var)
          var_matcher(pat)
        elsif pat.is_a?(Array)
          array_matcher(pat)
        else
          value_matcher(pat)
        end
      end
    end

    def array_matcher(pat)
      x = ident("x")
      env = ident("env")
      binding = ident("binding")
      _lambda([x, env, binding],
              _if(_or(_not(_is_type(x, Array)),
                      _not_equal?(_get_field(x, :size), pat.size)),
                  nil,
                  array_matcher_helper(pat, x, env, binding)))
    end

    def array_matcher_helper(pat, x, env, binding, index = 0)
      if pat.none?
        env
      else
        new_env = ident("env")
        v = ident("v")
        _let(v, _array_get(x, index),
             _let(new_env, _apply(matcher(pat.first), v, env, binding),
                  _if(_not(new_env),
                      nil,
                      array_matcher_helper(pat.drop(1), x, new_env, binding, index + 1))))
      end
    end

    def var_matcher(pat)
      x = ident("x")
      env = ident("env")
      binding = ident("binding")
      _lambda([x, env, binding],
              bind(env, pat.name, x))
    end

    def bind(env, sym, x)
      new_env = ident("new_env")
      _if(_not(env),
          env,
          _if(_equal?(env, true),
              _let(new_env, make_env,
                   bind_with_new_env(new_env, sym, x)),
              bind_with_full_env(env, sym, x)))
    end

    # "full" means an Env object as opposed to `true`
    def bind_with_full_env(env, sym, x)
      existing = ident("existing")
      _let(existing, _get_field(env, sym),
           _if(_equal?(existing, Env::UNBOUND),
               _begin(_set_field(env, sym, x),
                      env),
               _if(_not(_equal?(existing, x)),
                   nil,
                   env)))
    end

    # a new env is guaranteed to have no symbols bound, thus no conflicts
    def bind_with_new_env(env, sym, x)
      _begin(_set_field(env, sym, x),
             env)
    end

    def _let(var, val, body)
      Form.new(:let, var, val, body)
    end

    def make_env
      MakeEnv
    end

    def _is_type(x, klass)
      Form.new(:is_type, x, klass)
    end

    def _set_field(recv, meth, val)
      Form.new(:set_field, recv, meth, val)
    end

    def _get_field(recv, meth)
      Form.new(:get_field, recv, meth)
    end

    def _array_get(arr, index)
      Form.new(:array_get, arr, index)
    end

    def _noop
      _begin
    end

    def _begin(*xs)
      Form.new(:begin, *xs)
    end

    def value_matcher(pat)
      x = ident("x")
      env = ident("env")
      binding = ident("binding")
      _lambda([x, env, binding], _if(_not(_and(env, _equal?(x, pat))), nil, env))
    end

    def _and(*clauses)
      Form.new(:and, *clauses)
    end

    def _or(*clauses)
      Form.new(:or, *clauses)
    end

    def _apply(proc, *args)
      Form.new(:apply, proc, *args)
    end

    def _lambda(params, body)
      Form.new(:lambda, params, body)
    end

    def _if(cond, cons, alt)
      Form.new(:if, cond, cons, alt)
    end

    def _equal?(lhs, rhs)
      Form.new(:equal?, lhs, rhs)
    end

    def _not_equal?(lhs, rhs)
      Form.new(:not_equal?, lhs, rhs)
    end

    def _not(x)
      Form.new(:not, x)
    end

    def var_counts(pat)
      find_var_names_non_uniq(pat).group_by(&:itself).map { |k, vs| [k, vs.size] }.to_h
    end

    def find_var_names_non_uniq(pat)
      if pat.is_a?(Obj)
        pat.fields.values.flat_map(&method(:find_var_names_non_uniq))
      elsif pat.is_a?(Or)
        @has_or = true
        pat.patterns.flat_map(&method(:find_var_names_non_uniq))
      elsif pat.is_a?(Let)
        [pat.name, *find_var_names_non_uniq(pat.pattern)]
      elsif pat.is_a?(Binder)
        [pat.name]
      elsif pat.is_a?(Hash)
        pat.values.flat_map(&method(:find_var_names_non_uniq))
      elsif pat.is_a?(Array)
        pat.flat_map(&method(:find_var_names_non_uniq))
      elsif pat.is_a?(Regexp)
        pat.named_captures.keys.map(&:to_sym)
      elsif pat.is_a?(Strict)
        find_var_names_non_uniq(pat.pat)
      else
        []
      end
    end

    def match(s)
      if s.pat == Any
        # do nothing
      elsif s.pat.is_a?(Obj)
        match_obj(s)
      elsif s.pat.is_a?(Or)
        match_or(s)
      elsif s.pat.is_a?(Let)
        match_let(s)
      elsif s.pat.is_a?(Var)
        match_var(s)
      elsif s.pat.is_a?(Unquote)
        match_unquote(s)
      elsif s.pat.is_a?(Hash)
        match_hash(s)
      elsif s.pat.is_a?(Array)
        match_array(s)
      elsif s.pat.is_a?(Regexp)
        match_regexp(s)
      elsif s.pat.is_a?(Strict)
        match_strict(s)
      elsif is_literal_val?(s.pat)
        match_literal(s)
      elsif match_other(s)
      end
    end

    # def is_literal_val?(x)
    #   x.is_a?(Numeric) || x.is_a?(String) || x.is_a?(Symbol)
    # end

    def is_literal_pat?(p)
      !(p.is_a?(Obj) ||
          p.is_a?(Or) ||
          p.is_a?(Binder) ||
          p.is_a?(Unquote) ||
          p.is_a?(Hash) ||
          p.is_a?(Array))
    end

    def pattern_order(p)
      # check the cheapest or most likely to fail first
      if is_literal_pat?(p)
        0
      elsif p.is_a?(Or) || p.is_a?(Regexp)
        2
      elsif p.is_a?(Binder)
        3
      elsif p.is_a?(Unquote)
        4
      else
        1
      end
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

      s.x = localize(nil, s.x)
      known_real_envs_before = @known_real_envs.dup
      emit_if "#{s.x}.is_a?(Array)" do
        cond = splat_index ? "#{s.x}.size >= #{s.pat.size - 1}" : "#{s.x}.size == #{s.pat.size}"
        test(s, cond) do

          pre_splat_range
              .map { |i| [s.pat[i], i] }
              .sort_by { |(item_pat, i)| [pattern_order(item_pat), i] }
              .each do |item_pat, i|
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
      end.elsif "#{s.x}.is_a?(Enumerable)" do
        @known_real_envs = known_real_envs_before
        en = get_temp("en")
        done = get_temp("done")
        stopped = get_temp("stopped")
        emit "#{en} = #{s.x}.each"
        emit "#{done} = false"
        emit_begin do
          s.pat[0...(splat_index || s.pat.size)].each do |item_pat|
            x = localize(item_pat, "#{en}.next")
            match(Frame.new(item_pat, x, s.env, s))
          end

          if splat_index
            if is_closed
              splat = get_temp("splat")
              emit "#{splat} = []"
              splat_len = get_temp("splat_len")
              emit "#{splat_len} = #{s.x}.size - #{s.pat.size - 1}"
              emit "#{splat_len}.times do"
              emit "#{splat} << #{en}.next"
              emit "end"
              bind(s, s.pat[splat_index], splat)

              s.pat[(splat_index + 1)...(s.pat.size)].each do |item_pat|
                x = localize(item_pat, "#{en}.next")
                match(Frame.new(item_pat, x, s.env, s))
              end
            else
              bind(s, s.pat[splat_index], "#{en}.new_from_here")
            end
          end

          emit "#{done} = true"
          emit "#{en}.next" if is_closed
        end.rescue "StopIteration" do
          emit "#{stopped} = true"
          test(s, done)
        end.end
        test(s, stopped) if is_closed
      end.else do
        test(s, "nil")
      end
    end

    def in_or(s)
      !s.nil? && (s.type == :or || in_or(s.parent))
    end

    def in_strict(s)
      !s.nil? && (s.pat.is_a?(Strict) || in_strict(s.parent))
    end

    def match_regexp(s)
      s.type = :regexp
      m = get_temp("m")
      match_env = get_temp("env")
      test(s, "#{s.x}.is_a?(String) || #{s.x}.is_a?(Symbol)") do
        emit "#{m} = #{get_ref(s.pat)}.match(#{s.x})"
        emit "#{match_env} = Destruct::Env.new(#{m}) if #{m}"
        test(s, match_env)
        merge(s, match_env, dynamic: true)
      end
    end

    def match_strict(s)
      match(Frame.new(s.pat.pat, s.x, s.env, s))
    end

    def match_literal(s)
      s.type = :literal
      test(s, "#{s.x} == #{s.pat.inspect}")
    end

    def match_other(s)
      s.type = :other
      test(s, "#{s.x} == #{get_ref(s.pat)}")
    end

    # def test(s, cond)
    #   # emit "puts \"line #{emitted_line_count + 8}: \#{#{cond.inspect}}\""
    #   emit "puts \"test: \#{#{cond.inspect}}\"" if $show_tests
    #   if in_or(s)
    #     emit "#{s.env} = (#{cond}) ? #{s.env} : nil if #{s.env}"
    #     if block_given?
    #       emit_if s.env do
    #         yield
    #       end.end
    #     end
    #   elsif cond == "nil" || cond == "false"
    #     emit "return nil"
    #   else
    #     emit "#{cond} or return nil"
    #     yield if block_given?
    #   end
    # end

    def match_var(s)
      s.type = :var
      test(s, "#{s.x} != #{nothing_ref}")
      bind(s, s.pat, s.x)
    end

    def match_unquote(s)
      temp_env = get_temp("env")
      emit "raise 'binding must be provided' if _binding.nil?"
      emit "#{temp_env} = Destruct.match((_binding.respond_to?(:call) ? _binding.call : _binding).eval('#{s.pat.code_expr}'), #{s.x}, _binding)"
      test(s, temp_env)
      merge(s, temp_env, dynamic: true)
    end

    def match_let(s)
      s.type = :let
      match(Frame.new(s.pat.pattern, s.x, s.env, s))
      bind(s, s.pat, s.x)
    end

    def bind_old(s, var, val, val_could_be_unbound_sentinel = false)
      var_name = var.is_a?(Binder) ? var.name : var

      # emit "# bind #{var_name}"
      proposed_val =
          if val_could_be_unbound_sentinel
            # we'll want this in a local because the additional `if` clause below will need the value a second time.
            pv = get_temp("proposed_val")
            emit "#{pv} = #{val}"
            pv
          else
            val
          end

      do_it = proc do
        unless @known_real_envs.include?(s.env)
          # no need to ensure the env is real (i.e., an Env, not `true`) if it's already been ensured
          emit "#{s.env} = _make_env.() if #{s.env} == true"
          @known_real_envs.add(s.env) unless in_or(s)
        end
        current_val = "#{s.env}.#{var_name}"
        if @var_counts[var_name] > 1
          # if the pattern binds the var in two places, we'll have to check if it's already bound
          emit_if "#{current_val} == :__unbound__" do
            emit "#{s.env}.#{var_name} = #{proposed_val}"
          end.elsif "#{current_val} != #{proposed_val}" do
            if in_or(s)
              emit "#{s.env} = nil"
            else
              test(s, "nil")
            end
          end.end
        else
          # otherwise, this is the only place we'll attempt to bind this var, so just do it
          emit "#{current_val} = #{proposed_val}"
        end
      end

      if in_or(s)
        emit_if("#{s.env}", &do_it).end
      elsif val_could_be_unbound_sentinel
        emit_if("#{s.env} && #{proposed_val} != :__unbound__", &do_it).end
      else
        do_it.()
      end

      test(s, "#{s.env}") if in_or(s)
    end

    def match_obj(s)
      s.type = :obj
      match_hash_or_obj(s, get_ref(s.pat.type), s.pat.fields, proc { |field_name| "#{s.x}.#{field_name}" })
    end

    def match_hash(s)
      s.type = :hash
      match_hash_or_obj(s, "Hash", s.pat, proc { |field_name| "#{s.x}.fetch(#{field_name.inspect}, #{nothing_ref})" },
                        "#{s.x}.keys.sort == #{get_ref(s.pat.keys.sort)}")
    end

    def nothing_ref
      get_ref(Destruct::NOTHING)
    end

    def match_hash_or_obj(s, type_str, pairs, make_x_sub, strict_test = nil)
      test(s, "#{s.x}.is_a?(#{type_str})") do
        keep_matching = proc do
          pairs
              .sort_by { |(_, field_pat)| pattern_order(field_pat) }
              .each do |field_name, field_pat|
            x = localize(field_pat, make_x_sub.(field_name), field_name)
            match(Frame.new(field_pat, x, s.env, s))
          end
        end

        if in_strict(s) && strict_test
          test(s, strict_test) { keep_matching.call }
        else
          keep_matching.call
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
      merge(s, or_env)
      emit "#{s.env} or return nil" if !in_or(s.parent)
    end

    def merge(s, other_env, dynamic: false)
      @known_real_envs.include?(s.env)

      emit_if("#{s.env}.nil? || #{other_env}.nil?") do
        emit "#{s.env} = nil"
      end.elsif("#{s.env} == true") do
        emit "#{s.env} = #{other_env}"
      end.elsif("#{other_env} != true") do
        if dynamic
          emit "#{other_env}.env_each do |k, v|"
          emit_if("#{s.env}[k] == :__unbound__") do
            emit "#{s.env}[k] = v"
          end.elsif("#{s.env}[k] != v") do
            if in_or(s)
              emit "#{s.env} = nil"
            else
              test(s, "nil")
            end
          end.end
          emit "end"
        else
          @var_names.each do |var_name|
            bind(s, var_name, "#{other_env}.#{var_name}", true)
          end
        end
      end.end
    end

    private

    def localize(pat, x, prefix = "t")
      prefix = prefix.to_s.gsub(/[^\w\d_]/, '')
      if (pat.nil? && x =~ /\.\[\]/) || multi?(pat) || (pat.is_a?(Binder) && x =~ /\.fetch|\.next/)
        t = get_temp(prefix)
        emit "#{t} = #{x}"
        x = t
      end
      x
    end
  end

  class Pattern
    attr_reader :pat

    def initialize(pat)
      @pat = pat
    end

    def to_s
      "#<Pattern #{pat}>"
    end

    alias_method :inspect, :to_s

    def match(x, binding = nil)
      Compiler.compile(pat).match(x, binding)
    end
  end

  class CompiledPattern
    attr_reader :pat, :generated_code, :var_names

    def initialize(pat, generated_code, var_names)
      @pat = pat
      @generated_code = generated_code
      @var_names = var_names
    end

    def match(x, binding = nil)
      @generated_code.proc.(x, binding)
    end

    def show_code
      generated_code.show
    end
  end
end

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
