# frozen_string_literal: true

require_relative '../transformer'
require_relative '../rule_set'
require_relative './helpers'
require 'ast'

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
