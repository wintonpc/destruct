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
        add_rule(n(:send, [nil, v(:name)])) { |name:| Var.new(name) }
        add_rule(Parser::AST::Node) do |node, transform:|
          n(node.type, node.children.map { |c| transform.(c) })
        end
      end
    end
  end
end
