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
                                       # begin
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

    EnvInfo = Struct.new(:bindings)

    module HasMeta
      def possible_values
        @possible_values ||= [] #[false, nil, :truthy]
      end

      def possible_values=(x)
        raise "oops" unless x.is_a?(Array)
        @possible_values = x
      end

      def with_possible_values(pvs)
        r = dup
        r.possible_values = pvs.uniq
        r
      end
    end

    Form = Struct.new(:type, :children)
    class Form
      include HasMeta

      def initialize(type, *children)
        self.type = type
        self.children = children
      end

      def to_s
        "(#{type} #{children.map { |c| c.is_a?(HasMeta) ? c.to_s : c.inspect }.join(" ")})"
      end
    end

    Ident = Struct.new(:name)
    class Ident
      include HasMeta

      def to_s
        name.to_s
      end
    end

    class MakeEnvClass
      include HasMeta

      def initialize
        @possible_values = [Compiler::EnvInfo.new([])]
      end

      def to_s
        "#<MakeEnv>"
      end
    end

    def self.pretty_sexp(x)
      require 'open3'
      refs = {}
      pretty = Open3.popen3("scheme -q") do |i, o, e, t|
        refs
        i.write "(pretty-line-length 140) (pretty-print '#{to_sexp(x, [], refs)})"
        i.close
        o.read
      end
      refs = refs.invert
      pretty.lines.map { |line| line.gsub(/\s+$/, '') }.map do |line|
        rs = line.scan(/:\d+/)
        "#{line.ljust(120,)} #{rs.map { |r| "#{r}: #{to_sexp(possible_values(ObjectSpace._id2ref(refs[r])), [], {}) }" }.join(', ') }"
      end.join("\n") + "\n"
    end

    def self.to_sexp(x, path, refs)
      get_ref = proc { |x| possible_values(x).any? ? refs.fetch(x.object_id) { refs[x.object_id] = ":#{refs.size}" } : "" }
      destruct(x) do
        if ident?(x)
          if x.possible_values.any?
            "#{x.name}#{get_ref.(x)}"
          else
            x.name.to_s
          end
        elsif match { form(:lambda, args, body) }
          "(lambda#{get_ref.(x)} (#{args.map { |a| to_sexp(a, epath(x, path), refs) }.join(" ")}) #{to_sexp(body, epath(x, path), refs)})"
        elsif match { form(:let, var, val, body) }
          "(let#{get_ref.(x)} ([#{to_sexp(var, epath(x, path), refs)} #{to_sexp(val, epath(x, path), refs)}]) #{to_sexp(body, epath(x, path), refs)})"
        elsif match { form(type, ~children) }
          "(#{type}#{get_ref.(x)} #{children.map { |c| to_sexp(c, epath(x, path), refs) }.join(" ")})"
        elsif x.is_a?(Array)
          "#(#{x.map { |c| to_sexp(c, epath(x, path), refs) }.join(" ")})"
        elsif x.is_a?(Symbol)
          "'#{x}"
        elsif x.is_a?(MakeEnvClass)
          "(make-env)"
        elsif x.is_a?(EnvInfo)
          "(EnvInfo #{to_sexp(x.bindings, [], refs)})"
        else
          x.inspect
        end
      end
    end

    def self.epath(x, ls)
      ls.dup.unshift(x)
    end

    def epath(x, ls)
      ls.dup.unshift(x)
    end

    class CompilerPatternRules
      include Boot1::Destruct::RuleSet

      def initialize
        meta_rule_set Boot1::Destruct::RuleSets::AstToPattern
        add_rule(-> { form(type, *children) }) do |type:, children:|
          Boot1::Destruct::Obj.new(Form, type: type, children: children)
        end
        add_rule(-> { ident(name) }) do |name:|
          Boot1::Destruct::Obj.new(Ident, name: name)
        end
        add_rule_set(Boot1::Destruct::RuleSets::StandardPattern)
      end

      def validate(x)
        Boot1::Destruct::RuleSets::PatternValidator.validate(x)
      end
    end

    def ident(prefix = "t")
      Ident.new(get_temp(prefix).to_sym)
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
          if Destruct.optimize
            c = inline(c).tap(&print_pass("inline"))
            c = fixed_point(c) do |c|
              c = flow_meta(c, []).tap(&print_pass("flow_meta"))
              c = remove_redundant_tests(c, []).then(&method(:inline)).tap(&print_pass("remove_redundant_tests"))
              c = fold_bool(c).tap(&print_pass("fold_bool"))
            end
          end
          c = flow_meta(c, []).tap(&print_pass("flow_meta"))
          c = emit_ruby(c)
          emit c
        end
      end
      g = generate("Matcher for: #{pat.inspect.gsub(/\s+/, " ")}")
      CompiledPattern.new(pat, g, @var_names)
    end

    def fixed_point(x, max_iters = $max_iters || 1000)
      last_x = Object.new
      while x != last_x && max_iters > 0
        last_x = x
        x = yield(x)
        max_iters -= 1
      end
      x
    end

    def print_pass(name)
      proc { |c| puts "#{name}:\n#{Compiler.pretty_sexp(c)}\n" if Destruct.print_passes }
    end

    def tx(x, method_name = nil, &block)
      if x.is_a?(Form)
        block ||= method(method_name)
        Form.new(x.type, *x.children.map(&block))
      else
        x
      end
    end

    def ident_name(ident)
      ident.name
    end

    def normalize(x)
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
          tx(x, :normalize)
        end
      end
    end

    def inline(x)
      destruct(x) do
        if match { form(:let, var, val, body) } && inlineable?(var, val, body)
          inline(inline_ident(var, val, body))
        elsif match { form(:get_field, recv, :dup) } && !recv.is_a?(HasMeta)
          recv
        else
          tx(x, :inline)
        end
      end
    end

    def inline_ident(var, val, x)
      x == var ? val : tx(x) { |c| inline_ident(var, val, c) }
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

    def lambda?(x)
      x.is_a?(Form) && x.type == :lambda
    end

    def self.ident?(x)
      x.is_a?(Ident)
    end

    def ident?(x)
      x.is_a?(Ident)
    end

    def not?(x)
      x.is_a?(Form) && x.type == :not
    end

    def env_bindings(x)
      possible_values(x).find { |pv| pv.is_a?(EnvInfo) }&.bindings || []
    end

    def possible_values(x)
      self.class.possible_values(x)
    end

    def self.possible_values(x)
      if x == true
        [true]
      elsif x == false
        [false]
      elsif x == nil
        [nil]
      elsif x.is_a?(HasMeta)
        x.possible_values
      else
        [] #[false, nil, :truthy]
      end
    end

    def flow_meta(x, let_bindings)
      destruct(x) do
        if match { form(:bind, env, sym, val) } && (env.is_a?(MakeEnvClass) || env.is_a?(Ident))
          new_env = flow_meta(env, let_bindings)
          new_val = flow_meta(val, let_bindings)
          new_env_bindings = (env_bindings(new_env) + [sym]).uniq
          new_possible_values = new_env.possible_values.reject { |pv| pv.is_a?(EnvInfo) } + [EnvInfo.new(new_env_bindings)]
          result = bind_form(new_env, sym, new_val).with_possible_values(new_possible_values)
          result
        elsif match { form(:let, var, val, body) }
          new_val = flow_meta(val, let_bindings)
          new_var = var.with_possible_values(possible_values(new_val))
          new_body = flow_meta(body, let_bindings + [new_var])
          _let(new_var, new_val, new_body).with_possible_values(possible_values(new_body))
        elsif match { form(:if, cond, cons, alt) }
          update_bindings = proc do |var, &update_pvs|
            let_bindings.map do |lb|
              if lb.name == var.name
                lb.with_possible_values(update_pvs.(lb.possible_values))
              else
                lb
              end
            end
          end
          if ident?(cond)
            id = cond
            new_cons_bindings = update_bindings.(id) do |pvs|
              pvs = pvs.reject { |pv| pv == false || pv == nil }
              pvs.none? ? [:truthy] : pvs
            end
            new_alt_bindings = update_bindings.(id) { [false, nil] }
          elsif not?(cond) && ident?(cond.children[0])
            id = cond.children[0]
            new_cons_bindings = update_bindings.(id) { [false, nil] }
            new_alt_bindings = update_bindings.(id) do |pvs|
              pvs = pvs.reject { |pv| pv == false || pv == nil }
              pvs.none? ? [:truthy] : pvs
            end
          else
            new_cons_bindings = let_bindings
            new_alt_bindings = let_bindings
          end
          new_cond = flow_meta(cond, let_bindings)
          new_cons = flow_meta(cons, new_cons_bindings)
          new_alt = flow_meta(alt, new_alt_bindings)
          new_possible_values = merge_possible_values(possible_values(new_cons), possible_values(new_alt))
          _if(new_cond, new_cons, new_alt).with_possible_values(new_possible_values)
        elsif ident?(x) && let_bindings.include?(x)
          x.with_possible_values(possible_values(let_bindings.find { |lb| lb == x }))
        elsif match { form(:and, ~children) }
          new_children = children.map { |c| flow_meta(c, let_bindings) }
          pvs = possible_values(new_children.last)
          pvs = pvs.any? ? [*pvs, false, nil] : pvs
          _and(*new_children).with_possible_values(pvs)
        elsif match { form(:or, ~children) }
          new_children = children.map { |c| flow_meta(c, let_bindings) }
          pvs = merge_possible_values([false, nil], new_children.flat_map { |c| possible_values(c) })
          _or(*new_children).with_possible_values(pvs)
        elsif x.is_a?(Form)
          recurse = proc { Form.new(x.type, *x.children.map { |c| flow_meta(c, let_bindings) }) }
          if x.type == :equal?
            recurse.().with_possible_values([true, false])
          else
            recurse.()
          end
        else
          x
        end
      end
    end

    def merge_possible_values(pvs1, pvs2)
      if pvs1.none? || pvs2.empty?
        []
      else
        (pvs1 + pvs2).uniq
      end
    end

    def fold_bool(x)
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
        elsif match { form(:and, ~children) } && children.any? { |c| and?(c) }
          fold_bool(_and(*children.flat_map { |c| and?(c) ? c.children : [c] }))
        elsif match { form(:not, form(:or, ~children)) } && children.size > 1
          fold_bool(_and(*children.map { |c| _not(c) }))
        elsif match { form(:not, form(:and, ~children)) } && children.size > 1
          fold_bool(_or(*children.map { |c| _not(c) }))
        # elsif match { form(:if, id <= ident(_), id, alt) }
        #   trace_rule(x, "id ? id : alt => id || alt") do
        #     _or(id, fold_bool(alt))
        #   end
        elsif match { form(:or, ~clauses) } && clauses.all? { |c| and?(c) } &&
            clauses.map { |c| c.children[0] }.uniq.size == 1
          trace_rule(x, "factor common head clauses from ORed ANDs") do
            _and(fold_bool(clauses[0].children[0]), fold_bool(_or(*clauses.map { |c| _and(*c.children.drop(1)) })))
          end
        else
          tx(x, :fold_bool)
        end
      end
    end

    def and?(x)
      x.is_a?(Form) && x.type == :and
    end

    def known_truthy?(x)
      pvs = possible_values(x)
      pvs.any? { |pv| pv == true || pv == :truthy || pv.is_a?(EnvInfo) } &&
          pvs.none? { |pv| pv == false || pv == nil }
    end

    def known_true?(x)
      pvs = possible_values(x)
      pvs.any? { |pv| pv == true } &&
          pvs.none? { |pv| pv == false || pv == nil || pv.is_a?(EnvInfo) }
    end

    def known_falsey?(x)
      pvs = possible_values(x)
      pvs.any? { |pv| pv == false || pv == nil } &&
          pvs.none? { |pv| pv == true || pv == :truthy || pv.is_a?(EnvInfo) }
    end

    def known_env?(x)
      pvs = possible_values(x)
      pvs.size == 1 && pvs[0].is_a?(EnvInfo)
    end

    def known_not_env?(x)
      pvs = possible_values(x)
      pvs.size > 0 && pvs.none? { |pv| pv.is_a?(EnvInfo) }
    end

    def remove_redundant_tests(x, path)
      # puts "=> #{x}"
      path = epath(x, path)
      result = destruct(x) do
        if match { form(:if, cond, cons, alt) }
          if known_falsey?(cons) && !contains_complex_forms?(alt)
            trace_rule(x, "if => AND when known_falsey?(cons)") do
              _and(_not(remove_redundant_tests(cond, path)), remove_redundant_tests(alt, path))
            end
          elsif cons == true && known_falsey?(alt)
            trace_rule(x, "rrt2") do
              remove_redundant_tests(cond, path)
            end
          elsif alt == true && known_falsey?(cons)
            trace_rule(x, "rrt3") do
              remove_redundant_tests(_not(cond), path)
            end
          elsif known_truthy?(cond)
            trace_rule(x, "rrt4") do
              remove_redundant_tests(cons, path)
            end
          elsif known_falsey?(cond)
            trace_rule(x, "rrt5") do
              remove_redundant_tests(alt, path)
            end
          elsif ident?(cond) && cons == cond && known_falsey?(alt)
            trace_rule(x, "rrt6") do
              cond
            end
          elsif ident?(cond) && alt == cond && known_falsey?(cons)
            trace_rule(x, "rrt7") do
              cond
            end
          else
            tx(x) { |c| remove_redundant_tests(c, path) }
          end
        elsif match { form(:not, c) } && known_truthy?(c)
          trace_rule(x, "rrt8") do
            false
          end
        elsif match { form(:equal?, lhs, rhs) } && known_env?(lhs) && rhs == true
          trace_rule(x, "rrt9") do
            false
          end
        elsif match { form(:equal?, lhs, rhs) } && known_true?(lhs) && rhs == true
          trace_rule(x, "rrt10") do
            true
          end
        elsif match { form(:and) }
          trace_rule(x, "rrt11") do
            true
          end
        elsif match { form(:and, v) }
          trace_rule(x, "rrt12") do
            remove_redundant_tests(v, path)
          end
        elsif match { form(:and, ~children) } && has_redundant_and_children?(children)
          trace_rule(x, "rrt remove redundant AND children") do
            # If the last is an env, it's truthy but we can't eliminate it because it
            # becomes the value of the && expression
            new_children =
                (children.take(children.size - 1).reject { |c| known_truthy?(c) } +
                    children.drop(children.size - 1).reject { |c| c == true }).reverse.uniq.reverse
            remove_redundant_tests(_and(*new_children.map { |c| remove_redundant_tests(c, path) }), path)
          end
        elsif match { form(:get_field, obj, sym) } && known_not_env?(obj)
          trace_rule(x, "rrt known_not_env?(obj).get_field => :__unbound__") do
            :__unbound__
          end
        elsif match { form(:get_field, obj, sym) } && known_env?(obj)
          env_info = possible_values(obj)[0]
          if !env_info.bindings.include?(sym)
            :__unbound__
          else
            x
          end
        elsif match { form(:get_field, obj, sym) } && known_not_env?(obj)
          trace_rule(x, "rrt known_not_env?(obj).get_field => :__unbound__") do
            :__unbound__
          end
        elsif match { form(:let, id <= ident(_), form(:and, ~clauses, bound <= form(:bind, ~bc)),
                           form(:and, id, form(:bind, id, sym, val))) }
          trace_rule(x, "continue binding from let val to let body") do
            remove_redundant_tests(_and(*clauses, bind_form(bound, sym, val)), path)
          end
        else
          tx(x) { |c| remove_redundant_tests(c, path) }
        end
      end
      # puts "<= #{result}"
      result
    end

    def trace_rule(x, name)
      if !Destruct.print_np_transformations
        return yield
      end

      @trace_rule_depth ||= 0
      indent = ""
      begin
        @trace_rule_depth += 1
        result = yield
      ensure
        @trace_rule_depth -= 1
      end
      puts (name + " ").ljust(120, "-")
      puts "=> " + Compiler.pretty_sexp(x)
      puts "<= " + Compiler.pretty_sexp(result)
      result
    end

    def has_redundant_and_children?(children)
      children.take(children.size - 1).any? { |c| known_truthy?(c) } || children.last == true || contains_duplicates?(children)
    end

    def contains_duplicates?(xs)
      xs.uniq.size < xs.size
    end

    def contains_complex_forms?(x)
      contains_forms?(%i(if let begin), x)
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
        tx(x, :squash_begins)
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
      destruct(x) do
        if match { form(:let, var, val, body) }
          t = ident
          _begin(_set!(t, val),
                 _let(var, t, body))
        else
          tx(x, :let_to_set)
        end
      end
    end

    def _set!(var, val)
      Form.new(:set!, var, val)
    end

    # def remove_bind(x)
    #   destruct(x) do
    #     if match { form(:bind, env, sym, val) }
    #       if ident?(env)
    #         _begin(_set_field(env, sym, val), env)
    #       else
    #         t = ident("env")
    #         _let(t, remove_bind(env),
    #              _begin(_set_field(t, sym, val), t))
    #       end
    #     else
    #       tx(x, :remove_bind)
    #     end
    #   end
    # end

    def emit_ruby(x)
      destruct(x) do
        if match { form(:let, var, val, body) }
          if contains_complex_forms?(val)
            "#{eref(var)} = begin\n#{emit_ruby(val)}\nend\n#{emit_ruby(body)}"
          else
            "#{eref(var)} = #{emit_ruby(val)}\n#{emit_ruby(body)}"
          end
        elsif match { form(:if, cond, cons, alt) }
          ["if #{emit_ruby(cond)}",
           emit_ruby(cons),
           "else",
           emit_ruby(alt),
           "end"].join("\n")
        elsif match { form(:equal?, lhs, rhs) }
          "#{emit_ruby(lhs)} == #{emit_ruby(rhs)}"
        elsif match { form(:not_equal?, lhs, rhs) }
          "#{emit_ruby(lhs)} != #{emit_ruby(rhs)}"
        elsif ident?(x)
          eref(x).to_s
        elsif match { form(:begin, ~children) }
          children.map { |x| emit_ruby(x) }.join
        elsif match { form(:and, ~children) }
          children.map { |c| maybe_parenthesize(c) }.join(" && ")
        elsif match { form(:or, ~children) }
          children.map { |c| maybe_parenthesize(c) }.join(" || ")
        elsif match { form(:not, x) }
          "!(#{maybe_parenthesize(x.children.first)})"
        elsif match { form(:set_field, recv, meth, val) }
          "#{emit_ruby(recv)}.#{meth} = #{emit_ruby(val)}\n"
        elsif match { form(:get_field, recv, meth) }
          "#{emit_ruby(recv)}.#{meth}"
        elsif match { form(:array_get, arr, index) }
          "#{emit_ruby(arr)}[#{emit_ruby(index)}]"
        elsif match { form(:is_type, recv, klass) }
          "#{emit_ruby(recv)}.is_a?(#{emit_ruby(klass)})"
        elsif match { form(:bind, env, sym, val) }
          dot = known_truthy?(env) ? "." : "&."
          "#{emit_ruby(env)}#{dot}bind(#{emit_ruby(sym)}, #{emit_ruby(val)})"
        elsif match { Form[] }
          raise "emit3: unexpected: #{x}"
        elsif x.is_a?(MakeEnvClass)
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
      if x.is_a?(Form) && %i(and or if).include?(x.type)
        "(#{emit_ruby(x)})"
      else
        emit_ruby(x)
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
        elsif pat.is_a?(Or)
          or_matcher(pat)
        else
          value_matcher(pat)
        end
      end
    end

    def array_matcher(pat)
      x = ident("x")
      env = ident("env")
      binding = ident("binding")
      reordered_pat = pat.each_with_index.sort_by do |(p, i)|
        priority =
            if p.is_a?(Or)
              2
            elsif p.is_a?(Var)
              1
            else
              0
            end
        [priority, i]
      end
      _lambda([x, env, binding],
              _if(_or(_not(_is_type(x, Array)),
                      _not_equal?(_get_field(x, :size), pat.size)),
                  nil,
                  array_matcher_helper(reordered_pat, x, env, binding)))
    end

    def array_matcher_helper(pat_with_indexes, x, env, binding)
      if pat_with_indexes.none?
        env
      else
        (pat, index), *pat_rest = pat_with_indexes
        new_env = ident("env")
        v = ident("v")
        _let(v, _array_get(x, index),
             _let(new_env, _apply(matcher(pat), v, env, binding),
                  _if(_not(new_env),
                      nil,
                      array_matcher_helper(pat_rest, x, new_env, binding))))
      end
    end

    def or_matcher(pat)
      x = ident("x")
      env = ident("env")
      binding = ident("binding")
      _lambda([x, env, binding],
              or_matcher_helper(pat.patterns, x, env, binding))
    end

    def or_matcher_helper(pats, x, env, binding)
      if pats.none?
        nil
      else
        pat, *pats = pats
        new_env = ident("env")
        # or_env = might_bind?(pat) ? _get_field(env, :dup) : env
        _let(new_env, _apply(matcher(pat), x, env, binding),
             _if(new_env,
                 new_env,
                 or_matcher_helper(pats, x, env, binding)))
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
      new_env = ident("env")
      _if(_not(env),
          env,
          _if(_equal?(env, true),
              _let(new_env, make_env,
                   bind_form(new_env, sym, x)),
              bind_with_full_env(env, sym, x)))
    end

    # "full" means an Env object as opposed to `true`
    def bind_with_full_env(env, sym, x)
      existing = ident("existing")
      _let(existing, _get_field(env, sym),
           _if(_equal?(existing, Env::UNBOUND),
               bind_form(env, sym, x),
               _if(_not(_equal?(existing, x)),
                   nil,
                   env)))
    end

    def _let(var, val, body)
      Form.new(:let, var, val, body)
    end

    def make_env
      MakeEnvClass.new
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

    def bind_form(env, sym, val)
      Form.new(:bind, env, sym, val)
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

    def might_bind?(pat)
      mb = method(:might_bind?)
      if pat.is_a?(Obj)
        pat.fields.values.any?(&mb)
      elsif pat.is_a?(Or)
        pat.patterns.any?(&mb)
      elsif pat.is_a?(Binder)
        true
      elsif pat.is_a?(Hash)
        pat.values.any?(&mb)
      elsif pat.is_a?(Array)
        pat.any?(&mb)
      elsif pat.is_a?(Strict)
        might_bind?(pat.pat)
      elsif pat.is_a?(Regexp)
        true
      elsif pat.is_a?(Unquote)
        true
      else
        false
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
