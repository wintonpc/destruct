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
        add_rule_set(RubyInverse)
        add_rule(->{ !expr }) { |expr:, binding:| binding.eval(unparse(expr)) }
      end

      def validate(x)
        AstValidator.validate(x)
      end
    end
  end
end
