# frozen_string_literal: true

require_relative '../transformer'
require_relative '../rule_set'
require_relative './helpers'

class Destruct
  module RuleSets
    class RubyInverse
      include RuleSet

      def initialize
        add_rule(Integer) { |value| n(:int, value) }
        add_rule(Symbol) { |value| n(:sym, value) }
        add_rule(Float) { |value| n(:float, value) }
        add_rule(String) { |value| n(:str, value) }
        add_rule(nil) { n(:nil) }
        add_rule(true) { n(:true) }
        add_rule(false) { n(:false) }
        add_rule(Array) { |items| n(:array, *items) }
        add_rule(Hash) { |h| n(:hash, *h.map { |k, v| n(:pair, transform(k), transform(v)) }) }
        # add_rule(n(:const, [v(:parent), v(:name)]), parent: ConstRef) { |parent:, name:| ConstRef.new([parent&.fqn, name].compact.join("::")) }
        # add_rule(n(:cbase)) { ConstRef.new("") }
      end

      Pair = Struct.new(:k, :v)

      def n(type, *children)
        ::Parser::AST::Node.new(type, children)
      end

      def validate(x)
        AstValidator.validate(x)
      end
    end
  end
end
