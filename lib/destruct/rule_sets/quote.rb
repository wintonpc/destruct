# frozen_string_literal: true

require_relative '../transformer'
require_relative '../rule_set'
require_relative './helpers'
require_relative './ruby_inverse'

class Destruct
  module RuleSets
    class Quote
      include RuleSet

      def initialize
        add_rule(->{ !expr }) do |expr:, binding:|
          value = binding.eval(unparse(expr))
          if value.is_a?(Parser::AST::Node)
            value
          else
            RubyInverse.transform(value)
          end
        end
        add_rule_set(UnpackAst)
      end

      def validate(x)
        AstValidator.validate(x)
      end
    end
  end
end
