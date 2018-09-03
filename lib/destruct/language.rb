# frozen_string_literal: true

require 'destructure'
require 'active_support/core_ext/object/deep_dup'

class Destruct
  class Language
    LITERAL_TYPES = %i[int sym float str].freeze

    Rule = Struct.new(:pat, :template)
    NIL = Object.new
    NIL.singleton_class.instance_exec { define_method(:inspect) { "NIL" } }

    attr_reader :rules

    def initialize
      @rules = []
      @rules << Rule.new(n(any(:int, :sym, :float, :str), v(:value)), proc { |value:| value })
      @rules << Rule.new(n(:send, nil, v(:name)), proc { |name:| Var.new(name) })
    end

    def translate(expr=nil, &pat_proc)
      expr ||= ExprCache.get(pat_proc)
      return expr unless expr.is_a?(Parser::AST::Node)
      rules.each do |rule|
        if e = Compiler.compile(rule.pat).match(expr)
          args = {}
          e.env_each do |k, v|
            args[k.name] = translate(v)
          end
          return rule.template.(**args)
        end
      end
      NIL
    end

    def add_rule(pat_proc, &translate)
      node = ExprCache.get(pat_proc)
      pat = node_to_pattern(node)
      rules << Rule.new(pat, translate)
    end

    private

    def node_to_pattern(node)
      if !node.is_a?(Parser::AST::Node)
        node
      elsif name = try_read_var(node)
        DMatch::Var.new(name)
      else
        n(node.type, *node.children.map { |c| node_to_pattern(c) })
      end
    end

    def try_read_var(node)
      e = DMatch.match(n(:send, nil, v(:name)), node)
      e[:name] if e
    end

    def n(type, *children)
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
