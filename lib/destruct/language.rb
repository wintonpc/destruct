# frozen_string_literal: true

require 'destructure'
require 'active_support/core_ext/object/deep_dup'

class Destruct
  class Language
    LITERAL_TYPES = %i[int sym float str].freeze

    Rule = Struct.new(:pat, :template)

    attr_reader :rules

    def initialize(initial_rules=[])
      @rules = initial_rules
    end

    def self.from(base, &add_rules)
      lang = new(base.rules)
      lang.instance_exec(&add_rules) if add_rules
      lang
    end

    def translate(expr=nil, &pat_proc)
      expr ||= ExprCache.get(pat_proc)
      if expr.is_a?(Array)
        expr.map { |exp| translate(exp) }
      elsif !expr.is_a?(Parser::AST::Node)
        expr
      else
        rules.each do |rule|
          if e = Compiler.compile(rule.pat).match(expr)
            args = {}
            if e.is_a?(Env)
              e.env_each do |k, v|
                args[k] = translate(v)
              end
            end
            return rule.template.(**args)
          end
        end
        [:unmatched_expr, expr]
      end
    end

    def add_rule(pat_or_proc, &translate)
      if pat_or_proc.is_a?(Proc)
        node = ExprCache.get(pat_or_proc)
        pat = node_to_pattern(node)
        rules << Rule.new(pat, translate)
      else
        rules << Rule.new(pat_or_proc, translate)
      end
    end

    private

    def node_to_pattern(node)
      if !node.is_a?(Parser::AST::Node)
        node
      elsif name = try_read_var(node)
        Var.new(name)
      elsif name = try_read_splat(node)
        Splat.new(name)
      else
        n(node.type, node.children.map { |c| node_to_pattern(c) })
      end
    end

    def try_read_var(node)
      cp = Compiler.compile(any(n(:send, [nil, v(:name)]), n(:lvar, [v(:name)])))
      e = cp.match(node)
      if e
        puts "successfully matched var #{node}"
        e[:name]
      else
        puts "failed to match var #{node}"
        nil
      end
    end

    def try_read_splat(node)
      cp = Compiler.compile(n(:splat, [any(n(:send, [nil, v(:name)]), n(:lvar, [v(:name)]))]))
      e = cp.match(node)
      if e
        puts "successfully matched splat #{node}"
        e[:name]
      else
        puts "failed to match splat #{node}"
        nil
      end
    end

    def n(type, children)
      Obj.new(Parser::AST::Node, type: type, children: children)
    end

    def v(name)
      Var.new(name)
    end

    def any(*alt_patterns)
      Or.new(*alt_patterns)
    end

    Identity = Language.new
    Basic = Language.from(Identity) do
      add_rule(n(any(:int, :sym, :float, :str), [v(:value)])) { |value:| value }
      add_rule(n(:nil, [])) { nil }
      add_rule(n(:true, [])) { true }
      add_rule(n(:false, [])) { false }
      add_rule(n(:send, [nil, v(:name)])) { |name:| Var.new(name) }
      add_rule(n(:array, v(:items))) { |items:| items }
      add_rule(n(:hash, v(:pairs))) { |pairs:| pairs.to_h }
      add_rule(n(:pair, [v(:k), v(:v)])) { |k:, v:| [k, v] }
    end
  end
end
