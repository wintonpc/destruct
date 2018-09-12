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

    Ruby = Transformer.from(Identity) do
      add_rule(n(any(:int, :sym, :float, :str), [v(:value)])) { |value:| value }
      add_rule(n(:nil, [])) { nil }
      add_rule(n(:true, [])) { true }
      add_rule(n(:false, [])) { false }
      add_rule(n(:array, v(:items))) { |items:| items }
      add_rule(n(:hash, v(:pairs))) { |pairs:| pairs.to_h }
      add_rule(n(:pair, [v(:k), v(:v)])) { |k:, v:| [k, v] }
      add_rule(n(:lvar, [v(:name)])) { |name:| VarRef.new(name) }
      add_rule(n(:send, [nil, v(:name)])) { |name:| VarRef.new(name) }
      add_rule(n(:const, [nil, v(:name)])) { |name:| ConstRef.new(name.to_s) }
    end
  end
end
