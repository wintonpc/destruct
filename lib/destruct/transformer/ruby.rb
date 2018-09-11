# frozen_string_literal: true

require_relative '../transformer'

class Destruct
  class Transformer
    class VarRef < Syntax
      attr_reader :name

      def initialize(name)
        @name = name
      end
    end

    class ConstRef < Syntax
      attr_reader :fqn

      def initialize(fqn)
        @fqn = fqn
      end
    end

    class Case < Syntax
      attr_reader :value, :whens, :else_body

      def initialize(value, whens, else_body=nil)
        @value = value
        @whens = whens
        @else_body = else_body
      end
    end

    class CaseClause < Syntax
      attr_reader :pred, :body

      def initialize(pred, body)
        @pred = pred
        @body = body
      end
    end

    Ruby = Transformer.from(Identity) do
      add_rule(n(any(:int, :sym, :float, :str), [v(:value)])) { |value:| value }
      add_rule(n(:nil, [])) { nil }
      add_rule(n(:true, [])) { true }
      add_rule(n(:false, [])) { false }
      add_rule(n(:send, [nil, v(:name)])) { |name:| VarRef.new(name) }
      add_rule(n(:const, [nil, v(:name)])) { |name:| ConstRef.new(name.to_s) }
      add_rule(n(:array, v(:items))) { |items:| items }
      add_rule(n(:hash, v(:pairs))) { |pairs:| pairs.to_h }
      add_rule(n(:pair, [v(:k), v(:v)])) { |k:, v:| [k, v] }
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
