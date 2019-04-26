# frozen_string_literal: true

require_relative '../transformer'
require_relative '../rule_set'
require_relative './helpers'
require 'ast'

class Destruct
  module RuleSets
    class UnpackAst
      include RuleSet
      include Helpers

      ATOMIC_TYPES = %i[int float sym str const lvar].freeze

      def initialize
        add_rule(Parser::AST::Node) do |n, transform:|
          raise Transformer::NotApplicable if ATOMIC_TYPES.include?(n.type)
          n.updated(nil, n.children.map(&transform))
        end
      end

      def m(type, *children)
        Parser::AST::Node.new(type, children)
      end
    end
  end
end
