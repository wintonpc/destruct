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
        # add_rule(n(:true, [])) { true }
        # add_rule(n(:false, [])) { false }
        # add_rule(n(:array, v(:items))) { |items:| items }
        # add_rule(n(:hash, v(:pairs))) { |pairs:| pairs.to_h }
        # add_rule(n(:pair, [v(:k), v(:v)])) { |k:, v:| [k, v] }
        # add_rule(n(:lvar, [v(:name)])) { |name:| VarRef.new(name) }
        # add_rule(n(:send, [nil, v(:name)])) { |name:| VarRef.new(name) }
        # add_rule(n(:const, [v(:parent), v(:name)]), parent: ConstRef) { |parent:, name:| ConstRef.new([parent&.fqn, name].compact.join("::")) }
        # add_rule(n(:cbase)) { ConstRef.new("") }
      end

      def n(type, *children)
        ::Parser::AST::Node.new(type, children)
      end

      def validate(x)
        AstValidator.validate(x)
      end
    end
  end
end
