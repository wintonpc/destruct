# frozen_string_literal: true

require_relative '../transformer'
require_relative '../rule_set'
require_relative './helpers'
require_relative './unpack_ast'

class Destruct
  module RuleSets
    class PatternInverse
      include RuleSet

      def initialize
        add_rule(Var) { |var| n(:lvar, var.name) }
        add_rule_set(RubyInverse)
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
