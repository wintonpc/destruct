# frozen_string_literal: true

require_relative './ruby'

class Destruct
  class Transformer
    Destruct = Transformer.from(Identity) do
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
  end
end
