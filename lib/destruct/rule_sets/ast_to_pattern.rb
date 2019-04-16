# frozen_string_literal: true

require_relative '../transformer'
require_relative '../rule_set'
require_relative './helpers'

class Destruct
  module RuleSets
    class AstToPattern
      include RuleSet
      include Helpers

      ATOMIC_TYPES = %i[int float sym str const lvar].freeze

      def initialize
        mvar = n(:send, [nil, v(:name)])
        lvar = n(:lvar, [v(:name)])
        add_rule(any(mvar, lvar)) do |name:|
          Var.new(name)
        end
        add_rule(n(:splat, [any(mvar, lvar)])) do |name:|
          Splat.new(name)
        end
        add_rule(Parser::AST::Node) do |node, transform:|
          n(node.type, node.children.map { |c| transform.(c) })
        end
      end
    end
  end
end

module Parser
  module AST
    class Node
      def transformer_eql?(other)
        other.is_a?(Parser::AST::Node) && self.type == other.type &&
            self.children.size == other.children.size &&
            self.children.zip(other.children).all? { |a, b| a.transformer_eql?(b) }
      end
    end
  end
end
