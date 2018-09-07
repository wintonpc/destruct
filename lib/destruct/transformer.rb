# frozen_string_literal: true

require 'destructure'
require 'active_support/core_ext/object/deep_dup'

class Destruct
  class Transformer
    LITERAL_TYPES = %i[int sym float str].freeze

    Rule = Struct.new(:pat, :template)

    attr_reader :rules

    def initialize(initial_rules=[])
      @rules = initial_rules
    end

    Identity = Transformer.new

    def self.from(base, &add_rules)
      t = new(base.rules)
      t.instance_exec(&add_rules) if add_rules
      t
    end

    NOTHING = Object.new

    def transform(expr=NOTHING, iters: 0, &pat_proc)
      expr = ExprCache.get(pat_proc) if expr == NOTHING
      if expr.is_a?(Array)
        expr.map { |exp| transform(exp) }
      elsif !expr.is_a?(Parser::AST::Node)
        expr
      else
        rules.each do |rule|
          if e = Compiler.compile(rule.pat).match(expr)
            args = {}
            if e.is_a?(Env)
              e.env_each do |k, v|
                args[k] = transform(v)
              end
            end
            return transform(rule.template.(**args), iters: iters + 1)
          end
        end
        # no rules matched
        iters == 0 ? [:unmatched_expr, expr] : expr
      end
    end

    def add_rule(pat_or_proc, &translate)
      if pat_or_proc.is_a?(Proc)
        node = ExprCache.get(pat_or_proc)
        pat = node_to_pattern(node)
        rules.unshift(Rule.new(pat, translate))
      else
        rules.unshift(Rule.new(pat_or_proc, translate))
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
  end
end
