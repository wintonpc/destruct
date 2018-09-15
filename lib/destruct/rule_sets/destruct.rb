# frozen_string_literal: true

require_relative '../transformer'

class Destruct
  module RuleSets
    class Destruct
      include RuleSet
      include Helpers

      def initialize
        add_rule(n(:case, [v(:value), s(:clauses)])) do |value:, clauses:|
          *whens, last = clauses
          if last.is_a?(CaseClause)
            Case.new(value, clauses)
          else
            Case.new(value, whens, last)
          end
        end
        add_rule(n(:when, [v(:pred), v(:body)])) { |pred:, body:| CaseClause.new(pred, body) }
      end

      class Case
        attr_reader :value, :whens, :else_body

        def initialize(value, whens, else_body=nil)
          @value = value
          @whens = whens
          @else_body = else_body
        end
      end

      class CaseClause
        attr_reader :pred, :body

        def initialize(pred, body)
          @pred = pred
          @body = body
        end
      end
    end
  end
end
