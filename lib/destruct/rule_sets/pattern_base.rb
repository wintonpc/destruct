# frozen_string_literal: true

require_relative './ruby'
require_relative './pattern_validator'

class Destruct
  module RuleSets
    class PatternBase
      include RuleSet

      def initialize
        add_rule(Ruby::VarRef) { |ref| Var.new(ref.name) }
        add_rule(Ruby::ConstRef) { |ref, binding:| binding.eval(ref.fqn) }
        add_rule_set(Ruby)
      end

      def validate(x)
        PatternValidator.validate(x)
      end
    end
  end
end
