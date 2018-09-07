require_relative './transformer'

class Destruct
  class Transformer
    Basic = Transformer.from(Identity) do
      add_rule(n(any(:int, :sym, :float, :str), [v(:value)])) { |value:| value }
      add_rule(n(:nil, [])) { nil }
      add_rule(n(:true, [])) { true }
      add_rule(n(:false, [])) { false }
      add_rule(n(:send, [nil, v(:name)])) { |name:| Var.new(name) }
      add_rule(n(:array, v(:items))) { |items:| items }
      add_rule(n(:hash, v(:pairs))) { |pairs:| pairs.to_h }
      add_rule(n(:pair, [v(:k), v(:v)])) { |k:, v:| [k, v] }
    end
  end
end
