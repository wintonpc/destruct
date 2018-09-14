# frozen_string_literal: true

require_relative './ruby'

class Destruct
  module RuleSets
    class PatternBase
      include RuleSet

      def initialize
        add_rule(Ruby::VarRef) { |ref| Var.new(ref.name) }
        add_rule(Ruby::ConstRef) { |ref, binding:| binding.eval(ref.fqn) }
        add_rule_set(Ruby)
      end
    end
  end
end
