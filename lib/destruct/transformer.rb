# frozen_string_literal: true

require 'active_support/core_ext/object/deep_dup'
require 'destruct/types'
require_relative './compiler'

class Destruct
  class Transformer
    DEBUG = true
    LITERAL_TYPES = %i[int sym float str].freeze
    class NotApplicable < RuntimeError
    end

    Rule = Struct.new(:pat, :template)
    class Syntax
    end

    Code = Struct.new(:code)
    class Code
      def to_s
        "#<Code: #{code}>"
      end
      alias_method :inspect, :to_s
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

    def unparse(x)
      if x.is_a?(Code)
        x.code
      elsif x.is_a?(Parser::AST::Node)
        Unparser.unparse(x)
      elsif x.is_a?(Var)
        x.name.to_s
      else
        x
      end
    end

    NOTHING = Object.new

    def transform_pattern_proc(&pat_proc)
      transform(NOTHING, 0, pat_proc.binding, on_unmatched: :ignore, &pat_proc)
    end

    def transform(expr=NOTHING, iters=0, binding=nil, depth: 0, on_unmatched: :code, &pat_proc)
      if expr == NOTHING
        expr = ExprCache.get(pat_proc)
        binding = pat_proc.binding
      end
      if expr.is_a?(Array)
        expr.map { |exp| transform(exp, iters, binding, depth: depth + 1, on_unmatched: on_unmatched) }
      elsif !expr.is_a?(Parser::AST::Node) && !expr.is_a?(Syntax)
        expr
      else
        @rules.each do |rule|
          begin
            if rule.pat.is_a?(Class) && rule.pat.ancestors.include?(Syntax) && expr.is_a?(rule.pat)
              return log(expr, transform(apply_template(rule, expr, binding: binding), iters + 1, binding, depth: depth, on_unmatched: on_unmatched))
            elsif e = Compiler.compile(rule.pat).match(expr)
              args = {binding: binding}
              if e.is_a?(Env)
                e.env_each do |k, v|
                  val = v == expr ? v : transform(v, iters, binding, depth: depth + 1, on_unmatched: on_unmatched) # don't try to transform if we know we won't get anywhere (prevent stack overflow); template might guard by raising NotApplicable
                  args[k] = val
                end
              end
              return log(expr, transform(apply_template(rule, **args), iters + 1, binding, depth: depth, on_unmatched: on_unmatched))
            end
          rescue NotApplicable
            # continue to next rule
          end
        end
        # no rules matched
        result =
        if on_unmatched == :ignore || iters > 0
          expr
        elsif on_unmatched == :code
          if depth == 0
            raise "Invalid pattern: #{Unparser.unparse(expr)}"
          else
            Code.new(Unparser.unparse(expr))
          end
        elsif on_unmatched == :raise
          raise "Invalid pattern: #{Unparser.unparse(expr)}"
        elsif on_unmatched == :tag
          [:unmatched_expr, expr]
        end
        log(expr, result)
      end
    end

    def log(expr, result)
      puts "TX: #{expr.to_s.gsub("\n", " ")}\n => #{result.to_s.gsub("\n", " ")}" if DEBUG && expr != result
      result
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
                unless as_array(kws[var]).all? { |p| as_array(const).any? { |type| p.is_a?(type) } }
                  raise Transformer::NotApplicable
                end
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

    def as_array(x)
      if x.is_a?(Hash) || x.is_a?(Struct)
        [x]
      else
        Array(x)
      end
    end

    def node_to_pattern(node)
      if !node.is_a?(Parser::AST::Node)
        node
      else
        try_read_var(node) || try_read_splat(node) || try_read_lvasgn(node) ||
            just_node_to_pattern(node)
      end
    end

    def just_node_to_pattern(node)
      n(node.type, node.children.map { |c| node_to_pattern(c) })
    end

    def try_read_var(node)
      cp = Compiler.compile(any(n(:send, [nil, v(:name)]), n(:lvar, [v(:name)])))
      e = cp.match(node)
      if e
        puts "successfully matched var #{node}" if DEBUG
        Var.new(e[:name])
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
        Splat.new(e[:name])
      else
        puts "failed to match splat #{node}" if DEBUG
        nil
      end
    end

    def try_read_lvasgn(node)
      cp = Compiler.compile(n(:lvasgn, [v(:lvar), v(:expr)]))
      e = cp.match(node)
      if e
        puts "successfully matched lvasgn #{node}" if DEBUG
        just_node_to_pattern(node.updated(nil, [Var.new(e[:lvar]), node_to_pattern(e[:expr])]))
      else
        puts "failed to match lvasgn #{node}" if DEBUG
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
