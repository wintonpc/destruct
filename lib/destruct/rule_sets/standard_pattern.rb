# frozen_string_literal: true

require_relative '../transformer'
require_relative '../rule_set'

class Destruct
  module RuleSets
    class StandardPattern
      include RuleSet
      include Helpers

      def initialize
        add_rule(n(:send, [v(:a), :|, v(:b)])) { |a:, b:| Or.new(a, b) }
        add_rule_set(PatternBase)
      end

      def validate(x)
        PatternValidator.validate(x)
      end
    end
  end
end
