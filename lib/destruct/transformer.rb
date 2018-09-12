# frozen_string_literal: true

require 'active_support/core_ext/object/deep_dup'
require 'destruct/types'

class Destruct
  class Transformer
    DEBUG = false
    LITERAL_TYPES = %i[int sym float str].freeze
    class NotApplicable < RuntimeError
    end

    Rule = Struct.new(:pat, :template)
    class Syntax
    end

    def initialize(initial_rules=[])
      @rules = initial_rules
    end

    Identity = Transformer.new

    def self.from(base, &add_rules)
      t = new(base.rules)
      t.instance_exec(&add_rules) if add_rules
      t
    end

    def rules
      @rules.dup
    end

    NOTHING = Object.new

    def transform_pattern_proc(&pat_proc)
      transform(NOTHING, 0, pat_proc.binding, on_unmatched: :ignore, &pat_proc)
    end

    def transform(expr=NOTHING, iters=0, binding=nil, on_unmatched: :raise, &pat_proc)
      if expr == NOTHING
        expr = ExprCache.get(pat_proc)
        binding = pat_proc.binding
      end
      if expr.is_a?(Array)
        expr.map { |exp| transform(exp, iters, binding, on_unmatched: on_unmatched) }
      elsif !expr.is_a?(Parser::AST::Node) && !expr.is_a?(Syntax)
        expr
      else
        @rules.each do |rule|
          begin
            if rule.pat.is_a?(Class) && rule.pat.ancestors.include?(Syntax) && expr.is_a?(rule.pat)
              return transform(apply_template(rule, expr, binding: binding), iters + 1, binding, on_unmatched: on_unmatched)
            elsif e = Compiler.compile(rule.pat).match(expr)
              args = {binding: binding}
              if e.is_a?(Env)
                e.env_each do |k, v|
                  args[k] = transform(v, iters, binding, on_unmatched: on_unmatched)
                end
              end
              return transform(apply_template(rule, **args), iters + 1, binding, on_unmatched: on_unmatched)
            end
          rescue NotApplicable
            # continue to next rule
          end
        end
        # no rules matched
        if on_unmatched == :ignore || iters > 0
          expr
        elsif on_unmatched == :raise
          raise "Invalid pattern: #{Unparser.unparse(expr)}"
        elsif on_unmatched == :tag
          [:unmatched_expr, expr]
        end
      end
    end

    def apply_template(rule, *args, **kws)
      if kws.any?
        if !rule.template.parameters.include?([:key, :binding]) && !rule.template.parameters.include?([:keyreq, :binding])
          kws = kws.dup
          kws.delete(:binding)
        end
        rule.template.(*args, **kws)
      else
        rule.template.(*args)
      end
    end

    def add_rule(pat_or_proc, constraints={}, &translate_block)
      translate =
          if constraints.any?
            proc do |**kws|
              constraints.each_pair do |var, const|
                raise Transformer::NotApplicable unless Array(kws[var]).all? { |p| Array(const).any? { |type| p.is_a?(type) } }
              end
              translate_block.(**kws)
            end
          else
            translate_block
          end
      if pat_or_proc.is_a?(Proc)
        node = ExprCache.get(pat_or_proc)
        pat = node_to_pattern(node)
        @rules.unshift(Rule.new(pat, translate))
      else
        @rules.unshift(Rule.new(pat_or_proc, translate))
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
        puts "successfully matched var #{node}" if DEBUG
        e[:name]
      else
        puts "failed to match var #{node}" if DEBUG
        nil
      end
    end

    def try_read_splat(node)
      cp = Compiler.compile(n(:splat, [any(n(:send, [nil, v(:name)]), n(:lvar, [v(:name)]))]))
      e = cp.match(node)
      if e
        puts "successfully matched splat #{node}" if DEBUG
        e[:name]
      else
        puts "failed to match splat #{node}" if DEBUG
        nil
      end
    end

    def n(type, children=[])
      Obj.new(Parser::AST::Node, type: type, children: children)
    end

    def v(name)
      Var.new(name)
    end

    def s(name)
      Splat.new(name)
    end

    def any(*alt_patterns)
      Or.new(*alt_patterns)
    end
  end
end
