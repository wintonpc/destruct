# frozen_string_literal: true

require_relative '../transformer'
require_relative '../rule_set'
require_relative './helpers'
require_relative './unpack_ast'

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
        add_rule(Hash) { |h, transform:| n(:hash, *h.map { |k, v| n(:pair, transform.(k), transform.(v)) }) }
        add_rule(Module) { |m| m.name.split("::").map(&:to_sym).reduce(n(:cbase)) { |base, name| n(:const, base, name) } }
        add_rule_set(UnpackAst)
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
