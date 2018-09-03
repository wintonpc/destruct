# frozen_string_literal: true

require 'destructure'
require 'active_support/core_ext/object/deep_dup'

class Destruct
  class Language
    LITERAL_TYPES = %i[int sym float str].freeze

    Rule = Struct.new(:pat, :template)
    NIL = Object.new
    NIL.singleton_class.instance_exec { define_method(:inspect) { "NIL" }; define_method(:to_s) { "NIL" } }

    attr_reader :rules

    def initialize
      @rules = []
      @rules << Rule.new(n(any(:int, :sym, :float, :str), [v(:value)]), proc { |value:| value })
      @rules << Rule.new(n(:nil, []), proc { nil })
      @rules << Rule.new(n(:true, []), proc { true })
      @rules << Rule.new(n(:false, []), proc { false })
      @rules << Rule.new(n(:send, [nil, v(:name)]), proc { |name:| Var.new(name) })
      @rules << Rule.new(n(:array, v(:items)), proc { |items:| items })
      @rules << Rule.new(n(:hash, v(:pairs)), proc { |pairs:| pairs.to_h })
      @rules << Rule.new(n(:pair, [v(:k), v(:v)]), proc { |k:, v:| [k, v] })
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
                args[k.name] = translate(v)
              end
            end
            return rule.template.(**args)
          end
        end
        NIL
      end
    end

    def add_rule(pat_or_proc, &translate)
      if pat_or_proc.is_a?(Parser::AST::Node)
        rules << Rule.new(pat_or_proc, translate)
      else
        node = ExprCache.get(pat_or_proc)
        pat = node_to_pattern(node)
        rules << Rule.new(pat, translate)
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
