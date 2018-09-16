# frozen_string_literal: true

require_relative '../transformer'
require_relative '../rule_set'
require_relative './helpers'

class Destruct
  module RuleSets
    class UnpackAst
      include RuleSet
      include Helpers

      ATOMIC_TYPES = %i[int float sym str const lvar].freeze

      def initialize
        # add_rule(n(:send, [nil, v(:meth), s(:args)])) do |raw_meth:, args:|
        #   m(:send, nil, raw_meth, *args)
        # end
        # add_rule(n(:send, [v(:recv), v(:meth), s(:args)])) do |recv:, raw_meth:, raw_args:, transform:|
        #   m(:send, recv, raw_meth, *raw_args.map { |a| transform.(a) })
        # end
        # add_rule(n(any(:int, :float, :sym, :str, :lvar), any)) do
        #   raise Transformer::Accept
        # end
        # add_rule(n(:array, v(:items))) do |raw_items:, transform:|
        #   m(:array, *raw_items.map(&transform))
        # end
        # add_rule(n(:hash, v(:pairs))) do |raw_pairs:, transform:|
        #   m(:hash, *raw_pairs.map { |p| p.updated(nil, p.children.map { |c| transform.(c) }) })
        # end
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
