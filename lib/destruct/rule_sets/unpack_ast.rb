# frozen_string_literal: true

require_relative '../transformer'
require_relative '../rule_set'
require_relative './helpers'

class Destruct
  module RuleSets
    class UnpackAst
      include RuleSet
      include Helpers

      ATOMIC_TYPES = %i[int float sym str const].freeze

      def initialize
        add_rule(Parser::AST::Node) do |n, transform:|
          raise Transformer::NotApplicable if ATOMIC_TYPES.include?(n.type)
          n.updated(nil, n.children.map(&transform))
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
